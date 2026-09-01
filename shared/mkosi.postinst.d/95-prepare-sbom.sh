#!/usr/bin/env bash
# Record package metadata before it's removed by CleanPackageMetadata
set -euo pipefail
shopt -s nullglob

stage="${OUTPUTDIR:?}/.sbom-root"

# Copy dpkg metadata
mkdir -p "$stage/var/lib/dpkg" "$stage/etc" "$stage/usr/lib/sbom"
cp "${BUILDROOT:?}/var/lib/dpkg/status" "$stage/var/lib/dpkg/status"
cp -L "$BUILDROOT/etc/os-release" "$stage/etc/os-release"
if [[ -d "$BUILDROOT/usr/share/doc" ]]; then
  (cd "$BUILDROOT" && find usr/share/doc -maxdepth 2 -name copyright \
    -exec cp --parents -t "$stage" {} +)
fi

# Create SBOM metadata for deb packages installed manually
debroot=$(mktemp -d "${PACKAGEDIR:?}/.sbom.XXXXXX")
trap 'rm -r "$debroot"' EXIT
for deb in "${PACKAGEDIR:?}"/*.deb; do
  package=$(dpkg-deb -f "$deb" Package)
  if [[ $(dpkg-query --admindir="$stage/var/lib/dpkg" -W -f='${Status} ${Version}' \
    "$package" 2>/dev/null) == "install ok installed $(dpkg-deb -f "$deb" Version)" ]]; then
    ln "$deb" "$debroot/"
    sed -i "/^Package: $package$/,/^$/d" "$stage/var/lib/dpkg/status"
  fi
done
SYFT_CHECK_FOR_APP_UPDATE=false SYFT_FILE_METADATA_SELECTION=none \
  syft -q scan "dir:$debroot" --override-default-catalogers deb-archive-cataloger \
    -o syft-json >"$stage/usr/lib/sbom/local-debs.syft.json"
SYFT_CHECK_FOR_APP_UPDATE=false SYFT_FILE_METADATA_SELECTION=none \
  syft -q scan "dir:$BUILDROOT" --override-default-catalogers \
    go-module-binary-cataloger,cargo-auditable-binary-cataloger \
    -o syft-json >"$stage/usr/lib/sbom/binaries.syft.json"

# Add metadata for packages installed from source
if [[ -d "${ARTIFACTDIR:?}/sbom" ]]; then
  cp -r "$ARTIFACTDIR/sbom/." "$stage/usr/lib/sbom"
fi

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

#
# - record the SHA-256 and URL of each installed .deb, one line per package:
#   package, version, architecture, SHA-256, URL (empty for local packages)
#
# - installed packages are 'ii' or 'hi' (held); syft lists both
#
# - binary:Package adds ':ARCH' where the name alone is ambiguous (multi-arch)
#
# - apt-get prints: 'URL' PACKAGE_VERSION_ARCH.deb SIZE ALGORITHM:HASH
#
dpkg-query --admindir="$BUILDROOT/var/lib/dpkg" -W -f='${db:Status-Abbrev}${binary:Package}=${Version}\n' |
  sed -n 's/^[hi]i *//p' |
  xargs -r apt-get download --print-uris -qq |
  while read -r url file _ hash; do
    url=${url#\'} url=${url%\'}
    IFS=_ read -r package version arch <<<"${file%.deb}"
    if [[ $url == file:* ]]; then
      # mkosi's local repository (mkosi.packages, build scripts) is not signed: hash the file
      path=${url#file:}
      hash=$(sha256sum "$(printf '%b' "${path//%/\\x}")" | cut -d' ' -f1)
      url=
    elif [[ $hash == SHA256:* ]]; then
      # From the signed repository index
      hash=${hash#SHA256:}
    else
      hash=
    fi
    if [[ -z $hash || -z $arch ]]; then
      echo "no SHA-256 for this .deb: $url $file" >&2
      exit 1
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$package" "${version//%3a/:}" "$arch" "$hash" "$url"
  done >"$OUTPUTDIR/.sbom-debs.tsv"

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
# Go and Rust binaries are catalogued by mkosi.finalize.d/95-prepare-sbom-binaries.sh

# Add metadata for packages installed from source
if [[ -d "${ARTIFACTDIR:?}/sbom" ]]; then
  cp -r "$ARTIFACTDIR/sbom/." "$stage/usr/lib/sbom"
fi

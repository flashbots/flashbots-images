#!/usr/bin/env bash

#
# catalog go and rust binaries with their SHA-256
#
# this runs after the other finalise scripts, so the hashes match the files in
# the image
#
set -euo pipefail

#
# - syft-json gives the packages to 95-gen-sbom.sh, but that import drops the
#   file digests
#
# - therefore, we also keep the cyclonedx file components (one per binary), with
#   the paths relative to the image root
#
SYFT_CHECK_FOR_APP_UPDATE=false \
SYFT_FILE_METADATA_SELECTION=owned-by-package \
SYFT_FILE_METADATA_DIGESTS=sha256 \
  syft -q scan "dir:${BUILDROOT:?}" --override-default-catalogers \
    go-module-binary-cataloger,cargo-auditable-binary-cataloger \
    -o syft-json="${OUTPUTDIR:?}/.sbom-root/usr/lib/sbom/binaries.syft.json" \
    -o cyclonedx-json |
  jq --arg root "$BUILDROOT" '
    [.components[] | select(.type == "file") | .name |= ltrimstr($root)]' \
    >"$OUTPUTDIR/.sbom-files.json"

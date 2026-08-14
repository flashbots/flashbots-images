#!/usr/bin/env bash
set -euo pipefail

root="$OUTPUTDIR/.sbom-root"
sbom="$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}.sbom.cdx.json"

export SYFT_CHECK_FOR_APP_UPDATE=false
export SYFT_FILE_METADATA_SELECTION=none
syft scan "dir:$root" \
  --select-catalogers +sbom-cataloger \
  --source-name "$IMAGE_ID" \
  --source-version "$IMAGE_VERSION" \
  -o cyclonedx-json |
  jq 'del(.serialNumber) | del(.components[].properties[] | select(.name == "syft:cpe23")) | .metadata.timestamp = "1970-01-01T00:00:00Z" | .metadata.component += {"bom-ref":"root", "type":"operating-system"}' \
    >"$sbom"

rm -r "$root"

#!/usr/bin/env bash
set -euo pipefail

root="$OUTPUTDIR/.sbom-root"
out="$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}"

# Bind the SBOM to the primary image artifact
image="$out.efi"
[[ -f "$out.raw" ]] && image="$out.raw"
sha=$(sha256sum "$image" | cut -d' ' -f1)

export SYFT_CHECK_FOR_APP_UPDATE=false
export SYFT_FILE_METADATA_SELECTION=none
syft scan "dir:$root" \
  --select-catalogers +sbom-cataloger \
  --source-name "$IMAGE_ID" \
  --source-version "$IMAGE_VERSION" \
  -o cyclonedx-json |
  jq --arg file "${image##*/}" --arg sha "$sha" '
    # actions/attest requires serialNumber; derive a UUIDv8 from the image hash to stay reproducible
    def hexval: . as $c | "0123456789abcdef" | index($c);
    .serialNumber = "urn:uuid:\($sha[0:8])-\($sha[8:12])-8\($sha[13:16])-\(["8","9","a","b"][($sha[16:17] | hexval) % 4])\($sha[17:20])-\($sha[20:32])"
    | del(.components[].properties[]? | select(.name == "syft:cpe23"))
    | .metadata.timestamp = "1970-01-01T00:00:00Z"
    | .metadata.component += {
        "bom-ref": "root", "type": "operating-system",
        hashes: [{alg: "SHA-256", content: $sha}],
        properties: [{name: "sbom:image-file", value: $file}]}' \
    >"$out.sbom.cdx.json"

rm -r "$root"

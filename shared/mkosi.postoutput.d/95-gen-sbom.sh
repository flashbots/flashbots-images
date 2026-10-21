#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

root="$OUTPUTDIR/.sbom-root"
out="$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}"

# Bind the SBOM to the primary image artifact
image="$out.efi"
[[ -f "$out.raw" ]] && image="$out.raw"
sha=$(sha256sum "$image" | cut -d' ' -f1)

crates="$root/git-crates.jsonl"
: > "$crates"
for lock in "$root/usr/lib/sbom/"*.cargo-lock.toml; do
  dasel -i toml -o json < "$lock" |
    jq -c '.package[] | {name, version, source}' >> "$crates"
done

export SYFT_CHECK_FOR_APP_UPDATE=false
export SYFT_FILE_METADATA_SELECTION=none
syft scan "dir:$root" \
  --select-catalogers +sbom-cataloger \
  --source-name "$IMAGE_ID" \
  --source-version "$IMAGE_VERSION" \
  -o cyclonedx-json |
  jq --arg file "${image##*/}" --arg sha "$sha" --slurpfile crates "$crates" \
    -f "$SRCDIR/scripts/sbom.jq" \
    >"$out.sbom.cdx.json"

rm -r "$root"

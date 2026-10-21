#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

root="$OUTPUTDIR/.sbom-root"
sbom_dir="$root/usr/lib/sbom"
out="$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}"

# Bind the SBOM to the primary image artifact
image="$out.efi"
[[ -f "$out.raw" ]] && image="$out.raw"
sha=$(sha256sum "$image" | cut -d' ' -f1)

# The SBOM cannot tell apart the same name@version from different sources: warn and leave those out.
crates=$(mktemp)
cat "$sbom_dir"/*.crates.jsonl /dev/null | jq -s 'group_by("\(.name)@\(.version)") | map(
  (map(select(.sha256_verified != false)) | if length > 0 then . else null end) as $verified
  | {key: "\(.[0].name)@\(.[0].version)", candidates: ($verified // . | unique_by({source, repo, commit}))})' >"$crates"
jq -r '.[] | select(.candidates | length > 1)
  | "WARNING: \(.key) has more than one source, its sources are left out of the SBOM"' "$crates" >&2

export SYFT_CHECK_FOR_APP_UPDATE=false
export SYFT_FILE_METADATA_SELECTION=none
syft scan "dir:$root" \
  --select-catalogers +sbom-cataloger \
  --source-name "$IMAGE_ID" \
  --source-version "$IMAGE_VERSION" \
  -o cyclonedx-json |
  jq --arg file "${image##*/}" --arg sha "$sha" \
    --slurpfile notes "$sbom_dir/package-notes.syft.json" \
    --slurpfile crates "$crates" '
    # actions/attest requires serialNumber; derive a UUIDv8 from the image hash to stay reproducible
    def hexval: . as $c | "0123456789abcdef" | index($c);

    # Packages built from git: repo/commit from their ELF package note (scripts/package_note.sh),
    # which syft drops when writing CycloneDX
    def vcs_from_note: .purl as $purl
      | first($notes[0].artifacts[] | select(.purl == $purl)) | {repo: .metadata.sourceRepo, commit: .metadata.commit};
    def add_vcs($v):
      .externalReferences += [{type: "vcs", url: $v.repo}]
      | .pedigree.commits = [{uid: $v.commit}];

    # Rust crates: sbom:source says where repo/commit come from (crates.io publisher or a Cargo.lock pin)
    def add_crate_info($c):
      (if $c.sha256 then .hashes = [{alg: "SHA-256", content: $c.sha256}] else . end)
      | (if $c.repo then .externalReferences += [{type: "vcs", url: $c.repo}] else . end)
      | (if $c.commit then .pedigree.commits = [{uid: $c.commit}] else . end)
      | .properties += [
          {name: "sbom:source", value: $c.source},
          {name: "sbom:sha256-verified", value: ($c.sha256_verified | if . == null then null else tostring end)},
          {name: "sbom:vcs-ref", value: $c.ref},
          {name: "sbom:path-in-vcs", value: $c.path_in_vcs},
          {name: "sbom:vcs-dirty", value: (if $c.dirty then "true" else null end)}
          | select(.value != null)];

    .serialNumber = "urn:uuid:\($sha[0:8])-\($sha[8:12])-8\($sha[13:16])-\(["8","9","a","b"][($sha[16:17] | hexval) % 4])\($sha[17:20])-\($sha[20:32])"
    | del(.components[].properties[]? | select(.name == "syft:cpe23"))
    | ($crates[0] | map(select(.candidates | length == 1) | {key, value: .candidates[0]}) | from_entries) as $crate_info
    | .components[] |= (
        if (.purl // "" | startswith("pkg:cargo/")) then
          $crate_info["\(.name)@\(.version)"] as $c | if $c then add_crate_info($c) else . end
        else
          (vcs_from_note // null) as $v | if $v then add_vcs($v) else . end
        end)
    | .metadata.timestamp = "1970-01-01T00:00:00Z"
    | .metadata.component += {
        "bom-ref": "root", "type": "operating-system",
        hashes: [{alg: "SHA-256", content: $sha}],
        properties: [{name: "sbom:image-file", value: $file}]}' \
    >"$out.sbom.cdx.json"

rm -r "$root" "$crates"

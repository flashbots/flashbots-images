#!/usr/bin/env bash
# Convert the mkosi JSON manifest into a Debian-packages-only CycloneDX 1.6
# Output is byte-deterministic: fixed key order, sorted components, timestamp
# from SOURCE_DATE_EPOCH
#
#   SBOM_LOCAL_PACKAGES   comma-separated name globs of packages that do NOT
#                         come from the Debian archive (locally built debs)
#   SBOM_LOCAL_NAMESPACE  purl namespace for those packages (default: local)

set -euo pipefail
shopt -s nullglob

cd "${OUTPUTDIR:?}"

manifests=()
for f in *.manifest; do
    [[ -f "$f" && ! -L "$f" ]] && manifests+=("$f")
done
if [[ ${#manifests[@]} -ne 1 ]]; then
    echo "deb-sbom: expected exactly one *.manifest in $PWD, found ${#manifests[@]}" >&2
    exit 1
fi
manifest=${manifests[0]}
stem=${manifest%.manifest}
sbom="$stem.debian-packages.cdx.json"

# The .efi the manifest describes (matches Format=uki in shared/mkosi.conf);
# hash it into the SBOM so the document is bound to the artifact.
manifest_sha=$(sha256sum "$manifest" | cut -d' ' -f1)
efi_sha=""
if [[ -f "$stem.efi" && ! -L "$stem.efi" ]]; then
    efi_sha=$(sha256sum "$stem.efi" | cut -d' ' -f1)
else
    echo "deb-sbom: no $stem.efi found, SBOM will carry no image hash" >&2
fi

jq --arg name "${IMAGE_ID:-$stem}" \
   --arg version "${IMAGE_VERSION:-unknown}" \
   --arg release "${RELEASE:-debian}" \
   --arg manifest_sha "$manifest_sha" \
   --arg efi_sha "$efi_sha" \
   --arg local_globs "${SBOM_LOCAL_PACKAGES:-}" \
   --arg local_ns "${SBOM_LOCAL_NAMESPACE:-local}" \
   --argjson epoch "${SOURCE_DATE_EPOCH:-0}" '

def glob_to_regex: "^" + (gsub("(?<c>[.+])"; "\\\(.c)") | gsub("\\*"; ".*")) + "$";

($local_globs | split(",") | map(select(length > 0) | glob_to_regex)) as $globs
# release codename -> syft/grype-style purl qualifier, e.g. trixie -> debian-13
| ({bullseye: "11", bookworm: "12", trixie: "13", forky: "14"}[$release]
   | if . then "debian-\(.)" else $release end) as $distro
| [ .packages[]
    | select(.type == "deb")
    | if (.name | type) != "string" or (.version | type) != "string"
         or (.architecture | type) != "string"
      then error("deb package entry missing name/version/architecture: \(tojson)")
      else . end
    | . as $p
    | any($globs[]; . as $re | $p.name | test($re)) as $local
    | (if $local then $local_ns else "debian" end) as $group
    # @uri percent-encodes ":" and "+" in versions, as purl requires
    | ("pkg:deb/\($group | @uri)/\($p.name | @uri)@\($p.version | @uri)"
       + "?arch=\($p.architecture | @uri)"
       + (if $local then "" else "&distro=\($distro | @uri)" end)) as $purl
    | { type: "library",
        "bom-ref": $purl,
        group: $group,
        name: $p.name,
        version: $p.version,
        purl: $purl,
        properties: ([ {name: "mkosi:package-type", value: "deb"},
                       {name: "debian:architecture", value: $p.architecture} ]
                     + if $local
                       then [{name: "sbom:package-origin", value: $local_ns}]
                       else [] end) }
  ] as $components
| if $components == [] then error("manifest contains no packages with type=deb") else . end
| { bomFormat: "CycloneDX",
    specVersion: "1.6",
    version: 1,
    metadata: {
      timestamp: ($epoch | todate),
      tools: {components: [{type: "application", name: "mkosi-manifest-to-cyclonedx", version: "3"}]},
      component: ({ type: "operating-system",
                    "bom-ref": "root",
                    name: $name,
                    version: $version,
                    properties: [
                      {name: "sbom:scope", value: "debian-packages-only"},
                      {name: "mkosi:manifest-sha256", value: $manifest_sha},
                      {name: "debian:release", value: $release} ] }
                  + if $efi_sha == "" then {}
                    else {hashes: [{alg: "SHA-256", content: $efi_sha}]} end)
    },
    components: ($components | sort_by(.name, .version, .purl)),
    compositions: [{aggregate: "incomplete", assemblies: ["root"]}] }

' "$manifest" > "$sbom"

echo "deb-sbom: wrote $sbom ($(jq '.components | length' "$sbom") packages)" >&2

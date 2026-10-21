def add_vcs($vcs):
  .externalReferences += [{type: "vcs", url: $vcs.repo}]
  | .pedigree.commits += [{uid: $vcs.commit}];

def add_application_sources:
  .components[] |= (
    ((.purl // "" | capture("[?&]vcs_url=(?<url>[^&#]+)").url | @urid
      | capture("^git\\+(?<repo>.+)@(?<commit>[0-9a-f]+)$")) // null) as $vcs
    | if $vcs then add_vcs($vcs) else . end);

def add_git_dependency_sources($crates):
  ($crates | unique_by([.name, .version, .source]) | group_by([.name, .version])
    | map(select(length == 1) | .[0] | {key: "\(.name)@\(.version)", value: .source})
    | from_entries) as $sources
  | .components[] |= (
      (if (.purl // "" | startswith("pkg:cargo/")) then
         $sources["\(.name)@\(.version)"] else null end) as $source
      | if ($source // "" | startswith("git+")) then
          ($source | capture("^git\\+(?<repo>[^?#]+)(?:\\?[^#]*)?#(?<commit>[0-9a-f]+)$")
            // error("Unexpected Cargo git source: \($source)")) as $vcs
          | add_vcs($vcs)
        else . end);

def normalize_metadata:
  del(.components[].properties[]? | select(.name == "syft:cpe23"))
  | .metadata.timestamp = "1970-01-01T00:00:00Z";

def bind_image($file; $sha):
  # Derive the required attestation UUID from the image hash for reproducibility
  def hexval: . as $c | "0123456789abcdef" | index($c);
  .serialNumber = "urn:uuid:\($sha[0:8])-\($sha[8:12])-8\($sha[13:16])-\(["8","9","a","b"][($sha[16:17] | hexval) % 4])\($sha[17:20])-\($sha[20:32])"
  | .metadata.component += {
      "bom-ref": "root", "type": "operating-system",
      hashes: [{alg: "SHA-256", content: $sha}],
      properties: [{name: "sbom:image-file", value: $file}]};

normalize_metadata
| add_application_sources
| add_git_dependency_sources($crates)
| bind_image($file; $sha)

#!/usr/bin/env bash

CRATES_IO="registry+https://github.com/rust-lang/crates.io-index"

# Print each package in a Cargo.lock as a JSON line
cargo_lock_entries() {
    local dir=$( mktemp -d )
    cp "$1" "$dir/Cargo.lock" # syft only works with directories
    SYFT_CHECK_FOR_APP_UPDATE=false SYFT_FILE_METADATA_SELECTION=none \
        syft -q scan "dir:$dir" --override-default-catalogers rust-cargo-lock-cataloger -o syft-json |
        jq -c '.artifacts[].metadata'
    rm -r "$dir"
}

# git dependencies: repo and commit as pinned in Cargo.lock
git_crate_sources() {
    local lock_entries="$1"

    # git+<repo>?<rev|branch|tag>=<ref>#<commit>
    jq -c 'select(.source | startswith("git+"))
        | (.source | capture("^git\\+(?<repo>[^?#]+)(\\?(?<ref>[^#]*))?#(?<commit>[0-9a-f]+)$")
            // error("unexpected git source in Cargo.lock: \(.source)")) as $git
        | {source: "cargo-lock-pinned", name, version, repo: $git.repo, ref: $git.ref, commit: $git.commit}
        | with_entries(select(.value != null and .value != ""))' "$lock_entries"
}

# Workspace crates: built from the package's own clone
workspace_crate_sources() {
    local lock_entries="$1"
    local metadata="$2"
    local package="$3"
    local repo="$4"
    local commit="$5"

    jq -c --slurpfile metadata "$metadata" --arg root "/build/$package/" --arg repo "$repo" --arg commit "$commit" '
        ($metadata[0].packages | map(select(.source == null)
            | {key: "\(.name)@\(.version)", value: .manifest_path | ltrimstr($root) | rtrimstr("Cargo.toml") | rtrimstr("/")})
            | from_entries) as $paths
        | select(.source == "")
        | {source: "built-from-workspace", name, version, repo: $repo, commit: $commit, path_in_vcs: $paths["\(.name)@\(.version)"]}
        | with_entries(select(.value != null and .value != ""))' "$lock_entries"
}

# crates.io crates: the crate archive must match the Cargo.lock sha256
crates_io_crate_sources() {
    local lock_entries="$1"
    local metadata="$2"

    local manifest=$( jq -r --arg crates_io "$CRATES_IO" \
        'first(.packages[] | select(.source == $crates_io) | .manifest_path) // empty' "$metadata" )
    [ -n "$manifest" ] || return 0
    # <cargo home>/registry/src/<index>/<crate>/Cargo.toml -> <cargo home>/registry/src/<index>
    local src_dir=$( dirname "$( dirname "$manifest" )" )
    local cache_dir="$BUILDROOT${src_dir/\/registry\/src\//\/registry\/cache\/}"

    local repos=$( mktemp )
    jq --arg crates_io "$CRATES_IO" '[.packages[] | select(.source == $crates_io)
        | {key: "\(.name)@\(.version)", value: (.repository // "")}] | from_entries' "$metadata" > "$repos"

    jq -r --arg crates_io "$CRATES_IO" 'select(.source == $crates_io) | [.name, .version, .checksum] | @tsv' "$lock_entries" |
        while IFS=$'\t' read -r name version checksum; do
            local archive="$cache_dir/$name-$version.crate"
            if [ ! -f "$archive" ]; then
                jq -cn --arg name "$name" --arg version "$version" --arg sha256 "$checksum" \
                    '{source: "crates.io-publisher-claim", name: $name, version: $version, sha256: $sha256, sha256_verified: false}'
                continue
            fi

            if [ "$( sha256sum "$archive" | cut -d' ' -f1 )" != "$checksum" ]; then
                echo "ERROR: $archive does not match the Cargo.lock checksum" >&2
                exit 1
            fi

            local repo
            if jq -e --arg id "$name@$version" 'has($id)' "$repos" > /dev/null; then
                repo=$( jq -r --arg id "$name@$version" '.[$id]' "$repos" )
            else
                # enabled only by build features, which cargo metadata does not know
                repo=$( mkosi-chroot cargo metadata --format-version 1 --no-deps --offline \
                    --manifest-path "$src_dir/$name-$version/Cargo.toml" | jq -r '.packages[0].repository // ""' )
            fi

            local vcs_info=$( tar -xzOf "$archive" "$name-$version/.cargo_vcs_info.json" 2>/dev/null || echo '{}' )

            jq -cn --arg name "$name" --arg version "$version" --arg sha256 "$checksum" \
                --arg repo "$repo" --argjson vcs_info "$vcs_info" '
                {
                    source: "crates.io-publisher-claim",
                    name: $name,
                    version: $version,
                    sha256: $sha256,
                    sha256_verified: true,
                    repo: $repo,
                    commit: $vcs_info.git.sha1,
                    path_in_vcs: $vcs_info.path_in_vcs,
                    dirty: $vcs_info.git.dirty
                }
                | with_entries(select(.value != null and .value != "" and .value != false))'
        done

    rm "$repos"
}

# Write one JSON line per crate in the package's Cargo.lock to $out, with where its source comes from.
record_crate_sources() (
    set +x
    local package="$1"
    local source_url="$2"
    local commit="$3"
    local out="$4"

    local lock_entries=$( mktemp )
    cargo_lock_entries "$BUILDROOT/build/$package/Cargo.lock" > "$lock_entries"

    # cargo resolves this platform's crates from the sources it already fetched, and tells where they are
    local metadata=$( mktemp )
    mkosi-chroot bash -c "cd '/build/$package' && cargo metadata --format-version 1 --locked --offline \
        --filter-platform \"\$(rustc -vV | sed -n 's/^host: //p')\"" > "$metadata"

    git_crate_sources "$lock_entries" > "$out"
    workspace_crate_sources "$lock_entries" "$metadata" "$package" "$source_url" "$commit" >> "$out"
    crates_io_crate_sources "$lock_entries" "$metadata" >> "$out"

    echo "$package: $( jq -s 'map(select(.sha256_verified == false)) | length' "$out" ) crates.io crates without an archive, sha256 not verified" >&2

    rm "$metadata" "$lock_entries"
)

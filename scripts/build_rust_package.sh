#!/usr/bin/env bash

source scripts/package_note.sh
source scripts/crate_sources.sh

build_rust_package() {
    local package="$1"
    local version="$2"
    local git_url="$3"
    local provided_binary="${4:-}"
    local extra_features="${5:-}"
    local extra_rustflags="${6:-}"
    local cargo_package="${7:-$package}"

    local dest_path="$DESTDIR/usr/bin/$package"
    mkdir -p "$DESTDIR/usr/bin"

    # If binary path is provided, use it directly
    if [ -n "$provided_binary" ]; then
        echo "Using provided binary for $package"
        cp "$provided_binary" "$dest_path"
        return
    fi

    # Clone the repository
    local build_dir="$BUILDROOT/build/$package"
    local source_url=$git_url
    mkdir -p "$build_dir"
    set +x # don't leak github token into logs
    echo "Cloning ${git_url}"
    if [ -f "$BUILDDIR/.ghtoken" ]; then
        git_url="${git_url/#https:\/\/github.com/https:\/\/x-access-token:$(cat "$BUILDDIR/.ghtoken")@github.com}"
    fi
    git clone --depth 1 --branch "$version" "$git_url" "$build_dir" || (
        echo "Could not clone branch/tag, attempting to checkout the commit by sha"
        git clone "$git_url" "$build_dir" &&
        git -C "$build_dir" checkout "$version"
    )
    set -x

    # Get the git reference
    local git_describe=$( git -C "$build_dir" describe --always --long --tags )
    printf "${git_describe#$package/}" > "$BUILDDIR/$package.git"

    local commit=$( git -C "$build_dir" rev-parse HEAD )

    # If binary is cached, skip compilation
    if [ -n "${extra_features}" ]; then
        local cached_binary="$BUILDDIR/${package}-${git_describe#${package}/}-${extra_features}/${package}"
    else
        local cached_binary="$BUILDDIR/${package}-${git_describe#${package}/}/${package}"
    fi
    local cached_binary="${cached_binary//,/-}"
    local cached_crates="$( dirname "$cached_binary" )/crates.jsonl"
    local sbom_crates="${ARTIFACTDIR:?}/sbom/$package.crates.jsonl"
    mkdir -p "$ARTIFACTDIR/sbom"
    # Caches without crates.jsonl predate it and are rebuilt
    if [ -f "$cached_binary" ] && [ -f "$cached_crates" ] && grep -aFq .dep-v0 "$cached_binary"; then
        echo "Using cached binary for $package version $version"
        if [ -n "${extra_features}" ]; then
            echo "| \`$package\`  | \`$version\` (\`$git_describe\`, features: ${extra_features})  | reused from cache | \`$( du -sh $cached_binary | cut -f1 )\`  |   |" ">> $BUILDDIR/manifest.md"
        else
            echo "| \`$package\`  | \`$version\` (\`$git_describe\`)  | reused from cache | \`$( du -sh $cached_binary | cut -f1 )\`  |   |" >> "$BUILDDIR/manifest.md"
        fi
        cp "$cached_binary" "$dest_path"
        add_package_note "$dest_path" "$package" "$version" "$source_url" "$commit"
        cp "$cached_crates" "$sbom_crates"
        return
    fi

    # Define Rust flags for reproducibility
    local rustflags=(
        "-C target-cpu=generic"
        "-C link-arg=-Wl,--build-id=none"
        "-C symbol-mangling-version=v0"
        "-L /usr/lib/x86_64-linux-gnu"
    )

    # add extra flags from .cargo/config.toml
    if [[ -f $build_dir/.cargo/config.toml ]] && local cargoflags=$( mkosi-chroot dasel -f /build/$package/.cargo/config.toml -r toml 'build.rustflags' --pretty=false -w json ); then
        local cargoflags=$( echo $cargoflags | jq -r '. | join(" ")' )
        local rustflags+=( "$cargoflags" )
    fi

    # Build inside mkosi chroot
    local ts=$( date +%s )
    mkosi-chroot bash -c "
        unset DESTDIR
        export RUSTFLAGS='${rustflags[*]} ${extra_rustflags}' \
               CARGO_PROFILE_RELEASE_LTO='thin' \
               CARGO_PROFILE_RELEASE_CODEGEN_UNITS='1' \
               CARGO_PROFILE_RELEASE_PANIC='abort' \
               CARGO_PROFILE_RELEASE_INCREMENTAL='false' \
               CARGO_PROFILE_RELEASE_OPT_LEVEL='3' \
               CARGO_TERM_COLOR='never'
        cd '/build/$package'
        cargo fetch
        cargo auditable build --release --frozen ${extra_features:+--features $extra_features} --package $cargo_package
    "
    local seconds=$(( $( date +%s ) - ts ))
    local duration=$( printf "%dm%ds" $(( seconds / 60 )) $(( seconds % 60 )) )

    # Cache and install the built binary
    mkdir -p "$( dirname $cached_binary )"
    install -m 755 "$build_dir/target/release/$package" "$cached_binary"
    install -m 755 "$cached_binary" "$dest_path"
    add_package_note "$dest_path" "$package" "$version" "$source_url" "$commit"
    record_crate_sources "$package" "$source_url" "$commit" "$cached_crates"
    cp "$cached_crates" "$sbom_crates"

    echo "| \`$package\`  | \`$version\` (\`$git_describe\`, ${extra_features})  | built  | \`$( du -sh $cached_binary | cut -f1 )\`  | \`$duration\`  |" >> "$BUILDDIR/manifest.md"
}

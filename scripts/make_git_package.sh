#!/bin/bash
#
# Note env variables: DESTDIR, BUILDROOT, GOCACHE, BUILDDIR

make_git_package() {
    local package="$1"
    local version="$2"
    local git_url="$3"
    local build_cmd="$4"
    # All remaining arguments are artifact mappings in src:dest format

    mkdir -p "$DESTDIR/usr/bin"
    local cache_dir="$BUILDDIR/${package}-${version}"

    # Use cached artifacts if available
    if [ -n "$cache_dir" ] && [ -d "$cache_dir" ] && [ "$(ls -A "$cache_dir" 2>/dev/null)" ]; then
        echo "Using cached artifacts for $package version $version"
        for artifact_map in "${@:5}"; do
            local src="${artifact_map%%:*}"
            local dest="${artifact_map#*:}"
            mkdir -p "$(dirname "$DESTDIR$dest")"
            cp "$cache_dir/$(echo "$src" | tr '/' '_')" "$DESTDIR$dest"
        done
        return 0
    fi

    # Build from source
    local build_dir="$BUILDROOT/build/$package"
    git clone --depth 1 --branch "$version" "$git_url" "$build_dir"
    mkosi-chroot bash -c "cd '/build/$package' && $build_cmd"

    # Copy artifacts to image and cache
    for artifact_map in "${@:5}"; do
        local src="${artifact_map%%:*}"
        local dest="${artifact_map#*:}"

        # Copy the built artifact to the destination
        mkdir -p "$(dirname "$DESTDIR$dest")"
        cp "$build_dir/$src" "$DESTDIR$dest"

        # Cache artifact
        mkdir -p "$cache_dir"
        cp "$build_dir/$src" "$cache_dir/$(echo "$src" | tr '/' '_')"
    done
}

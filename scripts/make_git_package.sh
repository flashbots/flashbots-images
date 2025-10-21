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
            local cached_name="$(echo "$src" | tr '/' '_')"
            if [ -d "$cache_dir/$cached_name" ]; then
                mkdir -p "$DESTDIR$dest"
                cp -r "$cache_dir/$cached_name"/* "$DESTDIR$dest/"
            else
                cp "$cache_dir/$cached_name" "$DESTDIR$dest"
            fi
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
        if [ -d "$build_dir/$src" ]; then
            mkdir -p "$DESTDIR$dest"
            cp -r "$build_dir/$src"/* "$DESTDIR$dest/"
        else
            mkdir -p "$(dirname "$DESTDIR$dest")"
            cp "$build_dir/$src" "$DESTDIR$dest"
        fi
    
        # Cache artifact
        mkdir -p "$cache_dir"
        local cached_name="$(echo "$src" | tr '/' '_')"
        if [ -d "$build_dir/$src" ]; then
            mkdir -p "$cache_dir/$cached_name"
            cp -r "$build_dir/$src"/* "$cache_dir/$cached_name/"
        else
            cp "$build_dir/$src" "$cache_dir/$cached_name"
        fi
    done
}
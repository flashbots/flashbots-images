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

    # Clone the repository
    local build_dir="$BUILDROOT/build/$package"
    set +x
    echo "Cloning ${git_url}"
    if [ -f "$BUILDDIR/.ghtoken" ]; then
        git_url="${git_url/#https:\/\/github.com/https:\/\/x-access-token:$( cat $BUILDDIR/.ghtoken )@github.com}"
    fi
    git clone --depth 1 --branch "$version" "$git_url" "$build_dir" || (
        echo "Could not clone branch/tag, attempting to checkout the commit by sha"
        git clone -"$git_url" "$build_dir" &&
        git -C "$build_dir" checkout "$version"
    )
    set -x

    # Get the git reference
    local git_describe=$( git -C "$build_dir" describe --always --long --tags )
    printf "${git_describe#$package/}" > "$BUILDDIR/$package.git"

    local cache_dir="$BUILDDIR/${package}-${git_describe#${package}/}"

    # Use cached artifacts if available
    if [ -n "$cache_dir" ] && [ -d "$cache_dir" ] && [ "$(ls -A "$cache_dir" 2>/dev/null)" ]; then
        echo "Using cached artifacts for $package version $version"
        echo "| \`$package\`  | \`$version\` (\`$git_describe\`)  | reused from cache  |   |" >> "$BUILDDIR/manifest.md"
        for artifact_map in "${@:5}"; do
            local src="${artifact_map%%:*}"
            local dest="${artifact_map#*:}"
            mkdir -p "$(dirname "$DESTDIR$dest")"
            if [ -d "$cache_dir/$src" ]; then
                mkdir -p "$DESTDIR$dest"
                cp -r "$cache_dir/$src"/* "$DESTDIR$dest/"
            else
                cp "$cache_dir/$src" "$DESTDIR$dest"
            fi
        done
        return 0
    fi

    # Build from source
    local ts=$( date +%s )
    mkosi-chroot bash -c "cd '/build/$package' && $build_cmd"
    local seconds=$(( $( date +%s ) - ts ))
    local duration=$( printf "%dm%ds" $(( seconds / 60 )) $(( seconds % 60 )) )

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
        if [ -d "$build_dir/$src" ]; then
            mkdir -p "$cache_dir/$src"
            cp -r "$build_dir/$src"/* "$cache_dir/$src/"
        else
            mkdir -p "$( dirname $cache_dir/$src )"
            cp "$build_dir/$src" "$cache_dir/$src"
        fi
    done

    echo "| \`$package\`  | \`$version\` (\`$git_describe\`)  | built  | \`$duration\`  |" >> "$BUILDDIR/manifest.md"
}

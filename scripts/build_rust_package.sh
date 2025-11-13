#!/bin/bash

build_rust_package() {
    local package="$1"
    local version="$2"
    local git_url="$3"
    local provided_binary="$4"
    local extra_features="${5:-}"
    local extra_rustflags="${6:-}"

    local dest_path="$DESTDIR/usr/bin/$package"
    mkdir -p "$DESTDIR/usr/bin"

    # If binary path is provided, use it directly
    if [ -n "$provided_binary" ]; then
        echo "Using provided binary for $package"
        cp "$provided_binary" "$dest_path"
        return
    fi

    # If binary is cached, skip compilation
    local cached_binary="$BUILDDIR/${package}-${version#${package}/}/${package}"
    if [ -f "$cached_binary" ]; then
        echo "Using cached binary for $package version $version"
        cp "$cached_binary" "$dest_path"
        return
    fi

    # Clone the repository
    local build_dir="$BUILDROOT/build/$package"
    mkdir -p "$build_dir"
    git clone --depth 1 --branch "$version" "$git_url" "$build_dir"

    # Define Rust flags for reproducibility
    local rustflags=(
        "-C target-cpu=generic"
        "-C link-arg=-Wl,--build-id=none"
        "-C symbol-mangling-version=v0"
        "-L /usr/lib/x86_64-linux-gnu"
    )

    # Build inside mkosi chroot
    mkosi-chroot bash -c "
        export RUSTFLAGS='${rustflags[*]} ${extra_rustflags}' \
               CARGO_PROFILE_RELEASE_LTO='thin' \
               CARGO_PROFILE_RELEASE_CODEGEN_UNITS='1' \
               CARGO_PROFILE_RELEASE_PANIC='abort' \
               CARGO_PROFILE_RELEASE_INCREMENTAL='false' \
               CARGO_PROFILE_RELEASE_OPT_LEVEL='3' \
               CARGO_TERM_COLOR='never'
        cd '/build/$package'
        cargo fetch
        cargo build --release --frozen ${extra_features:+--features $extra_features} --package $package
    "

    # Cache and install the built binary
    mkdir -p "$( dirname $cached_binary )"
    install -m 755 "$build_dir/target/release/$package" "$cached_binary"
    install -m 755 "$cached_binary" "$dest_path"
}

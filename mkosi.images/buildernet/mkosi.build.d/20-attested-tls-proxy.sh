#!/usr/bin/env bash
set -euo pipefail

REF=06aafe43335a5d228a3ea2d3b871d15d2d06e855
CARGO_HOME="$BUILDDIR/.cargo"
PATH="$BUILDDIR/rust-toolchain/bin:$PATH"
BUILDDIR="$BUILDDIR/attested-tls-proxy"
export CARGO_HOME="$SRCDIR/mkosi.images/buildernet/mkosi.cache/cargo"

echo "Installing attested-tls-proxy..."

mkdir -p $BUILDDIR

curl -sSfL https://api.github.com/repos/flashbots/attested-tls-proxy/tarball/${REF} | \
  tar xzf - -C $BUILDDIR --strip-components=1

cd $BUILDDIR

RUSTFLAGS="-C target-cpu=x86-64-v4 \
           -C link-arg=-Wl,--build-id=none \
           -C symbol-mangling-version=v0 \
           -L /usr/lib/x86_64-linux-gnu"
CARGO_PROFILE_RELEASE_LTO='thin'
CARGO_PROFILE_RELEASE_CODEGEN_UNITS='1'
CARGO_PROFILE_RELEASE_PANIC='abort'
CARGO_PROFILE_RELEASE_INCREMENTAL='false'
CARGO_PROFILE_RELEASE_OPT_LEVEL='3'
CARGO_TARGET_DIR="$BUILDDIR/target"

cargo build --release --locked

mkdir -p $DESTDIR/usr/bin
cp $CARGO_TARGET_DIR/release/attested-tls-proxy $DESTDIR/usr/bin/attested-tls-proxy

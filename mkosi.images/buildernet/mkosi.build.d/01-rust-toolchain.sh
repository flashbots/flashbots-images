#!/bin/bash

set -eu -o pipefail

RUST_VERSION="1.96.1"

if [[ "$($BUILDDIR/rust-toolchain/bin/rustc --version 2>/dev/null)" == "rustc $RUST_VERSION "* ]]; then
  exit 0
fi

# builddir is cached in CI; drop a toolchain left over from an older version
rm -rf $BUILDDIR/rust-toolchain
mkdir -p $BUILDDIR/rust-tmp
curl -sSfL https://static.rust-lang.org/dist/rust-$RUST_VERSION-x86_64-unknown-linux-gnu.tar.xz | \
  tar xJf - -C $BUILDDIR/rust-tmp --strip-components=1
$BUILDDIR/rust-tmp/install.sh \
  --destdir=$BUILDDIR --without=rust-docs --prefix=/rust-toolchain --disable-ldconfig
rm -rf $BUILDDIR/rust-tmp
# TODO: verify archive signature

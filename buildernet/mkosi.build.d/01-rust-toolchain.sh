#!/bin/bash

set -eu -o pipefail

RUST_VERSION="1.88.0"

if [[ -f $BUILDDIR/rust-toolchain/bin/rustc ]]; then
  exit 0
fi

mkdir -p $BUILDDIR/rust-tmp
curl -sSfL https://static.rust-lang.org/dist/rust-$RUST_VERSION-x86_64-unknown-linux-gnu.tar.xz | \
  tar xJf - -C $BUILDDIR/rust-tmp --strip-components=1
$BUILDDIR/rust-tmp/install.sh \
  --destdir=$BUILDDIR --without=rust-docs --prefix=/rust-toolchain --disable-ldconfig
rm -rf $BUILDDIR/rust-tmp
# TODO: verify archive signature

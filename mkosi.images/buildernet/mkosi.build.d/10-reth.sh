#!/bin/bash
set -euo pipefail

REF=5fd44d08e5cf49107f1bc05823584fbb3449190e
CARGO_HOME="$BUILDDIR/.cargo"
PATH="$BUILDDIR/rust-toolchain/bin:$PATH"
BUILDDIR="$BUILDDIR/reth"
export CARGO_HOME="$SRCDIR/mkosi.images/buildernet/mkosi.cache/cargo"

echo "Installing reth..."

mkdir -p $BUILDDIR

curl -sSfL https://api.github.com/repos/flashbots/reth/tarball/${REF} | \
  tar xzf - -C $BUILDDIR --strip-components=1

cd $BUILDDIR

make build

mkdir -p $DESTDIR/usr/bin
cp $CARGO_TARGET_DIR/release/reth $DESTDIR/usr/bin/reth

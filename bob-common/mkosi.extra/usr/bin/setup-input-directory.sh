#!/bin/bash
# Sets up the input directory for the input-only-proxy
set -eu -o pipefail

INPUT_DIR="/persistent/input"

echo "Setting up input directory for input-only-proxy..."

# Create directory on persistent storage
mkdir -p "$INPUT_DIR"

# Set directory ownership to searcher:searcher
# This allows the container to create the Unix socket
chown 1000:1000 "$INPUT_DIR"  # searcher:searcher
chmod 755 "$INPUT_DIR"

# Remove any stale socket if it exists
if [ -e "$INPUT_DIR/input.sock" ]; then
    echo "Removing stale socket at $INPUT_DIR/input.sock"
    rm -f "$INPUT_DIR/input.sock"
fi

echo "Input directory ready at $INPUT_DIR"
echo "Container will create Unix socket at $INPUT_DIR/input.sock"
exit 0

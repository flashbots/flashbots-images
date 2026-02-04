#!/bin/bash
# Sets up the input FIFO for searcher data feed with hardened security
# MUST run as root to ensure proper ownership and prevent tampering
set -eu -o pipefail

# Use /persistent/input to match existing /persistent/searcher pattern
INPUT_DIR="/persistent/input"
FIFO_PATH="$INPUT_DIR/data.fifo"

echo "Setting up hardened searcher input FIFO..."

# Ensure we're running as root for security
if [ "$EUID" -ne 0 ]; then 
   echo "ERROR: This script must be run as root for security reasons" >&2
   exit 1
fi

# Create directory on persistent storage with secure ownership
mkdir -p "$INPUT_DIR"

# Set directory ownership to root with read/execute for searcher group
# Directory must be root-owned to prevent tampering
chown root:root "$INPUT_DIR"
chmod 755 "$INPUT_DIR"  # rwxr-xr-x - searcher can traverse but not modify

# Remove any existing FIFO/symlink (security check)
if [ -e "$FIFO_PATH" ] || [ -L "$FIFO_PATH" ]; then
    echo "Removing existing file at $FIFO_PATH for security..."
    rm -f "$FIFO_PATH"
fi

# Create FIFO with secure permissions
mkfifo "$FIFO_PATH"
echo "Created FIFO at $FIFO_PATH"

# Set FIFO ownership: root owns it, searcher group can read
# This prevents the container from modifying/replacing the FIFO
chown root:1000 "$FIFO_PATH"  # root:searcher
chmod 640 "$FIFO_PATH"        # rw-r----- (root write, group read, others none)

# Verify the FIFO was created correctly (security validation)
if [ ! -p "$FIFO_PATH" ]; then
    echo "ERROR: Failed to create FIFO at $FIFO_PATH" >&2
    exit 1
fi

# Verify no symlinks (extra security check)
if [ -L "$FIFO_PATH" ]; then
    echo "ERROR: Security violation - FIFO is a symlink!" >&2
    exit 1
fi

echo "Hardened searcher input FIFO ready at $FIFO_PATH"
echo "Security features enabled:"
echo "  - Root-owned directory (prevents tampering)"
echo "  - Root-owned FIFO (prevents replacement)"
echo "  - Read-only mount in container (prevents modification)"
echo "  - Group read permission only (searcher UID 1000)"
echo ""
echo "Container will access it READ-ONLY at /persistent/input/data.fifo"
echo "Usage: cat data.json | ssh searcher@host feed-data"
exit 0

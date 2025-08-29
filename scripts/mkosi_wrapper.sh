#!/bin/bash
set -euo pipefail

# This script is called in place of "mkosi" to ensure correct user namespace
# setup.

# This wrapper is called in both cases: plain host nix and Lima VM.

cmd=(
    # We need to run mkosi in a new user namespace,
    # because it creates files owned by multiple uids/gids, and we
    # either need to run as root, or use this unshare, which is safer.
    # See also:
    # https://manpages.debian.org/unstable/mkosi/mkosi.1.en.html#:~:text=Why%20do%20I%20see%20failures%20to%20chown%20files%20when%20building%20images
    "unshare"
    "--map-auto" "--map-current-user"
    "--setuid=0" "--setgid=0"
    "--"
    # unshare clears environment, so we need to pass PATH explicitly
    "env" "PATH=$PATH"
    # Run mkosi with all passed arguments
    "mkosi" "${@:1}"
)

exec "${cmd[@]}"

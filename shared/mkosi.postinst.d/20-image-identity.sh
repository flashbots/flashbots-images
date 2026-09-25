#!/usr/bin/env bash
set -euo pipefail
umask 022

# Keep the exact source commit in every image.
# GIT_COMMIT is set by env_wrapper.sh; direct mkosi runs fall back to git.
commit=${GIT_COMMIT:-$(git -C "$SRCDIR" rev-parse --verify 'HEAD^{commit}')}
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
[[ "$IMAGE_ID" =~ ^[a-zA-Z0-9._-]+$ ]]

install -d -m 0755 "$BUILDROOT/usr/lib/flashbots" "$BUILDROOT/usr/lib/flashbots/metrics"
printf '%s\n' "$commit" > "$BUILDROOT/usr/lib/flashbots/git-commit"
{
    echo '# HELP flashbots_image_info Always 1; image identifies the built image and git_commit identifies its source commit.'
    echo '# TYPE flashbots_image_info gauge'
    printf 'flashbots_image_info{image="%s",git_commit="%s"} 1\n' "$IMAGE_ID" "$commit"
} > "$BUILDROOT/usr/lib/flashbots/metrics/image.prom"

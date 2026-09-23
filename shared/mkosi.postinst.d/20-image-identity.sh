#!/usr/bin/env bash
set -euo pipefail

# Keep the exact source commit in every image.
commit=$(git -C "$SRCDIR" rev-parse --verify 'HEAD^{commit}')
[[ "$IMAGE_ID" =~ ^[a-zA-Z0-9._-]+$ ]]

install -d -m 0755 "$BUILDROOT/usr/lib/flashbots" "$BUILDROOT/usr/lib/flashbots/metrics"
printf '%s\n' "$commit" > "$BUILDROOT/usr/lib/flashbots/git-commit"
{
    echo '# HELP flashbots_image_info Always 1; image identifies the built image and git_commit identifies its source commit.'
    echo '# TYPE flashbots_image_info gauge'
    printf 'flashbots_image_info{image="%s",git_commit="%s"} 1\n' "$IMAGE_ID" "$commit"
} > "$BUILDROOT/usr/lib/flashbots/metrics/image.prom"

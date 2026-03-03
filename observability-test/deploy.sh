#!/bin/bash
set -euo pipefail

HOST="${1:?usage: ./deploy.sh root@<host>}"
REMOTE_DIR="/root/observability-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Deploying to $HOST:$REMOTE_DIR ..."
COPYFILE_DISABLE=1 tar czf - -C "$SCRIPT_DIR" --exclude='._*' . | ssh "$HOST" "mkdir -p $REMOTE_DIR && tar xzf - -C $REMOTE_DIR"

echo "==> Restarting containers..."
ssh "$HOST" "cd $REMOTE_DIR && bash run.sh"

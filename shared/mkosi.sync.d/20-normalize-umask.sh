#!/bin/bash
set -euo pipefail
find "$SRCDIR" -mindepth 1 -not -type l -exec chmod go-w {} +

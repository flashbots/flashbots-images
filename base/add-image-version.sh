#!/bin/bash
set -euo pipefail

echo "IMAGE_VERSION=$IMAGE_VERSION" >> "$BUILDROOT/usr/lib/os-release"

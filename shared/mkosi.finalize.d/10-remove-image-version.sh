#!/bin/bash
set -euo pipefail

# mkosi adds IMAGE_VERSION tag to /usr/lib/os-release, if it's set.
# We are including git commit hash in image versions, which might cause
# some reproducibility issues, so let's remove it for now

# This needs to be in finalize script, as mkosi adds version after postinst

sed -i '/^IMAGE_VERSION=/d' "$BUILDROOT/usr/lib/os-release"

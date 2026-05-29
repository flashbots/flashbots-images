#!/bin/bash
set -eu -o pipefail

apt-get -y build-dep linux-source-${KERNEL_VERSION}
apt-get -y install linux-source-${KERNEL_VERSION} --install-recommends
# socat UNIX-LISTEN:$SRCDIR/debug.sock,fork EXEC:/bin/bash,pty,stderr

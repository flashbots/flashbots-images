#!/bin/bash
set -eu -o pipefail

apt-get -y build-dep linux-source
apt-get -y install linux-source
# socat UNIX-LISTEN:$SRCDIR/debug.sock,fork EXEC:/bin/bash,pty,stderr

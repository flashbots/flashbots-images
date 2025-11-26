#!/bin/bash

# The mkosi sandbox environment should have a debian backports source list
# that matches the archive timestamp of the main release.
# See https://github.com/systemd/mkosi/issues/1755
MIRROR=$(jq -r .Mirror /work/config.json)
if [ "$MIRROR" = "null" ]; then
    : > "$SRCDIR/mkosi.builddir/debian-backports.sources"
else
    cat > "$SRCDIR/mkosi.builddir/debian-backports.sources" <<EOF
Types: deb deb-src
URIs: $MIRROR
Suites: ${RELEASE}-backports
Components: main
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
fi

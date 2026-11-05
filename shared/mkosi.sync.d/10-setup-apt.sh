#!/usr/bin/env bash

# Adds mkosi sources. See https://github.com/systemd/mkosi/issues/1755
SNAPSHOT=$(jq -r .Snapshot /work/config.json)
if [ "$SNAPSHOT" = "null" ]; then
    MIRROR="https://deb.debian.org/debian"
    SECURITY_MIRROR="https://deb.debian.org/debian-security"
else
    MIRROR="https://snapshot.debian.org/archive/debian/${SNAPSHOT}"
    SECURITY_MIRROR="https://snapshot.debian.org/archive/debian-security/${SNAPSHOT}"
fi

cat > "$SRCDIR/mkosi.builddir/mkosi.sources" <<EOF
Types: deb deb-src
URIs: $MIRROR
Suites: ${RELEASE} ${RELEASE}-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: $SECURITY_MIRROR
Suites: ${RELEASE}-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

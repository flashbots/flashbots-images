#!/usr/bin/env bash

# Adds mkosi sources. See https://github.com/systemd/mkosi/issues/1755
SNAPSHOT=$(jq -r .Snapshot /work/config.json)
if [ "$SNAPSHOT" = "null" ]; then
    MIRROR="http://deb.debian.org/debian"
    MIRROR_SECURITY="http://security.debian.org/debian-security"
else
    MIRROR="http://snapshot.debian.org/archive/debian/${SNAPSHOT}"
    MIRROR_SECURITY="http://snapshot.debian.org/archive/debian-security/${SNAPSHOT}"
fi

cat > "$SRCDIR/mkosi.builddir/mkosi.sources" <<EOF
Types: deb deb-src
URIs: $MIRROR
Suites: ${RELEASE} ${RELEASE}-backports
Components: main
Trusted: yes

Types: deb deb-src
URIs: $MIRROR_SECURITY
Suites: ${RELEASE}-security
Components: main
Trusted: yes
EOF

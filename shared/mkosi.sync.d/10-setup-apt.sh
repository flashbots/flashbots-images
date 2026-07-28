#!/usr/bin/env bash

# Adds mkosi sources. See https://github.com/systemd/mkosi/issues/1755
SNAPSHOT=$(jq -r .Snapshot /work/config.json)
if [ "$SNAPSHOT" = "null" ]; then
    MIRROR="http://deb.debian.org/debian"
else
    MIRROR="http://snapshot.debian.org/archive/debian/${SNAPSHOT}"
fi

cat > "$SRCDIR/mkosi.builddir/mkosi.sources" <<EOF
Types: deb deb-src
URIs: $MIRROR
Suites: ${RELEASE} ${RELEASE}-backports
Components: main
Trusted: yes

# deb only (no deb-src): sid is used solely to fetch the linux-source
# binary package, and its Sources index alone is ~12 MB per apt update.
Types: deb
URIs: $MIRROR
Suites: sid
Components: main
Trusted: yes
EOF

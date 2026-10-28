#!/bin/bash
set -euo pipefail

EXPECTED_SHA256="bfb1cb83bdc3705ef6a945ed81b00d8da2443057e57dfb8e7f4b61f695317a4d"
curl -sSfL https://github.com/pendulum-project/ntpd-rs/releases/download/v1.9.0/ntpd-rs_1.9.0-1_amd64.deb -o $PACKAGEDIR/ntpd-rs.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/ntpd-rs.deb | sha256sum --check

# postinst script causes errors during mkosi build, remove it
dpkg-deb -R $PACKAGEDIR/ntpd-rs.deb /tmp/ntpd-rs-deb
rm /tmp/ntpd-rs-deb/DEBIAN/postinst
dpkg -b /tmp/ntpd-rs-deb $PACKAGEDIR/ntpd-rs.deb
# TODO: switch to debian repository when updated, currently 1.4.0 there

#!/bin/bash
set -euo pipefail

EXPECTED_SHA256="b54d9495dda5cb042752f76d8e993b90f0df6cd67863fb8e6a4454454bacb194"
curl -sSfL https://github.com/pendulum-project/ntpd-rs/releases/download/v1.6.2/ntpd-rs_1.6.2-1_amd64.deb -o $PACKAGEDIR/ntpd-rs.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/ntpd-rs.deb | sha256sum --check

# postinst script causes errors during mkosi build, remove it
dpkg-deb -R $PACKAGEDIR/ntpd-rs.deb /tmp/ntpd-rs-deb
rm /tmp/ntpd-rs-deb/DEBIAN/postinst
dpkg -b /tmp/ntpd-rs-deb $PACKAGEDIR/ntpd-rs.deb

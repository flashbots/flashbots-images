#!/bin/bash
set -euo pipefail

# rbuilder-operator
EXPECTED_SHA256=1496db592d4c753b19480dc1529ecc99a86e0db7236ef25ccdbbe994759309f2
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.2/rbuilder-operator_1.v1.3.2_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=e235fac27aadc3c0c1cb5dc2c18f873aaf23a4af7e7bf302d0c0f4030f7fdf2e
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.2/rbuilder-rebalancer_1.v1.3.2_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

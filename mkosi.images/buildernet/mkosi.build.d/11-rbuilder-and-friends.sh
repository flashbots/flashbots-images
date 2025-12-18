#!/bin/bash
set -euo pipefail

# rbuilder-operator
EXPECTED_SHA256=f22110ca2411c851f7a1de57d456a872b969fd710a6453525329ef51f012b6cf
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.1/rbuilder-operator_1.v1.3.1_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=a1a9bc6c82055e82d8095c089586f6a3cfbdea4392d26e54271b8d90d7c1cb65
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.1/rbuilder-rebalancer_1.v1.3.1_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

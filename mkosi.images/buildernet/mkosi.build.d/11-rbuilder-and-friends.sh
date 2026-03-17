#!/bin/bash
set -euo pipefail

echo "Installing rbuilder..."

OPERATOR_VERSION="1.3.11"
REBALANCER_VERSION="1.3.11"

# rbuilder-operator
EXPECTED_SHA256=3ccdc85d2be2547df1cc3f5117e65ae31a8b3dbdf27eaab5515a6b9733f1acc0
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v${OPERATOR_VERSION}/rbuilder-operator_1.v${OPERATOR_VERSION}_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=d722bfbe6a85a7d47e83c2d0468d39cff2293866acbfc3f0b35565d65ae23f43
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v${REBALANCER_VERSION}/rbuilder-rebalancer_1.v${REBALANCER_VERSION}_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

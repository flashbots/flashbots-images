#!/bin/bash
set -euo pipefail

echo "Installing rbuilder..."

OPERATOR_VERSION="1.3.13"
REBALANCER_VERSION="1.3.13"

# rbuilder-operator
EXPECTED_SHA256=991b9c47fd5a549edd69f0d5e3524fc71cbbccf586b2250c5c059c03b1e23184
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v${OPERATOR_VERSION}/rbuilder-operator_1.v${OPERATOR_VERSION}_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=9fd7e50d980c7ae8a91e2a1bbe4eed893c0f1f87e4e3de60601a1d74ae4ba79d
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v${REBALANCER_VERSION}/rbuilder-rebalancer_1.v${REBALANCER_VERSION}_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

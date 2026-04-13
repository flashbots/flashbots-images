#!/bin/bash
set -euo pipefail

echo "Installing rbuilder..."

OPERATOR_VERSION="1.3.14"
REBALANCER_VERSION="1.3.14"

# rbuilder-operator
EXPECTED_SHA256=c91c4cc2fb1ad1b310c6835e3bd10d29fddeae1edc0b0885f9037326768a1e86
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v${OPERATOR_VERSION}/rbuilder-operator_1.v${OPERATOR_VERSION}_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=4751e2cc0ec4493f82e29c4b9d146298dc15d3b68ac28ca8db4ba3c94233524d
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v${REBALANCER_VERSION}/rbuilder-rebalancer_1.v${REBALANCER_VERSION}_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

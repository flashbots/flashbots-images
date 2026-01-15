#!/bin/bash
set -euo pipefail

# rbuilder-operator
EXPECTED_SHA256=b8997821cbe9e1144c36b54c5090a89aa75b1ecb578dcbbce5f0c3b731cc5457
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.4/rbuilder-operator_1.v1.3.4_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=1e4a9e75f332c5951cb3f8d46339da2d060322ed8e2407905de2ca5fe88f5206
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.4/rbuilder-rebalancer_1.v1.3.4_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

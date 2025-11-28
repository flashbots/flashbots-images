#!/bin/bash
set -euo pipefail

# rbuilder-operator
EXPECTED_SHA256=58f59ad269c8e85f5e4a33aba3bd781bd17a6cba3d6f49abbe6872dbb49d6630
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.2.29/rbuilder-operator_1.v1.2.29_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=3e94a9ab5d109ab930d8cbd99f1ce746d7484c8002237d8345511e9c91e87f12
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.2.29/rbuilder-rebalancer_1.v1.2.29_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

#!/bin/bash
set -euo pipefail

echo "Installing rbuilder..."

# rbuilder-operator
EXPECTED_SHA256=266d7e26e17663a3b75177e098c20a401ccc4f85a30c8fbf34018979240bd7bc
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.6/rbuilder-operator_1.v1.3.6_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=8fbf5af475c76657a49d5ffec45e66a073dfa1c75c08f926b64578f3f8acd955
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.3.6/rbuilder-rebalancer_1.v1.3.6_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

#!/bin/bash
set -euo pipefail

# TODO: prettify

# rbuilder-operator
EXPECTED_SHA256=a95c8f5039cc525539430112e3c5b3268cd05ea663e717268b28d2d690dcc25e
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.2.19/rbuilder-operator_1.v1.2.19_amd64.deb -o $PACKAGEDIR/rbuilder-operator.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-operator.deb | sha256sum --check

# rbuilder-rebalancer
EXPECTED_SHA256=cf8f2cf0d3194a94e5d136e66c5cef58038ebe7c391b10c351fe0c0f26c966e9
curl -sSfL https://github.com/flashbots/rbuilder/releases/download/v1.2.20/rbuilder-rebalancer_1.v1.2.20_amd64.deb -o $PACKAGEDIR/rbuilder-rebalancer.deb
echo "${EXPECTED_SHA256}" $PACKAGEDIR/rbuilder-rebalancer.deb | sha256sum --check

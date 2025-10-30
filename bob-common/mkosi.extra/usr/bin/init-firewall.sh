#!/bin/sh
set -eu -o pipefail

# =============================================================================
# Host Firewall Overview
#
# [Inbound Packet]
#  (INPUT Chain)
#    ├(ESTABLISHED/RELATED?)─> ACCEPT
#    ├─> evaluate chain ALWAYS_IN
#    ├─> evaluate chain MODE_SELECTOR_IN, jump to MAINTENANCE_IN or PRODUCTION_IN
#    ├(loopback?)─> ACCEPT
#    └─> default DROP
#
# [Outbound Packet]
#  (OUTPUT Chain)
#    ├(ESTABLISHED/RELATED?)─> ACCEPT
#    ├─> evaluate chain ALWAYS_OUT
#    ├─> evaluate chain MODE_SELECTOR_OUT, jump to MAINTENANCE_OUT or PRODUCTION_OUT
#    ├(loopback?)─> ACCEPT
#    └─> default DROP
#
# - There are no ports opened in this file, refer to bob*/mkosi.extra/etc/bob/firewall-config
#   for actual chain rules.
# - Mode-specific ESTABLISHED/RELATED connections are killed by
#   `conntrack -D ...` upon mode toggle.
# =============================================================================

echo "Initializing firewall..."

###########################################################################
# (1) Flush any existing rules/chains
###########################################################################
iptables -F
iptables -X

###########################################################################
# (2) Set default policies to DROP
###########################################################################
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

###########################################################################
# (3) Create custom chains
###########################################################################
CHAIN_ALWAYS_IN="ALWAYS_IN"
CHAIN_ALWAYS_OUT="ALWAYS_OUT"

CHAIN_MODE_SELECTOR_IN="MODE_SELECTOR_IN"
CHAIN_MODE_SELECTOR_OUT="MODE_SELECTOR_OUT"

CHAIN_MAINTENANCE_IN="MAINTENANCE_IN"
CHAIN_MAINTENANCE_OUT="MAINTENANCE_OUT"

CHAIN_PRODUCTION_IN="PRODUCTION_IN"
CHAIN_PRODUCTION_OUT="PRODUCTION_OUT"

for CHAIN in \
    $CHAIN_ALWAYS_IN \
    $CHAIN_ALWAYS_OUT \
    $CHAIN_MODE_SELECTOR_IN \
    $CHAIN_MODE_SELECTOR_OUT \
    $CHAIN_MAINTENANCE_IN \
    $CHAIN_MAINTENANCE_OUT \
    $CHAIN_PRODUCTION_IN \
    $CHAIN_PRODUCTION_OUT
do
    iptables -N $CHAIN
done

###########################################################################
# (4) Set up top-level INPUT/OUTPUT chains
#
# - First, allow packets for already established connections
#     Refer to {MAINTENANCE,PRODUCTION}_{IN,OUT} for ACCEPT rules
# - Main routing:
#     INPUT  -> ALWAYS_IN, if not matched, then MODE_SELECTOR_IN
#     OUTPUT -> ALWAYS_OUT, if not matched, then MODE_SELECTOR_OUT
# - Then, allow loopback traffic, prevent spoofing
# - If none matched, DROP as per default chain policy
###########################################################################
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A INPUT  -j $CHAIN_ALWAYS_IN
iptables -A OUTPUT -j $CHAIN_ALWAYS_OUT

iptables -A INPUT  -j $CHAIN_MODE_SELECTOR_IN
iptables -A OUTPUT -j $CHAIN_MODE_SELECTOR_OUT

iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

iptables -A INPUT  ! -i lo -s 127.0.0.0/8 -j DROP
iptables -A OUTPUT ! -o lo -d 127.0.0.0/8 -j DROP


###########################################################################
#
# Some helper functions to reduce boilerplate in /etc/bob/firewall-config
#
###########################################################################
accept_dst_port() {
    chain="$1"
    protocol="$2"
    port="$3"
    comment="$4"

    iptables -A "$chain" -p "$protocol" --dport "$port" \
                         -m conntrack --ctstate NEW -j ACCEPT \
                         -m comment --comment "$comment"
}

accept_dst_ip_port() {
    chain="$1"
    protocol="$2"
    ip="$3"
    port="$4"
    comment="$5"

    iptables -A "$chain" -p "$protocol" -d "$ip" --dport "$port" \
                         -m conntrack --ctstate NEW -j ACCEPT \
                         -m comment --comment "$comment"
}

drop_dst_ip() {
    chain="$1"
    ip="$2"
    comment="$3"

    iptables -A "$chain" -d "$ip" -j DROP \
                         -m comment --comment "$comment"
}

###########################################################################
# (5) Load firewall rules in {MAINTENANCE,PRODUCTION}_{IN,OUT} chains.
# Those are customized per image, see bob*/mkosi.extra/etc/bob/firewall-config
#
# `source` is not supported in dash
###########################################################################
. /etc/bob/firewall-config

###########################################################################
# (6) Start in Maintenance Mode
###########################################################################
iptables -A $CHAIN_MODE_SELECTOR_IN  -j $CHAIN_MAINTENANCE_IN
iptables -A $CHAIN_MODE_SELECTOR_OUT -j $CHAIN_MAINTENANCE_OUT

# Set initial state
echo "maintenance" > /etc/searcher-network.state

echo "Firewall initialized in Maintenance Mode."

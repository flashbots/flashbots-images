#!/bin/sh
set -eu -o pipefail

# =============================================================================
# Host Firewall Overview
#
# [Inbound Packet]
#    │
#    ▼
#  (INPUT Chain)
#    ├─(ESTABLISHED/RELATED?)─> ACCEPT
#    ├─> ALWAYS_ON_IN ──> Return
#    └─> MODE_SELECTOR_IN 
#          ├─> jumps MAINTENANCE_IN or PRODUCTION_IN ─> Return
#          └─> end => default DROP
#
# [Outbound Packet]
#    │
#    ▼
#  (OUTPUT Chain)
#    ├─(ESTABLISHED/RELATED?)─> ACCEPT
#    ├─> ALWAYS_ON_OUT ──> Return
#    └─> MODE_SELECTOR_OUT
#          ├─> jumps MAINTENANCE_OUT or PRODUCTION_OUT ─> Return
#          └─> end => default DROP
#
# - NEW connections are terminated and enabled by MODE_SELECTOR jumps to MAINTENANCE and PRODUCTION rule sets
# - ESTABLISHED/RELATED for mode specific connections are killed by `conntrack -D <port>` upon each mode switch.
# =============================================================================

echo "Initializing firewall with separate inbound/outbound chains..."

TITAN_BUILDER_IP="52.207.17.217"

# TEE Searcher IPs
FLASHBOTS_TX_IP1="3.136.107.142"
FLASHBOTS_TX_IP2="3.149.14.12"
FLASHBOTS_BUNDLE_IP1="18.221.59.61"
FLASHBOTS_BUNDLE_IP2="3.15.88.156"

###############################################################################
# Ports
###############################################################################
SSH_CONTROL_PORT=22        # Inbound: SSH control plane (always on)
SSH_DATA_PORT=10022        # Inbound: SSH data plane (maintenance mode only)
SSH_REGISTER_PORT=8080     # Inbound: SSH registration

CL_P2P_PORT=9000           # TCP/UDP inbound/outbound: Consensus client P2P (always on)
EL_P2P_PORT=30303          # TCP/UDP outbound: Execution client P2P (maintenance mode only)

DNS_PORT=53                # Outbound: DNS (maintenance mode only)
HTTP_PORT=80               # Outbound: HTTP (maintenance mode only)
HTTPS_PORT=443             # Outbound: HTTPS (maintenance mode only)

SEARCHER_INPUT_CHANNEL=27017  # Inbound: Input Only Channel (always on)

TITAN_STATE_DIFF_PORT_WSS=42203    # Outbound: Titan builder state diff new:42203 (production only)
TITAN_BUNDLE_PORT_HTTPS=1338        # Outbound: Titan builder bundle submission new:1338 (always on)

CVM_REVERSE_PROXY_PORT=8745      # Inbound: CVM reverse proxy (always on)
NTP_PORT=123           # Outbound: NTP (always on)

###############################################################################
# Custom Chains
###############################################################################
CHAIN_ALWAYS_ON_IN="ALWAYS_ON_IN"
CHAIN_ALWAYS_ON_OUT="ALWAYS_ON_OUT"

CHAIN_MODE_SELECTOR_IN="MODE_SELECTOR_IN"
CHAIN_MODE_SELECTOR_OUT="MODE_SELECTOR_OUT"

CHAIN_MAINTENANCE_IN="MAINTENANCE_IN"
CHAIN_MAINTENANCE_OUT="MAINTENANCE_OUT"

CHAIN_PRODUCTION_IN="PRODUCTION_IN"
CHAIN_PRODUCTION_OUT="PRODUCTION_OUT"


###########################################################################
# (1) Set default policies to DROP
###########################################################################
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

###########################################################################
# (2) Flush any existing rules/chains
###########################################################################
iptables -F
iptables -X

###########################################################################
# (3) Create custom chains
###########################################################################
for CHAIN in \
    $CHAIN_ALWAYS_ON_IN $CHAIN_ALWAYS_ON_OUT \
    $CHAIN_MODE_SELECTOR_IN $CHAIN_MODE_SELECTOR_OUT \
    $CHAIN_MAINTENANCE_IN $CHAIN_MAINTENANCE_OUT \
    $CHAIN_PRODUCTION_IN $CHAIN_PRODUCTION_OUT
do
    iptables -N $CHAIN
done

###########################################################################
# (4) Allow Established/Related connections (Inbound & Outbound)
# OUTPUT (always): SSH (22), CL P2P (9000), CVM reverse-proxy (8745)
# OUTPUT (maintenance): SSH (10022)
###########################################################################
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

###########################################################################
# (5) Main Routing:
#     INPUT  -> ALWAYS_ON_IN -> MODE_SELECTOR_IN
#     OUTPUT -> ALWAYS_ON_OUT -> MODE_SELECTOR_OUT
###########################################################################
iptables -A INPUT -j $CHAIN_ALWAYS_ON_IN
iptables -A INPUT -j $CHAIN_MODE_SELECTOR_IN

iptables -A OUTPUT -j $CHAIN_ALWAYS_ON_OUT
iptables -A OUTPUT -j $CHAIN_MODE_SELECTOR_OUT

###########################################################################
# (6) ALWAYS_ON_IN: Inbound rules that never turn off
###########################################################################
# SSH control port (22)
iptables -A $CHAIN_ALWAYS_ON_IN -p tcp --dport $SSH_CONTROL_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Searcher input channel (UDP on 27017)
iptables -A $CHAIN_ALWAYS_ON_IN -p udp --dport $SEARCHER_INPUT_CHANNEL \
    -m conntrack --ctstate NEW -j ACCEPT

# Consensus (CL) P2P inbound on port 9000 (TCP + UDP)
iptables -A $CHAIN_ALWAYS_ON_IN -p tcp --dport $CL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A $CHAIN_ALWAYS_ON_IN -p udp --dport $CL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# CVM reverse-proxy inbound on port 8745 (TCP)
# Serves server attestation 
# Also forwards request to ssh pubkey server on localhost:5001, 
#    which serves searcher-container openssh server pubkey 
iptables -A $CHAIN_ALWAYS_ON_IN -p tcp --dport $CVM_REVERSE_PROXY_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Return from ALWAYS_ON_IN back to caller (INPUT chain -> MODE_SELECTOR_IN) 
iptables -A $CHAIN_ALWAYS_ON_IN -j RETURN

###########################################################################
# (7) ALWAYS_ON_OUT: Outbound rules that never turn off
###########################################################################
# CL P2P outbound on port 9000 (TCP + UDP)
# Note: This is the lighthouse CL client run on the host, not the searcher's CL
iptables -A $CHAIN_ALWAYS_ON_OUT -p tcp --dport $CL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A $CHAIN_ALWAYS_ON_OUT -p udp --dport $CL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# NTP outbound on port 123 (UDP)
iptables -A $CHAIN_ALWAYS_ON_OUT -p udp --dport $NTP_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Titan builder bundle endpoints (always on)
# Security note: This is a side channel.
# While the operator will not be able to see the content of the packets, 
# they can observe the presence or absence of packets. 
iptables -A $CHAIN_ALWAYS_ON_OUT -p tcp -d $TITAN_BUILDER_IP --dport $TITAN_BUNDLE_PORT_HTTPS \
    -m conntrack --ctstate NEW -j ACCEPT

# Flashbots bundle endpoints (always on)
# Security note: This is a side channel.
# While the operator will not be able to see the content of the packets, 
# they can observe the presence or absence of packets.
iptables -A $CHAIN_ALWAYS_ON_OUT -p tcp -d $FLASHBOTS_BUNDLE_IP1,$FLASHBOTS_BUNDLE_IP2 --dport $HTTPS_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Return from ALWAYS_ON_OUT back to caller (OUTPUT chain -> MODE_SELECTOR_OUT) 
iptables -A $CHAIN_ALWAYS_ON_OUT -j RETURN

###########################################################################
# (8) MAINTENANCE_IN: Inbound rules for Maintenance Mode
###########################################################################
# SSH data plane on port 10022
iptables -A $CHAIN_MAINTENANCE_IN -p tcp --dport $SSH_DATA_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# SSH Registry port (not used in production mode)
iptables -A $CHAIN_MAINTENANCE_IN -p tcp --dport $SSH_REGISTER_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# EL P2P inbound on port 30303 (TCP + UDP)
iptables -A $CHAIN_MAINTENANCE_IN -p tcp --dport $EL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A $CHAIN_MAINTENANCE_IN -p udp --dport $EL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Return from MAINTENANCE_IN back to caller (INPUT chain -> END) 
iptables -A $CHAIN_MAINTENANCE_IN -j RETURN

###########################################################################
# (9) MAINTENANCE_OUT: Outbound rules for Maintenance Mode
###########################################################################
# Block Flashbots protect tx endpoints during maintenance
iptables -A $CHAIN_MAINTENANCE_OUT -d $FLASHBOTS_TX_IP1,$FLASHBOTS_TX_IP2 -j DROP

# DNS (UDP/TCP 53)
# Note: Searchers will only have DNS in maintenance mode! 
iptables -A $CHAIN_MAINTENANCE_OUT -p udp --dport $DNS_PORT \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A $CHAIN_MAINTENANCE_OUT -p tcp --dport $DNS_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# HTTP / HTTPS
iptables -A $CHAIN_MAINTENANCE_OUT -p tcp --dport $HTTP_PORT \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A $CHAIN_MAINTENANCE_OUT -p tcp --dport $HTTPS_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# EL P2P (30303) outbound only in Maintenance
iptables -A $CHAIN_MAINTENANCE_OUT -p tcp --dport $EL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A $CHAIN_MAINTENANCE_OUT -p udp --dport $EL_P2P_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# SSH Registry port (not used in production mode)
iptables -A $CHAIN_MAINTENANCE_OUT -p tcp --dport $SSH_REGISTER_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Return from MAINTENANCE_OUT back to caller (OUTPUT chain -> END) 
iptables -A $CHAIN_MAINTENANCE_OUT -j RETURN

###########################################################################
# (10) PRODUCTION_IN: Inbound rules for Production Mode
###########################################################################
# Return from PRODUCTION_IN back to caller (INPUT chain -> END) 
iptables -A $CHAIN_PRODUCTION_IN -j RETURN

###########################################################################
# (11) PRODUCTION_OUT: Outbound rules for Production Mode
# IP whitelisted for builder IPs
###########################################################################
# Titan state diff WSS
iptables -A $CHAIN_PRODUCTION_OUT -p tcp -d $TITAN_BUILDER_IP --dport $TITAN_STATE_DIFF_PORT_WSS \
    -m conntrack --ctstate NEW -j ACCEPT

# Flashbots protect tx endpoints (production only)
iptables -A $CHAIN_PRODUCTION_OUT -p tcp -d $FLASHBOTS_TX_IP1,$FLASHBOTS_TX_IP2 --dport $HTTPS_PORT \
    -m conntrack --ctstate NEW -j ACCEPT

# Return from PRODUCTION_OUT back to caller (OUTPUT chain -> END) 
iptables -A $CHAIN_PRODUCTION_OUT -j RETURN

###########################################################################
# (12) Start in Maintenance Mode
###########################################################################
iptables -A $CHAIN_MODE_SELECTOR_IN  -j $CHAIN_MAINTENANCE_IN
iptables -A $CHAIN_MODE_SELECTOR_OUT -j $CHAIN_MAINTENANCE_OUT

# Set initial state
echo "maintenance" > /etc/searcher-network.state

###########################################################################
# (13) Allow loopback traffic
###########################################################################
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

echo "Firewall initialized in Maintenance Mode."

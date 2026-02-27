#!/bin/bash
set -eu

# Project-specific dynamic configuration for bob-l2
# Called by fetch-config.sh with mode (qemu/vault) and config path

MODE="$1"
CONFIG_PATH="$2"

if [ "$MODE" = "qemu" ]; then
    # Local QEMU development configuration
    # GATEWAY is exported by the common fetch-config.sh
    cat <<EOF >> "$CONFIG_PATH"
CONFIG_NETWORK_ID='12345'
CONFIG_NETWORK_NAME='local-testnet'
CONFIG_JWT_SECRET='1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
CONFIG_EL_STATIC_PEERS='enode://abc123@${GATEWAY}:30303'
CONFIG_EL_PEERS_IPS='${GATEWAY}'
CONFIG_SIMULATOR_RPC_URL='http://${GATEWAY}:8545'
CONFIG_SIMULATOR_WS_URL='ws://${GATEWAY}:8546'
CONFIG_SIMULATOR_IP='${GATEWAY}'
EOF
    
elif [ "$MODE" = "vault" ]; then
    # Production configuration from Vault
    # get_data_value and get_ips_from_uris are exported by fetch-config.sh
    
    network_id=$(get_data_value network_id)
    network_name=$(get_data_value network_name)
    jwt_secret=$(get_data_value jwt_secret)
    
    el_static_peers=$(get_data_value el_static_peers | jq -r 'join(",")')
    el_peers_ips=$(get_ips_from_uris "$el_static_peers" | tr '\n' ',' | sed 's/,$//')
    
    simulator_rpc_url=$(get_data_value simulator_rpc_url)
    simulator_ws_url=$(get_data_value simulator_ws_url)
    simulator_ip=$(get_ips_from_uris "$simulator_rpc_url" | head -1)
    
    cat <<EOF >> "$CONFIG_PATH"
CONFIG_NETWORK_ID='${network_id}'
CONFIG_NETWORK_NAME='${network_name}'
CONFIG_JWT_SECRET='${jwt_secret}'
CONFIG_EL_STATIC_PEERS='${el_static_peers}'
CONFIG_EL_PEERS_IPS='${el_peers_ips}'
CONFIG_SIMULATOR_RPC_URL='${simulator_rpc_url}'
CONFIG_SIMULATOR_WS_URL='${simulator_ws_url}'
CONFIG_SIMULATOR_IP='${simulator_ip}'
EOF
fi

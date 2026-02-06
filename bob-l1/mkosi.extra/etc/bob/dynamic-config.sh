#!/bin/sh
set -eu

# Project-specific dynamic configuration for bob-l1
# Called by fetch-config.sh with mode (qemu/vault) and config path

MODE="$1"
CONFIG_PATH="$2"

if [ "$MODE" = "qemu" ]; then
    # Local QEMU development configuration
    # GATEWAY is exported by the common fetch-config.sh
    cat <<EOF >> "$CONFIG_PATH"
CONFIG_NETWORK_ID='1'
CONFIG_NETWORK_NAME='mainnet'
CONFIG_JWT_SECRET='1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
CONFIG_CL_STATIC_PEERS=''
CONFIG_EL_STATIC_PEERS='enode://abc123@${GATEWAY}:30303'
CONFIG_TITAN_IP='52.207.17.217'
CONFIG_FLASHBOTS_BUNDLE_1='18.221.59.61'
CONFIG_FLASHBOTS_BUNDLE_2='3.15.88.156'
CONFIG_FLASHBOTS_TX_STREAM_1='3.136.107.142'
CONFIG_FLASHBOTS_TX_STREAM_2='3.149.14.12'
EOF
    
elif [ "$MODE" = "vault" ]; then
    # Production configuration from Vault
    # get_data_value and get_ips_from_uris are exported by fetch-config.sh
    
    # For bob-l1, we might not have Vault set up yet
    # This is a placeholder for when Vault integration is added
    echo "Warning: Vault configuration not yet implemented for bob-l1"
    echo "Using environment variables or defaults..."
    
    # You can add Vault-based configuration here when ready
    # For now, we can use environment variables as fallback
    cat <<EOF >> "$CONFIG_PATH"
CONFIG_NETWORK_ID='${CONFIG_NETWORK_ID:-1}'
CONFIG_NETWORK_NAME='${CONFIG_NETWORK_NAME:-mainnet}'
CONFIG_JWT_SECRET='${CONFIG_JWT_SECRET:-}'
CONFIG_CL_STATIC_PEERS='${CONFIG_CL_STATIC_PEERS:-}'
CONFIG_EL_STATIC_PEERS='${CONFIG_EL_STATIC_PEERS:-}'
CONFIG_TITAN_IP='${CONFIG_TITAN_IP:-52.207.17.217}'
CONFIG_FLASHBOTS_BUNDLE_1='${CONFIG_FLASHBOTS_BUNDLE_1:-18.221.59.61}'
CONFIG_FLASHBOTS_BUNDLE_2='${CONFIG_FLASHBOTS_BUNDLE_2:-3.15.88.156}'
CONFIG_FLASHBOTS_TX_STREAM_1='${CONFIG_FLASHBOTS_TX_STREAM_1:-3.136.107.142}'
CONFIG_FLASHBOTS_TX_STREAM_2='${CONFIG_FLASHBOTS_TX_STREAM_2:-3.149.14.12}'
EOF
fi

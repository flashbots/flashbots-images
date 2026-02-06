#!/bin/sh
set -eu -o pipefail

# Common configuration fetching script for FlashBox (bob-l1 and bob-l2)
# This script provides shared functionality for configuration management
# Project-specific configuration should be done via /etc/bob/dynamic-config.sh

CONFIG_PATH=/etc/bob/config.env
OBSERVABILITY_CONFIG_PATH=/etc/flashbox/observability-config.json

# Don't override if config already exists
if [ -f "$CONFIG_PATH" ]; then
    echo "Config already exists at $CONFIG_PATH, skipping"
    exit 0
fi

# Helper functions
fetch_metadata_value() {
    curl -s \
        --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/$1"
}

get_ips_from_uris() {
    # Extract IP addresses from URIs
    echo "$1" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' || echo ""
}

write_observability_config() {
    local metrics_flashbots_url="$1"
    local metrics_flashbots_username="$2"
    local metrics_flashbots_password="$3"
    local metrics_searcher_url="$4"
    local metrics_searcher_auth="$5"
    
    # Extract IPs for firewall rules
    local metrics_endpoint_1=""
    local metrics_endpoint_2=""
    
    if [ -n "$metrics_flashbots_url" ]; then
        metrics_endpoint_1=$(get_ips_from_uris "$metrics_flashbots_url" | head -1)
    fi
    if [ -n "$metrics_searcher_url" ]; then
        metrics_endpoint_2=$(get_ips_from_uris "$metrics_searcher_url" | head -1)
    fi
    
    # Append observability config to main config
    cat <<EOF >> "$CONFIG_PATH"
CONFIG_METRICS_FLASHBOTS_URL='${metrics_flashbots_url}'
CONFIG_METRICS_FLASHBOTS_USERNAME='${metrics_flashbots_username}'
CONFIG_METRICS_FLASHBOTS_PASSWORD='${metrics_flashbots_password}'
CONFIG_METRICS_SEARCHER_URL='${metrics_searcher_url}'
CONFIG_METRICS_SEARCHER_AUTH='${metrics_searcher_auth}'
METRICS_ENDPOINT_1='${metrics_endpoint_1}'
METRICS_ENDPOINT_2='${metrics_endpoint_2}'
EOF
    
    # Create observability config for Prometheus if metrics are configured
    if [ -n "$metrics_flashbots_url" ] || [ -n "$metrics_searcher_url" ]; then
        mkdir -p /etc/flashbox
        cat <<EOF > "$OBSERVABILITY_CONFIG_PATH"
{
  "remote_write_flashbots_url": "${metrics_flashbots_url}",
  "remote_write_flashbots_username": "${metrics_flashbots_username}",
  "remote_write_flashbots_password": "${metrics_flashbots_password}",
  "remote_write_flashbots_auth": $([ -n "${metrics_flashbots_username}" ] && echo '"true"' || echo '""'),
  "remote_write_searcher_url": "${metrics_searcher_url}",
  "remote_write_searcher_auth": "${metrics_searcher_auth}"
}
EOF
        echo "Observability configuration written to $OBSERVABILITY_CONFIG_PATH"
    fi
}

# Check for local QEMU development environment
if dmidecode -s system-manufacturer 2>/dev/null | grep -q "QEMU" && \
   [ -f /etc/systemd/system/serial-console.service ]; then
    echo "Running in local QEMU dev image, using default test values"
    
    # Get default gateway (host in QEMU user-mode networking)
    GATEWAY=$(ip route | awk '/default/ {print $3}')
    if [ -z "$GATEWAY" ]; then
        echo "Warning: Could not detect gateway, falling back to 10.0.2.2"
        GATEWAY="10.0.2.2"
    fi
    
    # Export gateway for custom script
    export GATEWAY
    
    # Call project-specific configuration if it exists
    if [ -x /etc/bob/dynamic-config.sh ]; then
        echo "Running project-specific configuration..."
        /etc/bob/dynamic-config.sh qemu "$CONFIG_PATH"
    else
        echo "Warning: No project-specific configuration found at /etc/bob/dynamic-config.sh"
    fi
    
    # Add empty observability config for local dev
    write_observability_config "" "" "" "" ""
    
    exit 0
fi

# Production configuration using Vault
echo "Fetching configuration from Vault..."

# Get instance metadata
instance_name=$(fetch_metadata_value "name")
vault_addr=$(fetch_metadata_value "vault_addr")
vault_auth_mount=$(fetch_metadata_value "vault_auth_mount_gcp")
vault_kv_path=$(fetch_metadata_value "vault_kv_path")
vault_kv_common_suffix=$(fetch_metadata_value "vault_kv_common_suffix")

# Authenticate with Vault using GCP identity
gcp_token=$(curl \
  --header "Metadata-Flavor: Google" \
  --data-urlencode "audience=http://vault/$instance_name" \
  --data-urlencode "format=full" \
  "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity")

vault_token=$(curl \
    --data "$(printf '{"role":"%s","jwt":"%s"}' "$instance_name" "$gcp_token")" \
    "${vault_addr}/v1/${vault_auth_mount}/login" | \
    jq -r .auth.client_token)

# Fetch common and instance-specific data
common_data=$(curl \
    --header "X-Vault-Token: ${vault_token}" \
    "${vault_addr}/v1/${vault_kv_path}/node/${vault_kv_common_suffix}" |
    jq -c .data.data)
    
secret_data=$(curl \
    --header "X-Vault-Token: ${vault_token}" \
    "${vault_addr}/v1/${vault_kv_path}/node/${instance_name}" |
    jq -c .data.data)

# Merge data objects
data=$(echo "$common_data $secret_data" | jq -s 'add')

# Helper to get values from merged data
get_data_value() {
    echo "$data" | jq -rc --arg key "$1" '.[$key] // ""'
}

# Export data for project-specific script
export VAULT_DATA="$data"
export -f get_data_value
export -f get_ips_from_uris

# Call project-specific configuration
if [ -x /etc/bob/dynamic-config.sh ]; then
    echo "Running project-specific configuration..."
    /etc/bob/dynamic-config.sh vault "$CONFIG_PATH"
else
    echo "Error: No project-specific configuration found at /etc/bob/dynamic-config.sh"
    exit 1
fi

# Fetch observability configuration
metrics_flashbots_url=$(get_data_value metrics_flashbots_url)
metrics_flashbots_username=$(get_data_value metrics_flashbots_username)
metrics_flashbots_password=$(get_data_value metrics_flashbots_password)
metrics_searcher_url=$(get_data_value metrics_searcher_url)
metrics_searcher_auth=$(get_data_value metrics_searcher_auth)

# Write observability configuration
write_observability_config \
    "$metrics_flashbots_url" \
    "$metrics_flashbots_username" \
    "$metrics_flashbots_password" \
    "$metrics_searcher_url" \
    "$metrics_searcher_auth"

echo "Configuration successfully fetched and written to $CONFIG_PATH"

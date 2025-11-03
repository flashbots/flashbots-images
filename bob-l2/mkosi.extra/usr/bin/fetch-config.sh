#!/bin/sh
set -eu -o pipefail

# This script fetches couple of pre-defined keys from Vault
# and writes them to /etc/bob/config.env as:
#   CONFIG_{KEY}='{VALUE}'

CONFIG_PATH=/etc/bob/config.env

if dmidecode -s system-manufacturer 2>/dev/null | grep -q "QEMU"; then
    echo "Running in local QEMU, using hardcoded metadata values"

    cat <<EOF >> "$CONFIG_PATH"
CONFIG_NETWORK_ID='12345'
CONFIG_NETWORK_NAME='local-testnet'
CONFIG_JWT_SECRET='1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
CONFIG_EL_STATIC_PEERS='enode://abc123@192.168.1.10:30303'
CONFIG_EL_PEERS_IPS='192.168.1.10'
CONFIG_SIMULATOR_RPC_URL='http://192.168.1.100:8545'
CONFIG_SIMULATOR_WS_URL='ws://192.168.1.100:8546'
CONFIG_SIMULATOR_IP='192.168.1.100'
EOF

    # Ideally, this logic should be somewhere else, but it's fine for now
    chattr -i /etc/resolv.conf || true
    echo "nameserver 1.1.1.1" > /etc/resolv.conf

    exit 0
fi

fetch_metadata_value() {
    curl -s \
        --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/$1"
}

instance_name=$(fetch_metadata_value "name")
vault_addr=$(fetch_metadata_value "vault_addr")
vault_auth_mount=$(fetch_metadata_value "vault_auth_mount_gcp")
vault_kv_path=$(fetch_metadata_value "vault_kv_path")
vault_kv_common_suffix=$(fetch_metadata_value "vault_kv_common_suffix")

gcp_token=$(curl \
  --header "Metadata-Flavor: Google" \
  --data-urlencode "audience=http://vault/$instance_name" \
  --data-urlencode "format=full" \
  "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity")

vault_token=$(curl \
    --data "$(printf '{"role":"%s","jwt":"%s"}' "$instance_name" "$gcp_token")" \
    "${vault_addr}/v1/${vault_auth_mount}/login" | \
    jq -r .auth.client_token)

common_data=$(curl \
    --header "X-Vault-Token: ${vault_token}" \
    "${vault_addr}/v1/${vault_kv_path}/node/${vault_kv_common_suffix}" |
    jq -c .data.data)
secret_data=$(curl \
    --header "X-Vault-Token: ${vault_token}" \
    "${vault_addr}/v1/${vault_kv_path}/node/${instance_name}" |
    jq -c .data.data)

# merge objects
data=$(echo "$common_data $secret_data" | jq -s 'add')

get_data_value() {
    echo "$data" | jq -rc --arg key "$1" '.[$key]'
}

get_ips_from_uris() {
    # eh, good enough for our usecase
    echo "$1" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}'
}

network_id=$(get_data_value network_id)
network_name=$(get_data_value network_name)
jwt_secret=$(get_data_value jwt_secret)

el_static_peers=$(get_data_value el_static_peers | jq -r 'join(",")')
el_peers_ips=$(get_ips_from_uris "$el_static_peers" | tr '\n' ',' | sed 's/,$//')

simulator_rpc_url=$(get_data_value simulator_rpc_url)
simulator_ws_url=$(get_data_value simulator_ws_url)
simulator_ip=$(get_ips_from_uris "$simulator_rpc_url")

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

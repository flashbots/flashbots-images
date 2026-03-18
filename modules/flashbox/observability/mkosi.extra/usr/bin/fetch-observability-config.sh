#!/bin/sh
set -eu -o pipefail

# Fetches observability configuration (metrics endpoint credentials) and writes:
#   /etc/flashbox/observability-config.json  — consumed by gomplate for Prometheus config
#   /etc/flashbox/observability.env          — sourced by firewall for metrics endpoint IP
#
# On failure: logs a warning and writes empty defaults. Prometheus runs locally
# without remote_write. This is intentional — observability should never block boot.

OBSERVABILITY_CONFIG_PATH=/etc/flashbox/observability-config.json
OBSERVABILITY_ENV_PATH=/etc/flashbox/observability.env

write_config() {
    local url="${1:-}"
    local username="${2:-}"
    local password="${3:-}"

    # Extract IP for firewall rules
    local metrics_endpoint=""
    if [ -n "$url" ]; then
        metrics_endpoint=$(echo "$url" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1 || true)
    fi

    mkdir -p /etc/flashbox

    # JSON config for Prometheus gomplate template
    cat <<EOF > "$OBSERVABILITY_CONFIG_PATH"
{
  "remote_write_flashbots_url": "${url}",
  "remote_write_flashbots_username": "${username}",
  "remote_write_flashbots_password": "${password}",
  "remote_write_flashbots_auth": $([ -n "${username}" ] && echo '"true"' || echo '""')
}
EOF

    # Env file for firewall (sourced by init-firewall.sh)
    cat <<EOF > "$OBSERVABILITY_ENV_PATH"
METRICS_ENDPOINT='${metrics_endpoint}'
EOF

    echo "Observability config written (endpoint: ${metrics_endpoint:-none})"
}

# Don't override if config already exists
if [ -f "$OBSERVABILITY_CONFIG_PATH" ]; then
    echo "Observability config already exists, skipping"
    exit 0
fi

# Local QEMU dev: no remote_write
if dmidecode -s system-manufacturer 2>/dev/null | grep -q "QEMU" && \
   [ -f /etc/systemd/system/serial-console.service ]; then
    echo "QEMU dev environment, writing empty observability config"
    write_config "" "" ""
    exit 0
fi

# Production: fetch from Vault (non-fatal on failure)
echo "Fetching observability config from Vault..."

fetch_metadata_value() {
    curl -sf \
        --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/$1"
}

if ! instance_name=$(fetch_metadata_value "name") || \
   ! vault_addr=$(fetch_metadata_value "vault_addr") || \
   ! vault_auth_mount=$(fetch_metadata_value "vault_auth_mount_gcp") || \
   ! vault_kv_path=$(fetch_metadata_value "vault_kv_path") || \
   ! vault_kv_common_suffix=$(fetch_metadata_value "vault_kv_common_suffix"); then
    echo "WARNING: Could not fetch GCP metadata, writing empty observability config"
    write_config "" "" ""
    exit 0
fi

# Authenticate with Vault using GCP identity
gcp_token=$(curl -sf \
    --header "Metadata-Flavor: Google" \
    --data-urlencode "audience=http://vault/$instance_name" \
    --data-urlencode "format=full" \
    "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity") || true

if [ -z "${gcp_token:-}" ]; then
    echo "WARNING: Could not get GCP identity token, writing empty observability config"
    write_config "" "" ""
    exit 0
fi

vault_token=$(curl -sf \
    --data "$(printf '{"role":"%s","jwt":"%s"}' "$instance_name" "$gcp_token")" \
    "${vault_addr}/v1/${vault_auth_mount}/login" | \
    jq -r .auth.client_token) || true

if [ -z "${vault_token:-}" ]; then
    echo "WARNING: Could not authenticate with Vault, writing empty observability config"
    write_config "" "" ""
    exit 0
fi

# Fetch common data (observability keys live here)
common_data=$(curl -sf \
    --header "X-Vault-Token: ${vault_token}" \
    "${vault_addr}/v1/${vault_kv_path}/node/${vault_kv_common_suffix}" |
    jq -c .data.data) || true

if [ -z "${common_data:-}" ]; then
    echo "WARNING: Could not fetch Vault data, writing empty observability config"
    write_config "" "" ""
    exit 0
fi

get_value() {
    echo "$common_data" | jq -rc --arg key "$1" '.[$key] // ""'
}

write_config \
    "$(get_value metrics_flashbots_url)" \
    "$(get_value metrics_flashbots_username)" \
    "$(get_value metrics_flashbots_password)"

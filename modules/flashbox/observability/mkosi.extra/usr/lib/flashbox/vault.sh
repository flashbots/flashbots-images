#!/bin/sh
# Vault auth (GCP backend) and secret fetch.
#
# Reads bootstrap config from GCE instance metadata, authenticates to Vault
# using the instance identity JWT, fetches the shared secret blob, and
# exports every key in the blob as an uppercase env var.

_gce_metadata_get() {
    curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/$1"
}

# Authenticate to Vault and fetch the shared secret blob. Each key in the
# secret is exported as `<KEY>=<value>` verbatim — store keys in Vault with
# the exact casing you want as the env var name (UPPER_SNAKE_CASE by
# convention).
#
# Returns non-zero on any failure (metadata unreachable, auth failure,
# secret not found, malformed response). Exports nothing in that case.
vault_fetch() {
    local instance_name vault_addr auth_mount kv_path kv_common_suffix
    instance_name=$(_gce_metadata_get name) || return 1
    vault_addr=$(_gce_metadata_get attributes/vault_addr) || return 1
    auth_mount=$(_gce_metadata_get attributes/vault_auth_mount_gcp) || return 1
    kv_path=$(_gce_metadata_get attributes/vault_kv_path) || return 1
    kv_common_suffix=$(_gce_metadata_get attributes/vault_kv_common_suffix) || return 1

    local gcp_token
    gcp_token=$(curl -sf \
        --header "Metadata-Flavor: Google" \
        --data-urlencode "audience=http://vault/${instance_name}" \
        --data-urlencode "format=full" \
        "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity") || return 1
    [ -n "$gcp_token" ] || return 1

    local vault_token
    vault_token=$(curl -sf \
        --data "$(printf '{"role":"%s","jwt":"%s"}' "$instance_name" "$gcp_token")" \
        "${vault_addr}/v1/${auth_mount}/login" \
        | jq -re .auth.client_token) || return 1

    local secret_data
    secret_data=$(curl -sf \
        --header "X-Vault-Token: ${vault_token}" \
        "${vault_addr}/v1/${kv_path}/node/${kv_common_suffix}" \
        | jq -ce .data.data) || return 1

    local keys
    keys=$(echo "$secret_data" | jq -r 'keys[]') || return 1

    local key value
    for key in $keys; do
        value=$(echo "$secret_data" | jq -rc --arg k "$key" '.[$k] // ""')
        export "${key}=${value}"
    done
}

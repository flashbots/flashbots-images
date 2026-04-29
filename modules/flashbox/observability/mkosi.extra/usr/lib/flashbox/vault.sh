#!/bin/sh
# Vault auth (GCP backend) and KV reads.

# Authenticate to Vault using the GCE instance identity JWT.
# Args: $1 = instance name (used as audience and role), $2 = vault addr,
#       $3 = vault auth mount path (e.g. "auth/gcp/l1-flashbox")
# Stdout: vault client token. Returns non-zero on failure.
vault_login_gcp() {
    local instance_name="$1" vault_addr="$2" auth_mount="$3"

    local gcp_token
    gcp_token=$(curl -sf \
        --header "Metadata-Flavor: Google" \
        --data-urlencode "audience=http://vault/${instance_name}" \
        --data-urlencode "format=full" \
        "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity") || return 1

    [ -n "$gcp_token" ] || return 1

    curl -sf \
        --data "$(printf '{"role":"%s","jwt":"%s"}' "$instance_name" "$gcp_token")" \
        "${vault_addr}/v1/${auth_mount}/login" \
        | jq -re .auth.client_token
}

# Read a Vault KV v2 secret.
# Args: $1 = vault addr, $2 = vault token, $3 = full KV API path
#       (e.g. "secret/data/foo/bar")
# Stdout: the secret's `.data.data` JSON. Returns non-zero on failure.
vault_kv_get() {
    local vault_addr="$1" token="$2" path="$3"

    curl -sf \
        --header "X-Vault-Token: ${token}" \
        "${vault_addr}/v1/${path}" \
        | jq -ce .data.data
}

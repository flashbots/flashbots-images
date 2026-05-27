#!/bin/sh
# Vault auth (GCP backend) + fetch/validate the Prometheus remote_write secret.
# Sourced by flashbox-observability-setup.
#
# vault_fetch authenticates with the GCE instance-identity JWT, reads the
# shared secret, and exports the four metrics variables — each checked against
# its expected format, so a malformed or tampered value can never reach the
# rendered config (and can't carry shell/YAML metacharacters). Any failure
# returns non-zero and exports nothing usable; the caller then writes no config.
#
# Note: values are piped with `printf '%s'`, never `echo` — dash's echo
# interprets backslash escapes (\n, \c, ...) and would corrupt JSON / values.

vault_fetch() {
    local addr mount role kv suffix jwt token data

    # 1. Bootstrap config from GCE instance metadata.
    addr=$(curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/vault_addr") || return 1
    mount=$(curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/vault_auth_mount_gcp") || return 1
    role=$(curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/vault_role") || return 1
    kv=$(curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/vault_kv_path") || return 1
    suffix=$(curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/attributes/vault_kv_common_suffix") || return 1

    # 2. Authenticate: GCE identity JWT -> Vault token.
    jwt=$(curl -sf --header "Metadata-Flavor: Google" \
        --data-urlencode "audience=http://vault/${role}" \
        --data-urlencode "format=full" \
        "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity") || return 1
    token=$(curl -sf \
        --data "$(printf '{"role":"%s","jwt":"%s"}' "$role" "$jwt")" \
        "${addr}/v1/${mount}/login" | jq -re .auth.client_token) || return 1

    # 3. Read the shared secret blob.
    data=$(curl -sf --header "X-Vault-Token: ${token}" \
        "${addr}/v1/${kv}/node/${suffix}" | jq -ce .data.data) || return 1

    # 4. Extract each variable and validate it against its expected format.
    METRICS_FLASHBOTS_WORKSPACE=$(printf '%s' "$data" | jq -re .METRICS_FLASHBOTS_WORKSPACE) || return 1
    printf '%s' "$METRICS_FLASHBOTS_WORKSPACE" | grep -qE '^ws-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
        || { echo "vault_fetch: WORKSPACE is not an AMP workspace id" >&2; return 1; }

    METRICS_FLASHBOTS_REGION=$(printf '%s' "$data" | jq -re .METRICS_FLASHBOTS_REGION) || return 1
    printf '%s' "$METRICS_FLASHBOTS_REGION" | grep -qE '^[a-z]{2}-[a-z]+-[0-9]+$' \
        || { echo "vault_fetch: REGION is not an AWS region" >&2; return 1; }

    METRICS_FLASHBOTS_ACCESS_KEY=$(printf '%s' "$data" | jq -re .METRICS_FLASHBOTS_ACCESS_KEY) || return 1
    printf '%s' "$METRICS_FLASHBOTS_ACCESS_KEY" | grep -qE '^[A-Z0-9]{20}$' \
        || { echo "vault_fetch: ACCESS_KEY is not an AWS access key id" >&2; return 1; }

    METRICS_FLASHBOTS_SECRET_KEY=$(printf '%s' "$data" | jq -re .METRICS_FLASHBOTS_SECRET_KEY) || return 1
    printf '%s' "$METRICS_FLASHBOTS_SECRET_KEY" | grep -qE '^[A-Za-z0-9/+]{40}$' \
        || { echo "vault_fetch: SECRET_KEY is not an AWS secret key" >&2; return 1; }

    # 5. All present and well-formed — publish to the environment for envsubst.
    export METRICS_FLASHBOTS_WORKSPACE METRICS_FLASHBOTS_REGION \
           METRICS_FLASHBOTS_ACCESS_KEY METRICS_FLASHBOTS_SECRET_KEY
}

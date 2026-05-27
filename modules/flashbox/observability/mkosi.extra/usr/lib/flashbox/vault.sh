#!/bin/sh
# Vault auth (GCP backend) and secret fetch.
#
# Reads bootstrap config from GCE instance metadata, authenticates to Vault
# using the instance identity JWT, fetches the shared secret blob, and
# exports the explicitly-requested keys as env vars.

_gce_metadata_get() {
    curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/$1"
}

# Authenticate to Vault and fetch the shared secret blob, then export ONLY
# the keys named in the arguments (an allowlist) — never the whole blob.
# Usage: vault_fetch KEY [KEY ...]. Keys are exported verbatim, so store them
# in Vault with the exact UPPER_SNAKE_CASE env var name you want. Each value
# is charset-validated before export to prevent env/YAML injection from a
# tampered secret; missing/empty/invalid values are skipped with a warning.
#
# On auth/fetch failure, logs a specific reason to stderr and returns
# non-zero without exporting anything.
vault_fetch() {
    local instance_name vault_addr auth_mount vault_role kv_path kv_common_suffix
    instance_name=$(_gce_metadata_get name) || {
        echo "WARNING: vault_fetch: could not read GCE metadata 'name'" >&2; return 1; }
    vault_addr=$(_gce_metadata_get attributes/vault_addr) || {
        echo "WARNING: vault_fetch: could not read GCE metadata 'vault_addr'" >&2; return 1; }
    auth_mount=$(_gce_metadata_get attributes/vault_auth_mount_gcp) || {
        echo "WARNING: vault_fetch: could not read GCE metadata 'vault_auth_mount_gcp'" >&2; return 1; }
    kv_path=$(_gce_metadata_get attributes/vault_kv_path) || {
        echo "WARNING: vault_fetch: could not read GCE metadata 'vault_kv_path'" >&2; return 1; }
    kv_common_suffix=$(_gce_metadata_get attributes/vault_kv_common_suffix) || {
        echo "WARNING: vault_fetch: could not read GCE metadata 'vault_kv_common_suffix'" >&2; return 1; }

    # vault_role is optional metadata. If set, it's used as the Vault GCP
    # auth role name (and as the JWT audience). If unset, fall back to the
    # instance name — preserves the L2 meva-uni convention of role-name=VM-name
    # for projects that go with per-VM roles.
    vault_role=$(_gce_metadata_get attributes/vault_role 2>/dev/null) || vault_role="$instance_name"

    local gcp_token
    gcp_token=$(curl -sf \
        --header "Metadata-Flavor: Google" \
        --data-urlencode "audience=http://vault/${vault_role}" \
        --data-urlencode "format=full" \
        "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity") || {
        echo "WARNING: vault_fetch: could not obtain GCP identity JWT from metadata server" >&2; return 1; }
    [ -n "$gcp_token" ] || {
        echo "WARNING: vault_fetch: GCP identity JWT was empty" >&2; return 1; }

    local vault_token
    vault_token=$(curl -sf \
        --data "$(printf '{"role":"%s","jwt":"%s"}' "$vault_role" "$gcp_token")" \
        "${vault_addr}/v1/${auth_mount}/login" \
        | jq -re .auth.client_token) || {
        echo "WARNING: vault_fetch: Vault GCP login failed (role=${vault_role}, mount=${auth_mount})" >&2; return 1; }

    local secret_data
    secret_data=$(curl -sf \
        --header "X-Vault-Token: ${vault_token}" \
        "${vault_addr}/v1/${kv_path}/node/${kv_common_suffix}" \
        | jq -ce .data.data) || {
        echo "WARNING: vault_fetch: KV read failed at ${kv_path}/node/${kv_common_suffix}" >&2; return 1; }

    # Export ONLY the requested keys (the allowlist passed as args). This
    # bounds what a tampered/compromised secret can inject into our env — an
    # unexpected key (PATH, LD_PRELOAD, ...) is never exported. Each value is
    # charset-restricted to block YAML/env injection via crafted values
    # (newlines, quotes, $, backticks, spaces).
    local key value
    for key in "$@"; do
        value=$(echo "$secret_data" | jq -rc --arg k "$key" '.[$k] // ""')
        if [ -z "$value" ]; then
            echo "WARNING: vault_fetch: key '${key}' missing or empty in secret" >&2
            continue
        fi
        case "$value" in
            *[!A-Za-z0-9._/+=-]*)
                echo "WARNING: vault_fetch: value for '${key}' has disallowed characters, skipping" >&2
                continue
                ;;
        esac
        export "${key}=${value}"
    done
}

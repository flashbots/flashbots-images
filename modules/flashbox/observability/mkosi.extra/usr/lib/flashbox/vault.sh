#!/bin/sh
# Vault auth (GCP backend) + validated fetch of named keys.
#
#   vault_login              -> echoes a Vault client token
#   vault_fetch TOKEN KEY... -> exports each named key after validating its value
#
# Only the keys the caller names are ever read or exported (no blob iteration),
# and every value is charset-checked before export, so a tampered secret cannot
# inject shell or YAML. If any requested key is missing or fails validation,
# vault_fetch returns non-zero and the caller writes no config.

_meta() {
    curl -sf --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/$1"
}

# Conservative allowlist: alphanumerics + the symbols our values legitimately
# use (AWS keys are base64 -> / + = ; region/workspace use - _ .). Everything
# else -- whitespace, quotes, $, backtick, ; | & < > \, newlines -- is rejected.
_safe() {
    case "$1" in
        *[!A-Za-z0-9._/+=-]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Authenticate with the GCE instance-identity JWT and echo a Vault token.
# The Vault GCP auth role is read from metadata (a shared role for this
# project); there is no per-VM fallback.
vault_login() {
    local addr mount role jwt
    addr=$(_meta attributes/vault_addr) || return 1
    mount=$(_meta attributes/vault_auth_mount_gcp) || return 1
    role=$(_meta attributes/vault_role) || return 1

    jwt=$(curl -sf --header "Metadata-Flavor: Google" \
        --data-urlencode "audience=http://vault/${role}" \
        --data-urlencode "format=full" \
        "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity") || return 1

    curl -sf \
        --data "$(printf '{"role":"%s","jwt":"%s"}' "$role" "$jwt")" \
        "${addr}/v1/${mount}/login" \
        | jq -re .auth.client_token
}

# vault_fetch TOKEN KEY [KEY...]
# Reads the shared (common) secret blob once, then exports each requested key
# after validation. Returns 1 if any key is missing or fails validation.
vault_fetch() {
    local token addr kv suffix data key value
    token=$1
    shift

    addr=$(_meta attributes/vault_addr) || return 1
    kv=$(_meta attributes/vault_kv_path) || return 1
    suffix=$(_meta attributes/vault_kv_common_suffix) || return 1

    data=$(curl -sf --header "X-Vault-Token: ${token}" \
        "${addr}/v1/${kv}/node/${suffix}" \
        | jq -ce .data.data) || return 1

    for key in "$@"; do
        value=$(echo "$data" | jq -re --arg k "$key" '.[$k]') || {
            echo "WARNING: vault_fetch: key '${key}' missing in secret" >&2
            return 1
        }
        _safe "$value" || {
            echo "WARNING: vault_fetch: value for '${key}' has unsafe characters" >&2
            return 1
        }
        export "${key}=${value}"
    done
}

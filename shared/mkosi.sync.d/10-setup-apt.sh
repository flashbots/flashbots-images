#!/usr/bin/env bash
set -euo pipefail

render_apt_source() {
    local snapshot="$1"
    local release="$2"
    local destination="$3"
    local mirror
    local valid_until

    if [[ "$snapshot" == "null" ]]; then
        mirror="https://deb.debian.org/debian"
        valid_until=""
    else
        mirror="https://snapshot.debian.org/archive/debian/${snapshot}"
        # Archived Release files can be older than their validity window. The
        # metadata must still carry a valid Debian archive signature.
        valid_until="Check-Valid-Until: no"
    fi

    cat > "$destination" <<EOF
Types: deb deb-src
URIs: $mirror
Suites: ${release} ${release}-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
$valid_until
EOF
}

main() {
    local snapshot

    # Add the only apt source used during the build. See
    # https://github.com/systemd/mkosi/issues/1755. Read Snapshot from mkosi's
    # effective configuration so callers may define it directly or by include.
    snapshot=$(jq -r .Snapshot /work/config.json)
    # RELEASE is supplied by mkosi to sync scripts.
    # shellcheck disable=SC2153
    render_apt_source "$snapshot" "$RELEASE" \
        "$SRCDIR/mkosi.builddir/mkosi.sources"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

#!/bin/sh
# URL / DNS / /etc/hosts helpers.
#
# Used by orchestrators that need to pin a FQDN → IPs mapping locally so
# that DNS resolution works without going to the network (e.g. when the
# searcher firewall blocks port 53 in production mode).

HOSTS_FILE=/etc/hosts

# Extract the bare hostname from a URL (or return the input verbatim if
# it's already a bare host). Strips scheme, path, port.
url_to_host() {
    echo "${1:-}" | sed -E 's|^[a-z]+://||; s|/.*||; s|:.*||'
}

# Resolve a URL (or bare host) to a space-separated list of IPv4 addresses.
# IPv4 literals are passed through unchanged; hostnames go through getent.
# Empty input or unresolvable host → empty output.
#
# Intended to be called *before* the host firewall locks down — at that
# point getent can still reach upstream DNS through systemd-resolved.
resolve_to_ips() {
    local input="${1:-}"
    [ -n "$input" ] || { echo ""; return; }

    local host
    host=$(url_to_host "$input")
    if echo "$host" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
        echo "$host"
    else
        getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/ *$//'
    fi
}

# Drop a sentinel-delimited block from /etc/hosts (no-op if not present).
# Each block is delimited by "# BEGIN <marker>" / "# END <marker>" lines
# so multiple consumers can manage their own sections independently.
# Args: $1 = marker name (e.g. "flashbox-observability")
hosts_clean_block() {
    local marker="$1"
    [ -f "$HOSTS_FILE" ] || return 0
    sed -i "/# BEGIN ${marker}/,/# END ${marker}/d" "$HOSTS_FILE"
}

# Replace a sentinel-delimited block in /etc/hosts with fresh entries:
# one line per IP, all mapped to the same hostname. Empty inputs leave
# the block dropped (no entries written).
# Args: $1 = marker, $2 = hostname, $3 = space-separated IPs
hosts_write_block() {
    local marker="$1" host="$2" ips="$3"
    hosts_clean_block "$marker"
    [ -n "$host" ] && [ -n "$ips" ] || return 0

    {
        echo "# BEGIN ${marker} (managed by flashbox)"
        for ip in $ips; do
            echo "$ip $host"
        done
        echo "# END ${marker}"
    } >> "$HOSTS_FILE"
}

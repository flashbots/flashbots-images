#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shared_config="$repo_root/shared/mkosi.conf"
source_generator="$repo_root/shared/mkosi.sync.d/10-setup-apt.sh"
keyring_path='/usr/share/keyrings/debian-archive-keyring.gpg'
test_snapshot='20260430T025253Z'

# Source the renderer without running the production entry point.
# shellcheck disable=SC1090
source "$source_generator"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

assert_common_source_policy() {
    local source_file="$1"
    local expected_uri="$2"

    grep -Fxq 'Types: deb deb-src' "$source_file" || fail 'source must include binary and source packages'
    grep -Fxq "URIs: $expected_uri" "$source_file" || fail "unexpected repository URI in $source_file"
    grep -Fxq 'Suites: trixie trixie-backports' "$source_file" || fail 'source must include trixie and trixie-backports'
    grep -Fxq 'Components: main' "$source_file" || fail 'source must include the main component'
    grep -Fxq "Signed-By: $keyring_path" "$source_file" || fail 'source must require the Debian archive keyring'
    ! grep -Eqi '(^|[[:space:]])Trusted([[:space:]]*:|=)' "$source_file" || fail 'source must not bypass signature verification with Trusted'
}

grep -Fxq 'RepositoryKeyCheck=yes' "$shared_config" || fail 'repository key checking must be enabled'
grep -Fxq 'RepositoryKeyFetch=no' "$shared_config" || fail 'repository key fetching must be disabled'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

snapshot_source="$tmpdir/snapshot.sources"
render_apt_source "$test_snapshot" trixie "$snapshot_source"
assert_common_source_policy "$snapshot_source" "https://snapshot.debian.org/archive/debian/$test_snapshot"
grep -Fxq 'Check-Valid-Until: no' "$snapshot_source" || fail 'historical snapshots must disable metadata expiry checks'

live_source="$tmpdir/live.sources"
render_apt_source null trixie "$live_source"
assert_common_source_policy "$live_source" 'https://deb.debian.org/debian'
if grep -Fq 'Check-Valid-Until:' "$live_source"; then
    fail 'live repositories must retain normal metadata expiry checks'
fi

echo 'Debian repository source rendering and key verification policy are configured correctly.'

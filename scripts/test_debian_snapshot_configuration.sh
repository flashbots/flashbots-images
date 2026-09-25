#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_CONFIG="$REPO_ROOT/shared/mkosi.conf"
SOURCE_GENERATOR="$REPO_ROOT/shared/mkosi.sync.d/10-setup-apt.sh"
FLAKE="$REPO_ROOT/flake.nix"
KEYRING_PATH='/usr/share/keyrings/debian-archive-keyring.gpg'
TEST_SNAPSHOT='20260430T025253Z'

# shellcheck disable=SC1090
source "$SOURCE_GENERATOR"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

assert_rendered_source() {
    local source_file="$1"
    local expected_uri="$2"
    local expect_snapshot="$3"

    [[ "$(grep -c '^Types:' "$source_file")" -eq 1 ]] || fail 'source must contain one stanza'
    grep -Fxq 'Types: deb deb-src' "$source_file" || fail 'source must retain binary and source packages'
    grep -Fxq "URIs: $expected_uri" "$source_file" || fail 'unexpected repository URI'
    grep -Fxq 'Suites: trixie trixie-backports' "$source_file" || fail 'source must retain configured suites'
    grep -Fxq 'Components: main' "$source_file" || fail 'source must retain the main component'
    grep -Fxq "Signed-By: $KEYRING_PATH" "$source_file" || fail 'source is not bound to the pinned keyring'
    ! grep -Eqi '(^|[[:space:]])Trusted([[:space:]]*:|=)' "$source_file" || fail 'Trusted bypass must not be present'
    ! grep -Eq '^URIs: http://' "$source_file" || fail 'repository transport must use HTTPS'

    if [[ "$expect_snapshot" == yes ]]; then
        grep -Fxq 'Check-Valid-Until: no' "$source_file" || fail 'snapshot needs explicit validity handling'
    elif grep -Fq 'Check-Valid-Until:' "$source_file"; then
        fail 'live repository must retain normal metadata validity checks'
    fi
}

render_source() {
    local snapshot="$1"
    local destination="$2"

    render_apt_source "$snapshot" trixie "$destination"
}

grep -Fxq 'RepositoryKeyCheck=yes' "$SHARED_CONFIG" || fail 'repository key checking must be explicit'
grep -Fxq 'RepositoryKeyFetch=no' "$SHARED_CONFIG" || fail 'repository key fetching must be disabled'
# The single-quoted strings below intentionally match literal shell and Nix syntax.
# shellcheck disable=SC2016
grep -Fq 'snapshot=$(jq -r .Snapshot /work/config.json)' "$SOURCE_GENERATOR" || \
    fail 'production snapshot selection must use mkosi effective configuration'
if grep -Fq 'MKOSI_CONFIG_JSON' "$SOURCE_GENERATOR"; then
    fail 'production snapshot selection must not accept an ambient alternate path'
fi

mapfile -t static_sources < <(find \
    "$REPO_ROOT/shared" "$REPO_ROOT/images" "$REPO_ROOT/modules" "$REPO_ROOT/mkosi.profiles" \
    -type f \( -name '*.list' -o -name '*.sources' \) -print)
[[ ${#static_sources[@]} -eq 0 ]] || fail 'static apt source creates a second repository path'
mapfile -t source_mounts < <(grep -Rhs '^SandboxTrees=.*sources\.list\.d' \
    "$REPO_ROOT/shared" "$REPO_ROOT/images" "$REPO_ROOT/modules" "$REPO_ROOT/mkosi.profiles")
[[ ${#source_mounts[@]} -eq 1 ]] || fail 'expected exactly one apt source sandbox mount'
[[ "${source_mounts[0]}" == 'SandboxTrees=mkosi.builddir/mkosi.sources:/etc/apt/sources.list.d/mkosi.sources' ]] || \
    fail 'apt source must use the shared generated sandbox mount'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

render_source "$TEST_SNAPSHOT" "$tmpdir/snapshot.sources"
assert_rendered_source "$tmpdir/snapshot.sources" \
    "https://snapshot.debian.org/archive/debian/$TEST_SNAPSHOT" yes

render_source null "$tmpdir/live.sources"
assert_rendered_source "$tmpdir/live.sources" 'https://deb.debian.org/debian' no

# Exercise the production entry point with a jq shim. The shim fails unless the
# script reads mkosi's fixed /work/config.json path rather than ambient input.
mkdir -p "$tmpdir/bin" "$tmpdir/production/mkosi.builddir"
cat > "$tmpdir/bin/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 3 && "$1" == '-r' && "$2" == '.Snapshot' && "$3" == '/work/config.json' ]]
printf '%s\n' "$EXPECTED_SNAPSHOT"
EOF
chmod +x "$tmpdir/bin/jq"
PATH="$tmpdir/bin:$PATH" \
EXPECTED_SNAPSHOT="$TEST_SNAPSHOT" \
MKOSI_CONFIG_JSON="$tmpdir/not-production.json" \
RELEASE=trixie \
SRCDIR="$tmpdir/production" \
    "$SOURCE_GENERATOR"
assert_rendered_source "$tmpdir/production/mkosi.builddir/mkosi.sources" \
    "https://snapshot.debian.org/archive/debian/$TEST_SNAPSHOT" yes

# shellcheck disable=SC2016
grep -Fq '${pkgsForSystem.debian-archive-keyring}/share/keyrings/debian-archive-keyring.pgp' "$FLAKE" || \
    fail 'keyring must come from the flake-locked Nixpkgs package'
# shellcheck disable=SC2016
grep -Fq '"$out/usr/share/keyrings/debian-archive-keyring.gpg"' "$FLAKE" || \
    fail 'sandbox tree must expose the keyring at the Signed-By path'
# shellcheck disable=SC2016
grep -Fq -- '--sandbox-tree=${debian-keyring-tree}' "$FLAKE" || fail 'mkosi wrapper must mount the pinned keyring tree'

if grep -RqsE --exclude='test_debian_snapshot_configuration.sh' \
    '(^|[[:space:]])Trusted([[:space:]]*:|=)' \
    "$REPO_ROOT/shared" "$REPO_ROOT/images" "$REPO_ROOT/modules" "$REPO_ROOT/mkosi.profiles"; then
    fail 'repository configuration must not contain a Trusted bypass'
fi
if find "$REPO_ROOT/shared" "$REPO_ROOT/modules" "$REPO_ROOT/mkosi.profiles" \
    -type f \( -path '*/mkosi.extra/*' -o -path '*/mkosi.skeleton/*' \) \
    -exec grep -qsF "$KEYRING_PATH" {} +; then
    fail 'build trust root must not be copied into a guest ExtraTrees path'
fi
if find "$REPO_ROOT/shared" "$REPO_ROOT/images" "$REPO_ROOT/modules" "$REPO_ROOT/mkosi.profiles" \
    -type f -name '*.conf' \
    -exec grep -qsE '^[[:space:]]*Packages=.*debian-archive-keyring|^[[:space:]]+debian-archive-keyring([[:space:]]|$)' {} +; then
    fail 'build trust root must not be installed as a guest package'
fi

echo 'Debian repositories are content-pinned and signature-checked.'

#!/usr/bin/env bash
#
# version-bump.sh — bump BuilderNet downloader-unit versions + sha256sums.
#
# Updates the *_TAG, *_ARTIFACT and *_SHA256SUM fields of the systemd
# "*-downloader.service" units from the matching GitHub release assets.
# Checksums come from the release's published `sha256sums.txt` (falling
# back to hashing the downloaded artifact), discovered via the `gh` CLI.
#
# Supported services: flowproxy, rbuilder-operator, rbuilder-rebalancer
#
# Usage:
#   scripts/version-bump.sh --rbuilder-operator v1.7.15 --rbuilder-rebalancer v1.7.15
#   scripts/version-bump.sh --flowproxy 2.4.3            # leading 'v' optional
#   scripts/version-bump.sh --rbuilder-operator latest   # resolve newest release
#   scripts/version-bump.sh --flowproxy v2.4.3 --dry-run # preview the diff only
#
# One flag per service; combine as many as you like in a single invocation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SVC_DIR="$REPO_ROOT/mkosi.images/buildernet/mkosi.extra/etc/systemd/system"

OWNER="flashbots"
DRY_RUN=false

SERVICES=(flowproxy rbuilder-operator rbuilder-rebalancer)

# Per-service metadata. Artifact templates use %TAG% as the version placeholder;
# the rendered artifact name is both the release asset we fetch and the key we
# look up in sha256sums.txt, so it must match the release exactly.
declare -A SVC_REPO=(
  [flowproxy]="flowproxy-private"
  [rbuilder-operator]="rbuilder-prism"
  [rbuilder-rebalancer]="rbuilder-prism"
)
declare -A SVC_FILE=(
  [flowproxy]="flowproxy-downloader.service"
  [rbuilder-operator]="rbuilder-operator-rebalancer-downloader.service"
  [rbuilder-rebalancer]="rbuilder-operator-rebalancer-downloader.service"
)
declare -A SVC_PREFIX=(
  [flowproxy]="FLOWPROXY"
  [rbuilder-operator]="RBUILDER_OPERATOR"
  [rbuilder-rebalancer]="RBUILDER_REBALANCER"
)
declare -A SVC_ARTIFACT=(
  [flowproxy]="flowproxy"
  [rbuilder-operator]="rbuilder-operator-%TAG%-x86_64-unknown-linux-gnu"
  [rbuilder-rebalancer]="rbuilder-rebalancer-%TAG%-x86_64-unknown-linux-gnu"
)

die() { echo "error: $*" >&2; exit 1; }

usage() {
  # Print the leading comment block (after the shebang), stripped of '# '.
  awk 'NR==1 { next } /^#/ { sub(/^#[[:space:]]?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

# resolve_tag <repo> <version> -> normalized tag (v-prefixed, or newest for "latest")
resolve_tag() {
  local repo=$1 ver=$2
  if [[ "$ver" == "latest" ]]; then
    gh release view --repo "$OWNER/$repo" --json tagName --jq '.tagName' 2>/dev/null \
      || die "could not resolve latest release for $OWNER/$repo"
    return
  fi
  [[ "$ver" == v* ]] && printf '%s' "$ver" || printf 'v%s' "$ver"
}

# fetch_sha <repo> <tag> <artifact> -> sha256 of the artifact
fetch_sha() {
  local repo=$1 tag=$2 artifact=$3 sums sha tmp
  # Preferred: the release's published sha256sums.txt (format: "<hash>  <name>").
  if sums=$(gh release download "$tag" --repo "$OWNER/$repo" \
              --pattern 'sha256sums.txt' --output - 2>/dev/null) && [[ -n "$sums" ]]; then
    sha=$(awk -v a="$artifact" '$2 == a { print $1 }' <<<"$sums")
  fi
  # Fallback: download the artifact and hash it locally.
  if [[ -z "${sha:-}" ]]; then
    tmp=$(mktemp)
    if gh release download "$tag" --repo "$OWNER/$repo" \
         --pattern "$artifact" --clobber --output "$tmp" 2>/dev/null; then
      sha=$(sha256sum "$tmp" | awk '{ print $1 }')
    fi
    rm -f "$tmp"
  fi
  [[ -n "${sha:-}" ]] || return 1
  printf '%s' "$sha"
}

# read_field <file> <key> -> current value of "KEY=<value>"
read_field() {
  grep -oE "$2=[^[:space:]\\\\]*" "$1" | head -1 | cut -d= -f2-
}

# set_field <file> <key> <value> — replace the value after "KEY=" in place
set_field() {
  local file=$1 key=$2 value=$3
  grep -qE "${key}=" "$file" || die "'${key}=' not found in $(basename "$file") — service file layout changed?"
  # Match up to the first whitespace/backslash so the trailing ' \' continuation is preserved.
  sed -i -E "s|(${key}=)[^[:space:]\\\\]*|\1${value}|" "$file"
}

# ---- parse args -------------------------------------------------------------
declare -A REQ=()
[[ $# -gt 0 ]] || { usage; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --flowproxy|--rbuilder-operator|--rbuilder-rebalancer)
      svc="${1#--}"
      [[ $# -ge 2 ]] || die "missing version for $1"
      REQ[$svc]="$2"
      shift 2
      ;;
    --owner)    [[ $# -ge 2 ]] || die "missing value for --owner"; OWNER="$2"; shift 2 ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "unknown argument: $1 (see --help)" ;;
  esac
done
[[ ${#REQ[@]} -gt 0 ]] || die "no service bumps requested (see --help)"

command -v gh >/dev/null || die "gh CLI not found on PATH"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login'"

# ---- apply ------------------------------------------------------------------
# Edits are staged onto temp copies so --dry-run can show a diff without
# touching the tree, and so multiple services sharing one unit file compose.
declare -A WORK=()
# Sets global REPLY to the working (temp) copy for real file $1, creating it on
# first use. Returns via a global rather than stdout so the WORK mutation is not
# lost to a command-substitution subshell.
ensure_work() {
  local real=$1
  if [[ -z "${WORK[$real]:-}" ]]; then
    local t; t=$(mktemp)
    cp "$real" "$t"
    WORK[$real]=$t
  fi
  REPLY="${WORK[$real]}"
}

for svc in "${SERVICES[@]}"; do
  [[ -n "${REQ[$svc]:-}" ]] || continue
  repo="${SVC_REPO[$svc]}"
  file="$SVC_DIR/${SVC_FILE[$svc]}"
  prefix="${SVC_PREFIX[$svc]}"
  [[ -f "$file" ]] || die "service file not found: $file"

  tag=$(resolve_tag "$repo" "${REQ[$svc]}")
  gh release view "$tag" --repo "$OWNER/$repo" >/dev/null 2>&1 \
    || die "release $tag not found in $OWNER/$repo"
  artifact="${SVC_ARTIFACT[$svc]//%TAG%/$tag}"

  echo ">> $svc: resolving $tag ($OWNER/$repo, $artifact)"
  sha=$(fetch_sha "$repo" "$tag" "$artifact") \
    || die "could not determine sha256 for '$artifact' in $tag"

  old_tag=$(read_field "$file" "${prefix}_TAG")
  ensure_work "$file"; work="$REPLY"
  set_field "$work" "${prefix}_TAG"       "$tag"
  set_field "$work" "${prefix}_ARTIFACT"  "$artifact"
  set_field "$work" "${prefix}_SHA256SUM" "$sha"

  echo "   $svc: ${old_tag:-?} -> $tag  sha256=$sha"
done

# ---- write / preview --------------------------------------------------------
echo
for real in "${!WORK[@]}"; do
  tmp="${WORK[$real]}"
  rel="${real#"$REPO_ROOT"/}"
  diff -u --label "a/$rel" --label "b/$rel" "$real" "$tmp" || true
  $DRY_RUN || cp "$tmp" "$real"
  rm -f "$tmp"
done

if $DRY_RUN; then
  echo "(dry run — no files modified)"
else
  echo "Done. Review the diff above, then commit."
fi

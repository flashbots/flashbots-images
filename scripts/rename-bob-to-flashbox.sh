#!/usr/bin/env bash
# rename-bob-to-flashbox.sh
#
# Renames all "bob" references to "flashbox" across the flashbots-images repo.
#
# Phase 1: Renames files/directories containing "bob" (via git mv)
# Phase 2: Replaces "bob" in file contents (via awk), with a skip-list
#           for lines that should keep "bob" (e.g. historical terminal examples)
# Phase 3: Safety check — reports any remaining "bob" references
#
# The script is idempotent — safe to re-run after merging new branches.
# New "bob" references are caught automatically by the blanket replacement.
# Only lines matching SKIP_PATTERNS are preserved.
#
# Run from the repo root. Dry-run by default; pass --apply to execute.
#
# Usage:
#   ./scripts/rename-bob-to-flashbox.sh          # dry-run
#   ./scripts/rename-bob-to-flashbox.sh --apply   # apply changes

set -euo pipefail

# Resolve repo root from the script's own location (scripts/ -> repo root)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCRIPT_NAME="rename-bob-to-flashbox"

DRY_RUN=true
if [[ "${1:-}" == "--apply" ]]; then
    DRY_RUN=false
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()   { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }
action() { echo -e "${RED}[APPLY]${NC} $*"; }

# ---------------------------------------------------------------------------
# Skip-list: lines matching these patterns are LEFT ALONE.
# These are regex patterns matched against each line (via awk) before replacement.
# Add new entries here if you find "bob" references that should NOT be renamed.
# ---------------------------------------------------------------------------
SKIP_PATTERNS=(
    # Historical terminal examples in readme (someone's actual hostname/path)
    "schmangeLina-bob-mkosi-builder"
    "bobgela"
)

# Join SKIP_PATTERNS into a single "pattern1|pattern2" regex for awk
SKIP_REGEX=""
for pat in "${SKIP_PATTERNS[@]}"; do
    if [[ -z "$SKIP_REGEX" ]]; then
        SKIP_REGEX="$pat"
    else
        SKIP_REGEX="$SKIP_REGEX|$pat"
    fi
done

# ---------------------------------------------------------------------------
# replace_bob_in_file: runs awk on a file to replace "bob" -> "flashbox"
# on every line EXCEPT those matching the skip-list.
# Outputs the transformed content to stdout.
# ---------------------------------------------------------------------------
replace_bob_in_file() {
    local file="$1"
    awk -v skip="$SKIP_REGEX" '
        skip != "" && $0 ~ skip { print; next }
        { gsub(/bob/, "flashbox"); print }
    ' "$file"
}

# ---------------------------------------------------------------------------
# Phase 1: Rename files and directories containing "bob"
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Phase 1: Rename files and directories"
echo "=========================================="
echo ""

# Collect paths bottom-up (deepest first) so children rename before parents.
# Uses while+read instead of mapfile for macOS bash 3 compatibility.
BOB_PATHS=()
while IFS= read -r p; do
    BOB_PATHS+=("$p")
done < <(find . -path ./.git -prune -o -name '*bob*' -print | sort -r)

for old_path in "${BOB_PATHS[@]}"; do
    [[ "$old_path" == *"$SCRIPT_NAME"* ]] && continue

    new_path="${old_path//bob/flashbox}"
    if [[ "$old_path" != "$new_path" ]]; then
        if $DRY_RUN; then
            warn "RENAME: $old_path -> $new_path"
        else
            mkdir -p "$(dirname "$new_path")"
            git mv "$old_path" "$new_path"
            action "RENAMED: $old_path -> $new_path"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Phase 2: Replace "bob" in file contents
#
# For each file containing "bob", process line-by-line with awk:
# - Lines matching SKIP_PATTERNS are printed as-is
# - All other lines get a blanket bob -> flashbox replacement
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Phase 2: Replace content inside files"
echo "=========================================="
echo ""

# Scan AFTER phase 1 renames so we find files at their new paths
SEARCH_FILES=$(find . -path ./.git -prune -o -type f -print \
    | grep -v "$SCRIPT_NAME" \
    | xargs grep -l 'bob' 2>/dev/null \
    | sort || true)

for file in $SEARCH_FILES; do
    [[ -f "$file" ]] || continue
    # Skip binary files (but not text scripts that happen to be executable)
    if file "$file" | grep -q 'binary'; then
        continue
    fi

    if $DRY_RUN; then
        # Preview: show unified diff of what would change
        diff_output=$(replace_bob_in_file "$file" | diff "$file" - 2>/dev/null || true)
        if [[ -n "$diff_output" ]]; then
            info "Would modify: $file"
            echo "$diff_output"
            echo ""
        fi
    else
        # Write awk output to a temp file, then replace the original
        tmp="${file}.tmp.$$"  # $$ = current PID, ensures unique temp name
        replace_bob_in_file "$file" > "$tmp"
        mv "$tmp" "$file"
        action "Modified: $file"
    fi
done

# ---------------------------------------------------------------------------
# Phase 3: Safety check — report any remaining "bob" references
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Phase 3: Remaining 'bob' references"
echo "=========================================="
echo ""

if $DRY_RUN; then
    info "Checking what would remain AFTER replacements..."
    echo "(Only lines matching the skip-list should appear here)"
    echo ""

    found_remaining=false
    for file in $SEARCH_FILES; do
        [[ -f "$file" ]] || continue
        if file "$file" | grep -q 'binary'; then continue; fi

        remaining=$(replace_bob_in_file "$file" | grep -n 'bob' 2>/dev/null || true)
        if [[ -n "$remaining" ]]; then
            echo -e "${YELLOW}[WARNING]${NC} $file:"
            echo "$remaining" | head -20
            echo ""
            found_remaining=true
        fi
    done

    if ! $found_remaining; then
        info "No remaining 'bob' references outside the skip-list."
    fi
else
    remaining_files=$(find . -path ./.git -prune -o -type f -print \
        | grep -v "$SCRIPT_NAME" \
        | xargs grep -l 'bob' 2>/dev/null || true)
    if [[ -n "$remaining_files" ]]; then
        echo -e "${YELLOW}[REMAINING]${NC} Files still containing 'bob' (should only be skip-list matches):"
        for f in $remaining_files; do
            echo "  $f:"
            grep -n 'bob' "$f" | head -10
        done
        echo ""
    else
        info "No remaining 'bob' references found!"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo ""

if $DRY_RUN; then
    echo "This was a DRY RUN. No changes were made."
    echo "Review the output above and run with --apply to execute:"
    echo ""
    echo "  ./scripts/rename-bob-to-flashbox.sh --apply"
    echo ""
else
    echo "Rename complete. Review changes with:"
    echo ""
    echo "  git diff --stat"
    echo "  git diff"
    echo ""
fi

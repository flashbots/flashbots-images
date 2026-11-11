#!/usr/bin/env bash
# Compares the kernel config values fragments request with the resolved
# .config and the Debian base config.
#
# A request is any line a fragment sets: `CONFIG_X=VALUE`, `CONFIG_X=n` or
# `# CONFIG_X is not set`. Fragments are read in merge order, so a later
# fragment's request replaces an earlier one, as in merge_config.sh.
#
# Usage:
#   config-requests.sh check RESOLVED_CONFIG FRAGMENT...
#       Fails when a requested value is not the value in RESOLVED_CONFIG.
#       Kconfig ignores a request without a word when the option's
#       `depends on` is not met, or when another option `select`s an option a
#       fragment turns off.
#
#   config-requests.sh builtin-modules-report BASE_CONFIG RESOLVED_CONFIG FRAGMENT...
#       Counts what became of each BASE_CONFIG module (`=m`) and lists the
#       ones built into RESOLVED_CONFIG that no fragment requested: with
#       CONFIG_MODULES=n, Kconfig builds every `=m` option into the kernel
#       instead of leaving it out, so these are the ones to review.
set -euo pipefail

# Sets name and value for a config line, value "n" for an option turned off;
# returns 0 for any other line.
parse_config_line='
    function parse_config_line(line) {
        if (match(line, /^CONFIG_[A-Za-z0-9_]+=/)) {
            name = substr(line, 8, RLENGTH - 8)
            value = substr(line, RLENGTH + 1)
            return 1
        }
        if (match(line, /^# CONFIG_[A-Za-z0-9_]+ is not set$/)) {
            name = substr(line, 10, RLENGTH - 20)
            value = "n"
            return 1
        }
        return 0
    }
'

usage() {
    sed -n 's/^#   //p' "$0" >&2
    exit 2
}

check() {
    [[ $# -ge 2 ]] || usage
    awk "${parse_config_line}"'
        # Skip lines that set no option: blank lines and other comments.
        !parse_config_line($0) { next }
        # A line of RESOLVED_CONFIG: record the value Kconfig settled on.
        FILENAME == ARGV[1] { resolved[name] = value; next }
        # A fragment line: record the request and where it was made. A later
        # fragment overwrites an earlier request for the same option.
        { requested[name] = value; source[name] = FILENAME ":" FNR }
        # After all files: report each request that resolved to another value.
        # An option absent from RESOLVED_CONFIG is off.
        END {
            failures = 0
            for (n in requested) {
                got = (n in resolved) ? resolved[n] : "n"
                if (got != requested[n]) {
                    printf "%s: CONFIG_%s: requested %s, resolved to %s\n", \
                        source[n], n, requested[n], got | "sort"
                    failures++
                }
            }
            close("sort")
            if (failures > 0) {
                printf "%d requested kernel config value(s) did not take effect\n", failures
                exit 1
            }
        }
    ' "$@" >&2 # everything check prints is a failure, so sent to stderr
}

builtin_modules_report() {
    [[ $# -ge 3 ]] || usage
    awk "${parse_config_line}"'
        # Skip lines that set no option: blank lines and other comments.
        !parse_config_line($0) { next }
        # A line of BASE_CONFIG: keep only the options Debian builds as modules.
        FILENAME == ARGV[1] { if (value == "m") base_modules[name] = 1; next }
        # A line of RESOLVED_CONFIG: record the value Kconfig settled on.
        FILENAME == ARGV[2] { resolved[name] = value; next }
        # A fragment line: record the request; a later fragment overwrites it.
        { requested[name] = value }
        # After all files: sort each Debian module into one bucket, print the
        # counts, then list the modules built in without a request.
        END {
            total = requested_count = unrequested_count = turned_off_count = 0
            for (n in base_modules) {
                total++
                built = (n in resolved) && resolved[n] != "n"
                request = (n in requested) ? requested[n] : ""
                if (built && request != "" && request != "n") {
                    requested_count++
                } else if (built) {
                    unrequested[n] = resolved[n]
                    unrequested_count++
                } else if (request == "n") {
                    turned_off_count++
                }
            }
            printf "Debian modules (=m in the base config): %d\n", total
            printf "  %-36s %5d\n", "built in, requested by a fragment:", requested_count
            printf "  %-36s %5d\n", "built in, not requested:", unrequested_count
            printf "  %-36s %5d\n", "not built, turned off by a fragment:", turned_off_count
            printf "  %-36s %5d\n", "not built, a dependency is off:", \
                total - requested_count - unrequested_count - turned_off_count
            if (unrequested_count > 0) {
                print "Built in without a request:"
                for (n in unrequested)
                    print "  CONFIG_" n "=" unrequested[n] | "sort"
                close("sort")
            }
        }
    ' "$@"
}

[[ $# -ge 1 ]] || usage
command=$1
shift
case "${command}" in
    check) check "$@" ;;
    builtin-modules-report) builtin_modules_report "$@" ;;
    *) usage ;;
esac

#!/bin/sh
# Template rendering helpers.

# Concatenate one or more templates and render the result with envsubst,
# substituting only the env vars in the explicit allowlist.
#
# Args: $1 = output path
#       $2 = space-separated list of var names to substitute (e.g.
#            "METRICS_URL METRICS_USERNAME")
#       $3.. = template files to concatenate
render_template() {
    local out="$1" vars="$2"
    shift 2

    local allowlist="" v
    for v in $vars; do
        allowlist="${allowlist}\$${v} "
    done

    cat "$@" | envsubst "$allowlist" > "$out"
}

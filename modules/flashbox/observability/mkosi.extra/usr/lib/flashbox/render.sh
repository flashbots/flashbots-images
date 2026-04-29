#!/bin/sh
# Template rendering helpers.

# Render a template by substituting ${VAR} references from the environment.
# Args: $1 = template path, $2 = output path
render_envsubst() {
    envsubst < "$1" > "$2"
}

#!/bin/sh

# Check if "create" appears anywhere in arguments
if echo "$@" | grep -q " create "; then
    # Find bundle path (comes after --bundle)
    BUNDLE=$(echo "$@" | sed -n 's/.*--bundle \([^ ]*\).*/\1/p')
    
    if [ -n "$BUNDLE" ] && [ -f "$BUNDLE/config.json" ]; then
        # Add apparmorProfile right after '"process":{' 
        sed -i 's/"process":{"user":/"process":{"apparmorProfile":"searcher-container","user":/' "$BUNDLE/config.json"
    fi
fi

# Run real runc
exec /usr/bin/runc.real "$@"

#!/bin/sh
# Helpers for reading GCE instance metadata.

# Read a single attribute from the GCE metadata server.
# Args: $1 = relative path under /computeMetadata/v1/instance/
gce_metadata_get() {
    curl -sf \
        --header "Metadata-Flavor: Google" \
        "http://metadata/computeMetadata/v1/instance/$1"
}

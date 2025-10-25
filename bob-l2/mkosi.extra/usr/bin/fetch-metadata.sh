#!/bin/sh
set -eu -o pipefail

# This script fetches couple of pre-defined keys from instance metadata server
# and writes them to /etc/metadata.env in the format:
#   METADATA_{KEY}='{VALUE}'
#
# It also checks that received values do not contain newlines and conform to
# ^[a-zA-Z0-9.,@:/_ -]*$

if dmidecode -s system-manufacturer 2>/dev/null | grep -q "QEMU"; then
    echo "Running in local QEMU, using hardcoded metadata values"

    cat <<EOF >> /etc/metadata.env
METADATA_BOB_L2_BACKRUNS_IP='1.1.1.1'
METADATA_BOB_L2_TX_STREAM_IP='1.0.0.1'
METADATA_BOB_L2_OP_NODE_CIDR='10.0.0.0/8'
EOF

    # Ideally, this logic should be somewhere else, but it's fine for now
    chattr -i /etc/resolv.conf || true
    echo "nameserver 1.1.1.1" > /etc/resolv.conf

    exit 0
fi

rm -f /etc/metadata.env # just in case
touch /etc/metadata.env

METADATA_URL="http://169.254.169.254/computeMetadata/v1/instance/attributes/"
fetch_metadata_value() {
    local key="$1"
    curl -s -H "Metadata-Flavor: Google" "${METADATA_URL}${key}"
}

for key in \
    BOB_L2_BACKRUNS_IP \
    BOB_L2_TX_STREAM_IP \
    BOB_L2_OP_NODE_CIDR
do
    value=$(fetch_metadata_value "$key")

    if [ "$(echo "$value" | wc -l)" -ne 1 ]; then
        echo "Error: Value for $key contains newlines"
        exit 1
    fi

    if echo "$value" | grep -qvE '^[a-zA-Z0-9.,@:/_ -]*$'; then
        echo "Error: Value for $key contains bad characters"
        exit 1
    fi

    echo "METADATA_$key='$value'" >> /etc/metadata.env
done

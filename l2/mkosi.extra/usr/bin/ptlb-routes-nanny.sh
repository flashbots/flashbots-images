#!/bin/sh

set -eu

is_ip4() {
    echo "$1" | awk -F. '
        $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 &&
        $1 >= 0   && $2 >= 0   && $3 >= 0   && $4 >= 0   &&
        $1 != ""  && $2 != ""  && $3 != ""  && $4 != ""  &&
        NF == 4
        { exit 0 }
        { exit 1 }
    '
}

for line in "$(
  ip -br link show | grep -v lo
)"; do
  interface="${line%% *}"

  for idx in $(
    curl \
        --header "metadata-flavor: Google" \
        --max-time 1 \
        --show-error \
        --silent \
      http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/forwarded-ips/
  ); do
    ip=$(
      curl \
          --header "metadata-flavor: Google" \
          --max-time 1 \
          --show-error \
          --silent \
        http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/forwarded-ips/${idx}
    )

    if is_ip4 "${ip}"; then
      route="local ${ip} dev ${interface} proto 66 scope host"

      if ! ip route show table local | grep -q "${route}"; then
        echo "---"
        echo "$ ip route show table local"
        ip route show table local
        echo "---"
        echo "Route is missing, adding..."
        echo "---"
        echo "$ ip route add ${route}"
        ip route add ${route}
        echo "---"
        echo "$ ip route show table local"
        ip route show table local
        echo "---"
      fi
    fi
  done
done

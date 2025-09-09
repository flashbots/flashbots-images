#!/bin/sh
set -eu -o pipefail

NAME=searcher-container

# PORT FORWARDS
SEARCHER_SSH_PORT=10022
ENGINE_API_PORT=8551
EL_P2P_PORT=30303
SEARCHER_INPUT_CHANNEL=27017

echo "Starting $NAME..."
su -s /bin/sh searcher -c "cd ~ && podman run -d \
    --name $NAME --replace \
    -p ${SEARCHER_SSH_PORT}:22 \
    -p ${ENGINE_API_PORT}:${ENGINE_API_PORT} \
    -p ${EL_P2P_PORT}:${EL_P2P_PORT} \
    -p ${EL_P2P_PORT}:${EL_P2P_PORT}/udp \
    -p ${SEARCHER_INPUT_CHANNEL}:${SEARCHER_INPUT_CHANNEL}/udp \
    -v /persistent/searcher:/persistent:rw \
    -v /etc/searcher/ssh_hostkey:/etc/searcher/ssh_hostkey:rw \
    -v /persistent/searcher_logs:/var/log/searcher:rw \
    -v /persistent/lighthouse_logs:/var/log/lighthouse:ro \
    -v /tmp/jwt.hex:/secrets/jwt.hex:ro \
    -v /etc/searcher-logrotate.conf:/tmp/searcher.conf:ro \
    docker.io/library/ubuntu:24.04 \
    /bin/sh -c ' \
        DEBIAN_FRONTEND=noninteractive apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server logrotate cron && \
        cp /tmp/searcher.conf /etc/logrotate.d/searcher.conf && \
        chown root:root /etc/logrotate.d/searcher.conf && \
        mkdir -p /run/sshd && \
        mkdir -p /root/.ssh && \
        echo \"ssh-ed25519 $(cat /etc/searcher_key)\" > /root/.ssh/authorized_keys && \
        chmod 700 /root/.ssh && \
        chmod 600 /root/.ssh/authorized_keys && \
        cp /etc/ssh/ssh_host_ed25519_key.pub /etc/searcher/ssh_hostkey/host_key.pub && \
        echo \"0 * * * * root /usr/sbin/logrotate /etc/logrotate.d/searcher.conf\" > /etc/cron.d/searcher-logrotate && \
        service cron start && \
        /usr/sbin/sshd -D -e'"

# Attempt a quick check that the container is running
for i in 1 2 3 4 5; do
    status=$(su -s /bin/sh - searcher -c "podman inspect --format '{{.State.Status}}' $NAME 2>/dev/null || true")
    if [ "$status" = "running" ]; then
        break
    fi
    echo "Waiting for $NAME container to reach 'running' state..."
    sleep 1
done

if [ "$status" != "running" ]; then
    echo "ERROR: $NAME container is not running (status: $status)"
    exit 1
fi

# Retrieve the PID
pid=$(su -s /bin/sh - searcher -c "podman inspect --format '{{.State.Pid}}' $NAME")
if [ -z "$pid" ] || [ "$pid" = "0" ]; then
    echo "ERROR: Could not retrieve PID for container $NAME."
    exit 1
fi

echo "Applying iptables rules in $NAME (PID: $pid) network namespace..."

# Enter network namespace and apply DROP rules on port 9000 TCP/UDP
nsenter --target "$pid" --net iptables -A OUTPUT -p tcp --dport 9000 -j DROP
nsenter --target "$pid" --net iptables -A OUTPUT -p udp --dport 9000 -j DROP

# Enter network namespace and apply DROP rule on port 123 UDP
nsenter --target "$pid" --net iptables -A OUTPUT -p udp --dport 123 -j DROP

# Drop outbound traffic from SEARCHER_INPUT_CHANNEL
nsenter --target "$pid" --net iptables -A OUTPUT -p udp --sport $SEARCHER_INPUT_CHANNEL -j DROP
nsenter --target "$pid" --net iptables -A OUTPUT -p tcp --sport $SEARCHER_INPUT_CHANNEL -j DROP

echo "Injecting static hosts into $NAME..."

su -s /bin/sh searcher -c "podman exec $NAME /bin/sh -c '
    echo \"3.149.14.12 tx.tee-searcher.flashbots.net\" >> /etc/hosts &&
    echo \"3.136.107.142 tx.tee-searcher.flashbots.net\" >> /etc/hosts &&
    echo \"18.221.59.61 backruns.tee-searcher.flashbots.net\" >> /etc/hosts &&
    echo \"3.15.88.156 backruns.tee-searcher.flashbots.net\" >> /etc/hosts &&
    echo \"52.207.17.217 fbtee.titanbuilder.xyz\" >> /etc/hosts
'"
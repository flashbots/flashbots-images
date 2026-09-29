#!/bin/sh
set -eu -o pipefail

NAME=searcher-container

# PORT FORWARDS
SEARCHER_SSH_PORT=10022
SEARCHER_INPUT_UDP_PORT=27017  # External UDP input channel
SEARCHER_INPUT_TCP_PORT=27018  # External TCP input channel

# ENDPOINTS
PROMETHEUS_PROXY_IP=10.88.0.100  # host firewall allows in ALWAYS_OUT

# CONTAINER SSH HOST KEY
# Generated here on the guest OS, never inside the container. The directory is
# bind-mounted read-only below, and host_key.pub is what ssh-pubkey-server
# publishes on the attested :8745 endpoint, which is open in production mode.
# If the container could write here, a searcher could publish arbitrary data
# through /pubkey. The image has no ssh-keygen, so generate with dropbearkey and
# convert to the OpenSSH format the container's sshd expects. /etc is volatile,
# so this is a fresh key per boot, same as the dropbear host key.
HOSTKEY_DIR=/etc/searcher/ssh_hostkey
if [ ! -f "$HOSTKEY_DIR/host_key" ]; then
    dropbearkey -t ed25519 -f "$HOSTKEY_DIR/host_key.dropbear"
    dropbearconvert dropbear openssh "$HOSTKEY_DIR/host_key.dropbear" "$HOSTKEY_DIR/host_key"
    dropbearkey -y -f "$HOSTKEY_DIR/host_key.dropbear" | grep "^ssh-" > "$HOSTKEY_DIR/host_key.pub"
    rm -f "$HOSTKEY_DIR/host_key.dropbear" "$HOSTKEY_DIR/host_key.dropbear.pub"
fi
chmod 600 "$HOSTKEY_DIR/host_key"
# Container root maps to the searcher uid under rootless podman, so it can read the key
chown -R searcher:searcher "$HOSTKEY_DIR"

# Run extra commands which are customized per image,
# see bob*/mkosi.extra/etc/bob/searcher-container-before-init
#
# `source` is not supported in dash
. /etc/bob/searcher-container-before-init

# BOB_SEARCHER_EXTRA_PODMAN_FLAGS is unescaped, it's sourced from trusted hardcoded file

echo "Starting $NAME..."
su -s /bin/sh searcher -c "cd ~ && podman run -d \
    --name $NAME --replace \
    --init \
    -p ${SEARCHER_SSH_PORT}:22 \
    -p ${SEARCHER_INPUT_UDP_PORT}:${SEARCHER_INPUT_UDP_PORT}/udp \
    -v /persistent/searcher:/persistent:rw \
    -v /persistent/input:/persistent/input:rw \
    -v /etc/searcher/ssh_hostkey:/etc/searcher/ssh_hostkey:ro \
    -v /persistent/searcher_logs:/var/log/searcher:rw \
    -v /etc/searcher-logrotate.conf:/tmp/searcher.conf:ro \
    $BOB_SEARCHER_EXTRA_PODMAN_FLAGS \
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
        mkdir -p /etc/ssh/sshd_config.d && \
        echo \"HostKey /etc/searcher/ssh_hostkey/host_key\" > /etc/ssh/sshd_config.d/00-hostkey.conf && \
        echo \"0 * * * * root /usr/sbin/logrotate /etc/logrotate.d/searcher.conf\" > /etc/cron.d/searcher-logrotate && \
        service cron start && \
        while true; do /usr/sbin/sshd -D -e; sleep 5; done'"

# Attempt a quick check that the container is running
for i in $(seq 1 5); do
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
ns_iptables() {
    nsenter --target "$pid" --net iptables "$@"
}

ns_iptables -A OUTPUT -d 169.254.169.254 -j DROP

# Block container from reaching the internal Prometheus Proxy
ns_iptables -A OUTPUT -d $PROMETHEUS_PROXY_IP -j DROP

# Block consensus layer P2P port (TCP and UDP)
ns_iptables -A OUTPUT -p tcp --dport 9000 -j DROP
ns_iptables -A OUTPUT -p udp --dport 9000 -j DROP

# Block NTP port (UDP, rarely TCP)
ns_iptables -A OUTPUT -p udp --dport 123 -j DROP
ns_iptables -A OUTPUT -p tcp --dport 123 -j DROP

# Block container from sending responses on input channels
ns_iptables -A OUTPUT -p udp --sport $SEARCHER_INPUT_UDP_PORT -j DROP
ns_iptables -A OUTPUT -p tcp --sport $SEARCHER_INPUT_UDP_PORT -j DROP
ns_iptables -A OUTPUT -p tcp --sport $SEARCHER_INPUT_TCP_PORT -j DROP

# Helper, only used in sourced script below
exec_in_container() {
    su -s /bin/sh searcher -c "podman exec $NAME /bin/sh -c '$1'"
}

# Run extra commands which are customized per image,
# see bob*/mkosi.extra/etc/bob/searcher-container-after-init
. /etc/bob/searcher-container-after-init

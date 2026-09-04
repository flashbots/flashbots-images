"""First-boot integration tests for the flashbox-l1 production image.

Runs against the ephemeral TDX VM deployed by the workflow. Tests follow
the real first-boot chain, which gates almost everything behind key
registration (dropbear Requires=wait-for-key, ssh-pubkey-server and
attested-tls-proxy sit behind dropbear):

    wait-for-key (8080) -> push key -> dropbear (22)
        -> ssh-pubkey-server -> attested-tls-proxy (8745)
        -> initialize -> /persistent -> searcher container

So the order here is load-bearing: attestation is only reachable AFTER
the key push, and a failure cascades into the tests below it by design.
"""

import json
import os
import subprocess
import time

import pytest
import requests

from conftest import DATA_SSH_PORT, wait_for_port

KEY_REGISTER_PORT = 8080
ATTESTATION_PORT = 8745
PROXY_LISTEN = "127.0.0.1:18080"
RETH_VERSION = "v2.5.2"
RETH_ARCHIVE_SHA256 = \
    "e360895ac51b351ff0c44573f0f619bb1e7c3ff2df55502af1190c14c9b5ef6d"


def attestation_diagnostics(vm_ip, tmp_path):
    """Return the expected policy and the measurements reported by the VM."""
    actual_path = tmp_path / "actual_measurements.json"
    try:
        result = subprocess.run(
            [
                os.environ["PROXY_CLIENT"], "get-tls-cert",
                "--allowed-remote-attestation-type", "gcp-tdx",
                "--allow-self-signed",
                "--out-measurements", str(actual_path),
                f"{vm_ip}:{ATTESTATION_PORT}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        diagnostic_error = result.stderr.strip() or "<none>"
    except subprocess.TimeoutExpired:
        diagnostic_error = "diagnostic attestation timed out after 120 seconds"

    with open(os.environ["MEASUREMENTS_DCAP"]) as expected_file:
        expected = expected_file.read()
    actual = actual_path.read_text() if actual_path.exists() else "<unavailable>"

    return (
        f"expected portable policy:\n{expected}\n"
        f"actual GCP-TDX measurements:\n{actual}\n"
        f"diagnostic stderr:\n{diagnostic_error}"
    )


def fetch_attested_host_keys(vm_ip, tmp_path):
    """Fetch SSH host keys only after the VM quote passes verification."""
    proxy = subprocess.Popen(
        [
            os.environ["PROXY_CLIENT"], "client",
            "--log-debug",
            "--listen-addr", PROXY_LISTEN,
            "--measurements-file", os.environ["MEASUREMENTS_DCAP"],
            "--allow-self-signed",
            f"{vm_ip}:{ATTESTATION_PORT}",
        ],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    try:
        resp = None
        for _ in range(30):
            if proxy.poll() is not None:
                break
            try:
                resp = requests.get(f"http://{PROXY_LISTEN}/pubkey", timeout=10)
                break
            except requests.ConnectionError:
                time.sleep(2)
        if proxy.poll() is not None:
            out = proxy.stdout.read().decode(errors="replace")
            details = attestation_diagnostics(vm_ip, tmp_path)
            print(f"attestation client exited:\n{out}\n{details}", flush=True)
            pytest.fail(
                f"attestation client exited:\n{out}\n"
                f"{details}",
                pytrace=False,
            )
        assert resp is not None, "proxy client never started listening"
        if "X-Flashbots-Measurement" not in resp.headers:
            details = attestation_diagnostics(vm_ip, tmp_path)
            print(
                f"quote did not verify against expected measurements\n{details}",
                flush=True,
            )
            pytest.fail(
                f"quote did not verify against expected measurements\n{details}",
                pytrace=False,
            )
        assert resp.status_code == 200, \
            f"attested /pubkey returned HTTP {resp.status_code}: {resp.text}"

        host_keys = [line.strip() for line in resp.text.splitlines()
                     if line.strip()]
        assert host_keys and all(
            key.split()[0].startswith(("ssh-", "ecdsa-", "sk-"))
            for key in host_keys
        ), f"attested /pubkey returned no valid SSH host keys: {resp.text!r}"
        return host_keys
    finally:
        proxy.kill()


def test_deploy(vm_ip):
    # wait-for-key's HTTP server is the first externally visible signal
    # that the image booted; 8745 stays closed until a key is registered.
    # Short timeout on purpose: the long boot wait happens outside pytest
    # (workflow polls 8080 before running the suite)
    assert wait_for_port(vm_ip, KEY_REGISTER_PORT, timeout=5, interval=5), \
        "tdx-init key server (8080) never came up"


def test_push_key(vm_ip, searcher_key):
    resp = requests.post(
        f"http://{vm_ip}:{KEY_REGISTER_PORT}",
        data=searcher_key["pub_blob"],
        timeout=5,
    )
    assert resp.status_code == 200, resp.text


def test_attest(vm_ip, tmp_path, known_hosts_file):
    # the key push releases wait-for-key, which lets dropbear and then
    # attested-tls-proxy start. The port coming up validates the boot
    # chain, so that part stays a hard failure
    assert wait_for_port(vm_ip, ATTESTATION_PORT, timeout=60, interval=5), \
        "attested-tls-proxy (8745) did not come up after key registration"

    host_keys = fetch_attested_host_keys(vm_ip, tmp_path)
    known_hosts_file.write_text("".join(
        f"{vm_ip} {key}\n" for key in host_keys
    ))


def test_initialize_disk(searchersh, disk_passphrase):
    before = searchersh("status")
    assert "not initialized" in (before.stdout + before.stderr).lower(), \
        "expected searchersh to refuse commands before initialize"

    # tdx-init prompts "Enter passphrase:" on stdin (the searcher's disk
    # encryption key); luksFormat + mkfs on the 50G data disk takes a while
    init = searchersh("initialize", timeout=300,
                      input_text=disk_passphrase + "\n")
    assert init.returncode == 0, init.stdout + init.stderr


@pytest.mark.dependency(name="container_ssh")
def test_ssh_in(vm_ip, tmp_path, known_hosts_file, containersh):
    assert wait_for_port(vm_ip, DATA_SSH_PORT, timeout=120, interval=5), \
        f"searcher container SSH ({DATA_SSH_PORT}) did not come up"

    # The container creates its OpenSSH host key after disk initialization.
    # Fetch /pubkey through attested TLS again before trusting that new key.
    host_keys = fetch_attested_host_keys(vm_ip, tmp_path)
    with known_hosts_file.open("a") as known_hosts:
        known_hosts.writelines(
            f"[{vm_ip}]:{DATA_SSH_PORT} {key}\n" for key in host_keys
        )

    result = containersh("true")
    if result.returncode != 0:
        print(
            f"container SSH failed ({result.returncode}):\n"
            f"{result.stdout}{result.stderr}",
            flush=True,
        )
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.dependency(depends=["container_ssh"])
def test_lighthouse_syncing(containersh):
    deadline = time.monotonic() + 180
    snapshot = None
    while time.monotonic() < deadline:
        result = containersh(
            "grep -F '\"msg\":\"Slot timer\"' "
            "/var/log/lighthouse/beacon.log 2>/dev/null | tail -n 1"
        )
        if result.returncode == 0 and result.stdout.strip():
            snapshot = json.loads(result.stdout)
            if "Sync" in str(snapshot.get("sync_state", "")):
                break
        time.sleep(5)

    assert snapshot is not None, "Lighthouse produced no Slot timer sync status"
    assert "Sync" in str(snapshot.get("sync_state", "")), snapshot
    print(f"Lighthouse sync status: {json.dumps(snapshot, sort_keys=True)}")


@pytest.mark.dependency(name="reth_installed", depends=["container_ssh"])
def test_install_reth(containersh):
    archive = f"reth-{RETH_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
    url = f"https://github.com/paradigmxyz/reth/releases/download/{RETH_VERSION}/{archive}"
    result = containersh(
        f"set -eu; "
        f"apt-get update -qq; "
        f"DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates; "
        f"curl -fsSL '{url}' -o /tmp/reth.tar.gz; "
        f"echo '{RETH_ARCHIVE_SHA256}  /tmp/reth.tar.gz' | sha256sum -c -; "
        f"tar -xzf /tmp/reth.tar.gz -C /usr/local/bin reth; "
        f"chmod 0755 /usr/local/bin/reth; "
        f"/usr/local/bin/reth --version; "
        f"nohup /usr/local/bin/reth node "
        f"--datadir /persistent/reth "
        f"--authrpc.jwtsecret /secrets/jwt.hex "
        f"--authrpc.addr 0.0.0.0 --authrpc.port 8551 "
        f"--http --http.addr 127.0.0.1 --http.api eth,net "
        f">>/var/log/searcher/bob.log 2>&1 </dev/null & "
        f"echo $! >/persistent/reth.pid",
        timeout=300,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert RETH_VERSION.removeprefix("v") in result.stdout, result.stdout


@pytest.mark.dependency(depends=["reth_installed"])
def test_reth_syncing(containersh):
    request = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "eth_syncing", "params": [],
    })
    deadline = time.monotonic() + 300
    last_response = None
    while time.monotonic() < deadline:
        result = containersh(
            "curl -fsS -H 'Content-Type: application/json' "
            f"--data '{request}' http://127.0.0.1:8545",
        )
        if result.returncode == 0:
            last_response = json.loads(result.stdout)
            if isinstance(last_response.get("result"), dict):
                break
        time.sleep(5)

    assert last_response is not None, "Reth JSON-RPC did not become available"
    assert isinstance(last_response.get("result"), dict), \
        f"Reth did not report active syncing: {last_response}"
    print(f"Reth sync status: {json.dumps(last_response['result'], sort_keys=True)}")

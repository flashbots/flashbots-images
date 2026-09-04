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

import os
import subprocess
import time

import pytest
import requests

from conftest import wait_for_port

KEY_REGISTER_PORT = 8080
ATTESTATION_PORT = 8745
PROXY_LISTEN = "127.0.0.1:18080"


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

    # PROXY_CLIENT is attested-tls-proxy (what the image runs since #168),
    # NOT cvm-reverse-proxy: the new protocol (TLS 1.3 + ALPN
    # flashbots-ratls/1) makes the old proxy-client fail the handshake
    # with "illegal parameter"
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
                resp = requests.get(
                    f"http://{PROXY_LISTEN}/pubkey", timeout=10,
                )
                break
            except requests.ConnectionError:
                time.sleep(2)
        if proxy.poll() is not None:
            out = proxy.stdout.read().decode(errors="replace")
            pytest.fail(
                f"attestation client exited:\n{out}\n"
                f"{attestation_diagnostics(vm_ip, tmp_path)}",
                pytrace=False,
            )
        assert resp is not None, "proxy client never started listening"

        debug = (
            f"response headers through proxy: {dict(resp.headers)}\n"
        )
        # the header is only set after the quote verified against our
        # measurements; on mismatch the proxy client logs what the quote
        # actually contained, so capture that for comparing later
        if "X-Flashbots-Measurement" not in resp.headers:
            proxy.kill()
            debug += f"proxy client output:\n" \
                     f"{proxy.stdout.read().decode(errors='replace')}"
        print(debug)

        if "X-Flashbots-Measurement" not in resp.headers:
            pytest.fail(
                f"quote did not verify against expected measurements "
                f"(HTTP {resp.status_code} through proxy)\n{debug}\n"
                f"{attestation_diagnostics(vm_ip, tmp_path)}",
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
        known_hosts_file.write_text("".join(
            f"{vm_ip} {key}\n" for key in host_keys
        ))
    finally:
        proxy.kill()


def test_initialize_disk(searchersh, disk_passphrase):
    before = searchersh("status")
    assert "not initialized" in (before.stdout + before.stderr).lower(), \
        "expected searchersh to refuse commands before initialize"

    # tdx-init prompts "Enter passphrase:" on stdin (the searcher's disk
    # encryption key); luksFormat + mkfs on the 50G data disk takes a while
    init = searchersh("initialize", timeout=300,
                      input_text=disk_passphrase + "\n")
    assert init.returncode == 0, init.stdout + init.stderr


def test_ssh_in(searchersh):
    status = searchersh("status")
    assert status.returncode == 0, status.stdout + status.stderr
    assert status.stdout.strip(), "status returned nothing"

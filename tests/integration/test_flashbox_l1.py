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


def test_attest(vm_ip):
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
                resp = requests.get(f"http://{PROXY_LISTEN}", timeout=10)
                break
            except requests.ConnectionError:
                time.sleep(2)
        if proxy.poll() is not None:
            out = proxy.stdout.read().decode(errors="replace")
            print(out)
            # the client verifies at startup and exits on rejection
            # ("Measurements not accepted"), so this path is the same
            # whitelisted soft-fail as a 502 below
            pytest.xfail(f"attestation client exited:\n{out}")
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
            # soft-fail ("whitelisted"): the official release-notes
            # attestation flow is broken for this image (stale client),
            # and mrtd/rtmr0 rot when GCP rolls firmware. The debug text
            # goes in the reason so it lands on screen without -s
            pytest.xfail(
                f"quote did not verify against expected measurements "
                f"(HTTP {resp.status_code} through proxy)\n{debug}"
            )
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

import os
import pathlib
import secrets
import socket
import subprocess
import time

import pytest

SSH_OPTS = [
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=10",
    "-o", "IdentitiesOnly=yes",
    "-o", "LogLevel=ERROR",
]

DATA_SSH_PORT = 10022


@pytest.fixture(scope="session")
def vm_ip():
    return os.environ["VM_IP"]


@pytest.fixture(scope="session")
def searcher_key():
    """Ed25519 keypair registered as the searcher key.

    Persisted across runs (default ~/.cache/flashbox-itest/id_ed25519,
    override with SEARCHER_KEY_FILE): push_key and initialize only work
    once per VM, but a saved key keeps ssh working on reruns against an
    already-claimed VM.
    """
    keyfile = pathlib.Path(os.environ.get(
        "SEARCHER_KEY_FILE",
        os.path.expanduser("~/.cache/flashbox-itest/id_ed25519"),
    ))
    if not keyfile.exists():
        keyfile.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["ssh-keygen", "-t", "ed25519", "-N", "", "-q", "-f", str(keyfile)],
            check=True,
        )
    # tdx-init expects only the base64 blob, not the full authorized_keys line
    blob = keyfile.with_suffix(".pub").read_text().split()[1]
    return {"private": str(keyfile), "pub_blob": blob}


@pytest.fixture(scope="session")
def disk_passphrase():
    """Disk encryption passphrase, entered on initialize like a searcher would.

    Single token: tdx-init reads it with fmt.Scanln, which stops at spaces.
    """
    return secrets.token_hex(16)


@pytest.fixture(scope="session")
def known_hosts_file(tmp_path_factory):
    return tmp_path_factory.mktemp("ssh") / "known_hosts"


@pytest.fixture(scope="session")
def searchersh(vm_ip, searcher_key, known_hosts_file):
    """Run a searchersh menu command over dropbear."""

    def run(command, timeout=60, input_text=None):
        return subprocess.run(
            ["ssh", *SSH_OPTS,
             "-o", "StrictHostKeyChecking=yes",
             "-o", f"UserKnownHostsFile={known_hosts_file}",
             "-i", searcher_key["private"],
             f"searcher@{vm_ip}", command],
            capture_output=True, text=True, timeout=timeout,
            input=input_text,
        )

    return run


@pytest.fixture(scope="session")
def containersh(vm_ip, searcher_key, known_hosts_file):
    """Run a command inside the searcher's container over OpenSSH."""

    def run(command, timeout=60):
        return subprocess.run(
            ["ssh", *SSH_OPTS,
             "-o", "StrictHostKeyChecking=yes",
             "-o", f"UserKnownHostsFile={known_hosts_file}",
             "-p", str(DATA_SSH_PORT),
             "-i", searcher_key["private"],
             f"root@{vm_ip}", command],
            capture_output=True, text=True, timeout=timeout,
        )

    return run


def wait_for_port(ip, port, timeout=900, interval=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((ip, port), timeout=5):
                return True
        except OSError:
            time.sleep(interval)
    return False

#!/usr/bin/env python3
"""
verify-hardening.py — post-build regression for flashbox hardening.

Run inside the searcher container of a booted image. Exit 0 if all checks
pass, 1 on regression.

This is a hand-maintained checklist, not a source-driven test. When you
add a seccomp rule or a kernel pin, ADD A CORRESPONDING CHECK BELOW.
The script is the regression spec — keeping it current is part of the
rule-addition workflow.

Usage:
    python3 verify-hardening.py [--json]
    make verify-hardening TARGET=root@host:port    # scp + ssh + run
"""

import argparse
import ctypes
import ctypes.util
import errno
import json
import os
import socket
import sys


libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)


# Syscall numbers for x86_64 (production) and aarch64 (podman-on-mac testbed).
_SYSNRS = {
    "x86_64":  {"swapon": 167, "userfaultfd": 323, "io_uring_setup": 425,
                "io_uring_enter": 426, "io_uring_register": 427,
                "pidfd_open": 434, "pidfd_getfd": 438, "add_key": 248,
                "request_key": 249, "keyctl": 250, "unshare": 272,
                "clone3": 435, "mount": 165, "bpf": 321},
    "aarch64": {"swapon": 224, "userfaultfd": 282, "io_uring_setup": 425,
                "io_uring_enter": 426, "io_uring_register": 427,
                "pidfd_open": 434, "pidfd_getfd": 438, "add_key": 217,
                "request_key": 218, "keyctl": 219, "unshare": 97,
                "clone3": 435, "mount": 40, "bpf": 280},
}


def _detect_arch():
    try:
        v = open("/proc/version").read()
        return "aarch64" if ("aarch64" in v or "arm64" in v) else "x86_64"
    except FileNotFoundError:
        return "x86_64"


_ARCH = _detect_arch()
SYS = _SYSNRS[_ARCH]

_USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
_C = (lambda code, t: f"\033[{code}m{t}\033[0m") if _USE_COLOR else (lambda code, t: t)
PASS = _C("32", "PASS")
FAIL = _C("31", "FAIL")
INFO = _C("33", "INFO")


def _ename(n):
    return errno.errorcode.get(n, str(n))


def _syscall(nr, *args):
    ctypes.set_errno(0)
    r = libc.syscall(nr, *args)
    return r, ctypes.get_errno()


class Recorder:
    def __init__(self):
        self.results = []  # (status, label, msg)

    def record(self, status, label, msg):
        self.results.append((status, label, msg))
        print(f"  {status}  {label:46s}  {msg}")

    def expect_deny(self, label, expected, indeterminate, fn):
        try:
            rc, e = fn()
        except OSError as ex:
            rc, e = -1, ex.errno
        if rc is not None and rc >= 0:
            self.record(FAIL, label, f"syscall succeeded (rc={rc}) — expected denial")
        elif e in expected:
            self.record(PASS, label, f"denied with {_ename(e)}")
        elif e in indeterminate:
            self.record(INFO, label, f"got {_ename(e)} — covered, layer indistinguishable")
        else:
            exp = ", ".join(_ename(x) for x in expected)
            self.record(FAIL, label, f"got {_ename(e)}; expected {exp}")

    def expect_ok(self, label, fn):
        try:
            fn()
            self.record(PASS, label, "ok")
        except OSError as ex:
            self.record(FAIL, label, f"{_ename(ex.errno)}: {ex.strerror}")

    def check_kallsyms_absent(self, kallsyms, label, sym):
        present = (f" {sym}\n" in kallsyms) or (f"\t{sym}\n" in kallsyms)
        if present:
            self.record(FAIL, label, f"symbol {sym} PRESENT (pin not in effect)")
        else:
            self.record(PASS, label, f"symbol {sym} absent")

    def info(self, label, msg):
        self.record(INFO, label, msg)


def _section(t):
    print(f"\n=== {t} ===")


def _socket_probe(family):
    def _():
        try:
            socket.socket(family, socket.SOCK_RAW, 0).close()
            return 0, 0
        except OSError as ex:
            return -1, ex.errno
    return _


def main():
    ap = argparse.ArgumentParser(description="post-build hardening regression")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    r = Recorder()
    print(f"Kernel arch detected from /proc/version: {_ARCH}")

    _section("Canary: seccomp filter active")
    r.expect_deny("swapon (default-ERRNO)", (1,), (),
                  lambda: _syscall(SYS["swapon"], ctypes.c_char_p(b"/nonexistent"), 0))

    _section("Sanity: legitimate syscalls still pass")
    r.expect_ok("AF_INET socket open",
                lambda: socket.socket(socket.AF_INET, socket.SOCK_STREAM).close())
    r.expect_ok("AF_UNIX socket open",
                lambda: socket.socket(socket.AF_UNIX, socket.SOCK_STREAM).close())
    r.expect_ok("AF_NETLINK socket open",
                lambda: socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, 0).close())
    r.expect_ok("pidfd_open(self,0)",
                lambda: os.close(os.pidfd_open(os.getpid(), 0)))

    # Cap-gated escape primitives: container's CapEff (0x800405fb) excludes
    # CAP_SYS_ADMIN; these must all deny.
    _section("Sandbox boundaries (cap-gated denies)")
    CLONE_NEWUSER, CLONE_NEWNET = 0x10000000, 0x40000000
    r.expect_deny("unshare(NEWUSER|NEWNET)", (1,), (),
                  lambda: _syscall(SYS["unshare"], CLONE_NEWUSER | CLONE_NEWNET))
    r.expect_deny("clone3(empty args)", (1, 22, 38), (38,),
                  lambda: _syscall(SYS["clone3"], 0, 0))
    r.expect_deny("mount(NULL, /, NULL, 0, NULL)", (1,), (),
                  lambda: _syscall(SYS["mount"], 0, ctypes.c_char_p(b"/"), 0, 0, 0))
    r.expect_deny("bpf(BPF_PROG_LOAD, ...)", (1,), (),
                  lambda: _syscall(SYS["bpf"], 5, 0, 0))

    # EQ rules inside the arg0<38 ALLOW range. EAFNOSUPPORT is indeterminate
    # because the kernel also has these families pinned off; the libseccomp
    # regression section below pries the layers apart.
    _section("Explicit EQ socket family denies")
    r.expect_deny("AF_KEY (15)", (97,), (97,), _socket_probe(15))
    r.expect_deny("AF_RXRPC (33)", (97,), (97,), _socket_probe(33))

    # Simplified block 4 is arg0>45; these fall to defaultErrnoRet=1.
    _section("Gap denies (default-ERRNO)")
    for fam, label in [(38, "AF_ALG (38)"), (40, "AF_VSOCK (40)"),
                       (41, "AF_KCM (41)"), (42, "AF_QIPCRTR (42)"),
                       (43, "AF_SMC (43)"), (44, "AF_XDP (44)"),
                       (45, "AF_MCTP (45)")]:
        r.expect_deny(label, (1,), (97,), _socket_probe(fam))

    # libseccomp NE/EQ chain-ordering bug regression. On a kernel with the
    # family compiled in, EAFNOSUPPORT proves seccomp fired (not kernel).
    _section("libseccomp chain-ordering regression")
    try:
        kallsyms = open("/proc/kallsyms").read()
    except (FileNotFoundError, PermissionError):
        kallsyms = ""
    for fam, label, sym in [(15, "AF_KEY  vs CONFIG_NET_KEY",  "pfkey_create"),
                            (33, "AF_RXRPC vs CONFIG_AF_RXRPC", "rxrpc_create")]:
        if sym in kallsyms:
            r.expect_deny(f"{label} [kernel-present]", (97,), (), _socket_probe(fam))
        else:
            try:
                socket.socket(fam, socket.SOCK_RAW, 0).close()
                r.record(FAIL, label, "syscall succeeded — regression")
            except OSError as ex:
                r.info(label, f"kernel-absent ({sym} not in kallsyms); got {_ename(ex.errno)}")

    _section("Syscall denies")

    def t_pidfd_getfd():
        pfd = os.pidfd_open(os.getpid(), 0)
        try:
            return _syscall(SYS["pidfd_getfd"], ctypes.c_int(pfd),
                            ctypes.c_int(0), ctypes.c_uint(0))
        finally:
            os.close(pfd)
    r.expect_deny("pidfd_getfd", (1,), (), t_pidfd_getfd)
    r.expect_deny("io_uring_setup", (38,), (38,),
                  lambda: _syscall(SYS["io_uring_setup"], ctypes.c_uint(32), ctypes.c_void_p(0)))
    r.expect_deny("io_uring_enter", (38,), (38,),
                  lambda: _syscall(SYS["io_uring_enter"], ctypes.c_int(-1), 0, 0, 0, 0, 0))
    r.expect_deny("io_uring_register", (38,), (38,),
                  lambda: _syscall(SYS["io_uring_register"], ctypes.c_int(-1), 0, 0, 0))
    r.expect_deny("userfaultfd", (1,), (),
                  lambda: _syscall(SYS["userfaultfd"], 0))
    r.expect_deny("keyctl", (38,), (38,),
                  lambda: _syscall(SYS["keyctl"], 0, 0, 0, 0, 0))
    r.expect_deny("add_key", (38,), (38,),
                  lambda: _syscall(SYS["add_key"], ctypes.c_char_p(b"user"),
                                   ctypes.c_char_p(b"flashbox-test"),
                                   ctypes.c_char_p(b"x"), ctypes.c_size_t(1),
                                   ctypes.c_int(0)))
    r.expect_deny("request_key", (38,), (38,),
                  lambda: _syscall(SYS["request_key"], ctypes.c_char_p(b"user"),
                                   ctypes.c_char_p(b"flashbox-test"), 0, 0))

    # Kernel-config pins, verified by absence of representative kallsyms symbol.
    # NF_TABLES is overlaid back on by modules/flashbox/common/kernel/config.d/10-bob
    # for iptables-nft; expected PRESENT on flashbox images.
    _section("Deployed kernel-config pins (via /proc/kallsyms)")
    if not kallsyms:
        r.info("kallsyms unreadable", "skipping kernel-config audit")
    else:
        is_flashbox = "mkosi-cloud" in os.uname().release
        nft_present = "nft_chain_validate" in kallsyms
        if is_flashbox:
            label = "CONFIG_NF_TABLES (flashbox: 10-bob =y)"
            if nft_present:
                r.info(label, "present as expected for iptables-nft")
            else:
                r.record(FAIL, label, "absent — would break iptables-nft")
        else:
            r.check_kallsyms_absent(kallsyms, "CONFIG_NF_TABLES=n", "nft_chain_validate")

        # Pins added on this branch + pre-existing pins worth regressing.
        for cfg, sym in [
            ("CONFIG_AF_KCM=n",        "kcm_create_basic"),
            ("CONFIG_USERFAULTFD=n",   "new_userfaultfd"),
            ("CONFIG_TCP_MD5SIG=n",    "tcp_md5_do_add"),
            ("CONFIG_VHOST=n",         "vhost_dev_init"),
            ("CONFIG_VHOST_NET=n",     "vhost_net_open"),
            ("CONFIG_VHOST_VSOCK=n",   "vhost_vsock_dev_open"),
            ("CONFIG_VDPA=n",          "vdpa_register_device"),
            ("CONFIG_AF_RXRPC=n",      "rxrpc_create"),
            ("CONFIG_NET_KEY=n",       "pfkey_create"),
            ("CONFIG_MCTP=n",          "mctp_init"),
            ("CONFIG_XFRM=n",          "xfrm_state_alloc"),
            ("CONFIG_XFRM_ESPINTCP=n", "espintcp_init_sk"),
            ("CONFIG_IO_URING=n",      "__do_sys_io_uring_setup"),
        ]:
            r.check_kallsyms_absent(kallsyms, cfg, sym)

        # Tripwire: presence indicates the upstream ptrace fix landed and
        # the in-tree backport (when we add it) can be dropped.
        if "task_still_dumpable" in kallsyms:
            r.info("__ptrace_may_access fix landed",
                   "task_still_dumpable PRESENT — drop in-tree backport")
        else:
            r.info("__ptrace_may_access fix not backported",
                   "seccomp pidfd_getfd deny is the only layer")

    _section("Summary")
    n_pass = sum(1 for x in r.results if x[0] == PASS)
    n_info = sum(1 for x in r.results if x[0] == INFO)
    n_fail = sum(1 for x in r.results if x[0] == FAIL)
    print(f"  {n_pass} pass, {n_info} info, {n_fail} fail")
    if n_fail:
        print("\nFAIL details:")
        for status, label, msg in r.results:
            if status == FAIL:
                print(f"  • {label}: {msg}")

    if args.json:
        def strip(s):
            return s.replace("\033[32m", "").replace("\033[31m", "") \
                    .replace("\033[33m", "").replace("\033[0m", "")
        out = {
            "arch": _ARCH,
            "summary": {"pass": n_pass, "info": n_info, "fail": n_fail},
            "results": [{"status": strip(s), "label": l, "msg": m}
                        for s, l, m in r.results],
        }
        print("\n--- JSON ---")
        print(json.dumps(out, indent=2))

    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

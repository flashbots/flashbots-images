#!/usr/bin/env python3
"""
Validate a kernel .config against Flashbots TDX requirements.
Fails with exit code 1 if any required options are wrong or missing.

Usage: scripts/validate_kernel_config.py [--verbose] <path-to-.config>

Sources:
    [flashbots-tdx-guide]       Flashbots TDX Kernel Hardening and Tuning Guide
                                https://www.notion.so/flashbots/TDX-Kernel-Hardening-and-Tuning-Guide-24c6b4a0d876804b8162da33062354c0
    [kvm-tuning-guide]          Linux KVM Tuning Guide
                                https://www.linux-kvm.org/page/Tuning_Kernel
    [herecura-kconfig-bench]    Kconfig Hardening Performance Benchmark (herecura.eu, 2020)
                                https://blog.herecura.eu/blog/2020-05-30-kconfig-hardening-tests/
    [kspp-settings]             Kernel Self Protection Project — Recommended Settings
                                https://kspp.github.io/Recommended_Settings
    [clip-os-kernel]            CLIP OS Kernel Hardening Configuration
                                https://docs.clip-os.org/clipos/kernel.html#configuration
    [al2023-hardening]          Amazon Linux 2023 — Kernel Hardening
                                https://docs.aws.amazon.com/linux/al2023/ug/kernel-hardening.html
    [intel-ccc-guest]           Intel CCC Linux Guest Hardening
                                https://github.com/intel/ccc-linux-guest-hardening
"""

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Requirement:
    option: str
    value: str          # "y", "n", or a specific value like "32"
    section: str        # guide section
    note: str = ""      # optional context


# ---------------------------------------------------------------------------
# Requirements table — from Flashbots TDX Kernel Hardening and Tuning Guide
# See source URLs in module docstring above.
# ---------------------------------------------------------------------------
REQUIREMENTS: list[Requirement] = [

    # == Kernel Modules (monolithic kernel) ==
    Requirement("CONFIG_MODULES", "n", "Kernel Modules",
                "monolithic kernel — no dynamic module loading"),

    # == Container Support ==
    Requirement("CONFIG_NAMESPACES", "y", "Container Support"),
    Requirement("CONFIG_USER_NS", "y", "Container Support"),
    Requirement("CONFIG_NET_NS", "y", "Container Support"),
    Requirement("CONFIG_PID_NS", "y", "Container Support"),
    Requirement("CONFIG_IPC_NS", "y", "Container Support"),
    Requirement("CONFIG_UTS_NS", "y", "Container Support"),
    Requirement("CONFIG_CGROUPS", "y", "Container Support"),

    # == Virtual Machine Support ==
    Requirement("CONFIG_VIRTUALIZATION", "y", "VM Support (essential)"),

    # == VM Host — disabled (containers only, no nested VMs) ==
    Requirement("CONFIG_KVM", "n", "VM Host (attack surface)",
                "hypervisor — not needed for containers; Debian defconfig enables by default"),
    Requirement("CONFIG_KVM_INTEL", "n", "VM Host (attack surface)",
                "Intel VT-x hypervisor — not needed without KVM"),
    Requirement("CONFIG_VHOST_NET", "n", "VM Host (attack surface)",
                "kernel-level guest network acceleration — not needed without KVM"),

    # == Virtual Machine Support — performance ==
    Requirement("CONFIG_HIGH_RES_TIMERS", "y", "VM Support (performance)",
                "may cause issues depending on workload"),
    Requirement("CONFIG_COMPACTION", "y", "VM Support (performance)",
                "for huge page allocation"),
    Requirement("CONFIG_MIGRATION", "y", "VM Support (performance)",
                "for huge page allocation"),

    # == Network — Azure ==
    Requirement("CONFIG_PCI_IOV", "y", "Network (Azure)",
                "SR-IOV — reduces PCIe virtualization overhead"),
    Requirement("CONFIG_HYPERV", "y", "Network (Azure)"),

    # == Network — GCP ==
    Requirement("CONFIG_GVE", "y", "Network (GCP)",
                "Google Virtual Ethernet driver"),

    # == Network — congestion ==
    Requirement("CONFIG_TCP_CONG_BBR", "y", "Network (congestion)",
                "BBR congestion control — helps with lossy connections"),

    # == Debug options — must be disabled ==
    Requirement("CONFIG_PROVE_LOCKING", "n", "Debug Options",
                "debug-only, significant perf impact"),
    Requirement("CONFIG_KASAN", "n", "Debug Options",
                "kernel address sanitizer — debug only"),
    Requirement("CONFIG_KCOV", "n", "Debug Options",
                "code coverage — debug only"),
    Requirement("CONFIG_SLUB_DEBUG_ON", "n", "Debug Options",
                "~10% perf hit alone — see herecura-kconfig-bench"),

    # == TDX ==
    Requirement("CONFIG_INTEL_TDX_GUEST", "y", "TDX"),

    # == Cloud/VM Optimization — VirtIO ==
    Requirement("CONFIG_VIRTIO_PCI", "y", "Cloud/VM (VirtIO)"),
    Requirement("CONFIG_VIRTIO_BALLOON", "y", "Cloud/VM (VirtIO)"),
    Requirement("CONFIG_VIRTIO_NET", "y", "Cloud/VM (VirtIO)"),
    Requirement("CONFIG_VIRTIO_BLK", "y", "Cloud/VM (VirtIO)"),
    Requirement("CONFIG_VIRTIO_CONSOLE", "y", "Cloud/VM (VirtIO)"),

    # == Cloud/VM Optimization — paravirt ==
    Requirement("CONFIG_PARAVIRT", "y", "Cloud/VM (paravirt)"),
    Requirement("CONFIG_KVM_GUEST", "y", "Cloud/VM (paravirt)"),
    Requirement("CONFIG_HW_RANDOM_VIRTIO", "y", "Cloud/VM (paravirt)",
                "guest RNG via host — per kvm-tuning-guide"),

    # == Cloud/VM Optimization — timer ==
    Requirement("CONFIG_NO_HZ_IDLE", "y", "Cloud/VM (timer)",
                "stop timer tick when idle"),

    # == Storage and I/O ==
    Requirement("CONFIG_BLK_DEV_NVME", "y", "Storage/IO"),
    Requirement("CONFIG_NVME_CORE", "y", "Storage/IO"),
    # Requirement("CONFIG_BLK_MQ_VIRTIO", "y", "Storage/IO (investigate)",
    #             "flashbots-tdx-guide recommends for I/O speed; may be always-on in 6.18+"),

    # == Memory Management ==
    Requirement("CONFIG_TRANSPARENT_HUGEPAGE", "y", "Memory Management",
                "flashbots-tdx-guide recommends MADVISE mode"),
    Requirement("CONFIG_TRANSPARENT_HUGEPAGE_MADVISE", "y", "Memory Management",
                "opt-in only — avoids latency spikes"),

    # == TDX-redundant (should be disabled in TDX guests) ==
    Requirement("CONFIG_RESET_ATTACK_MITIGATION", "n", "TDX-redundant",
                "TDX uses ephemeral keys — cold boot N/A"),

    # == Hardening — debug overrides (perf impact) ==
    Requirement("CONFIG_DEBUG_VIRTUAL", "n", "Hardening (debug override)",
                "~72% sys-time increase — see herecura-kconfig-bench"),
    Requirement("CONFIG_DEBUG_SG", "n", "Hardening (debug override)"),
    Requirement("CONFIG_DEBUG_NOTIFIERS", "n", "Hardening (debug override)"),

    # == Hardening — zero-cost consensus ==
    Requirement("CONFIG_PANIC_ON_OOPS", "y", "Hardening (consensus)",
                "kspp-settings + clip-os-kernel + al2023-hardening all enable; prevents exploit retries after oops"),

    # == Borderline — potentially discuss ==
    # Requirement("CONFIG_BINFMT_MISC", "n", "Borderline",
    #             "kspp-settings says disable; unnecessary attack surface unless something uses it"),
    # Requirement("CONFIG_KSM", "n", "Borderline",
    #             "kvm-tuning-guide says y for memory dedup; clip-os-kernel says n for cache side-channel risk"),

    # == Needs benchmark — al2023-hardening excludes these, kspp-settings/clip-os-kernel enable ==
    # Requirement("CONFIG_INIT_ON_FREE_DEFAULT_ON", "y", "Needs benchmark",
    #             "al2023-hardening excludes citing perf; kspp-settings + clip-os-kernel enable"),
    # Requirement("CONFIG_ZERO_CALL_USED_REGS", "y", "Needs benchmark",
    #             "al2023-hardening excludes; wipes registers on function exit"),
    # Requirement("CONFIG_PAGE_TABLE_CHECK_ENFORCED", "y", "Needs benchmark",
    #             "checks every page table modification; overhead unknown"),
    # Requirement("CONFIG_KFENCE", "y", "Needs benchmark",
    #             "sampling-based memory safety; al2023-hardening excludes"),
    # Requirement("CONFIG_UBSAN_SANITIZE_ALL", "y", "Needs benchmark",
    #             "branch-check overhead on all code paths; in 01-hardening"),

    # == TDX-redundant — may disable for performance ==
    # Requirement("CONFIG_MITIGATION_PAGE_TABLE_ISOLATION", "n", "TDX-redundant (investigate)",
    #             "Meltdown fixed in silicon on TDX hardware (Sapphire Rapids+)"),
    # Requirement("CONFIG_INTEL_IOMMU_DEFAULT_ON", "n", "TDX-redundant (investigate)",
    #             "intel-ccc-guest TDX config disables; overhead in TDX guest"),

    # == TDX features — needs decision ==
    # Requirement("CONFIG_EFI_COCO_SECRET", "y", "TDX (investigate)",
    #             "TDX secret injection via EFI secret area"),
    # Requirement("CONFIG_EFI_SECRET", "y", "TDX (investigate)",
    #             "EFI secret module for confidential computing"),
    # Requirement("CONFIG_SWIOTLB_DYNAMIC", "y", "TDX (investigate)",
    #             "dynamic SWIOTLB — potential DMA perf improvement in TDX"),

    # == Azure-specific — enable if targeting Azure ==
    # Requirement("CONFIG_MLX5_CORE", "y", "Network (Azure)",
    #             "Mellanox NIC driver — per flashbots-tdx-guide network section"),
    # Requirement("CONFIG_MICROSOFT_MANA", "y", "Network (Azure)",
    #             "Azure MANA NIC — already in 02-sane-defaults"),
]


def parse_config(path: Path) -> dict[str, str]:
    """Parse a kernel .config into {option: value}."""
    config: dict[str, str] = {}
    not_set_re = re.compile(r"^# (CONFIG_\w+) is not set$")
    set_re = re.compile(r"^(CONFIG_\w+)=(.+)$")

    for line in path.read_text().splitlines():
        line = line.strip()
        m = not_set_re.match(line)
        if m:
            config[m.group(1)] = "n"
            continue
        m = set_re.match(line)
        if m:
            config[m.group(1)] = m.group(2)
    return config


def validate(config: dict[str, str], requirements: list[Requirement]) -> tuple[list, list, list]:
    """Returns (pass_list, fail_list, missing_list)."""
    passed, failed, missing = [], [], []

    for req in requirements:
        actual = config.get(req.option)
        if actual is None:
            # not present in config — treated as "n" for bool options
            actual_effective = "n"
        else:
            actual_effective = actual

        if actual_effective == req.value:
            passed.append((req, actual_effective))
        elif actual is None:
            missing.append((req, None))
        else:
            failed.append((req, actual_effective))

    return passed, failed, missing


def print_results(passed, failed, missing, verbose=False):
    total = len(passed) + len(failed) + len(missing)

    if failed:
        print(f"\n FAIL ({len(failed)}):")
        for req, actual in failed:
            note = f"  # {req.note}" if req.note else ""
            print(f"  {req.option}={actual}  (expected {req.value})"
                  f"  [{req.section}]{note}")

    if missing:
        print(f"\n MISSING ({len(missing)}):")
        for req, _ in missing:
            note = f"  # {req.note}" if req.note else ""
            print(f"  {req.option}  (expected {req.value})"
                  f"  [{req.section}]{note}")

    if verbose and passed:
        print(f"\n PASS ({len(passed)}):")
        for req, actual in passed:
            print(f"  {req.option}={actual}  [{req.section}]")

    print(f"\n--- {len(passed)}/{total} passed", end="")
    if failed:
        print(f", {len(failed)} failed", end="")
    if missing:
        print(f", {len(missing)} missing", end="")
    print(" ---")

    return len(failed) + len(missing)


def main():
    parser = argparse.ArgumentParser(
        description="Validate kernel .config against Flashbots TDX requirements")
    parser.add_argument("config", help="path to .config file")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="show passing checks too")
    args = parser.parse_args()

    path = Path(args.config)
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        return 1

    config = parse_config(path)
    print(f"Loaded {len(config)} options from {path}")

    passed, failed, missing = validate(config, REQUIREMENTS)
    errors = print_results(passed, failed, missing, args.verbose)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
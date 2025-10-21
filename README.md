# Flashbots Images 📦⚡📦

**Reproducible hardened Linux images for confidential computing and safe MEV**

This repository provides a toolkit for building minimal, hardened Linux images designed for confidential computing environments and MEV (Maximum Extractable Value) applications. Built on mkosi and Nix, it provides reproducible, security-focused Linux distributions with strong network isolation, attestation capabilities, and blockchain infrastructure support.

It contains our [bottom-of-block searcher sandbox](https://collective.flashbots.net/t/searching-in-tdx/3902) infrastructure and will soon contain our [BuilderNet](https://buildernet.org/blog/introducing-buildernet) infrastructure as well, along with any future TDX projects we implement.

For more information about this repository, see [the Flashbots collective post](https://collective.flashbots.net/t/beyond-yocto-exploring-mkosi-for-tdx-images/4739).

## 🌟 Features

- **Reproducible Builds**: Deterministic image generation using Nix and frozen Debian snapshots
- **Confidential Computing**: Built-in support for Intel TDX and remote attestation
- **Minimal Attack Surface**: Uses very few packages (20Mb base)
- **Flexible Deployment**: Support for Bare Metal TDX, QEMU, Azure, and GCP

## 🚀 Quick Start

### Prerequisites

0. Make sure you're running systemd v250 or greater. Alternatively, you can utilize experimental [container support](DEVELOPMENT.md#building-with-podman-not-recommended).

1. **Install Nix** (single user mode is sufficient):
   ```bash
   sh <(curl -L https://nixos.org/nix/install) --no-daemon
   ```

2. **Enable Nix experimental features** in `~/.config/nix/nix.conf`:
   ```
   experimental-features = nix-command flakes
   ```

3. **Install Debian archive keyring** (temporary requirement):
   ```bash
   # On Ubuntu/Debian
   sudo apt install debian-archive-keyring
   # On other systems, download via package manager or use Docker approach below
   ```

### Building Images

**Using Make (Recommended)**:
```bash
# Build the BOB (searcher sandbox) image
make build IMAGE=bob

# Build the Buildernet image
make build IMAGE=buildernet

# Build with development tools
make build-dev IMAGE=bob

# View all available targets
make help
```

**Manual Build**:
```bash
# Enter the development environment
nix develop -c $SHELL

# Build a specific image
mkosi --force -I bob.conf
mkosi --force -I buildernet.conf

# Build with profiles
mkosi --force -I bob.conf --profile=devtools
mkosi --force -I bob.conf --profile=azure
mkosi --force -I bob.conf --profile=azure,devtools
```

### Measuring TDX Boot Process

**Export TDX measurements** for the built image:
```bash
make measure
```

This generates measurement files in the `build/` directory for attestation and verification.

### Running Images

**Create persistent storage** (for stateful applications):
   ```bash
   qemu-img create -f qcow2 persistent.qcow2 2048G
   ```

**Run QEMU**:
  ```bash
  sudo qemu-system-x86_64 \
    -enable-kvm \
    -machine type=q35,smm=on \
    -m 16384M \
    -nographic \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd \
    -drive file=/usr/share/edk2/x64/OVMF_VARS.4m.fd,if=pflash,format=raw \
    -kernel build/tdx-debian.efi \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-scsi-pci,id=scsi0 \
    -drive file=persistent.qcow2,format=qcow2,if=none,id=disk0 \
    -device scsi-hd,drive=disk0,bus=scsi0.0,channel=0,scsi-id=0,lun=10
  ```

**With TDX confidential computing** (requires TDX-enabled hardware/hypervisor):
  ```bash
  sudo qemu-system-x86_64 \
    -accel kvm \
    -machine type=q35,kernel_irqchip=split,confidential-guest-support=tdx0 \
    -object tdx-guest,id=tdx0 \
    -cpu host,-kvm-steal-time,-kvmclock \
    -m 16384M \
    -nographic \
    -kernel build/tdx-debian.efi \
    # ... rest of options same as above
  ```

> Depending on your Linux distro, these commands may require changing the supplied OVMF paths or installing your distro's OVMF package.

## 📖 Documentation

- [Development Guide](DEVELOPMENT.md) - Comprehensive guide for creating new modules and extending existing ones
- [BOB Module Guide](bob-common/readme.md) - Detailed documentation for the MEV searcher environment

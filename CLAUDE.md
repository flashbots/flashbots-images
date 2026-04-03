## Project Overview

Toolkit for building reproducible Linux VM images for [BuilderNet](https://buildernet.org/) using [mkosi](https://github.com/systemd/mkosi) (systemd's OS image builder). Images target Debian Trixie and support Azure, GCP, and QEMU platforms.

Include GOTCHAS file into the context

## Build Commands

```bash
# Install mkosi (pinned version)
pip3 install git+https://github.com/systemd/mkosi.git@$(cat .mkosi_version)

# On Ubuntu, also need:
sudo apt-get update && sudo apt-get install -y debian-archive-keyring

# Build all images
mkosi -I buildernet.conf

# Force rebuild
mkosi --force -I buildernet.conf

# Build with reproducible umask (needed on Ubuntu which defaults to 002)
(umask 022; mkosi --force -I buildernet.conf)

# Build with a profile (devtools adds debugging tools, playground for local dev)
mkosi --profile=devtools -I buildernet.conf
mkosi --profile=playground -I buildernet.conf
```

## Architecture

### Image dependency chain
```
base → buildernet → buildernet-{azure,gcp,qemu}
```

- **`mkosi.images/base/`** — Base OS with custom Linux kernel. Kernel config fragments live in `kernel/configs/` and are merged via `merge_config.sh`.
- **`mkosi.images/buildernet/`** — Core services and configuration. `mkosi.extra/` is overlaid onto `/` in the image.
- **`mkosi.images/buildernet-{azure,gcp,qemu}/`** — Platform-specific UKI (Unified Kernel Image) packaging.

### Entry point
`buildernet.conf` is the main mkosi config. Individual images extend/override it via their own `mkosi.conf` files.

### Build profiles (`mkosi.profiles/`)
Build profiles extend the final image with extra functionality (e.g., autologin in the `local` profile). Profiles apply to all built images. E.g., doing `mkosi --profile=local -I buildernet.conf` will build three images with the local profile applied to each image.

### Configuration templates
Templates in `mkosi.images/buildernet/mkosi.extra/usr/lib/mustache-templates/` are rendered at boot using values fetched from BuilderHub. The directory structure mirrors the filesystem destination.

Template file suffixes:
- `_unsafe` — Enables Go control character interpretation (e.g., `\n` becomes newline)
- `_600`, `_400` — Sets file mode on the rendered output
- Suffixes combine in order: `template-foo_unsafe_600`

### Key services (systemd)
reth (Ethereum execution), lighthouse (consensus), rbuilder-operator, rbuilder-bidding, operator-api, haproxy, vector (metrics/logs), attested-tls-proxy, flowproxy, config-watchdog, acme-le (Let's Encrypt)

### System users
Defined in `mkosi.images/buildernet/mkosi.extra/etc/sysusers.d/`.

## Development Conventions

- **Stick to systemd-native approaches**: use `systemd-resolved`, `systemd-networkd`, `sysusers.d`, `tmpfiles.d`, etc. If systemd provides a component that does the job, use it.
- **Use standard mkosi directory names** so mkosi auto-discovers them.
- **Reproducibility**: `SourceDateEpoch=0` and a fixed `Seed` GUID ensure deterministic builds. Output images built from the same git revision on different flavors of Linux must bit bit-identical. Reproducibility is **VERY** important. Never break reproducibility of production images.

## CI/CD

- **release.yml** — Triggered on `buildernet-v*` tags; builds, signs (minisign), and uploads to R2
- **reprotest.yml** — Builds on 2 machines, compares SHA256 to verify reproducibility
- **playground-test.yml** — Integration tests with builder-playground

## Docs
- mkosi docs is here: https://raw.githubusercontent.com/systemd/mkosi/<mkosi_version_sha>/mkosi/resources/man/mkosi.1.md. Never use the latest version of the mkosi docs. Lookup the SHA from the `.mkosi_version` first.
- if the target flavor of the image matches local OS prefer using manpages to lookup the documentation for the packages (e.g., for systemd).

Read HACKING file to understand how to deal with kernel fragments, testing images locally with qemu, Vector relabeling.

# Development

## Building

On Linux, install mkosi as per the README and use `mkosi -I buildernet.conf` directly,
or use the make targets below with a `.bypass-lima` file in the repo root.

On macOS (or any host without native mkosi support), the make targets run every command
inside a per-repo [Lima](https://lima-vm.io) VM (`brew install lima`). The VM is created
automatically on first use from `lima.yaml`, with the repo mounted at `~/mnt` and mkosi
installed into a venv pinned to `.mkosi_version`.

```bash
make help          # list targets
make smoke         # tiny test image. validates the toolchain
make build         # full BuilderNet images (azure, gcp, qemu)
make build-dev     # + devtools profile (apt, tcpdump, strace, vim, ...)
make build-local   # + local profile too (root autologin), for `make boot`
make boot          # boot the built qemu UKI (kernel log on stdio; Ctrl-A X to exit)
make console       # second terminal: root shell via hvc0 (local profile autologin)
make clean         # remove build artifacts (keeps the VM)
make stop-vm       # stop all tee-builder Lima VMs (keeps disks; restarts on next make)
make clean-vm      # delete the Lima VM entirely
```

Resource overrides at VM creation time: `LIMA_CPUS=12 LIMA_MEMORY=32GiB make build`.
To resize an existing VM, edit `~/.lima/tee-builder-*/lima.yaml` and restart it.

### How the Lima build works

`scripts/env_wrapper.sh`:
1. Creates/starts a VM named `tee-builder-<sha256(repo path)[:8]>` (one VM per checkout).
2. Ensures a venv with mkosi pinned to `.mkosi_version` exists inside the VM.
3. rsyncs the working tree to a VM-local directory (`~/.cache/tee-builder/src`) and runs
   the command there. mkosi cannot build directly on the virtiofs mount: it is slow and
   mkosi's cross-device rename fallback breaks on hardlink-rich trees (e.g. the default
   tools tree). Cache/build dirs persist VM-side between builds.
4. Copies resulting artifact files back to `mkosi.output/` in the repo.

Apple Silicon note: images are x86-64 (`--architecture=x86-64` is set by the Makefile but
the kernel config is amd64-only). Build scripts run under Rosetta; booting with
`make boot` uses TCG emulation, so guest boot takes a few minutes.

### Gotchas

- First build downloads a ~1.6G mkosi tools tree and compiles the kernel; expect ~20 min
  on native Linux, noticeably longer under Rosetta.
- For iteration speed when you don't need reth/lighthouse, put `exit 0` at the top of
  `mkosi.images/buildernet/mkosi.build.d/{10-reth,18-lighthouse}.sh.chroot` (do not commit).

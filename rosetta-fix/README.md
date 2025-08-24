# rosetta-fix

So, this abomination exists to support running mkosi under Rosetta on M\* macs.

For some reason, Rosetta does not translate `mount_setattr` syscall to host
kernel, instead returning `ENOSYS`. This syscall is used by `mkosi-sandbox`
to recursively mark mounts as readonly. Unsafe fix would be to remove this call,
making some mounts writable inside the sandbox.

This thing exists to fix the issue properly (only within `mkosi-sandbox`).
When running in Rosetta, we actually can call aarch64 binaries from translated
x86_64 process, so `mkosi-sandbox-mount-rbind.c` is an implementation of
`mount_rbind` function from `mkosi/sandbox.py`.

In `flake.nix`, it gets cross-compiled as static aarch64 binary, and then we
patch `mkosi/sandbox.py` to write and exec this binary instead of using syscall.

As `mount_rbind` is called often after setting up sandbox, the patch writes
this static binary to either `/oldroot/tmp` (if exists), or `/tmp` otherwise.
This seems to handle all cases I've encountered so far.

Ugly, but works.

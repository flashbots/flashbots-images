# Flashboxes Development Guide

This comprehensive guide covers everything you need to know about developing with Flashboxes, from creating new modules to testing for reproducibility.

## Table of Contents

- [Project Structure](#project-structure)
- [Creating a New Module](#creating-a-new-module)
- [Adding Files to Modules](#adding-files-to-modules)
- [Common mkosi Configuration Options](#common-mkosi-configuration-options)
- [Custom Kernel Configuration](#custom-kernel-configuration)
- [Adding Source Repositories](#adding-source-repositories)
- [Creating systemd Services](#creating-systemd-services)
- [Extending Built-in systemd Services](#extending-built-in-systemd-services)
- [Freezing to Debian Archive Snapshots](#freezing-to-debian-archive-snapshots)
- [Testing for Reproducibility](#testing-for-reproducibility)
- [Creating Debian Packages](#creating-debian-packages)
- [Debugging and Troubleshooting](#debugging-and-troubleshooting)

## Project Structure

```
flashboxes/
├── base/                   # Core minimal Linux system
│   ├── mkosi.conf          # Base mkosi configuration
│   ├── mkosi.skeleton/     # Base filesystem overlay
│   └── debloat*.sh         # System cleanup scripts
├── bob-common/             # TEE Searcher common image
├── bob-l1/                 # L1 TEE Searcher sandbox image
├── buildernet/             # BuilderNet
├── tdx-dummy/              # TDX test environment
├── kernel/                 # Kernel configuration
│   ├── kernel-yocto.config # Base kernel config
│   └── snippets/           # Additional config fragments
├── scripts/                # Build helper scripts
├── services/               # Shared systemd services
└── mkosi.profiles/         # Build profiles (devtools, azure)
```

## Creating a New Module

A module in Flashboxes is a collection of configuration files that define how to build a specific type of image. Each module inherits from the base configuration and adds its own customizations.

### Step 1: Create Module Directory Structure

```bash
mkdir mymodule/
cd mymodule/

# Create the basic files
touch mymodule.conf      # Main configuration
touch mkosi.build        # Build script (optional)
touch mkosi.postinst     # Post-installation script (optional)
mkdir mkosi.extra/       # File overlays

# Scripts need the executable bit set
chmod +x mkosi.build mkosi.postinst
```

### Step 2: Create Module Configuration

**`mymodule/mkosi.conf`**:
```ini
[Build]
# Environment variables available in scripts
Environment=MY_CUSTOM_VAR
# Enable network access during build (needed for downloads)
WithNetwork=true

[Content]
# File overlays
ExtraTrees=mymodule/mkosi.extra
# Scripts to run during build phase
BuildScripts=mymodule/mkosi.build
# Scripts to run after package installation
PostInstallationScripts=mymodule/mkosi.postinst

# Packages to install
Packages=curl
         wget
         python3
# Packages needed only during build
BuildPackages=build-essential
              git
              golang
```

### Step 3: Create Top-Level Configuration

**`mymodule.conf`** (in project root):
```ini
[Include]
Include=base/mkosi.conf
Include=mymodule/mkosi.conf
```

### Step 4: Build Your Module

```bash
nix develop -c mkosi --force -I mymodule.conf
```

## Adding Files to Modules

There are two main ways to add custom files to your module. **mkosi.extra is preferred** because files are placed after package installation and can override default package files. To add overlay files before packages are installed, use `SkeletonTrees` and `mkosi.skeleton` instead of `ExtraTrees` and `mkosi.extra`

To add files:

```bash
mkdir -p mymodule/mkosi.extra/etc/systemd/system/
mkdir -p mymodule/mkosi.extra/usr/bin/
mkdir -p mymodule/mkosi.extra/home/myuser/

# Add a custom systemd service
cat > mymodule/mkosi.extra/etc/systemd/system/myservice.service << 'EOF'
[Unit]
Description=My Custom Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/myapp
Restart=always

[Install]
WantedBy=minimal.target
EOF

# Add a custom script
cp myscript mymodule/mkosi.extra/usr/bin/
chmod +x mymodule/mkosi.extra/usr/bin/myscript

# Add configuration files
echo "config_value=123" > mymodule/mkosi.extra/etc/myapp.conf
```

### File Permissions and Ownership

Files copied via mkosi.extra inherit permissions from the source. To set specific permissions or ownership, use the post-installation script:

**`mymodule/mkosi.postinst`**:
```bash
#!/bin/bash
set -euxo pipefail

# Set file permissions
chmod 600 "$BUILDROOT/etc/myapp.conf"
chmod +x "$BUILDROOT/usr/bin/myapp"

# Set ownership (must use mkosi-chroot for user/group operations)
mkosi-chroot chown root:root /home/myuser/config
```

## Common mkosi Configuration Options

Here are the most commonly used mkosi configuration options for modules:

### [Build] Section

```ini
[Build]
# Environment variables for scripts
Environment=VAR1 VAR2=value
# Enable network during build
WithNetwork=true
```

### [Content] Section

```ini
[Content]
# File overlays
ExtraTrees=module/mkosi.extra
SkeletonTrees=module/mkosi.skeleton
# Build and post-install scripts
BuildScripts=module/mkosi.build
PostInstallationScripts=module/mkosi.postinst
# Package selection
Packages=package1 package2
BuildPackages=build-only-package
```

For comprehensive mkosi options, see: [mkosi Documentation](https://github.com/systemd/mkosi/blob/main/mkosi/resources/man/mkosi.1.md)

## Custom Kernel Configuration

Flashboxes supports custom kernel configurations through base configs and snippets.

### Using Kernel Snippets

Create a custom kernel config snippet in your module folder:

**`module/kernel.config`**:
```
# Enable custom features
CONFIG_MY_FEATURE=y
```

**Enable in your module**:
```ini
[Build]
Environment=KERNEL_CONFIG_SNIPPETS=module/kernel.config,module/another-kernel-snippet.config
```

These snippets will be applied over the base configuration in `kernel/kernel-yocto.config`

## Adding Source Repositories

Flashboxes provides helper scripts for building software from source repositories.

### Building Rust Projects

Use the `build_rust_package.sh` script for Rust/Cargo projects:

**In your `mkosi.build` script**:
```bash
#!/bin/bash
set -euxo pipefail

source scripts/build_rust_package.sh

# Build a Rust package
build_rust_package \
    "lighthouse" \                             # Package name
    "v7.0.1" \                                 # Git tag
    "https://github.com/sigp/lighthouse.git" \ # Repository URL
    "$LIGHTHOUSE_BINARY" \                     # Pre-built binary (optional)
    "modern" \                                 # Cargo features (optional)
    "-l z -l zstd -l snappy"                   # Extra RUSTFLAGS (optional)

# Package will be installed to /usr/bin/lighthouse
```

### Building Generic Projects

Use the `make_git_package.sh` script for Go and other projects:

**In your `mkosi.build` script**:
```bash
#!/bin/bash
set -euxo pipefail

source scripts/make_git_package.sh

# Build a Go package
make_git_package \
    "myapp" \                                 # Package name
    "v1.0.0" \                                # Git tag
    "https://github.com/user/myapp" \         # Repository URL
    'go build -o ./build/myapp cmd/main.go' \ # Build command
    "build/myapp:/usr/bin/myapp"              # src:dest mapping

# Multiple artifacts supported
make_git_package \
    "multi-tool" \
    "v2.0.0" \
    "https://github.com/user/multi-tool" \
    'make build' \
    "bin/tool1:/usr/bin/tool1" \
    "bin/tool2:/usr/bin/tool2" \
    "config/default.conf:/etc/multi-tool.conf"
```

### Build Caching

Both scripts automatically cache built artifacts based on package name and version. Cached builds are stored in `$BUILDDIR/package-version/` and significantly speed up subsequent builds.

## Creating systemd Services

systemd services are the primary way to run applications in Flashboxes. Here's how to create and configure them.

### Basic Service Creation

**`mymodule/mkosi.extra/etc/systemd/system/myapp.service`**:
```ini
[Unit]
Description=My Application
After=network.target network-setup.service
Requires=network-setup.service

[Service]
Type=simple
ExecStart=/usr/bin/myapp --config /etc/myapp.conf
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=minimal.target
```

### Common Service Configurations

**Long-running daemon**:
```ini
[Service]
Type=simple                    # Service doesn't fork
ExecStart=/usr/bin/myapp
Restart=always                 # Always restart on exit
RestartSec=5                   # Wait 5s before restart
```

**One-shot service**:
```ini
[Service]
Type=oneshot                  # Runs once and exits
ExecStart=/usr/bin/setup-task
RemainAfterExit=yes           # Needed to use this service as a dependency
```

**User/Group isolation**:
```ini
[Service]
User=myuser
Group=mygroup
# Create user in postinst script:
# mkosi-chroot useradd -r -s /bin/false myuser
```

**Security hardening**:
```ini
[Service]
# Sandboxing
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
# Capabilities
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
# Resource limits
MemoryMax=1G
CPUQuota=50%
```

### Service Dependencies

**Dependency types**:
```ini
[Unit]
# Must start after these services
After=network.target postgresql.service
# Require these services (will start them)
Requires=network.target
# Want these services (prefer but don't require)
Wants=postgresql.service
# Conflicts with these services
Conflicts=apache2.service
```

**Common Flashboxes dependencies**:
```ini
[Unit]
# Network is available
After=network.target network-setup.service
Requires=network-setup.service

# Persistent storage is mounted
After=persistent-mount.service
Requires=persistent-mount.service

# Basic system is ready
After=basic.target
```

### Enabling Services

**In `mkosi.postinst` script**:
```bash
#!/bin/bash
set -euxo pipefail

# Enable service
mkosi-chroot systemctl enable myapp.service

# Create symlink for minimal.target
mkdir -p "$BUILDROOT/etc/systemd/system/minimal.target.wants"
ln -sf "/etc/systemd/system/myapp.service" \
    "$BUILDROOT/etc/systemd/system/minimal.target.wants/"
```

For comprehensive systemd options, see: [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

## Extending Built-in systemd Services

Sometimes you need to modify existing systemd services rather than creating new ones.

### Using Drop-in Files

Create drop-in directories to override specific settings:

**`mymodule/mkosi.extra/etc/systemd/system/dropbear.service.d/custom.conf`**:
```ini
[Unit]
# Add additional dependencies
After=wait-for-key.service
Requires=wait-for-key.service

[Service]
# Override or add environment variables
Environment=DROPBEAR_EXTRA_ARGS="-s -w -g"
# Add pre-start commands
ExecStartPre=/usr/bin/setup-keys
```

### Masking Unwanted Services

**In `mkosi.postinst` script**:
```bash
# Disable and mask unwanted services
mkosi-chroot systemctl disable ssh.service ssh.socket
mkosi-chroot systemctl mask ssh.service ssh.socket

# Create mask symlinks manually if needed
ln -sf /dev/null "$BUILDROOT/etc/systemd/system/unwanted.service"
```

### Overriding Service Files Completely

Place a complete service file in `mkosi.extra/etc/systemd/system/` to completely override the package default:

**`mymodule/mkosi.extra/etc/systemd/system/nginx.service`**:
```ini
[Unit]
Description=Custom Nginx Configuration
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/nginx -c /etc/nginx/custom.conf
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=mixed

[Install]
WantedBy=multi-user.target
```

## Freezing to Debian Archive Snapshots

For production deployments, it's critical to pin your builds to specific Debian archive snapshots to ensure reproducibility and security.

### Finding the Right Snapshot

1. **Browse available snapshots**: [Debian Snapshot Archive](https://snapshot.debian.org/)
2. **Choose a recent stable snapshot**: Ideally, pick the most recent snapshot
3. **Test the snapshot**: Build with the snapshot and verify all packages install correctly

### Pinning in Configuration

**In your module configuration**:
```ini
[Distribution]
Mirror=https://snapshot.debian.org/archive/debian/20250526T142542Z/

[Build]
ToolsTreeMirror=https://snapshot.debian.org/archive/debian/20250526T142542Z/
```

⚠ Update snapshots regularly to get security patches

## Testing for Reproducibility

Reproducible builds are essential for security and trust. Here's how to verify your builds are deterministic.

### Basic Reproducibility Test

```bash
# Build twice
mkosi --force -I mymodule.conf
cp build/mymodule-image.efi build/first-build.efi

mkosi --force -I mymodule.conf
cp build/mymodule-image.efi build/second-build.efi

# Compare hashes
sha256sum build/first-build.efi build/second-build.efi

# Should show identical hashes
```

### Detailed Comparison with diffoscope

```bash
# Install diffoscope
apt install diffoscope

# Compare builds in detail
diffoscope build/first-build.initrd build/second-build.initrd
```

## Creating Debian Packages

For distributing software that's not available in Debian repositories, you can create custom .deb packages.

### Basic Package Structure

```
mypackage-1.0/
├── DEBIAN/
│   ├── control          # Package metadata
│   ├── postinst         # Post-installation script
│   ├── prerm           # Pre-removal script
│   ├── postrm          # Post-removal script
│   └── preinst         # Pre-installation script
├── usr/
│   └── bin/
│       └── myapp       # Your application
└── etc/
    └── myapp/
        └── config.conf # Configuration files
```

### Package Metadata (control)

**`DEBIAN/control`**:
```
Package: mypackage
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.34), libssl3
Maintainer: Your Name <your.email@example.com>
Description: My custom application
 Longer description of what this package does.
 Each line should be indented with a space.
```

### Post-installation Script

**`DEBIAN/postinst`**:
```bash
#!/bin/bash
set -e

# Create system user
useradd -r -s /bin/false myapp || true

# Set permissions
chown myapp:myapp /etc/myapp/config.conf
chmod 600 /etc/myapp/config.conf

# Enable systemd service
systemctl enable myapp.service || true
systemctl start myapp.service || true

exit 0
```

### Pre-removal Script

**`DEBIAN/prerm`**:
```bash
#!/bin/bash
set -e

# Stop service before removal
systemctl stop myapp.service || true
systemctl disable myapp.service || true

exit 0
```

### Post-removal Script

**`DEBIAN/postrm`**:
```bash
#!/bin/bash
set -e

case "$1" in
    purge)
        # Remove user and data on purge
        userdel myapp || true
        rm -rf /var/lib/myapp
        ;;
    remove)
        # Keep data on remove
        ;;
esac

exit 0
```

### Building the Package

```bash
# Build the .deb file
dpkg-deb --build mypackage-1.0

# Verify package contents
dpkg -c mypackage-1.0.deb

# Install locally for testing
sudo dpkg -i mypackage-1.0.deb
```

### Package Scripts Execution Order

1. **Installation**: `preinst` → files copied → `postinst`
2. **Upgrade**: `preinst upgrade` → files copied → `postinst configure`
3. **Removal**: `prerm remove` → files removed → `postrm remove`
4. **Purge**: `prerm remove` → files removed → `postrm purge`

For comprehensive .deb creation, see: [Debian New Maintainers' Guide](https://www.debian.org/doc/manuals/maint-guide/)

## Building with Podman (Not Recommended)
For systems without systemd v250+ or where Nix installation isn't feasible, you can use the experimental Podman containerization support. This approach is not recommended due to slower build times and a complex setup process.
1. Configure the Podman daemon to use a storage driver other than OverlayFS
   - The btrfs driver is fastest, but requires that you have a btrfs filesystem
   - The storage driver can be configuring by editing `/etc/containers/storage.conf`
2. Build the development container:
   ```
   sudo podman build -t flashbots-images .
   ```
3. Create required directories
   ```
   mkdir mkosi.packages mkosi.cache mkosi.builddir build
   ```
4. Run the container with proper mounts and privilages
   ```
   sudo podman run \
     --storage-driver btrfs \
     --privileged \
     --cap-add=ALL \
     --security-opt label=disable \
     -it \
     -v $(pwd)/mkosi.packages:/home/ubuntu/mkosi/mkosi.packages \
     -v $(pwd)/mkosi.cache:/home/ubuntu/mkosi/mkosi.cache \
     -v $(pwd)/mkosi.builddir:/home/ubuntu/mkosi/mkosi.builddir \
     -v $(pwd)/build:/home/ubuntu/mkosi/build \
     flashbots-images
   ```
   > Replace "btrfs" with your chosen storage driver
5. Run the desired `mkosi` command inside the shell Podman environment

## Debugging and Troubleshooting

### mkosi Debugging

**Interactive debugging during build**:
```bash
# Add to your build script where you want to break
socat UNIX-LISTEN:$SRCDIR/debug.sock,fork EXEC:/bin/bash,pty,stderr

# Then connect from host
script -qfc "socat STDIO UNIX-CONNECT:debug.sock" /dev/null
```

**Access the build chroot**:
```bash
# From debug session
mkosi-chroot /bin/bash
```

### Build Troubleshooting

**Package installation failures**:
```bash
# Check package availability
mkosi-chroot apt search mypackage
mkosi-chroot apt policy mypackage

# Check repository configuration
cat $BUILDROOT/etc/apt/sources.list
```

**Network issues during build**:
```ini
[Build]
# Ensure network is enabled
WithNetwork=true
```

**Permission issues**:
```bash
# Check file ownership in build
ls -la $BUILDROOT/path/to/file
```

> ⚠ Sometimes, postinst files are not able to dynamically chown files. In this case, the only option is to set permissions from an early one-shot boot service.

### Runtime Debugging

**Boot debugging**:
```ini
[Content]
# Add debug options to kernel command line
KernelCommandLine=console=ttyS0,115200n8 systemd.show_status=1 systemd.log_level=debug
```

**Service debugging**:
```bash
# Inside running system
journalctl -u myservice.service
systemctl status myservice.service
```

**Development profile**:
```bash
# Build with debugging tools
mkosi --force -I mymodule.conf --profile devtools
```

Toolkit for building VM images of [BuilderNet](https://buildernet.org/)

# Quickstart
Tested on Debian Trixie and Ubuntu 24.04
```
pip3 install git+https://github.com/systemd/mkosi.git@$(cat .mkosi_version)
# On Ubuntu
sudo apt-get update && sudo apt-get install -y debian-archive-keyring

mkosi -I buildernet.conf
```

# What is this?
This repository contains source code and configuration files for building Linux VM images for BuilderNet using [`mkosi`](https://github.com/systemd/mkosi).

The configuration supports building multiple flavors of the image for different platforms: Azure, GCP, and QEMU (see `mkosi.images` directory).

The entrypoint for the build is the main configuration file `buildernet.conf`. It defines basic parameters shared between the images. Each individual image may extend and override the main configuration (see [`mkosi` manual](https://github.com/systemd/mkosi/blob/main/mkosi/resources/man/mkosi.1.md#building-multiple-images)).

Final images depend on the successful build of the intermediate images. All of Azure, GCP, and QEMU images depend on `buildernet` image which in turn depends on `base` image.

BuilderNet images use Debian Trixie as a base. The images have low footprint and designed to be run fully in memory. One can still attach a persistent disk if needed (expected to mount at `/var/lib/persistent`).

We build a custom Linux kernel using Debian's source kernel package with a bunch of configuration overrides (see `base` image) and, optionally, patches.

`mkosi` produces UKI images that can be booted directly as a EFI image using a systemd UEFI stub. To make the images compatible with different platforms post-output scripts further massage it wrapping in a platform-friendly container. E.g., VHD for Azure, raw disk image packaged as *.tar.gz for GCP.

## Base image
Located in `mkosi.images/base` is the base intermediate image that is shared between all downstream images.

This image builds a custom Linux kernel with configuration and patches overrides. The kernel uses `linux-config` Debian package for the base kernel configuration: (`config.amd64_none_cloud-amd64` configuration file)

We further tweak the base config by disabling unnecessary modules/drivers (see `kernel/configs`). All the configuration fragments are merged and applied on top the default configuration.

If you want to produce a new fragment you can use the tools that come with the Linux kernel source tree:
1. Clone the version of the kernel that matches one used in the image
2. Grab the base config (e.g., `config.amd64_none_cloud-amd64`) by installing the `linux-config` package matching the kernel version
3. Navigate to the Linux source tree directory
4. Apply existing overrides on top of it using the script located in the kernel tree
```
./scripts/kconfig/merge_config.sh -O . <path to config.amd64_none_cloud-amd64> <path to flashbots-images/mkosi.images/base/kernel/configs/*>
```
This will produce a file `.config` that you can tweak using `menuconfig` (e.g., `make nconfig` for the ncurses menuconfig)
1. After you're done with tweaking, save the config under the new name, e.g., `.config_new`
2. Produce a fragment by diff'ing the configs
```
./scripts/diffconfig -m .config .config_new > <path to flashbots-images/mkosi.images/base/kernel/configs/new-fragment>
```

## BuilderNet image
Located in `mkosi.images/builernet` is the intermediate image containing the main logic shared between all the downstream "flavored" images

`mkosi.extra` directory contains the most of the configuration. During the build `mkosi` copies this directory into the resulting file tree of the image on top of `/`.

Some packages needed for the image we install from the Debian official repos (see `Packages=`), some are pulled as *.deb files from the projects' repos, some are pulled as binaries, some are built from source during the image build.

### Configuration templates
We rely on the templates for configuration files of the services running inside the image. It allows us to avoid hardcoding configuration and secrets while still maintaining security and developer experience.

The templates are stored in `usr/lib/mustache-templates`. As the name suggests we use [`mustache`](https://github.com/cbroglie/mustache) for rendering the templates.

When the instance boots it attempts to fetch the values from [BuilderHub](https://github.com/flashbots/builder-hub/), render each template in the directory, and putting the resulting file to a destination. Destination path is defined by the structure of the `mustache-templates` directory. `mustache-templates` directory is treated as filesystem, files relative to it will be copied to a destination replication the directory structure.

Template files optionally support `unsafe` and file mode settings suffixes, in that order. E.g., a file named `template-foo_unsafe_600` will be rendered with [Go's control characters](https://go.dev/ref/spec#Rune_literals) enabled (e.g., `\n` in the value will insert a new line instead of escaping it and printing literally), and a file mode set to `600`.


# Reproducibility
BuilderNet image are [reproducible](https://reproducible-builds.org/). Images built on two different machines from the same git revision should produce bit-identical UKI images. We tested reproducibility on Debian Trixie and Ubuntu 24.04 host OSes.

To verify that our official images are built from the corresponding git revision:
1. Navigate to https://downloads.buildernet.org and grab the version of the image (starting from 2.0.0) that you want to verify (*.efi)
2. In the *.minisig file find the git commit that this image was built from and check out to it
3. Build the image with `(umask 022; mkosi --force -I buildernet.conf)` command. `umask` here is to fight the discrepancy between Debian (that uses `002` by default) and Ubuntu (that uses `022` by default)
4. Calculate the SHA256 hashsum of the *.efi image in the `mkosi.output` directory. It should match the hashsum from the *.sha256 file from https://downloads.buildernet.org

# Measurements
Measurement are a way to verify that the image you built offline matches the one running as a VM.

To measure a Azure image:
1. Clone github.com/flashbots/measured-boot/ repo and build the `measured-boot` script
```
go build
```
2. Measure the image offline
```
./measured-boot image.efi /dev/null --direct-uki
```
3. Clone github.com/flashbots/cvm-reverse-proxy repo and build the `attested-get` tool
```
go build cmd/attested-get/main.go
```
4. Measure the deployed image
```
./attested-get --addr=https://<instance IP>:7936
```
5. Compare PCRs 4 and 11 of the offline image and the deployed one, they should match.

To measure a GCP image:
1. Clone github.com/flashbots/dstack-mr-gcp repo and build the `dstack-mr` tool
```
go build
```
2. Measure the image offline
```
./dstack-mr -uki buildernet-gcp.efi
```
3. Clone github.com/flashbots/cvm-reverse-proxy repo and build the `attested-get` tool
```
go build cmd/attested-get/main.go
```
4. Measure the deployed image
```
./attested-get --addr=https://<instance IP>:7936
```
5. Compare PCRs 0-4 of the offline image and the deployed one, they should match.

# Development
- Use standard directory names of `mkosi` so that it can automatically pick it up.
- Stick to systemd-native way of doing things. If there is a systemd component that does the job right, use it. E.g., `systemd-resolved` is good enough as a local DNS resolver/caching layer. `systemd-networkd` is a decent networking management tool. Instead of creating users manually use `sysusers.d`. Use `tmpfiles.d` to create dynamic files.

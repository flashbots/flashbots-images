#!/bin/bash
set -euo pipefail
shopt -s inherit_errexit  # propagate errexit to $() subshells

# KERNEL_VERSION must be set (Debian major.minor, e.g. "6.16").
# Must match a linux-source package available in the pinned snapshot mirror.
if [[ -z "${KERNEL_VERSION:-}" ]]; then
    echo "ERROR: KERNEL_VERSION is not set. Set it in mkosi.conf Environment= (e.g. KERNEL_VERSION=6.16)" >&2
    exit 1
fi

# Read distribution info from mkosi config JSON
snapshot=$(jq -re '.Snapshot' "$MKOSI_CONFIG")
release=$(jq -re '.Release' "$MKOSI_CONFIG")
echo "Snapshot: $snapshot"
echo "Release: $release"

# Auto-discover config fragments from registered directories
# KERNEL_CONFIG_SNIPPETS is processed first, then KERNEL_CONFIG_SNIPPETS_* in alphabetical order
config_paths=()
for dir_var in "${!KERNEL_CONFIG_SNIPPETS@}"; do
    config_dir="$SRCDIR/${!dir_var}"
    if [[ -d "$config_dir" ]]; then
        for f in "$config_dir"/*; do
            [[ -f "$f" ]] && config_paths+=("$f")
        done
    fi
done

# Auto-discover patches from registered directories
# KERNEL_PATCHES is processed first, then KERNEL_PATCHES_* in alphabetical order
patch_paths=()
for dir_var in "${!KERNEL_PATCHES@}"; do
    patch_dir="$SRCDIR/${!dir_var}"
    for f in "$patch_dir"/*.patch; do
        [[ -f "$f" ]] && patch_paths+=("$f")
    done
done

KERNEL_FLAVOR=cloud
LOCALVERSION="-mkosi-${KERNEL_FLAVOR}"

echo "Building kernel ${KERNEL_VERSION} (Debian source)"
echo "LOCALVERSION: $LOCALVERSION"
echo "Config fragments (${#config_paths[@]}):"
for f in "${config_paths[@]}"; do echo "  $f"; done
echo "Patches (${#patch_paths[@]}):"
for f in "${patch_paths[@]}"; do echo "  $f"; done

# Cache key from version + localversion + config/patch contents
cache_hash=$(
    { echo "KERNEL_VERSION=${KERNEL_VERSION}"; \
      echo "LOCALVERSION=${LOCALVERSION}"; \
      echo "SNAPSHOT=${snapshot}"; \
      cat -- "${config_paths[@]}" "${patch_paths[@]}"; } \
    | sha256sum | cut -d' ' -f1 | cut -c1-12
)
cache_dir="$BUILDDIR/kernel-${KERNEL_VERSION}-${cache_hash}"
cached_deb="$cache_dir/kernel.deb"

# Use cached kernel .deb if available
if [[ -f "$cached_deb" ]] && [[ -s "$cached_deb" ]]; then
    echo "Using cached kernel .deb: $cached_deb"
else
    echo "Building kernel from source..."

    # Build directory layout (chroot-relative paths, then host paths derived from BUILDROOT)
    chroot_kernel_build_dir="/build/kernel-build"
    chroot_kernel_src_dir="${chroot_kernel_build_dir}/linux-source-${KERNEL_VERSION}"
    chroot_kconfig_dir="${chroot_kernel_build_dir}/kconfig"
    kernel_build_dir="${BUILDROOT}${chroot_kernel_build_dir}"
    kernel_src_dir="${BUILDROOT}${chroot_kernel_src_dir}"
    kconfig_dir="${BUILDROOT}${chroot_kconfig_dir}"

    apt-get -y install "linux-source-${KERNEL_VERSION}/${release}-backports" --install-recommends

    source_tarball="${BUILDROOT}/usr/src/linux-source-${KERNEL_VERSION}.tar.xz"
    if [[ ! -f "${source_tarball}" ]]; then
        echo "ERROR: Source tarball not found: ${source_tarball}" >&2
        exit 1
    fi
    mkdir -p "${kernel_build_dir}"
    tar xaf "${source_tarball}" -C "${kernel_build_dir}/"

    if [[ ! -f "${kernel_src_dir}/scripts/kconfig/merge_config.sh" ]]; then
        echo "ERROR: merge_config.sh not found in kernel source" >&2
        exit 1
    fi
    cloud_config_xz="${BUILDROOT}/usr/src/linux-config-${KERNEL_VERSION}/config.amd64_none_${KERNEL_FLAVOR}-amd64.xz"
    if [[ ! -f "${cloud_config_xz}" ]]; then
        echo "ERROR: Debian ${KERNEL_FLAVOR} config not found: ${cloud_config_xz}" >&2
        exit 1
    fi

    echo "Kernel source: ${kernel_src_dir}"
    echo "Cloud config: ${cloud_config_xz}"

    # Apply patches
    for patch_file in "${patch_paths[@]}"; do
        echo "  Applying: ${patch_file}"
        patch -d "${kernel_src_dir}" -p1 < "${patch_file}"
    done

    mkdir -p "${kconfig_dir}/fragments"
    rm -f "${kconfig_dir}/fragments/"*

    xz -dc "${cloud_config_xz}" > "${kconfig_dir}/base.config"

    for f in "${config_paths[@]}"; do
        if [[ -e "${kconfig_dir}/fragments/$(basename "$f")" ]]; then
            echo "ERROR: duplicate kernel config fragment '$(basename "$f")' from $f" >&2
            exit 1
        fi
        cp "$f" "${kconfig_dir}/fragments/$(basename "$f")"
    done

    merge_args=("${chroot_kconfig_dir}/base.config")
    for f in "${kconfig_dir}/fragments/"*; do
        [[ -f "$f" ]] && merge_args+=("${chroot_kconfig_dir}/fragments/$(basename "$f")")
    done

    echo "Config merge order:"
    for a in "${merge_args[@]}"; do echo "  $a"; done

    mkosi-chroot --chdir "${chroot_kernel_src_dir}" \
        ./scripts/kconfig/merge_config.sh "${merge_args[@]}"

    # Build kernel .deb package
    export KBUILD_BUILD_TIMESTAMP="$(date -u -d @0)"
    export KBUILD_BUILD_USER="mkosi"
    export KBUILD_BUILD_HOST="mkosi-builder"
    export LOCALVERSION  # suffix appended to kernel version, e.g. -mkosi-cloud
    export DEB_BUILD_PROFILES='pkg.linux-upstream.nokernelheaders pkg.linux-upstream.nokerneldbg'
    rm -f "${kernel_src_dir}/.version"

    mkosi-chroot --chdir "${chroot_kernel_src_dir}" make olddefconfig
    mkosi-chroot --chdir "${chroot_kernel_src_dir}" make -j "$(nproc 2>/dev/null || echo 2)" bindeb-pkg

    built_deb=$(find "${kernel_build_dir}" -maxdepth 1 -name "linux-image-*${LOCALVERSION}_*.deb" -type f | head -1)
    if [[ -z "${built_deb}" ]]; then
        echo "ERROR: linux-image .deb not found after build" >&2
        exit 1
    fi

    kernel_version_string=$(cat "${kernel_src_dir}/include/config/kernel.release")
    echo "Kernel version: ${kernel_version_string}"
    echo "Built .deb: $(basename "${built_deb}")"

    # Cache the .deb
    mkdir -p "${cache_dir}"
    cp "${built_deb}" "${cached_deb}"
    cp "${kernel_src_dir}/.config" "${cache_dir}/config"
    echo "${kernel_version_string}" > "${cache_dir}/kernel.release"
    echo "Cached kernel to: ${cache_dir}"

    rm -rf "${kernel_build_dir}"
fi

# Copy to PACKAGEDIR for mkosi VolatilePackages installation
cp "${cached_deb}" "${PACKAGEDIR}/"
echo "Kernel .deb copied to PACKAGEDIR"

#!/usr/bin/env bash
set -euxo pipefail
shopt -s inherit_errexit  # propagate errexit to $() subshells
shopt -s nullglob         # non-matching globs expand to nothing

KERNEL_REPO="${KERNEL_REPO:-https://github.com/gregkh/linux}"

if [[ -z "${KERNEL_GIT_SHA:-}" ]]; then
    echo "ERROR: KERNEL_GIT_SHA is not set. Set it to a full 40-character commit hash in mkosi.conf via Environment=" >&2
    exit 1
fi

# Must match a linux-config package available in the pinned snapshot mirror.
if [[ -z "${KERNEL_CONFIG_VERSION:-}" ]]; then
    echo "ERROR: KERNEL_CONFIG_VERSION is not set. Set it in mkosi.conf via Environment=" >&2
    exit 1
fi

# Read distribution info from mkosi config JSON
snapshot=$(jq -r '.Snapshot' "$MKOSI_CONFIG")
echo "Snapshot: $snapshot"

# Auto-discover config fragments from registered directories
# KERNEL_CONFIG_SNIPPETS is processed first, then KERNEL_CONFIG_SNIPPETS_* in alphabetical order
config_paths=()
for dir_var in "${!KERNEL_CONFIG_SNIPPETS@}"; do
    config_paths+=("$SRCDIR/${!dir_var}"/*)
done

# If KERNEL_MODULES is set, include the config fragments for enabling module support
if [[ -n "${KERNEL_MODULES:-}" ]]; then
    config_paths+=("$SRCDIR/shared/kernel/modules.config")
fi

# Auto-discover patches from registered directories
# KERNEL_PATCHES is processed first, then KERNEL_PATCHES_* in alphabetical order
patch_paths=()
for dir_var in "${!KERNEL_PATCHES@}"; do
    patch_paths+=("$SRCDIR/${!dir_var}"/*.patch)
done

KERNEL_FLAVOR=cloud
LOCALVERSION="-mkosi-${KERNEL_FLAVOR}"

echo "Building kernel ${KERNEL_GIT_SHA}"
echo "Base Debian config: linux-config-${KERNEL_CONFIG_VERSION}"
echo "LOCALVERSION: $LOCALVERSION"
echo "Config fragments (${#config_paths[@]}):"
for f in "${config_paths[@]}"; do echo "  $f"; done
echo "Patches (${#patch_paths[@]}):"
for f in "${patch_paths[@]}"; do echo "  $f"; done

# Cache key from commit + config version + localversion + config/patch contents
cache_hash=$(
    { echo "KERNEL_GIT_SHA=${KERNEL_GIT_SHA}"; \
      echo "KERNEL_CONFIG_VERSION=${KERNEL_CONFIG_VERSION}"; \
      echo "LOCALVERSION=${LOCALVERSION}"; \
      echo "SNAPSHOT=${snapshot}"; \
      cat -- "${config_paths[@]}" "${patch_paths[@]}"; } \
    | sha256sum | cut -d' ' -f1 | cut -c1-12
)
cache_dir="$BUILDDIR/kernel-${KERNEL_GIT_SHA:0:12}-${cache_hash}"
cached_deb="$cache_dir/kernel.deb"
cached_headers_deb="$cache_dir/headers.deb"

cat <<EOF > "$BUILDDIR/manifest.md"
| component  | version  | built / cached  | size  | duration  |
| ---------- | -------- | --------------- | ----- | --------- |
EOF

# Use cached kernel .deb if available
if [[ -f "$cached_deb" ]] && [[ -s "$cached_deb" ]]; then
    echo "Using cached kernel .deb: $cached_deb"
    echo "| \`kernel\`  | \`${KERNEL_GIT_SHA:0:12}\` (config hash \`${cache_hash}\`)  | reused from cache  | \`$( du -sh "$cached_deb" | cut -f1 )\`  |   |" >> "$BUILDDIR/manifest.md"
else
    ts=$( date +%s )

    echo "Building kernel from source..."

    # Build directory layout (chroot-relative paths, then host paths derived from BUILDROOT)
    chroot_kernel_build_dir="/build/kernel-build"
    chroot_kernel_src_dir="${chroot_kernel_build_dir}/linux"
    chroot_kconfig_dir="${chroot_kernel_build_dir}/kconfig"
    kernel_build_dir="${BUILDROOT}${chroot_kernel_build_dir}"
    kernel_src_dir="${BUILDROOT}${chroot_kernel_src_dir}"
    kconfig_dir="${BUILDROOT}${chroot_kconfig_dir}"

    # Speed up clone by only fetching the necessary commit
    mkdir -p "${kernel_src_dir}"
    git init -q "${kernel_src_dir}"
    git -C "${kernel_src_dir}" remote add origin "${KERNEL_REPO}"
    git -C "${kernel_src_dir}" fetch --depth 1 origin "${KERNEL_GIT_SHA}"
    git -C "${kernel_src_dir}" checkout -q FETCH_HEAD
    # Verify that the fetched commit matches the expected hash
    fetched_sha=$(git -C "${kernel_src_dir}" rev-parse HEAD)
    if [[ "${fetched_sha}" != "${KERNEL_GIT_SHA}" ]]; then
        echo "ERROR: fetched ${fetched_sha}, expected ${KERNEL_GIT_SHA}" >&2
        exit 1
    fi
    rm -rf "${kernel_src_dir}/.git"

    if [[ ! -f "${kernel_src_dir}/scripts/kconfig/merge_config.sh" ]]; then
        echo "ERROR: merge_config.sh not found in kernel source" >&2
        exit 1
    fi
    cloud_config_xz="${BUILDROOT}/usr/src/linux-config-${KERNEL_CONFIG_VERSION}/config.amd64_none_${KERNEL_FLAVOR}-amd64.xz"
    if [[ ! -f "${cloud_config_xz}" ]]; then
        echo "ERROR: Debian ${KERNEL_FLAVOR} config not found: ${cloud_config_xz}" >&2
        echo "       Make sure BuildPackages= lists linux-config-${KERNEL_CONFIG_VERSION}" >&2
        exit 1
    fi

    echo "Kernel source: ${kernel_src_dir}"
    echo "Cloud config: ${cloud_config_xz}"

    # Apply patches
    for patch_file in "${patch_paths[@]}"; do
        echo "  Applying: ${patch_file}"
        patch -d "${kernel_src_dir}" -p1 < "${patch_file}"
    done

    rm -rf "${kconfig_dir}/fragments"
    mkdir -p "${kconfig_dir}/fragments"

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
        merge_args+=("${chroot_kconfig_dir}/fragments/$(basename "$f")")
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
    
    if [[ -z "${KERNEL_MODULES:-}" ]]; then
        export DEB_BUILD_PROFILES='pkg.linux-upstream.nokerneldbg pkg.linux-upstream.nokernelheaders'
    else
        export DEB_BUILD_PROFILES='pkg.linux-upstream.nokerneldbg'
    fi

    rm -f "${kernel_src_dir}/.version"

    mkosi-chroot --chdir "${chroot_kernel_src_dir}" make olddefconfig
    if [[ -n "${KERNEL_MODULES:-}" ]]; then
        mkosi-chroot --chdir "${chroot_kernel_src_dir}" make mod2yesconfig
    fi
    mkosi-chroot --chdir "${chroot_kernel_src_dir}" make -j "$(nproc 2>/dev/null || echo 2)" bindeb-pkg

    built_deb=$(find "${kernel_build_dir}" -maxdepth 1 -name "linux-image-*${LOCALVERSION}_*.deb" -type f | head -1)
    if [[ -z "${built_deb}" ]]; then
        echo "ERROR: linux-image .deb not found after build" >&2
        exit 1
    fi

    kernel_version_string=$(cat "${kernel_src_dir}/include/config/kernel.release")
    echo "Kernel version: ${kernel_version_string}"
    echo "Built .deb: $(basename "${built_deb}")"

    seconds=$(( $( date +%s ) - ts ))
    duration=$( printf "%dm%ds" $(( seconds / 60 )) $(( seconds % 60 )) )

    # Cache .deb files
    mkdir -p "${cache_dir}"
    cp "${built_deb}" "${cached_deb}"
    if [[ -n "${KERNEL_MODULES:-}" ]]; then
        built_headers_deb=$(find "${kernel_build_dir}" -maxdepth 1 -name "linux-headers-*${LOCALVERSION}_*.deb" -type f | head -1)
        cp "${built_headers_deb}" "${cached_headers_deb}"
    fi
    cp "${kernel_src_dir}/.config" "${cache_dir}/config"
    echo "${kernel_version_string}" > "${cache_dir}/kernel.release"
    echo "Cached kernel to: ${cache_dir}"

    rm -rf "${kernel_build_dir}"

    echo "| \`kernel\`  | \`${KERNEL_GIT_SHA:0:12}\` (config hash \`${cache_hash}\`)  | built  | \`$( du -sh "$cached_deb" | cut -f1 )\`  | \`$duration\`  |" >> "$BUILDDIR/manifest.md"
fi

if [[ -n "${KERNEL_MODULES:-}" ]]; then
    mkosi-chroot dpkg -i "${CHROOT_BUILDDIR}/$(basename "${cache_dir}")/headers.deb"
    echo "Kernel headers installed into the build environment"
fi

# Copy to PACKAGEDIR for mkosi VolatilePackages installation
cp "${cached_deb}" "${PACKAGEDIR}/"
echo "Kernel .deb copied to PACKAGEDIR"

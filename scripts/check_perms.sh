#!/usr/bin/env bash

check_perms() {
    local path="$1"
    local expected_perms="$2"

    if [ ! -e "$path" ]; then
        echo "Error: $path not found"
        return 1
    fi

    # Cross-platform way to get octal permissions
    perms=$(stat -c "%a" "$path" 2>/dev/null || stat -f "%OLp" "$path" 2>/dev/null)

    if [ "$perms" = "$expected_perms" ]; then
        return 0
    else
        echo "$path has incorrect permissions ($perms), expected $expected_perms"
        return 1
    fi
}

err=0

check_perms "base/mkosi.skeleton/init" "755" || err=1
check_perms "base/mkosi.skeleton/etc" "755" || err=1
check_perms "base/mkosi.skeleton/etc/resolv.conf" "644" || err=1

if [ $err -eq 1 ]; then
    echo "Permission check failed!"
    echo "Please run umask 0022 and re-clone the repository."
    exit 1
fi

#!/usr/bin/env bash

is_elf() {
    [[ -f "$1" && $(head -c4 "$1") == $'\x7fELF' ]]
}

# Embed source repo and commit into an ELF binary as a systemd-style .note.package
# (https://systemd.io/ELF_PACKAGE_METADATA/); syft reads sourceRepo/commit from it.
add_package_note() {
    local file="$1"
    local package="$2"
    local version="$3"
    local source_url="$4"
    local commit="$5"

    local repository=${source_url#*://*/}
    local owner=${repository%/*}
    local note=$( mktemp )
    jq -cn --arg name "$package" --arg version "$version" --arg system "$owner" \
        --arg repo "$source_url" --arg commit "$commit" \
        '{name: $name, version: $version, system: $system, sourceRepo: $repo, commit: $commit}' > "$note"
    objcopy --remove-section .note.package \
        --add-section .note.package="$note" \
        --set-section-flags .note.package=noload,readonly "$file"
    rm "$note"
}

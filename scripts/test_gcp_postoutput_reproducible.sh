#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

export IMAGE_ID=test-image
export IMAGE_VERSION=test

# shellcheck source=../mkosi.profiles/gcp/mkosi.postoutput
source "$repo_root/mkosi.profiles/gcp/mkosi.postoutput"

for run in first second; do
    export OUTPUTDIR="$test_root/$run"
    mkdir -p "$OUTPUTDIR"
    printf 'deterministic raw disk fixture\n' > "$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}.raw"

    if [[ "$run" == first ]]; then
        touch -d '@1' "$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}.raw"
    else
        touch -d '@2' "$OUTPUTDIR/${IMAGE_ID}_${IMAGE_VERSION}.raw"
    fi

    package_raw_as_tar
done

first_archive="$test_root/first/${IMAGE_ID}_${IMAGE_VERSION}.tar.gz"
second_archive="$test_root/second/${IMAGE_ID}_${IMAGE_VERSION}.tar.gz"
cmp "$first_archive" "$second_archive"

member="$(tar -tzf "$first_archive")"
[[ "$member" == disk.raw ]] || {
    echo "unexpected GCP archive member: $member" >&2
    exit 1
}

owner_group="$(tar --numeric-owner -tvzf "$first_archive" | awk '{print $2}')"
[[ "$owner_group" == 0/0 ]] || {
    echo "GCP archive member has non-normalized ownership: $owner_group" >&2
    exit 1
}

read -r gzip_id1 gzip_id2 gzip_method gzip_flags gzip_mtime1 gzip_mtime2 gzip_mtime3 gzip_mtime4 _ \
    < <(od -An -tu1 -N10 "$first_archive")
[[ "$gzip_id1" == 31 && "$gzip_id2" == 139 && "$gzip_method" == 8 ]] || {
    echo 'GCP archive does not have the expected gzip header' >&2
    exit 1
}
[[ "$gzip_flags" == 0 ]] || {
    echo 'GCP archive gzip header includes optional filename or metadata fields' >&2
    exit 1
}
[[ "$gzip_mtime1" == 0 && "$gzip_mtime2" == 0 && "$gzip_mtime3" == 0 && "$gzip_mtime4" == 0 ]] || {
    echo 'GCP archive gzip header has a non-zero timestamp' >&2
    exit 1
}

extracted="$test_root/extracted.raw"
tar -xOzf "$first_archive" disk.raw > "$extracted"
cmp "$test_root/first/${IMAGE_ID}_${IMAGE_VERSION}.raw" "$extracted"

digest="$(sha256sum "$first_archive" | cut -d' ' -f1)"
echo "GCP post-output archive is reproducible: sha256:$digest"

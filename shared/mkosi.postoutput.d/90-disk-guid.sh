#!/usr/bin/env bash

#
# give the disk image the fixed GPT disk GUID that the cloud images use
#
# - this has to run before 95-gen-sbom.sh hashes the image.  mkosi runs the
#   profiles' post-output scripts (mkosi.profiles/*/mkosi.postoutput) after all
#   of the scripts here, so the SBOM would not have a change that they make
#
set -euo pipefail

raw="${OUTPUTDIR:?}/${IMAGE_ID}_${IMAGE_VERSION}.raw"
[[ -f "$raw" ]] || exit 0 # not a disk image (Format=uki)

sgdisk --disk-guid 12345678-1234-5678-1234-567812345678 "$raw"

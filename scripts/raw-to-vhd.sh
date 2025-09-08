#!/bin/bash

# Convert raw disk image to Azure-compatible VHD format
# Adapted from https://learn.microsoft.com/en-us/azure/virtual-machines/linux/create-upload-generic#general-linux-installation-notes
# Usage: ./raw-to-vhd.sh <input.raw> <output.vhd>

set -euo pipefail

# Function to display usage
usage() {
    echo "Usage: $0 <input.raw> <output.vhd>"
    echo "Convert raw disk image to Azure-compatible VHD format"
    exit 1
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is not installed or not in PATH"
        echo "Please install $1 and try again"
        exit 1
    fi
}

# Check dependencies
echo "Checking dependencies..."
check_command "qemu-img"
check_command "jq"

# Check arguments
if [ $# -ne 2 ]; then
    echo "Error: Incorrect number of arguments"
    usage
fi

rawdisk="$1"
vhddisk="$2"

# Check if input file exists
if [ ! -f "$rawdisk" ]; then
    echo "Error: Input file '$rawdisk' does not exist"
    exit 1
fi

# Check if output directory exists
output_dir=$(dirname "$vhddisk")
if [ ! -d "$output_dir" ]; then
    echo "Error: Output directory '$output_dir' does not exist"
    exit 1
fi

echo "Converting $rawdisk to $vhddisk..."

# Convert raw to VHD
MB=$((1024*1024))
size=$(qemu-img info -f raw --output json "$rawdisk" | jq -r '."virtual-size"')
rounded_size=$(((($size+$MB-1)/$MB)*$MB))

echo "Original size: $size bytes"
echo "Rounded size: $rounded_size bytes"

# Resize the raw image to MB boundary
qemu-img resize -f raw "$rawdisk" "$rounded_size"

# Convert to VHD format
qemu-img convert -f raw -o subformat=fixed,force_size -O vpc "$rawdisk" "$vhddisk"

echo "Conversion completed successfully!"
echo "Output file: $vhddisk"

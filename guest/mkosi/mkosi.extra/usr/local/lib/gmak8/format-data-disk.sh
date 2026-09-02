#!/bin/sh
set -eu
# Whole-disk ext4 on nvme1n1. DISK= override is for host-side idempotency tests.
DISK=${DISK:-/dev/nvme1n1}
if ! blkid -o value -s LABEL "$DISK" 2>/dev/null | grep -qx GMAK8_DATA; then
  mkfs.ext4 -F -L GMAK8_DATA "$DISK"
fi
# Host-side tests use a regular file; udev only applies to a real block device.
if [ -b "$DISK" ] && command -v udevadm >/dev/null 2>&1; then
  udevadm trigger --action=change -- "$DISK"
  udevadm settle --timeout=30 --exit-if-exists=/dev/disk/by-label/GMAK8_DATA
fi
echo "gmak8-data-format: labeled GMAK8_DATA"

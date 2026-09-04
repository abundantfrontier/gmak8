#!/bin/sh
# Whole-disk ext4 labeled GMAK8_DATA. DISK= override is for host-side tests.
# Virtualization.framework does not guarantee nvme0=OS / nvme1=data; pick the
# unpartitioned NVMe that is not the root device.
set -eu

find_data_disk() {
  if [ -e /dev/disk/by-label/GMAK8_DATA ]; then
    readlink -f /dev/disk/by-label/GMAK8_DATA
    return 0
  fi
  root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
  root_pk=""
  if [ -n "$root_src" ]; then
    root_pk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n 1 || true)
    if [ -z "$root_pk" ]; then
      root_pk=$(lsblk -no NAME "$root_src" 2>/dev/null | head -n 1 || true)
    fi
  fi
  for d in /dev/nvme*n1; do
    [ -b "$d" ] || continue
    base=$(basename "$d")
    if [ -n "$root_pk" ] && [ "$base" = "$root_pk" ]; then
      continue
    fi
    if [ -b "${d}p1" ]; then
      continue
    fi
    printf '%s\n' "$d"
    return 0
  done
  echo "gmak8-data-format: no data NVMe (need an unpartitioned disk that is not the root device)" >&2
  return 1
}

DISK=${DISK:-}
if [ -z "$DISK" ]; then
  i=0
  while [ "$i" -lt 30 ]; do
    if DISK=$(find_data_disk); then
      break
    fi
    i=$((i + 1))
    sleep 1
  done
fi
if [ -z "${DISK:-}" ]; then
  echo "gmak8-data-format: no data NVMe" >&2
  exit 1
fi

if ! blkid -o value -s LABEL "$DISK" 2>/dev/null | grep -qx GMAK8_DATA; then
  mkfs.ext4 -F -L GMAK8_DATA "$DISK"
fi
# Host-side tests use a regular file; udev only applies to a real block device.
if [ -b "$DISK" ] && command -v udevadm >/dev/null 2>&1; then
  udevadm trigger --action=change -- "$DISK"
  udevadm settle --timeout=30 --exit-if-exists=/dev/disk/by-label/GMAK8_DATA
fi
echo "gmak8-data-format: labeled GMAK8_DATA"

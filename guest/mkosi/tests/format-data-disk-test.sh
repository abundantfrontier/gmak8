#!/usr/bin/env bash
# Idempotency test for format-data-disk.sh against fake blkid/mkfs (no real disk).
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
script="$root/guest/mkosi/mkosi.extra/usr/local/lib/gmak8/format-data-disk.sh"
test -x "$script"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin="$work/bin"
mkdir -p "$bin"

cat >"$bin/blkid" <<'EOF'
#!/bin/sh
device=""
while [ $# -gt 0 ]; do
  device=$1
  shift
done
if [ -f "${device}.label" ]; then
  cat "${device}.label"
  exit 0
fi
exit 2
EOF

cat >"$bin/mkfs.ext4" <<'EOF'
#!/bin/sh
label=""
disk=""
while [ $# -gt 0 ]; do
  case $1 in
    -L)
      label=$2
      shift 2
      ;;
    -F)
      shift
      ;;
    *)
      disk=$1
      shift
      ;;
  esac
done
printf '%s\n' "$label" >"${disk}.label"
echo "mkfs $disk $label" >>"${disk}.mkfs-log"
EOF

chmod +x "$bin/blkid" "$bin/mkfs.ext4"

export PATH="$bin:$PATH"
export DISK="$work/nvme1n1"
: >"$DISK"

out1=$("$script")
test -f "$DISK.mkfs-log" || {
  echo "expected mkfs on unlabeled disk" >&2
  exit 1
}
test "$(cat "$DISK.label")" = GMAK8_DATA
printf '%s\n' "$out1" | grep -qx 'gmak8-data-format: labeled GMAK8_DATA'

"$script" >/dev/null
count=$(wc -l <"$DISK.mkfs-log")
if [ "$count" -ne 1 ]; then
  echo "expected idempotent skip, mkfs ran $count times" >&2
  exit 1
fi

echo OTHER >"$DISK.label"
"$script" >/dev/null
count=$(wc -l <"$DISK.mkfs-log")
if [ "$count" -ne 2 ]; then
  echo "expected re-format when label is not GMAK8_DATA" >&2
  exit 1
fi
test "$(cat "$DISK.label")" = GMAK8_DATA

echo "format-data-disk-test: ok"

#!/usr/bin/env bash
# Grep /boot/config-* for CONFIG_KVM=y or =m and assert kvm.ko exists.
set -euo pipefail

root=${1:?usage: assert-kvm.sh ROOTFS}

if [ ! -d "$root" ]; then
  echo "assert-kvm: not a directory: $root" >&2
  exit 1
fi

configs=$(find "$root" \( -path '*/boot/config-*' -o -path '*/usr/src/*/config-*' \) -type f 2>/dev/null || true)
if [ -z "$configs" ]; then
  echo "assert-kvm: no /boot/config-* under $root" >&2
  exit 1
fi

kvm_cfg=""
while IFS= read -r cfg; do
  [ -n "$cfg" ] || continue
  line=$(grep -E '^CONFIG_KVM=[ym]$' "$cfg" || true)
  if [ -n "$line" ]; then
    kvm_cfg=$line
    echo "assert-kvm: $cfg: $line"
  fi
done <<EOF
$configs
EOF

if [ -z "$kvm_cfg" ]; then
  echo "assert-kvm: CONFIG_KVM=y or CONFIG_KVM=m not found" >&2
  exit 1
fi

ko=""
while IFS= read -r path; do
  ko=$path
  break
done < <(find "$root" \( \
  -name kvm.ko -o -name kvm.ko.xz -o -name kvm.ko.zst -o -name kvm.ko.gz \
  \) -type f 2>/dev/null)
if [ -z "$ko" ]; then
  echo "assert-kvm: kvm.ko not found under $root" >&2
  exit 1
fi
echo "assert-kvm: $ko"

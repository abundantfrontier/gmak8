#!/usr/bin/env bash
# Grep /boot/config-* for CONFIG_KVM=y or =m.
# =y is built-in (no kvm.ko file). =m requires kvm.ko*.
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

find_kvm_ko() {
  while IFS= read -r path; do
    echo "$path"
    return 0
  done < <(find "$root" \( \
    -name kvm.ko -o -name kvm.ko.xz -o -name kvm.ko.zst -o -name kvm.ko.gz \
    \) -type f 2>/dev/null)
  return 1
}

if [ "$kvm_cfg" = "CONFIG_KVM=y" ]; then
  builtin=""
  while IFS= read -r path; do
    if grep -E -q '(^|/)kvm\.ko$' "$path"; then
      builtin=$path
      break
    fi
  done < <(find "$root" -name modules.builtin -type f 2>/dev/null)
  if [ -n "$builtin" ]; then
    echo "assert-kvm: built-in ($builtin)"
  else
    echo "assert-kvm: CONFIG_KVM=y (built-in; no kvm.ko module file)"
  fi
  exit 0
fi

ko=""
if ko=$(find_kvm_ko); then
  echo "assert-kvm: $ko"
  exit 0
fi
echo "assert-kvm: CONFIG_KVM=m but kvm.ko not found under $root" >&2
exit 1

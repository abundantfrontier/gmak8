#!/usr/bin/env bash
# CONFIG_KVM=y is built-in (no kvm.ko file). CONFIG_KVM=m requires kvm.ko*.
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
assert="$root/guest/mkosi/scripts/assert-kvm.sh"
test -x "$assert"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/y/boot" "$work/y/lib/modules/1.0"
echo 'CONFIG_KVM=y' >"$work/y/boot/config-1.0"
echo 'kernel/arch/arm64/kvm/kvm.ko' >"$work/y/lib/modules/1.0/modules.builtin"
bash "$assert" "$work/y" >/dev/null

mkdir -p "$work/y2/boot"
echo 'CONFIG_KVM=y' >"$work/y2/boot/config-1.0"
bash "$assert" "$work/y2" >/dev/null

mkdir -p "$work/m/boot" "$work/m/lib/modules/1.0/kernel/arch/arm64/kvm"
echo 'CONFIG_KVM=m' >"$work/m/boot/config-1.0"
: >"$work/m/lib/modules/1.0/kernel/arch/arm64/kvm/kvm.ko.xz"
bash "$assert" "$work/m" >/dev/null

mkdir -p "$work/mbad/boot"
echo 'CONFIG_KVM=m' >"$work/mbad/boot/config-1.0"
if bash "$assert" "$work/mbad" >/dev/null 2>&1; then
  echo "assert-kvm-test: expected fail for CONFIG_KVM=m without kvm.ko" >&2
  exit 1
fi

mkdir -p "$work/none/boot"
echo 'CONFIG_KVM=n' >"$work/none/boot/config-1.0"
if bash "$assert" "$work/none" >/dev/null 2>&1; then
  echo "assert-kvm-test: expected fail when CONFIG_KVM is not y or m" >&2
  exit 1
fi

echo "assert-kvm-test: ok"

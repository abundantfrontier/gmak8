#!/bin/sh
set -eu
# CONFIG_KVM=y: modprobe kvm is a no-op via modules.builtin.
# kvm-arm is folded into kvm on many arm64 configs; load it only if present.
modprobe kvm
if modprobe -n kvm-arm >/dev/null 2>&1; then
  modprobe kvm-arm
fi

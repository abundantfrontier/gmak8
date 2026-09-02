#!/bin/sh
set -eu
# kvm-arm is folded into kvm.ko on many arm64 configs; load it only if present.
modprobe kvm
if modprobe -n kvm-arm >/dev/null 2>&1; then
  modprobe kvm-arm
fi

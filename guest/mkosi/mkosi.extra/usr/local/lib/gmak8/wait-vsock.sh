#!/bin/sh
# virtio-vsock must exist before gmak8-agent binds port 1024.
set -eu
exec >/dev/console 2>&1
modprobe vsock 2>/dev/null || true
modprobe virtio_vsock 2>/dev/null || true
i=0
while [ "$i" -lt 50 ]; do
  if [ -e /dev/vsock ]; then
    echo "gmak8-agent: /dev/vsock ready"
    exit 0
  fi
  i=$((i + 1))
  sleep 0.1
done
echo "gmak8-agent: /dev/vsock missing after wait"
lsmod 2>/dev/null | grep vsock || true
ls -l /dev/vsock /sys/bus/virtio/devices 2>/dev/null || true
exit 1

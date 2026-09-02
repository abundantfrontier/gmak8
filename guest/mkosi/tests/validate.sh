#!/usr/bin/env bash
# Contract checks for the Debian appliance units (no mkosi, no VZ).
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
extra="$root/guest/mkosi/mkosi.extra"
fmt="$extra/usr/local/lib/gmak8/format-data-disk.sh"
format_unit="$extra/etc/systemd/system/gmak8-data-format.service"
mount_unit="$extra/etc/systemd/system/mnt-data.mount"
prep_unit="$extra/etc/systemd/system/mnt-data-prep.service"
kvm_unit="$extra/etc/systemd/system/gmak8-kvm.service"
k3s_cfg="$root/guest/k3s/config.yaml"
readme="$root/guest/README.md"
mkosi_conf="$root/guest/mkosi/mkosi.conf"

fail() {
  echo "validate: $*" >&2
  exit 1
}

test -f "$fmt" || fail "missing format-data-disk.sh"
test -x "$fmt" || fail "format-data-disk.sh must be executable"
test -x "$extra/usr/local/lib/gmak8/modprobe-kvm.sh" || fail "modprobe-kvm.sh must be executable"

grep -q 'DISK=${DISK:-/dev/nvme1n1}' "$fmt" || fail "format script must default DISK to /dev/nvme1n1"
grep -q 'mkfs.ext4 -F -L GMAK8_DATA' "$fmt" || fail "format script must mkfs.ext4 -F -L GMAK8_DATA"
grep -q 'gmak8-data-format: labeled GMAK8_DATA' "$fmt" || fail "format script must log the serial contract line"

grep -q 'Before=mnt-data.mount' "$format_unit" || fail "format unit must be Before=mnt-data.mount"
grep -q 'ConditionPathExists=/dev/nvme1n1' "$format_unit" || fail "format unit must ConditionPathExists=/dev/nvme1n1"
grep -q 'ExecStart=/usr/local/lib/gmak8/format-data-disk.sh' "$format_unit" || fail "format unit ExecStart"

grep -q 'Requires=gmak8-data-format.service' "$mount_unit" || fail "mount must Require format unit"
grep -q 'After=gmak8-data-format.service' "$mount_unit" || fail "mount must After format unit"
grep -q 'Before=local-fs.target gmak8-agent.service k3s.service' "$mount_unit" || fail "mount Before= local-fs/agent/k3s"
grep -q 'What=/dev/disk/by-label/GMAK8_DATA' "$mount_unit" || fail "mount What= GMAK8_DATA"
grep -q 'Where=/mnt/data' "$mount_unit" || fail "mount Where=/mnt/data"
grep -q 'Type=ext4' "$mount_unit" || fail "mount Type=ext4"

grep -q 'After=mnt-data.mount' "$prep_unit" || fail "prep After=mnt-data.mount"
grep -q 'Before=k3s.service' "$prep_unit" || fail "prep Before=k3s.service"
grep -q '/mnt/data/rancher' "$prep_unit" || fail "prep must mkdir rancher"
grep -q '/mnt/data/buildkit' "$prep_unit" || fail "prep must mkdir buildkit"
grep -q '/mnt/data/local-path' "$prep_unit" || fail "prep must mkdir local-path"

grep -q 'modprobe-kvm.sh' "$kvm_unit" || fail "kvm unit must call modprobe-kvm.sh"
grep -q '^kvm$' "$extra/etc/modules-load.d/gmak8-kvm.conf" || fail "modules-load.d must list kvm"

wants_mount="$extra/etc/systemd/system/local-fs.target.wants/mnt-data.mount"
test -L "$wants_mount" || fail "local-fs.target.wants/mnt-data.mount symlink missing"
test -L "$extra/etc/systemd/system/multi-user.target.wants/mnt-data-prep.service" || fail "multi-user.target.wants/mnt-data-prep.service symlink missing"
test -L "$extra/etc/systemd/system/multi-user.target.wants/gmak8-kvm.service" || fail "multi-user.target.wants/gmak8-kvm.service symlink missing"

grep -qx 'data-dir: /mnt/data/rancher' "$k3s_cfg" || fail "k3s config data-dir"
grep -qx 'default-local-storage-path: /mnt/data/local-path' "$k3s_cfg" || fail "k3s config default-local-storage-path"
if grep -E '^[[:space:]]*(disable-helm-controller|write-kubeconfig)[[:space:]]*:' "$k3s_cfg"; then
  fail "k3s template must not set disable-helm-controller or write-kubeconfig"
fi

grep -q 'linux-image-arm64' "$mkosi_conf" || fail "mkosi must install linux-image-arm64"
if grep -E '^[[:space:]]+linux-image-cloud-arm64([[:space:]]|$)' "$mkosi_conf"; then
  fail "mkosi must not install linux-image-cloud-arm64"
fi
grep -q 'openssh-server' "$mkosi_conf" || fail "mkosi must include openssh-server"
grep -q 'Ssh=never' "$mkosi_conf" || fail "mkosi must set Ssh=never (sshd disabled until PR 30)"
if grep -E '^[[:space:]]+(k3s|docker|docker-ce|containerd)([[:space:]]|$)' "$mkosi_conf"; then
  fail "this PR must not install k3s/docker/containerd in the image"
fi

image_k3s="$extra/etc/rancher/k3s/config.yaml"
test -f "$image_k3s" || fail "appliance must ship /etc/rancher/k3s/config.yaml"
cmp -s "$k3s_cfg" "$image_k3s" || fail "guest/k3s/config.yaml must match mkosi.extra copy"

grep -q 'efi-nvram.bin' "$readme" || fail "README must document efi-nvram.bin recreate"
grep -q 'data.img' "$readme" || fail "README must document keeping data.img"
grep -q 'GMAK8_DATA' "$readme" || fail "README must document GMAK8_DATA"

if grep -Eiq 'xcodebuild|VZVirtualMachine|com.apple.security.virtualization' "$root/.github/workflows/guest.yml"; then
  fail "guest.yml must not run Virtualization.framework"
fi

echo "validate: ok"

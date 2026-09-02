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
agent_unit="$extra/etc/systemd/system/gmak8-agent.service"
agent_src="$root/guest/agent"
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
grep -q 'Wants=dev-nvme1n1.device' "$format_unit" || fail "format unit must Wants=dev-nvme1n1.device"
grep -q 'Conflicts=umount.target' "$format_unit" || fail "format unit must Conflicts=umount.target"
grep -q 'ConditionPathExists=/dev/nvme1n1' "$format_unit" || fail "format unit must ConditionPathExists=/dev/nvme1n1"
grep -q 'ExecStart=/usr/local/lib/gmak8/format-data-disk.sh' "$format_unit" || fail "format unit ExecStart"
grep -q udevadm "$fmt" || fail "format script must udevadm settle after mkfs"

grep -q 'Requires=gmak8-data-format.service' "$mount_unit" || fail "mount must Require format unit"
grep -q 'dev-disk-by-label-GMAK8_DATA.device' "$mount_unit" || fail "mount must wait on by-label device"
grep -q 'After=gmak8-data-format.service' "$mount_unit" || fail "mount must After format unit"
grep -q 'Conflicts=umount.target' "$mount_unit" || fail "mount must Conflicts=umount.target"
grep -q 'Before=local-fs.target umount.target gmak8-agent.service k3s.service' "$mount_unit" || fail "mount Before= local-fs/umount/agent/k3s"
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

test -f "$agent_unit" || fail "missing gmak8-agent.service"
grep -q 'After=mnt-data.mount' "$agent_unit" || fail "agent After=mnt-data.mount"
grep -q 'ExecStart=/usr/local/bin/gmak8-agent' "$agent_unit" || fail "agent ExecStart"
grep -q 'vsock:1024' "$agent_unit" || fail "agent must listen on vsock:1024"
if grep -Eiq 'mkfs|format-data-disk' "$agent_unit"; then
  fail "agent unit must not format the data disk"
fi
if grep -E '^Requires=mnt-data.mount' "$agent_unit"; then
  fail "agent must not Requires=mnt-data.mount (format is a separate oneshot)"
fi
test -L "$extra/etc/systemd/system/multi-user.target.wants/gmak8-agent.service" || fail "multi-user.target.wants/gmak8-agent.service symlink missing"
grep -q 'enable gmak8-agent.service' "$extra/etc/systemd/system-preset/90-gmak8.preset" || fail "preset must enable gmak8-agent.service"
grep -q 'systemctl enable gmak8-agent.service' "$root/guest/mkosi/mkosi.postinst.chroot" || fail "postinst must enable gmak8-agent.service"
test -f "$agent_src/go.mod" || fail "missing guest/agent/go.mod"
test -f "$agent_src/Makefile" || fail "missing guest/agent/Makefile"
if grep -R -E --include='*.go' 'mkfs\.ext4|format-data-disk' "$agent_src"; then
  fail "agent source must not format the data disk"
fi
grep -q 'AgentVsockPort.*=.*1024' "$agent_src/ports.go" || fail "agent vsock port must be 1024"
grep -q 'BuildkitVsockPort.*=.*1025' "$agent_src/ports.go" || fail "buildkit vsock port must be reserved 1025"

wants_mount="$extra/etc/systemd/system/local-fs.target.wants/mnt-data.mount"
test -L "$wants_mount" || fail "local-fs.target.wants/mnt-data.mount symlink missing"
test -L "$extra/etc/systemd/system/multi-user.target.wants/mnt-data-prep.service" || fail "multi-user.target.wants/mnt-data-prep.service symlink missing"
test -L "$extra/etc/systemd/system/multi-user.target.wants/gmak8-kvm.service" || fail "multi-user.target.wants/gmak8-kvm.service symlink missing"
test -L "$extra/etc/systemd/system/multi-user.target.wants/gmak8-agent.service" || fail "multi-user.target.wants/gmak8-agent.service symlink missing"

grep -qx 'data-dir: /mnt/data/rancher' "$k3s_cfg" || fail "k3s config data-dir"
grep -qx 'default-local-storage-path: /mnt/data/local-path' "$k3s_cfg" || fail "k3s config default-local-storage-path"
grep -qx 'cluster-cidr: 10.42.0.0/16' "$k3s_cfg" || fail "k3s config cluster-cidr"
grep -qx 'service-cidr: 10.43.0.0/16' "$k3s_cfg" || fail "k3s config service-cidr"
grep -qx 'cluster-dns: 10.43.0.10' "$k3s_cfg" || fail "k3s config cluster-dns"
grep -qx 'node-name: gmak8' "$k3s_cfg" || fail "k3s config node-name"
grep -qx 'https-listen-port: 6443' "$k3s_cfg" || fail "k3s config https-listen-port"
grep -q '192.168.127.2' "$k3s_cfg" || fail "k3s config tls-san must include guest IP"
if grep -E '^[[:space:]]*(disable-helm-controller|write-kubeconfig)[[:space:]]*:' "$k3s_cfg"; then
  fail "k3s template must not set disable-helm-controller or write-kubeconfig"
fi
if grep -E '^[[:space:]]*disable[[:space:]]*:' "$k3s_cfg"; then
  fail "k3s template must not set a disable: list yet"
fi

k3s_unit="$extra/etc/systemd/system/k3s.service"
compat_unit="$extra/etc/systemd/system/gmak8-k3s-compat.service"
test -f "$k3s_unit" || fail "missing k3s.service"
test -f "$compat_unit" || fail "missing gmak8-k3s-compat.service"
grep -q 'Requires=mnt-data.mount' "$k3s_unit" || fail "k3s.service must Requires=mnt-data.mount"
grep -q 'gmak8-k3s-compat.service' "$k3s_unit" || fail "k3s.service must require data-dir compat oneshot"
grep -q 'After=.*mnt-data.mount' "$k3s_unit" || fail "k3s.service must After=mnt-data.mount"
grep -q 'ExecStart=/usr/local/bin/k3s server' "$k3s_unit" || fail "k3s.service ExecStart must be the pinned static binary"
grep -q 'Before=k3s.service' "$compat_unit" || fail "compat oneshot must be Before=k3s.service"
grep -q -- '-check-data-dir' "$compat_unit" || fail "compat oneshot must run gmak8-agent -check-data-dir"
grep -q 'check-data-dir' "$root/guest/agent/main.go" || fail "agent must support -check-data-dir"
if grep -Eiq 'disable-helm-controller' "$k3s_unit"; then
  fail "k3s.service must not disable helm-controller"
fi
if grep -Eiq 'write-kubeconfig' "$k3s_unit"; then
  fail "k3s.service must not set a custom write-kubeconfig path"
fi
if test -e "$extra/etc/systemd/system/multi-user.target.wants/k3s.service"; then
  fail "k3s.service must not be enabled at boot (host starts it after the probe)"
fi
grep -q 'disable k3s.service' "$extra/etc/systemd/system-preset/90-gmak8.preset" || fail "preset must disable k3s.service at boot"
if grep -q 'systemctl enable k3s.service' "$root/guest/mkosi/mkosi.postinst.chroot"; then
  fail "postinst must not enable k3s.service at boot"
fi
grep -q 'systemctl disable k3s.service' "$root/guest/mkosi/mkosi.postinst.chroot" || fail "postinst must disable k3s.service"
grep -q 'install-k3s.sh' "$root/guest/mkosi/mkosi.postinst.chroot" || fail "postinst must install pinned k3s"

k3s_pin="$root/guest/k3s/k3s.pin"
k3s_install="$root/guest/k3s/install.sh"
image_pin="$extra/usr/local/lib/gmak8/k3s.pin"
image_install="$extra/usr/local/lib/gmak8/install-k3s.sh"
test -f "$k3s_pin" || fail "missing guest/k3s/k3s.pin"
test -f "$k3s_install" || fail "missing guest/k3s/install.sh"
test -x "$k3s_install" || fail "guest/k3s/install.sh must be executable"
test -x "$image_install" || fail "install-k3s.sh must be executable"
cmp -s "$k3s_pin" "$image_pin" || fail "guest/k3s/k3s.pin must match mkosi.extra copy"
cmp -s "$k3s_install" "$image_install" || fail "guest/k3s/install.sh must match mkosi.extra copy"
grep -q 'v1.33.3+k3s1' "$k3s_pin" || fail "k3s pin must be v1.33.3+k3s1"
grep -q '%2B' "$k3s_pin" || fail "k3s pin URL must encode + as %2B"
grep -q '152c961aae4aa7553865481c21902a3cc8e02550df97587379a409494c3626c4' "$k3s_pin" || fail "k3s pin must include the official arm64 SHA256"
grep -q 'k3s-arm64' "$root/guest/k3s/k3s-arm64.sha256sum" || fail "missing guest/k3s/k3s-arm64.sha256sum"
test -f "$extra/etc/systemd/system/mnt-config.mount" || fail "missing mnt-config.mount"
grep -q 'What=gmak8-config' "$extra/etc/systemd/system/mnt-config.mount" || fail "mnt-config.mount must use virtiofs tag gmak8-config"
grep -q 'Type=virtiofs' "$extra/etc/systemd/system/mnt-config.mount" || fail "mnt-config.mount Type=virtiofs"
grep -q 'Where=/mnt/config' "$extra/etc/systemd/system/mnt-config.mount" || fail "mnt-config.mount Where=/mnt/config"
if grep -E '^Requires=mnt-config.mount' "$k3s_unit"; then
  fail "k3s must not Requires=mnt-config.mount (share is optional)"
fi

grep -q 'linux-image-arm64' "$mkosi_conf" || fail "mkosi must install linux-image-arm64"
if grep -E '^[[:space:]]+linux-image-cloud-arm64([[:space:]]|$)' "$mkosi_conf"; then
  fail "mkosi must not install linux-image-cloud-arm64"
fi
grep -q 'openssh-server' "$mkosi_conf" || fail "mkosi must include openssh-server"
grep -q 'Ssh=never' "$mkosi_conf" || fail "mkosi must set Ssh=never (sshd disabled until PR 30)"
grep -q 'systemd.ssh_auto=no' "$mkosi_conf" || fail "mkosi must set systemd.ssh_auto=no"
if grep -E '^[[:space:]]+(k3s|docker|docker-ce|docker.io|containerd)([[:space:]]|$)' "$mkosi_conf"; then
  fail "must not install k3s/docker/containerd as Debian packages"
fi
grep -q 'curl' "$mkosi_conf" || fail "mkosi must install curl to fetch k3s"

image_k3s="$extra/etc/rancher/k3s/config.yaml"
test -f "$image_k3s" || fail "appliance must ship /etc/rancher/k3s/config.yaml"
cmp -s "$k3s_cfg" "$image_k3s" || fail "guest/k3s/config.yaml must match mkosi.extra copy"

grep -q 'efi-nvram.bin' "$readme" || fail "README must document efi-nvram.bin recreate"
grep -q 'data.img' "$readme" || fail "README must document keeping data.img"
grep -q 'GMAK8_DATA' "$readme" || fail "README must document GMAK8_DATA"
grep -q 'whole-disk label is' "$readme" || fail "README must document non-GMAK8_DATA labels are reformatted"
grep -q 'vsock port 1024' "$readme" || fail "README must document vsock 1024 agent"
grep -q 'gmak8-agent.service' "$readme" || fail "README must document gmak8-agent.service"
grep -q 'v1.33.3+k3s1' "$readme" || fail "README must document pinned k3s version"
grep -q '/etc/rancher/k3s/k3s.yaml' "$readme" || fail "README must document admin kubeconfig path"
grep -q 'helm-controller' "$readme" || fail "README must document helm-controller left enabled"
grep -q '/kubeconfig' "$readme" || fail "README must document GET /kubeconfig"
grep -q '/k3s' "$readme" || fail "README must document GET /k3s"
grep -q '/k3s/start' "$readme" || fail "README must document POST /k3s/start"
grep -q '/node' "$readme" || fail "README must document GET /node"
grep -q 'check-data-dir' "$readme" || fail "README must document data-dir compat check"

if grep -Eiq 'xcodebuild|VZVirtualMachine|com.apple.security.virtualization' "$root/.github/workflows/guest.yml"; then
  fail "guest.yml must not run Virtualization.framework"
fi
if grep -E '^[[:space:]]+continue-on-error: true' "$root/.github/workflows/guest.yml"; then
  fail "guest.yml mkosi job must not continue-on-error"
fi

echo "validate: ok"

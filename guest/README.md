# gmak8 guest appliance

Debian 13 (trixie) arm64 image built with [mkosi](https://github.com/systemd/mkosi).
Virtualization.framework attaches two NVMe disks:

| Role | Guest device | Host file |
| --- | --- | --- |
| OS (replaceable) | `/dev/nvme0n1` | `~/Library/Application Support/dev.gmak8.app/vm/os.img` |
| Data (persistent) | `/dev/nvme1n1` | `~/Library/Application Support/dev.gmak8.app/vm/data.img` |

EFI NVRAM lives on the host as `vm/efi-nvram.bin` (`VZEFIVariableStore`).

Do not vendor the built disk image in git.

## Data disk contract

The data disk is **whole-disk ext4**, label **`GMAK8_DATA`**, no partition table.
It is findable after an OS replace without GPT UUIDs from the previous `os.img`.

**First-boot format is not the agent and not k3s.** On a blank `data.img` there
is no `/dev/disk/by-label/GMAK8_DATA`, so `mnt-data.mount` would fail and an
agent that `Requires=` that mount would never start — mkfs would deadlock.

Boot order:

1. `gmak8-data-format.service` (oneshot, `Before=mnt-data.mount`) runs
   `/usr/local/lib/gmak8/format-data-disk.sh` if the whole-disk label is
   not `GMAK8_DATA` (blank `data.img` **or** a stray filesystem). That
   path is `mkfs.ext4 -F` and wipes the device.
2. `mnt-data.mount` mounts `/dev/disk/by-label/GMAK8_DATA` at `/mnt/data`.
3. `mnt-data-prep.service` (`After=mnt-data.mount`, `Before=k3s.service`)
   creates `/mnt/data/{rancher,buildkit,tmp,log,local-path}`.
4. `gmak8-agent.service` (`After=mnt-data.mount`, no format responsibility)
   listens on **vsock port 1024**. gvproxy is vfkit unixgram, not vsock.
   Port **1025** is reserved for buildkitd (not in this image yet).

k3s is **not** installed in this image yet. The config template shipped at
`/etc/rancher/k3s/config.yaml` (source: [`k3s/config.yaml`](k3s/config.yaml)) is:

```yaml
data-dir: /mnt/data/rancher
default-local-storage-path: /mnt/data/local-path
```

Do **not** set `disable-helm-controller` (Traefik and metrics-server are
HelmChart addons). Do **not** set a custom `write-kubeconfig` path. The admin
file remains `/etc/rancher/k3s/k3s.yaml`.

## Guest agent (vsock 1024)

Source: [`agent/`](agent/). HTTP/1.1 over virtio-vsock, **not** gvproxy.

| Method | Path | Contract |
| --- | --- | --- |
| `GET` | `/health` | Agent process is up. Does **not** report data-disk mount. |
| `GET` | `/disks` | `gmak8_data` / `kite_data` are `mounted` when `/mnt/data` is `GMAK8_DATA`. |
| `GET` | `/kvm` | `kvm` is true iff `/dev/kvm` exists as a character device. |
| `PUT` | `/time` | SET_TIME / `chrony makestep` equivalent. Body: `{"unix":…}` or `{"rfc3339":"…"}`. |
| `POST` | `/shutdown` | ACPI-friendly `systemctl poweroff --no-block`. |

Host client: `Packages/Gmak8GuestClient`. Tests fake this HTTP API over loopback TCP.

```bash
make -C guest/agent test
make -C guest/agent install DESTDIR="$PWD/guest/mkosi/mkosi.extra"
```

## KVM

The kernel package is **`linux-image-arm64`**, not `linux-image-cloud-arm64`.
Debian arm64 KVM is a bool: regular `linux-image-arm64` is `CONFIG_KVM=y`
(built into vmlinux; there is no `kvm.ko` file). `CONFIG_KVM=m` plus `kvm.ko`
is also acceptable. Do not switch to the cloud flavour to “get a module”.

Image CI greps `/boot/config-*` for `CONFIG_KVM=y` **or** `CONFIG_KVM=m`.
When `=m`, it asserts `kvm.ko` exists (compressed suffixes allowed). When
`=y`, KVM is built-in (`modules.builtin` may list `kvm.ko` as a name only).
First boot runs `modprobe kvm` (a no-op when built-in; and `kvm-arm` if that
module is present). There is no TCG fallback.

## sshd

`openssh-server` is installed and **disabled**. PR 30 starts it when the Eureka
profile publishes L1:22 for the Builderdash jump. Do not mask the unit.

## OS replace / EFI

On **every** `os.img` replace (guest upgrade):

1. Stop the VM (ACPI, then force).
2. **Delete and recreate `efi-nvram.bin`.** Do not reuse NVRAM across GPT/ESP
   PARTUUIDs minted by mkosi. Firmware boot entries from the old ESP are poison.
3. **Keep `data.img` and `machine-identifier.bin`.**

## Build

Requires Linux (preferably arm64) with a recent mkosi. This Mac app repo does
not run mkosi as part of `scripts/ci.sh`.

```bash
cd guest/mkosi
mkosi summary
mkosi
```

Output is `guest/mkosi/mkosi.output/os.img` (8 GiB sparse). CI does **not** run
Virtualization.framework.

Host-side checks (no image build):

```bash
bash guest/mkosi/tests/validate.sh
bash guest/mkosi/tests/format-data-disk-test.sh
make -C guest/agent test
```

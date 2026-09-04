# gmak8 guest appliance

Debian 13 (trixie) arm64 image built with [mkosi](https://github.com/systemd/mkosi).
Virtualization.framework attaches two NVMe disks:

| Role | Guest device | Host file |
| --- | --- | --- |
| OS (replaceable) | the NVMe that contains the root GPT | `~/Library/Application Support/dev.gmak8.app/vm/os.img` |
| Data (persistent) | the other NVMe, whole-disk ext4 label `GMAK8_DATA` | `~/Library/Application Support/dev.gmak8.app/vm/data.img` |

Apple Virtualization.framework may number those as `nvme0n1`/`nvme1n1` in either order.
`format-data-disk.sh` formats the unpartitioned NVMe that is not the root device.

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
   path is `mkfs.ext4 -F` and wipes the device. It must not format the
   OS disk even when Linux names the OS `nvme1n1`.
2. `mnt-data.mount` mounts `/dev/disk/by-label/GMAK8_DATA` at `/mnt/data`.
3. `mnt-data-prep.service` (`After=mnt-data.mount`, `Before=k3s.service`)
   creates `/mnt/data/{rancher,buildkit,tmp,log,local-path}`.
4. `gmak8-agent.service` (`After=mnt-data.mount`, no format responsibility)
   listens on **vsock port 1024**. gvproxy is vfkit unixgram, not vsock.
   Port **1025** is reserved for buildkitd (not in this image yet).

k3s **`v1.33.3+k3s1`** is installed as a static arm64 binary (`/usr/local/bin/k3s`),
not a Debian k3s/containerd/docker package. mkosi postinst fetches
`https://github.com/k3s-io/k3s/releases/download/v1.33.3%2Bk3s1/k3s-arm64`
and checks the SHA256 in [`k3s/k3s.pin`](k3s/k3s.pin). `k3s.service`
`Requires=`/`After=` `mnt-data.mount`. `mnt-data-prep.service` is already
`Before=k3s.service`. k3s is **not** enabled at boot. The host probes
`GET /k3s` first, then `POST /k3s/start`. `gmak8-k3s-compat.service`
(`gmak8-agent -check-data-dir`) runs `Before=k3s.service` and fails if
`/mnt/data/rancher/server/db` has data whose Kubernetes minor is missing
or not `1.33`.

The config template shipped at `/etc/rancher/k3s/config.yaml` (source:
[`k3s/config.yaml`](k3s/config.yaml)) is also written by the host onto
virtio-fs tag `gmak8-config` at `/mnt/config/k3s/config.yaml` when that
share is attached:

```yaml
data-dir: /mnt/data/rancher
default-local-storage-path: /mnt/data/local-path
cluster-cidr: 10.42.0.0/16
service-cidr: 10.43.0.0/16
cluster-dns: 10.43.0.10
tls-san:
  - 127.0.0.1
  - localhost
  - gmak8
  - gmak8.internal
  - 192.168.127.2
node-name: gmak8
https-listen-port: 6443
```

Do **not** set `disable-helm-controller` (Traefik and metrics-server are
HelmChart addons). Do **not** set a custom `write-kubeconfig` path. The admin
file remains `/etc/rancher/k3s/k3s.yaml`. The agent reads that file for
`GET /kubeconfig`.

## k3s airgap images

First boot must not pull `docker.io/rancher/*`. The host drops the pinned archive
into `/mnt/data/rancher/agent/images/` **before** `POST /k3s/start`. k3s imports
those files on server start (`--data-dir /mnt/data/rancher`).

Pins (URL, SHA-256, 500 MiB budget) and the keyful Cosign public key live in
[`airgap/`](airgap/). Do **not** vendor `gmak8-k3s-airgap-v1.33.3-arm64.tar.zst`
in git. `fetch.sh` downloads the upstream `k3s-airgap-images-arm64.tar.zst` and
re-wraps it under that name. `sign.sh` / `verify.sh` use keyful Cosign
(`cosign.pub` is pinned in the app). macOS CI only checks metadata and a tiny
fixture tar.

## Guest agent (vsock 1024)

Source: [`agent/`](agent/). HTTP/1.1 over virtio-vsock, **not** gvproxy.

| Method | Path | Contract |
| --- | --- | --- |
| `GET` | `/health` | Agent process is up. Does **not** report data-disk mount. |
| `GET` | `/disks` | `gmak8_data` / `kite_data` are `mounted` when `/mnt/data` is `GMAK8_DATA`. |
| `GET` | `/kvm` | `kvm` is true iff `/dev/kvm` exists as a character device. |
| `GET` | `/kubeconfig` | Bytes of `/etc/rancher/k3s/k3s.yaml`, or 404 if missing. |
| `GET` | `/k3s` | JSON: systemd active, installed version, on-disk data-dir minor if known. |
| `POST` | `/k3s/start` | `systemctl start --no-block k3s` (after the host compatibility probe). |
| `GET` | `/node` | JSON: Node.Ready from `kubectl get nodes` (false if k3s is not up). |
| `GET` | `/airgap` | JSON: whether k3s airgap archives are in `/mnt/data/rancher/agent/images`. |
| `PUT` | `/airgap/k3s` | Stream an airgap `.tar` / `.tar.zst` into `agent/images` (vsock, 0600, fsync). Header `X-Gmak8-Name`. |
| `GET` | `/images` | containerd `k8s.io` images (`k3s ctr -n k8s.io images ls`). System images are `docker.io/rancher/*`. |
| `PUT` | `/images/import` | Stream an OCI/Docker tar to `/mnt/data/tmp`, `k3s ctr -n k8s.io images import`, unlink temp. Query `name=`. |
| `POST` | `/images/prune` | `k3s ctr -n k8s.io images prune`. |
| `GET` | `/host-mounts` | User virtio-fs shares from `/mnt/config/host-mounts.json`, with `stat` uid/gid. |
| `POST` | `/host-mounts/apply` | `mount -t virtiofs` each share at `/mnt/host/<name>`. |
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

# Eureka on gmak8

gmak8 is a local Kubernetes appliance. **Eureka** is a profile and a KubeVirt addon pack on that appliance, not a fork and not a copy of the Eureka tree.

This file is the Mac/ARM override list. Stock `image/env.py`, `u1.xlarge`, and amd64 cirros **Pending** here. Do not run them unmodified.

## Profiles

Pick one at first-run or in Settings → Kubernetes. There is one cluster on the Mac.

| Profile | Default vCPU | Default RAM | Data disk (sparse) | KubeVirt | Nested virt |
| --- | --- | --- | --- | --- | --- |
| Kubernetes | `min(4, host−2)` | 6 GiB if host ≥ 16 GiB, else 4 GiB | 60 GiB | Off | Off |
| Eureka | `min(8, host−2)` | 16 GiB if host ≥ 24 GiB; 12 GiB if host ≥ 18 GiB | 256 GiB | On | Required |
| Eureka API-only | 4 | 4 GiB | 60 GiB | On (CRDs) | Off |

Eureka is refused below 18 GiB RAM, 80 GiB free disk, or without nested virt (Apple Silicon M3+ and macOS 15+). Use Eureka API-only for object tests that do not need a Running VMI.

Eureka start also requires `default-local-storage-path: /mnt/data/local-path` and local-storage left enabled. PVCs must not land on the 8 GiB OS disk. See [k3s-deltas.md](k3s-deltas.md).

Pick Eureka **before** the first start if you want the 256 GiB sparse data disk. v1 does not grow an existing `data.img`.

## kubeconfig and virtctl

```bash
export KUBECONFIG="$HOME/Library/Application Support/dev.gmak8.app/kubeconfig"
export PATH="$HOME/.local/bin:$PATH"   # virtctl
```

gmak8 copies bundled `virtctl` v1.6.1 (darwin-arm64) to `~/.local/bin/virtctl`. Eureka’s SSH ProxyCommand looks up `virtctl` on `PATH`:

```
ProxyCommand virtctl port-forward --stdio=true vm/{name}/{namespace} %p
```

Do **not** use `ssh -p <nodePort> user@127.0.0.1` as the Eureka SSH path. NodePorts on 127.0.0.1 are for generic kubectl/curl.

1.0 soak (when the KubeVirt airgap pack is published): one Running aarch64 VMI, ServiceAccount virtiofs, and

```bash
virtctl port-forward --stdio=true vm/<name>/<ns> 22
```

## Instancetype (Cluster, not namespaced)

```yaml
instancetype:
  kind: VirtualMachineClusterInstancetype
  name: u1.nano          # smoke / cirros-sized
  # name: u1.medium      # fedora cloud / Builderdash
```

Not `u1.xlarge` (4 vCPU / 16 Gi — will not schedule in a 12–16 Gi L1). Not a namespaced `VirtualMachineInstancetype` unless you copy `u1.medium` into the VM namespace (that is an Eureka override, not gmak8).

gmak8 applies common-instancetypes v1.4.0 as **Cluster** objects. Verify:

```bash
kubectl get virtualmachineclusterinstancetype u1.nano
kubectl get virtualmachineclusterinstancetype u1.medium
```

## Disk image

Airgapped **linux/arm64** containerDisk from the KubeVirt pack:

- Reference: `quay.io/containerdisks/fedora:40`
- Digest: unpublished until `gmak8-kubevirt-airgap-1.6.1-arm64.tar.zst` is a GitHub Release with a real SHA-256. The pin in-tree is all zeros; pack-airgap.sh records the digest at pack time. Until then the addon pack is skipped.

**Not** `quay.io/kubevirt/cirros-container-disk-demo` (x86_64). **Not** Eureka GCE amd64 images.

CDI `StorageProfile` for `local-path` uses `cloneStrategy: copy` (host-assisted). A 35–55 Gi DataVolume is a full copy, not GCE csi-clone.

## Storage

```
k8s_storage_class: local-path
```

local-path **Retain** after a Builderdash `saveimage` is a local-PV caveat, not CSI clone.

## HTTPS / LoadBalancer

Klipper ServiceLB sets `status.loadBalancer.ingress[0].ip` to **192.168.127.2**, which is not a Mac route. `image/env.py` HTTPS to `{public_ip}:443` (`/apps/afw/admin/`) is GCE-shaped and **out of local proving**. Open OnDemand is not in the gmak8 GUI.

Two Eureka LoadBalancers both on 22/80/443 collide on Klipper hostPorts. Scaled-down local target is **one** nested VM.

## Builderdash (Mac/ARM config matrix)

Builderdash (omnibond/builderdash, Eureka `image/build.py -k`) does **not** call gmak8. gmak8 does not vendor it. Point Eureka at the local cluster:

| Knob | Local value |
| --- | --- |
| kubeconfig | `$HOME/Library/Application Support/dev.gmak8.app/kubeconfig` (context `gmak8`) |
| storage class | `local-path` |
| source disk | **aarch64** qcow2 — not the AlmaLinux-9 x86_64 GCS URL in `build.in` |
| instancetype | Cluster `u1.medium` (or a namespaced copy). Stock `u1.xlarge` Pending |
| DV size | one image at a time (35–100 Gi on the 256 Gi data disk) |
| SSH | `proxy_conf` → `127.0.0.1` and the published L1 SSH port (gmak8 PR 30), **or** `gmak8 port-forward vm/<name> 2222:22` then SSH localhost |

Until PR 30, virtctl `--stdio` (path A) is the SSH that works if the VMI is Running. Unmodified paramiko to the VMI pod IP does not, because that IP is inside L1.

## AFW / Python

Object-only tests (ConfigMap, Service, create VM YAML without Ready) run on Eureka API-only. Tests that wait `status.ready == true` need nested virt + the overrides above. AFW test 050 (3 replicas + in-guest DNS) is stretch, not a 1.0 gate.

Admin kubeconfig is the local credential. gmak8 does not implement OCL.

## What this profile will not run

- Full `env.py` controller + login + OrangeFS + batch VMPools
- Stock `env.py` / `u1.xlarge` / x86_64 cirros without the overrides above
- Production amd64 GCE images
- Open OnDemand in the gmak8 GUI
- HTTPS to Klipper EXTERNAL-IP
- Six-node scheduling
- Cilium

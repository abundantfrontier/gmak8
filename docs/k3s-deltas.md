# k3s deltas (gmak8 vs upstream defaults / Eureka kops)

gmak8 runs **k3s `v1.33.3+k3s1`**, single-node, **SQLite**. It is not kops, not GCE, not etcd, not Cilium.

Host-generated config is virtio-fs tag `gmak8-config` → guest `/mnt/config/k3s/config.yaml`.

## Always set

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

PVCs must live under `/mnt/data/local-path` (the data NVMe), never the 8 GiB OS disk. Eureka **refuses to start** without that path, and if Settings disables `local-storage`.

## Do not set

| Flag | Why |
| --- | --- |
| `disable-helm-controller` | Traefik and metrics-server are HelmChart addons. Disabling the controller drops them and leaves CoreDNS + ServiceLB. |
| custom `write-kubeconfig` | Admin kubeconfig stays `/etc/rancher/k3s/k3s.yaml`. The agent reads that file. |
| custom `--enable-admission-plugins` | Redundant with k3s defaults; additive lists are a footgun. |
| CoreDNS `--disable` | CoreDNS is not optional. Helm-controller is not a disable checkbox. |

Settings “Disable bundled” maps only to k3s `disable:` / `--disable=`: `traefik`, `servicelb`, `local-storage`, `metrics-server`.

## Privileged pods

k3s 1.33 does not deny privileged pods by default (no restricted PSS). Eureka kops `allowPrivileged: true` is the kops-era equivalent. Locally, virt-launcher privileged + `/dev/kvm` is allowed. Do not turn on PodSecurity restricted.

## Networking vs GCE

Klipper ServiceLB on one node assigns `EXTERNAL-IP=192.168.127.2` and hostPorts the Service ports. That is not a cloud LB and not a Mac route. See [eureka-local.md](eureka-local.md) for HTTPS-to-LB.

API bind is **127.0.0.1** only. Published NodePorts are 127.0.0.1. Eureka SSH is virtctl, not those NodePorts.

## Registries and proxy

Image pulls are **guest containerd**, not gvproxy. `registries.yaml` is mirrors/insecure/auth. Guest `HTTP(S)_PROXY` comes from the Mac system proxy (`/mnt/config/proxy.env`).

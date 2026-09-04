# KubeVirt addon pack

Pinned to Eureka: **KubeVirt v1.6.1**, **CDI v1.62.0**, **common-instancetypes v1.4.0**
(Cluster objects), feature gates `VMExport` and `EnableVirtioFsConfigVolumes`.

Do **not** curl GitHub while the cluster is starting. YAML in [`yaml/`](yaml/) is
applied by the guest agent from `/usr/local/share/gmak8/kubevirt`.

| File | Role |
| --- | --- |
| `kubevirt.pin` | Versions and smoke instancetype `u1.nano` |
| `virtctl.pin` | darwin-arm64 virtctl → `Contents/Helpers/virtctl` → `~/.local/bin/virtctl` |
| `airgap.pin` | Operand image tarball (not vendored) |
| `images.txt` | linux/arm64 images including virt-launcher/virtiofsd |
| `yaml/` | Operator+CR, CDI, StorageProfile `local-path` `cloneStrategy: copy`, ClusterInstancetypes |

`fetch-yaml.sh` refreshes YAML. Re-apply feature gates and `local-path-storageprofile.yaml`
after a refresh. `pack-airgap.sh` documents skopeo/crane (no Docker Engine).
`fetch-virtctl.sh` writes `ThirdParty/virtctl/bin/virtctl` (gitignored).

Install order is `apply-order.txt`. Missing `/dev/kvm` still applies CRDs/operator
so Eureka API-only works. Verify:

```
kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.phase}'
kubectl get virtualmachineclusterinstancetype u1.nano
```

# Changelog

## Unreleased

### Added

- Eureka and Eureka API-only profiles restamp CPU/RAM/disk from the host table in onboarding, Setup, and Settings.
- Eureka start is refused on low RAM, missing nested virt, disabled local-storage, or missing `default-local-storage-path: /mnt/data/local-path`.
- [docs/eureka-local.md](docs/eureka-local.md) — Mac/ARM instancetype, virtctl PATH, airgap disk, Builderdash config matrix.
- `guest/kubevirt/pack-airgap.sh` packs linux/arm64 images with skopeo (no Docker). KubeVirt operand pin is **v1.6.2** because v1.6.1 has no arm64. The GitHub SHA stays all zeros until Cosign-sign + Release upload.
- [docs/k3s-deltas.md](docs/k3s-deltas.md) — k3s config gmak8 actually writes.
- Engine `portForwardStart` / `portForwardStop` for `vm` / `vmi` via bundled virtctl bound to `127.0.0.1`. CLI `gmak8 port-forward vm/<name> [local:]remote`.
- Eureka can start guest sshd and publish it to `127.0.0.1:22022` (never host :22) for Builderdash `proxy_conf`.

### Notes

KubeVirt 1.0 soak (one aarch64 VMI Ready, SA virtiofs, `virtctl --stdio`) stays deferred until the KubeVirt airgap GitHub asset has a real SHA-256. AFW test 050 is stretch. Rosetta is a later PR. Builderdash SSH handshake to `127.0.0.1` waits on that same Ready VMI.

# Changelog

## Unreleased

### Added

- Eureka and Eureka API-only profiles restamp CPU/RAM/disk from the host table in onboarding, Setup, and Settings.
- Eureka start is refused on low RAM, missing nested virt, disabled local-storage, or missing `default-local-storage-path: /mnt/data/local-path`.
- [docs/eureka-local.md](docs/eureka-local.md) — Mac/ARM instancetype, virtctl PATH, airgap disk, Builderdash config matrix.
- [docs/k3s-deltas.md](docs/k3s-deltas.md) — k3s config gmak8 actually writes.

### Notes

KubeVirt 1.0 soak (one aarch64 VMI Ready, SA virtiofs, `virtctl --stdio`) stays deferred until the KubeVirt airgap GitHub asset has a real SHA-256. AFW test 050 is stretch. Rosetta is a later PR. Builderdash SSH to 127.0.0.1 is PR 30.

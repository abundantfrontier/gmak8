# Agent notes

gmak8 is a native **Swift / SwiftUI** macOS app (not Electron).

- Platform: **macOS 14+**, Apple Silicon (arm64) only
- Bundle ID: `dev.gmak8.app`
- LaunchAgent: `dev.gmak8.core` (`gmak8-core`)
- Display name / product: **gmak8**
- License: Apache-2.0; contributions use DCO (not a CLA)

## Do not

- Do not add Docker Engine, Docker CLI, Compose, Buildx-as-Docker, Docker Hub accounts, or `/var/run/docker.sock`
- Do not copy Eureka into this repository (it is an external profile / proving workload)
- Do not enable App Sandbox on the app or `gmak8-core`
- Do not set `com.apple.security.virtualization` on the UI target. Set it true on `gmak8-core` only.
- Do not implement the menu bar extra unless the current PR asks for it

## Layout

- `Apps/gmak8` — SwiftUI app (`gmak8.app`)
- `Apps/gmak8/Gmak8Core` — LaunchAgent (`gmak8-core`) listening on `engine.sock`
- `Apps/gmak8/CLI` — ArgumentParser CLI (`gmak8`) on `engine.sock` (`status`, `version`)
- `Packages/Gmak8Kit` — paths, settings, logging
- `Packages/Gmak8XPC` — NDJSON engine protocol, fake cluster state machine, peer/Team ID policy
- `Packages/Gmak8Virtualization` — VZ on `dev.gmak8.vm`, NVMe/EFI/serial, disk flock, virtio-vsock
- `Packages/Gmak8GuestClient` — vsock HTTP client to the guest agent on port 1024
- `docs/design.md` — product and implementation design
- `guest/mkosi` — Debian 13 arm64 appliance (data-disk format unit, KVM)
- `guest/agent` — Go HTTP agent on vsock 1024 (`GET /health`, `/disks`, `/kvm`, `/kubeconfig`, `/k3s`, `/node`, `PUT /time`, `POST /shutdown`)
- `guest/k3s` — k3s `v1.33.3+k3s1` pin, install script, config template (helm-controller on; admin kubeconfig `/etc/rancher/k3s/k3s.yaml`)

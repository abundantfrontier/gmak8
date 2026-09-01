# Agent notes

gmak8 is a native **Swift / SwiftUI** macOS app (not Electron).

- Platform: **macOS 14+**, Apple Silicon (arm64) only
- Bundle ID: `dev.gmak8.app`
- Display name / product: **gmak8**
- License: Apache-2.0; contributions use DCO (not a CLA)

## Do not

- Do not add Docker Engine, Docker CLI, Compose, Buildx-as-Docker, Docker Hub accounts, or `/var/run/docker.sock`
- Do not copy Eureka into this repository (it is an external profile / proving workload)
- Do not enable App Sandbox on the app in this phase
- Do not set `com.apple.security.virtualization` on the UI target
- Do not implement Virtualization, k3s, the menu bar extra, or the LaunchAgent unless the current PR asks for them

## Layout

- `Apps/gmak8` — SwiftUI app (`gmak8.app`)
- `Packages/Gmak8Kit` — shared Swift package
- `docs/design.md` — product and implementation design

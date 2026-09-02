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
- Do not set `com.apple.security.virtualization` on the UI target or on `gmak8-core` in this phase
- Do not implement Virtualization, k3s, or the menu bar extra unless the current PR asks for them

## Layout

- `Apps/gmak8` — SwiftUI app (`gmak8.app`)
- `Apps/gmak8/Gmak8Core` — LaunchAgent (`gmak8-core`) listening on `engine.sock`
- `Packages/Gmak8Kit` — paths, settings, logging
- `Packages/Gmak8XPC` — NDJSON engine protocol, fake cluster state machine, peer/Team ID policy
- `docs/design.md` — product and implementation design

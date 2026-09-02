# gmak8

**gmak8** is a native SwiftUI macOS appliance for one local Kubernetes cluster. It is not Docker, not Electron, and not a remote-cluster IDE. The same Apache-2.0 binary is for individuals, students, and companies.

This repository is early. The app currently opens a window; it does **not** start a cluster yet.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon
- Xcode with Swift 6

## Build

```bash
swift test --package-path Packages/Gmak8Kit
swift test --package-path Packages/Gmak8XPC
swift test --package-path Packages/Gmak8Virtualization
swift test --package-path Packages/Gmak8GuestClient

xcodebuild -project Apps/gmak8/gmak8.xcodeproj \
  -scheme gmak8 \
  -destination 'platform=macOS' \
  -quiet \
  build
```

The **gmak8** CLI (`status`, `version`) is the `gmak8-cli` scheme; `version` does not need `gmak8-core`. Open `Apps/gmak8/gmak8.xcodeproj` in Xcode and run the **gmak8** scheme.

CI on GitHub-hosted `macos-15` (arm64) runs `scripts/ci.sh` (format lint, package tests, xcodebuild test).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Design

See [docs/design.md](docs/design.md).

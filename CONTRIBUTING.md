# Contributing to gmak8

## Developer Certificate of Origin

This project uses the [Developer Certificate of Origin](https://developercertificate.org/) (DCO), not a CLA.

Every commit must include:

```
Signed-off-by: Your Name <you@example.com>
```

`git commit -s` adds this from your `user.name` and `user.email`.

## Build and test

Requirements: macOS 14+, Apple Silicon, Xcode with Swift 6.

```bash
swift test --package-path Packages/Gmak8Kit
swift test --package-path Packages/Gmak8XPC

xcodebuild -project Apps/gmak8/gmak8.xcodeproj \
  -scheme gmak8 \
  -destination 'platform=macOS' \
  test

xcodebuild -project Apps/gmak8/gmak8.xcodeproj \
  -scheme gmak8-core \
  -destination 'platform=macOS' \
  test

xcodebuild -project Apps/gmak8/gmak8.xcodeproj \
  -scheme gmak8-cli \
  -destination 'platform=macOS' \
  test
```

Format Swift with the repo config:

```bash
swift format --in-place --recursive --configuration .swift-format Apps Packages
```

CI on GitHub-hosted `macos-15` (arm64) runs `scripts/ci.sh` (format lint, Gmak8Kit tests, xcodebuild test). It does not run Virtualization.framework.

Do not add Docker, Compose, or a Docker socket shim. Do not copy the Eureka source tree into this repository.

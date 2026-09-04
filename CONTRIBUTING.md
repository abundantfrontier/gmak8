# Contributing to gmak8

## License

gmak8 is MIT, like other Abundant Frontier Institute projects. There is no CLA.

## Build and test

Requirements: macOS 14+, Apple Silicon, Xcode with Swift 6.

```bash
swift test --package-path Packages/Gmak8Kit
swift test --package-path Packages/Gmak8XPC
swift test --package-path Packages/Gmak8Virtualization
swift test --package-path Packages/Gmak8GuestClient
swift test --package-path Packages/Gmak8Kubernetes

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

Run tests **before** pushing to GitHub, on this Mac or on a builder you control (not GitHub Actions):

```bash
bash scripts/ci.sh
```

That is format lint, soak `--self-test`, package tests, and `xcodebuild test`. It does not boot a Linux VM. Guest mkosi checks are `bash guest/mkosi/tests/validate.sh` on Linux arm64 when you change the appliance.

Do not add GitHub Actions workflows. Do not add Docker, Compose, or a Docker socket shim. Do not copy the Eureka source tree into this repository.

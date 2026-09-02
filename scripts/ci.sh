#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift format lint --strict --recursive --configuration .swift-format Apps Packages
swift test --package-path Packages/Gmak8Kit
swift test --package-path Packages/Gmak8XPC
swift test --package-path Packages/Gmak8Virtualization
swift test --package-path Packages/Gmak8GuestClient
xcodebuild -project Apps/gmak8/gmak8.xcodeproj -scheme gmak8 -destination 'platform=macOS' test

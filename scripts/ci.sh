#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift format lint --recursive --configuration .swift-format Apps Packages
swift test --package-path Packages/Gmak8Kit
xcodebuild -project Apps/gmak8/gmak8.xcodeproj -scheme gmak8 -destination 'platform=macOS' test

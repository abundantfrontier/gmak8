#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if git ls-files | grep -Ei '(^|/)(cosign\.key|AuthKey_[A-Za-z0-9]+\.p8|.*eddsa.*private.*|sparkle_private.*)$'
then
    echo "error: private key files must not be committed" >&2
    exit 1
fi
if git grep -I -n -E -- '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----'
then
    echo "error: PEM private key material must not be committed" >&2
    exit 1
fi

swift format lint --strict --recursive --configuration .swift-format Apps Packages
# Plan-only soak checks. Must not pass --live (no VZ on GitHub-hosted macOS).
bash scripts/soak.sh --self-test
swift test --package-path Packages/Gmak8Kit
swift test --package-path Packages/Gmak8XPC
swift test --package-path Packages/Gmak8Virtualization
swift test --package-path Packages/Gmak8GuestClient
xcodebuild -project Apps/gmak8/gmak8.xcodeproj -scheme gmak8 -destination 'platform=macOS' test

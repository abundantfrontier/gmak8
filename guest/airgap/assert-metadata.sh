#!/bin/sh
# Pin, Cosign pubkey, and size-budget checks. Does not download the airgap blob.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
PIN="$here/k3s-airgap.pin"
PUB="$here/cosign.pub"
KIT_PIN="$root/Packages/Gmak8Kit/Sources/Gmak8Kit/Airgap/k3s-airgap.pin"
KIT_PUB="$root/Packages/Gmak8Kit/Sources/Gmak8Kit/Airgap/cosign.pub"
SWIFT="$root/Packages/Gmak8Kit/Sources/Gmak8Kit/Airgap/AirgapPin.swift"
AGENT="$root/guest/agent/airgap.go"

fail() {
  echo "airgap-metadata: $*" >&2
  exit 1
}

test -f "$PIN" || fail "missing $PIN"
test -f "$PUB" || fail "missing $PUB"
test -f "$here/k3s-airgap-images-arm64.sha256sum" || fail "missing sha256sum file"
test -f "$here/k3s-images.txt" || fail "missing k3s-images.txt"
test -f "$here/testdata/tiny.tar" || fail "missing testdata/tiny.tar"
test -f "$here/testdata/tiny.tar.sig" || fail "missing testdata/tiny.tar.sig"
test -f "$here/testdata/cosign.pub" || fail "missing testdata/cosign.pub"
if cmp -s "$here/testdata/cosign.pub" "$PUB"; then
  fail "fixture Cosign key must not be the production pin"
fi
if test -f "$here/testdata/cosign.key"; then
  fail "must not commit the fixture Cosign private key"
fi
test -x "$here/fetch.sh" || fail "fetch.sh must be executable"
test -x "$here/sign.sh" || fail "sign.sh must be executable"
test -x "$here/verify.sh" || fail "verify.sh must be executable"

# shellcheck disable=SC1090
. "$PIN"
test "${K3S_VERSION:-}" = "v1.33.3+k3s1" || fail "K3S_VERSION must be v1.33.3+k3s1"
test "${AIRGAP_NAME:-}" = "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst" || fail "AIRGAP_NAME"
test "${GUEST_IMAGES_DIR:-}" = "/mnt/data/rancher/agent/images" || fail "GUEST_IMAGES_DIR"
echo "${AIRGAP_URL:-}" | grep -q '%2B' || fail "AIRGAP_URL must encode + as %2B"
echo "${AIRGAP_SHA256:-}" | grep -Eq '^[0-9a-f]{64}$' || fail "AIRGAP_SHA256 must be 64 lowercase hex"
test "${AIRGAP_SHA256}" = "c12ec7b122f34eb1f89310b05e66b500a2f49522d7cd4ceb3475a675cab6ebc6" || fail "AIRGAP_SHA256 must match k3s v1.33.3+k3s1 arm64 zst"
test "${AIRGAP_MAX_BYTES:-0}" -le 524288000 || fail "AIRGAP_MAX_BYTES must be <= 500 MiB"
test "${AIRGAP_MAX_BYTES:-0}" -lt 2147483648 || fail "AIRGAP_MAX_BYTES must stay under the 2 GiB GitHub Release limit"
test "${AIRGAP_MAX_BYTES:-0}" -gt 0 || fail "AIRGAP_MAX_BYTES must be positive"

grep -q 'BEGIN PUBLIC KEY' "$PUB" || fail "cosign.pub must be a keyful PEM public key"
grep -q 'END PUBLIC KEY' "$PUB" || fail "cosign.pub must be a keyful PEM public key"
if grep -q 'BEGIN ENCRYPTED COSIGN PRIVATE KEY\|BEGIN PRIVATE KEY\|BEGIN EC PRIVATE KEY' "$PUB" "$PIN"; then
  fail "must not commit a Cosign private key"
fi

cmp -s "$PIN" "$KIT_PIN" || fail "Gmak8Kit k3s-airgap.pin must match guest/airgap"
cmp -s "$PUB" "$KIT_PUB" || fail "Gmak8Kit cosign.pub must match guest/airgap"

grep -q 'gmak8-k3s-airgap-v1.33.3-arm64.tar.zst' "$SWIFT" || fail "AirgapPin.swift must name the archive"
grep -q '500 \* 1_024 \* 1_024' "$SWIFT" || fail "AirgapPin.swift must pin the 500 MiB budget"
grep -q '/mnt/data/rancher/agent/images' "$SWIFT" || fail "AirgapPin.swift must pin the guest images dir"
grep -q '500 \* 1024 \* 1024' "$AGENT" || fail "agent must cap imports at 500 MiB"

grep -q 'docker.io/rancher/mirrored-pause' "$here/k3s-images.txt" || fail "k3s-images.txt must list rancher images first boot would pull"
grep -q "$AIRGAP_SHA256" "$here/k3s-airgap-images-arm64.sha256sum" || fail "sha256sum file must include the pin"

# Refuse vendoring the real multi-hundred-MB archive.
# The 4 KiB testdata tar is a fixture, not the k3s airgap blob.
found=$(find "$here" -type f \( -name '*.tar.zst' -o -name '*.tar.gz' -o -size +1M \) ! -path '*/.*' || true)
if [ -n "$found" ]; then
  fail "airgap tree must not vendor large blobs: $found"
fi

echo "airgap-metadata: ok"

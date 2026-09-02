#!/bin/sh
# SHA-256 plus keyful Cosign verify-blob. Public key is pinned in this directory.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PIN=${PIN:-"$here/k3s-airgap.pin"}
# shellcheck disable=SC1090
. "$PIN"

blob=${1:-}
test -n "$blob" || {
  echo "usage: verify.sh <archive> [signature]" >&2
  exit 1
}
test -f "$blob" || {
  echo "verify.sh: missing $blob" >&2
  exit 1
}
sig=${2:-"$blob.sig"}
test -f "$sig" || {
  echo "verify.sh: missing Cosign signature $sig" >&2
  exit 1
}
pub=${COSIGN_PUB:-"$here/cosign.pub"}
test -f "$pub" || {
  echo "verify.sh: missing Cosign public key $pub" >&2
  exit 1
}
cosign=${COSIGN:-cosign}

size=$(wc -c < "$blob")
if [ "$size" -gt "$AIRGAP_MAX_BYTES" ]; then
  echo "verify.sh: $size bytes exceeds AIRGAP_MAX_BYTES=$AIRGAP_MAX_BYTES" >&2
  exit 1
fi
echo "$AIRGAP_SHA256  $blob" | sha256sum -c -
"$cosign" verify-blob --key "$pub" --signature "$sig" --insecure-ignore-tlog --offline "$blob"
echo "verify.sh: ok"

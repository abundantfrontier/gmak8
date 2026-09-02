#!/bin/sh
# Keyful Cosign sign-blob. Does not use Fulcio/Rekor keyless.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
blob=${1:-}
test -n "$blob" || {
  echo "usage: sign.sh <archive>" >&2
  exit 1
}
test -f "$blob" || {
  echo "sign.sh: missing $blob" >&2
  exit 1
}
test -n "${COSIGN_KEY:-}" || {
  echo "sign.sh: COSIGN_KEY is required (path to keyful Cosign private key)" >&2
  exit 1
}

sig=${SIGNATURE:-"$blob.sig"}
cosign=${COSIGN:-cosign}

"$cosign" sign-blob --key "$COSIGN_KEY" --tlog-upload=false --yes --output-signature "$sig" "$blob"
chmod 0600 "$sig"
echo "sign.sh: wrote $sig"

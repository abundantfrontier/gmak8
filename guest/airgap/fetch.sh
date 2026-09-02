#!/bin/sh
# Fetch the pinned k3s airgap archive. Does not pull docker.io. Do not vendor the blob in git.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PIN=${PIN:-"$here/k3s-airgap.pin"}
# shellcheck disable=SC1090
. "$PIN"

test -n "${AIRGAP_URL:-}" || {
  echo "fetch-airgap: AIRGAP_URL missing in $PIN" >&2
  exit 1
}
test -n "${AIRGAP_SHA256:-}" || {
  echo "fetch-airgap: AIRGAP_SHA256 missing in $PIN" >&2
  exit 1
}
test -n "${AIRGAP_NAME:-}" || {
  echo "fetch-airgap: AIRGAP_NAME missing in $PIN" >&2
  exit 1
}
test -n "${AIRGAP_MAX_BYTES:-}" || {
  echo "fetch-airgap: AIRGAP_MAX_BYTES missing in $PIN" >&2
  exit 1
}

dest=${DEST:-"$here/$AIRGAP_NAME"}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

curl -fsSL --retry 5 --retry-delay 2 -o "$tmp" "$AIRGAP_URL"
size=$(wc -c < "$tmp")
if [ "$size" -gt "$AIRGAP_MAX_BYTES" ]; then
  echo "fetch-airgap: $size bytes exceeds AIRGAP_MAX_BYTES=$AIRGAP_MAX_BYTES" >&2
  exit 1
fi
echo "$AIRGAP_SHA256  $tmp" | sha256sum -c -
install -d "$(dirname "$dest")"
install -m 0600 "$tmp" "$dest"
echo "fetch-airgap: wrote $dest ($size bytes)"

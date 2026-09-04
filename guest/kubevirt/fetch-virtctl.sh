#!/bin/sh
# Fetch pinned virtctl darwin-arm64. Do not vendor the Mach-O in git.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/virtctl.pin"
repo=$(CDPATH= cd -- "$here/../.." && pwd)
dest=${DEST:-"$repo/ThirdParty/virtctl/bin/virtctl"}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 5 --retry-delay 2 -o "$tmp" "$VIRTCTL_URL"
size=$(wc -c < "$tmp")
if [ "$size" -gt "$VIRTCTL_MAX_BYTES" ]; then
  echo "fetch-virtctl: $size bytes exceeds VIRTCTL_MAX_BYTES=$VIRTCTL_MAX_BYTES" >&2
  exit 1
fi
echo "$VIRTCTL_SHA256  $tmp" | shasum -a 256 -c -
install -d "$(dirname "$dest")"
install -m 0755 "$tmp" "$dest"
echo "fetch-virtctl: wrote $dest ($size bytes)"

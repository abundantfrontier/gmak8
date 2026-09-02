#!/bin/sh
# Fetch and install the pinned k3s static binary. Not a Debian k3s/docker package.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PIN=${PIN:-"$here/k3s.pin"}
# shellcheck disable=SC1090
. "$PIN"

test -n "${K3S_URL:-}" || {
  echo "install-k3s: K3S_URL missing in $PIN" >&2
  exit 1
}
test -n "${K3S_SHA256:-}" || {
  echo "install-k3s: K3S_SHA256 missing in $PIN" >&2
  exit 1
}

dest=${DESTDIR:-}/usr/local/bin/k3s
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

curl -fsSL --retry 5 --retry-delay 2 -o "$tmp" "$K3S_URL"
echo "$K3S_SHA256  $tmp" | sha256sum -c -
install -d "$(dirname "$dest")"
install -m 0755 "$tmp" "$dest"
ln -sfn k3s "$(dirname "$dest")/kubectl"
ln -sfn k3s "$(dirname "$dest")/crictl"
ln -sfn k3s "$(dirname "$dest")/ctr"

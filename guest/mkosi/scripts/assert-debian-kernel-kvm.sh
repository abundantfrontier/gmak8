#!/usr/bin/env bash
# Download Debian trixie linux-image-arm64 (not cloud) and assert CONFIG_KVM=y|m.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
packages_url=${PACKAGES_URL:-http://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.gz}
mirror=${DEBIAN_MIRROR:-http://deb.debian.org/debian}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 - "$packages_url" "$mirror" "$work" <<'PY'
import gzip, sys, urllib.request
from pathlib import Path

packages_url, mirror, work = sys.argv[1], sys.argv[2], Path(sys.argv[3])
with urllib.request.urlopen(packages_url, timeout=120) as resp:
    text = gzip.decompress(resp.read()).decode("utf-8", "replace")

pkgs = {}
for block in text.split("\n\n"):
    fields = {}
    key = None
    for line in block.splitlines():
        if not line:
            continue
        if line.startswith(" ") and key:
            fields[key] += "\n" + line[1:]
            continue
        if ":" in line:
            key, val = line.split(":", 1)
            fields[key] = val.strip()
    name = fields.get("Package")
    if name:
        pkgs[name] = fields

meta = pkgs.get("linux-image-arm64")
if not meta:
    sys.exit("linux-image-arm64 metapackage not found in Packages")
depends = meta.get("Depends", "")
dep = depends.split(",")[0].split("(")[0].strip()
if not dep or "cloud" in dep or "rt-" in dep:
    sys.exit(f"unexpected linux-image-arm64 dependency: {depends!r}")
pkg = pkgs.get(dep)
if not pkg:
    sys.exit(f"kernel package {dep} not in Packages")
filename = pkg.get("Filename")
if not filename:
    sys.exit(f"no Filename for {dep}")
url = mirror.rstrip("/") + "/" + filename
(work / "kernel.url").write_text(url + "\n")
(work / "kernel.pkg").write_text(dep + "\n")
print(f"kernel: {dep}")
print(f"url: {url}")
PY

url=$(cat "$work/kernel.url")
curl -fsSL --retry 3 -o "$work/kernel.deb" "$url"
mkdir -p "$work/rootfs"
dpkg-deb -x "$work/kernel.deb" "$work/rootfs"
bash "$here/assert-kvm.sh" "$work/rootfs"

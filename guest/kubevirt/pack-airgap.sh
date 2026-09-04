#!/bin/sh
# Pack linux/arm64 KubeVirt/CDI images with skopeo. Not Docker. Do not vendor the tarball.
#
#   bash guest/kubevirt/pack-airgap.sh --self-test   # CI: no registry pull
#   bash guest/kubevirt/pack-airgap.sh               # writes $DEST (gitignored)
#
# Output is an OCI image-layout tar.zst for `ctr -n k8s.io images import`.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
# shellcheck disable=SC1091
. "$here/airgap.pin"

images="$here/images.txt"
kit_pin="$root/Packages/Gmak8Kit/Sources/Gmak8Kit/KubeVirt/kubevirt-airgap.pin"
out=${DEST:-"$root/.build/kubevirt-airgap/$AIRGAP_NAME"}
smoke_ref="quay.io/containerdisks/fedora:40"
forbidden_disk="quay.io/kubevirt/cirros-container-disk-demo"
arch=arm64
os=linux

usage() {
  echo "usage: pack-airgap.sh [--self-test]" >&2
}

fail() {
  echo "pack-airgap: $*" >&2
  exit 1
}

list_images() {
  grep -v '^[[:space:]]*#' "$images" | grep -v '^[[:space:]]*$'
}

assert_images() {
  test -f "$images" || fail "missing $images"
  test -s "$images" || fail "empty $images"
  if grep -E '^[[:space:]]*docker\.io/' "$images"; then
    fail "images.txt must not list docker.io"
  fi
  if grep -F "$forbidden_disk" "$images" | grep -v '^[[:space:]]*#'; then
    fail "images.txt must not pack $forbidden_disk (x86_64)"
  fi
  list_images | grep -qx "$smoke_ref" || fail "images.txt must list $smoke_ref"
  list_images | grep -q 'quay.io/kubevirt/virt-launcher:' || fail "images.txt must list virt-launcher"
  list_images | grep -q 'quay.io/kubevirt/cdi-operator:' || fail "images.txt must list cdi-operator"
}

assert_pin() {
  test -f "$here/airgap.pin" || fail "missing airgap.pin"
  test -f "$kit_pin" || fail "missing $kit_pin"
  cmp -s "$here/airgap.pin" "$kit_pin" || fail "Gmak8Kit kubevirt-airgap.pin must match guest/kubevirt/airgap.pin"
  test "${KUBEVIRT_VERSION:-}" = "v1.6.2" || fail "KUBEVIRT_VERSION"
  test "${AIRGAP_NAME:-}" = "gmak8-kubevirt-airgap-1.6.2-arm64.tar.zst" || fail "AIRGAP_NAME"
  test "${GUEST_IMAGES_DIR:-}" = "/mnt/data/rancher/agent/images" || fail "GUEST_IMAGES_DIR"
  echo "${AIRGAP_SHA256:-}" | grep -Eq '^[0-9a-f]{64}$' || fail "AIRGAP_SHA256 must be 64 lowercase hex"
  test "${AIRGAP_MAX_BYTES:-0}" -eq 1610612736 || fail "AIRGAP_MAX_BYTES must be 1.5 GiB"
  test "${AIRGAP_MAX_BYTES:-0}" -lt 2147483648 || fail "AIRGAP_MAX_BYTES must stay under the 2 GiB GitHub Release limit"
  echo "${AIRGAP_URL:-}" | grep -q 'abundantfrontier/gmak8' || fail "AIRGAP_URL must be a gmak8 GitHub Release"
}

assert_no_vendored_blob() {
  found=$(find "$here" -type f \( -name '*.tar.zst' -o -name '*.tar.gz' -o -name '*.tar' -o -size +1M \) ! -path '*/.*' || true)
  if [ -n "$found" ]; then
    fail "kubevirt tree must not vendor large blobs: $found"
  fi
}

self_test() {
  test -x "$here/pack-airgap.sh" || fail "pack-airgap.sh must be executable"
  assert_pin
  assert_images
  assert_no_vendored_blob
  echo "pack-airgap: self-test ok"
}

inspect_smoke_digest() {
  skopeo inspect --override-arch "$arch" --override-os "$os" "docker://$smoke_ref" \
    | awk -F '"' '/"Digest":/ { print $4; exit }'
}

require_arm64() {
  img=$1
  raw=$(skopeo inspect --raw "docker://$img") || fail "inspect $img"
  echo "$raw" | grep -q '"architecture":"arm64"' || echo "$raw" | grep -q '"architecture": "arm64"' ||
    fail "$img has no linux/arm64 (KubeVirt v1.6.1 dropped arm64; use v1.6.2+)"
}

merge_docker_archives() {
  dest=$1
  shift
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to merge docker-archives"
  python3 - "$dest" "$@" <<'PY'
import io, json, sys, tarfile

out_path = sys.argv[1]
inputs = sys.argv[2:]
if not inputs:
    raise SystemExit("no docker-archives to merge")
manifests = []
seen = set()
with tarfile.open(out_path, "w") as out:
    for path in inputs:
        with tarfile.open(path, "r") as inp:
            manifests.extend(json.load(inp.extractfile("manifest.json")))
            for member in inp.getmembers():
                if member.name == "manifest.json" or member.name in seen:
                    continue
                seen.add(member.name)
                fileobj = inp.extractfile(member) if member.isfile() else None
                out.addfile(member, fileobj)
    blob = json.dumps(manifests).encode()
    info = tarfile.TarInfo("manifest.json")
    info.size = len(blob)
    out.addfile(info, io.BytesIO(blob))
PY
}

pack() {
  command -v skopeo >/dev/null 2>&1 || fail "skopeo is required (brew install skopeo). Do not use Docker."
  command -v zstd >/dev/null 2>&1 || fail "zstd is required"
  command -v tar >/dev/null 2>&1 || fail "tar is required"
  assert_pin
  assert_images

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/gmak8-kubevirt-airgap.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  parts=""
  n=0
  digest=""
  while IFS= read -r img; do
    require_arm64 "$img"
    n=$((n + 1))
    part=$(printf "%s/img-%02d.tar" "$tmp" "$n")
    echo "pack-airgap: copy $img (linux/$arch)" >&2
    skopeo copy \
      --override-arch "$arch" \
      --override-os "$os" \
      "docker://$img" \
      "docker-archive:${part}:${img}"
    parts="$parts $part"
    if [ "$img" = "$smoke_ref" ]; then
      digest=$(inspect_smoke_digest)
    fi
  done <<EOF
$(list_images)
EOF

  test -n "$digest" || fail "could not inspect $smoke_ref digest"
  test "$n" -gt 0 || fail "no images to pack"

  # shellcheck disable=SC2086
  merge_docker_archives "$tmp/merged.tar" $parts

  mkdir -p "$(dirname "$out")"
  zstd -f -T0 -19 -o "$out" "$tmp/merged.tar"
  chmod 0600 "$out"

  size=$(wc -c < "$out")
  if [ "$size" -gt "$AIRGAP_MAX_BYTES" ]; then
    fail "$size bytes exceeds AIRGAP_MAX_BYTES=$AIRGAP_MAX_BYTES (try a smaller arm64 smoke disk)"
  fi
  sha=$(shasum -a 256 "$out" | awk '{ print $1 }')

  echo "pack-airgap: wrote $out ($size bytes)"
  echo "pack-airgap: sha256 $sha"
  echo "pack-airgap: smoke digest $smoke_ref@$digest"
  echo "pack-airgap: next: COSIGN_KEY=... bash guest/airgap/sign.sh $out"
  echo "pack-airgap: then: gh release upload v0.0.1 $out ${out}.sig --repo abundantfrontier/gmak8"
  echo "pack-airgap: then pin AIRGAP_SHA256 and the fedora digest in docs/eureka-local.md"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  -h|--help)
    usage
    ;;
  "")
    pack
    ;;
  *)
    usage
    exit 1
    ;;
esac

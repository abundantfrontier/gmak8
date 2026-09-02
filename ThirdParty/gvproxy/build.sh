#!/usr/bin/env bash
# Build darwin/arm64 gvproxy from the pinned gvisor-tap-vsock tag.
# Requires Go. If go is missing, this script exits 0 so CI can pin without building.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/PIN"

OUT="${ROOT}/bin/gvproxy"
SRC="${ROOT}/src"

if ! command -v go >/dev/null 2>&1; then
    echo "go not found; gvproxy ${VERSION} is pinned in ${ROOT}/PIN."
    echo "Install Go and re-run $0 to build ${OUT} (darwin/arm64)."
    exit 0
fi

rm -rf "${SRC}"
git clone --depth 1 --branch "${VERSION}" "${REPO}" "${SRC}"
mkdir -p "${ROOT}/bin"
# gvproxy v0.8.9 needs Go 1.25+; auto-download that toolchain if the host Go is older.
(
    cd "${SRC}"
    GOTOOLCHAIN=auto GOOS=darwin GOARCH=arm64 go build -o "${OUT}" ./cmd/gvproxy
)
echo "built ${OUT} (${VERSION})"

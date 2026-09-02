#!/usr/bin/env bash
# gvproxy must be signed with Hardened Runtime and the same Team ID as
# gmak8 / gmak8-core. Go binaries may need
# com.apple.security.cs.allow-unsigned-executable-memory and/or
# com.apple.security.cs.disable-library-validation; measure, don't assume.
set -euo pipefail

BIN="${1:?usage: sign.sh path/to/gvproxy}"
if [[ ! -f "${BIN}" ]]; then
    echo "sign.sh: missing binary ${BIN}" >&2
    exit 1
fi

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "sign.sh: CODESIGN_IDENTITY unset; not signing ${BIN}"
    echo "Required later: codesign --force --options runtime --sign <Team ID> --timestamp ${BIN}"
    exit 0
fi

codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" --timestamp "${BIN}"
codesign --verify --verbose=2 "${BIN}"

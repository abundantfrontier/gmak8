#!/usr/bin/env bash
# Copy the pinned gvproxy into gmak8.app/Contents/Helpers and sign it with the
# same identity as the app. Missing binary is a warning so CI can run without Go.
set -euo pipefail

SRC="${SRCROOT}/../../ThirdParty/gvproxy/bin/gvproxy"
DEST="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Helpers/gvproxy"
mkdir -p "$(dirname "${DEST}")"

if [[ ! -x "${SRC}" ]]; then
    echo "warning: gvproxy not built at ${SRC}; run ThirdParty/gvproxy/build.sh"
    exit 0
fi

cp -f "${SRC}" "${DEST}"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -n "${IDENTITY}" && "${IDENTITY}" != "-" ]]; then
    codesign --force --sign "${IDENTITY}" --options runtime --timestamp=none "${DEST}"
else
    codesign --force --sign - --timestamp=none "${DEST}" || true
fi

#!/usr/bin/env bash
# Copy pinned virtctl into gmak8.app/Contents/Helpers. Missing binary is a warning.
set -euo pipefail

SRC="${SRCROOT}/../../ThirdParty/virtctl/bin/virtctl"
DEST="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Helpers/virtctl"
mkdir -p "$(dirname "${DEST}")"

if [[ ! -x "${SRC}" ]]; then
    echo "warning: virtctl not fetched at ${SRC}; run guest/kubevirt/fetch-virtctl.sh"
    exit 0
fi

cp -f "${SRC}" "${DEST}"
chmod u+w "${DEST}"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -n "${IDENTITY}" && "${IDENTITY}" != "-" ]]; then
    codesign --force --sign "${IDENTITY}" --options runtime --timestamp=none "${DEST}"
else
    codesign --force --sign - --timestamp=none "${DEST}" || true
fi

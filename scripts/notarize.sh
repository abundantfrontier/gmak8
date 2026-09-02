#!/usr/bin/env bash
# Submit a signed DMG to Apple notary. The API key file is a GitHub Actions secret — never the repo.
# Usage: scripts/notarize.sh dist/gmak8-0.0.1.dmg
set -euo pipefail

DMG="${1:?usage: notarize.sh /path/to/gmak8.dmg}"
KEY_PATH="${NOTARY_API_KEY_PATH:-}"
KEY_ID="${NOTARY_API_KEY_ID:-}"
ISSUER="${NOTARY_API_ISSUER:-}"

if [[ ! -f "${DMG}" ]]; then
    echo "notarize.sh: missing ${DMG}" >&2
    exit 1
fi
if [[ -z "${KEY_PATH}" || -z "${KEY_ID}" || -z "${ISSUER}" ]]; then
    echo "notarize.sh: set NOTARY_API_KEY_PATH, NOTARY_API_KEY_ID, NOTARY_API_ISSUER" >&2
    exit 1
fi
if [[ ! -f "${KEY_PATH}" ]]; then
    echo "notarize.sh: missing API key file" >&2
    exit 1
fi

xcrun notarytool submit "${DMG}" \
    --key "${KEY_PATH}" \
    --key-id "${KEY_ID}" \
    --issuer "${ISSUER}" \
    --wait
xcrun stapler staple "${DMG}"
echo "notarize.sh: stapled ${DMG}"

#!/usr/bin/env bash
# Sign every Mach-O in gmak8.app (Developer ID, Hardened Runtime) and wrap a UDZO DMG.
# Usage: scripts/package-dmg.sh /path/to/gmak8.app [dist/gmak8.dmg]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: package-dmg.sh /path/to/gmak8.app [output.dmg]}"
APP="$(cd "$(dirname "${APP}")" && pwd)/$(basename "${APP}")"
VERSION="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist" 2>/dev/null || echo 0.0.1)}"
OUTPUT="${2:-"${ROOT}/dist/gmak8-${VERSION}.dmg"}"
IDENTITY="${CODESIGN_IDENTITY:-}"
APP_ENTITLEMENTS="${ROOT}/Apps/gmak8/Entitlements/gmak8.entitlements"
CORE_ENTITLEMENTS="${ROOT}/Apps/gmak8/Entitlements/gmak8-core.entitlements"

if [[ ! -d "${APP}" ]]; then
    echo "package-dmg.sh: missing app bundle ${APP}" >&2
    exit 1
fi

sign() {
    local target="$1"
    shift
    if [[ -z "${IDENTITY}" ]]; then
        echo "package-dmg.sh: CODESIGN_IDENTITY unset; skip ${target}"
        return 0
    fi
    codesign --force --options runtime --timestamp --sign "${IDENTITY}" "$@" "${target}"
}

sign_helpers() {
    local helpers="${APP}/Contents/Helpers"
    if [[ ! -d "${helpers}" ]]; then
        return 0
    fi
    local helper
    for helper in "${helpers}"/*; do
        [[ -e "${helper}" ]] || continue
        # Bundle Helpers only — never PATH.
        if [[ -d "${helper}" ]]; then
            sign "${helper}"
        elif [[ -f "${helper}" ]]; then
            sign "${helper}"
        fi
    done
}

sign_sparkle() {
    local sparkle="${APP}/Contents/Frameworks/Sparkle.framework"
    if [[ ! -d "${sparkle}" ]]; then
        return 0
    fi
    local xpc updater autoupdate
    while IFS= read -r xpc; do
        sign "${xpc}"
    done < <(find "${sparkle}" -name '*.xpc' -print)
    while IFS= read -r updater; do
        sign "${updater}"
    done < <(find "${sparkle}" -name 'Updater.app' -print)
    while IFS= read -r autoupdate; do
        sign "${autoupdate}"
    done < <(find "${sparkle}" \( -name Autoupdate -o -name Autoupdate.app \) -print)
    sign "${sparkle}"
}

sign_helpers
sign_sparkle

if [[ -x "${APP}/Contents/MacOS/gmak8-core" ]]; then
    sign "${APP}/Contents/MacOS/gmak8-core" --entitlements "${CORE_ENTITLEMENTS}"
fi
if [[ -x "${APP}/Contents/MacOS/gmak8" ]]; then
    sign "${APP}/Contents/MacOS/gmak8" --entitlements "${APP_ENTITLEMENTS}"
fi
sign "${APP}" --entitlements "${APP_ENTITLEMENTS}"

if [[ -n "${IDENTITY}" ]]; then
    codesign --verify --deep --strict --verbose=2 "${APP}"
fi

mkdir -p "$(dirname "${OUTPUT}")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/gmak8-dmg.XXXXXX")"
trap 'rm -rf "${STAGING}"' EXIT
cp -R "${APP}" "${STAGING}/gmak8.app"
ln -s /Applications "${STAGING}/Applications"

rm -f "${OUTPUT}"
hdiutil create \
    -volname gmak8 \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${OUTPUT}"

echo "package-dmg.sh: wrote ${OUTPUT}"

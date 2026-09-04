#!/usr/bin/env bash
# Build a Debug gmak8.app and copy it to /Applications so SMAppService can register.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash ThirdParty/gvproxy/build.sh

DERIVED="${ROOT}/.build/DerivedData"
xcodebuild -project Apps/gmak8/gmak8.xcodeproj \
    -scheme gmak8 \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED}" \
    build

APP="${DERIVED}/Build/Products/Debug/gmak8.app"
DEST="/Applications/gmak8.app"
if [[ ! -d "${APP}" ]]; then
    echo "error: build did not produce ${APP}" >&2
    exit 1
fi
if [[ ! -x "${APP}/Contents/Helpers/gvproxy" ]]; then
    echo "warning: gvproxy missing from Helpers; VM start will fail until ThirdParty/gvproxy/build.sh succeeds" >&2
fi

osascript -e 'tell application "gmak8" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x gmak8 >/dev/null 2>&1; then
        break
    fi
    sleep 0.3
done
if pgrep -x gmak8 >/dev/null 2>&1 || pgrep -x gmak8-core >/dev/null 2>&1; then
    killall gmak8 gmak8-core >/dev/null 2>&1 || true
    sleep 0.5
fi
if pgrep -x gmak8 >/dev/null 2>&1 || pgrep -x gmak8-core >/dev/null 2>&1; then
    killall -9 gmak8 gmak8-core >/dev/null 2>&1 || true
    sleep 0.3
fi
if pgrep -x gmak8 >/dev/null 2>&1 || pgrep -x gmak8-core >/dev/null 2>&1; then
    echo "gmak8 is still running. Quit it, then double-click again." >&2
    exit 1
fi
launchctl bootout "gui/$(id -u)/dev.gmak8.core" >/dev/null 2>&1 || true

rm -rf "${DEST}"
ditto "${APP}" "${DEST}"
echo "installed ${DEST}"
open "${DEST}"

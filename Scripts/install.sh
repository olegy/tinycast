#!/bin/bash
# Build Release and replace /Applications/Tinycast.app (com.olegy.tinycast), then launch it.
# Usage: install.sh [--no-launch]

set -euo pipefail
# shellcheck source=Scripts/lite-build.sh
. "$(dirname "$0")/lite-build.sh"

LAUNCH=true
for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=false ;;
        *) lite_fail "unknown argument: $arg" ;;
    esac
done

lite_build
DEST=/Applications/Tinycast.app
if pgrep -qf "$DEST/Contents/MacOS/"; then
    osascript -e "tell application id \"$LITE_BUNDLE_ID\" to quit" || true
    for _ in $(seq 20); do pgrep -qf "$DEST/Contents/MacOS/" || break; sleep 0.5; done
fi
rm -rf "$DEST"
ditto "$LITE_APP" "$DEST"
echo "Installed Tinycast $(lite_version) to $DEST."
[ "$LAUNCH" = true ] && open "$DEST"
exit 0

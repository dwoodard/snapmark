#!/bin/bash
# Builds a drag-to-Applications disk image from a built app.
#   scripts/make-dmg.sh build/Snapmark.app dist/snapmark-0.1.1-macos-universal.dmg
# The window background comes from packaging/dmg/background.tiff (regenerate with make-background.sh).
# Styling the Finder window is best effort: if it fails the DMG still works, just unstyled.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: make-dmg.sh <Snapmark.app> <out.dmg>}"
OUT="${2:?usage: make-dmg.sh <Snapmark.app> <out.dmg>}"
VOL="Snapmark"

STAGE="$(mktemp -d)"
RW="$STAGE/rw.dmg"
DEV=""
cleanup() {
    [[ -n "$DEV" ]] && hdiutil detach "$DEV" -quiet -force 2>/dev/null || true
    rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$STAGE/src/.background"
cp -R "$APP" "$STAGE/src/Snapmark.app"
ln -s /Applications "$STAGE/src/Applications"
cp packaging/dmg/background.tiff "$STAGE/src/.background/background.tiff"

# A volume with this name already mounted would make Finder address the wrong disk.
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true

hdiutil create -srcfolder "$STAGE/src" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/^\/dev\// {print $1; exit}')"

# Icon positions match the arrow in the background (window 560x340, icons at x=150 and x=410).
perl -e 'alarm 90; exec @ARGV' osascript <<APPLESCRIPT || echo "warning: could not style the DMG window; continuing unstyled" >&2
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 760, 460}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Snapmark.app" of container window to {150, 170}
        set position of item "Applications" of container window to {410, 170}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
for _ in 1 2 3 4 5; do
    hdiutil detach "$DEV" -quiet 2>/dev/null && { DEV=""; break; }
    sleep 2
done
[[ -z "$DEV" ]] || { echo "Could not unmount the temporary image" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

# Sign the image with the same identity as the app.
if [[ -z "${SIGN_ID:-}" ]] && security find-identity -p codesigning | grep -q "Snapmark Local Signing"; then
    SIGN_ID="Snapmark Local Signing"
fi
codesign --force --sign "${SIGN_ID:--}" "$OUT"
echo "Built $OUT"

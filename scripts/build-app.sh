#!/bin/bash
# Builds build/Snapmark.app.
#   --install     copy it to /Applications
#   --universal   arm64 + x86_64 (releases use this; dev builds are host-only and faster)
# The version comes from the VERSION file. SNAPMARK_VERSION overrides it for test builds.
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
ARCHS=()
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

VERSION="${SNAPMARK_VERSION:-$(cat VERSION)}"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Snapmark"

APP="build/Snapmark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snapmark"
cp packaging/icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp packaging/menubar/MenuBarIdle.png packaging/menubar/MenuBarRecording.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snapmark</string>
    <key>CFBundleDisplayName</key><string>Snapmark</string>
    <key>CFBundleIdentifier</key><string>com.dustinwoodard.snapmark</string>
    <key>CFBundleExecutable</key><string>Snapmark</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>SnapmarkBuildCommit</key><string>${COMMIT}</string>
    <key>LSMinimumSystemVersion</key><string>15.2</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Snapmark records your microphone into screen recordings when you turn Mic on.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature unless SIGN_ID names a real identity, or the local "Snapmark Local Signing" certificate exists.
# A stable identity keeps privacy permissions across rebuilds and across versions.
if [[ -z "${SIGN_ID:-}" ]] && security find-identity -p codesigning | grep -q "Snapmark Local Signing"; then
    SIGN_ID="Snapmark Local Signing"
fi
if [[ -z "${SIGN_ID:-}" ]]; then
    echo "::warning::No signing identity found. Using an ad-hoc signature: macOS will ask for permissions again after every update."
fi
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP ($VERSION, $COMMIT)"

if [[ "$INSTALL" == 1 ]]; then
    mkdir -p /Applications
    rm -rf /Applications/Snapmark.app
    cp -R "$APP" /Applications/Snapmark.app
    echo "Installed /Applications/Snapmark.app"
fi

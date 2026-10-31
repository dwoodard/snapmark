#!/bin/bash
# Builds Snapmark.app. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Snapmark"

APP="build/Snapmark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snapmark"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snapmark</string>
    <key>CFBundleDisplayName</key><string>Snapmark</string>
    <key>CFBundleIdentifier</key><string>com.dustinwoodard.snapmark</string>
    <key>CFBundleExecutable</key><string>Snapmark</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.2</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature unless SIGN_ID names a real identity (a stable identity keeps privacy permissions across rebuilds).
if [[ -z "${SIGN_ID:-}" ]] && security find-identity -p codesigning | grep -q "Snapmark Local Signing"; then SIGN_ID="Snapmark Local Signing"; fi
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p /Applications
    rm -rf /Applications/Snapmark.app
    cp -R "$APP" /Applications/Snapmark.app
    echo "Installed /Applications/Snapmark.app"
fi

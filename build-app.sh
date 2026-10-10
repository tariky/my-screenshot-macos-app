#!/usr/bin/env bash
# Builds Screenshot.app (release) in the repo root and signs it.
# Usage: ./build-app.sh [--install]   (--install copies it to /Applications and relaunches it)
set -euo pipefail

INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

cd "$(dirname "$0")"

SCRATCH=.build-app
APP=Screenshot.app

swift build -c release --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Screenshot" "$APP/Contents/MacOS/Screenshot"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Screenshot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>ba.tarik.screenshot</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Screenshot</string>
    <key>CFBundleDisplayName</key>
    <string>Screenshot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# A stable identity keeps the Screen Recording grant across rebuilds; ad-hoc signatures
# change with every build, so macOS treats each build as a new app.
SIGN_ID="${SIGN_ID:-Screenshot Local Signing}"
if security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
    codesign --force --deep --sign "$SIGN_ID" "$APP"
else
    echo "warning: no \"$SIGN_ID\" identity (run scripts/make-signing-cert.sh); signing ad-hoc" >&2
    codesign --force --deep --sign - "$APP"
fi
echo "Built $(pwd)/$APP"

if $INSTALL; then
    pkill -f "/Applications/$APP/Contents/MacOS/" || true
    rm -rf "/Applications/$APP"
    ditto "$APP" "/Applications/$APP"
    open "/Applications/$APP"
    echo "Installed /Applications/$APP"
fi

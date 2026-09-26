#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT="BTTLite"
APP_NAME="BTT Lite"
BUNDLE_ID="com.landco.bttlite"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
BT_HELPER_APP="$APP/Contents/Helpers/BTTLiteBluetoothHelper.app"
mkdir -p "$BT_HELPER_APP/Contents/MacOS"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp "$BIN_DIR/BTTLiteBluetoothHelper" "$BT_HELPER_APP/Contents/MacOS/BTTLiteBluetoothHelper"
cp "$BIN_DIR/BTTLiteJavaScriptHelper" "$APP/Contents/Helpers/BTTLiteJavaScriptHelper"

cat > "$BT_HELPER_APP/Contents/Info.plist" <<'BTPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>BTT Lite</string>
    <key>CFBundleExecutable</key><string>BTTLiteBluetoothHelper</string>
    <key>CFBundleIdentifier</key><string>com.landco.bttlite.bluetooth-helper</string>
    <key>CFBundleName</key><string>BTT Lite Bluetooth Helper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key><string>BTT Lite uses Bluetooth only when you run a configured connect, disconnect, or toggle action for a paired device.</string>
</dict>
</plist>
BTPLIST

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$PRODUCT</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>BTT Lite uses automation only for actions explicitly configured by the user.</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>BTT Lite uses Bluetooth only when you run a configured connect, disconnect, or toggle action for a paired device.</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$BT_HELPER_APP"
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/BTT-Lite-arm64.zip"

echo "Built: $DIST/BTT-Lite-arm64.zip"

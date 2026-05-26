#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/mac-activity-menubar"
BUILD_DIR="$APP_DIR/build"
OUTPUT_APP="$APP_DIR/dist/Mac Activity Menu Bar.app"
EXECUTABLE_NAME="MacActivityMenuBar"

mkdir -p "$BUILD_DIR"

echo "Building Cocoa menu bar app..."
clang \
  -fobjc-arc \
  -framework Cocoa \
  -mmacosx-version-min=13.0 \
  "$APP_DIR/main.m" \
  -o "$BUILD_DIR/$EXECUTABLE_NAME"

mkdir -p "$OUTPUT_APP/Contents/MacOS" "$OUTPUT_APP/Contents/Resources"

cat > "$OUTPUT_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Activity Menu Bar</string>
    <key>CFBundleExecutable</key>
    <string>MacActivityMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>io.yurikko.mac-activity-menubar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mac Activity Menu Bar</string>
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
</dict>
</plist>
PLIST

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$OUTPUT_APP/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$OUTPUT_APP/Contents/MacOS/$EXECUTABLE_NAME"

echo "App bundle created at:"
echo "$OUTPUT_APP"

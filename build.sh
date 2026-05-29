#!/bin/bash
# Builds JiggleBar.app — a menu-bar anti-idle tool.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="JiggleBar"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "→ Cleaning…"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "→ Compiling (release, arm64)…"
swiftc -O \
  -framework Cocoa -framework CoreGraphics -framework IOKit -framework ServiceManagement \
  -o "$MACOS_DIR/$APP_NAME" \
  Sources/main.swift

echo "→ Writing Info.plist…"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>com.cankilic.jigglebar</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>JiggleBar</string>
</dict>
</plist>
PLIST

echo "→ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Built: $APP"
echo ""
echo "Çalıştırmak için:  open \"$PWD/$APP\""
echo "Applications'a kopyalamak için:  cp -R \"$APP\" /Applications/"

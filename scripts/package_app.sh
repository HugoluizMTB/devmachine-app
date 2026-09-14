#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DevmachineApp.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build -c release
cp .build/release/DevmachineApp "$APP/Contents/MacOS/DevmachineApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp wallpaper.jpg "$APP/Contents/Resources/wallpaper.jpg"
cp Resources/wallpapers.json "$APP/Contents/Resources/wallpapers.json"

# icon: PNGs -> iconset -> icns
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$ICONSET"
# rename to the names iconutil expects
mv "$ICONSET/icon_16.png"   "$ICONSET/icon_16x16.png"
mv "$ICONSET/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_16x16@2x.png" "$ICONSET/icon_32x32.png"
mv "$ICONSET/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
mv "$ICONSET/icon_128.png"  "$ICONSET/icon_128x128.png"
mv "$ICONSET/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_128x128@2x.png" "$ICONSET/icon_256x256.png"
mv "$ICONSET/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_256x256@2x.png" "$ICONSET/icon_512x512.png"
mv "$ICONSET/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

chmod 755 "$APP/Contents/MacOS/DevmachineApp"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $APP"

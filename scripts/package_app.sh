#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DevmachineApp.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build -c release
cp .build/release/DevmachineApp "$APP/Contents/MacOS/DevmachineApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${DEVMACHINE_APP_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $DEVMACHINE_APP_VERSION" \
    "$APP/Contents/Info.plist"
fi
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

# zmx keeps local sessions alive after the app quits. It is embedded rather
# than required from the machine, so nothing has to be installed first.
./scripts/fetch_zmx.sh
mkdir -p "$APP/Contents/Resources/zmx"
cp vendor/zmx/zmx "$APP/Contents/Resources/zmx/zmx"
chmod 755 "$APP/Contents/Resources/zmx/zmx"

# Inside out: signing the bundle seals what is already inside it, so a nested
# binary signed afterwards breaks the seal. `-` is an ad-hoc signature, which
# is all a local install needs; notarizing needs a Developer ID identity here.
IDENTITY="${DEVMACHINE_CODESIGN_IDENTITY:--}"
ENTITLEMENTS="Resources/Devmachine.entitlements"

SIGN=(codesign --force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
  SIGN+=(--options runtime --timestamp --entitlements "$ENTITLEMENTS")
fi

# Every nested executable/dylib/framework first, then the app that seals them.
# zmx is the only one this bundle carries today; a future embedded binary
# joins this list before the final "${SIGN[@]}" "$APP" line.
"${SIGN[@]}" "$APP/Contents/Resources/zmx/zmx"
"${SIGN[@]}" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built: $APP"

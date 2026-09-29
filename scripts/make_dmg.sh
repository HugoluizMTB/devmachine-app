#!/bin/bash
# Builds Devmachine.app (scripts/package_app.sh) and wraps it in a .dmg with
# an /Applications shortcut, using only hdiutil — no third-party tooling.
#
# Env:
#   DEVMACHINE_CODESIGN_IDENTITY  passed straight through to package_app.sh;
#                                 unset/"-" means ad hoc, same as there.
#   DEVMACHINE_APP_VERSION        passed straight through to package_app.sh;
#                                 also names the dmg. Defaults to whatever is
#                                 already in Resources/Info.plist. The release
#                                 workflow sets it from the pushed git tag.
#   SKIP_NOTARIZE=1               build and sign the dmg but skip
#                                 scripts/notarize.sh — for a local dry run
#                                 without Apple API credentials.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/package_app.sh

APP="build/DevmachineApp.app"
VERSION="${DEVMACHINE_APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="build/Devmachine-$VERSION.dmg"

STAGING="build/dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Devmachine.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname Devmachine -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

IDENTITY="${DEVMACHINE_CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
  echo "SKIP_NOTARIZE=1: built $DMG without notarizing"
else
  ./scripts/notarize.sh "$DMG"
fi

echo "Built: $DMG"

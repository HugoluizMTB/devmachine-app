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
IDENTITY="${DEVMACHINE_CODESIGN_IDENTITY:--}"
NOTARIZE=0
if [ "$IDENTITY" != "-" ] && [ "${SKIP_NOTARIZE:-}" != "1" ]; then
  NOTARIZE=1
fi

# The app is notarized and stapled on its own before it goes into the dmg, so
# it still opens offline once someone has copied it out of the disk image.
if [ "$NOTARIZE" = "1" ]; then
  ./scripts/notarize.sh "$APP"
fi

VERSION="${DEVMACHINE_APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="build/Devmachine-$VERSION.dmg"

STAGING="build/dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Devmachine.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname Devmachine -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

if [ "$NOTARIZE" = "1" ]; then
  ./scripts/notarize.sh "$DMG"
  # Gatekeeper only accepts a Developer ID build once it is notarized, so it
  # is asked here, at the end, and not right after signing.
  spctl -a -vvv -t exec "$APP"
  spctl -a -vvv -t open --context context:primary-signature "$DMG"
else
  echo "Not notarized (ad hoc or SKIP_NOTARIZE=1): built $DMG"
fi

echo "Built: $DMG"

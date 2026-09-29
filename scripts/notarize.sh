#!/bin/bash
# Submits a signed app or dmg to Apple notarization and staples the ticket.
# Usage: scripts/notarize.sh <path-to-.app-or-.dmg>
#
# Needs, all from the environment:
#   APPLE_API_KEY_PATH   path to the .p8 App Store Connect API key file
#   APPLE_API_KEY_ID     that key's Key ID
#   APPLE_API_ISSUER_ID  that key's Issuer ID
#
# A .app is zipped first (notarytool only accepts a zip, dmg or pkg); a .dmg
# goes straight in. The staple then goes on the original path in both cases —
# stapling a copy inside a temporary zip would staple nothing the owner ships.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
  echo "usage: scripts/notarize.sh <path-to-.app-or-.dmg>" >&2
  exit 1
fi

missing=()
for var in APPLE_API_KEY_PATH APPLE_API_KEY_ID APPLE_API_ISSUER_ID; do
  if [ -z "${!var:-}" ]; then
    missing+=("$var")
  fi
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "notarize.sh: missing required environment variable(s): ${missing[*]}" >&2
  exit 1
fi
if [ ! -f "$APPLE_API_KEY_PATH" ]; then
  echo "notarize.sh: APPLE_API_KEY_PATH does not point at a file: $APPLE_API_KEY_PATH" >&2
  exit 1
fi

SUBMIT_PATH="$TARGET"
case "$TARGET" in
  *.app)
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    SUBMIT_PATH="$WORK/$(basename "$TARGET" .app).zip"
    ditto -c -k --keepParent "$TARGET" "$SUBMIT_PATH"
    ;;
  *.dmg) ;;
  *)
    echo "notarize.sh: don't know how to submit $TARGET (expected .app or .dmg)" >&2
    exit 1
    ;;
esac

xcrun notarytool submit "$SUBMIT_PATH" \
  --key "$APPLE_API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "Notarized and stapled: $TARGET"

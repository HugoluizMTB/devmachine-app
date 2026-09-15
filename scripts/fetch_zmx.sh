#!/bin/bash
# Downloads the zmx release the app embeds and builds a universal binary from
# the two per-architecture ones upstream ships. The version is pinned on
# purpose: zmx has a frozen IPC wire shape, and a version bump kills every
# running local session, so it is a deliberate change, never a refresh.
set -euo pipefail
cd "$(dirname "$0")/.."

ZMX_VERSION="0.8.1"
SHA_AARCH64="1d86b1c9fba47fa707a6f0e976b20510b07c1c26d0ed010b9414b2a2c5e6beef"
SHA_X86_64="3208578ad91d8a62077772dc8a1369a92033d9e84169bac673ef8542b6ff9707"

OUT="vendor/zmx"
STAMP="$OUT/.version"

if [ -f "$OUT/zmx" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$ZMX_VERSION" ]; then
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
  local arch="$1"
  local want="$2"
  local file="zmx-$ZMX_VERSION-macos-$arch.tar.gz"
  curl -fsSL -o "$WORK/$file" \
    "https://github.com/neurosnap/zmx/releases/download/v$ZMX_VERSION/$file"
  local got=""
  got="$(shasum -a 256 "$WORK/$file" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "FAILED: $file checksum $got, expected $want" >&2
    exit 1
  fi
  mkdir -p "$WORK/$arch"
  tar -xzf "$WORK/$file" -C "$WORK/$arch"
}

fetch aarch64 "$SHA_AARCH64"
fetch x86_64 "$SHA_X86_64"

mkdir -p "$OUT"
lipo -create "$WORK/aarch64/zmx" "$WORK/x86_64/zmx" -output "$OUT/zmx"
chmod 755 "$OUT/zmx"
echo "$ZMX_VERSION" > "$STAMP"
echo "zmx $ZMX_VERSION: $OUT/zmx ($(lipo -archs "$OUT/zmx"))"

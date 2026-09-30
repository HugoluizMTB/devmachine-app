#!/bin/bash
# Builds the mosh-client the app embeds, from source, as one universal
# (arm64 + x86_64) binary with protobuf linked in statically. What is left
# dynamic is part of macOS itself (libc++, libz, libncurses, CommonCrypto),
# so the binary runs on a Mac with nothing installed and signs like any other
# nested executable. Versions and checksums are pinned; a bump is a
# deliberate change, never a refresh.
set -euo pipefail
cd "$(dirname "$0")/.."

MOSH_VERSION="1.4.0"
MOSH_SHA256="872e4b134e5df29c8933dff12350785054d2fd2839b5ae6b5587b14db1465ddd"
# 3.21.x is the last protobuf line without an abseil dependency, and the one
# mosh 1.4.0 was released against.
PROTOBUF_VERSION="3.21.12"
PROTOBUF_TAG="v21.12"
PROTOBUF_SHA256="4eab9b524aa5913c6fffb20b2a8abf5ef7f95a80bc0701f3a6dbb4c607f73460"
DEPLOYMENT_TARGET="14.0"
ARCHS="arm64;x86_64"

OUT="vendor/mosh"
STAMP="$OUT/.version"
WANT="mosh-$MOSH_VERSION protobuf-$PROTOBUF_VERSION macos-$DEPLOYMENT_TARGET"

if [ -x "$OUT/mosh-client" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$WANT" ]; then
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
JOBS="$(sysctl -n hw.ncpu)"

# Build output goes to a log; only a failing step shows the end of it.
logged() {
  local log="$WORK/$1.log"
  shift
  if ! "$@" >"$log" 2>&1; then
    tail -n 40 "$log" >&2
    echo "FAILED: $*" >&2
    exit 1
  fi
}

fetch() {
  local url="$1" want="$2" file
  file="$WORK/$(basename "$url")"
  curl -fsSL -o "$file" "$url"
  local got
  got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "FAILED: $(basename "$url") checksum $got, expected $want" >&2
    exit 1
  fi
  tar -xzf "$file" -C "$WORK"
}

fetch "https://github.com/protocolbuffers/protobuf/releases/download/$PROTOBUF_TAG/protobuf-cpp-$PROTOBUF_VERSION.tar.gz" \
  "$PROTOBUF_SHA256"
fetch "https://github.com/mobile-shell/mosh/releases/download/mosh-$MOSH_VERSION/mosh-$MOSH_VERSION.tar.gz" \
  "$MOSH_SHA256"

export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
PREFIX="$WORK/prefix"

logged protobuf-configure cmake -S "$WORK/protobuf-$PROTOBUF_VERSION" -B "$WORK/protobuf-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -Dprotobuf_BUILD_TESTS=OFF \
  -Dprotobuf_BUILD_SHARED_LIBS=OFF \
  -Dprotobuf_WITH_ZLIB=OFF
logged protobuf-build cmake --build "$WORK/protobuf-build" --parallel "$JOBS"
logged protobuf-install cmake --install "$WORK/protobuf-build"

ARCH_FLAGS=""
for arch in ${ARCHS//;/ }; do ARCH_FLAGS="$ARCH_FLAGS -arch $arch"; done

cd "$WORK/mosh-$MOSH_VERSION"
# mosh's own messages only need the lite runtime (its .proto files say
# LITE_RUNTIME), so the smaller library is the one linked.
logged mosh-configure ./configure \
  --disable-dependency-tracking \
  --disable-server \
  --enable-client \
  --disable-completion \
  --with-crypto-library=apple-common-crypto \
  CC="clang" CXX="clang++" \
  CFLAGS="$ARCH_FLAGS -O2" \
  CXXFLAGS="$ARCH_FLAGS -O2 -std=c++17" \
  LDFLAGS="$ARCH_FLAGS" \
  PROTOC="$PREFIX/bin/protoc" \
  protobuf_CFLAGS="-I$PREFIX/include" \
  protobuf_LIBS="$PREFIX/lib/libprotobuf-lite.a"
logged mosh-build make -j"$JOBS"
cd - >/dev/null

mkdir -p "$OUT"
cp "$WORK/mosh-$MOSH_VERSION/src/frontend/mosh-client" "$OUT/mosh-client"
strip -x "$OUT/mosh-client"
chmod 755 "$OUT/mosh-client"

if otool -L "$OUT/mosh-client" | grep -E '^[[:space:]]' | grep -v -E '^[[:space:]]+/(usr/lib|System/Library)/'; then
  echo "FAILED: mosh-client links a library that is not part of macOS" >&2
  exit 1
fi

echo "$WANT" > "$STAMP"
echo "mosh-client $MOSH_VERSION: $OUT/mosh-client ($(lipo -archs "$OUT/mosh-client"), $(du -h "$OUT/mosh-client" | cut -f1))"

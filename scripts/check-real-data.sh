#!/bin/bash
# Greps the tracked tree for the owner's private pattern list (kept outside the
# repo). Exit 1 on any hit other than the 1Password socket path.
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERNS="${DEVMACHINE_PRIVATE_PATTERNS:-$HOME/.config/devmachine-app/private-patterns}"
if [ ! -s "$PATTERNS" ]; then
  echo "no pattern file at $PATTERNS — nothing checked" >&2
  exit 2
fi

hits=$(git grep -inE -f "$PATTERNS" -- . | grep -v "2BUA8C4S2C.com.1password" || true)
if [ -n "$hits" ]; then
  echo "$hits"
  echo "real data found — fix before pushing" >&2
  exit 1
fi
echo "clean"

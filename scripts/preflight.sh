#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift test
swift build -c release
scripts/check-real-data.sh
echo "preflight passed: safe to tag"

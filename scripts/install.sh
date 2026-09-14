#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/Devmachine.app"

./scripts/package_app.sh
pkill -x DevmachineApp || true
sleep 1
rm -rf "$APP"
ditto build/DevmachineApp.app "$APP"
open "$APP"
echo "Installed: $APP"

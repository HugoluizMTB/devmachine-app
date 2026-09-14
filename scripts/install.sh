#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/Devmachine.app"

./scripts/package_app.sh

# `pkill` is not reliable from a sandboxed shell: it can return success while the
# app keeps running, and `open` then just activates the stale copy. Quitting
# through AppleScript and waiting for the pid to go is what actually works.
osascript -e 'tell application "Devmachine" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  pgrep -x DevmachineApp >/dev/null || break
  sleep 0.5
done
pgrep -x DevmachineApp >/dev/null && pkill -9 -x DevmachineApp || true
sleep 1

rm -rf "$APP"
ditto build/DevmachineApp.app "$APP"
open "$APP"
sleep 3

PID=$(pgrep -x DevmachineApp || true)
if [ -z "$PID" ]; then
  echo "FAILED: app did not start" >&2
  exit 1
fi
echo "Installed: $APP (pid $PID, started $(ps -o lstart= -p "$PID" | xargs))"

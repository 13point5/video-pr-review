#!/usr/bin/env bash

set -euo pipefail

CDP_PORT="${CDP_PORT:-9222}"
CHROME_PROFILE_DIR="${CHROME_PROFILE_DIR:-$HOME/Library/Application Support/Google/Chrome-RemoteDebug-RLX}"
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: this helper currently targets macOS."
  exit 1
fi

if [[ ! -x "${CHROME_BIN}" ]]; then
  echo "Error: Chrome binary not found at ${CHROME_BIN}"
  exit 1
fi

mkdir -p "${CHROME_PROFILE_DIR}"

echo "Closing existing Chrome processes..."
osascript -e 'tell application "Google Chrome" to quit' >/dev/null 2>&1 || true
sleep 2
pkill -f "Google Chrome" >/dev/null 2>&1 || true
sleep 1

echo "Starting Chrome with CDP on port ${CDP_PORT}..."
"${CHROME_BIN}" --remote-debugging-port="${CDP_PORT}" --user-data-dir="${CHROME_PROFILE_DIR}" >/tmp/rlx-chrome-cdp.log 2>&1 &

echo "Waiting for CDP endpoint..."
for _ in $(seq 1 20); do
  if curl -sS "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    WS_URL="$(curl -sS "http://localhost:${CDP_PORT}/json/version" | python -c 'import json,sys; print(json.load(sys.stdin).get("webSocketDebuggerUrl",""))')"
    echo "Ready: ${WS_URL}"
    echo "Profile dir: ${CHROME_PROFILE_DIR}"
    exit 0
  fi
  sleep 1
done

echo "Error: CDP endpoint did not come up. Check /tmp/rlx-chrome-cdp.log"
exit 1

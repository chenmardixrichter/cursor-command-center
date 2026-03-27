#!/usr/bin/env bash
# Canonical flow after ANY command-center/ change (agents must run this script end-to-end):
# 1) Quit every running Command Center process
# 2) Delete Command Center.app in /Applications and every copy under this repo’s .build
# 3) swift build -c release, assemble bundle, install to /Applications
# 4) open the installed app
#
# Usage: bash /Users/chenma/Personal/command-center/reinstall-and-open.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/Command Center.app"
APP_NAME="Command Center"

quit_everything() {
  echo "==> Quitting all ${APP_NAME} processes…"
  osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
  sleep 0.9

  killall -9 CommandCenter 2>/dev/null || true
  killall -9 "${APP_NAME}" 2>/dev/null || true
  pkill -9 -f "Command Center.app/Contents/MacOS/CommandCenter" 2>/dev/null || true

  local n=0
  while pgrep -f "Command Center.app/Contents/MacOS/CommandCenter" >/dev/null 2>&1 && [[ $n -lt 20 ]]; do
    sleep 0.15
    n=$((n + 1))
  done
  sleep 0.25
}

remove_all_app_bundles() {
  echo "==> Deleting all Command Center.app bundles (Applications + .build)…"

  _rm_app() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    echo "    removing: $path"
    if rm -rf "$path" 2>/dev/null; then
      return 0
    fi
    echo "    (sudo) removing: $path"
    sudo rm -rf "$path"
  }

  _rm_app "$DEST"

  if [[ -d "${ROOT}/.build" ]]; then
    while IFS= read -r bundle; do
      [[ -n "$bundle" ]] && _rm_app "$bundle"
    done < <(find "${ROOT}/.build" -name "Command Center.app" -type d 2>/dev/null)
  fi
}

cd "$ROOT" || exit 1
quit_everything
remove_all_app_bundles

echo "==> Building, installing to /Applications, opening…"
exec bash "${ROOT}/install-to-applications.sh" --open

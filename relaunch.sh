#!/usr/bin/env bash
# Rebuild and relaunch Command Center (kills prior instances). Safe to run after every code change.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 1

(killall -9 CommandCenter 2>/dev/null || true)
(pkill -9 -f "${ROOT}/.build/.*/debug/CommandCenter" 2>/dev/null || true)
(pkill -9 -f "swift run CommandCenter" 2>/dev/null || true)
sleep 0.25

swift build || exit 1

BIN=""
for cand in "${ROOT}/.build/arm64-apple-macosx/debug/CommandCenter" "${ROOT}/.build/x86_64-apple-macosx/debug/CommandCenter"; do
  if [[ -x "$cand" ]]; then
    BIN="$cand"
    break
  fi
done
if [[ -z "$BIN" ]]; then
  BIN="$(find "${ROOT}/.build" -path '*/debug/CommandCenter' -type f -perm +111 2>/dev/null | head -1)"
fi
if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  echo "relaunch.sh: could not find built CommandCenter binary under .build" >&2
  exit 1
fi

exec "$BIN"

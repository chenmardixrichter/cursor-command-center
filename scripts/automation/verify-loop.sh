#!/usr/bin/env bash
# Build → run headless CommandCenterAutomation in a loop until AUTOMATION_OK.
#
# Usage:
#   bash scripts/automation/verify-loop.sh
#   COMMAND_CENTER_VERIFY_MAX=20 bash scripts/automation/verify-loop.sh   # stop after 20 failed attempts
#
# Logs: .automation/ (gitignored recommended). This script does not edit source code; pair it with an
# agent that reads the latest log and fixes code between iterations if you want “until it works.”
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

LOG_DIR="${ROOT}/.automation"
mkdir -p "$LOG_DIR"
MAX="${COMMAND_CENTER_VERIFY_MAX:-0}"

echo "Log directory: $LOG_DIR"
echo "Max iterations: ${MAX:-unlimited}"

iter=0
while true; do
  iter=$((iter + 1))
  ts="$(date +%Y%m%d-%H%M%S)"
  log="${LOG_DIR}/verify-${iter}-${ts}.log"

  {
    echo "========== iteration ${iter} at ${ts} =========="
    echo "==> swift build -c release"
    swift build -c release
    echo
    echo "==> swift run -c release CommandCenterAutomation"
    swift run -c release CommandCenterAutomation
  } 2>&1 | tee "$log"

  if grep -q "AUTOMATION_OK" "$log" 2>/dev/null; then
    echo ""
    echo "VERIFY_OK after ${iter} iteration(s). Log: $log"
    exit 0
  fi

  echo "" | tee -a "${LOG_DIR}/issues.log"
  echo "VERIFY_FAIL iteration ${iter} — see $log" | tee -a "${LOG_DIR}/issues.log"

  if [[ "$MAX" -gt 0 && "$iter" -ge "$MAX" ]]; then
    echo "Stopped: reached COMMAND_CENTER_VERIFY_MAX=$MAX"
    exit 1
  fi

  sleep 2
done

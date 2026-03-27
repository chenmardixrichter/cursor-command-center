#!/usr/bin/env bash
# Full automated verification for Command Center (no manual steps).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
echo "==> $(date -u +%Y-%m-%dT%H:%M:%SZ) Command Center full verification"
echo "==> swift build -c release"
swift build -c release
echo "==> swift run -c release CommandCenterAutomation"
swift run -c release CommandCenterAutomation

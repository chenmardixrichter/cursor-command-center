#!/usr/bin/env bash
# Build release, assemble Command Center.app, and write a .zip next to the repo (for GitHub Releases).
# Usage: from repo root: bash scripts/package-release-zip.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/macos/Info.plist" 2>/dev/null || echo "0")"
OUT="${ROOT}/Command-Center-${VER}.zip"

bash "${ROOT}/install-to-applications.sh"

echo "==> Zipping for release upload…"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "/Applications/Command Center.app" "$OUT"
echo "==> Wrote: $OUT"
echo "    Upload this file to GitHub Releases as the meeting build."

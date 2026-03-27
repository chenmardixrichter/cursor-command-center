#!/usr/bin/env bash
# One-line installer for Command Center.
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/chenmardixrichter/cursor-command-center/main/install.sh)"
set -euo pipefail

APP_NAME="Command Center"
DEST="/Applications/${APP_NAME}.app"
REPO="chenmardixrichter/cursor-command-center"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "==> Downloading Command Center..."
DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"browser_download_url"' \
  | grep '\.zip"' \
  | head -1 \
  | sed 's/.*"browser_download_url": *"//;s/"//')

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Error: Could not find download URL. Check https://github.com/${REPO}/releases" >&2
  exit 1
fi

curl -sL "$DOWNLOAD_URL" -o "${TMP_DIR}/CommandCenter.zip"

echo "==> Installing to /Applications..."
unzip -qo "${TMP_DIR}/CommandCenter.zip" -d "$TMP_DIR"

if [[ -d "$DEST" ]]; then
  rm -rf "$DEST" 2>/dev/null || sudo rm -rf "$DEST"
fi

cp -R "${TMP_DIR}/${APP_NAME}.app" "/Applications/" 2>/dev/null \
  || sudo cp -R "${TMP_DIR}/${APP_NAME}.app" "/Applications/"

# Remove quarantine so macOS doesn't block the unsigned app
xattr -rd com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Installed: ${DEST}"
echo "==> Opening Command Center..."
open "$DEST"
echo ""
echo "Done! Command Center will set up Cursor integration automatically on first launch."

#!/usr/bin/env bash
# Build release and install "Command Center.app" to /Applications (needs write access; may prompt for admin).
# Optional: pass --open to launch the app after a successful install.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 1

OPEN_AFTER=0
for arg in "$@"; do
  [[ "$arg" == "--open" ]] && OPEN_AFTER=1
done

APP_BUNDLE_NAME="Command Center.app"
DEST="/Applications/${APP_BUNDLE_NAME}"
STAGING="${ROOT}/.build/${APP_BUNDLE_NAME}"

echo "Building release…"
swift build -c release || exit 1

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  TRIPLE="arm64-apple-macosx"
else
  TRIPLE="x86_64-apple-macosx"
fi

BIN_DIR="${ROOT}/.build/${TRIPLE}/release"
EXE="${BIN_DIR}/CommandCenter"
RES_BUNDLE="${BIN_DIR}/CommandCenter_CommandCenter.bundle"

if [[ ! -x "$EXE" ]]; then
  echo "install: missing executable: $EXE" >&2
  exit 1
fi

echo "Assembling ${APP_BUNDLE_NAME}…"
rm -rf "$STAGING"
mkdir -p "${STAGING}/Contents/MacOS"
cp "$EXE" "${STAGING}/Contents/MacOS/CommandCenter"
chmod +x "${STAGING}/Contents/MacOS/CommandCenter"
if [[ -d "$RES_BUNDLE" ]]; then
  cp -R "$RES_BUNDLE" "${STAGING}/Contents/MacOS/"
fi
cp "${ROOT}/macos/Info.plist" "${STAGING}/Contents/Info.plist"
mkdir -p "${STAGING}/Contents/Resources"
if [[ -f "${ROOT}/macos/AppIcon.icns" ]]; then
  cp "${ROOT}/macos/AppIcon.icns" "${STAGING}/Contents/Resources/AppIcon.icns"
fi

echo "Installing to ${DEST}…"
if rm -rf "$DEST" 2>/dev/null && cp -R "$STAGING" "/Applications/"; then
  rm -rf "$STAGING"
  echo "Installed: ${DEST}"
  echo "You can launch it from Applications or Spotlight (\"Command Center\")."
  [[ "$OPEN_AFTER" -eq 1 ]] && open "$DEST"
  exit 0
fi

echo "Could not write to /Applications without elevated permissions. Trying with sudo…" >&2
sudo rm -rf "$DEST"
sudo cp -R "$STAGING" "/Applications/"
rm -rf "$STAGING"
echo "Installed: ${DEST}"
[[ "$OPEN_AFTER" -eq 1 ]] && open "$DEST"
exit 0

#!/usr/bin/env bash
# Uninstall Command Center — removes app, Cursor rule, signal files, and registry.
set -uo pipefail

echo "==> Quitting Command Center..."
osascript -e 'quit app "Command Center"' 2>/dev/null || true
sleep 1
killall CommandCenter 2>/dev/null || true

echo "==> Removing app..."
rm -rf "/Applications/Command Center.app" 2>/dev/null || sudo rm -rf "/Applications/Command Center.app"

echo "==> Removing Cursor rule..."
rm -f ~/.cursor/rules/command-center-signal.mdc

echo "==> Removing helper script..."
rm -f ~/.cursor/bin/cc-signal

echo "==> Removing signal inbox..."
rm -rf ~/.cursor/command-center-agents

echo "==> Removing registry..."
rm -f ~/.cursor/command-center-registry.json

echo ""
echo "Command Center has been fully removed."
echo "Your Cursor projects and settings are untouched."

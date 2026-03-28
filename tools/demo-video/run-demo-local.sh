#!/usr/bin/env bash
# Use your Mac login HOME so demo JSON lands where Command Center reads it.
set -euo pipefail
cd "$(dirname "$0")"
echo "HOME=$HOME"
exec python3 demo-simulate.py "$@"

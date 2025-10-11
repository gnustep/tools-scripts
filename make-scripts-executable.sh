#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
echo "Making os-scripts wrappers executable..."
find "$ROOT/os-scripts" -type f -exec chmod +x {} + || true
echo "Done."

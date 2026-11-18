#!/usr/bin/env bash
# Rebuild and reinstall the MacGlass Downloads stack into ~/.local
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${HOME}/.local"
cmake --build build
cmake --install build
pkill -x macglass-stack 2>/dev/null || true   # next dock click starts the new build
echo "macglass-stack rebuilt and installed."

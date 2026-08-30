#!/usr/bin/env bash
set -euo pipefail

# Detect install prefix
if [ "$(id -u)" -eq 0 ]; then
    PREFIX="${PREFIX:-/usr/local}"
    SYSTEMD_USER_DIR="/usr/local/lib/systemd/user"
else
    PREFIX="${PREFIX:-$HOME/.local}"
    SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
fi

echo "Uninstalling Wick from ${PREFIX}..."

rm -f "$PREFIX/bin/wick"
rm -f "$PREFIX/share/applications/wick.desktop"
rm -f "$PREFIX/share/icons/hicolor/scalable/apps/wick.svg"
rm -f "$SYSTEMD_USER_DIR/wick.service"
if [ -n "${HOME:-}" ]; then
    rm -rf "$HOME/.config/omarchy/plugins/wick.progress"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
fi

echo "✓ Wick has been uninstalled."

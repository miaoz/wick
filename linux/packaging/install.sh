#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect install prefix
if [ "$(id -u)" -eq 0 ]; then
    PREFIX="${PREFIX:-/usr/local}"
    SYSTEMD_USER_DIR="/usr/local/lib/systemd/user"
else
    PREFIX="${PREFIX:-$HOME/.local}"
    SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
fi

BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"

echo "Installing Wick to ${PREFIX}..."

mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR" "$SYSTEMD_USER_DIR"

# 1. Install binary
if [ -f "$SCRIPT_DIR/bin/wick" ]; then
    install -Dm755 "$SCRIPT_DIR/bin/wick" "$BIN_DIR/wick"
elif [ -f "$SCRIPT_DIR/build/wick" ]; then
    install -Dm755 "$SCRIPT_DIR/build/wick" "$BIN_DIR/wick"
elif [ -f "$SCRIPT_DIR/wick" ]; then
    install -Dm755 "$SCRIPT_DIR/wick" "$BIN_DIR/wick"
else
    echo "Error: wick binary not found in $SCRIPT_DIR" >&2
    exit 1
fi
echo "✓ Installed $BIN_DIR/wick"

# 2. Install desktop entry
DESKTOP_SRC=""
if [ -f "$SCRIPT_DIR/share/applications/wick.desktop" ]; then
    DESKTOP_SRC="$SCRIPT_DIR/share/applications/wick.desktop"
elif [ -f "$SCRIPT_DIR/resources/wick.desktop" ]; then
    DESKTOP_SRC="$SCRIPT_DIR/resources/wick.desktop"
fi

if [ -n "$DESKTOP_SRC" ]; then
    install -Dm644 "$DESKTOP_SRC" "$APP_DIR/wick.desktop"
    echo "✓ Installed $APP_DIR/wick.desktop"
fi

# 3. Install icon
ICON_SRC=""
if [ -f "$SCRIPT_DIR/share/icons/hicolor/scalable/apps/wick.svg" ]; then
    ICON_SRC="$SCRIPT_DIR/share/icons/hicolor/scalable/apps/wick.svg"
elif [ -f "$SCRIPT_DIR/resources/candle.svg" ]; then
    ICON_SRC="$SCRIPT_DIR/resources/candle.svg"
fi

if [ -n "$ICON_SRC" ]; then
    install -Dm644 "$ICON_SRC" "$ICON_DIR/wick.svg"
    echo "✓ Installed $ICON_DIR/wick.svg"
fi

# 4. Install systemd service
SERVICE_SRC=""
if [ -f "$SCRIPT_DIR/systemd/wick.service" ]; then
    SERVICE_SRC="$SCRIPT_DIR/systemd/wick.service"
elif [ -f "$SCRIPT_DIR/packaging/wick.service" ]; then
    SERVICE_SRC="$SCRIPT_DIR/packaging/wick.service"
fi

if [ -n "$SERVICE_SRC" ]; then
    install -Dm644 "$SERVICE_SRC" "$SYSTEMD_USER_DIR/wick.service"
    echo "✓ Installed $SYSTEMD_USER_DIR/wick.service"
fi

# 5. Install Omarchy plugin if Omarchy is used
OMARCHY_PLUGIN_SRC=""
if [ -d "$SCRIPT_DIR/plugins/omarchy/wick.progress" ]; then
    OMARCHY_PLUGIN_SRC="$SCRIPT_DIR/plugins/omarchy/wick.progress"
elif [ -d "$SCRIPT_DIR/omarchy/wick.progress" ]; then
    OMARCHY_PLUGIN_SRC="$SCRIPT_DIR/omarchy/wick.progress"
fi

if [ -n "$OMARCHY_PLUGIN_SRC" ] && [ -n "${HOME:-}" ]; then
    OMARCHY_PLUGINS_DEST="$HOME/.config/omarchy/plugins/wick.progress"
    mkdir -p "$OMARCHY_PLUGINS_DEST"
    cp -r "$OMARCHY_PLUGIN_SRC/"* "$OMARCHY_PLUGINS_DEST/"
    echo "✓ Installed Omarchy plugin to $OMARCHY_PLUGINS_DEST"
fi

# 6. Update desktop database and MIME handlers
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" 2>/dev/null || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true
fi

if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default wick.desktop x-scheme-handler/db-hm5yscsy9a11g0q 2>/dev/null || true
fi

echo ""
echo "Wick has been successfully installed!"
echo "Run 'wick' or 'wick --journal' to get started."

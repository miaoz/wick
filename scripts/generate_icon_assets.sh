#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
MASTER_PNG="$ASSETS_DIR/AppIcon-master.png"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
ICNS_FILE="$ASSETS_DIR/AppIcon.icns"

mkdir -p "$ASSETS_DIR" "$ICONSET_DIR"

swift "$ROOT_DIR/scripts/generate_icon.swift" "$MASTER_PNG" >/dev/null

make_icon() {
    local size="$1"
    local name="$2"
    sips -s format png -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
cp "$MASTER_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
printf 'Created %s\n' "$ICNS_FILE"

# iOS app icon: full-bleed variant (no macOS margin/squircle mask).
IOS_PNG="$ASSETS_DIR/AppIcon-ios.png"
swift "$ROOT_DIR/scripts/generate_icon.swift" "$IOS_PNG" --ios >/dev/null
cp "$IOS_PNG" "$ROOT_DIR/ios/WickPhone/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
printf 'Created %s\n' "$IOS_PNG"

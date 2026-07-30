#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Wick"
LEGACY_APP_NAME="CandleMenuBar"
BUNDLE_ID="com.miaoz.wick"
MIN_SYSTEM_VERSION="13.0"
# Optional overrides for CI / tagged releases:
#   VERSION=1.4.0 BUILD=42 ./scripts/package_app.sh
VERSION="${VERSION:-1.4.6}"
BUILD="${BUILD:-26}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
LEGACY_APP_DIR="$DIST_DIR/$LEGACY_APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$ROOT_DIR/assets/AppIcon.icns"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARM64_SCRATCH="$ROOT_DIR/.build/arm64"
X86_64_SCRATCH="$ROOT_DIR/.build/x86_64"
UNIVERSAL_DIR="$ROOT_DIR/.build/universal/release"
UNIVERSAL_BIN="$UNIVERSAL_DIR/$APP_NAME"

mkdir -p "$DIST_DIR"
rm -rf "$APP_DIR" "$LEGACY_APP_DIR"
mkdir -p "$UNIVERSAL_DIR"

"$ROOT_DIR/scripts/generate_icon_assets.sh"

build_arch() {
    local arch="$1"
    local scratch="$2"
    local triple="${arch}-apple-macosx${MIN_SYSTEM_VERSION}"

    echo "Building $arch..."
    swift build \
        -c release \
        --product "$APP_NAME" \
        --scratch-path "$scratch" \
        --triple "$triple" \
        --sdk "$SDKROOT"
}

build_arch arm64 "$ARM64_SCRATCH"
build_arch x86_64 "$X86_64_SCRATCH"

lipo -create \
    "$ARM64_SCRATCH/release/$APP_NAME" \
    "$X86_64_SCRATCH/release/$APP_NAME" \
    -output "$UNIVERSAL_BIN"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$UNIVERSAL_BIN" "$MACOS_DIR/$APP_NAME"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$MACOS_DIR/$APP_NAME"

# Localized Info.plist strings (notification usage description).
mkdir -p "$RESOURCES_DIR/en.lproj" "$RESOURCES_DIR/zh-Hans.lproj"
cat > "$RESOURCES_DIR/en.lproj/InfoPlist.strings" <<'STRINGS'
"NSUserNotificationsUsageDescription" = "Wick uses notifications for the daily journal reminder.";
STRINGS
cat > "$RESOURCES_DIR/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
"NSUserNotificationsUsageDescription" = "Wick 使用通知发送每日日记提醒。";
STRINGS

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_SYSTEM_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationsUsageDescription</key>
    <string>Wick uses notifications for the daily journal reminder.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
lipo -info "$MACOS_DIR/$APP_NAME"
printf 'Created %s\n' "$APP_DIR"

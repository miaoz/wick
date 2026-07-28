#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Wick"
LEGACY_APP_NAME="CandleMenuBar"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
# Optional: VERSION=1.2.3 ./scripts/package_zip.sh → Wick-macOS-1.2.3.zip
VERSION="${VERSION:-}"
if [[ -n "$VERSION" ]]; then
    ZIP_FILE="$DIST_DIR/${APP_NAME}-macOS-${VERSION}.zip"
else
    ZIP_FILE="$DIST_DIR/${APP_NAME}-macOS.zip"
fi
LEGACY_ZIP_FILE="$DIST_DIR/${LEGACY_APP_NAME}-macOS.zip"
LEGACY_UNIVERSAL_ZIP_FILE="$DIST_DIR/${LEGACY_APP_NAME}-macOS-universal.zip"

"$ROOT_DIR/scripts/package_app.sh"

rm -f "$ZIP_FILE" "$LEGACY_ZIP_FILE" "$LEGACY_UNIVERSAL_ZIP_FILE"
# Also remove unversioned zip when publishing a versioned build.
if [[ -n "$VERSION" ]]; then
    rm -f "$DIST_DIR/${APP_NAME}-macOS.zip"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

printf 'Created %s\n' "$ZIP_FILE"

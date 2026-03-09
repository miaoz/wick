#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CandleMenuBar"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_FILE="$DIST_DIR/${APP_NAME}-macOS.zip"
LEGACY_ZIP_FILE="$DIST_DIR/${APP_NAME}-macOS-universal.zip"

"$ROOT_DIR/scripts/package_app.sh"

rm -f "$ZIP_FILE" "$LEGACY_ZIP_FILE"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

printf 'Created %s\n' "$ZIP_FILE"

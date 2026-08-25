#!/usr/bin/env bash
# Upload packaged zip to Cloudflare R2 bucket (application-releases/wick/)
#
# Usage:
#   ./scripts/upload_r2.sh [path/to/Wick-macOS-x.y.z.zip]
#
# Environment variables (or loaded from .env):
#   CLOUDFLARE_API_TOKEN
#   CLOUDFLARE_ACCOUNT_ID
#   R2_BUCKET (default: application-releases)
#   R2_DOMAIN (default: https://dl.bitfroth.com)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load .env if present and vars are unset
if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
    echo "Error: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID must be set in environment or .env" >&2
    exit 1
fi

R2_BUCKET="${R2_BUCKET:-application-releases}"
R2_DOMAIN="${R2_DOMAIN:-https://dl.bitfroth.com}"
APP_PREFIX="wick"

# Locate zip file
ZIP_PATH="${1:-}"
if [[ -z "$ZIP_PATH" ]]; then
    ZIP_PATH="$(ls -1t "$ROOT_DIR/dist"/Wick-macOS*.zip 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$ZIP_PATH" || ! -f "$ZIP_PATH" ]]; then
    echo "No packaged zip found. Packaging now..."
    "$ROOT_DIR/scripts/package_zip.sh"
    ZIP_PATH="$(ls -1t "$ROOT_DIR/dist"/Wick-macOS*.zip 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$ZIP_PATH" || ! -f "$ZIP_PATH" ]]; then
    echo "Error: Could not locate zip file in $ROOT_DIR/dist/" >&2
    exit 1
fi

ZIP_FILENAME="$(basename "$ZIP_PATH")"
# Extract version from Wick-macOS-1.2.3.zip -> 1.2.3
VERSION=""
if [[ "$ZIP_FILENAME" =~ ^Wick-macOS-(.+)\.zip$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
fi

echo "Uploading $ZIP_FILENAME to Cloudflare R2 (bucket: $R2_BUCKET)..."

# Upload versioned zip
npx wrangler r2 object put "$R2_BUCKET/$APP_PREFIX/$ZIP_FILENAME" --file="$ZIP_PATH" --remote

# Upload latest generic Wick.zip
npx wrangler r2 object put "$R2_BUCKET/$APP_PREFIX/Wick.zip" --file="$ZIP_PATH" --remote

echo "=========================================="
echo " Upload complete!"
echo " Latest download:   $R2_DOMAIN/$APP_PREFIX/Wick.zip"
if [[ -n "$VERSION" ]]; then
    echo " Versioned download: $R2_DOMAIN/$APP_PREFIX/$ZIP_FILENAME"
fi
echo "=========================================="

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_app.sh"
PBXPROJ="$ROOT_DIR/ios/WickPhone.xcodeproj/project.pbxproj"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [build_number]"
    echo "Example: $0 1.10.30 69"
    exit 1
fi

NEW_VERSION="$1"

# Extract current build number from package_app.sh if not provided
CURRENT_BUILD=$(grep -E '^BUILD=' "$PACKAGE_SCRIPT" | sed -E 's/.*:-?([0-9]+).*/\1/')
if [ $# -ge 2 ]; then
    NEW_BUILD="$2"
else
    NEW_BUILD=$((CURRENT_BUILD + 1))
fi

echo "Synchronizing version to ${NEW_VERSION} (${NEW_BUILD})..."

# 1. Update scripts/package_app.sh
sed -i '' -E "s/VERSION=\"\$\{VERSION:-[^\}]+\}\"/VERSION=\"\$\{VERSION:-${NEW_VERSION}\}\"/" "$PACKAGE_SCRIPT"
sed -i '' -E "s/BUILD=\"\$\{BUILD:-[^\}]+\}\"/BUILD=\"\$\{BUILD:-${NEW_BUILD}\}\"/" "$PACKAGE_SCRIPT"
echo "✓ Updated $PACKAGE_SCRIPT"

# 2. Update ios/WickPhone.xcodeproj/project.pbxproj
sed -i '' -E "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"
echo "✓ Updated $PBXPROJ"

echo "Done! Both macOS and iOS versions are now ${NEW_VERSION} (${NEW_BUILD})."

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

# Portable in-place sed
sedi() {
    if [[ "${OSTYPE:-}" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

echo "Synchronizing version to ${NEW_VERSION} (${NEW_BUILD})..."

# 1. Update scripts/package_app.sh
sedi -E "s/^VERSION=.*/VERSION=\"\${VERSION:-${NEW_VERSION}}\"/" "$PACKAGE_SCRIPT"
sedi -E "s/^BUILD=.*/BUILD=\"\${BUILD:-${NEW_BUILD}}\"/" "$PACKAGE_SCRIPT"
grep -q "^VERSION=\"\${VERSION:-${NEW_VERSION}}\"$" "$PACKAGE_SCRIPT"
grep -q "^BUILD=\"\${BUILD:-${NEW_BUILD}}\"$" "$PACKAGE_SCRIPT"
echo "✓ Updated $PACKAGE_SCRIPT"

# 2. Update ios/WickPhone.xcodeproj/project.pbxproj
if [[ -f "$PBXPROJ" ]]; then
    sedi -E "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"
    sedi -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"
    echo "✓ Updated $PBXPROJ"
fi

# 3. Update linux/CMakeLists.txt
CMAKE_FILE="$ROOT_DIR/linux/CMakeLists.txt"
if [[ -f "$CMAKE_FILE" ]]; then
    sedi -E "s/project\(wick VERSION [0-9.]+/project\(wick VERSION ${NEW_VERSION}/" "$CMAKE_FILE"
    echo "✓ Updated $CMAKE_FILE"
fi

# 4. Update linux/packaging/PKGBUILD
PKGBUILD_FILE="$ROOT_DIR/linux/packaging/PKGBUILD"
if [[ -f "$PKGBUILD_FILE" ]]; then
    sedi -E "s/^pkgver=.*/pkgver=${NEW_VERSION}/" "$PKGBUILD_FILE"
    echo "✓ Updated $PKGBUILD_FILE"
fi

echo "Done! macOS, iOS, and Linux versions are now ${NEW_VERSION} (${NEW_BUILD})."

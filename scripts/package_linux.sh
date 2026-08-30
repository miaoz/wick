#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
LINUX_DIR="$ROOT_DIR/linux"
BUILD_DIR="$LINUX_DIR/build"

# Fallback version from package_app.sh if not provided
DEFAULT_VERSION=$(grep -E '^VERSION=' "$ROOT_DIR/scripts/package_app.sh" | sed -E 's/.*:-?([0-9.]+).*/\1/')
DEFAULT_BUILD=$(grep -E '^BUILD=' "$ROOT_DIR/scripts/package_app.sh" | sed -E 's/.*:-?([0-9]+).*/\1/')

VERSION="${VERSION:-$DEFAULT_VERSION}"
BUILD="${BUILD:-$DEFAULT_BUILD}"

echo "========================================="
echo "Packaging Wick for Linux v${VERSION} (${BUILD})"
echo "========================================="

mkdir -p "$DIST_DIR"

# 1. Build Linux release binary and tests
echo "--> Configuring CMake (Release)..."
cmake -G Ninja -B "$BUILD_DIR" -S "$LINUX_DIR" -DCMAKE_BUILD_TYPE=Release
echo "--> Building targets..."
cmake --build "$BUILD_DIR" -j"$(nproc 2>/dev/null || echo 4)"

# 2. Run unit tests
echo "--> Running CTests..."
ctest --test-dir "$BUILD_DIR" --output-on-failure

# 3. Create generic distribution tarball
STAGE_DIR="$DIST_DIR/stage-linux"
PKG_DIR="$STAGE_DIR/Wick-Linux-${VERSION}"
rm -rf "$STAGE_DIR"
mkdir -p "$PKG_DIR/bin" "$PKG_DIR/share/applications" "$PKG_DIR/share/icons/hicolor/scalable/apps" "$PKG_DIR/systemd" "$PKG_DIR/plugins/omarchy/wick.progress"

cp "$BUILD_DIR/wick" "$PKG_DIR/bin/"
cp "$LINUX_DIR/resources/wick.desktop" "$PKG_DIR/share/applications/"
cp "$LINUX_DIR/resources/candle.svg" "$PKG_DIR/share/icons/hicolor/scalable/apps/wick.svg"
cp "$LINUX_DIR/packaging/wick.service" "$PKG_DIR/systemd/"
cp -r "$LINUX_DIR/omarchy/wick.progress/"* "$PKG_DIR/plugins/omarchy/wick.progress/"
cp "$LINUX_DIR/packaging/install.sh" "$PKG_DIR/"
cp "$LINUX_DIR/packaging/uninstall.sh" "$PKG_DIR/"
chmod +x "$PKG_DIR/bin/wick" "$PKG_DIR/install.sh" "$PKG_DIR/uninstall.sh"

cat << README_EOF > "$PKG_DIR/README.md"
# 秉烛 · Wick for Linux (v${VERSION})

Native desktop app for Wick on Linux.

## Requirements
- Qt 6 (qt6-base, qt6-declarative, qt6-svg)
- OpenSSL
- libsecret

## Installation
Run the installer script:
\`\`\`bash
./install.sh
\`\`\`

To install system-wide (requires sudo):
\`\`\`bash
sudo ./install.sh
\`\`\`

To uninstall:
\`\`\`bash
./uninstall.sh
\`\`\`
README_EOF

echo "--> Creating tarball and zip archives..."
TAR_FILE="$DIST_DIR/Wick-Linux-${VERSION}.tar.gz"
ZIP_FILE="$DIST_DIR/Wick-Linux-${VERSION}.zip"
(cd "$STAGE_DIR" && tar -czf "$TAR_FILE" "Wick-Linux-${VERSION}")
(cd "$STAGE_DIR" && zip -rq "$ZIP_FILE" "Wick-Linux-${VERSION}")
rm -rf "$STAGE_DIR"

echo "✓ Created $TAR_FILE"
echo "✓ Created $ZIP_FILE"

# 4. If on Arch Linux / Omarchy with makepkg available, generate Arch package
if command -v makepkg >/dev/null 2>&1; then
    echo "--> Building Arch Linux package with makepkg..."
    ARCH_STAGE="$DIST_DIR/stage-arch"
    rm -rf "$ARCH_STAGE"
    mkdir -p "$ARCH_STAGE"
    cp "$LINUX_DIR/packaging/PKGBUILD" "$ARCH_STAGE/"
    cp "$LINUX_DIR/packaging/wick.service" "$ARCH_STAGE/"

    # Replace pkgver in PKGBUILD
    sed -i -E "s/^pkgver=.*/pkgver=${VERSION}/" "$ARCH_STAGE/PKGBUILD"

    (cd "$ARCH_STAGE" && makepkg -f --nodeps)
    mv "$ARCH_STAGE"/*.pkg.tar.zst "$DIST_DIR/" 2>/dev/null || true
    rm -rf "$ARCH_STAGE"
    echo "✓ Created Arch package in $DIST_DIR"
fi

echo ""
echo "Linux Packaging Complete! Artifacts in $DIST_DIR:"
ls -lh "$DIST_DIR"/Wick-Linux* "$DIST_DIR"/wick-*.pkg.tar.zst 2>/dev/null || true

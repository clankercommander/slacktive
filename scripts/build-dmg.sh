#!/bin/bash
set -euo pipefail

APP_NAME="Slacktive"
SCHEME="Slacktive"
PROJECT="Slacktive.xcodeproj"
DIST_DIR="dist"
DMG_NAME="$APP_NAME.dmg"
BUILD_DIR=$(mktemp -d)
STAGING_DIR=$(mktemp -d)

echo "==> Building $APP_NAME (Release)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build \
    ONLY_ACTIVE_ARCH=NO

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build failed — $APP_NAME.app not found"
    exit 1
fi

echo "==> Creating DMG..."
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

# Set up DMG staging area
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME"

# Clean up
rm -rf "$BUILD_DIR" "$STAGING_DIR"

echo ""
echo "==> Done! DMG created at $DIST_DIR/$DMG_NAME"
echo "    Size: $(du -h "$DIST_DIR/$DMG_NAME" | cut -f1)"

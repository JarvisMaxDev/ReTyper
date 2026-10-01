#!/bin/bash
# Build ReTyper and create .app bundle
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJ_DIR/ReTyper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "🔨 Building..."
cd "$PROJ_DIR"
# Use the same engine for building and resolving its output directory. Xcode 27's new default
# engine uses a different directory; the old hard-coded path can silently package a stale binary.
BUILD_SYSTEM="${RETYPER_BUILD_SYSTEM:-native}"
swift build --build-system "$BUILD_SYSTEM"
BIN_DIR="$(swift build --build-system "$BUILD_SYSTEM" --show-bin-path)"
test -x "$BIN_DIR/ReTyper" || { echo "Built executable not found: $BIN_DIR/ReTyper" >&2; exit 1; }

echo "📦 Creating .app bundle..."
mkdir -p "$MACOS_DIR"
cp "$BIN_DIR/ReTyper" "$MACOS_DIR/ReTyper"
cp "$APP_DIR/Contents/Info.plist" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true

echo "🎨 Copying resources..."
RESOURCES_DIR="$CONTENTS_DIR/Resources"
mkdir -p "$RESOURCES_DIR"
cp "$APP_DIR/Contents/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || true

echo "🔏 Code-signing..."
codesign --force --sign - "$APP_DIR"

echo "✅ Done! App bundle: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "Or to run from terminal:"
echo "  $MACOS_DIR/ReTyper"

#!/bin/bash
# Build ReTyper and create .app bundle
set -e

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJ_DIR/ReTyper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "🔨 Building..."
cd "$PROJ_DIR"
swift build

echo "📦 Creating .app bundle..."
mkdir -p "$MACOS_DIR"
cp .build/debug/ReTyper "$MACOS_DIR/ReTyper"
cp "$APP_DIR/Contents/Info.plist" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true

echo "🔏 Code-signing..."
codesign --force --sign - "$APP_DIR"

echo "✅ Done! App bundle: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "Or to run from terminal:"
echo "  $MACOS_DIR/ReTyper"


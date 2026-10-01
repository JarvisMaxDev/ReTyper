#!/bin/bash
# Builds and runs the ReTyper test stand against the ReTyper instance that is running now.
#
#   Tools/ReTyperStand/run.sh [output-directory]
#
# The stand is its own app with one text field; the driver presses a double ⌥ only while the stand
# is the active app, checks text, layout, clipboard restore and the log, and restores the user's
# clipboard, layout and "Switch Only Last Word" afterwards. Do not type during the run (~1 minute).
# Needs: ReTyper running, Polish Pro + Russian – PC enabled, Accessibility for the calling terminal.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
if [[ "${1:-}" == "--terminal" ]]; then
    shift
    mkdir -p "$BUILD"
    swiftc -O "$DIR/TerminalDriver.swift" "$DIR/../../Sources/ReTyper/KeyLayout.swift" -o "$BUILD/terminal-driver"
    exec "$BUILD/terminal-driver" "$@"
fi
OUT="${1:-$DIR/out/$(date +%Y%m%d-%H%M%S)}"
APP="$BUILD/ReTyperStand.app"

mkdir -p "$APP/Contents/MacOS" "$OUT"
swiftc -O "$DIR/Stand.swift" -o "$APP/Contents/MacOS/ReTyperStand"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.retyper.stand</string>
    <key>CFBundleName</key><string>ReTyper Stand</string>
    <key>CFBundleExecutable</key><string>ReTyperStand</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
swiftc -O "$DIR/Driver.swift" -o "$BUILD/stand-driver"

echo "Output: $OUT"
"$BUILD/stand-driver" --stand "$APP" --out "$OUT"

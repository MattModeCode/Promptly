#!/bin/bash
# run.sh — dev loop: compile → bundle .app → install to /Applications → relaunch → tail log.
# Builds NATIVE Apple Silicon (arm64) by default; pass --universal for a fat arm64+x86_64 binary.
# Sources are auto-discovered from Promptly/*.swift, so adding/removing a file needs no edit here.
# Usage:  ./run.sh [--universal]
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/promptly-build"
APP_PATH="/Applications/Promptly.app"
BUNDLE_ID="com.promptly.app"
DEPLOY_MIN="12.0"

UNIVERSAL=0
for a in "$@"; do [ "$a" = "--universal" ] && UNIVERSAL=1; done

# --- Build ---
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Promptly.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/Promptly.app/Contents/Resources/SeedPrompts"

# main.swift carries the top-level entry point; swiftc handles it regardless of argument order.
SOURCES=( "$PROJECT_ROOT"/Promptly/*.swift )
BIN="$BUILD_DIR/Promptly.app/Contents/MacOS/Promptly"

compile_slice() { # $1 = arch, $2 = output binary
    swiftc \
        -framework AppKit -framework Carbon -framework ApplicationServices \
        -O -target "$1-apple-macosx$DEPLOY_MIN" \
        "${SOURCES[@]}" \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
        -Xlinker "$PROJECT_ROOT/Promptly/Info.plist" \
        -o "$2"
}

if [ "$UNIVERSAL" = 1 ]; then
    echo "# Compiling Universal (arm64 + x86_64)…"
    compile_slice arm64  "$BUILD_DIR/Promptly-arm64"
    compile_slice x86_64 "$BUILD_DIR/Promptly-x86_64"
    lipo -create "$BUILD_DIR/Promptly-arm64" "$BUILD_DIR/Promptly-x86_64" -output "$BIN"
else
    echo "# Compiling native Apple Silicon (arm64)…"
    compile_slice arm64 "$BIN"
fi

# Copy resources
cp "$PROJECT_ROOT/Promptly/Info.plist" "$BUILD_DIR/Promptly.app/Contents/"
# Fonts are optional — the UI falls back to the system monospace font if absent.
cp "$PROJECT_ROOT/Promptly/Resources/"*.ttf "$BUILD_DIR/Promptly.app/Contents/Resources/" 2>/dev/null \
    || echo "# NOTE: no JetBrains Mono .ttf bundled — UI uses system monospace fallback."
cp "$PROJECT_ROOT/Promptly/Resources/SeedPrompts/"*.md "$BUILD_DIR/Promptly.app/Contents/Resources/SeedPrompts/" 2>/dev/null || true
cp "$PROJECT_ROOT/Promptly/Resources/AppIcon.icns" "$BUILD_DIR/Promptly.app/Contents/Resources/"

# Ad-hoc sign (stable for TCC — never use a Developer ID cert here; see CLAUDE.md)
codesign --sign - --force --deep "$BUILD_DIR/Promptly.app"

echo "# archs: $(lipo -archs "$BIN")"

# --- Install ---
pkill -x Promptly 2>/dev/null || true
sleep 0.3
rm -rf "$APP_PATH"
cp -R "$BUILD_DIR/Promptly.app" "$APP_PATH"

# --- Launch ---
open "$APP_PATH"

echo ""
echo "Promptly launched. Tailing logs..."
echo "(Ctrl-C to stop tailing — app keeps running)"
echo ""
echo "# If Accessibility stops working after rebuild: tccutil reset Accessibility $BUNDLE_ID"
echo ""
log stream --predicate 'subsystem == "com.promptly.app"' --level debug

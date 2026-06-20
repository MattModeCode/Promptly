#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/promptly-build"
APP_PATH="/Applications/Promptly.app"
BUNDLE_ID="com.promptly.app"

# --- Build ---
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Promptly.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/Promptly.app/Contents/Resources/SeedPrompts"

# Compile (x86_64 / Apple Intel — see CLAUDE.md Boundaries)
arch -x86_64 swiftc \
    -framework AppKit \
    -framework Carbon \
    -framework ApplicationServices \
    -target x86_64-apple-macosx12.0 \
    "$PROJECT_ROOT/Promptly/PasteCore.swift" \
    "$PROJECT_ROOT/Promptly/Capture.swift" \
    "$PROJECT_ROOT/Promptly/HotkeyManager.swift" \
    "$PROJECT_ROOT/Promptly/PromptStore.swift" \
    "$PROJECT_ROOT/Promptly/TokenEngine.swift" \
    "$PROJECT_ROOT/Promptly/PasteService.swift" \
    "$PROJECT_ROOT/Promptly/PromptEditorPanel.swift" \
    "$PROJECT_ROOT/Promptly/PanelController.swift" \
    "$PROJECT_ROOT/Promptly/main.swift" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "$PROJECT_ROOT/Promptly/Info.plist" \
    -o "$BUILD_DIR/Promptly.app/Contents/MacOS/Promptly"

# Copy resources
cp "$PROJECT_ROOT/Promptly/Info.plist" "$BUILD_DIR/Promptly.app/Contents/"
# Fonts are optional — the UI falls back to the system monospace font if absent.
for f in JetBrainsMono-Regular.ttf JetBrainsMono-Medium.ttf; do
    if [ -f "$PROJECT_ROOT/Promptly/Resources/$f" ]; then
        cp "$PROJECT_ROOT/Promptly/Resources/$f" "$BUILD_DIR/Promptly.app/Contents/Resources/"
    else
        echo "# NOTE: $f not bundled — UI uses system monospace fallback."
    fi
done
cp "$PROJECT_ROOT/Promptly/Resources/SeedPrompts/"*.md "$BUILD_DIR/Promptly.app/Contents/Resources/SeedPrompts/" 2>/dev/null || true

# Ad-hoc sign (stable for TCC — never use a Developer ID cert here; see CLAUDE.md)
codesign --sign - --force --deep "$BUILD_DIR/Promptly.app"

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

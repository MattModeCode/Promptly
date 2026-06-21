#!/bin/bash
#
# release.sh — build a distributable Promptly.app and zip it for a GitHub Release.
#
# Unlike run.sh (the dev loop: x86_64 only, installs to /Applications, relaunches, tails logs),
# this builds a clean **Universal** (arm64 + x86_64) ad-hoc-signed bundle into ./dist and does
# NOT install or launch anything. Ad-hoc signing needs no certificates or secrets.
#
# Usage:  ./scripts/release.sh [version]      (version defaults to 0.1.0; used only for the zip name)
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
DEPLOY_TARGET="12.0"
BUILD_DIR="$(mktemp -d /tmp/promptly-release.XXXXXX)"
APP="$BUILD_DIR/Promptly.app"
DIST_DIR="$PROJECT_ROOT/dist"
ZIP="$DIST_DIR/Promptly-$VERSION.zip"

# Same 13 sources, in the same order, as run.sh — keep them in sync.
SOURCES=(
  PasteCore.swift Capture.swift HotkeyManager.swift PromptStore.swift TokenEngine.swift
  PasteService.swift Palette.swift ThemedControls.swift LibraryScope.swift RelativeTime.swift
  PanelController.swift LibraryWindowController.swift main.swift
)
SRC_PATHS=()
for s in "${SOURCES[@]}"; do SRC_PATHS+=("$PROJECT_ROOT/Promptly/$s"); done
PLIST="$PROJECT_ROOT/Promptly/Info.plist"

compile() { # $1 = target triple, $2 = output binary path
  swiftc \
    -framework AppKit -framework Carbon -framework ApplicationServices \
    -target "$1" \
    "${SRC_PATHS[@]}" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" \
    -o "$2"
}

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/SeedPrompts"

echo "→ Compiling x86_64 slice…"
compile "x86_64-apple-macosx$DEPLOY_TARGET" "$BUILD_DIR/Promptly-x86_64"

ARM64_OK=1
echo "→ Compiling arm64 slice…"
compile "arm64-apple-macosx$DEPLOY_TARGET" "$BUILD_DIR/Promptly-arm64" || ARM64_OK=0

if [ "$ARM64_OK" = "1" ]; then
  echo "→ Merging Universal binary (arm64 + x86_64)…"
  lipo -create "$BUILD_DIR/Promptly-x86_64" "$BUILD_DIR/Promptly-arm64" \
       -output "$APP/Contents/MacOS/Promptly"
else
  echo "⚠️  arm64 build failed — shipping x86_64-only (still runs on Apple Silicon via Rosetta)."
  cp "$BUILD_DIR/Promptly-x86_64" "$APP/Contents/MacOS/Promptly"
fi

echo "→ Bundling resources…"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$PROJECT_ROOT/Promptly/Resources/SeedPrompts/"*.md "$APP/Contents/Resources/SeedPrompts/" 2>/dev/null || true
cp "$PROJECT_ROOT/Promptly/Resources/AppIcon.icns" "$APP/Contents/Resources/" 2>/dev/null || true
for f in JetBrainsMono-Regular.ttf JetBrainsMono-Medium.ttf; do
  [ -f "$PROJECT_ROOT/Promptly/Resources/$f" ] && \
    cp "$PROJECT_ROOT/Promptly/Resources/$f" "$APP/Contents/Resources/"
done

echo "→ Ad-hoc signing…"
codesign --sign - --force --deep "$APP"
codesign --verify --verbose=2 "$APP"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Promptly")"

echo "→ Packaging…"
mkdir -p "$DIST_DIR"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
rm -rf "$BUILD_DIR"

echo ""
echo "✅ $ZIP"
echo "   size: $(du -h "$ZIP" | cut -f1)    archs: $ARCHS"

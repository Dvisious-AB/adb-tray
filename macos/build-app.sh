#!/usr/bin/env bash
# Build "Appninjas ADB.app" from source. Used by the Homebrew formula and for local development.
#
#   macos/build-app.sh [--version X.Y.Z] [--output DIR] [--disable-sandbox]
#
# The version defaults to the VERSION file at the root of the repository.
#
# --disable-sandbox is passed on to `swift build`; Homebrew needs it because it already builds inside a
# sandbox, and macOS does not allow SwiftPM to nest one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUTPUT="$ROOT/macos/build"
SWIFT_FLAGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --disable-sandbox) SWIFT_FLAGS+=(--disable-sandbox); shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

swift build --package-path "$ROOT/macos" -c release ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
BIN_DIR="$(swift build --package-path "$ROOT/macos" -c release ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)"

APP="$OUTPUT/Appninjas ADB.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/locale" "$APP/Contents/Resources/icons"
install -m 755 "$BIN_DIR/adb-tray" "$APP/Contents/MacOS/adb-tray"
# The app reads the .po files directly; see macos/Sources/AdbTray/Localization.swift.
while read -r lang; do
    [[ -n "$lang" ]] && install -m 644 "$ROOT/po/$lang.po" "$APP/Contents/Resources/locale/$lang.po"
done < "$ROOT/po/LINGUAS"

# Menu icons: the Phosphor files as they are, drawn by the app itself (macos/Sources/AdbTray/Icons.swift).
install -m 644 "$ROOT"/branding/phosphor/*.svg "$APP/Contents/Resources/icons/"

# The app icon: branding/appninjas-adb.svg rendered by the app's own SVG reader, then packed by iconutil.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN_DIR/adb-tray" --render-iconset "$ROOT/branding/appninjas-adb.svg" "$ICONSET"
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>se.dvisious.adb-tray</string>
    <key>CFBundleName</key><string>Appninjas ADB</string>
    <key>CFBundleDisplayName</key><string>Appninjas ADB</string>
    <key>CFBundleExecutable</key><string>adb-tray</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>sv</string></array>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Anders Elmén and Dvisious AB. MIT License.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: built on the user's own machine, so there is no quarantine flag and no notarization
# is needed. A signed bundle is what notifications require.
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

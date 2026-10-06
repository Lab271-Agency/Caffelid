#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Caffelid.app"
# Never retain obsolete plists or tickets from a previous bundle identity.
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Caffelid" "$BIN_DIR/CaffelidHelper" "$APP_DIR/Contents/MacOS/"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"
cp -R "$PROJECT_DIR/Resources/en.lproj" "$PROJECT_DIR/Resources/it.lproj" "$APP_DIR/Contents/Resources/"
swift "$PROJECT_DIR/Scripts/make-icon.swift" "$PROJECT_DIR/.build/Caffelid.iconset"
iconutil -c icns "$PROJECT_DIR/.build/Caffelid.iconset" -o "$APP_DIR/Contents/Resources/Caffelid.icns"
plutil -lint "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/Resources/en.lproj/Localizable.strings" "$APP_DIR/Contents/Resources/it.lproj/Localizable.strings"
SIGNING_IDENTITY="${CAFFELID_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ { print $2; exit }')"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
fi
if [ -z "$SIGNING_IDENTITY" ] || [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "An Apple-issued signing certificate is required. Create an Apple Development certificate in Xcode Settings > Accounts, or set CAFFELID_SIGNING_IDENTITY." >&2
    exit 78
fi
mkdir -p "$APP_DIR/Contents/Library/LaunchDaemons"
cp "$PROJECT_DIR/Resources/app.caffelid.desktop.sleep-service.plist" "$APP_DIR/Contents/Library/LaunchDaemons/"
plutil -lint "$APP_DIR/Contents/Library/LaunchDaemons/app.caffelid.desktop.sleep-service.plist"
codesign --force --options runtime --timestamp --identifier app.caffelid.desktop.sleep-service --sign "$SIGNING_IDENTITY" "$APP_DIR/Contents/MacOS/CaffelidHelper"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --strict --verbose=2 -R '=anchor apple generic' "$APP_DIR"
codesign --verify --strict -R '=anchor apple generic' "$APP_DIR/Contents/MacOS/CaffelidHelper"
# One downloadable app. No standalone installer or runtime-generated package.
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PROJECT_DIR/dist/Caffelid.zip"
bash "$PROJECT_DIR/Scripts/make-dmg.sh"
printf '\nBuilt: %s\nDownload artifact: %s\n' "$APP_DIR" "$PROJECT_DIR/dist/Caffelid.dmg"

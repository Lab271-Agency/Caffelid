#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "Usage: bash Scripts/notarize.sh KEYCHAIN_PROFILE" >&2
    exit 64
fi
PROFILE="$1"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
APP="dist/Caffelid.app"
ZIP="dist/Caffelid.zip"
DMG="dist/Caffelid.dmg"
STATE_DIR="$PROJECT_DIR/.build/notarization"
mkdir -p "$STATE_DIR"
REQUIREMENT='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
codesign --verify --deep --strict -R "=$REQUIREMENT" "$APP"
codesign --verify --strict -R "=$REQUIREMENT" "$APP/Contents/MacOS/CaffelidHelper"
IDENTITY="${CAFFELID_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ { print $2; exit }')"
fi
if [ -z "$IDENTITY" ]; then
    echo "A Developer ID Application identity is required." >&2
    exit 78
fi

notarize_archive() {
    local archive="$1" digest receipt submission status
    digest="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    receipt="$STATE_DIR/$digest.json"
    if [ ! -f "$receipt" ]; then
        xcrun notarytool submit "$archive" --keychain-profile "$PROFILE" --output-format json > "$receipt.tmp"
        mv "$receipt.tmp" "$receipt"
    fi
    submission="$(plutil -extract id raw -o - "$receipt")"
    xcrun notarytool info "$submission" --keychain-profile "$PROFILE" --output-format json > "$STATE_DIR/status.json"
    status="$(plutil -extract status raw -o - "$STATE_DIR/status.json")"
    if [ "$status" = "In Progress" ]; then
        # Limit each wait; the same archive resumes its existing submission.
        xcrun notarytool wait "$submission" --keychain-profile "$PROFILE" --timeout 60s || true
        xcrun notarytool info "$submission" --keychain-profile "$PROFILE" --output-format json > "$STATE_DIR/status.json"
        status="$(plutil -extract status raw -o - "$STATE_DIR/status.json")"
    fi
    if [ "$status" != "Accepted" ]; then
        if [ "$status" = "Invalid" ] || [ "$status" = "Rejected" ]; then
            xcrun notarytool log "$submission" --keychain-profile "$PROFILE" "$STATE_DIR/$submission.log.json"
            echo "Notarization failed ($status). See $STATE_DIR/$submission.log.json" >&2
            exit 1
        fi
        echo "Notarization pending ($submission). Run this script again to resume." >&2
        exit 75
    fi
}

if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    notarize_archive "$ZIP"
    xcrun stapler staple "$APP"
fi
xcrun stapler validate "$APP"
# Include the app's ticket in both downloadable archives.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
APP_DIGEST="$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
if [ ! -f "$STATE_DIR/dmg-source.txt" ] || [ ! -f "$DMG" ] ||
   [ "$(cat "$STATE_DIR/dmg-source.txt")" != "$APP_DIGEST" ] ||
   ! codesign --verify --strict -R "=$REQUIREMENT" "$DMG" >/dev/null 2>&1; then
    bash Scripts/make-dmg.sh
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    # Avoid accidentally using an identity from a different developer team.
    APP_TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    DMG_TEAM="$(codesign -dv "$DMG" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [ -z "$APP_TEAM" ] || [ "$APP_TEAM" != "$DMG_TEAM" ]; then
        echo "The app and DMG must be signed by the same team." >&2
        exit 78
    fi
    printf '%s\n' "$APP_DIGEST" > "$STATE_DIR/dmg-source.txt"
fi
if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    notarize_archive "$DMG"
    xcrun stapler staple "$DMG"
fi
xcrun stapler validate "$DMG"
codesign --verify --deep --strict "$APP"
codesign --verify --strict "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 Caffelid.dmg Caffelid.zip > SHA256SUMS)
printf '\nNotarized app and DMG verified. Checksums: dist/SHA256SUMS\n'

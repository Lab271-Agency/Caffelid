#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/Caffelid.app"
if [ ! -d "$APP_DIR" ]; then
    echo "Build Caffelid before creating the disk image." >&2
    exit 66
fi
codesign --verify --strict -R '=anchor apple generic' "$APP_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/caffelid.dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_DIR" "$STAGING_DIR/Caffelid.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -ov -volname Caffelid -srcfolder "$STAGING_DIR" -format UDZO "$PROJECT_DIR/dist/Caffelid.dmg"
hdiutil verify "$PROJECT_DIR/dist/Caffelid.dmg"
printf '\nDisk image: %s\n' "$PROJECT_DIR/dist/Caffelid.dmg"

#!/bin/bash
# Read-only release acceptance: never launch the app or register its service.
set -euo pipefail
if [ "$#" -gt 1 ]; then
    echo "Usage: bash Scripts/verify-release.sh [DIST_DIRECTORY]" >&2
    exit 64
fi
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$(cd "${1:-$PROJECT_DIR/dist}" && pwd)"
APP="$DIST_DIR/Caffelid.app"
DMG="$DIST_DIR/Caffelid.dmg"
ZIP="$DIST_DIR/Caffelid.zip"
REQUIREMENT='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'

# Require the complete, exact manifest rather than trusting arbitrary paths.
python3 - "$DIST_DIR" "$PROJECT_DIR/Resources/Info.plist" <<'PY'
import hashlib
import plistlib
import re
import sys
from pathlib import Path

dist = Path(sys.argv[1])
expected = plistlib.loads(Path(sys.argv[2]).read_bytes())
info = plistlib.loads((dist / 'Caffelid.app/Contents/Info.plist').read_bytes())
for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion',
            'LSMinimumSystemVersion', 'LSUIElement'):
    if info.get(key) != expected[key]:
        raise SystemExit(f'App/source metadata mismatch: {key}')
license_file = dist / 'Caffelid.app/Contents/Resources/LICENSE.txt'
source_license = Path(sys.argv[2]).parent.parent / 'LICENSE'
if license_file.read_bytes() != source_license.read_bytes():
    raise SystemExit('Bundled MIT license differs from source license')
manifest = (dist / 'SHA256SUMS').read_text().splitlines()
seen = set()
for line in manifest:
    match = re.fullmatch(r'([a-f0-9]{64})  (Caffelid\.(?:dmg|zip))', line)
    if not match or match[2] in seen:
        raise SystemExit('Invalid or duplicate checksum entry')
    seen.add(match[2])
    if hashlib.sha256((dist / match[2]).read_bytes()).hexdigest() != match[1]:
        raise SystemExit(f'Checksum mismatch: {match[2]}')
if seen != {'Caffelid.dmg', 'Caffelid.zip'}:
    raise SystemExit('Missing release checksum')
print(f"Caffelid {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}): checksums and metadata valid")
PY

APP_TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ -z "$APP_TEAM" ]; then
    echo "Missing Apple signing team." >&2
    exit 78
fi
for target in "$APP" "$APP/Contents/MacOS/CaffelidHelper" "$DMG"; do
    codesign --verify --strict -R "=$REQUIREMENT" "$target"
    TEAM="$(codesign -dv "$target" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [ "$TEAM" != "$APP_TEAM" ]; then
        echo "Signing teams differ: $target" >&2
        exit 78
    fi
done
codesign --verify --deep --strict "$APP"
for binary in Caffelid CaffelidHelper; do
    if [ "$(lipo -archs "$APP/Contents/MacOS/$binary")" != "arm64" ]; then
        echo "V1 requires arm64 binaries: $binary" >&2
        exit 78
    fi
done
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil verify "$DMG"

WORK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/caffelid.verify.XXXXXX")"
MOUNT_DIR="$WORK_DIR/mounted"
mkdir "$MOUNT_DIR"
ATTACHED=0
cleanup() {
    local result=$?
    if [ "$ATTACHED" -eq 1 ]; then
        if ! hdiutil detach "$MOUNT_DIR"; then
            echo "Could not detach verification image: $MOUNT_DIR" >&2
            exit 1
        fi
    fi
    rm -rf "$WORK_DIR"
    exit "$result"
}
trap cleanup EXIT
ditto -x -k "$ZIP" "$WORK_DIR/zip"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_DIR" >/dev/null
ATTACHED=1
for copy in "$WORK_DIR/zip/Caffelid.app" "$MOUNT_DIR/Caffelid.app"; do
    codesign --verify --deep --strict -R "=$REQUIREMENT" "$copy"
    xcrun stapler validate "$copy"
done
python3 - "$APP" "$WORK_DIR/zip/Caffelid.app" "$MOUNT_DIR/Caffelid.app" "$MOUNT_DIR/Applications" <<'PY'
import hashlib
import os
import sys
from pathlib import Path

def contents(root):
    entries = {}
    for path in root.rglob('*'):
        key = str(path.relative_to(root))
        if path.is_symlink():
            entries[key] = ('link', os.readlink(path))
        elif path.is_file():
            entries[key] = ('file', hashlib.sha256(path.read_bytes()).hexdigest())
    return entries

original = contents(Path(sys.argv[1]))
for name in sys.argv[2:4]:
    if contents(Path(name)) != original:
        raise SystemExit(f'Archive app differs from signed app: {name}')
shortcut = Path(sys.argv[4])
if not shortcut.is_symlink() or os.readlink(shortcut) != '/Applications':
    raise SystemExit('DMG is missing the Applications shortcut')
print('ZIP and DMG contain the same signed app; Applications shortcut valid.')
PY
echo "Release verification passed. No app launch or power changes performed."

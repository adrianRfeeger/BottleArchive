#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
BOTTLE_ARCHIVE_CONFIGURATION=release ./script/build_and_run.sh --build-only
ZIP_PATH="$ROOT_DIR/dist/BottleArchive-1.1.1-arm64.zip"
TEMP_ZIP="$ROOT_DIR/dist/.BottleArchive-$(date +%s)-$$.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/Bottle Archive.app" "$TEMP_ZIP"
mv "$TEMP_ZIP" "$ZIP_PATH"
/usr/bin/codesign --verify --deep --strict "$ROOT_DIR/dist/Bottle Archive.app"
/usr/bin/file "$ROOT_DIR/dist/Bottle Archive.app/Contents/MacOS/BottleArchive"
echo "$ZIP_PATH"

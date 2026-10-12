#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
ARCHITECTURES="${BOTTLE_ARCHIVE_ARCHITECTURES:-universal}"
if [[ -n "${BOTTLE_ARCHIVE_NOTARY_PROFILE:-}" && "${BOTTLE_ARCHIVE_SIGNING_IDENTITY:--}" == - ]]; then
    echo "Notarisation requires BOTTLE_ARCHIVE_SIGNING_IDENTITY to name a Developer ID Application certificate." >&2
    exit 2
fi
BOTTLE_ARCHIVE_ARCHITECTURES="$ARCHITECTURES" BOTTLE_ARCHIVE_CONFIGURATION=release ./script/build_and_run.sh --build-only
ZIP_PATH="$ROOT_DIR/dist/BottleArchive-1.1.1-$ARCHITECTURES.zip"
TEMP_ZIP="$ROOT_DIR/dist/.BottleArchive-$(date +%s)-$$.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/Bottle Archive.app" "$TEMP_ZIP"
mv "$TEMP_ZIP" "$ZIP_PATH"
/usr/bin/codesign --verify --deep --strict "$ROOT_DIR/dist/Bottle Archive.app"
if [[ "$ARCHITECTURES" == universal ]]; then
    /usr/bin/python3 - "$ROOT_DIR/dist/Bottle Archive.app" <<'PYARCH'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1])
for path in ['Contents/MacOS/BottleArchive','Contents/Helpers/pigz']:
    architectures=set(subprocess.check_output(['/usr/bin/lipo','-archs',str(app/path)],text=True).split())
    if architectures != {'arm64','x86_64'}:raise SystemExit('Expected both architectures in '+path)
PYARCH
fi
if [[ -n "${BOTTLE_ARCHIVE_NOTARY_PROFILE:-}" ]]; then
    NOTARY_RESULT="$ROOT_DIR/dist/notarization-result.json"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$BOTTLE_ARCHIVE_NOTARY_PROFILE" --wait --output-format json > "$NOTARY_RESULT"
    /usr/bin/python3 - "$NOTARY_RESULT" <<'PYNOTARY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarisation was not accepted: '+result.get('status','unknown'))
print('Notarisation accepted: '+result['id'])
PYNOTARY
    xcrun stapler staple "$ROOT_DIR/dist/Bottle Archive.app"
    xcrun stapler validate "$ROOT_DIR/dist/Bottle Archive.app"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$ROOT_DIR/dist/Bottle Archive.app"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/Bottle Archive.app" "$TEMP_ZIP"
    mv "$TEMP_ZIP" "$ZIP_PATH"
    /usr/bin/codesign --verify --deep --strict "$ROOT_DIR/dist/Bottle Archive.app"
fi
(cd "$ROOT_DIR/dist"; shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256")
/usr/bin/file "$ROOT_DIR/dist/Bottle Archive.app/Contents/MacOS/BottleArchive"
echo "$ZIP_PATH"

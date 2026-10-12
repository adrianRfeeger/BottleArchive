#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Bottle Archive.app"
CONFIGURATION="${BOTTLE_ARCHIVE_CONFIGURATION:-debug}"
JOB_MARKER="$HOME/Library/Caches/BottleArchive/active-job"
if [[ -f "$JOB_MARKER" ]]; then
    ACTIVE_PID="$(cat "$JOB_MARKER")"
    if [[ "$ACTIVE_PID" =~ ^[0-9]+$ ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        echo "Bottle Archive has an active job. Finish or cancel it before rebuilding." >&2
        exit 1
    fi
fi
pkill -x BottleArchive >/dev/null 2>&1 || true
cd "$ROOT_DIR"
swift build --build-system native -c "$CONFIGURATION" --product BottleArchive
swift build --build-system native -c "$CONFIGURATION" --product pigz
BINARY_DIR="$(swift build --build-system native -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.stage.XXXXXX")"
STAGED_APP="$STAGING_DIR/Bottle Archive.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$STAGED_APP/Contents/Helpers"
cp "$BINARY_DIR/BottleArchive" "$STAGED_APP/Contents/MacOS/"
cp "$BINARY_DIR/pigz" "$STAGED_APP/Contents/Helpers/"
cp "$ROOT_DIR/Vendor/pigz/README" "$STAGED_APP/Contents/Resources/pigz-LICENSE.txt"
cp "$ROOT_DIR/LICENSE" "$STAGED_APP/Contents/Resources/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/codesign --force --sign - "$STAGED_APP/Contents/Helpers/pigz"
cp -R "$BINARY_DIR/BottleArchive_BottleArchive.bundle" "$STAGED_APP/Contents/Resources/"
if [[ ! -f "$ROOT_DIR/.build/BottleArchive.icns" || "$ROOT_DIR/script/create_icon.swift" -nt "$ROOT_DIR/.build/BottleArchive.icns" ]]; then
    xcrun swift -module-cache-path "$ROOT_DIR/.build/icon-module-cache" "$ROOT_DIR/script/create_icon.swift" "$ROOT_DIR/.build"
fi
cp "$ROOT_DIR/.build/BottleArchive.icns" "$STAGED_APP/Contents/Resources/"
/usr/bin/python3 - "$STAGED_APP/Contents/Info.plist" <<'PYINFO'
import plistlib,sys
info={'CFBundleExecutable':'BottleArchive','CFBundleIdentifier':'com.adrianfeeger.BottleArchive','CFBundleName':'Bottle Archive','CFBundleDisplayName':'Bottle Archive','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.1.1','CFBundleVersion':'3','LSMinimumSystemVersion':'15.0','NSPrincipalClass':'NSApplication','CFBundleIconFile':'BottleArchive','CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en','fr','de','es','it','ja','zh-Hans','pt-BR'],'NSHighResolutionCapable':True}
with open(sys.argv[1],'wb') as f:plistlib.dump(info,f)
PYINFO
/usr/bin/codesign --force --sign - "$STAGED_APP"
if [[ -d "$APP_BUNDLE" ]]; then mv "$APP_BUNDLE" "$STAGING_DIR/previous.app"; fi
mv "$STAGED_APP" "$APP_BUNDLE"
case "$MODE" in
 --build-only) ;;
 run) /usr/bin/open -n "$APP_BUNDLE" ;;
 --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x BottleArchive >/dev/null ;;
 --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/BottleArchive" ;;
 --logs|logs|--telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.adrianfeeger.BottleArchive"' ;;
 *) echo "usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2;exit 2 ;;
esac

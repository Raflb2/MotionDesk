#!/bin/bash
# Builds MotionDesk.app (Intel + Apple Silicon) and packages it into MotionDesk.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP=MotionDesk
OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/$APP.app/Contents/MacOS" "$OUT/$APP.app/Contents/Resources"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

cp "$BIN/$APP" "$OUT/$APP.app/Contents/MacOS/$APP"
cp Info.plist "$OUT/$APP.app/Contents/Info.plist"

# App icon
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/$APP.app/Contents/Resources/AppIcon.icns"

# Ad-hoc sign (no paid Apple developer account needed)
codesign --force --deep --sign - "$OUT/$APP.app"

# DMG
mkdir -p "$OUT/dmg"
cp -R "$OUT/$APP.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "$APP" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/$APP.dmg"

echo "Done: $OUT/$APP.dmg"

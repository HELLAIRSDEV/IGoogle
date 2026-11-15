#!/usr/bin/env bash
#
# Собирает красивый DMG: крупная иконка, тематический фон, раскладка «перетащи в Applications».
# Использование: VERSION=0.1.0 ./scripts/make_dmg.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.1.0}"
APP="dist/IGoogle.app"
OUT="dist/IGoogle-${VERSION}-macos.dmg"
BG="macos/Packaging/dmg-background.png"
MNT="/Volumes/IGoogle"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> release build"
( cd macos && xcrun --sdk macosx swift build -c release )

echo "==> .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp macos/.build/release/IGoogle "$APP/Contents/MacOS/IGoogle"
cp macos/Packaging/Info.plist "$APP/Contents/Info.plist"
cp macos/Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/IGoogle"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "==> staging"
STAGE="dist/dmgstage"
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/IGoogle.app"
ln -sf /Applications "$STAGE/Applications"
cp "$BG" "$STAGE/.background/background.png"

echo "==> writable DMG"
TMP="dist/tmp-igoogle.dmg"
rm -f "$TMP"
hdiutil create -volname "IGoogle" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$TMP" >/dev/null

echo "==> mount + Finder layout"
hdiutil detach "$MNT" >/dev/null 2>&1 || true
hdiutil attach "$TMP" -mountpoint "$MNT" -nobrowse -readwrite >/dev/null
sleep 1

osascript <<'AS' || echo "!! Finder-layout пропущен (нет разрешения Automation) — DMG будет без раскладки"
tell application "Finder"
  tell disk "IGoogle"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 1100, 640}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 160
    set text size of vo to 13
    set background picture of vo to file ".background:background.png"
    set position of item "IGoogle.app" of container window to {150, 250}
    set position of item "Applications" of container window to {750, 250}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
AS

sync
hdiutil detach "$MNT" >/dev/null 2>&1 || true

echo "==> compress"
rm -f "$OUT"
hdiutil convert "$TMP" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$TMP"
echo "DMG готов: $OUT ($(du -h "$OUT" | cut -f1))"

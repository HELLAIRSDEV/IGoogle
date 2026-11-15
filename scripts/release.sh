#!/usr/bin/env bash
#
# Собирает релизные артефакты IGoogle: .app + .dmg (macOS) и подписанный .apk (Android).
# Использование:  VERSION=0.1.0 ./scripts/release.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.1.0}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
JDK21="${JDK21:-$HOME/Library/Java/JavaVirtualMachines/jbr-21.0.11/Contents/Home}"

mkdir -p dist

echo "==> macOS release build"
( cd macos && xcrun --sdk macosx swift build -c release )

echo "==> Сборка IGoogle.app"
rm -rf "dist/IGoogle.app"
mkdir -p "dist/IGoogle.app/Contents/MacOS" "dist/IGoogle.app/Contents/Resources"
cp macos/.build/release/IGoogle "dist/IGoogle.app/Contents/MacOS/IGoogle"
cp macos/Packaging/Info.plist "dist/IGoogle.app/Contents/Info.plist"
cp macos/Packaging/AppIcon.icns "dist/IGoogle.app/Contents/Resources/AppIcon.icns"
chmod +x "dist/IGoogle.app/Contents/MacOS/IGoogle"
codesign --force --deep --sign - "dist/IGoogle.app"

echo "==> DMG"
rm -f "dist/IGoogle-${VERSION}-macos.dmg"
hdiutil create -volname "IGoogle" -srcfolder "dist/IGoogle.app" \
  -ov -format UDZO "dist/IGoogle-${VERSION}-macos.dmg" >/dev/null

echo "==> Android release APK"
GRADLE_BIN="$(ls -d "$HOME/.gradle/wrapper/dists/gradle-8.9-bin"/*/gradle-8.9/bin/gradle 2>/dev/null | head -1)"
if [ -z "$GRADLE_BIN" ]; then
  echo "!! Gradle 8.9 не найден в ~/.gradle/wrapper/dists (открой проект в Android Studio один раз)"
  exit 1
fi
JAVA_HOME="$JDK21" "$GRADLE_BIN" -p "$ROOT" :android:assembleRelease --no-daemon --console=plain
cp android/build/outputs/apk/release/android-release.apk "dist/IGoogle-${VERSION}-android.apk"

echo "==> Готово:"
ls -lh dist/*.dmg dist/*.apk

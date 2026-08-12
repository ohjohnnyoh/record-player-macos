#!/bin/bash
# Собирает установочный образ Record.dmg с перетаскиванием в «Программы».
#   ./package.sh
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
APP_NAME="Record"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
STAGE="$BUILD_DIR/dmg-stage"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Сборка приложения"
./build.sh --no-install >/dev/null
[[ -d "$APP" ]] || { echo "Не собралось: $APP"; exit 1; }

echo "==> Подготовка образа"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/$APP_NAME.app"

# Ярлык «Программ» рядом с приложением — то самое перетаскивание при установке.
ln -s /Applications "$STAGE/Applications"

# Иконка тома: та же, что у приложения.
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true

echo "==> Создание $(basename "$DMG")"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO -imagekey zlib-level=9 \
    "$DMG" >/dev/null

rm -rf "$STAGE"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo
echo "Готово: $DMG  ($SIZE)"
echo
echo "Установка: открыть образ и перетащить Record в «Программы»."
echo "Открыть сейчас:  open \"$DMG\""

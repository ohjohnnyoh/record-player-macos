#!/bin/bash
# Собирает оформленный установочный образ Record.dmg.
#   ./package.sh
#
# Окно образа открывается заданного размера, с крупными иконками по центру
# и стрелкой между ними. Раскладка хранится в .DS_Store тома, а его умеет
# записать только Finder — поэтому шаг оформления идёт через AppleScript.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
APP_NAME="Record"
VOL_NAME="Record"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
RW_DMG="$BUILD_DIR/.$APP_NAME-rw.dmg"
MOUNT="/Volumes/$VOL_NAME"

# Размер окна и позиции иконок должны совпадать с геометрией фона
# из tools/makedmgbg.swift.
WIN_W=640; WIN_H=400; WIN_X=280; WIN_Y=140
ICON_SIZE=128
APP_X=160; APP_Y=235
LINK_X=480; LINK_Y=235

echo "==> Сборка приложения"
./build.sh --no-install >/dev/null
[[ -d "$APP" ]] || { echo "Не собралось: $APP"; exit 1; }

echo "==> Фон окна установщика"
BG_DIR="$BUILD_DIR/dmg-bg"
rm -rf "$BG_DIR" && mkdir -p "$BG_DIR"
swift "$ROOT/tools/makedmgbg.swift" "$BG_DIR/bg.png" 1 >/dev/null
swift "$ROOT/tools/makedmgbg.swift" "$BG_DIR/bg@2x.png" 2 >/dev/null
# Один файл с обычным и retina-вариантом: Finder сам выберет нужный.
tiffutil -cathidpicheck "$BG_DIR/bg.png" "$BG_DIR/bg@2x.png" -out "$BG_DIR/background.tiff" >/dev/null 2>&1 \
    || cp "$BG_DIR/bg.png" "$BG_DIR/background.tiff"

echo "==> Создание тома"
[[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
rm -f "$RW_DMG" "$DMG"
# -type UDIF вместе с -size даёт образ для чтения и записи;
# -format здесь не годится, он требует готовой папки-источника.
hdiutil create -size 96m -fs HFS+ -volname "$VOL_NAME" -type UDIF "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -nobrowse -noautoopen >/dev/null

cp -R "$APP" "$MOUNT/$APP_NAME.app"
ln -s /Applications "$MOUNT/Applications"
mkdir -p "$MOUNT/.background"
cp "$BG_DIR/background.tiff" "$MOUNT/.background/background.tiff"

echo "==> Раскладка окна"
# Если Finder не даст собой управлять (не выдано разрешение на автоматизацию),
# образ всё равно соберётся — просто без оформления.
if ! osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H + 28))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT
then
    echo "   Finder не дал управлять собой — образ будет без оформления."
    echo "   Разрешение выдаётся в «Конфиденциальность и безопасность» → «Автоматизация»."
fi

# Иконку тома ставим уже после раскладки: Finder при первом открытии тома
# перебирает его содержимое, и положенный заранее файл до образа не доезжает.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true

echo "==> Проверка тома перед сжатием"
for item in "$APP_NAME.app" "Applications" ".background/background.tiff" ".DS_Store" ".VolumeIcon.icns"; do
    if [[ -e "$MOUNT/$item" || -L "$MOUNT/$item" ]]; then
        echo "   есть      $item"
    else
        echo "   ОТСУТСТВУЕТ $item"
    fi
done

sync
hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || hdiutil detach "$MOUNT" -quiet || true

echo "==> Сжатие"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW_DMG"
rm -rf "$BG_DIR"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo
echo "Готово: $DMG  ($SIZE)"
echo "Открыть:  open \"$DMG\""

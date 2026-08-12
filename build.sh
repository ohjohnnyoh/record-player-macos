#!/bin/bash
# Собирает Record.app и (по умолчанию) устанавливает его в /Applications.
#   ./build.sh          — собрать и установить
#   ./build.sh --no-install  — только собрать, .app останется в build/
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
APP_NAME="Record"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

echo "==> Компиляция (release)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/RecordPlayer"
[[ -f "$BIN" ]] || { echo "Не найден бинарник: $BIN"; exit 1; }

echo "==> Сборка бандла"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RecordPlayer"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Локализации"
for catalog in "$ROOT"/Resources/*.xcstrings; do
    xcrun xcstringstool compile "$catalog" --output-directory "$APP/Contents/Resources"
done

echo "==> Иконка"
ICON_TMP="$BUILD_DIR/icon"
rm -rf "$ICON_TMP" && mkdir -p "$ICON_TMP/AppIcon.iconset"
swift "$ROOT/tools/makeicon.swift" "$ICON_TMP/icon.png" "$ROOT/Resources/logo.png"
for size in 16 32 64 128 256 512; do
    sips -z $size $size "$ICON_TMP/icon.png" --out "$ICON_TMP/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON_TMP/icon.png" --out "$ICON_TMP/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Подпись (ad-hoc, для локального запуска)"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   подпись пропущена"

if [[ $INSTALL -eq 1 ]]; then
    echo "==> Установка в /Applications"
    # Если приложение запущено — закрываем, иначе замена файлов сломает сессию.
    osascript -e 'tell application "Record" to quit' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"

    # Finder кэширует иконки и сам бандл не перечитывает — приложение так и будет
    # показываться со стандартной. Обновляем время изменения, перерегистрируем
    # в LaunchServices и просим Dock перечитать кэш.
    touch "/Applications/$APP_NAME.app"
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "/Applications/$APP_NAME.app" || true
    killall Dock >/dev/null 2>&1 || true

    echo
    echo "Готово: /Applications/$APP_NAME.app"
    echo "Запустить:  open -a Record"
else
    echo
    echo "Готово: $APP"
fi

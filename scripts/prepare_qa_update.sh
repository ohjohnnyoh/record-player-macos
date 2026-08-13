#!/bin/bash
# Создаёт изолированную пару QA-сборок и локальный подписанный Sparkle feed.
# Ничего не устанавливает и не публикует.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
QA_ROOT="$PROJECT_ROOT/build/update-qa"
QA_FEED="$QA_ROOT/feed"
QA_APPS="$QA_ROOT/apps"
OLD_APP="$QA_APPS/Record QA 1.6.90.app"
NEW_APP="$QA_APPS/Record QA 1.6.91.app"
ARCHIVE_NAME="Record-QA-1.6.91.zip"
ARCHIVE="$QA_FEED/$ARCHIVE_NAME"
FEED_URL="http://127.0.0.1:8765/appcast.xml"
DOWNLOAD_PREFIX="http://127.0.0.1:8765/"
PLIST_BUDDY=/usr/libexec/PlistBuddy
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"

configure_app() {
    local app_path="$1"
    local short_version="$2"
    local build_number="$3"
    local plist="$app_path/Contents/Info.plist"

    "$PLIST_BUDDY" -c "Set :CFBundleName Record QA" "$plist"
    "$PLIST_BUDDY" -c "Set :CFBundleDisplayName Record QA" "$plist"
    "$PLIST_BUDDY" -c "Set :CFBundleIdentifier ru.local.recordplayer.qa" "$plist"
    "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $short_version" "$plist"
    "$PLIST_BUDDY" -c "Set :CFBundleVersion $build_number" "$plist"
    "$PLIST_BUDDY" -c "Set :SUFeedURL $FEED_URL" "$plist"

    codesign --force --deep --sign - "$app_path" >/dev/null
}

echo "==> Базовая release-сборка"
"$PROJECT_ROOT/build.sh" --no-install >/dev/null

echo "==> Изолированные QA-приложения"
rm -rf "$QA_ROOT"
mkdir -p "$QA_FEED" "$QA_APPS"
ditto "$PROJECT_ROOT/build/Record.app" "$OLD_APP"
ditto "$PROJECT_ROOT/build/Record.app" "$NEW_APP"
configure_app "$OLD_APP" "1.6.90" "790"
configure_app "$NEW_APP" "1.6.91" "791"

echo "==> Update ZIP с сохранением структуры фреймворка"
ditto -c -k --sequesterRsrc --keepParent "$NEW_APP" "$ARCHIVE"

echo "==> Заметки QA-версии"
cp "$PROJECT_ROOT/scripts/qa/Record-QA-1.6.91.md" "$QA_FEED/Record-QA-1.6.91.md"

echo "==> Подписанный appcast"
(
    cd "$QA_FEED"
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --maximum-versions 1 \
        --maximum-deltas 0 \
        -o appcast.xml \
        . >/dev/null
)
[[ -f "$QA_FEED/appcast.xml" ]] || { echo "Sparkle не создал appcast"; exit 1; }

echo "==> Проверки артефактов"
codesign --verify --deep --strict "$OLD_APP"
codesign --verify --deep --strict "$NEW_APP"
unzip -t "$ARCHIVE" >/dev/null
xmllint --noout "$QA_FEED/appcast.xml"

echo
echo "QA old:  $OLD_APP"
echo "QA new:  $NEW_APP"
echo "Feed:    $QA_FEED/appcast.xml"
echo "Archive: $ARCHIVE"
echo "Server:  python3 -m http.server 8765 --directory \"$QA_FEED\""

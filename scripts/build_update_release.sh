#!/bin/bash
# Создаёт подписанный ZIP для Sparkle и appcast для публикации.
# Приватный EdDSA-ключ хранится только в macOS Keychain.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
PLIST="$PROJECT_ROOT/Resources/Info.plist"
PLIST_BUDDY=/usr/libexec/PlistBuddy
VERSION="$($PLIST_BUDDY -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$($PLIST_BUDDY -c 'Print :CFBundleVersion' "$PLIST")"
RELEASE_ROOT="$PROJECT_ROOT/build/update-release"
ARCHIVES="$RELEASE_ROOT/archives"
ARCHIVE_NAME="Record-$VERSION.zip"
ARCHIVE="$ARCHIVES/$ARCHIVE_NAME"
APPCAST="$RELEASE_ROOT/appcast.xml"
WORKING_APPCAST="$ARCHIVES/appcast.xml"
APPCAST_NOTES_SOURCE="$PROJECT_ROOT/docs/APPCAST-$VERSION.md"
RELEASE_NOTES_SOURCE="$PROJECT_ROOT/docs/RELEASE-$VERSION.md"
NOTES_SOURCE="$APPCAST_NOTES_SOURCE"
NOTES="$ARCHIVES/Record-$VERSION.md"
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_PREFIX="https://github.com/ohjohnnyoh/record-player-macos/releases/download/v$VERSION/"

[[ -f "$RELEASE_NOTES_SOURCE" ]] || {
    echo "Не найдены заметки релиза: $RELEASE_NOTES_SOURCE"
    exit 1
}
[[ -f "$APPCAST_NOTES_SOURCE" ]] || NOTES_SOURCE="$RELEASE_NOTES_SOURCE"

echo "==> Release-сборка Record $VERSION ($BUILD_NUMBER)"
"$PROJECT_ROOT/build.sh" --no-install >/dev/null

rm -rf "$RELEASE_ROOT"
mkdir -p "$ARCHIVES"

echo "==> Подписанный update ZIP"
ditto -c -k --sequesterRsrc --keepParent \
    "$PROJECT_ROOT/build/Record.app" "$ARCHIVE"
cp "$NOTES_SOURCE" "$NOTES"
if [[ -f "$PROJECT_ROOT/appcast.xml" ]]; then
    cp "$PROJECT_ROOT/appcast.xml" "$WORKING_APPCAST"
fi

echo "==> Подписанный appcast"
(
    cd "$ARCHIVES"
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --maximum-versions 3 \
        --maximum-deltas 0 \
        -o appcast.xml \
        . >/dev/null
)
[[ -f "$WORKING_APPCAST" ]] || { echo "Sparkle не создал appcast"; exit 1; }
mv "$WORKING_APPCAST" "$APPCAST"

echo "==> Проверки"
codesign --verify --deep --strict "$PROJECT_ROOT/build/Record.app"
unzip -t "$ARCHIVE" >/dev/null
xmllint --noout "$APPCAST"
grep -q 'sparkle:edSignature=' "$APPCAST"
grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST"

ARCHIVE_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

echo
echo "App:     $PROJECT_ROOT/build/Record.app"
echo "ZIP:     $ARCHIVE"
echo "Appcast: $APPCAST"
echo "SHA-256: $ARCHIVE_SHA"

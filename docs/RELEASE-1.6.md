# Record 1.6

[Русский](#русский) · [English](#english)

## Русский

Нативный неофициальный плеер Radio Record для macOS. Работает без браузера и вебвью.

### Установка

1. Скачайте `Record-1.6.dmg` в разделе Assets ниже.
2. Откройте образ и перетащите Record в папку «Программы».
3. При первом запуске нажмите на приложение правой кнопкой мыши и выберите **Открыть**.
4. Подтвердите запуск в появившемся окне.

У сборки локальная ad-hoc подпись, но нет сертификата Apple Developer ID и нотарификации. Поэтому Gatekeeper может показать предупреждение. Эти действия нужны только при первом запуске.

Если macOS продолжает блокировать приложение:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Требуется macOS 14 или новее.

### Что нового

- Добавлен полноразмерный режим станции в стиле Apple Music. Нажмите обложку текущего трека в нижнем плеере, чтобы открыть его.
- В центре показана крупная квадратная обложка текущего трека, а справа расположена история эфира за последние сутки с поиском и ручным обновлением.
- Кнопки предыдущей станции, воспроизведения, следующей станции и избранного находятся под обложкой. Нижняя пилюля плеера в этом режиме скрыта.
- Компоновка адаптируется к боковой панели. При скрытой панели обложка и левая часть становятся шире, а история эфира компактнее.
- Полный режим следует за воспроизведением. Случайный выбор, стрелки и горячие клавиши сразу обновляют станцию, обложку и историю эфира.
- Добавлена автоматическая проверка GitHub Releases не чаще одного раза в сутки.
- В меню Record появилась ручная команда «Проверить обновления…».
- Запросы обновлений используют `ETag` и локальный кэш. Сетевые ошибки не мешают запуску и воспроизведению.
- Исправлен рывок верхней панели при открытии и закрытии бокового меню. Поиск получил фиксированную ширину и больше не схлопывается в кнопку.
- Элементы верхней панели сохранены отдельными системными пилюлями и собраны справа в стабильном порядке.
- Обновлено системное окно «О программе». Добавлена кликабельная ссылка на независимого разработчика oh_johnny.

Record не загружает и не устанавливает обновления автоматически. По запросу пользователя приложение открывает страницу нового релиза в браузере.

### Основные возможности

- Все 117 станций с поиском, жанрами и избранным.
- Полный режим станции и история эфира за последние сутки.
- История треков и локальная статистика прослушивания.
- Мини-плеер и управление из строки меню.
- Медиаклавиши и панель «Сейчас исполняется».
- Четыре уровня качества потока.
- Переподключение после сетевого сбоя или сна Mac.

### Проверено

- Семь автоматических тестов.
- Релизная сборка с `-warnings-as-errors`.
- Подпись через `codesign --verify --deep --strict`.
- Целостность образа через `hdiutil verify`.
- Русская и английская локализации.
- Запуск приложения непосредственно из смонтированного DMG.

SHA-256 для `Record-1.6.dmg`: `cdab0150c1ed8840f330d332df4bbb653ed38fc88f5e24277cd9b4edc9352813`

## English

An unofficial native Radio Record player for macOS. No browser or web view required.

### Installation

1. Download `Record-1.6.dmg` from the Assets section below.
2. Open the disk image and drag Record to Applications.
3. On first launch, right-click the app and choose **Open**.
4. Confirm the launch in the macOS dialog.

The build has a local ad-hoc signature, but it is not signed with an Apple Developer ID certificate and is not notarized. Gatekeeper may display a warning. These steps are only required for the first launch.

If macOS continues to block the app:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Record requires macOS 14 or later.

### What is new

- Added a full station view inspired by Apple Music. Click the current track artwork in the bottom player to open it.
- Large square artwork for the current track is shown in the center, with searchable broadcast history from the last 24 hours on the right.
- Previous station, play, next station, and favorite controls sit below the artwork. The bottom player bar is hidden in this view.
- The layout adapts to the sidebar. Hiding it expands the artwork and left column while keeping broadcast history compact.
- The full view follows playback. Random selection, arrow controls, and keyboard shortcuts immediately update the station, artwork, and history.
- Added automatic GitHub Releases checks no more than once per day.
- Added a manual "Check for Updates…" command to the Record menu.
- Update requests use `ETag` and a local cache. Network failures never interrupt startup or playback.
- Fixed the toolbar jump when showing or hiding the sidebar. Search now has a fixed width and no longer collapses into a button.
- Toolbar controls remain separate system pills and form a stable trailing group.
- Updated the system About panel with a clickable link to independent developer oh_johnny.

Record never downloads or installs updates automatically. It opens the new release page in the browser only after a user request.

### Main features

- All 117 stations with search, genres, and favorites.
- Full station view and broadcast history for the last 24 hours.
- Track history and local listening statistics.
- Mini player and menu bar controls.
- Media keys and the Now Playing panel.
- Four stream quality levels.
- Automatic reconnection after network errors or Mac sleep.

### Verified

- Seven automated tests.
- Release build with `-warnings-as-errors`.
- Signature check with `codesign --verify --deep --strict`.
- Disk image integrity with `hdiutil verify`.
- Russian and English localizations.
- App launch directly from the mounted DMG.

SHA-256 for `Record-1.6.dmg`: `cdab0150c1ed8840f330d332df4bbb653ed38fc88f5e24277cd9b4edc9352813`

## Disclaimer

This is an unofficial project and is not affiliated with Radio Record. The Radio Record name, logo, audio streams, and metadata belong to their respective owner.

Название Radio Record, логотип, аудиопотоки и метаданные принадлежат правообладателю. Это неофициальный проект, не связанный с Radio Record.

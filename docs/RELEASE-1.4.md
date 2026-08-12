# Record 1.4

[Русский](#русский) · [English](#english)

## Русский

Нативный неофициальный плеер Radio Record для macOS. Работает без браузера и вебвью.

### Установка

1. Скачайте `Record-1.4.dmg` в разделе Assets ниже.
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

- Нативный Liquid Glass на macOS 26 с группировкой поверхностей через `GlassEffectContainer`.
- Системное скругление окна без дополнительной рамки и второго канта.
- Русский и английский интерфейс с автоматическим выбором языка macOS.
- Системные формы множественного числа через String Catalog и правила CLDR.
- Поддержка VoiceOver, клавиатурной навигации, Reduce Motion, Reduce Transparency и повышенного контраста.
- Исправлен переход AirPods в режим пространственного аудио.
- Обновлены README, установка, описание API и галерея скриншотов.

### Возможности

- Все 117 станций с поиском, жанрами и избранным.
- Плейлист станции за последние сутки.
- История треков и локальная статистика прослушивания.
- Мини-плеер и управление из строки меню.
- Медиаклавиши и панель «Сейчас исполняется».
- Четыре уровня качества потока.
- Переподключение после сетевого сбоя или сна Mac.

### Проверено

- Релизная сборка с `-warnings-as-errors`.
- Подпись через `codesign --verify --deep --strict`.
- Целостность образа через `hdiutil verify`.
- Русская и английская локализации.
- Системные формы числа в обеих локалях.
- Запуск приложения непосредственно из смонтированного DMG.

## English

An unofficial native Radio Record player for macOS. No browser or web view required.

### Installation

1. Download `Record-1.4.dmg` from the Assets section below.
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

- Native Liquid Glass on macOS 26 with surfaces grouped through `GlassEffectContainer`.
- System window corners without a duplicate border.
- Russian and English interfaces that follow the selected macOS language.
- System plural rules through String Catalog and CLDR categories.
- VoiceOver, keyboard navigation, Reduce Motion, Reduce Transparency, and increased contrast.
- Fixed AirPods switching to spatial audio.
- Updated README, installation guide, API notes, and screenshot gallery.

### Features

- All 117 stations with search, genres, and favorites.
- Station playlist for the last 24 hours.
- Track history and local listening statistics.
- Mini player and menu bar controls.
- Media keys and the Now Playing panel.
- Four stream quality levels.
- Automatic reconnection after network errors or Mac sleep.

### Verified

- Release build with `-warnings-as-errors`.
- Signature check with `codesign --verify --deep --strict`.
- Disk image integrity with `hdiutil verify`.
- Russian and English localizations.
- System plural forms in both locales.
- App launch directly from the mounted DMG.

## Disclaimer

This is an unofficial project and is not affiliated with Radio Record. The Radio Record name, logo, audio streams, and metadata belong to their respective owner.

Название Radio Record, логотип, аудиопотоки и метаданные принадлежат правообладателю. Это неофициальный проект, не связанный с Radio Record.

# Record 1.9

[Русский](#русский) · [English](#english)

## Русский

Нативный неофициальный плеер Radio Record для macOS. Работает без браузера и вебвью.

### Обновление

Если Record уже установлен, обновление придёт само: приложение проверяет канал
обновлений раз в сутки. Можно и вручную — меню **Record → Проверить обновления…**

### Установка

1. Скачайте `Record-1.9.dmg` в разделе Assets ниже.
2. Откройте образ и перетащите Record в папку «Программы».
3. При первом запуске нажмите на приложение правой кнопкой мыши и выберите **Открыть**.
4. Подтвердите запуск в появившемся окне.

У сборки локальная ad-hoc подпись, но нет сертификата Apple Developer ID и
нотарификации. Поэтому Gatekeeper может показать предупреждение. Эти действия
нужны только при первом запуске.

Если macOS продолжает блокировать приложение:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Требуется macOS 14 или новее.

### Что нового

Верхняя панель окна вернулась к системному виду.

- Поле поиска и элемент сортировки больше не сжимаются по вертикали. Сжатие на
  8% искажало пропорции шрифта и рамки, из-за чего оба элемента выглядели
  чужими среди системных.
- Снята обрезка по собственному радиусу: она срезала кант контрола и кольцо
  фокуса, которые macOS рисует сама.
- Полю поиска вернули подсказку. Без неё `NSSearchField` центрирует лупу
  посреди поля, и раньше это обходили самодельной иконкой поверх поля с
  отключением штатной кнопки поиска. Теперь поле полностью системное — со своей
  лупой, кнопкой очистки, фокусом и меню недавних запросов.
- Размеры элементов панели приведены к одному, поэтому выравнивать высоту
  масштабированием больше не нужно.

### Проверено

- Релизная сборка с `-warnings-as-errors`.
- Модульные тесты.
- Подпись через `codesign --verify --deep --strict`.
- Целостность образа через `hdiutil verify`.
- Подпись EdDSA в канале обновлений.

## English

An unofficial native Radio Record player for macOS. No browser or web view required.

### Updating

If Record is already installed, the update arrives on its own: the app checks the
update feed once a day. You can also check manually via **Record → Check for
Updates…**

### Installation

1. Download `Record-1.9.dmg` from the Assets section below.
2. Open the disk image and drag Record to Applications.
3. On first launch, right-click the app and choose **Open**.
4. Confirm the launch in the macOS dialog.

The build has a local ad-hoc signature, but it is not signed with an Apple
Developer ID certificate and is not notarized. Gatekeeper may display a warning.
These steps are only required for the first launch.

If macOS continues to block the app:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Record requires macOS 14 or later.

### What is new

The window toolbar looks native again.

- The search field and sort control are no longer squeezed vertically. The 8%
  squeeze distorted their font and bezel proportions, making both look foreign
  next to system controls.
- Removed the custom corner clipping that cut off the control bezel and the
  focus ring macOS draws itself.
- The search field regains its placeholder. Without one, `NSSearchField` centers
  the magnifier in the middle of the field; this used to be worked around with a
  hand-drawn icon on top and the system search button disabled. The field is now
  fully native, with its own magnifier, clear button, focus, and recent searches.
- Toolbar controls share a single control size, so no scaling is needed to line
  up their heights.

### Verified

- Release build with `-warnings-as-errors`.
- Unit tests.
- Signature check with `codesign --verify --deep --strict`.
- Disk image integrity with `hdiutil verify`.
- EdDSA signature in the update feed.

## Disclaimer

This is an unofficial project and is not affiliated with Radio Record. The Radio
Record name, logo, audio streams, and metadata belong to their respective owner.

Название Radio Record, логотип, аудиопотоки и метаданные принадлежат
правообладателю. Это неофициальный проект, не связанный с Radio Record.

# Record 2.1

[Русский](#русский) · [English](#english)

## Русский

Нативный неофициальный плеер Radio Record для macOS. Работает без браузера и вебвью.

### Обновление

Если Record уже установлен, обновление придёт само — приложение проверяет канал
раз в сутки. Вручную: меню **Record → Проверить обновления…**

### Установка

1. Скачайте `Record-2.1.dmg` в разделе Assets ниже.
2. Откройте образ и перетащите Record в папку «Программы».
3. При первом запуске нажмите на приложение правой кнопкой мыши и выберите **Открыть**.
4. Подтвердите запуск в появившемся окне.

У сборки локальная ad-hoc подпись, без сертификата Apple Developer ID и
нотарификации, поэтому Gatekeeper может предупредить. Это нужно только один раз.

Если macOS продолжает блокировать приложение:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Требуется macOS 14 или новее.

### Что нового

**Экран красится в цвета обложки.** Откройте станцию на весь экран — фон
подхватит цвета текущего трека, как это делает развёрнутый плеер Apple Music.
Тёплая обложка даёт тёплый фон, серо-синяя — серо-синий, чёрно-белая честно
оставляет экран серым: выдуманных оттенков нет. При смене трека фон
переливается за две трети секунды.

То же самое на странице подкаста — там цвет идёт за обложкой играющего выпуска.

**Каталог не тронут.** Цветной фон живёт только в полноразмерных экранах, где
обложка и есть главный объект. Список станций остался обычным полупрозрачным
окном macOS, сквозь которое видны обои рабочего стола.

### Как это сделано

Обложка ужимается до 32×32, и тысяча пикселей раскладывается по корзинам
оттенка. Кластеризации нет намеренно: на такой выборке она ничего не добавляет,
а разбор должен стоить доли миллисекунды — на радио трек меняется каждые три
минуты. Палитра считается один раз на обложку и кэшируется.

Три места, где легко ошибиться, сделаны явно: оттенок усредняется через вектор
(иначе красный из 359° и 1° превращается в бирюзовый), основа берётся из
доминирующей корзины, а не из среднего по картинке (среднее у красно-зелёной
обложки — бурая грязь), и полупрозрачные пиксели делятся на альфу (иначе
сглаженный край белого логотипа читается серым).

Верхние границы яркости держат белый текст читаемым даже на кислотной обложке,
а при включённом повышенном контрасте цвет приглушается вдвое.

### Проверено

- Релизная сборка с `-warnings-as-errors` и 27 модульных тестов, из них
  одиннадцать — на разбор палитры.
- Подпись через `codesign --verify --deep --strict`.
- Целостность образа через `hdiutil verify`.
- Подпись EdDSA в канале обновлений.
- Живые обложки: тёплая, серо-синяя, кремовая — фон совпадает с каждой.

## English

An unofficial native Radio Record player for macOS. No browser or web view required.

### Updating

If Record is already installed, the update arrives on its own — the app checks the
feed once a day. Manually: **Record → Check for Updates…**

### Installation

1. Download `Record-2.1.dmg` from the Assets section below.
2. Open the disk image and drag Record to Applications.
3. On first launch, right-click the app and choose **Open**.
4. Confirm the launch in the macOS dialog.

The build has a local ad-hoc signature, without an Apple Developer ID certificate
or notarization, so Gatekeeper may warn you. This is needed only once.

If macOS keeps blocking the app:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Record requires macOS 14 or later.

### What is new

**The screen takes on the artwork's colors.** Open a station full-screen and the
background picks up the colors of the current track, the way the expanded Apple
Music player does. A warm cover gives a warm background, a blue-grey one gives
blue-grey, and a black-and-white cover honestly leaves the screen grey — no
invented hues. The background cross-fades over two thirds of a second when the
track changes.

The same applies to the podcast page, where the color follows the playing
episode's artwork.

**The catalog is untouched.** The tint lives only in the full-size views, where
the artwork is the point of the screen. The station list stays the same
translucent macOS window with your desktop showing through.

### How it works

The artwork is scaled down to 32×32 and a thousand pixels are sorted into hue
buckets. Clustering is deliberately absent: on a sample this small it adds
nothing, and the analysis has to cost a fraction of a millisecond — a radio track
changes every three minutes. The palette is computed once per artwork and cached.

Three easy mistakes are handled explicitly: hue is averaged as a vector (plain
averaging turns red at 359° and 1° into cyan), the base color comes from the
dominant bucket rather than the image mean (the mean of a red-and-green cover is
brown mud), and semi-transparent pixels are divided by alpha (otherwise the
anti-aliased edge of a white logo reads as grey).

Upper brightness bounds keep white text readable even on an acid-bright cover,
and the tint dims by half when increased contrast is enabled.

### Verified

- Release build with `-warnings-as-errors` and 27 unit tests, eleven of them
  covering palette extraction.
- Signature check with `codesign --verify --deep --strict`.
- Disk image integrity with `hdiutil verify`.
- EdDSA signature in the update feed.
- Live artwork: warm, blue-grey, and cream covers each produced a matching background.

## Disclaimer

This is an unofficial project and is not affiliated with Radio Record. The Radio
Record name, logo, audio streams, and metadata belong to their respective owner.

Название Radio Record, логотип, аудиопотоки и метаданные принадлежат
правообладателю. Это неофициальный проект, не связанный с Radio Record.

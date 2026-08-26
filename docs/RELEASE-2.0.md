# Record 2.0

[Русский](#русский) · [English](#english)

## Русский

Нативный неофициальный плеер Radio Record для macOS. Работает без браузера и вебвью.

### Обновление

Если Record уже установлен, обновление придёт само — приложение проверяет канал
раз в сутки. Вручную: меню **Record → Проверить обновления…**

### Установка

1. Скачайте `Record-2.0.dmg` в разделе Assets ниже.
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

**Чарты.** Новый раздел с тремя вкладками: Суперчарт, Клаб чарт и Новинки.
У каждой позиции обложка, переход в Apple Music и тридцатисекундный фрагмент —
полного трека радио не отдаёт, и выдавать фрагмент за что-то большее нечестно.
Фрагмент играет отдельный плеер и ставит эфир на паузу: звучать должно что-то одно.

**Подкасты.** Десять шоу с обложками, внутри — выпуски с датой, длительностью и
раскрывающимся составом. Есть поиск по названиям и содержимому, группировка по
дням. Каталог кэшируется и открывается без сети.

**Воспроизведение выпусков.** Перемотка полосой и кнопками ±15 секунд,
продолжение с места остановки, отметка прослушанного. Позиция сохраняется между
запусками и переживает обрыв связи, сон Mac и смену сети — выпуск идёт сорок
минут, и терять их недопустимо. Автоперехода к следующему выпуску нет намеренно.

**Системная панель.** Для выпусков показывает реальную длительность и позицию,
работают перемотка и ⏪⏩ из Пункта управления. Для эфира всё как раньше.

### Что осталось прежним

Радио не изменилось: те же станции, переподключение, восстановление после сна,
медиаклавиши и AirPods. Различие между бесконечным потоком и файлом проведено
явным типом источника, а не флагом в глубине плеера.

### Проверено

- Релизная сборка с `-warnings-as-errors` и модульные тесты.
- Подпись через `codesign --verify --deep --strict`.
- Целостность образа через `hdiutil verify`.
- Подпись EdDSA в канале обновлений.
- Перемотка по сети: сервер отвечает `206 Partial Content`.

## English

An unofficial native Radio Record player for macOS. No browser or web view required.

### Updating

If Record is already installed, the update arrives on its own — the app checks the
feed once a day. Manually: **Record → Check for Updates…**

### Installation

1. Download `Record-2.0.dmg` from the Assets section below.
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

**Charts.** A new section with three tabs: Superchart, Club Chart, and New
Releases. Every entry has cover art, an Apple Music link, and a 30-second
preview — the station does not serve full tracks, and presenting a preview as
anything more would be dishonest. Previews play through a separate player and
pause the radio: only one thing should be audible.

**Podcasts.** Ten shows with cover art; inside, episodes with date, duration, and
expandable contents. Search covers titles and contents, and episodes are grouped
by day. The catalog is cached and opens without a network connection.

**Episode playback.** Scrubbing and ±15-second buttons, resume from where you
stopped, played marks. Position survives app restarts, connection drops, Mac
sleep, and network changes — an episode runs forty minutes and losing that is not
acceptable. There is deliberately no auto-advance to the next episode.

**System panel.** For episodes it shows real duration and position, with seeking
and ⏪⏩ from Control Center. For live radio everything works as before.

### What stayed the same

Radio is unchanged: same stations, reconnection, wake recovery, media keys, and
AirPods behavior. The difference between an endless stream and a file is carried
by an explicit source type rather than a flag buried in the player.

### Verified

- Release build with `-warnings-as-errors` and unit tests.
- Signature check with `codesign --verify --deep --strict`.
- Disk image integrity with `hdiutil verify`.
- EdDSA signature in the update feed.
- Network seeking: the server answers with `206 Partial Content`.

## Disclaimer

This is an unofficial project and is not affiliated with Radio Record. The Radio
Record name, logo, audio streams, and metadata belong to their respective owner.

Название Radio Record, логотип, аудиопотоки и метаданные принадлежат
правообладателю. Это неофициальный проект, не связанный с Radio Record.

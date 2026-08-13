# Record 1.7

## Русский

Record теперь умеет обновляться прямо внутри приложения. Канал обновлений и
архивы подписаны отдельным EdDSA-ключом, а установка выполняется через Sparkle.

### Что нового

- Автоматическая проверка обновлений раз в сутки.
- Стеклянная панель в стиле приложения с описанием новой версии.
- Действия «Обновить», «Напомнить завтра» и «Пропустить эту версию».
- Прогресс загрузки, подготовки и установки.
- Ручная проверка через меню `Record > Проверить обновления…`.
- Настройки автоматической проверки и фоновой загрузки.
- Подписанный HTTPS appcast и обязательная проверка EdDSA перед распаковкой.

### Установка

Для первой установки скачайте `Record-1.7.dmg`, перенесите Record в «Программы»,
затем нажмите на приложение правой кнопкой мыши и выберите «Открыть».

У приложения ad-hoc подпись, нет Developer ID и нотарификации. Это личная
тестовая сборка. Если macOS продолжает блокировать первый запуск:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Следующие версии можно будет устанавливать из самого Record.

## English

Record can now update itself without sending you to a browser. The update feed
and archives are protected with a dedicated EdDSA key, while Sparkle handles
download, validation, installation, and relaunch.

### What is new

- Automatic update checks once a day.
- A glass update panel matching the rest of the app.
- Update, Remind Me Tomorrow, and Skip This Version actions.
- Download, preparation, and installation progress.
- Manual checks from `Record > Check for Updates…`.
- Settings for automatic checks and background downloads.
- A signed HTTPS appcast with mandatory EdDSA verification before extraction.

### Installation

For the first installation, download `Record-1.7.dmg`, drag Record to
Applications, then right-click the app and choose Open.

The app uses an ad-hoc signature and is not signed with Developer ID or
notarized. This is a personal test build. If macOS still blocks the first launch:

```bash
xattr -dr com.apple.quarantine /Applications/Record.app
```

Future versions can be installed from within Record.

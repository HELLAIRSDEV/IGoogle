# IGoogle

Полная интеграция **Pixel (Android) → MacBook** в духе связки iPhone ↔ Mac:

| # | Возможность | Статус | Где реализовано |
|---|-------------|--------|-----------------|
| 1 | Общий буфер обмена | ✅ работает | `IGoogleHub` (macOS) + `ClipboardSync` (Android) |
| 2 | AirDrop-передача файлов Pixel → MacBook | ✅ работает | `file_meta` + бинарные кадры → `~/Downloads/IGoogle` |
| 3 | Анимации | ✅ | SwiftUI (`ContentView.swift`), Compose (`IGoogleScreen.kt`) |
| 4 | Бесшовный режим (keep-alive, без обрывов) | ✅ | ping/pong, `pingInterval`, авто-reconnect |
| 5 | В меню «Поделиться» пункт «Отправить на MacBook» | ✅ | `ShareToMacActivity` + intent-filter `ACTION_SEND` |

## Архитектура

```
IGoogle/
├── macos/          # SwiftUI-приложение на Mac (хаб)
│   ├── Package.swift
│   └── Sources/
│       ├── IGoogleCore/      # без UI: WebSocket-сервер, Bonjour, буфер, протокол
│       │   ├── Models.swift        # протокол (зеркалит shared/Protocol.kt)
│       │   ├── WebSocket.swift     # рукописный WS-сервер поверх Network.framework
│       │   ├── FileTransfer.swift  # бинарные кадры файлов (UUID + offset + данные)
│       │   ├── ClipboardMonitor.swift
│       │   └── IGoogleHub.swift    # оркестратор
│       └── IGoogleApp/       # SwiftUI + анимации
└── shared/         # Kotlin Multiplatform — общий протокол и логика
│   └── src/
│       ├── commonMain/      # Protocol.kt, TransferEngine.kt, Platform.kt
│       ├── androidMain/     # actual-реализации для Android
│       └── macosMain/       # actual-реализации для macOS (фреймворк IGoogleShared)
└── android/        # Android-приложение (Compose)
    └── src/main/kotlin/com/igoogle/android/
        ├── IGoogleController.kt   # аналог IGoogleHub
        ├── NsdDiscovery.kt        # NSD (находит Mac)
        ├── WebSocketClient.kt     # OkHttp WS-клиент (текст + бинарные кадры)
        ├── ClipboardSync.kt       # слушатель буфера
        ├── FileTransfer.kt        # отправка/приём файлов (MediaStore Downloads)
        └── share/ShareToMacActivity.kt  # «Отправить на MacBook»
```

### Как устроена кроссплатформенность

Общий модуль `shared` (Kotlin Multiplatform) содержит **сетевой протокол и логику
синхронизации один раз**. Android использует его напрямую (JVM), а для macOS он
компилируется во фреймворк `IGoogleShared`. В текущей сборке Mac-приложение
реализует тот же протокол на Swift (`Models.swift`), чтобы его можно было
собрать без Gradle/Java — но JSON-контракт у обеих сторон идентичен.

Ключевое правило: **`shared/src/commonMain/.../Protocol.kt` и
`macos/Sources/IGoogleCore/Models.swift` должны всегда совпадать** (имена полей,
`SerialName`/raw value, типы). Для этого оба файла снабжены комментариями.

## Сетевой протокол

Транспорт — **WebSocket** по локальной сети. Mac — сервер (объявляется через
Bonjour `_igoogle._tcp`), Pixel — клиент (находит Mac через NSD).

Сообщения — JSON в текстовых кадрах:

```json
{ "type": "clipboard", "timestamp": 1712345678.0,
  "device": { "id": "android-…", "name": "Pixel 8", "platform": "android" },
  "clipboard": { "text": "привет", "timestamp": 1712345678.0 } }
```

Типы: `hello`, `goodbye`, `clipboard`, `ping`, `pong`, `file_meta`, `ack`.

Файлы передаются так: `file_meta` (имя/размер/mime) → подтверждение `ack` →
бинарные кадры в формате `[16 байт UUID файла][8 байт offset][данные…]`.
Получатель собирает кадры и сохраняет файл.

## Сборка macOS

Требуется Xcode (для SwiftUI-макросов) либо только Command Line Tools для ядра.

```bash
cd macos
swift build --target IGoogleCore   # собрать ядро без UI
swift run IGoogle                  # запустить приложение (нужен Xcode для @State)
```

Проверка сетевого ядра без Xcode (запускает живой WS-сервер + клиент):

```bash
cd ..
swiftc -o /tmp/igoogle-verify \
  macos/Sources/IGoogleCore/Models.swift \
  macos/Sources/IGoogleCore/WebSocket.swift \
  macos/Sources/IGoogleCore/FileTransfer.swift \
  verify/main.swift \
  -framework Network -framework CryptoKit
/tmp/igoogle-verify
```

## Сборка Android + shared

Нужны **JDK 21** и Android Studio (или Gradle 8.9). JDK 21 обязателен: Gradle 8.9
не поддерживает Java 23+. Если в Android Studio стоит JDK 25 — выбери **Use JVM 21**
в диалоге импорта (или Settings → Build Tools → Gradle → Gradle JDK = 21).

```bash
# сгенерировать wrapper (однократно)
gradle wrapper --gradle-version 8.9

# собрать всё
./gradlew :android:assembleDebug

# собрать macOS-фреймворк общего модуля (для Swift)
./gradlew :shared:linkDebugFrameworkMacosArm64
```

Откройте папку `IGoogle` в Android Studio — проекты `:shared` и `:android`
подхватятся автоматически.

## Что уже работает / что дальше

- ✅ **Буфер обмена в обе стороны** по локальной сети (проверено живым тестом ядра).
- ✅ **Передача файлов в обе стороны** (Pixel → Mac и Mac → Pixel) с записью в
  `~/Downloads/IGoogle` (Mac) и `Загрузки/IGoogle` (Android).
- ✅ Обнаружение устройств (Bonjour ↔ NSD).
- ✅ «Отправить на MacBook» в системном share-меню Android (текст и файлы).
- ✅ Keep-alive и анимации.
- 🧱 Авто-reconnect на Android при обрыве сети (сейчас — через повторное
  обнаружение NSD).

## Как скачать и пользоваться

### Mac (приложение-хаб)

1. Установите **Xcode** (App Store) — он нужен для SwiftUI-части.
2. Скачайте папку проекта `IGoogle` (весь репозиторий целиком).
3. Откройте `IGoogle/macos/Package.swift` в Xcode (двойной клик или
   `open macos/Package.swift`).
4. Выберите схему **IGoogle** → запустите (▶). Появится окно IGoogle — оно
   начнёт «слушать» локальную сеть и ждать Pixel.

> Если Mac не видит Pixel — разрешите входящие подключения:
> «Системные настройки → Сеть → Брандмауэр» и разрешите IGoogle,
> либо временно выключите брандмауэр.

### Pixel (Android-приложение)

1. Установите **Android Studio**.
2. Откройте в нём папку `IGoogle` (не подпапку) — проекты `:shared` и `:android`
   подхватятся сами.
3. Подключите Pixel по USB (режим «Передача файлов» + отладка по USB) и нажмите
   **Run ▶** — или соберите APK:
   ```bash
   ./gradlew :android:assembleDebug
   # APK: android/build/outputs/apk/debug/android-debug.apk
   ```
   APK можно перекинуть на Pixel и установить вручную.
4. Оба устройства должны быть **в одной Wi-Fi-сети**.

### Как пользоваться

- **Буфер обмена**: скопировали текст на Pixel → он сам появился на Mac
  (и наоборот). Ничего нажимать не нужно.
- **Файл Pixel → Mac**: в любом приложении нажмите «Поделиться» → выберите
  **«Отправить на MacBook»**. Файл сохранится в `~/Downloads/IGoogle`.
- **Файл Mac → Pixel**: перетащите файл в пунктирную зону в окне IGoogle.
- **Бесшовный режим** (в настройках) держит соединение живым (keep-alive).

## Частые проблемы

- **Pixel не находит Mac.** Чаще всего виноват **VPN** (Happ/Hiddify и т.п.) — TUN
  перехватывает mDNS/Bonjour. Отключи VPN на обоих устройствах или включи в нём
  «Bypass LAN» / «Не проксировать локальную сеть». Проверь, что оба в одной Wi‑Fi.
- **`CLEARTEXT communication not permitted`.** Уже решено: в манифесте
  `android:usesCleartextTraffic="true"`.
- **`commonizeNativeDistribution` / Kotlin-плагин грузится дважды.** Уже решено:
  версии плагинов вынесены в корневой `build.gradle.kts`, а macOS-нативные таргеты
  в `shared` отключены (см. комментарий в `shared/build.gradle.kts`).
- **Связь рвётся в фоне.** Пока приложение держи открытым: WebSocket живёт, пока
  IGoogle на экране. Фоновый режим (foreground-service) — следующий шаг.

## Безопасность

Трафик ходит по локальной сети без шифрования и без аутентификации — как у
обычного AirDrop-прототипа. Для продакшена добавьте TLS + парную кнопку
подтверждения (PIN) по аналогии с KDE Connect.

# Релиз IGoogle

## Артефакты

После `./scripts/release.sh` в `dist/`:

- `IGoogle-0.1.0-macos.dmg` — приложение для Mac (перетащить в Applications).
- `IGoogle-0.1.0-android.apk` — подписанный APK для Pixel (sideload).

> `.dmg` и `.apk` **не коммитятся** (в `.gitignore`) — они прикладываются к GitHub Release.

## Сборка релиза

```bash
VERSION=0.1.0 ./scripts/release.sh
```

Требуется: Xcode (для SwiftUI-макросов), JDK 21, Android SDK, Gradle 8.9
(появляется после первого открытия проекта в Android Studio), и файл
`keystore.properties` + `keystore.jks` для подписи APK (в `.gitignore`).

## Публикация на GitHub

Нужен свой репозиторий и авторизация (`gh auth login` или HTTPS-токен).

```bash
# 1) Создать репозиторий и запушить (вариант через gh):
gh repo create IGoogle --public --source=. --remote=origin --push

#    либо вручную, если репозиторий уже создан на github.com:
git remote add origin https://github.com/<USER>/IGoogle.git
git push -u origin main
git push origin v0.1.0

# 2) Создать GitHub Release с артефактами:
gh release create v0.1.0 \
  dist/IGoogle-0.1.0-android.apk \
  dist/IGoogle-0.1.0-macos.dmg \
  --title "IGoogle v0.1.0" \
  --notes-file CHANGELOG.md
```

Либо без `gh` — через веб-интерфейс GitHub: **Releases → Draft a new release →
выбрать тег `v0.1.0` → прикрепить `.apk` и `.dmg`**.

## Версии

- Версия Mac: `macos/Packaging/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`).
- Версия Android: `android/build.gradle.kts` (`versionName`, `versionCode`).
- Тег: `git tag -a vX.Y.Z -m "IGoogle vX.Y.Z"`.

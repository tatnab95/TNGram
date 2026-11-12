# Тнграм

Приватный мессенджер. Сообщение уходит на сервер, доходит до получателя и сразу удаляется с сервера. Переписка хранится только на устройствах участников. Номер телефона не нужен, вход по нику.

Есть четыре варианта программы:
- **Android** — APK-файл для телефона;
- **Windows** — `TNGram.exe`;
- **Linux** — `TNGram.x86_64`;
- **Веб** — мессенджер прямо в браузере на сайте.

Все они говорят с одним облаком (Supabase), поэтому сообщения доходят между ними.

## Что где лежит

| Папка / файл | Что это |
|---|---|
| `tn-gram_godot/` | Сама программа (Godot 4.7, язык GDScript). Для Android, Windows и Linux. |
| `сайт/` | Сайт: лендинг, веб-мессенджер (`web_app.js`, `web_app.css`), файл версии `version.json`, APK для скачивания. |
| `supabase/` | SQL для облака: таблицы и правила доступа. Выполняется один раз в Supabase. |
| `.github/workflows/` | Автоматика GitHub: `pages.yml` публикует сайт, `keepalive.yml` раз в сутки «будит» облако. |
| `README.md` | Этот файл. GitHub показывает его на главной странице репозитория. |

## Как запустить

- **Сайт / веб-мессенджер:** открой `https://tatnab95.github.io/TNGram/`, а мессенджер — с хвостом `#messenger`.
- **Компьютер из исходников:** открой папку `tn-gram_godot` в Godot 4.7 и нажми F5. Либо запусти `tn-gram_godot\run.bat`.
- **Android:** скачай `TNGram.apk` со страницы сайта или из релиза, открой на телефоне и разреши установку из неизвестных источников.

## Как собрать программу

Нужны Godot 4.7 с шаблонами экспорта и Android Studio (для Android).

```
Windows:  godot --headless --path tn-gram_godot --export-release "Windows Desktop" build/TNGram.exe
Linux:    godot --headless --path tn-gram_godot --export-release "Linux" build/TNGram.x86_64
Android:  godot --headless --path tn-gram_godot --export-debug "Android" build/TNGram.apk
```

Для Android перед экспортом укажи в Godot пути к Java (`jbr` из Android Studio) и Android SDK. Подробно — в `tn-gram_godot/build/ANDROID-КАК-СОБРАТЬ.txt`.

Сборки складываются в `tn-gram_godot/build/`. Эта папка не попадает в git: файлы больше 100 МБ GitHub не принимает.

## Как обновить версию

Версия хранится в трёх местах, их нужно менять вместе:
1. `tn-gram_godot/scripts/net/Protocol.gd` — `APP_VERSION` и запись в `CHANGELOG`.
2. `tn-gram_godot/export_presets.cfg` — `version/name` и `version/code` (код для Android должен расти при каждом выпуске).
3. `сайт/version.json` — номер, который видят приложения и сайт.

## Выпуск релиза (пошагово)

Релиз нужен, чтобы люди могли скачать большие файлы для ПК и Linux.

1. Собери программу (см. выше) и проверь, что файлы открываются.
2. Обнови версию в трёх местах из раздела выше.
3. Закоммить и запушь изменения в `main`. Сайт обновится сам.
4. Открой репозиторий на GitHub → **Releases** → **Draft a new release**.
5. В поле **Choose a tag** введи, например, `v2.1`, выбери **Create new tag**.
6. В **Release title** напиши `Тнграм 2.1`, в описании — что нового.
7. Перетащи в блок **Attach binaries** файлы `TNGram.exe`, `TNGram.x86_64` и `TNGram.apk`.
8. Нажми **Publish release**.

Ссылки на файлы будут вида `https://github.com/tatnab95/TNGram/releases/download/v2.1/TNGram.exe`.

## Публикация сайта

Один раз: **Settings → Pages → Source: GitHub Actions** и репозиторий должен быть **Public**. После этого каждый пуш в `main` обновляет сайт.

## Облако

Облако — Supabase, бесплатный тариф. Ключи в приложении и на сайте публичные (publishable), это нормально: защищает правило доступа в таблицах. Таблицы создаются скриптами из папки `supabase/`. Выпуск новой версии облако может сообщить через таблицу `version`.

## Лицензия

Лицензия не выбрана, поэтому все права принадлежат автору. Если хочешь открыть код для других, добавь файл `LICENSE` (например, MIT) через **Add file → Create new file** в GitHub.

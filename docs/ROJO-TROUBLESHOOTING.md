# Rojo: NetFail и рабочая синхронизация

Симптом из Output:
    [Rojo-Warn] Disconnected from an error: Unknown HTTP error: HttpError: NetFail

Это значит: плагин в Studio не смог достучаться до процесса `rojo serve`. Не ошибка кода.

## Почему это случилось у нас

Патч применяется через `git am` и **пересоздаёт** `default.project.json`
(rename в legacy + новый файл). Файловый watcher Rojo переживает такое плохо и умирает.
Правило: **после каждого `git am` перезапускай `rojo serve`**.

Второй симптом того же корня: `Infinite yield possible on WaitForChild("services")`.
Так выглядит Play, запущенный посреди синка: скрипты уже приехали, содержимое папок ещё нет.

## Чеклист по порядку

1. Процесс жив? Терминал с `rojo serve` открыт, без ошибок и без Ctrl+C.
       rojo serve default.project.json --port 34872
2. Отвечает ли HTTP? Открой в браузере `http://127.0.0.1:34872/`.
   Нет ответа — проблема на стороне serve, а не Studio.
3. Хост. В настройках плагина укажи `127.0.0.1` вместо `localhost`:
   `localhost` может резолвиться в IPv6 `::1`, который serve не слушает.
4. Порт. Плагин по умолчанию 34872. Порт в `--port` и в плагине должен совпадать.
5. Версии. `rojo --version` и версия плагина должны быть одной мажорной линии (7.x с 7.x).
6. WSL / Docker. Если serve внутри WSL2, а Studio на Windows — loopback не прокинется сам.
   Запускай serve в Windows либо пробрасывай порт явно.
7. Firewall / антивирус. Разреши `rojo.exe` входящие на loopback.
8. VPN / прокси. Отключи: некоторые клиенты перехватывают даже localhost.
9. Перезапуск обеих сторон. Закрой вкладку синка в плагине, останови serve, подними serve, подключись заново.

## Надёжный путь без живого синка

Если NetFail не чинится за 10 минут — не блокируй разработку инфраструктурой:

    rojo build default.project.json -o build/ragdoll-dodgeball.rbxlx

Открой `.rbxlx` в Studio: всё дерево внутри файла, синк не нужен.
Итерация: правишь код в редакторе → `rojo build` → открываешь свежий place.
Хелперы: `tools/build.ps1` (Windows) и `tools/build.sh` (macOS / Linux).

`build/` уже в `.gitignore`, артефакты в репозиторий не попадут.

## Проверка результата

`tools/doctor.lua` в Command Bar (режим Edit) печатает:
- какие модули реально лежат в Shared / Server / Client,
- чего не хватает,
- дубликаты имён (резолвер возьмёт первый попавшийся — это ловушка),
- неверные типы инстансов и отключённые скрипты,
- вердикт: готово к запуску или нет.

## Ожидаемый Output при успешном старте

    [Bootstrap] модули под Server: AbilityService, AntiCheat, BallService, BotController,
                  CatchService, MatchService, RagdollService, RoundService
    [Client] модули под PlayerScripts: HUDController, InputController
    [RagdollDodgeball] v0.2.1 запущен: матч, ловля, боты, ульты
    [RagdollDodgeball] Клиент v0.2.1 готов

Ошибки `ContentId: rbxassetid://...` относятся к ассетам аватара и на игру не влияют.

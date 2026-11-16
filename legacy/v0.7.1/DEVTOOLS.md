# DEVTOOLS — как запускать инструменты

## Главное правило

**Command Bar выполняет код Luau, а не путь к файлу.**
Строка `tools/perf-setup.lua` разбирается как `tools / perf - setup.lua` — выражение
без присваивания и без вызова. Отсюда `Incomplete statement: expected assignment or a function call`.

Раньше инструменты лежали в `tools/*.lua` и их надо было копировать целиком.
Теперь они модули в `ServerStorage.DevTools`, и запуск — одна строка.

## Команды

| Контекст | Команда |
|---|---|
| Edit | `require(game.ServerStorage.DevTools).PerfSetup()` |
| Edit | `require(game.ServerStorage.DevTools).Doctor()` |
| Play, Server | `require(game.ServerStorage.DevTools).PerfReport()` |
| Play, Server | `require(game.ServerStorage.DevTools).FunnelReport()` |
| любой | `require(game.ServerStorage.DevTools).Help()` |

Переключение контекста: в Command Bar слева есть выпадающий список Client / Server.
В режиме Edit контекст один и имеет полный доступ к дереву.

## Замер FPS

FPS существует только на клиенте. В Play переключи Command Bar на **Client** и вставь:

    local n,t=0,0 local c c=game:GetService("RunService").RenderStepped:Connect(function(dt) n+=1 t+=dt end) task.delay(1.5,function() c:Disconnect() print(("FPS %.1f"):format(n/t)) end)

Через полторы секунды напечатает средний FPS. Бюджет: 60 на mid-tier Android, 30 минимум.

## Почему ServerStorage, а не ReplicatedStorage

`ServerStorage` не реплицируется клиентам. Эксплойтер не может вызвать `PerfSetup`
и поменять себе стриминг или тени, не может вызвать `Doctor` и разведать структуру проекта.
Инструменты доступны только тебе в Studio и серверному коду.

## Порядок после патча

1. `git am ragdoll-dodgeball-v0.7.1.patch`
2. Перезапусти `rojo serve`, дождись окончания синка.
3. В Edit: `Doctor()` — должен сказать READY.
4. В Edit: `PerfSetup()` — применит бюджет. **Сохрани place.**
5. Play, Server: `PerfReport()` — проверь вердикты.
6. Play, Client: проба FPS.
7. Сыграй матч, выйди, Server: `FunnelReport()`.

## Если модуль не найден

`[DevTools] Module not found` означает, что синк не довёз `src/devtools`.
Проверь, что в `default.project.json` есть маппинг `ServerStorage.DevTools`,
и что Rojo действительно подключён (не отвалился с NetFail).
`Doctor()` покажет, чего именно не хватает.

## Старые файлы в tools/

`tools/perf-setup.lua`, `tools/perf-report.lua`, `tools/funnel-report.lua`, `tools/doctor.lua`
оставлены как есть для тех, кто предпочитает вставлять содержимое вручную.
Они не смаплены в Studio и в игру не попадают. Дублирования логики нет:
модули в `src/devtools` — основной путь, файлы в `tools` — запасной.

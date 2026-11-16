# DEVTOOLS — запуск, кэш модулей и диагностика

## Command Bar выполняет код, а не путь

Строка `tools/perf-setup.lua` разбирается как `tools / perf - setup.lua` — выражение
без присваивания и вызова. Отсюда `Incomplete statement: expected assignment or a function call`.
Инструменты живут в `ServerStorage.DevTools` и вызываются одной строкой.

## Главная ловушка Studio: кэш ошибок модуля

Симптом:

    Requested module experienced an error while loading
    Stack Begin
    Script 'CommandBar', Line 1
    Stack End

Это **не** ошибка твоего кода. Это сообщение означает: модуль уже падал раньше,
Roblox закэшировал failure, и теперь отдаёт заглушку вместо повторной загрузки.
**Текст исходной ошибки при этом теряется** — в логе не будет ни строки, ни причины.

Три способа выйти:

1. **Вызвать дочерний модуль напрямую.** У каждого ModuleScript своя запись в кэше,
   поэтому падение родителя не мешает ребёнку:
       require(game.ServerStorage.DevTools.Doctor).Run()
2. **Загрузить клон.** Клон — новый инстанс, кэш для него чистый, ошибка печатается целиком.
   Именно так работает `DevTools` начиная с v0.7.2.
3. **Инвалидировать кэш вручную.** Открой модуль в редакторе, добавь пробел, сохрани.
   Кэш сбросится, следующая загрузка покажет настоящую ошибку.

## Команды

| Контекст | Команда |
|---|---|
| любой | `require(game.ServerStorage.DevTools).Diagnose()` |
| Edit | `require(game.ServerStorage.DevTools).Doctor()` |
| Edit | `require(game.ServerStorage.DevTools).PerfSetup()` |
| Play, Server | `require(game.ServerStorage.DevTools).PerfReport()` |
| Play, Server | `require(game.ServerStorage.DevTools).FunnelReport()` |
| любой | `require(game.ServerStorage.DevTools).Help()` |

`Diagnose()` грузит все четыре инструмента через клоны, ничего не запускает и ничего не меняет.
Если что-то падает, ты получаешь строку `FAILED PerfReport` и warning с реальным текстом ошибки.
Начинай с него, когда что-то не работает.

Переключатель Client / Server находится слева в Command Bar.

## Замер FPS

FPS существует только на клиенте. В Play переключи Command Bar на **Client**:

    local n,t=0,0 local c c=game:GetService("RunService").RenderStepped:Connect(function(dt) n+=1 t+=dt end) task.delay(1.5,function() c:Disconnect() print(("FPS %.1f"):format(n/t)) end)

Бюджет: 60 на mid-tier Android, 30 минимум.

## Почему клон, а не обычный require

`require` кэширует по инстансу. Для игрового кода это правильно: сервисы должны быть синглтонами.
Для инструментов разработки это вредно: одна transient-ошибка при неполном синке Rojo
отравляет модуль до перезапуска сессии, и ты перестаёшь видеть причину.

Клонирование даёт свежую загрузку каждый вызов. Цена — инструмент не может полагаться на
`script`-relative пути, потому что клон живёт отдельно. Все четыре инструмента используют
абсолютные пути через `game:GetService`, поэтому ограничение соблюдено.

Клон уничтожается после `Run()`, чтобы не оставлять мусор в дереве.

## Почему ServerStorage

`ServerStorage` не реплицируется клиентам. Эксплойтер не вызовет `PerfSetup`,
не поменяет себе стриминг и не разведает структуру проекта через `Doctor`.

## Порядок после патча

1. `git am ragdoll-dodgeball-v0.7.2.patch`
2. Перезапусти `rojo serve`, дождись конца синка.
3. `Diagnose()` — все четыре должны быть OK.
4. `Doctor()` — ждём READY.
5. `PerfSetup()` — применит бюджет. **Сохрани place.**
6. Play, Server: `PerfReport()`.
7. Play, Client: проба FPS.
8. Сыграй матч, выйди, Server: `FunnelReport()`.

## Если инструмент не найден

`[DevTools] Missing module` означает, что синк не довёз `src/devtools`.
Проверь маппинг `ServerStorage.DevTools` в `default.project.json` и что Rojo подключён,
а не отвалился с NetFail. `Diagnose()` печатает список детей контейнера — сразу видно, чего нет.

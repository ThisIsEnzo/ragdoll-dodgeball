# RAGDOLL DODGEBALL

Командные вышибалы с ragdoll-физикой для Roblox. Каждое попадание отправляет соперника
в смешной полёт, а пойманный мяч выбивает бросавшего и воскрешает твоего тиммейта.

Позиционирование: skill-first, матч 5 минут, ноль pay-to-win.

## Документы

| Файл | Что внутри |
|---|---|
| docs/GDD.md | Механики, точные числа баланса, режимы, прогрессия, экономика, FTUE, аналитика |
| docs/TECHPLAN.md | Архитектура, контракт ремоутов, сеть/физика, бюджет производительности, roadmap 10 недель |
| docs/LAUNCH.md | Исследование рынка (ноябрь 2026), KPI-гейты, план запуска и маркетинга |

## Что уже есть в коде

| Модуль | Состояние |
|---|---|
| src/shared/BalanceConfig.lua | Готов. Единый источник всех чисел баланса |
| src/shared/Net.lua | Готов. Обёртка над RemoteEvent / UnreliableRemoteEvent |
| src/server/services/AntiCheat.lua | Готов. Rate-limit по действиям и игрокам |
| src/server/services/RagdollService.lua | Готов. Пре-билд констрейнтов, импульс, восстановление, лимит 8 |
| src/server/services/BallService.lua | Готов. Спавн, владение, бросок, история позиций для lag-comp |
| src/server/services/RoundService.lua | Готов. FSM раунда, учёт живых, sudden death, победитель |
| src/server/Bootstrap.server.lua | Готов. Загрузка сервисов, wiring броска и попадания |

Следующие вехи (ещё не в репо): MatchService (очередь/арены/боты), EconomyService + DataStore,
UI и FTUE, CatchService, AbilityService, аналитика. Порядок — в docs/TECHPLAN.md, раздел B7.

## Быстрый старт

### Вариант A — чистый Roblox Studio
1. Открой Baseplate.
2. ReplicatedStorage → папка Shared → ModuleScript BalanceConfig и Net (вставь содержимое).
3. ServerScriptService → папка Server → Script Bootstrap (содержимое Bootstrap.server.lua).
4. Внутри Server → папка services → ModuleScript на каждый сервис из src/server/services.
5. Workspace → папка Arena с полом и стенами (Anchored), и папка BallSpawns с Part-маркерами.
6. Play. Мячи спавнятся, бросок и ragdoll работают.

### Вариант B — Rojo (рекомендуется)
    rojo serve default.project.json

Подключись плагином Rojo в Studio. Дерево смапится само.

## Правила разработки

1. Сервер — единственный источник истины. Клиент шлёт намерения, не результаты.
2. Никаких магических чисел в коде: всё через BalanceConfig.
3. Каждый новый RemoteEvent закрывается валидацией и rate-limit в тот же день.
4. Прежде чем масштабировать трафик — пройди KPI-гейт из docs/LAUNCH.md.

## Лицензия

Proprietary. Все права защищены.

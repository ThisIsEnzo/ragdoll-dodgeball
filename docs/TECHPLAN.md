# TECH PLAN — MVP под Roblox Studio

## B1. Принципы

1. Сервер — единственный источник истины. Клиент отправляет намерения, не результаты.
2. Один конфиг баланса (BalanceConfig) читают и сервер, и клиент.
3. MVP: один сервер = лобби + N арен. Кросс-серверный матчмейкинг только после PMF.
4. Модули, не монолит: каждый сервис ModuleScript с Init() и Start(), единый бутстрап.
5. Косметика по UnreliableRemoteEvent, геймплей по надёжному каналу.

## B2. Дерево проекта

    ReplicatedStorage/Shared/
      BalanceConfig, Net, Types, BallMath, Signal, Trove
    ServerScriptService/Server/
      Bootstrap (Script)
      services/
        DataService, PlayerService, MatchService, RoundService, BallService,
        ThrowService, CatchService, RagdollService, AbilityService,
        EconomyService, AnalyticsService, AntiCheat
      AI/BotController
    StarterPlayer/StarterPlayerScripts/Client/
      ClientBootstrap
      controllers/
        InputController, CameraController, PredictController,
        RagdollFX, UIController, ClipController

## B3. Контракт ремоутов

| Remote | Направление | Payload | Валидация | Лимит |
|---|---|---|---|---|
| ThrowRequest | C->S | charge, aimDir, clientTime | владение мячом, заряд 0.15-0.9, КД 0.35, нормализация | 4/с |
| CatchRequest | C->S | ballId, clientTime | окно 0.35, дистанция 4, конус 90, скорость <= 110, lag-comp | 3/с |
| DodgeRequest | C->S | dir | КД 3.5, на земле | 2/с |
| UltRequest | C->S | ultId | Hype >= 100, ульта в лоадауте | 1/с |
| QueueJoin | C->S | mode | режим существует, не в матче | 1 / 2 с |
| PartyInvite | C->S | targetUserId | анти-спам | 1 / 3 с |
| ShopBuy | C->S | itemId | цена из серверного каталога, баланс | 2/с |
| QuestClaim | C->S | questId | прогресс проверен сервером | 2/с |
| MatchState | S->C | снапшот | - | 5/с или по изменению |
| FXEvent | S->C | Unreliable | - | без лимита |

Все числа сервер берёт из BalanceConfig, а не из payload.

## B4. Ключевые решения

### Ragdoll
- Пре-билд BallSocketConstraint для каждого Motor6D при спавне (Attachment из C0/C1), Enabled=false.
- Включение: motor.Enabled=false, constraint.Enabled=true, RequiresNeck=false,
  BreakJointsOnDeath=false, AutoRotate=false, ChangeState(Physics), SetStateEnabled(GettingUp,false).
- Импульс на торс, кап 220. Восстановление через 2.5 с.
- Лимит 8 активных ragdoll на арену, остальные в упрощённом стейте.
- Collision groups: Players, Ragdolls, Balls, Arena. Ragdolls между собой не сталкиваются.

### Мяч и сеть
- Мяч всегда server-owned: SetNetworkOwner(nil).
- Клиент рисует предсказанный ghost и плавно реконсилит (lerp 12/с).
- CustomPhysicalProperties: Elasticity 0.6, Friction 0.3, Density 1.
- Кольцевой буфер позиций 1.5 с (30 сэмплов) для компенсации лага при ловле.
- Curve: VectorForce перпендикулярно скорости, не телепорт.

### Ловля с компенсацией лага
    ping = player:GetNetworkPing()
    t = workspace:GetServerTimeNow() - ping
    pos = BallHistory[ballId]:SampleAt(t)
    accept if distance <= 4 and angleOK and speedOK

Без этого при 150 мс на мобилках ловля ощущается сломанной, а это ядро игры.

### Матчмейкинг MVP
Один сервер: лобби + до 4 арен. Старт при 2 живых игроках, остальные слоты — боты.
Бот FSM: SeekBall -> Aim -> Throw -> Evade. Сложность: реакция 0.35-0.8 с, ошибка прицела 3-12 градусов.
Замена бота на игрока между раундами.

### Данные
ProfileStore (или ProfileService) с session-locking, Reconcile по шаблону, версионирование.
Автосейв 60 с + PlayerRemoving + BindToClose.

Схема:
    schemaVersion, coins, xp, level, mmr, rankTier, seasonId,
    loadout { throwType, ult, perks },
    owned { emotes, trails, balls, effects },
    quests { daily, weekly, lastReset },
    streak { day, lastClaim },
    stats { matches, wins, kos, catches, revives },
    passes, rvToday { count, date }, settings

### Производительность (Android mid-tier)
| Метрика | Бюджет |
|---|---|
| Parts на арене | <= 3000, всё Anchored кроме мячей и игроков |
| StreamingEnabled | radius 256, LowMemory |
| Активных ragdoll | <= 8 |
| VFX | пул, <= 60 частиц на событие |
| Remote-трафик | снапшот 5/с, косметика Unreliable |
| FPS | 60 mid-tier, 30 минимум low |

### Анти-чит
Rate-limit на каждый remote, серверные КД, кап скорости мяча, проверка владения,
sanity-check перемещения (delta > 60 studs/с -> rubber-band), экономика только на сервере.

Rewarded Video подключай через официальный plug-and-play формат Creator Hub
(Monetization -> Rewarded Video), награду выдавай только по серверному колбэку.
Точную сигнатуру API сверь в актуальной документации: Roblox менял её в 2026.

## B5. Конфиг
См. src/shared/BalanceConfig.lua — единственный источник чисел.

## B6. FSM раунда
См. src/server/services/RoundService.lua.
Состояния: Warmup -> Live -> SuddenDeath -> RoundEnd -> MatchEnd.

## B7. Roadmap 10 недель

| Неделя | Deliverable | Definition of Done |
|---|---|---|
| 1-2 | Greybox арена, мяч, бросок, ragdoll | 2 игрока кидают мяч, без крашей, 60 FPS на телефоне |
| 3-4 | RoundService, счёт, боты, скамейка | полный 3v3 матч до экрана результатов |
| 5 | Ловля + воскрешение + Hype/ульты | lag-comp честный при 150 мс |
| 6 | DataService, XP, уровни, квесты, шоп | прогресс переживает релог и краш |
| 7 | UI, FTUE, аналитика, локализация | новичок бросает мяч на 8-й секунде |
| 8 | Мобильный ввод, перф, анти-чит | 60 FPS mid-tier, все remote закрыты валидацией |
| 9 | VFX, звук, эмоции, 3 арены, Duel, клипы | 10 смотрибельных клипов с реальных матчей |
| 10 | Софт-лонч, видео, Discord, коды | метрики и воронка FTUE в дашборде |

Гейт перед масштабированием: D1 >= 25%, сессия >= 15 мин, like-ratio >= 85%,
первый матч доигрывают >= 70% новичков, краш-рейт < 1%.

## B8. Инструменты
Rojo + Wally + Git, ProfileStore, TestEZ (тесты на BallMath, экономику, кривые XP),
Creator Analytics (кастомные события и funnel), отдельный эпик Первые 15 минут.

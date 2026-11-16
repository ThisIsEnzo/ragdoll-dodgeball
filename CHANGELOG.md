# CHANGELOG

## v0.2.0 — Sprint 2 "Core"

### Added
- CatchService: ловля мяча с компенсацией лага через историю позиций и GetNetworkPing.
  Успех выбивает бросавшего и воскрешает союзника. Промах даёт стаггер и кулдаун.
- MatchService: очередь, команды, арена-спавны, скамейка, матч до 3 побед, реванш.
- BotController: NPC-боты с FSM Seek / Aim / Throw / Evade.
- AbilityService: Hype-метр и четыре ульта (Cannon, Magnet, Wall, Ghost).
- Клиент: ClientBootstrap, InputController (PC и mobile), HUDController.
- ROADMAP.md: фазы 0-6, спринты, KPI-гейты, контент-кейденс, kill-критерии.

### Changed
- BallService: владение ключуется по персонажу (Model), а не по UserId — нужно для ботов.
  Добавлены атрибуты Clean и Uncatchable, таймаут удержания, GiveBall, ForceRelease, NearestFree.
- Net: добавлены ремоуты PingRequest, RematchRequest, HypeState.
- Bootstrap: переписан, удалена ошибочная строка-заглушка из v0.1, полное связывание сервисов.
- default.project.json: смаплен клиент в StarterPlayerScripts.

### Preserved
- Предыдущие версии Net.lua, BallService.lua, Bootstrap.server.lua и default.project.json
  перенесены в legacy/v0.1/ — ничего не потеряно, можно сравнить и перенести свои правки.

### Known limitations
- Одна арена на сервер. Мульти-арена — S3.
- Экономика и DataStore не подключены: награда за матч только логируется. Это S4.
- Аналитика не подключена. Это S5.
- Sudden death меняет только скорость мячей, геометрия арены не сжимается. Это S3.

## v0.1.0 — Sprint 1
- BalanceConfig, Net, AntiCheat, RagdollService, BallService, RoundService, Bootstrap.
- GDD, TECHPLAN, LAUNCH.

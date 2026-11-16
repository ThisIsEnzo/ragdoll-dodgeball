-- FtueService: онбординг по секундам, dẫn игрока от спавна до первой ловли.
-- Шаги воронки пишет ТОЛЬКО сервер, из реальных геймплейных событий.
-- Клиент получает подсказку и не может сам отметить прогресс.
--
-- Целевая последовательность (GDD A9):
--   0-8s   подбор мяча и первый бросок
--   8-40s  первое выбивание, затем подсказка ловли
--   40s+   первая ловля и воскрешение союзника
--   после 2 матчей подсказки выключаются навсегда

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local AnalyticsService = Resolve.Require(ServerScriptService, "AnalyticsService")
local DataService = Resolve.Require(ServerScriptService, "DataService")

local FtueService = {}

local state: { [number]: any } = {}

local function push(player: Player, hintKey: string?, extra: any?)
	local entry = state[player.UserId]
	if not entry then return end
	Net.FireClient("FtueState", player, {
		hint = hintKey,
		step = entry.step,
		done = entry.done,
		extra = extra,
	})
	if hintKey then
		AnalyticsService.UiMarker(player, "hint_shown")
	end
end

local function currentHint(player: Player): string?
	local entry = state[player.UserId]
	if not entry or entry.done or not CFG.FTUE.Enabled then return nil end

	if not entry.pickedUp then return "ftue.pickup" end
	if not entry.threw then return "ftue.throw" end
	if not entry.ko then return "ftue.ko" end
	if not entry.caught then return "ftue.catch" end
	if not entry.revived then return "ftue.revive" end
	return nil
end

local function refresh(player: Player)
	local entry = state[player.UserId]
	if not entry then return end
	local hint = currentHint(player)
	if hint == nil and not entry.done then
		entry.done = true
		AnalyticsService.Event(player, "ftue_complete", {
			seconds = math.floor(os.clock() - entry.startedAt),
		})
		push(player, "ftue.done")
		task.delay(4, function()
			if state[player.UserId] then push(player, nil) end
		end)
		return
	end
	entry.step = hint
	push(player, hint)
end

function FtueService.Init() end

function FtueService.OnPlayer(player: Player)
	local data = DataService.Get(player)
	local matches = if data then (data.matches or 0) else 0

	state[player.UserId] = {
		startedAt = os.clock(),
		pickedUp = false,
		threw = false,
		ko = false,
		caught = false,
		revived = false,
		done = matches >= CFG.FTUE.SkipAfterMatches,
		step = nil,
	}

	AnalyticsService.StartSession(player)

	if state[player.UserId].done then
		push(player, nil)
	else
		task.delay(0.6, function()
			if state[player.UserId] then refresh(player) end
		end)
	end
end

function FtueService.PickedUp(player: Player?)
	if not player then return end
	local entry = state[player.UserId]
	if not entry or entry.pickedUp then return end
	entry.pickedUp = true
	AnalyticsService.Event(player, "ftue_pickup", {
		seconds = math.floor(os.clock() - entry.startedAt),
	})
	refresh(player)
end

function FtueService.Threw(player: Player?)
	if not player then return end
	local entry = state[player.UserId]
	AnalyticsService.Count(player, "throws")
	if not entry or entry.threw then return end
	entry.threw = true
	AnalyticsService.Step(player, "first_throw")
	refresh(player)
end

function FtueService.KnockedOut(player: Player?)
	if not player then return end
	local entry = state[player.UserId]
	AnalyticsService.Count(player, "kos")
	if not entry or entry.ko then return end
	entry.ko = true
	AnalyticsService.Step(player, "first_ko")
	refresh(player)
end

function FtueService.Caught(player: Player?)
	if not player then return end
	local entry = state[player.UserId]
	AnalyticsService.Count(player, "catches")
	if not entry or entry.caught then return end
	entry.caught = true
	AnalyticsService.Step(player, "first_catch")
	refresh(player)
end

function FtueService.Revived(player: Player?)
	if not player then return end
	local entry = state[player.UserId]
	AnalyticsService.Count(player, "revives")
	if not entry or entry.revived then return end
	entry.revived = true
	refresh(player)
end

function FtueService.MatchFinished(player: Player?, matchIndex: number)
	if not player then return end
	AnalyticsService.Count(player, "matches")
	if matchIndex <= 1 then
		AnalyticsService.Step(player, "match_done")
	else
		AnalyticsService.Step(player, "second_match")
	end
end

function FtueService.Benched(player: Player?)
	if not player or not CFG.FTUE.BenchedHint then return end
	local entry = state[player.UserId]
	if entry and entry.done then return end
	push(player, "ftue.benched")
	task.delay(3, function()
		if state[player.UserId] then refresh(player) end
	end)
end

function FtueService.IsMobile(player: Player): boolean
	return player:GetAttribute("IsMobile") == true
end

function FtueService.Start()
	Players.PlayerRemoving:Connect(function(player)
		state[player.UserId] = nil
	end)
end

return FtueService

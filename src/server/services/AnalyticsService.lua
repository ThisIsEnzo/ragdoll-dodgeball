-- AnalyticsService: серверная воронка FTUE, тайминги шагов, сессионные метрики.
-- Principle: gameplay steps are recorded ONLY on the server. A client can never mark itself
-- as having thrown, caught or finished a match. Client may only report UI markers.
--
-- Два стока:
--   1) sessions (в памяти процесса) -> tools/funnel-report.lua печатает воронку сразу в Studio
--   2) Roblox AnalyticsService custom events -> Creator Analytics dashboard (pcall-safe)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))

local AnalyticsService = {}

local STEP_ORDER = { "spawn", "first_throw", "first_ko", "first_catch", "match_done", "second_match" }
local STEP_INDEX = {}
for index, name in ipairs(STEP_ORDER) do STEP_INDEX[name] = index end

local sessions: { [number]: any } = {}
local completed: { any } = {}
local robloxAvailable: boolean? = nil
local warned = false

local function tryRoblox(player: Player, eventName: string, params: any)
	if not CFG.Analytics.SendToRoblox then return end
	if robloxAvailable == false then return end

	local ok = pcall(function()
		local analytics = game:GetService("AnalyticsService")
		analytics:LogCustomEvent(player, eventName, params)
	end)

	if ok then
		robloxAvailable = true
	elseif robloxAvailable == nil then
		robloxAvailable = false
		if not warned then
			warned = true
			warn("[Analytics] Roblox custom events unavailable. Local funnel still works. "
				.. "Register event names in Creator Hub -> Analytics -> Custom Events.")
		end
	end
end

local function bucketOf(seconds: number): string
	for _, limit in ipairs(CFG.Analytics.TimingBuckets) do
		if seconds <= limit then return "<=" .. limit .. "s" end
	end
	return ">" .. CFG.Analytics.TimingBuckets[#CFG.Analytics.TimingBuckets] .. "s"
end

function AnalyticsService.Init() end

function AnalyticsService.StartSession(player: Player)
	sessions[player.UserId] = {
		userId = player.UserId,
		name = player.Name,
		startedAt = os.clock(),
		steps = {},
		timings = {},
		counters = { throws = 0, kos = 0, catches = 0, revives = 0, matches = 0 },
		device = if player:GetAttribute("IsMobile") then "mobile" else "unknown",
		finished = false,
	}
	AnalyticsService.Step(player, "spawn")
end

function AnalyticsService.SetDevice(player: Player, device: string)
	local session = sessions[player.UserId]
	if session and typeof(device) == "string" then
		session.device = device
	end
end

-- Идемпотентный шаг воронки. Повторный вызов не портит тайминг.
function AnalyticsService.Step(player: Player, step: string)
	if not CFG.Analytics.Enabled then return end
	local session = sessions[player.UserId]
	if not session then return end
	if not STEP_INDEX[step] then return end
	if session.steps[step] then return end

	local elapsed = os.clock() - session.startedAt
	session.steps[step] = elapsed
	session.timings[step] = elapsed

	tryRoblox(player, "ftue_step", {
		step = step,
		stepIndex = STEP_INDEX[step],
		seconds = math.floor(elapsed * 10) / 10,
		bucket = bucketOf(elapsed),
		device = session.device,
	})

	print(string.format("[Funnel] %s %s at %.1fs", player.Name, step, elapsed))
end

function AnalyticsService.Count(player: Player, counter: string, amount: number?)
	local session = sessions[player.UserId]
	if not session then return end
	if typeof(session.counters[counter]) ~= "number" then return end
	session.counters[counter] += (amount or 1)
end

function AnalyticsService.Event(player: Player, eventName: string, params: any?)
	if not CFG.Analytics.Enabled then return end
	tryRoblox(player, eventName, params or {})
end

-- Только UI-маркеры. Никаких геймплейных достижений здесь быть не может.
function AnalyticsService.UiMarker(player: Player, marker: string)
	if marker == "hint_shown" or marker == "hint_dismissed" or marker == "result_shown" then
		AnalyticsService.Event(player, "ftue_ui", { marker = marker })
	end
end

function AnalyticsService.EndSession(player: Player, reason: string)
	local session = sessions[player.UserId]
	if not session or session.finished then return end
	session.finished = true

	local duration = os.clock() - session.startedAt
	local lastStep = 0
	local lastStepName = "none"
	for name, index in pairs(STEP_INDEX) do
		if session.steps[name] and index > lastStep then
			lastStep = index
			lastStepName = name
		end
	end

	local record = {
		userId = session.userId,
		name = session.name,
		duration = duration,
		steps = session.steps,
		counters = session.counters,
		device = session.device,
		lastStep = lastStepName,
		reason = reason,
		at = os.time(),
	}
	table.insert(completed, record)

	tryRoblox(player, "session_end", {
		duration = math.floor(duration),
		lastStep = lastStepName,
		throws = session.counters.throws,
		kos = session.counters.kos,
		catches = session.counters.catches,
		matches = session.counters.matches,
		reason = reason,
		device = session.device,
	})

	sessions[player.UserId] = nil

	local cutoff = os.time() - CFG.Analytics.KeepSessionSeconds
	for i = #completed, 1, -1 do
		if completed[i].at < cutoff then table.remove(completed, i) end
	end
end

function AnalyticsService.GetRecords()
	return completed
end

function AnalyticsService.GetLiveSessions()
	return sessions
end

function AnalyticsService.StepOrder()
	return STEP_ORDER
end

function AnalyticsService.Start()
	Players.PlayerRemoving:Connect(function(player)
		AnalyticsService.EndSession(player, "left")
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			AnalyticsService.EndSession(player, "shutdown")
		end
	end)
end

return AnalyticsService

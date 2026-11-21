-- Personal match summary. Reads existing profile counters; does not award or persist anything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Ranks = require(Shared:WaitForChild("RankCatalog"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local MatchService = Resolve.Require(ServerScriptService, "MatchService")
local RoundService = Resolve.Require(ServerScriptService, "RoundService")

local remoteFolder = ReplicatedStorage:FindFirstChild("SummaryRemotes")
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "SummaryRemotes"
	remoteFolder.Parent = ReplicatedStorage
end

local summaryRemote = remoteFolder:FindFirstChild("MatchSummary")
if not summaryRemote then
	summaryRemote = Instance.new("RemoteEvent")
	summaryRemote.Name = "MatchSummary"
	summaryRemote.Parent = remoteFolder
end

local TRACKED = { "kos", "catches", "revives", "throws", "roundWins", "wins", "matches", "coins", "level", "xp" }
local active = false
local snapshots = {}
local finalScore = { [1] = 0, [2] = 0 }
local matchSerial = 0

local function lifetimeXp(data)
	local total = math.max(0, tonumber(data.xp) or 0)
	local level = math.clamp(math.floor(tonumber(data.level) or 1), 1, CFG.Progression.MaxLevel)
	for current = 1, level - 1 do
		total += CFG.XP.ToNext(current)
	end
	return total
end

local function rankFor(wins)
	local tiers = Ranks.Tiers
	local current = tiers[1]
	local nextTier = nil
	for index, tier in ipairs(tiers) do
		if wins >= tier.wins then
			current = tier
			nextTier = tiers[index + 1]
		else
			nextTier = tier
			break
		end
	end
	local progress = 1
	if nextTier then
		progress = math.clamp((wins - current.wins) / math.max(1, nextTier.wins - current.wins), 0, 1)
	end
	return {
		name = current.name,
		color = current.color,
		wins = wins,
		currentWins = current.wins,
		nextName = nextTier and nextTier.name or nil,
		nextWins = nextTier and nextTier.wins or current.wins,
		progress = progress,
	}
end

local function snapshotPlayer(player)
	local data = DataService.Get(player)
	if not data then return nil end
	local snapshot = { team = nil, values = {} }
	for _, key in ipairs(TRACKED) do
		snapshot.values[key] = tonumber(data[key]) or 0
	end
	snapshot.totalXp = lifetimeXp(data)
	local character = player.Character
	local team = character and character:GetAttribute("Team")
	if typeof(team) == "number" and (team == 1 or team == 2) then
		snapshot.team = team
	end
	return snapshot
end

local function beginMatch()
	matchSerial += 1
	table.clear(snapshots)
	finalScore[1], finalScore[2] = 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		local snapshot = snapshotPlayer(player)
		if snapshot then snapshots[player.UserId] = snapshot end
	end
end

local function buildSummary(player, before, winningTeam)
	local data = DataService.Get(player)
	if not data or not before then return nil end

	local function delta(key)
		return math.max(0, (tonumber(data[key]) or 0) - (before.values[key] or 0))
	end

	local xpAfter = lifetimeXp(data)
	local xpEarned = math.max(0, xpAfter - before.totalXp)
	local winsAfter = tonumber(data.wins) or 0
	local won = delta("wins") > 0
	local teamWon = winningTeam ~= nil and before.team == winningTeam

	-- wins delta is authoritative for the personal result; team score is presentation only.
	return {
		matchId = matchSerial,
		result = if won then "WIN" else "LOSS",
		teamWon = teamWon,
		score = { blue = finalScore[1], red = finalScore[2] },
		stats = {
			kos = delta("kos"),
			catches = delta("catches"),
			revives = delta("revives"),
			throws = delta("throws"),
			roundWins = delta("roundWins"),
		},
		rewards = {
			coins = delta("coins"),
			xp = xpEarned,
			levels = math.max(0, (tonumber(data.level) or 1) - (before.values.level or 1)),
		},
		level = {
			before = before.values.level or 1,
			after = tonumber(data.level) or 1,
			xp = tonumber(data.xp) or 0,
			xpToNext = CFG.XP.ToNext(tonumber(data.level) or 1),
		},
		rank = rankFor(winsAfter),
	}
end

local function finishMatch()
	local winningTeam = nil
	if finalScore[1] > finalScore[2] then
		winningTeam = 1
	elseif finalScore[2] > finalScore[1] then
		winningTeam = 2
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local before = snapshots[player.UserId]
		local payload = before and buildSummary(player, before, winningTeam)
		if payload then
			summaryRemote:FireClient(player, payload)
		end
	end
	table.clear(snapshots)
end

RunService.Heartbeat:Connect(function()
	local running = MatchService.IsRunning()
	if running then
		if not active then
			active = true
			beginMatch()
		end
		-- Cache score before MatchService.clearMatch() calls RoundService.ResetRound().
		finalScore[1] = math.max(finalScore[1], RoundService.Wins(1))
		finalScore[2] = math.max(finalScore[2], RoundService.Wins(2))
	elseif active then
		active = false
		finishMatch()
	end
end)

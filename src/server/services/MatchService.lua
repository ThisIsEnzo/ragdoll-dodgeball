-- MatchService v0.6.0: сообщает FtueService о завершённых матчах (шаги match_done / second_match).

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local BallService = Resolve.Require(ServerScriptService, "BallService")
local BotController = Resolve.Require(ServerScriptService, "BotController")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local FtueService = Resolve.Require(ServerScriptService, "FtueService")

local MatchService = {}

local queue: { Player } = {}
local inMatch = false
local teams: { [number]: { Model } } = { [1] = {}, [2] = {} }
local downed: { [number]: { Model } } = { [1] = {}, [2] = {} }
local teamOf: { [Model]: number } = {}
local spawns: { [number]: { Vector3 } } = { [1] = {}, [2] = {} }
local bench: { [number]: Vector3 } = {}
local running = false

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

local function playersOf(team: number): { Player }
	local list = {}
	for _, character in ipairs(teams[team]) do
		local player = Players:GetPlayerFromCharacter(character)
		if player then table.insert(list, player) end
	end
	return list
end

local function readMarkers()
	local arena = workspace:FindFirstChild("Arena")
	for team = 1, 2 do
		local folder = arena and arena:FindFirstChild("Team" .. team .. "Spawns")
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				if part:IsA("BasePart") then
					table.insert(spawns[team], part.Position)
					part.Transparency = 1
					part.CanCollide = false
				end
			end
		end
		if #spawns[team] == 0 then
			for i = -1, 1 do
				table.insert(spawns[team], Vector3.new(i * 8, 5, team == 1 and -28 or 28))
			end
		end
		local benchPart = arena and arena:FindFirstChild("Bench" .. team)
		bench[team] = benchPart and benchPart.Position or Vector3.new(team == 1 and -40 or 40, 5, 0)
	end
end

local function teleport(character: Model, position: Vector3)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function broadcast()
	Net.FireAll("MatchState", {
		state = RoundService.State,
		timer = math.max(0, math.floor(RoundService.Timer)),
		wins1 = RoundService.Wins(1), wins2 = RoundService.Wins(2),
		alive1 = RoundService.AliveCount(1), alive2 = RoundService.AliveCount(2),
		inMatch = inMatch,
	})
end

function MatchService.Init()
	readMarkers()
	RoundService.StateChanged.Event:Connect(broadcast)
end

function MatchService.Enqueue(player: Player)
	if table.find(queue, player) then return end
	table.insert(queue, player)
	broadcast()
end

function MatchService.Leave(player: Player)
	local index = table.find(queue, player)
	if index then table.remove(queue, index) end
end

function MatchService.TeamOf(character: Model): number?
	return teamOf[character]
end

function MatchService.IsRunning(): boolean
	return inMatch
end

function MatchService.OnKO(character: Model, reason: string)
	local team = teamOf[character]
	if not team then return end
	RoundService.RegisterKO(character)
	character:SetAttribute("Ragdolled", true)
	BallService.ForceRelease(character)
	if not table.find(downed[team], character) then
		table.insert(downed[team], character)
	end
	Net.FireAll("FXEvent", "ko", character, reason)

	local victim = Players:GetPlayerFromCharacter(character)
	if victim then FtueService.Benched(victim) end

	task.delay(CFG.Round.RagdollTime, function()
		if not character.Parent then return end
		RagdollService.Restore(character)
		character:SetAttribute("Ragdolled", false)
		character:SetAttribute("Benched", true)
		teleport(character, bench[team])
		broadcast()
	end)
	broadcast()
end

function MatchService.ReviveOne(team: number): boolean
	local character = table.remove(downed[team], 1)
	if not character or not character.Parent then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	RagdollService.Restore(character)
	character:SetAttribute("Ragdolled", false)
	character:SetAttribute("Benched", false)
	humanoid.Health = humanoid.MaxHealth
	teleport(character, spawns[team][math.random(1, #spawns[team])])
	RoundService.Revive(character, team)
	Net.FireAll("FXEvent", "revive", character)
	broadcast()
	return true
end

local function clearMatch()
	for team = 1, 2 do
		for _, character in ipairs(teams[team]) do teamOf[character] = nil end
		table.clear(teams[team])
		table.clear(downed[team])
	end
	BotController.DespawnAll()
	RoundService.ResetRound()
	inMatch = false
	broadcast()
end

local function setupRound()
	BallService.SpawnAll()
	for team = 1, 2 do
		for index, character in ipairs(teams[team]) do
			if character.Parent then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then humanoid.Health = humanoid.MaxHealth end
				RagdollService.Restore(character)
				character:SetAttribute("Ragdolled", false)
				character:SetAttribute("Benched", false)
				character:SetAttribute("Carrying", false)
				teleport(character, spawns[team][((index - 1) % #spawns[team]) + 1])
				RoundService.Register(character, team)
			end
		end
		table.clear(downed[team])
	end
	broadcast()
end

function MatchService.StartMatch()
	if inMatch then return end
	inMatch = true

	local participants = table.clone(queue)
	table.clear(queue)
	shuffle(participants)

	local matchIndexByPlayer = {}
	for index, player in ipairs(participants) do
		local character = player.Character
		if character then
			local team = (index % 2) + 1
			table.insert(teams[team], character)
			teamOf[character] = team
			character:SetAttribute("Team", team)
			local data = game:GetService("ReplicatedStorage")
			matchIndexByPlayer[player.UserId] = (player:GetAttribute("MatchesThisSession") or 0) + 1
			player:SetAttribute("MatchesThisSession", matchIndexByPlayer[player.UserId])
		end
	end

	for team = 1, 2 do
		local needed = 3 - #teams[team]
		for _ = 1, needed do
			local bot = BotController.Spawn(team, spawns[team][math.random(1, #spawns[team])])
			if bot then
				table.insert(teams[team], bot)
				teamOf[bot] = team
				bot:SetAttribute("Team", team)
			end
		end
	end

	task.spawn(function()
		while RoundService.Wins(1) < CFG.Round.WinsNeeded and RoundService.Wins(2) < CFG.Round.WinsNeeded do
			local winner = RoundService.RunRound(setupRound)
			if winner == nil then break end
			ProgressionService.SettleRound(playersOf(winner))
		end

		local matchWinner = if RoundService.Wins(1) > RoundService.Wins(2) then 1 else 2
		Net.FireAll("MatchState", {
			state = "MatchEnd", winner = matchWinner, inMatch = false,
			wins1 = RoundService.Wins(1), wins2 = RoundService.Wins(2), timer = 0,
		})

		local all = { table.unpack(playersOf(1)), table.unpack(playersOf(2)) }
		ProgressionService.SettleMatch(all, playersOf(matchWinner))
		for _, player in ipairs(all) do
			FtueService.MatchFinished(player, matchIndexByPlayer[player.UserId] or 1)
		end

		print("[Match] Team " .. matchWinner .. " won")
		task.wait(CFG.Round.MatchEnd)

		for _, player in ipairs(Players:GetPlayers()) do MatchService.Enqueue(player) end
		clearMatch()
	end)
end

function MatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		MatchService.Leave(player)
		local character = player.Character
		if character then
			local team = teamOf[character]
			if team then
				RoundService.RegisterKO(character)
				local index = table.find(teams[team], character)
				if index then table.remove(teams[team], index) end
				teamOf[character] = nil
			end
		end
	end)

	if running then return end
	running = true
	task.spawn(function()
		while true do
			task.wait(1)
			if not inMatch and #queue >= CFG.Bots.MinRealPlayersToStart then
				MatchService.StartMatch()
			end
		end
	end)
end

return MatchService

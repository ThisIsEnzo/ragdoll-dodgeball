-- ProgressionService v0.6.0: пишет firstThrowSeconds и ftueDone в профиль для когортного анализа.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")

local ProgressionService = {}

local DAY = 86400

local function today(): number
	return math.floor(os.time() / DAY)
end

local function pushProfile(player: Player)
	local data = DataService.Get(player)
	if not data then return end
	Net.FireClient("ProfileState", player, {
		coins = data.coins, xp = data.xp, level = data.level,
		xpToNext = CFG.XP.ToNext(data.level),
		streakDay = data.streakDay,
		persistent = DataService.IsPersistent(player),
		matches = data.matches,
	})
end

local function pushQuests(player: Player)
	local data = DataService.Get(player)
	if not data then return end
	local list = {}
	for index, quest in ipairs(data.quests) do
		table.insert(list, {
			index = index, id = quest.id, stat = quest.stat, target = quest.target,
			progress = math.min(data.questProgress[quest.stat] or 0, quest.target),
			claimed = quest.claimed == true,
			rewardCoins = CFG.Progression.QuestRewardCoins,
		})
	end
	Net.FireClient("QuestState", player, list)
end

local function rollQuests(userId: number, day: number)
	local rng = Random.new(userId % 2147483647 + day)
	local pool = table.clone(CFG.QuestPool)
	local picked = {}
	for _ = 1, math.min(CFG.Progression.QuestSlots, #pool) do
		local index = rng:NextInteger(1, #pool)
		local entry = table.remove(pool, index)
		table.insert(picked, { id = entry.id, stat = entry.stat, target = entry.target, claimed = false })
	end
	return picked
end

local function refreshDaily(player: Player, data: any)
	local day = today()
	if data.questDay == day then return end

	local previous = data.streakStamp
	if previous == day - 1 then
		data.streakDay = math.min(#CFG.Progression.StreakCoins, data.streakDay + 1)
	elseif previous ~= day then
		data.streakDay = 1
	end
	data.streakStamp = day
	data.lastSeenDay = day

	local reward = CFG.Progression.StreakCoins[data.streakDay] or CFG.Progression.StreakCoins[1]
	data.coins += reward

	data.questDay = day
	data.quests = rollQuests(player.UserId, day)
	data.questProgress = {}

	print(string.format("[Progress] %s day %d streak, +%d coins, quests rolled", player.Name, day, reward))
end

local function checkLevelUp(player: Player, data: any)
	local maxLevel = CFG.Progression.MaxLevel
	while data.level < maxLevel and data.xp >= CFG.XP.ToNext(data.level) do
		data.xp -= CFG.XP.ToNext(data.level)
		data.level += 1
		data.coins += CFG.Progression.LevelUpCoins
		local unlock = CFG.Unlocks[data.level]
		Net.FireClient("LevelUp", player, data.level, unlock, CFG.Progression.LevelUpCoins)
		print(string.format("[Progress] %s level %d%s", player.Name, data.level,
			if unlock then (" unlocked " .. unlock) else ""))
	end
	if data.level >= maxLevel then
		data.xp = math.min(data.xp, CFG.XP.ToNext(maxLevel))
	end
end

function ProgressionService.Init() end

function ProgressionService.OnPlayer(player: Player)
	local data = DataService.Load(player)
	refreshDaily(player, data)
	checkLevelUp(player, data)
	pushProfile(player)
	pushQuests(player)
end

function ProgressionService.AddXP(player: Player?, amount: number)
	if not player then return end
	local data = DataService.Get(player)
	if not data or amount <= 0 then return end
	data.xp += amount
	checkLevelUp(player, data)
	pushProfile(player)
end

function ProgressionService.AddCoins(player: Player?, amount: number)
	if not player then return end
	local data = DataService.Get(player)
	if not data or amount <= 0 then return end
	data.coins += amount
	pushProfile(player)
end

function ProgressionService.RegisterStat(player: Player?, stat: string, amount: number?)
	if not player then return end
	local data = DataService.Get(player)
	if not data then return end
	local n = amount or 1

	if typeof(data[stat]) == "number" then data[stat] += n end
	data.questProgress[stat] = (data.questProgress[stat] or 0) + n

	if stat == "kos" then
		ProgressionService.AddCoins(player, CFG.Progression.KoCoins * n)
		ProgressionService.AddXP(player, CFG.Progression.KoXP * n)
	elseif stat == "catches" then
		ProgressionService.AddCoins(player, CFG.Progression.CatchCoins * n)
		ProgressionService.AddXP(player, CFG.Progression.CatchXP * n)
	elseif stat == "revives" then
		ProgressionService.AddXP(player, CFG.Progression.ReviveXP * n)
	elseif stat == "throws" then
		ProgressionService.AddXP(player, CFG.Progression.ThrowXP * n)
		if data.firstThrowSeconds == 0 then
			local session = player:GetAttribute("SessionSeconds")
			if typeof(session) == "number" then
				data.firstThrowSeconds = math.floor(session * 10) / 10
			end
		end
	end

	pushQuests(player)
end

function ProgressionService.MarkFtueDone(player: Player?)
	if not player then return end
	local data = DataService.Get(player)
	if data then data.ftueDone = true end
end

function ProgressionService.ClaimQuest(player: Player, index: any): boolean
	if typeof(index) ~= "number" then return false end
	local data = DataService.Get(player)
	if not data then return false end
	local quest = data.quests[index]
	if not quest or quest.claimed then return false end
	if (data.questProgress[quest.stat] or 0) < quest.target then return false end

	quest.claimed = true
	data.coins += CFG.Progression.QuestRewardCoins
	ProgressionService.AddXP(player, CFG.Progression.QuestRewardXP)
	pushQuests(player)
	pushProfile(player)
	return true
end

function ProgressionService.SettleRound(players: { Player })
	for _, player in ipairs(players) do
		ProgressionService.RegisterStat(player, "roundWins", 1)
	end
end

function ProgressionService.SettleMatch(players: { Player }, winners: { Player })
	local winnerSet = {}
	for _, player in ipairs(winners) do winnerSet[player.UserId] = true end

	for _, player in ipairs(players) do
		local data = DataService.Get(player)
		if data then
			local won = winnerSet[player.UserId] == true
			data.matches += 1
			if won then data.wins += 1 end
			data.coins += if won then CFG.Progression.MatchWinCoins else CFG.Progression.MatchLossCoins
			ProgressionService.AddXP(player,
				if won then CFG.Progression.MatchWinXP else CFG.Progression.MatchLossXP)
			pushProfile(player)
		end
	end
end

function ProgressionService.Start() end

return ProgressionService

-- PartyService: play together, and get paid for it.
--
-- A party is a small mutual group inside one server. Members are marked with
-- attributes so any client can show them, and at match end each member gets
-- the coin bonus that CFG.Economy.PartyBonus has always promised but nothing
-- ever applied.
--
-- Self-contained: own remotes, no edits to MatchService or ProgressionService.
-- Match boundaries are observed by polling IsRunning, the same approach the
-- summary service uses.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local MatchService = Resolve.Require(ServerScriptService, "MatchService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

local MAX_PARTY = 3
local OFFER_SECONDS = 20

local parties = {}
local membership = {}
local offers = {}
local friendsCache = {}
local nextPartyId = 1
local matchSnapshot = {}

local wasRunning = false

local folder = Instance.new("Folder")
folder.Name = "PartyRemotes"
folder.Parent = ReplicatedStorage

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateRemote = makeRemote("PartyState")
local inviteRemote = makeRemote("PartyInvite")
local respondRemote = makeRemote("PartyRespond")
local leaveRemote = makeRemote("PartyLeave")
local friendsRemote = makeRemote("PartyFriends")
local offerRemote = makeRemote("PartyOffer")

local function nameOf(userId)
	local target = Players:GetPlayerByUserId(userId)
	if target then return target.DisplayName end
	return "Player" .. tostring(userId % 10000)
end

local function membersOf(partyId)
	local party = parties[partyId]
	local list = {}
	if not party then return list end
	for userId in pairs(party.members) do
		if Players:GetPlayerByUserId(userId) then
			table.insert(list, userId)
		end
	end
	table.sort(list)
	return list
end

local function publishAttributes(partyId)
	local party = parties[partyId]
	if not party then return end
	local members = membersOf(partyId)
	for _, userId in ipairs(members) do
		local target = Players:GetPlayerByUserId(userId)
		if target then
			target:SetAttribute("PartyId", partyId)
			target:SetAttribute("PartySize", #members)
		end
	end
end

local function clearAttributes(userId)
	local target = Players:GetPlayerByUserId(userId)
	if target then
		target:SetAttribute("PartyId", nil)
		target:SetAttribute("PartySize", nil)
	end
end

local function dissolveIfSmall(partyId)
	local party = parties[partyId]
	if not party then return end
	local members = membersOf(partyId)
	if #members >= 2 then
		publishAttributes(partyId)
		return
	end
	for _, userId in ipairs(members) do
		membership[userId] = nil
		clearAttributes(userId)
	end
	for userId in pairs(party.members) do
		membership[userId] = nil
		clearAttributes(userId)
	end
	parties[partyId] = nil
end

local function pushState()
	local roster = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local partyId = membership[other.UserId]
		table.insert(roster, {
			userId = other.UserId,
			name = other.DisplayName,
			username = other.Name,
			partyId = partyId,
			isFriend = false,
		})
	end

	for _, target in ipairs(Players:GetPlayers()) do
		local partyId = membership[target.UserId]
		local members = {}
		if partyId then
			for _, userId in ipairs(membersOf(partyId)) do
				table.insert(members, { userId = userId, name = nameOf(userId) })
			end
		end

		local bonusPercent = math.floor(CFG.Economy.PartyBonus * 100)
		local activeBonus = 0
		if #members >= 2 then
			activeBonus = bonusPercent * (#members - 1)
		end

		stateRemote:FireClient(target, {
			roster = roster,
			partyId = partyId,
			members = members,
			maxSize = MAX_PARTY,
			bonusPercent = activeBonus,
		})
	end
end

local function createParty(userId)
	local partyId = nextPartyId
	nextPartyId += 1
	parties[partyId] = { members = { [userId] = true } }
	membership[userId] = partyId
	return partyId
end

local function removeFromParty(userId)
	local partyId = membership[userId]
	if not partyId then return end
	local party = parties[partyId]
	membership[userId] = nil
	clearAttributes(userId)
	if party then
		party.members[userId] = nil
		dissolveIfSmall(partyId)
	end
end

inviteRemote.OnServerEvent:Connect(function(player, targetUserId)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if typeof(targetUserId) ~= "number" then return end
	if targetUserId == player.UserId then return end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then return end

	local existingOffer = offers[targetUserId]
	if existingOffer and os.clock() - existingOffer.at < 6 then return end

	local partyId = membership[player.UserId]
	if partyId then
		local members = membersOf(partyId)
		if #members >= MAX_PARTY then return end
		if membership[targetUserId] == partyId then return end
	end

	offers[targetUserId] = { from = player.UserId, at = os.clock() }
	offerRemote:FireClient(target, {
		from = player.UserId,
		name = player.DisplayName,
		expires = OFFER_SECONDS,
	})
end)

respondRemote.OnServerEvent:Connect(function(player, accept)
	local offer = offers[player.UserId]
	if not offer then return end
	offers[player.UserId] = nil
	if os.clock() - offer.at > OFFER_SECONDS then return end
	if accept ~= true then return end

	local inviter = Players:GetPlayerByUserId(offer.from)
	if not inviter then return end

	local partyId = membership[inviter.UserId]
	if not partyId then
		partyId = createParty(inviter.UserId)
	end

	local members = membersOf(partyId)
	if #members >= MAX_PARTY then return end

	removeFromParty(player.UserId)
	parties[partyId].members[player.UserId] = true
	membership[player.UserId] = partyId

	publishAttributes(partyId)
	pushState()
	print(string.format("[Party] %s joined %s (%d members)", player.Name, inviter.Name, #membersOf(partyId)))
end)

leaveRemote.OnServerEvent:Connect(function(player)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	removeFromParty(player.UserId)
	pushState()
end)

friendsRemote.OnServerEvent:Connect(function(player)
	if not AntiCheat.Allow(player, "ShopBuy") then return end

	local cached = friendsCache[player.UserId]
	if cached and os.clock() - cached.at < 120 then
		friendsRemote:FireClient(player, cached.list)
		return
	end

	local list = {}
	local ok = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		local count = 0
		while count < 60 do
			for _, entry in ipairs(pages:GetCurrentPage()) do
				table.insert(list, {
					userId = entry.Id,
					name = entry.DisplayName,
					username = entry.Username,
					isOnline = entry.IsOnline == true,
				})
				count += 1
				if count >= 60 then break end
			end
			if pages.IsFinished then break end
			pages:AdvanceToNextPageAsync()
		end
	end)

	if not ok then
		list = {}
	end

	local here = {}
	for _, other in ipairs(Players:GetPlayers()) do
		here[other.UserId] = true
	end
	for _, entry in ipairs(list) do
		entry.inThisServer = here[entry.userId] == true
	end

	table.sort(list, function(a, b)
		if a.inThisServer ~= b.inThisServer then return a.inThisServer end
		if a.isOnline ~= b.isOnline then return a.isOnline end
		return a.name < b.name
	end)

	friendsCache[player.UserId] = { at = os.clock(), list = list }
	friendsRemote:FireClient(player, list)
end)

-- Snapshot profile match counts at match start; only participants can earn bonus.
local function beginMatch()
	table.clear(matchSnapshot)
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(player)
		if data and typeof(data.matches) == "number" then
			matchSnapshot[player.UserId] = data.matches
		end
	end
end

local function participated(userId)
	local baseline = matchSnapshot[userId]
	if baseline == nil then return false end
	local player = Players:GetPlayerByUserId(userId)
	if not player then return false end
	local data = DataService.Get(player)
	return data ~= nil and typeof(data.matches) == "number" and data.matches > baseline
end

local function payPartyBonus()
	local paid = {}
	for partyId in pairs(parties) do
		local members = membersOf(partyId)
		local eligible = {}
		for _, userId in ipairs(members) do
			if participated(userId) then
				table.insert(eligible, userId)
			end
		end

		if #eligible >= 2 then
			local perMember = math.floor(CFG.Progression.MatchWinCoins * CFG.Economy.PartyBonus * (#eligible - 1))
			if perMember > 0 then
				for _, userId in ipairs(eligible) do
					local target = Players:GetPlayerByUserId(userId)
					if target and not paid[userId] then
						paid[userId] = true
						ProgressionService.GrantCoins(target, perMember)
					end
				end
				print(string.format("[Party] party %d: +%d coins each to %d participants", partyId, perMember, #eligible))
			end
		end
	end
	table.clear(matchSnapshot)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.5 then return end
	accumulator = 0

	local running = MatchService.IsRunning()
	if running and not wasRunning then
		beginMatch()
	elseif not running and wasRunning then
		payPartyBonus()
	end
	wasRunning = running

	for userId, offer in pairs(offers) do
		if os.clock() - offer.at > OFFER_SECONDS then
			offers[userId] = nil
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	pushState()
end)

Players.PlayerRemoving:Connect(function(player)
	removeFromParty(player.UserId)
	offers[player.UserId] = nil
	friendsCache[player.UserId] = nil
	task.defer(pushState)
end)

pushState()
print("[Party] service up, bonus " .. math.floor(CFG.Economy.PartyBonus * 100) .. "% per extra member")

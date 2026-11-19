-- LeaderboardService: global boards and rank tiers.
-- Writes are throttled and batched so a busy server never hammers OrderedDataStore.
-- Reads are cached and shared, so opening the panel costs nothing per player.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("RankCatalog"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

local stores = {}
for _, board in ipairs(Catalog.Boards) do
	stores[board.key] = DataStoreService:GetDataStore("RD_Board_" .. board.key .. "_v1")
end

local cache = {}
local nameCache = {}
local warned = false
local lastRefresh = 0

local folder = Instance.new("Folder")
folder.Name = "RankRemotes"
folder.Parent = ReplicatedStorage

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local boardRemote = makeRemote("BoardState")
local requestRemote = makeRemote("BoardRequest")

local function warnOnce(message)
	if warned then return end
	warned = true
	warn("[Ranks] " .. message)
end

function _G.RDTierFor(wins)
	local picked = Catalog.Tiers[1]
	for _, tier in ipairs(Catalog.Tiers) do
		if wins >= tier.wins then picked = tier end
	end
	return picked
end

local function tierFor(wins)
	local picked = Catalog.Tiers[1]
	for _, tier in ipairs(Catalog.Tiers) do
		if wins >= tier.wins then picked = tier end
	end
	return picked
end

local function nextTier(wins)
	for _, tier in ipairs(Catalog.Tiers) do
		if wins < tier.wins then return tier end
	end
	return nil
end

local function resolveName(userId)
	local cached = nameCache[userId]
	if cached then return cached end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and typeof(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return "Player" .. tostring(userId % 10000)
end

local function writeScores()
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(player)
		if data then
			for _, board in ipairs(Catalog.Boards) do
				local value = data[board.stat]
				if typeof(value) == "number" and value > 0 then
					local store = stores[board.key]
					local payload = math.max(1, math.floor(value))
					local ok = pcall(function()
						store:UpdateAsync(tostring(player.UserId), function(old)
							if typeof(old) == "number" and old >= payload then return old end
							return payload
						end)
					end)
					if not ok then
						warnOnce("OrderedDataStore write failed. Publish the place and enable API access.")
					end
				end
			end
			local tier = tierFor(data.wins or 0)
			player:SetAttribute("RankKey", tier.key)
			player:SetAttribute("RankName", tier.name)
		end
	end
end

local function refreshBoards()
	for _, board in ipairs(Catalog.Boards) do
		local ok, pages = pcall(function()
			return stores[board.key]:GetSortedAsync(false, Catalog.BoardSize)
		end)
		if ok and pages then
			local okPage, entries = pcall(function()
				return pages:GetCurrentPage()
			end)
			if okPage and typeof(entries) == "table" then
				local rows = {}
				for index, entry in ipairs(entries) do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(rows, {
							place = index,
							userId = userId,
							name = resolveName(userId),
							value = entry.value,
						})
					end
				end
				cache[board.key] = rows
			end
		else
			warnOnce("OrderedDataStore read failed. Boards show local data until the place is published.")
		end
	end
	lastRefresh = os.clock()
end

local function localFallback(board)
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(player)
		if data then
			local value = data[board.stat]
			if typeof(value) == "number" then
				table.insert(rows, { place = 0, userId = player.UserId, name = player.DisplayName, value = value })
			end
		end
	end
	table.sort(rows, function(a, b) return a.value > b.value end)
	for index, row in ipairs(rows) do row.place = index end
	return rows
end

local function push(player)
	local data = DataService.Get(player)
	local wins = 0
	local mine = {}
	if data then
		wins = data.wins or 0
		for _, board in ipairs(Catalog.Boards) do
			mine[board.key] = data[board.stat] or 0
		end
	end

	local tier = tierFor(wins)
	local upcoming = nextTier(wins)
	local progress = 1
	local remaining = 0
	if upcoming then
		local span = upcoming.wins - tier.wins
		if span > 0 then
			progress = math.clamp((wins - tier.wins) / span, 0, 1)
		end
		remaining = math.max(0, upcoming.wins - wins)
	end

	local boards = {}
	for _, board in ipairs(Catalog.Boards) do
		local rows = cache[board.key]
		if not rows or #rows == 0 then rows = localFallback(board) end
		table.insert(boards, { key = board.key, label = board.label, rows = rows })
	end

	boardRemote:FireClient(player, {
		boards = boards,
		rank = {
			key = tier.key,
			name = tier.name,
			color = tier.color,
			wins = wins,
			progress = progress,
			nextName = upcoming and upcoming.name or nil,
			remaining = remaining,
		},
		mine = mine,
		stats = {
			matches = data and data.matches or 0,
			kos = data and data.kos or 0,
			catches = data and data.catches or 0,
			revives = data and data.revives or 0,
		},
	})
end

requestRemote.OnServerEvent:Connect(function(player)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if os.clock() - lastRefresh > Catalog.RefreshSeconds then
		task.spawn(refreshBoards)
	end
	push(player)
end)

local function onPlayer(player)
	task.spawn(function()
		for _ = 1, 100 do
			if DataService.Get(player) then break end
			task.wait(0.1)
		end
		local data = DataService.Get(player)
		if data then
			local tier = tierFor(data.wins or 0)
			player:SetAttribute("RankKey", tier.key)
			player:SetAttribute("RankName", tier.name)
		end
		push(player)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end

task.spawn(function()
	task.wait(6)
	refreshBoards()
	while true do
		task.wait(Catalog.WriteSeconds)
		writeScores()
		if os.clock() - lastRefresh > Catalog.RefreshSeconds then
			refreshBoards()
		end
		for _, player in ipairs(Players:GetPlayers()) do
			push(player)
		end
	end
end)

game:BindToClose(function()
	writeScores()
end)

print("[Ranks] leaderboards up: " .. #Catalog.Boards .. " boards, " .. #Catalog.Tiers .. " tiers")
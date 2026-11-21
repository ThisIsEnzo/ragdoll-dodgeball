-- StyleService: server-authoritative ownership/equip and earned-title validation.
-- Cosmetic state is stored separately from progression. Titles are never for sale.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("StyleCatalog"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

local STORE = DataStoreService:GetDataStore("RagdollDodgeball_Style_v1")
local records = {}
local loading = {}
local warnedStore = false

local folder = ReplicatedStorage:FindFirstChild("StyleRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "StyleRemotes"
	folder.Parent = ReplicatedStorage
end

local function remote(name)
	local found = folder:FindFirstChild(name)
	if found and found:IsA("RemoteEvent") then return found end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end

local stateRemote = remote("StyleState")
local buyRemote = remote("StyleBuy")
local equipRemote = remote("StyleEquip")
local requestRemote = remote("StyleRequest")

local function warnStore(message)
	if warnedStore then return end
	warnedStore = true
	warn("[Style] " .. message)
end

local function validOwned(source)
	local owned = {}
	if typeof(source) ~= "table" then return owned end
	for key, value in pairs(source) do
		if value == true and typeof(key) == "string" then
			local kind, itemKey = string.match(key, "^(trail):([%w_]+)$")
			if kind and Catalog.TrailByKey[itemKey] and Catalog.TrailByKey[itemKey].price > 0 then
				owned[key] = true
			else
				kind, itemKey = string.match(key, "^(effect):([%w_]+)$")
				if kind and Catalog.EffectByKey[itemKey] and Catalog.EffectByKey[itemKey].price > 0 then
					owned[key] = true
				end
			end
		end
	end
	return owned
end

local function loadRecord(player)
	local record = { owned = {}, trail = "none", effect = "default", title = "none" }
	local ok, stored = pcall(function()
		return STORE:GetAsync("style_" .. player.UserId)
	end)
	if not ok then
		warnStore("DataStore unavailable; cosmetics are session-only for this server.")
	elseif typeof(stored) == "table" then
		record.owned = validOwned(stored.owned)
		if typeof(stored.trail) == "string" and Catalog.TrailByKey[stored.trail] then
			record.trail = stored.trail
		end
		if typeof(stored.effect) == "string" and Catalog.EffectByKey[stored.effect] then
			record.effect = stored.effect
		end
		if typeof(stored.title) == "string" and Catalog.TitleByKey[stored.title] then
			record.title = stored.title
		end
	end
	records[player.UserId] = record
	return record
end

local function saveRecord(player)
	local record = records[player.UserId]
	if not record or not player.Parent then return false end
	local payload = {
		owned = table.clone(record.owned),
		trail = record.trail,
		effect = record.effect,
		title = record.title,
	}
	local ok, err = pcall(function()
		STORE:UpdateAsync("style_" .. player.UserId, function()
			return payload
		end)
	end)
	if not ok then
		warnStore("Could not save cosmetics; current server session remains usable. " .. tostring(err))
	end
	return ok
end

local function getTitleUnlocked(player, entry)
	local data = DataService.Get(player)
	if not data then return false end
	if entry.stat then
		return typeof(data[entry.stat]) == "number" and data[entry.stat] >= entry.amount
	end
	return (tonumber(data.level) or 1) >= (entry.level or 1)
end

local function owns(record, kind, key)
	if kind == "title" then
		local entry = Catalog.TitleByKey[key]
		return entry ~= nil and getTitleUnlocked(player, entry)
	end
	local map = if kind == "effect" then Catalog.EffectByKey else Catalog.TrailByKey
	local entry = map[key]
	if not entry then return false end
	if entry.price == 0 then return true end
	return record.owned[kind .. ":" .. key] == true
end

local function sanitizeAndApply(player)
	local record = records[player.UserId]
	if not record then return end
	if not owns(record, "trail", record.trail) then record.trail = "none" end
	if not owns(record, "effect", record.effect) then record.effect = "default" end
	local titleEntry = Catalog.TitleByKey[record.title]
	if not titleEntry or not getTitleUnlocked(player, titleEntry) then
		record.title = "none"
	end
	player:SetAttribute("TrailId", record.trail)
	player:SetAttribute("EffectId", record.effect)
	player:SetAttribute("TitleId", record.title)
end

local function buildState(player)
	local record = records[player.UserId]
	local data = DataService.Get(player)
	if not record or not data then return nil end
	local titles = {}
	for _, entry in ipairs(Catalog.Titles) do
		table.insert(titles, { key = entry.key, unlocked = getTitleUnlocked(player, entry) })
	end
	return {
		coins = data.coins,
		level = data.level,
		owned = table.clone(record.owned),
		trail = record.trail,
		effect = record.effect,
		title = record.title,
		titles = titles,
		stats = { kos = data.kos, catches = data.catches, revives = data.revives },
	}
end

local function pushState(player)
	sanitizeAndApply(player)
	local state = buildState(player)
	if state then stateRemote:FireClient(player, state) end
end

local function loadPlayer(player)
	if loading[player.UserId] or records[player.UserId] then return end
	loading[player.UserId] = true
	task.spawn(function()
		for _ = 1, 300 do
			if not player.Parent then loading[player.UserId] = nil return end
			if DataService.Get(player) then break end
			task.wait(0.1)
		end
		if player.Parent and DataService.Get(player) then
			loadRecord(player)
			pushState(player)
		else
			warn("[Style] Profile did not become available for " .. player.Name .. "; shop disabled for this session.")
		end
		loading[player.UserId] = nil
	end)
end

local function validRequest(player, kind, key)
	if not AntiCheat.Allow(player, "ShopBuy") then return false end
	if typeof(kind) ~= "string" or typeof(key) ~= "string" then return false end
	if #kind > 12 or #key > 24 then return false end
	return true
end

buyRemote.OnServerEvent:Connect(function(player, kind, key)
	if not validRequest(player, kind, key) then return end
	if kind == "title" then return end -- titles are earned, never purchasable
	local record = records[player.UserId]
	local data = DataService.Get(player)
	if not record or not data then return end
	local map = if kind == "effect" then Catalog.EffectByKey else Catalog.TrailByKey
	local entry = map[key]
	if not entry or entry.price <= 0 or (kind ~= "trail" and kind ~= "effect") then return end
	if record.owned[kind .. ":" .. key] then
		pushState(player)
		return
	end
	if not ProgressionService.SpendCoins(player, entry.price) then
		pushState(player)
		return
	end

	record.owned[kind .. ":" .. key] = true
	if kind == "trail" then record.trail = key else record.effect = key end
	saveRecord(player)
	pushState(player)
end)

equipRemote.OnServerEvent:Connect(function(player, kind, key)
	if not validRequest(player, kind, key) then return end
	local record = records[player.UserId]
	if not record then return end
	if kind == "trail" or kind == "effect" then
		if not owns(record, kind, key) then return end
		if kind == "trail" then record.trail = key else record.effect = key end
	elseif kind == "title" then
		local entry = Catalog.TitleByKey[key]
		if not entry or not getTitleUnlocked(player, entry) then return end
		record.title = key
	else
		return
	end
	saveRecord(player)
	pushState(player)
end)

requestRemote.OnServerEvent:Connect(function(player)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if not records[player.UserId] then loadPlayer(player) else pushState(player) end
end)

Players.PlayerAdded:Connect(loadPlayer)
for _, player in ipairs(Players:GetPlayers()) do loadPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
	saveRecord(player)
	records[player.UserId] = nil
	loading[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do saveRecord(player) end
end)

print(string.format("[Style] catalog ready: %d trails, %d effects, %d earned titles",
	#Catalog.Trails, #Catalog.Effects, #Catalog.Titles))

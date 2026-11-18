-- ShopService: замывает петлю награды. Владение живёт в отдельном DataStore,
-- поэтому не зависит от TEMPLATE профиля и переживает релог самостоятельно.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("ShopCatalog"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local BallService = Resolve.Require(ServerScriptService, "BallService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

local store = DataStoreService:GetDataStore("RagdollDodgeball_Shop_v1")
local records = {}
local warned = false

local folder = Instance.new("Folder")
folder.Name = "ShopRemotes"
folder.Parent = ReplicatedStorage

local function mk(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end

local stateRemote = mk("ShopState")
local buyRemote = mk("ShopBuyRequest")
local equipRemote = mk("ShopEquipRequest")
local ultRemote = mk("UltSelectRequest")

local byId = {}
for _, item in ipairs(Catalog.Balls) do byId[item.id] = item end

local function warnOnce(message)
	if warned then return end
	warned = true
	warn("[Shop] " .. message)
end

local function load(player)
	local rec = { owned = {}, equipped = "ball_default", ult = "Cannon" }
	local ok, result = pcall(function()
		return store:GetAsync("shop_" .. player.UserId)
	end)
	if ok and typeof(result) == "table" then
		if typeof(result.owned) == "table" then rec.owned = result.owned end
		if typeof(result.equipped) == "string" then rec.equipped = result.equipped end
		if typeof(result.ult) == "string" then rec.ult = result.ult end
	elseif not ok then
		warnOnce("Shop DataStore unavailable, ownership is session-only. "
			.. "Enable Studio Access to API Services or test in a published place.")
	end
	records[player.UserId] = rec
	return rec
end

local function save(userId)
	local rec = records[userId]
	if not rec then return end
	pcall(function()
		store:UpdateAsync("shop_" .. userId, function(old)
			local merged = { owned = {}, equipped = rec.equipped, ult = rec.ult }
			if typeof(old) == "table" and typeof(old.owned) == "table" then
				for key, value in pairs(old.owned) do merged.owned[key] = value end
			end
			for key, value in pairs(rec.owned) do merged.owned[key] = value end
			return merged
		end)
	end)
end

local function push(player)
	local rec = records[player.UserId]
	if not rec then return end
	local data = DataService.Get(player)
	stateRemote:FireClient(player, {
		coins = if data then data.coins else 0,
		level = if data then data.level else 1,
		owned = rec.owned,
		equipped = rec.equipped,
		ult = rec.ult,
	})
end

local function applyVisuals(player)
	local rec = records[player.UserId]
	if not rec then return end
	local item = byId[rec.equipped] or Catalog.Balls[1]
	player:SetAttribute("BallColor", item.color)
	player:SetAttribute("SelectedUlt", rec.ult)
end

local function owns(rec, item)
	return item.price == 0 or rec.owned[item.id] == true
end

local function spend(player, amount)
	if typeof(ProgressionService.SpendCoins) == "function" then
		return ProgressionService.SpendCoins(player, amount)
	end
	local data = DataService.Get(player)
	if not data or data.coins < amount then return false end
	data.coins -= amount
	warnOnce("ProgressionService.SpendCoins missing, deducting coins directly. "
		.. "HUD coin counter may lag until the next progression event.")
	return true
end

buyRemote.OnServerEvent:Connect(function(player, itemId)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if typeof(itemId) ~= "string" then return end
	local item = byId[itemId]
	local rec = records[player.UserId]
	if not item or not rec then return end
	if owns(rec, item) then return end
	if not spend(player, item.price) then return end

	rec.owned[item.id] = true
	rec.equipped = item.id
	save(player.UserId)
	applyVisuals(player)
	push(player)
	print(string.format("[Shop] %s bought %s for %d", player.Name, item.id, item.price))
end)

equipRemote.OnServerEvent:Connect(function(player, itemId)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if typeof(itemId) ~= "string" then return end
	local item = byId[itemId]
	local rec = records[player.UserId]
	if not item or not rec or not owns(rec, item) then return end

	rec.equipped = item.id
	save(player.UserId)
	applyVisuals(player)
	push(player)
end)

ultRemote.OnServerEvent:Connect(function(player, ultId)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if typeof(ultId) ~= "string" then return end
	local required = Catalog.UltLevels[ultId]
	local rec = records[player.UserId]
	local data = DataService.Get(player)
	if not required or not rec or not data then return end
	if data.level < required then return end

	rec.ult = ultId
	save(player.UserId)
	applyVisuals(player)
	push(player)
end)

BallService.PickedUp.Event:Connect(function(player)
	local character = player.Character
	if not character then return end
	local ball = BallService.GetHeld(character)
	local color = player:GetAttribute("BallColor")
	if ball and typeof(color) == "Color3" then
		ball.Color = color
	end
end)

local function onPlayer(player)
	task.spawn(function()
		for _ = 1, 100 do
			if DataService.Get(player) then break end
			task.wait(0.1)
		end
		load(player)
		applyVisuals(player)
		push(player)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
	save(player.UserId)
	records[player.UserId] = nil
end)

game:BindToClose(function()
	for userId in pairs(records) do save(userId) end
end)

task.spawn(function()
	while true do
		task.wait(2)
		for _, player in ipairs(Players:GetPlayers()) do push(player) end
	end
end)

print("[Shop] service up: " .. #Catalog.Balls .. " skins, own DataStore, ult gates")
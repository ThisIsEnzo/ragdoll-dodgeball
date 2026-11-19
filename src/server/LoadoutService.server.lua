-- LoadoutService: throw type selection, persisted per account.
-- Self-contained: own DataStore, own remotes, publishes ThrowType as a
-- player attribute that ThrowMods reads. No existing service is modified.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared:WaitForChild("Loadout"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

local store = DataStoreService:GetDataStore("RagdollDodgeball_Loadout_v1")
local records = {}
local warned = false

local folder = Instance.new("Folder")
folder.Name = "LoadoutRemotes"
folder.Parent = ReplicatedStorage

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateRemote = makeRemote("LoadoutState")
local selectRemote = makeRemote("LoadoutSelect")

local function warnOnce(message)
	if warned then return end
	warned = true
	warn("[Loadout] " .. message)
end

local function load(player)
	local record = { throwType = "Straight" }
	local ok, result = pcall(function()
		return store:GetAsync("loadout_" .. player.UserId)
	end)
	if ok and typeof(result) == "table" then
		if typeof(result.throwType) == "string" and Loadout.Types[result.throwType] then
			record.throwType = result.throwType
		end
	elseif not ok then
		warnOnce("DataStore unavailable, loadout is session-only.")
	end
	records[player.UserId] = record
	return record
end

local function save(userId)
	local record = records[userId]
	if not record then return end
	pcall(function()
		store:UpdateAsync("loadout_" .. userId, function()
			return { throwType = record.throwType }
		end)
	end)
end

local function levelOf(player)
	local data = DataService.Get(player)
	if data then return data.level end
	return 1
end

local function apply(player)
	local record = records[player.UserId]
	if not record then return end
	local entry = Loadout.Types[record.throwType]
	if not entry then return end
	if levelOf(player) < entry.level then
		record.throwType = "Straight"
	end
	player:SetAttribute("ThrowType", record.throwType)
end

local function push(player)
	local record = records[player.UserId]
	if not record then return end
	stateRemote:FireClient(player, {
		level = levelOf(player),
		selected = record.throwType,
	})
end

selectRemote.OnServerEvent:Connect(function(player, typeId)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if typeof(typeId) ~= "string" then return end
	local entry = Loadout.Types[typeId]
	local record = records[player.UserId]
	if not entry or not record then return end
	if levelOf(player) < entry.level then return end

	record.throwType = typeId
	save(player.UserId)
	apply(player)
	push(player)
	print(string.format("[Loadout] %s selected %s", player.Name, typeId))
end)

local function onPlayer(player)
	task.spawn(function()
		for _ = 1, 100 do
			if DataService.Get(player) then break end
			task.wait(0.1)
		end
		load(player)
		apply(player)
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
		for _, player in ipairs(Players:GetPlayers()) do
			apply(player)
			push(player)
		end
	end
end)

print("[Loadout] service up: " .. #Loadout.Order .. " throw types")
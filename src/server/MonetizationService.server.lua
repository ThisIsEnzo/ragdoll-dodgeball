-- MonetizationService: gamepass ownership and developer product receipts.
--
-- Ownership is checked on join and refreshed after a purchase prompt closes.
-- Receipts are idempotent: a purchaseId is written to a dedicated DataStore
-- before the grant, so a re-delivered receipt cannot double-pay.
--
-- Every effect is applied through ProgressionService hooks, so the reward
-- pipeline stays in one place.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("MonetizationCatalog"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local DataService = Resolve.Require(ServerScriptService, "DataService")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local AnalyticsService = Resolve.Require(ServerScriptService, "AnalyticsService")

local receiptStore = DataStoreService:GetDataStore("RagdollDodgeball_Receipts_v1")
local owned = {}
local warned = false

local folder = Instance.new("Folder")
folder.Name = "StoreRemotes"
folder.Parent = ReplicatedStorage

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateRemote = makeRemote("StoreState")
local refreshRemote = makeRemote("StoreRefresh")

local passById = {}
local productById = {}
for _, pass in ipairs(Catalog.GamePasses) do
	if pass.id > 0 then passById[pass.id] = pass end
end
for _, product in ipairs(Catalog.Products) do
	if product.id > 0 then productById[product.id] = product end
end

local function warnOnce(message)
	if warned then return end
	warned = true
	warn("[Store] " .. message)
end

local function configured()
	local count = 0
	for _ in pairs(passById) do count += 1 end
	for _ in pairs(productById) do count += 1 end
	return count
end

local function applyEffects(player)
	local set = owned[player.UserId]
	if not set then return end

	local coinMult, xpMult, slots = 1, 1, nil
	local gold, badge, announce = false, false, false

	for _, pass in ipairs(Catalog.GamePasses) do
		if set[pass.key] then
			local effect = Catalog.Effects[pass.key]
			if effect then
				if effect.coinMultiplier then coinMult = math.max(coinMult, effect.coinMultiplier) end
				if effect.xpMultiplier then xpMult = math.max(xpMult, effect.xpMultiplier) end
				if effect.questSlots then slots = math.max(slots or 0, effect.questSlots) end
				if effect.goldTag then gold = true end
				if effect.badge then badge = true end
				if effect.announce then announce = true end
			end
		end
	end

	ProgressionService.CoinMultiplier[player.UserId] = coinMult
	ProgressionService.XpMultiplier[player.UserId] = xpMult
	if slots then ProgressionService.QuestSlots[player.UserId] = slots end

	player:SetAttribute("VIP", badge)
	player:SetAttribute("GoldTag", gold)
	player:SetAttribute("RadioAnnounce", announce)

	ProgressionService.SyncQuestSlots(player)
end

local function push(player)
	local set = owned[player.UserId] or {}
	local list = {}
	for _, pass in ipairs(Catalog.GamePasses) do
		table.insert(list, { key = pass.key, owned = set[pass.key] == true, configured = pass.id > 0 })
	end
	stateRemote:FireClient(player, { passes = list })
end

local function checkOwnership(player)
	local set = {}
	for _, pass in ipairs(Catalog.GamePasses) do
		if pass.id > 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and result then
				set[pass.key] = true
			elseif not ok then
				warnOnce("Ownership check failed. Publish the place and configure gamepass ids.")
			end
		end
	end
	owned[player.UserId] = set
	applyEffects(player)
	push(player)
end

MarketplaceService.ProcessReceipt = function(receipt)
	local product = productById[receipt.ProductId]
	if not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = tostring(receipt.PlayerId) .. "_" .. tostring(receipt.PurchaseId)
	local alreadyGranted = false

	local ok = pcall(function()
		receiptStore:UpdateAsync(key, function(old)
			if old == true then
				alreadyGranted = true
				return true
			end
			return true
		end)
	end)

	if not ok then
		warnOnce("Receipt store unavailable, deferring grant.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if alreadyGranted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if product.coins then
		ProgressionService.GrantCoins(player, product.coins)
		print(string.format("[Store] %s bought %d coins", player.Name, product.coins))
	end

	if product.reroll then
		ProgressionService.RerollQuests(player)
		print(string.format("[Store] %s rerolled quests", player.Name))
	end

	AnalyticsService.Event(player, "purchase", { key = product.key, productId = receipt.ProductId })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	local pass = passById[gamePassId]
	if not pass then return end
	local set = owned[player.UserId] or {}
	set[pass.key] = true
	owned[player.UserId] = set
	applyEffects(player)
	push(player)
	AnalyticsService.Event(player, "gamepass", { key = pass.key })
	print(string.format("[Store] %s unlocked %s", player.Name, pass.name))
end)

refreshRemote.OnServerEvent:Connect(function(player)
	task.spawn(checkOwnership, player)
end)

local function onPlayer(player)
	task.spawn(function()
		for _ = 1, 100 do
			if DataService.Get(player) then break end
			task.wait(0.1)
		end
		checkOwnership(player)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
	owned[player.UserId] = nil
end)

if configured() == 0 then
	warn("[Store] No ids configured. Create gamepasses and products in Creator Hub, then paste ids into MonetizationCatalog.")
else
	print("[Store] " .. configured() .. " items configured")
end

print("[Store] monetization service up")
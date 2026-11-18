-- PromoService: redeemable codes that grant coins.
-- Marketing lever for short-form video: a code in the clip description gives
-- the viewer a reason to join now, and every redemption is an attributable event.
--
-- Self-contained: own DataStore, own remotes, no edits to existing services.
-- Redemption is server-authoritative and one-time per account per code.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Resolve = require(Shared:WaitForChild("Resolve"))

local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local DataService = Resolve.Require(ServerScriptService, "DataService")
local AnalyticsService = Resolve.Require(ServerScriptService, "AnalyticsService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

-- Add new codes here. Keep them short, uppercase, easy to read aloud in a clip.
local CODES = {
	BONK = { coins = 500, label = "Launch bonus" },
	LAUNCH = { coins = 1000, label = "Welcome pack" },
	TIKTOK = { coins = 750, label = "Creator bonus" },
}

local store = DataStoreService:GetDataStore("RagdollDodgeball_Promo_v1")
local records = {}
local warned = false

local folder = Instance.new("Folder")
folder.Name = "PromoRemotes"
folder.Parent = ReplicatedStorage

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local redeemRemote = makeRemote("PromoRedeem")
local resultRemote = makeRemote("PromoResult")

local function warnOnce(message)
	if warned then return end
	warned = true
	warn("[Promo] " .. message)
end

local function load(player)
	local record = { redeemed = {} }
	local ok, result = pcall(function()
		return store:GetAsync("promo_" .. player.UserId)
	end)
	if ok and typeof(result) == "table" and typeof(result.redeemed) == "table" then
		record.redeemed = result.redeemed
	elseif not ok then
		warnOnce("DataStore unavailable, redemptions are session-only. "
			.. "Enable Studio Access to API Services or test in a published place.")
	end
	records[player.UserId] = record
	return record
end

local function save(userId)
	local record = records[userId]
	if not record then return end
	pcall(function()
		store:UpdateAsync("promo_" .. userId, function(old)
			local merged = { redeemed = {} }
			if typeof(old) == "table" and typeof(old.redeemed) == "table" then
				for key, value in pairs(old.redeemed) do
					merged.redeemed[key] = value
				end
			end
			for key, value in pairs(record.redeemed) do
				merged.redeemed[key] = value
			end
			return merged
		end)
	end)
end

local function normalize(raw)
	if typeof(raw) ~= "string" then return nil end
	local stripped = string.gsub(raw, "%s+", "")
	if #stripped == 0 or #stripped > 24 then return nil end
	return string.upper(stripped)
end

redeemRemote.OnServerEvent:Connect(function(player, rawCode)
	if not AntiCheat.Allow(player, "ShopBuy") then return end

	local code = normalize(rawCode)
	if not code then
		resultRemote:FireClient(player, false, "Enter a code")
		return
	end

	local entry = CODES[code]
	if not entry then
		resultRemote:FireClient(player, false, "Unknown code")
		return
	end

	local record = records[player.UserId]
	if not record then
		resultRemote:FireClient(player, false, "Still loading, try again")
		return
	end

	if record.redeemed[code] == true then
		resultRemote:FireClient(player, false, "Already used")
		return
	end

	if not DataService.Get(player) then
		resultRemote:FireClient(player, false, "Still loading, try again")
		return
	end

	record.redeemed[code] = true
	save(player.UserId)
	ProgressionService.AddCoins(player, entry.coins)

	resultRemote:FireClient(player, true, string.format("+%d coins  %s", entry.coins, entry.label))
	AnalyticsService.Event(player, "promo_redeem", { code = code, coins = entry.coins })
	print(string.format("[Promo] %s redeemed %s for %d coins", player.Name, code, entry.coins))
end)

local function onPlayer(player)
	task.spawn(function()
		for _ = 1, 100 do
			if DataService.Get(player) then break end
			task.wait(0.1)
		end
		load(player)
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

local count = 0
for _ in pairs(CODES) do count += 1 end
print("[Promo] service up: " .. count .. " active codes")
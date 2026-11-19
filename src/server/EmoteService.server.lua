-- EmoteService: celebrations with a cooldown.
-- Emotes never grant invulnerability, speed or hitbox changes. The physics
-- impulses are small and self-cancelling so an emote cannot be used to dodge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("RankCatalog"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")

local byKey = {}
for _, emote in ipairs(Catalog.Emotes) do byKey[emote.key] = emote end

local lastUse = {}

local folder = Instance.new("Folder")
folder.Name = "EmoteRemotes"
folder.Parent = ReplicatedStorage

local requestRemote = folder:FindFirstChild("EmoteRequest")
if not requestRemote then
	requestRemote = Instance.new("RemoteEvent")
	requestRemote.Name = "EmoteRequest"
	requestRemote.Parent = folder
end

requestRemote.OnServerEvent:Connect(function(player, key)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if typeof(key) ~= "string" then return end
	local emote = byKey[key]
	if not emote then return end

	local now = os.clock()
	if (lastUse[player.UserId] or 0) > now then return end

	local character = player.Character
	if not character then return end
	if character:GetAttribute("Benched") then return end
	if RagdollService.IsActive(character) then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	lastUse[player.UserId] = now + Catalog.EmoteCooldown

	character:SetAttribute("EmoteKey", key)
	character:SetAttribute("EmoteAt", now)

	if emote.impulse == "spin" then
		root.AssemblyAngularVelocity = Vector3.new(0, 14, 0)
		task.delay(0.45, function()
			if root.Parent then root.AssemblyAngularVelocity = Vector3.zero end
		end)
	elseif emote.impulse == "jump" then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, 42, v.Z)
	end

	Net.FireAll("FXEvent", "emote", character, key)
end)

Players.PlayerRemoving:Connect(function(player)
	lastUse[player.UserId] = nil
end)

print("[Emotes] " .. #Catalog.Emotes .. " celebrations ready")
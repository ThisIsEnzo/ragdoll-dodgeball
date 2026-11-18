-- AbilityService: Hype-метр и ульты Cannon / Magnet / Wall / Ghost.
-- Уровень анлока проверяется на сервере: объявление анлока должно быть правдой.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))
local Catalog = require(Shared:WaitForChild("ShopCatalog"))
local BallService = require(script.Parent:WaitForChild("BallService"))
local DataService = Resolve.Require(ServerScriptService, "DataService")

local AbilityService = {}

local hype: { [number]: number } = {}
local shields: { [number]: number } = {}

local ULTS = { Cannon = true, Magnet = true, Wall = true, Ghost = true }

local function push(player: Player)
	Net.FireClient("HypeState", player, hype[player.UserId] or 0, CFG.Hype.Max)
end

function AbilityService.Init() end

function AbilityService.AddHype(player: Player?, amount: number)
	if not player then return end
	hype[player.UserId] = math.clamp((hype[player.UserId] or 0) + amount, 0, CFG.Hype.Max)
	push(player)
end

function AbilityService.GetHype(player: Player): number
	return hype[player.UserId] or 0
end

function AbilityService.UnlockedLevel(ultId: string): number
	return Catalog.UltLevels[ultId] or 1
end

function AbilityService.Use(player: Player, ultId: any): boolean
	if typeof(ultId) ~= "string" or not ULTS[ultId] then return false end
	if (hype[player.UserId] or 0) < CFG.Hype.Max then return false end

	local data = DataService.Get(player)
	local level = if data then data.level else 1
	if level < AbilityService.UnlockedLevel(ultId) then return false end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	if ultId == "Cannon" then
		player:SetAttribute("CannonUntil", os.clock() + 8)
	elseif ultId == "Magnet" then
		local ball = BallService.NearestFree(root.Position, 40)
		if not ball or not BallService.GiveBall(character, ball) then return false end
	elseif ultId == "Wall" then
		local team = character:GetAttribute("Team")
		if typeof(team) ~= "number" then return false end
		shields[team] = 1
		task.delay(5, function() shields[team] = nil end)
	elseif ultId == "Ghost" then
		player:SetAttribute("InvulnUntil", os.clock() + 2)
	end

	hype[player.UserId] = 0
	push(player)
	Net.FireAll("FXEvent", "ult", character, ultId)
	return true
end

function AbilityService.ConsumeCannon(player: Player): (number, boolean)
	local until_ = player:GetAttribute("CannonUntil")
	if typeof(until_) == "number" and os.clock() < until_ then
		player:SetAttribute("CannonUntil", nil)
		return 1.6, true
	end
	return 1, false
end

function AbilityService.IsInvulnerable(player: Player?): boolean
	if not player then return false end
	local until_ = player:GetAttribute("InvulnUntil")
	return typeof(until_) == "number" and os.clock() < until_
end

function AbilityService.ConsumeShield(team: number?): boolean
	if typeof(team) ~= "number" then return false end
	if shields[team] then
		shields[team] = nil
		return true
	end
	return false
end

function AbilityService.Start()
	Players.PlayerAdded:Connect(function(player)
		hype[player.UserId] = 0
		push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		hype[player.UserId] = nil
	end)
end

return AbilityService
-- CatchService: catch is a stance resolved on contact.
-- Audit fix: catching used to require a Player, so bots could never catch.
-- Stances are now keyed by character Model, and bots use the same path.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local RoundService = Resolve.Require(ServerScriptService, "RoundService")

local CatchService = {}
CatchService.Caught = Instance.new("BindableEvent")

local MatchService, AbilityService
local stance = {}
local cooldown = {}

function CatchService.Init(matchService, abilityService)
	MatchService = matchService
	AbilityService = abilityService
end

local function stagger(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed * 0.5
	task.delay(CFG.Catch.Stagger, function()
		if humanoid.Parent then humanoid.WalkSpeed = CFG.Movement.WalkSpeed end
	end)
end

local function succeed(character, ball)
	local player = Players:GetPlayerFromCharacter(character)
	local thrower = BallService.LastThrower(ball)

	if thrower and thrower.Parent and not RagdollService.IsActive(thrower) then
		local throwerRoot = thrower:FindFirstChild("HumanoidRootPart")
		local root = character:FindFirstChild("HumanoidRootPart")
		if throwerRoot and root then
			RagdollService.Knockback(thrower, throwerRoot.Position - root.Position, CFG.Impact.CatchKnockback)
			if MatchService then MatchService.OnKO(thrower, "caught") end
		end
	end

	BallService.GiveBall(character, ball)

	local team = RoundService.TeamOf(character)
	local revived = false
	if team and MatchService then revived = MatchService.ReviveOne(team) end
	if player and AbilityService then AbilityService.AddHype(player, CFG.Hype.Catch) end

	stance[character] = nil
	if player then
		CatchService.Caught:Fire(player, revived)
	else
		CatchService.Caught:Fire(nil, revived, character)
	end
	Net.FireAll("FXEvent", "catch", character, thrower)
end

local function speedOk(ball)
	local speed = ball.AssemblyLinearVelocity.Magnitude
	return speed >= CFG.Ball.MinHitSpeed and speed <= CFG.Catch.MaxSpeed
end

local function eligible(character, ball)
	if not character or not character.Parent then return false end
	if character:GetAttribute("Benched") then return false end
	if RagdollService.IsActive(character) then return false end
	if ball:GetAttribute("HeldBy") then return false end
	if ball:GetAttribute("Uncatchable") then return false end
	if not speedOk(ball) then return false end
	local thrower = BallService.LastThrower(ball)
	if not thrower or thrower == character then return false end
	if thrower:GetAttribute("Team") == character:GetAttribute("Team") then return false end
	return true
end

-- Opens a stance for any actor, player or bot.
function CatchService.OpenStance(character, seconds)
	if not character then return end
	local duration = seconds or CFG.Catch.StanceSeconds
	stance[character] = { expires = os.clock() + duration, token = os.clock() }
	local player = Players:GetPlayerFromCharacter(character)
	if player then player:SetAttribute("CatchAttemptAt", os.clock()) end
	Net.FireAll("FXEvent", "stance", character)
end

-- Called from the hit pipeline before damage. Returns true when the hit became a catch.
function CatchService.Intercept(character, ball)
	local entry = stance[character]
	if not entry then return false end
	if os.clock() > entry.expires then return false end
	if not eligible(character, ball) then return false end
	succeed(character, ball)
	return true
end

function CatchService.InStance(character)
	local entry = stance[character]
	return entry ~= nil and os.clock() <= entry.expires
end

-- Player button press: open a stance and try an immediate grab.
function CatchService.Try(player, aimDir)
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return false end

	local now = os.clock()
	if (cooldown[player.UserId] or 0) > now then return false end

	CatchService.OpenStance(character)
	local entry = stance[character]

	local ping = player:GetNetworkPing()
	local sampleTime = workspace:GetServerTimeNow() - ping

	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace)
			and ball:GetAttribute("Clean") and eligible(character, ball) then
			local position = BallService.SampleAt(ball, sampleTime) or ball.Position
			if (position - root.Position).Magnitude <= CFG.Catch.Distance then
				succeed(character, ball)
				return true
			end
		end
	end

	task.delay(CFG.Catch.StanceSeconds, function()
		local current = stance[character]
		if current and entry and current.token == entry.token then
			stance[character] = nil
			cooldown[player.UserId] = os.clock() + CFG.Catch.WhiffCooldown
			if character.Parent and not character:GetAttribute("Benched") then
				stagger(character)
				Net.FireAll("FXEvent", "whiff", character)
			end
		end
	end)

	return false
end

function CatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		cooldown[player.UserId] = nil
		if player.Character then stance[player.Character] = nil end
	end)
end

return CatchService
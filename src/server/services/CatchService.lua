-- CatchService: catch is a stance resolved on contact.
--
-- Change: catching no longer knocks the thrower out. The old rule called
-- MatchService.OnKO on the thrower, which ragdolled them and read as "I got
-- hit" rather than "my throw was caught". Classic dodgeball does eliminate
-- the thrower, so PUNISH_THROWER is kept as a switch if that rule is wanted
-- later. Default is off.
--
-- A catch still swings the round: possession changes, a benched teammate
-- returns, and the catcher gains hype. The thrower only loses tempo.

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

-- Set true to restore the classic rule where a caught throw eliminates
-- the thrower. Left false because it reads as a bug in playtests.
local PUNISH_THROWER = false

-- Tempo penalty applied to the thrower instead of a knockout.
local STAGGER_SECONDS = 0.9
local STAGGER_SPEED_MUL = 0.55

local CatchService = {}
CatchService.Caught = Instance.new("BindableEvent")

local MatchService, AbilityService
local stance = {}
local cooldown = {}
local staggered = {}

function CatchService.Init(matchService, abilityService)
	MatchService = matchService
	AbilityService = abilityService
end

local function applySpeed(character, multiplier, seconds)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local token = os.clock()
	staggered[character] = token
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed * multiplier

	task.delay(seconds, function()
		if staggered[character] ~= token then return end
		staggered[character] = nil
		if humanoid.Parent then
			humanoid.WalkSpeed = CFG.Movement.WalkSpeed
		end
	end)
end

local function succeed(character, ball)
	local player = Players:GetPlayerFromCharacter(character)
	local thrower = BallService.LastThrower(ball)

	if thrower and thrower.Parent and thrower ~= character then
		if PUNISH_THROWER then
			local throwerRoot = thrower:FindFirstChild("HumanoidRootPart")
			local root = character:FindFirstChild("HumanoidRootPart")
			if throwerRoot and root and not RagdollService.IsActive(thrower) then
				RagdollService.Knockback(thrower, throwerRoot.Position - root.Position, CFG.Impact.CatchKnockback)
				if MatchService then MatchService.OnKO(thrower, "caught") end
			end
		elseif not RagdollService.IsActive(thrower) and not thrower:GetAttribute("Benched") then
			-- Tempo loss only: no ragdoll, no elimination, no bench.
			applySpeed(thrower, STAGGER_SPEED_MUL, STAGGER_SECONDS)
		end
	end

	BallService.GiveBall(character, ball)

	local team = RoundService.TeamOf(character)
	local revived = false
	if team and MatchService then
		revived = MatchService.ReviveOne(team)
	end
	if player and AbilityService then
		AbilityService.AddHype(player, CFG.Hype.Catch)
	end

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

function CatchService.OpenStance(character, seconds)
	if not character then return end
	local duration = seconds or CFG.Catch.StanceSeconds
	stance[character] = { expires = os.clock() + duration, token = os.clock() }

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		player:SetAttribute("CatchAttemptAt", os.clock())
	end
	Net.FireAll("FXEvent", "stance", character)
end

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
				applySpeed(character, 0.5, CFG.Catch.Stagger)
				Net.FireAll("FXEvent", "whiff", character)
			end
		end
	end)

	return false
end

function CatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		cooldown[player.UserId] = nil
		local character = player.Character
		if character then
			stance[character] = nil
			staggered[character] = nil
		end
	end)
end

return CatchService
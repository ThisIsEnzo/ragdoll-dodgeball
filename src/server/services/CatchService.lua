-- CatchService v0.5.0: ловля с компенсацией лага и grace-окном.
-- Новое: событие Caught для прогрессии (квесты, XP, монеты).

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

local MatchService
local AbilityService
local cooldownUntil: { [number]: number } = {}

function CatchService.Init(matchService, abilityService)
	MatchService = matchService
	AbilityService = abilityService
end

local function stagger(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed * 0.4
	task.delay(CFG.Catch.Stagger, function()
		if humanoid.Parent then humanoid.WalkSpeed = CFG.Movement.WalkSpeed end
	end)
end

local function succeed(player: Player, character: Model, ball: BasePart)
	local thrower = BallService.LastThrower(ball)
	if thrower and thrower.Parent and not RagdollService.IsActive(thrower) then
		local throwerRoot = thrower:FindFirstChild("HumanoidRootPart") :: BasePart?
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if throwerRoot and root then
			RagdollService.Knockback(thrower, throwerRoot.Position - root.Position, CFG.Impact.CatchKnockback)
			if MatchService then MatchService.OnKO(thrower, "caught") end
		end
	end

	BallService.GiveBall(character, ball)

	local team = RoundService.TeamOf(character)
	local revived = false
	if team and MatchService then
		revived = MatchService.ReviveOne(team)
	end
	if AbilityService then AbilityService.AddHype(player, CFG.Hype.Catch) end

	CatchService.Caught:Fire(player, revived)
	Net.FireAll("FXEvent", "catch", character, thrower)
end

local function findCatchable(character: Model, root: BasePart, t: number): BasePart?
	local look = root.CFrame.LookVector
	local halfCone = math.rad(CFG.Catch.ConeDeg / 2)

	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart")
			and ball:IsDescendantOf(workspace)
			and not ball:GetAttribute("HeldBy")
			and ball:GetAttribute("Clean")
			and not ball:GetAttribute("Uncatchable") then

			local speed = ball.AssemblyLinearVelocity.Magnitude
			if speed >= CFG.Ball.MinHitSpeed and speed <= CFG.Catch.MaxSpeed then
				local position = BallService.SampleAt(ball, t) or ball.Position
				local offset = position - root.Position
				if offset.Magnitude <= CFG.Catch.Distance then
					local angle = math.acos(math.clamp(look:Dot(offset.Unit), -1, 1))
					if angle <= halfCone then
						local thrower = BallService.LastThrower(ball)
						if thrower and thrower ~= character then
							return ball
						end
					end
				end
			end
		end
	end
	return nil
end

function CatchService.Try(player: Player): boolean
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return false end

	local now = os.clock()
	if (cooldownUntil[player.UserId] or 0) > now then return false end

	player:SetAttribute("CatchAttemptAt", now)

	local sampleTime = workspace:GetServerTimeNow() - player:GetNetworkPing()
	local ball = findCatchable(character, root, sampleTime)

	if not ball then
		cooldownUntil[player.UserId] = now + CFG.Catch.WhiffCooldown
		stagger(character)
		Net.FireAll("FXEvent", "whiff", character)
		return false
	end

	succeed(player, character, ball)
	return true
end

function CatchService.GraceCatch(player: Player, ball: BasePart): boolean
	if ball:GetAttribute("Uncatchable") then return false end
	if ball.AssemblyLinearVelocity.Magnitude > CFG.Catch.MaxSpeed then return false end
	local character = player.Character
	if not character or RagdollService.IsActive(character) then return false end
	succeed(player, character, ball)
	return true
end

function CatchService.InGrace(player: Player?): boolean
	if not player then return false end
	local at = player:GetAttribute("CatchAttemptAt")
	return typeof(at) == "number" and os.clock() - at <= CFG.Impact.CatchGrace
end

function CatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player.UserId] = nil
	end)
end

return CatchService

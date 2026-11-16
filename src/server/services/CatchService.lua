-- CatchService: сигнатурная механика. Ловля с компенсацией лага.
-- Успех: бросавший выбит, союзник воскрешён, мяч в руках. Промах: стаггер и кулдаун.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local BallService = require(script.Parent:WaitForChild("BallService"))
local RagdollService = require(script.Parent:WaitForChild("RagdollService"))
local RoundService = require(script.Parent:WaitForChild("RoundService"))

local CatchService = {}
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

local function findCatchable(character: Model, root: BasePart, t: number): BasePart?
	local look = root.CFrame.LookVector
	local halfCone = math.rad(CFG.Catch.ConeDeg / 2)

	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart")
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

	local ping = player:GetNetworkPing()
	local sampleTime = workspace:GetServerTimeNow() - ping
	local ball = findCatchable(character, root, sampleTime)

	if not ball then
		cooldownUntil[player.UserId] = now + CFG.Catch.WhiffCooldown
		stagger(character)
		Net.FireAll("FXEvent", "whiff", character)
		return false
	end

	local thrower = BallService.LastThrower(ball)
	if thrower and thrower.Parent and not RagdollService.IsActive(thrower) then
		local throwerRoot = thrower:FindFirstChild("HumanoidRootPart") :: BasePart?
		if throwerRoot then
			local direction = (throwerRoot.Position - root.Position).Unit
			RagdollService.Apply(thrower, direction * 70)
			if MatchService then MatchService.OnKO(thrower, "caught") end
		end
	end

	BallService.GiveBall(character, ball)
	ball:SetAttribute("Clean", false)

	local team = RoundService.TeamOf(character)
	if team and MatchService then MatchService.ReviveOne(team) end
	if AbilityService then AbilityService.AddHype(player, CFG.Hype.Catch) end

	Net.FireAll("FXEvent", "catch", character, thrower)
	return true
end

function CatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player.UserId] = nil
	end)
end

return CatchService

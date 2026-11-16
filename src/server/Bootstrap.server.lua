-- Bootstrap v0.3.0: попадания приходят из sweep-сигнала BallService, не из Touched.
-- Откат считает RagdollService по модели Impact. Физика мяча игрока не толкает.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Bootstrap] В ReplicatedStorage нет папки Shared")

local CFG = require(Shared:WaitForChild("BalanceConfig", 20))
local Net = require(Shared:WaitForChild("Net", 20))
local Resolve = require(Shared:WaitForChild("Resolve", 20))
local Collision = require(Shared:WaitForChild("Collision", 20))

Collision.Setup()
Resolve.Report(ServerScriptService, "Bootstrap")

local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local BallService = Resolve.Require(ServerScriptService, "BallService")
local RoundService = Resolve.Require(ServerScriptService, "RoundService")
local AbilityService = Resolve.Require(ServerScriptService, "AbilityService")
local MatchService = Resolve.Require(ServerScriptService, "MatchService")
local CatchService = Resolve.Require(ServerScriptService, "CatchService")

Net.Init()
CatchService.Init(MatchService, AbilityService)

local ORDER = { AntiCheat, RagdollService, BallService, RoundService, AbilityService, MatchService, CatchService }

for _, service in ipairs(ORDER) do
	if service.Init and service ~= CatchService then service.Init() end
end
for _, service in ipairs(ORDER) do
	if service.Start then service.Start() end
end

BallService.SpawnAll()

local throwCooldown: { [number]: number } = {}
local dodgeCooldown: { [number]: number } = {}

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed
	humanoid.JumpPower = CFG.Movement.JumpPower
	character:SetAttribute("Benched", false)
	character:SetAttribute("Ragdolled", false)
	RagdollService.Prepare(character)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then onCharacter(player.Character) end
	MatchService.Enqueue(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end

Net.On("ThrowRequest", function(player: Player, charge: any, aimDir: any)
	if not AntiCheat.Allow(player, "Throw") then return end
	if not AntiCheat.ValidCharge(charge) or not AntiCheat.ValidDirection(aimDir) then return end

	local now = os.clock()
	if (throwCooldown[player.UserId] or 0) > now then return end

	local character = player.Character
	if not character or character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end
	local ball = BallService.GetHeld(character)
	if not ball then return end

	local cannonMul, uncatchable = AbilityService.ConsumeCannon(player)
	local suddenMul = if RoundService.IsSuddenDeath() then CFG.Round.SuddenDeathSpeedMul else 1

	if BallService.Throw(character, ball, aimDir, charge, cannonMul * suddenMul) then
		throwCooldown[player.UserId] = now + CFG.Throw.Cooldown
		if uncatchable then ball:SetAttribute("Uncatchable", true) end
		Net.FireAll("FXEvent", "throw", ball, player.UserId)
	end
end)

Net.On("CatchRequest", function(player: Player)
	if not AntiCheat.Allow(player, "Catch") then return end
	CatchService.Try(player)
end)

Net.On("DodgeRequest", function(player: Player, direction: any)
	if not AntiCheat.Allow(player, "Dodge") then return end
	local now = os.clock()
	if (dodgeCooldown[player.UserId] or 0) > now then return end
	if not AntiCheat.ValidDirection(direction) then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or character:GetAttribute("Benched") then return end

	dodgeCooldown[player.UserId] = now + CFG.Movement.DodgeCooldown
	player:SetAttribute("InvulnUntil", now + CFG.Movement.DodgeIFrames)
	root.AssemblyLinearVelocity = Vector3.new(
		direction.Unit.X * CFG.Movement.DodgeSpeed,
		6,
		direction.Unit.Z * CFG.Movement.DodgeSpeed
	)
	Net.FireAll("FXEvent", "dodge", character)
end)

Net.On("UltRequest", function(player: Player, ultId: any)
	if not AntiCheat.Allow(player, "Ult") then return end
	AbilityService.Use(player, ultId)
end)

Net.On("QueueJoin", function(player: Player)
	if not AntiCheat.Allow(player, "QueueJoin") then return end
	MatchService.Enqueue(player)
end)

Net.On("RematchRequest", function(player: Player)
	if not AntiCheat.Allow(player, "QueueJoin") then return end
	MatchService.Enqueue(player)
end)

Net.On("PingRequest", function(player: Player, position: any)
	if not AntiCheat.Allow(player, "PingRequest", 0.2) then return end
	local character = player.Character
	if not character or not character:GetAttribute("Benched") then return end
	if typeof(position) ~= "Vector3" then return end
	Net.FireAll("FXEvent", "ping", position, player.UserId)
end)

-- Единая точка правил попадания
BallService.HitDetected.Event:Connect(function(ball: BasePart, character: Model, speed: number)
	if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end

	local thrower = BallService.LastThrower(ball)
	if not thrower or thrower == character then return end
	if thrower:GetAttribute("Team") == character:GetAttribute("Team") then return end

	local victimPlayer = Players:GetPlayerFromCharacter(character)

	if CatchService.InGrace(victimPlayer) and CatchService.GraceCatch(victimPlayer, ball) then
		return
	end

	if AbilityService.IsInvulnerable(victimPlayer) then return end

	if AbilityService.ConsumeShield(character:GetAttribute("Team")) then
		ball.AssemblyLinearVelocity = -ball.AssemblyLinearVelocity * 0.4
		Net.FireAll("FXEvent", "shield", character)
		return
	end

	if RagdollService.Hit(character, ball.AssemblyLinearVelocity) then
		MatchService.OnKO(character, "hit")
		AbilityService.AddHype(Players:GetPlayerFromCharacter(thrower), CFG.Hype.Hit)
		ball.AssemblyLinearVelocity *= CFG.Impact.HitSlowdown
		Net.FireAll("FXEvent", "ko", character, thrower, speed)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	throwCooldown[player.UserId] = nil
	dodgeCooldown[player.UserId] = nil
end)

print("[RagdollDodgeball] v0.3.0 запущен: контролируемый откат, перенос без физики, sweep-попадания")

-- Bootstrap v0.10.0: ловля разрешается на контакте через стойку.
-- CatchRequest принимает направление камеры, попадание сначала пробует превратиться в ловлю.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Bootstrap] ReplicatedStorage.Shared is missing")

local CFG = require(Shared:WaitForChild("BalanceConfig", 20))
local Net = require(Shared:WaitForChild("Net", 20))
local Resolve = require(Shared:WaitForChild("Resolve", 20))
local Collision = require(Shared:WaitForChild("Collision", 20))
local AimAssist = require(Shared:WaitForChild("AimAssist", 20))

Collision.Setup()
Resolve.Report(ServerScriptService, "Bootstrap")

local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")
local ArenaService = Resolve.Require(ServerScriptService, "ArenaService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local BallService = Resolve.Require(ServerScriptService, "BallService")
local RoundService = Resolve.Require(ServerScriptService, "RoundService")
local AbilityService = Resolve.Require(ServerScriptService, "AbilityService")
local TeamIdentityService = Resolve.Require(ServerScriptService, "TeamIdentityService")
local AnalyticsService = Resolve.Require(ServerScriptService, "AnalyticsService")
local DataService = Resolve.Require(ServerScriptService, "DataService")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local FtueService = Resolve.Require(ServerScriptService, "FtueService")
local MatchService = Resolve.Require(ServerScriptService, "MatchService")
local CatchService = Resolve.Require(ServerScriptService, "CatchService")

Net.Init()
CatchService.Init(MatchService, AbilityService)

local ORDER = {
	AntiCheat, ArenaService, RagdollService, BallService, RoundService, AbilityService,
	TeamIdentityService, AnalyticsService, DataService, ProgressionService,
	FtueService, MatchService, CatchService,
}

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
	character:SetAttribute("Carrying", false)
	character:SetAttribute("IsBot", false)

	local owner = Players:GetPlayerFromCharacter(character)
	if owner then character:SetAttribute("DisplayName", owner.DisplayName) end

	RagdollService.Prepare(character)
	TeamIdentityService.Refresh(character)
end

local function onPlayer(player: Player)
	player:SetAttribute("MatchesThisSession", 0)
	ProgressionService.OnPlayer(player)
	FtueService.OnPlayer(player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then onCharacter(player.Character) end
	MatchService.Enqueue(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, player) end

AntiCheat.Flagged.Event:Connect(function(player: Player, reason: string, total: number)
	AnalyticsService.Event(player, "security_flag", { reason = reason, total = total })
	warn(string.format("[Security] %s: %s (total %d)", player.Name, reason, total))
end)

BallService.PickedUp.Event:Connect(function(player: Player)
	FtueService.PickedUp(player)
end)

CatchService.Caught.Event:Connect(function(player: Player, revived: boolean)
	ProgressionService.RegisterStat(player, "catches", 1)
	FtueService.Caught(player)
	if revived then
		ProgressionService.RegisterStat(player, "revives", 1)
		FtueService.Revived(player)
	end
end)

local function enemyTargets(character: Model)
	local team = character:GetAttribute("Team")
	local list = {}
	for _, other in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if other:IsA("Model") and other ~= character and other:GetAttribute("Team") ~= team then
			if not other:GetAttribute("Benched") and not other:GetAttribute("Ragdolled") then
				local root = other:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = other:FindFirstChildOfClass("Humanoid")
				if root and humanoid and humanoid.Health > 0 then
					table.insert(list, { root = root, character = other })
				end
			end
		end
	end
	return list
end

Net.On("ThrowRequest", function(player: Player, charge: any, aimDir: any, clientOrigin: any)
	if not AntiCheat.Allow(player, "Throw") then return end
	if not AntiCheat.ValidCharge(charge) or not AntiCheat.ValidDirection(aimDir) then return end

	local now = os.clock()
	if (throwCooldown[player.UserId] or 0) > now then return end

	local character = player.Character
	if not character or character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local ball = BallService.GetHeld(character)
	if not ball or not root then return end

	local origin = root.Position
	if typeof(clientOrigin) == "Vector3"
		and (clientOrigin - root.Position).Magnitude <= CFG.Throw.OriginLeeway then
		origin = clientOrigin
	end
	origin += Vector3.new(0, CFG.Throw.SpawnLift, 0)

	local isMobile = player:GetAttribute("IsMobile") == true
	local ballsFolder = workspace:FindFirstChild("Balls")
	local exclude = { character }
	if ballsFolder then table.insert(exclude, ballsFolder) end

	local finalDir = AimAssist.Adjust(origin, aimDir, enemyTargets(character), isMobile, exclude)

	local cannonMul, uncatchable = AbilityService.ConsumeCannon(player)
	local suddenMul = if RoundService.IsSuddenDeath() then CFG.Round.SuddenDeathSpeedMul else 1

	if BallService.Throw(character, ball, finalDir, charge, cannonMul * suddenMul, origin) then
		throwCooldown[player.UserId] = now + CFG.Throw.Cooldown
		if uncatchable then ball:SetAttribute("Uncatchable", true) end
		ProgressionService.RegisterStat(player, "throws", 1)
		FtueService.Threw(player)
		Net.FireAll("FXEvent", "throw", ball, player.UserId)
	end
end)

Net.On("CatchRequest", function(player: Player, aimDir: any)
	if not AntiCheat.Allow(player, "Catch") then return end
	CatchService.Try(player, aimDir)
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
	local dir = direction.Unit
	root.AssemblyLinearVelocity = Vector3.new(dir.X * CFG.Movement.DodgeSpeed, 6, dir.Z * CFG.Movement.DodgeSpeed)
	Net.FireAll("FXEvent", "dodge", character)
end)

Net.On("UltRequest", function(player: Player, ultId: any)
	if not AntiCheat.Allow(player, "Ult") then return end
	AbilityService.Use(player, ultId)
end)

Net.On("QuestClaim", function(player: Player, index: any)
	if not AntiCheat.Allow(player, "QuestClaim") then return end
	if ProgressionService.ClaimQuest(player, index) then
		AnalyticsService.Event(player, "quest_claim", { index = index })
	end
end)

Net.On("UiEvent", function(player: Player, marker: any, device: any)
	if not AntiCheat.Allow(player, "UiEvent") then return end
	if typeof(marker) == "string" then AnalyticsService.UiMarker(player, marker) end
	if typeof(device) == "string" then
		player:SetAttribute("IsMobile", device == "mobile")
		AnalyticsService.SetDevice(player, device)
	end
end)

Net.On("QueueJoin", function(player: Player)
	if not AntiCheat.Allow(player, "QueueJoin") then return end
	MatchService.Enqueue(player)
end)

Net.On("RematchRequest", function(player: Player)
	if not AntiCheat.Allow(player, "QueueJoin") then return end
	AnalyticsService.Event(player, "rematch_pressed", {})
	MatchService.Enqueue(player)
end)

Net.On("PingRequest", function(player: Player, position: any)
	if not AntiCheat.Allow(player, "PingRequest") then return end
	local character = player.Character
	if not character or not character:GetAttribute("Benched") then return end
	if not AntiCheat.ValidPingPosition(player, position) then return end
	Net.FireAll("FXEvent", "ping", position, player.UserId)
end)

BallService.HitDetected.Event:Connect(function(ball: BasePart, character: Model, speed: number)
	if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end

	local thrower = BallService.LastThrower(ball)
	if not thrower or thrower == character then return end

	-- без команды нельзя ни бить, ни быть битым
	local throwerTeam = thrower:GetAttribute("Team")
	local victimTeam = character:GetAttribute("Team")
	if typeof(throwerTeam) ~= "number" or typeof(victimTeam) ~= "number" then return end
	if throwerTeam == victimTeam then return end

	local victimPlayer = Players:GetPlayerFromCharacter(character)

	-- стойка ловли превращает попадание в ловлю
	if CatchService.TryConvert(victimPlayer, ball) then return end
	if AbilityService.IsInvulnerable(victimPlayer) then return end

	if AbilityService.ConsumeShield(character:GetAttribute("Team")) then
		ball.AssemblyLinearVelocity = -ball.AssemblyLinearVelocity * 0.4
		Net.FireAll("FXEvent", "shield", character)
		return
	end

	if RagdollService.Hit(character, ball.AssemblyLinearVelocity) then
		MatchService.OnKO(character, "hit")
		local throwerPlayer = Players:GetPlayerFromCharacter(thrower)
		AbilityService.AddHype(throwerPlayer, CFG.Hype.Hit)
		ProgressionService.RegisterStat(throwerPlayer, "kos", 1)
		FtueService.KnockedOut(throwerPlayer)
		ball.AssemblyLinearVelocity *= CFG.Impact.HitSlowdown
		Net.FireAll("FXEvent", "ko", character, thrower, speed)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	throwCooldown[player.UserId] = nil
	dodgeCooldown[player.UserId] = nil
end)

print("[RagdollDodgeball] v0.10.0 server up: half-court bots, ball claims, catch stance")

-- Bootstrap: wiring and rules.
-- The velocity-based half-court clamp is gone. CourtBarrier owns that rule
-- with real collision, so nothing shoves the player anymore.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local ContactForce = require(Shared:WaitForChild("ContactForce", 20))

Collision.Setup()

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

local throwCooldown = {}
local dodgeCooldown = {}

local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
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

local function onPlayer(player)
	player:SetAttribute("MatchesThisSession", 0)
	player:SetAttribute("DodgeReadyAt", 0)
	ProgressionService.OnPlayer(player)
	FtueService.OnPlayer(player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then onCharacter(player.Character) end
	MatchService.Enqueue(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, player) end

AntiCheat.Flagged.Event:Connect(function(player, reason, total)
	AnalyticsService.Event(player, "security_flag", { reason = reason, total = total })
	warn(string.format("[Security] %s: %s (total %d)", player.Name, reason, total))
end)

BallService.PickedUp.Event:Connect(function(player)
	FtueService.PickedUp(player)
end)

CatchService.Caught.Event:Connect(function(player, revived)
	if not player then return end
	ProgressionService.RegisterStat(player, "catches", 1)
	FtueService.Caught(player)
	if revived then
		ProgressionService.RegisterStat(player, "revives", 1)
		FtueService.Revived(player)
	end
end)

local function enemyTargets(character)
	local team = character:GetAttribute("Team")
	local list = {}
	for _, other in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if other:IsA("Model") and other ~= character and other:GetAttribute("Team") ~= team then
			if not other:GetAttribute("Benched") and not other:GetAttribute("Ragdolled") then
				local root = other:FindFirstChild("HumanoidRootPart")
				local humanoid = other:FindFirstChildOfClass("Humanoid")
				if root and humanoid and humanoid.Health > 0 then
					table.insert(list, { root = root, character = other })
				end
			end
		end
	end
	return list
end

Net.On("ThrowRequest", function(player, charge, aimDir, clientOrigin)
	if not AntiCheat.Allow(player, "Throw") then return end
	if not AntiCheat.ValidCharge(charge) or not AntiCheat.ValidDirection(aimDir) then return end

	local now = os.clock()
	if (throwCooldown[player.UserId] or 0) > now then return end

	local character = player.Character
	if not character or character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local ball = BallService.GetHeld(character)
	if not ball or not root then return end

	local origin = root.Position
	if typeof(clientOrigin) == "Vector3" and (clientOrigin - root.Position).Magnitude <= CFG.Throw.OriginLeeway then
		origin = clientOrigin
	end
	origin += Vector3.new(0, CFG.Throw.SpawnLift, 0)

	local isMobile = player:GetAttribute("IsMobile") == true
	local ballsFolder = workspace:FindFirstChild("Balls")
	local exclude = { character }
	if ballsFolder then table.insert(exclude, ballsFolder) end
	local centreBarrier = workspace:FindFirstChild("CentreBarrier")
	if centreBarrier then table.insert(exclude, centreBarrier) end
	local finalDir = AimAssist.Adjust(origin, aimDir, enemyTargets(character), isMobile, exclude)

	local cannonMul, uncatchable = AbilityService.ConsumeCannon(player)
	local suddenMul = 1
	if RoundService.IsSuddenDeath() then suddenMul = CFG.Round.SuddenDeathSpeedMul end

	if BallService.Throw(character, ball, finalDir, charge, cannonMul * suddenMul, origin) then
		throwCooldown[player.UserId] = now + CFG.Throw.Cooldown
		ball:SetAttribute("IsSlam", uncatchable)
		if uncatchable then ball:SetAttribute("Uncatchable", true) end
		ProgressionService.RegisterStat(player, "throws", 1)
		FtueService.Threw(player)
		Net.FireAll("FXEvent", "throw", ball, player.UserId)
	end
end)

Net.On("CatchRequest", function(player, aimDir)
	if not AntiCheat.Allow(player, "Catch") then return end
	CatchService.Try(player, aimDir)
end)

Net.On("DodgeRequest", function(player, direction)
	if not AntiCheat.Allow(player, "Dodge") then return end
	local now = os.clock()
	if (dodgeCooldown[player.UserId] or 0) > now then return end
	if not AntiCheat.ValidDirection(direction) then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end

	dodgeCooldown[player.UserId] = now + CFG.Movement.DodgeCooldown
	player:SetAttribute("DodgeReadyAt", dodgeCooldown[player.UserId])
	player:SetAttribute("InvulnUntil", now + CFG.Movement.DodgeIFrames)

	local dir = direction.Unit
	local velocity = Vector3.new(dir.X * CFG.Movement.DodgeSpeed, CFG.Movement.DodgeLift, dir.Z * CFG.Movement.DodgeSpeed)
	local finish = now + CFG.Movement.DodgeDuration

	task.spawn(function()
		while os.clock() < finish do
			if not root.Parent or character:GetAttribute("Ragdolled") then return end
			root.AssemblyLinearVelocity = velocity
			RunService.Heartbeat:Wait()
		end
	end)

	Net.FireAll("FXEvent", "dodge", character)
end)

Net.On("UltRequest", function(player, ultId)
	if not AntiCheat.Allow(player, "Ult") then return end
	local used = AbilityService.Use(player, ultId)
	if not used then
		Net.FireClient("HypeState", player, AbilityService.GetHype(player), CFG.Hype.Max)
	end
end)

Net.On("QuestClaim", function(player, index)
	if not AntiCheat.Allow(player, "QuestClaim") then return end
	if ProgressionService.ClaimQuest(player, index) then
		AnalyticsService.Event(player, "quest_claim", { index = index })
	end
end)

Net.On("UiEvent", function(player, marker, device)
	if not AntiCheat.Allow(player, "UiEvent") then return end
	if typeof(marker) == "string" then AnalyticsService.UiMarker(player, marker) end
	if typeof(device) == "string" then
		player:SetAttribute("IsMobile", device == "mobile")
		AnalyticsService.SetDevice(player, device)
	end
end)

Net.On("QueueJoin", function(player)
	if not AntiCheat.Allow(player, "QueueJoin") then return end
	MatchService.Enqueue(player)
end)

Net.On("RematchRequest", function(player)
	if not AntiCheat.Allow(player, "QueueJoin") then return end
	AnalyticsService.Event(player, "rematch_pressed", {})
	MatchService.Enqueue(player)
end)

Net.On("PingRequest", function(player, position)
	if not AntiCheat.Allow(player, "PingRequest") then return end
	local character = player.Character
	if not character or not character:GetAttribute("Benched") then return end
	if not AntiCheat.ValidPingPosition(player, position) then return end
	Net.FireAll("FXEvent", "ping", position, player.UserId)
end)

BallService.HitDetected.Event:Connect(function(ball, character, speed, _impactPosition, contact)
	if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end

	local thrower = BallService.LastThrower(ball)
	if not thrower or thrower == character then return end

	local throwerTeam = thrower:GetAttribute("Team")
	local victimTeam = character:GetAttribute("Team")
	if typeof(throwerTeam) ~= "number" or typeof(victimTeam) ~= "number" then return end
	if throwerTeam == victimTeam then return end

	if CatchService.Intercept(character, ball) then return end

	local victimPlayer = Players:GetPlayerFromCharacter(character)
	if AbilityService.IsInvulnerable(victimPlayer) then return end

	if AbilityService.ConsumeShield(victimTeam) then
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

		-- Contact-derived value drives the existing impact presentation only.
		-- RagdollService remains the sole owner of the knockout impulse.
		local feedbackSpeed = speed
		if typeof(contact) == "table" then
			local force = ContactForce.Calculate(
				contact.closingSpeed,
				CFG.Throw.SpeedMax,
				0,
				1
			)
			feedbackSpeed = force.normalized * CFG.Throw.SpeedMax
		end
		Net.FireAll("FXEvent", "ko", character, thrower, feedbackSpeed)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	throwCooldown[player.UserId] = nil
	dodgeCooldown[player.UserId] = nil
end)

print("[RagdollDodgeball] centre rule moved to physical barrier, no more shoving")
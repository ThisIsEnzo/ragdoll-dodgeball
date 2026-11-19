-- Bootstrap: wiring and rule enforcement.
--
-- Half-court fix: the old clamp teleported a violating player to
-- limit - sign * 0.5, which lands on the WRONG side of the line. The player
-- was still violating next tick, so it teleported again every frame and
-- froze them at centre. The target now pushes into their own half, a soft
-- velocity nudge handles shallow crossings, and only a deep violation
-- triggers a teleport. No loop, no rubber-banding at the line.

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
	local finalDir = AimAssist.Adjust(origin, aimDir, enemyTargets(character), isMobile, exclude)

	local cannonMul, uncatchable = AbilityService.ConsumeCannon(player)
	local suddenMul = 1
	if RoundService.IsSuddenDeath() then suddenMul = CFG.Round.SuddenDeathSpeedMul end

	if BallService.Throw(character, ball, finalDir, charge, cannonMul * suddenMul, origin) then
		throwCooldown[player.UserId] = now + CFG.Throw.Cooldown
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

BallService.HitDetected.Event:Connect(function(ball, character, speed)
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
		Net.FireAll("FXEvent", "ko", character, thrower, speed)
	end
end)

-- ---------------------------------------------------------------------------
-- Half-court rule, rewritten so it cannot trap a player on the line.
-- depth = how far the player is inside their own half. Positive is legal.
-- ---------------------------------------------------------------------------

local halfAccumulator = 0
local warnUntil = {}

RunService.Heartbeat:Connect(function(dt)
	if not CFG.Rules.EnforceHalfCourt then return end
	halfAccumulator += dt
	local interval = 1 / math.max(CFG.Rules.HalfClampHz, 1)
	if halfAccumulator < interval then return end
	halfAccumulator = 0

	if not MatchService.IsRunning() then return end
	local state = RoundService.State
	if state ~= "Live" and state ~= "SuddenDeath" then return end

	local halfW = CFG.Arena.Width * 0.5
	local band = CFG.Rules.NeutralBand

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and not character:GetAttribute("Benched") and not character:GetAttribute("Ragdolled") then
			local team = character:GetAttribute("Team")
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if typeof(team) == "number" and root and humanoid and humanoid.Health > 0 then
				local sign = -1
				if team == 2 then sign = 1 end

				local pos = root.Position
				local depth = pos.Z * sign
				local legal = band

				if depth < legal then
					local overshoot = legal - depth
					local safeZ = sign * (legal + 1.6)

					if overshoot > 4 then
						-- deep violation: place them safely inside their own half
						local target = Vector3.new(
							math.clamp(pos.X, -halfW + 4, halfW - 4),
							pos.Y,
							safeZ)
						local _, yaw = root.CFrame:ToEulerAnglesYXZ()
						character:PivotTo(CFrame.new(target) * CFrame.Angles(0, yaw, 0))
						root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					else
						-- shallow crossing: nudge back, never teleport
						local v = root.AssemblyLinearVelocity
						local push = math.clamp(overshoot * 9, 6, 26)
						root.AssemblyLinearVelocity = Vector3.new(v.X * 0.6, v.Y, sign * push)
					end

					if (warnUntil[player.UserId] or 0) < os.clock() then
						warnUntil[player.UserId] = os.clock() + 2
						Net.FireClient("FXEvent", "halfwarn", character)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	throwCooldown[player.UserId] = nil
	dodgeCooldown[player.UserId] = nil
	warnUntil[player.UserId] = nil
end)

print("[RagdollDodgeball] half-court fixed: soft nudge, safe-side teleport, no centre trap")
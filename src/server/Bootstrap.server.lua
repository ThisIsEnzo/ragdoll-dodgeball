-- Bootstrap v0.6.0: подключены AnalyticsService и FtueService.
-- Порядок: аналитика и данные до FTUE, FTUE до матча.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Bootstrap] ReplicatedStorage.Shared is missing")

local CFG = require(Shared:WaitForChild("BalanceConfig", 20))
local Net = require(Shared:WaitForChild("Net", 20))
local Resolve = require(Shared:WaitForChild("Resolve", 20))
local Collision = require(Shared:WaitForChild("Collision", 20))

Collision.Setup()
Resolve.Report(ServerScriptService, "Bootstrap")

local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")
local ArenaService = Resolve.Require(ServerScriptService, "ArenaService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local BallService = Resolve.Require(ServerScriptService, "BallService")
local RoundService = Resolve.Require(ServerScriptService, "RoundService")
local AbilityService = Resolve.Require(ServerScriptService, "AbilityService")
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
	AnalyticsService, DataService, ProgressionService, FtueService, MatchService, CatchService,
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
local sessionStart: { [number]: number } = {}

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed
	humanoid.JumpPower = CFG.Movement.JumpPower
	character:SetAttribute("Benched", false)
	character:SetAttribute("Ragdolled", false)
	character:SetAttribute("Carrying", false)
	RagdollService.Prepare(character)
end

local function onPlayer(player: Player)
	sessionStart[player.UserId] = os.clock()
	player:SetAttribute("MatchesThisSession", 0)

	ProgressionService.OnPlayer(player)
	FtueService.OnPlayer(player)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then onCharacter(player.Character) end
	MatchService.Enqueue(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, player) end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local started = sessionStart[player.UserId]
			if started then
				player:SetAttribute("SessionSeconds", os.clock() - started)
			end
		end
	end
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

Net.On("ThrowRequest", function(player: Player, charge: any, aimDir: any, clientOrigin: any)
	if not AntiCheat.Allow(player, "Throw") then return end
	if not AntiCheat.ValidCharge(charge) or not AntiCheat.ValidDirection(aimDir) then return end

	local now = os.clock()
	if (throwCooldown[player.UserId] or 0) > now then return end

	local character = player.Character
	if not character or character:GetAttribute("Benched") or RagdollService.IsActive(character) then return end
	local ball = BallService.GetHeld(character)
	if not ball then return end

	local origin = if typeof(clientOrigin) == "Vector3" then clientOrigin else nil
	local cannonMul, uncatchable = AbilityService.ConsumeCannon(player)
	local suddenMul = if RoundService.IsSuddenDeath() then CFG.Round.SuddenDeathSpeedMul else 1

	if BallService.Throw(character, ball, aimDir, charge, cannonMul * suddenMul, origin) then
		throwCooldown[player.UserId] = now + CFG.Throw.Cooldown
		if uncatchable then ball:SetAttribute("Uncatchable", true) end
		ProgressionService.RegisterStat(player, "throws", 1)
		FtueService.Threw(player)
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
		direction.Unit.X * CFG.Movement.DodgeSpeed, 6, direction.Unit.Z * CFG.Movement.DodgeSpeed
	)
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
	if typeof(marker) == "string" then
		AnalyticsService.UiMarker(player, marker)
	end
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
	if not AntiCheat.Allow(player, "PingRequest", 0.2) then return end
	local character = player.Character
	if not character or not character:GetAttribute("Benched") then return end
	if typeof(position) ~= "Vector3" then return end
	Net.FireAll("FXEvent", "ping", position, player.UserId)
end)

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
	sessionStart[player.UserId] = nil
end)

print("[RagdollDodgeball] v0.6.0 server up: FTUE prompts, server-side funnel, session analytics")

-- CatchService v0.10.0: ловля как стойка, а не мгновенная проверка.
--
-- Было два блокера:
--   1. конус считался от root.CFrame.LookVector, то есть от разворота ТЕЛА.
--      Стоя на месте и ведя камерой на мяч, тело смотрит в сторону — ловля отклонялась.
--   2. проверка была мгновенной в окне 5 studs. Мяч на 100 studs/s проходит их за 0.05 с,
--      что при реакции 0.25 с и пинге 267 мс недостижимо.
--
-- Стало: нажатие включает стойку на StanceSeconds. Любой подходящий мяч, долетевший
-- в это время, ловится на контакте. Конус считается от направления камеры.
-- Промах штрафуется только когда стойка истекла впустую.

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

local stance: { [number]: any } = {}
local cooldownUntil: { [number]: number } = {}

function CatchService.Init(matchService, abilityService)
	MatchService = matchService
	AbilityService = abilityService
end

local function applyStagger(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed * 0.45
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
	if team and MatchService then revived = MatchService.ReviveOne(team) end
	if AbilityService then AbilityService.AddHype(player, CFG.Hype.Catch) end

	stance[player.UserId] = nil
	CatchService.Caught:Fire(player, revived)
	Net.FireAll("FXEvent", "catch", character, thrower)
end

local function catchableBall(ball: BasePart): boolean
	if not ball:IsA("BasePart") then return false end
	if not ball:IsDescendantOf(workspace) then return false end
	if ball:GetAttribute("HeldBy") then return false end
	if not ball:GetAttribute("Clean") then return false end
	if ball:GetAttribute("Uncatchable") then return false end
	local speed = ball.AssemblyLinearVelocity.Magnitude
	return speed >= CFG.Ball.MinHitSpeed and speed <= CFG.Catch.MaxSpeed
end

local function withinCone(root: BasePart, aim: Vector3, ballPosition: Vector3): boolean
	local offset = ballPosition - root.Position
	if offset.Magnitude < 0.01 then return true end
	local reference = if aim.Magnitude > 0.01 then aim.Unit else root.CFrame.LookVector
	local angle = math.acos(math.clamp(reference:Dot(offset.Unit), -1, 1))
	return angle <= math.rad(CFG.Catch.ConeDeg * 0.5)
end

local function findCatchable(character: Model, root: BasePart, sampleTime: number, aim: Vector3): BasePart?
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if catchableBall(ball) then
			local position = BallService.SampleAt(ball, sampleTime) or ball.Position
			if (position - root.Position).Magnitude <= CFG.Catch.Distance
				and withinCone(root, aim, position) then
				local thrower = BallService.LastThrower(ball)
				if thrower and thrower ~= character then
					return ball
				end
			end
		end
	end
	return nil
end

-- Вызывается при нажатии кнопки. Открывает стойку и пробует мгновенную ловлю.
function CatchService.Try(player: Player, aimDir: any): boolean
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return false end

	local now = os.clock()
	if (cooldownUntil[player.UserId] or 0) > now then return false end

	local aim = if typeof(aimDir) == "Vector3" and CFG.Catch.UseCameraAim
		then aimDir else root.CFrame.LookVector

	local ping = player:GetNetworkPing()
	local entry = {
		startedAt = now - ping,
		expires = now + CFG.Catch.StanceSeconds,
		aim = aim,
		token = now,
	}
	stance[player.UserId] = entry
	player:SetAttribute("CatchAttemptAt", now)
	Net.FireAll("FXEvent", "stance", character)

	local sampleTime = workspace:GetServerTimeNow() - ping
	local ball = findCatchable(character, root, sampleTime, aim)
	if ball then
		succeed(player, character, ball)
		return true
	end

	-- штраф только если стойка истекла впустую
	task.delay(CFG.Catch.StanceSeconds, function()
		local current = stance[player.UserId]
		if current and current.token == entry.token then
			stance[player.UserId] = nil
			cooldownUntil[player.UserId] = os.clock() + CFG.Catch.WhiffCooldown
			if character.Parent and not character:GetAttribute("Benched") then
				applyStagger(character)
				Net.FireAll("FXEvent", "whiff", character)
			end
		end
	end)

	return false
end

-- Вызывается из Bootstrap в момент попадания: стойка превращает удар в ловлю.
function CatchService.TryConvert(player: Player?, ball: BasePart): boolean
	if not player then return false end
	local entry = stance[player.UserId]
	if not entry then return false end
	if os.clock() > entry.expires then return false end
	if not catchableBall(ball) then return false end

	local character = player.Character
	if not character or RagdollService.IsActive(character) then return false end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	if not withinCone(root, entry.aim, ball.Position) then return false end

	local thrower = BallService.LastThrower(ball)
	if not thrower or thrower == character then return false end

	succeed(player, character, ball)
	return true
end

function CatchService.InStance(player: Player?): boolean
	if not player then return false end
	local entry = stance[player.UserId]
	return entry ~= nil and os.clock() <= entry.expires
end

function CatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		stance[player.UserId] = nil
		cooldownUntil[player.UserId] = nil
	end)
end

return CatchService

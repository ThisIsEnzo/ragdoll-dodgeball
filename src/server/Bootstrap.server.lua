-- Bootstrap: единственная точка входа на сервере.
-- Загружает сервисы, поднимает ремоуты, связывает бросок и попадание.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local servicesFolder = script:WaitForChild("services")
local AntiCheat = require(servicesFolder:WaitForChild("AntiCheat"))
local RagdollService = require(servicesFolder:WaitForChild("RagdollService"))
local BallService = require(servicesFolder:WaitForChild("BallService"))
local RoundService = require(servicesFolder:WaitForChild("RoundService"))

local SERVICES = { AntiCheat, RagdollService, BallService, RoundService }

Net.Init()

for _, service in ipairs(SERVICES) do
	if service.Init then
		service.Init()
	end
end
for _, service in ipairs(SERVICES) do
	if service.Start then
		service.Start()
	end
end

BallService.SpawnAll()

-- Персонажи: готовим ragdoll-риг и базовые настройки движения
local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed
	humanoid.JumpPower = CFG.Movement.JumpPower
	RagdollService.Prepare(character)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end

-- Бросок: сервер решает всё
local throwCooldown: { [number]: number } = {}

Net.On("ThrowRequest", function(player: Player, charge: any, aimDir: any)
	if not AntiCheat.Allow(player, "Throw") then
		return
	end
	if not AntiCheat.ValidCharge(charge) or not AntiCheat.ValidDirection(aimDir) then
		return
	end

	local now = os.clock()
	if throwCooldown[player.UserId] and now - throwCooldown[player.UserId] < CFG.Throw.Cooldown then
		return
	end

	local character = player.Character
	if not character or RagdollService.IsActive(character) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local ball = BallService.GetHeld(player.UserId)
	if not ball then
		return
	end

	local speedMul = RoundService.IsSuddenDeath() and CFG.Round.SuddenDeathSpeedMul or 1
	if BallService.Throw(player, ball, aimDir, charge, speedMul) then
		throwCooldown[player.UserId] = now
		Net.FireAll("FXEvent", "throw", ball, player.UserId)
	end
end)

-- Попадание: мяч касается персонажа -> выбивание + ragdoll
for _, ball in ipairs(CollectionService_GetBalls()) do end -- placeholder removed below

local CollectionService = game:GetService("CollectionService")

local function bindBall(ball: BasePart)
	if not ball:IsA("BasePart") or ball:GetAttribute("Bound") then
		return
	end
	ball:SetAttribute("Bound", true)

	ball.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character or not character:FindFirstChildOfClass("Humanoid") then
			return
		end
		if RagdollService.IsActive(character) then
			return
		end

		local speed = ball.AssemblyLinearVelocity.Magnitude
		if speed < CFG.Ball.MinHitSpeed then
			return
		end

		local throwerId, thrownAt = BallService.LastThrower(ball)
		if not throwerId or (thrownAt and os.clock() - thrownAt < 0.15) then
			return
		end
		local victim = Players:GetPlayerFromCharacter(character)
		if victim and victim.UserId == throwerId then
			return
		end

		local impulse = ball.AssemblyLinearVelocity.Unit * (speed * CFG.Throw.ImpulseMul)
		if RagdollService.Apply(character, impulse) then
			RoundService.RegisterKO(character)
			Net.FireAll("FXEvent", "ko", character, throwerId, speed)
		end
	end)
end

for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
	bindBall(ball)
end
CollectionService:GetInstanceAddedSignal("Dodgeball"):Connect(bindBall)

Players.PlayerRemoving:Connect(function(player)
	throwCooldown[player.UserId] = nil
end)

print("[RagdollDodgeball] Сервер запущен: ragdoll, мячи, раунд-FSM, анти-чит активны")

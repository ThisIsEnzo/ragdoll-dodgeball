-- BotController v0.8.1: боты различимы. Уникальные имена, цвета команды, разброс пропорций.
-- Путь именно src/server/AI/, не services/ — в v0.8.0 патч указал неверную папку.
--
-- Атрибуты DisplayName и IsBot читает TeamIdentityService: без них над ботами
-- висит одинаковый Bot_Team1 и нет метки BOT.
--
-- Зависимости берутся резолвером от ServerScriptService, поэтому вложенность папок не важна.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")

local BotController = {}
local bots: { Model } = {}
local usedNames: { [string]: boolean } = {}

local SKIN_TONES = {
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 134, 96),
	Color3.fromRGB(140, 92, 62),
	Color3.fromRGB(255, 219, 172),
}

local function pickName(): string
	local pool = CFG.Readability.BotNames
	for _ = 1, #pool do
		local candidate = pool[math.random(1, #pool)]
		if not usedNames[candidate] then
			usedNames[candidate] = true
			return candidate
		end
	end
	local fallback = "Bot" .. tostring(math.random(10, 99))
	usedNames[fallback] = true
	return fallback
end

-- Цвета работают и на R6, и на R15. Пропорции R6 может проигнорировать,
-- поэтому основные различители — имя, цвет торса и тон кожи.
local function buildDescription(team: number): HumanoidDescription
	local entry = CFG.Teams[team] or CFG.Teams[1]
	local skin = SKIN_TONES[math.random(1, #SKIN_TONES)]
	local jitter = CFG.Readability.BotScaleJitter

	local description = Instance.new("HumanoidDescription")
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = entry.color
	description.LeftLegColor = entry.dark
	description.RightLegColor = entry.dark

	local function scale()
		return 1 + (math.random() * 2 - 1) * jitter
	end
	description.HeightScale = scale()
	description.WidthScale = scale()
	description.DepthScale = scale()
	description.HeadScale = scale()

	return description
end

local function createRig(team: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(buildDescription(team), Enum.HumanoidRigType.R6)
	end)
	if ok and model then return model end

	local template = ServerStorage:FindFirstChild("BotRig")
	if template then return template:Clone() end
	return nil
end

local function nearestEnemy(character: Model): Model?
	local team = character:GetAttribute("Team")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local best, bestDist = nil, math.huge
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= character and model:GetAttribute("Team") then
			if model:GetAttribute("Team") ~= team and not model:GetAttribute("Benched") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local enemyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if humanoid and humanoid.Health > 0 and enemyRoot then
					local d = (enemyRoot.Position - root.Position).Magnitude
					if d < bestDist then best, bestDist = model, d end
				end
			end
		end
	end
	return best
end

local function think(bot: Model)
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then return end

	local reaction = CFG.Bots.ReactionMin + math.random() * (CFG.Bots.ReactionMax - CFG.Bots.ReactionMin)
	local aimError = CFG.Bots.AimErrorMin + math.random() * (CFG.Bots.AimErrorMax - CFG.Bots.AimErrorMin)

	while bot.Parent and humanoid.Health > 0 do
		task.wait(reaction)

		if bot:GetAttribute("Benched") or bot:GetAttribute("Ragdolled") then
			continue
		end

		local ball = BallService.GetHeld(bot)
		if ball then
			local enemy = nearestEnemy(bot)
			local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
			if enemyRoot then
				local direction = (enemyRoot.Position + Vector3.new(0, 1.5, 0) - root.Position).Unit
				local jitter = Vector3.new(
					math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
				) * math.rad(aimError)
				BallService.Throw(bot, ball, (direction + jitter).Unit, 0.5 + math.random() * 0.4)
			end
		else
			local free = BallService.NearestFree(root.Position, 200)
			if free then
				humanoid:MoveTo(free.Position)
			else
				local enemy = nearestEnemy(bot)
				local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
				if enemyRoot then
					humanoid:MoveTo(enemyRoot.Position + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
				end
			end
		end
	end
end

function BotController.Spawn(team: number, position: Vector3): Model?
	local bot = createRig(team)
	if not bot then
		warn("[BotController] Could not create a rig. Put a BotRig into ServerStorage as a fallback.")
		return nil
	end

	local displayName = pickName()
	bot.Name = "Bot_" .. displayName
	bot:SetAttribute("Team", team)
	bot:SetAttribute("DisplayName", displayName)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("Benched", false)
	bot:SetAttribute("Ragdolled", false)
	bot.Parent = workspace
	bot:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))

	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = CFG.Movement.WalkSpeed
		humanoid.JumpPower = CFG.Movement.JumpPower
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	RagdollService.Prepare(bot)
	table.insert(bots, bot)
	task.spawn(think, bot)
	return bot
end

function BotController.DespawnAll()
	for _, bot in ipairs(bots) do
		if bot.Parent then bot:Destroy() end
	end
	table.clear(bots)
	table.clear(usedNames)
end

function BotController.Init() end
function BotController.Start() end

return BotController

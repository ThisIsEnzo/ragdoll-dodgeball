-- BotController v0.10.0: спортивное поведение вместо толпы.
--
-- Было: все боты обеих команд брали глобально ближайший мяч и бежали к нему через всё поле.
-- Стало:
--   1. половина поля — жёсткое ограничение, бот не пересекает центр;
--   2. заявка на мяч эксклюзивна: один мяч — один бот, срок ClaimSeconds;
--   3. мяч заявляется только на своей половине или в нейтральной зоне у центра;
--   4. коридоры по x разводят ботов, чтобы они не выстраивались в ряд;
--   5. сепарация отталкивает от союзников;
--   6. без доступного мяча бот держит коридор, а не бежит в толпу;
--   7. бросок с баллистическим лофтом, чтобы мяч долетал;
--   8. иногда уклоняется от летящего мяча.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")

local BotController = {}

local bots: { Model } = {}
local usedNames: { [string]: boolean } = {}
local slotCount: { [number]: number } = { [1] = 0, [2] = 0 }
local state: { [Model]: any } = {}
local claims: { [BasePart]: any } = {}

local SKIN_TONES = {
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 134, 96),
	Color3.fromRGB(140, 92, 62),
	Color3.fromRGB(255, 219, 172),
}

local function halfSign(team: number): number
	return if team == 1 then -1 else 1
end

local function halfBounds(team: number)
	local A = CFG.BotAI
	local halfW = CFG.Arena.Width * 0.5 - A.EdgeMargin
	local halfD = CFG.Arena.Depth * 0.5 - A.EdgeMargin
	local sign = halfSign(team)
	local zNear = sign * A.CenterMargin
	local zFar = sign * halfD
	return {
		xMin = -halfW, xMax = halfW,
		zMin = math.min(zNear, zFar), zMax = math.max(zNear, zFar),
	}
end

local function clampToHalf(position: Vector3, team: number): Vector3
	local b = halfBounds(team)
	return Vector3.new(
		math.clamp(position.X, b.xMin, b.xMax),
		position.Y,
		math.clamp(position.Z, b.zMin, b.zMax)
	)
end

local function freeBalls()
	local list = {}
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace)
			and not ball:GetAttribute("HeldBy") then
			table.insert(list, ball)
		end
	end
	return list
end

local function purgeClaims(now: number)
	for ball, claim in pairs(claims) do
		if not ball.Parent or not ball:IsDescendantOf(workspace)
			or ball:GetAttribute("HeldBy")
			or now > claim.expires
			or not claim.bot.Parent then
			claims[ball] = nil
		end
	end
end

local function ballEligible(ball: BasePart, team: number): boolean
	local sign = halfSign(team)
	local z = ball.Position.Z
	if z * sign > 0 then return true end
	return math.abs(z) <= CFG.BotAI.CenterReach
end

local function claimBall(bot: Model, team: number, root: BasePart, now: number)
	local best, bestDist = nil, math.huge
	for _, ball in ipairs(freeBalls()) do
		if ballEligible(ball, team) and not claims[ball] then
			local d = (ball.Position - root.Position).Magnitude
			if d < bestDist then best, bestDist = ball, d end
		end
	end
	if best then
		claims[best] = { bot = bot, expires = now + CFG.BotAI.ClaimSeconds }
		return best
	end
	return nil
end

local function ownClaim(bot: Model): BasePart?
	for ball, claim in pairs(claims) do
		if claim.bot == bot then return ball end
	end
	return nil
end

local function separationOffset(bot: Model, root: BasePart): Vector3
	local push = Vector3.zero
	local team = bot:GetAttribute("Team")
	for _, other in ipairs(bots) do
		if other ~= bot and other.Parent and other:GetAttribute("Team") == team then
			local otherRoot = other:FindFirstChild("HumanoidRootPart") :: BasePart?
			if otherRoot then
				local offset = root.Position - otherRoot.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local d = flat.Magnitude
				if d > 0.1 and d < CFG.BotAI.Separation then
					push += flat.Unit * (CFG.BotAI.Separation - d) / CFG.BotAI.Separation * CFG.BotAI.SeparationPush
				end
			end
		end
	end
	return push
end

local function incomingThreat(root: BasePart): BasePart?
	for _, ball in ipairs(freeBalls()) do
		local velocity = ball.AssemblyLinearVelocity
		if velocity.Magnitude > 45 then
			local toBot = root.Position - ball.Position
			local d = toBot.Magnitude
			if d > 1 and d < CFG.BotAI.EvadeDistance then
				if velocity.Unit:Dot(toBot.Unit) > 0.86 then
					return ball
				end
			end
		end
	end
	return nil
end

local function hasLineOfSight(from: Vector3, to: Vector3, exclude: { Instance }, target: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local delta = to - from
	local hit = workspace:Raycast(from, delta, params)
	-- луч заканчивается внутри цели, поэтому попадание по самой цели это успех.
	-- Раньше return hit == nil всегда давал false, и боты никогда не бросали.
	if hit == nil then return true end
	return hit.Instance:IsDescendantOf(target)
end

-- Низкая дуга: theta = 0.5 * asin(g * R / v^2)
local function ballisticDirection(origin: Vector3, target: Vector3, speed: number): Vector3
	local offset = target - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance < 0.5 then return Vector3.new(0, 0, halfSign(1)) end

	local g = workspace.Gravity * math.clamp(CFG.Ball.GravityScale, 0.05, 1)
	local ratio = math.clamp(g * distance / (speed * speed), 0, 1)
	local angle = 0.5 * math.asin(ratio)
	angle = math.clamp(angle + math.rad(2), math.rad(2), math.rad(40))

	local dir = flat.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
	return dir.Unit
end

local function nearestEnemy(character: Model): Model?
	local team = character:GetAttribute("Team")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local best, bestDist = nil, math.huge
	for _, model in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if model:IsA("Model") and model ~= character and model:GetAttribute("Team") ~= team then
			if not model:GetAttribute("Benched") and not model:GetAttribute("Ragdolled") then
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

	local function scale() return 1 + (math.random() * 2 - 1) * jitter end
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

local function think(bot: Model)
	local info = state[bot]
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not info or not humanoid or not root then return end

	local team = info.team
	local sign = halfSign(team)
	local anchor = Vector3.new(info.laneX, root.Position.Y, sign * CFG.Arena.Depth * 0.5 * CFG.BotAI.AnchorDepth)
	local throwLine = Vector3.new(info.laneX, root.Position.Y, sign * (CFG.BotAI.CenterMargin + CFG.BotAI.ThrowLineOffset))
	local aimError = CFG.Bots.AimErrorMin + math.random() * (CFG.Bots.AimErrorMax - CFG.Bots.AimErrorMin)
	local lastThrowAt = 0
	local wander = Vector3.zero
	local nextWander = 0

	while bot.Parent and humanoid.Health > 0 do
		task.wait(CFG.BotAI.TickSeconds)

		if bot:GetAttribute("Benched") or bot:GetAttribute("Ragdolled") then
			continue
		end

		local now = os.clock()
		purgeClaims(now)

		-- 1. уклонение от летящего мяча
		local threat = incomingThreat(root)
		if threat and math.random() < CFG.BotAI.EvadeChance then
			local velocity = threat.AssemblyLinearVelocity.Unit
			local side = Vector3.new(-velocity.Z, 0, velocity.X)
			if math.random() < 0.5 then side = -side end
			humanoid:MoveTo(clampToHalf(root.Position + side * CFG.BotAI.EvadeStrafe, team))
			continue
		end

		local held = BallService.GetHeld(bot)
		if held then
			-- 2. с мячом: выходим на линию броска в своём коридоре
			local goal = throwLine + separationOffset(bot, root)
			humanoid:MoveTo(clampToHalf(goal, team))

			if now - lastThrowAt >= CFG.BotAI.ThrowInterval then
				local enemy = nearestEnemy(bot)
				local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
				if enemyRoot then
					local origin = root.Position + Vector3.new(0, CFG.Throw.SpawnLift, 0)
					local target = enemyRoot.Position + Vector3.new(0, 1, 0)
					local ballsFolder = workspace:FindFirstChild("Balls")
					local exclude = { bot }
					if ballsFolder then table.insert(exclude, ballsFolder) end

					if hasLineOfSight(origin, target, exclude, enemy) then
						local charge = 0.55 + math.random() * 0.35
						local t = math.clamp((charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1)
						local speed = CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t

						local dir = ballisticDirection(origin, target, speed)
						local jitter = Vector3.new(
							math.random() - 0.5, (math.random() - 0.5) * 0.4, math.random() - 0.5
						) * math.rad(aimError)

						if BallService.Throw(bot, held, (dir + jitter).Unit, charge) then
							lastThrowAt = now
						end
					end
				end
			end
		else
			-- 3. без мяча: своя заявка, иначе держим коридор
			local target = ownClaim(bot)
			if not target or not target.Parent or target:GetAttribute("HeldBy") then
				target = claimBall(bot, team, root, now)
			end

			if target then
				local goal = target.Position + separationOffset(bot, root)
				humanoid:MoveTo(clampToHalf(goal, team))
			else
				if now > nextWander then
					nextWander = now + 1.5 + math.random()
					local r = CFG.BotAI.WanderRadius
					wander = Vector3.new((math.random() * 2 - 1) * r, 0, (math.random() * 2 - 1) * r * 0.5)
				end
				local goal = anchor + wander + separationOffset(bot, root)
				humanoid:MoveTo(clampToHalf(goal, team))
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

	slotCount[team] = (slotCount[team] or 0) + 1
	local slot = slotCount[team]
	local laneX = (slot - 2) * CFG.BotAI.LaneSpacing

	local displayName = pickName()
	bot.Name = "Bot_" .. displayName
	bot:SetAttribute("Team", team)
	bot:SetAttribute("DisplayName", displayName)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("Benched", false)
	bot:SetAttribute("Ragdolled", false)
	bot.Parent = workspace

	local start = clampToHalf(Vector3.new(laneX, position.Y, position.Z), team)
	bot:PivotTo(CFrame.new(start + Vector3.new(0, 3, 0)))

	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = CFG.Movement.WalkSpeed
		humanoid.JumpPower = CFG.Movement.JumpPower
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	state[bot] = { team = team, slot = slot, laneX = laneX }

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
	table.clear(state)
	table.clear(claims)
	table.clear(usedNames)
	slotCount[1] = 0
	slotCount[2] = 0
end

function BotController.Init() end
function BotController.Start() end

return BotController

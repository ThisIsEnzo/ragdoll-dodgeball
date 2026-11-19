-- BotController: half-court sports AI.
-- Audit fix: bots never caught anything. They now read incoming live throws
-- and open a catch stance through CatchService, same path as players.

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
local CatchService = Resolve.Require(ServerScriptService, "CatchService")

local BotController = {}
local bots = {}
local usedNames = {}
local slotCount = { [1] = 0, [2] = 0 }
local state = {}
local claims = {}

local SKIN = {
	Color3.fromRGB(255, 208, 164), Color3.fromRGB(238, 190, 150),
	Color3.fromRGB(202, 140, 100), Color3.fromRGB(146, 98, 66),
}

local function halfSign(team)
	if team == 1 then return -1 end
	return 1
end

local function bounds(team)
	local A = CFG.BotAI
	local halfW = CFG.Arena.Width * 0.5 - A.EdgeMargin
	local halfD = CFG.Arena.Depth * 0.5 - A.EdgeMargin
	local sign = halfSign(team)
	local near = sign * A.CenterMargin
	local far = sign * halfD
	return { xMin = -halfW, xMax = halfW, zMin = math.min(near, far), zMax = math.max(near, far) }
end

local function clampToHalf(position, team)
	local b = bounds(team)
	return Vector3.new(
		math.clamp(position.X, b.xMin, b.xMax),
		position.Y,
		math.clamp(position.Z, b.zMin, b.zMax))
end

local function freeBalls()
	local list = {}
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace) and not ball:GetAttribute("HeldBy") then
			table.insert(list, ball)
		end
	end
	return list
end

local function purgeClaims(now)
	for ball, claim in pairs(claims) do
		if not ball.Parent or not ball:IsDescendantOf(workspace)
			or ball:GetAttribute("HeldBy") or now > claim.expires or not claim.bot.Parent then
			claims[ball] = nil
		end
	end
end

local function eligibleBall(ball, team)
	local z = ball.Position.Z
	if z * halfSign(team) > 0 then return true end
	return math.abs(z) <= CFG.BotAI.CenterReach
end

local function claimBall(bot, team, root, now)
	local best, bestDist = nil, math.huge
	for _, ball in ipairs(freeBalls()) do
		if eligibleBall(ball, team) and not claims[ball] then
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

local function ownClaim(bot)
	for ball, claim in pairs(claims) do
		if claim.bot == bot then return ball end
	end
	return nil
end

local function separation(bot, root)
	local push = Vector3.zero
	local team = bot:GetAttribute("Team")
	for _, other in ipairs(bots) do
		if other ~= bot and other.Parent and other:GetAttribute("Team") == team then
			local otherRoot = other:FindFirstChild("HumanoidRootPart")
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

local function lineOfSight(from, to, exclude, target)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(from, to - from, params)
	if hit == nil then return true end
	return hit.Instance:IsDescendantOf(target)
end

local function ballistic(origin, target, speed)
	local offset = target - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance < 0.5 then return Vector3.new(0, 0, -1) end
	local g = workspace.Gravity * math.clamp(CFG.Ball.GravityScale, 0.05, 1)
	local ratio = math.clamp(g * distance / (speed * speed), 0, 1)
	local angle = math.clamp(0.5 * math.asin(ratio) + math.rad(2), math.rad(2), math.rad(40))
	return (flat.Unit * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)).Unit
end

local function nearestEnemy(character)
	local team = character:GetAttribute("Team")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local best, bestDist = nil, math.huge
	for _, model in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if model:IsA("Model") and model ~= character and model:GetAttribute("Team") ~= team then
			if not model:GetAttribute("Benched") and not model:GetAttribute("Ragdolled") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local enemyRoot = model:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and enemyRoot then
					local d = (enemyRoot.Position - root.Position).Magnitude
					if d < bestDist then best, bestDist = model, d end
				end
			end
		end
	end
	return best
end

local function pickName()
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

local function createRig(team)
	local entry = CFG.Teams[team] or CFG.Teams[1]
	local skin = SKIN[math.random(1, #SKIN)]
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

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if ok and model then return model end
	local template = ServerStorage:FindFirstChild("BotRig")
	if template then return template:Clone() end
	return nil
end

local function think(bot)
	local info = state[bot]
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not info or not humanoid or not root then return end

	local team = info.team
	local sign = halfSign(team)
	local anchor = Vector3.new(info.laneX, root.Position.Y, sign * CFG.Arena.Depth * 0.5 * CFG.BotAI.AnchorDepth)
	local throwLine = Vector3.new(info.laneX, root.Position.Y, sign * (CFG.BotAI.CenterMargin + CFG.BotAI.ThrowLineOffset))
	local aimError = CFG.Bots.AimErrorMin + math.random() * (CFG.Bots.AimErrorMax - CFG.Bots.AimErrorMin)
	local lastThrowAt = 0
	local wander = Vector3.zero
	local nextWander = 0
	local nextCatchTry = 0

	while bot.Parent and humanoid.Health > 0 do
		task.wait(CFG.BotAI.TickSeconds)

		if bot:GetAttribute("Benched") or bot:GetAttribute("Ragdolled") then
			continue
		end

		local now = os.clock()
		purgeClaims(now)

		-- Catch first: a live throw heading at this bot is the highest priority.
		local threat, threatDist = BallService.IncomingThreat(root, CFG.BotAI.CatchRange)
		if threat and now > nextCatchTry and not bot:GetAttribute("Carrying") then
			nextCatchTry = now + CFG.BotAI.CatchReaction
			if math.random() < CFG.BotAI.CatchChance then
				local flight = threatDist / math.max(threat.AssemblyLinearVelocity.Magnitude, 1)
				CatchService.OpenStance(bot, math.clamp(flight + 0.35, 0.3, 1.4))
			else
				local velocity = threat.AssemblyLinearVelocity.Unit
				local side = Vector3.new(-velocity.Z, 0, velocity.X)
				if math.random() < 0.5 then side = -side end
				humanoid:MoveTo(clampToHalf(root.Position + side * CFG.BotAI.EvadeStrafe, team))
			end
			continue
		end

		local held = BallService.GetHeld(bot)
		if held then
			humanoid:MoveTo(clampToHalf(throwLine + separation(bot, root), team))
			if now - lastThrowAt >= CFG.BotAI.ThrowInterval then
				local enemy = nearestEnemy(bot)
				local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
				if enemyRoot then
					local origin = root.Position + Vector3.new(0, CFG.Throw.SpawnLift, 0)
					local target = enemyRoot.Position + Vector3.new(0, 1, 0)
					local ballsFolder = workspace:FindFirstChild("Balls")
					local exclude = { bot }
					if ballsFolder then table.insert(exclude, ballsFolder) end
					if lineOfSight(origin, target, exclude, enemy) then
						local charge = 0.55 + math.random() * 0.35
						local t = math.clamp((charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1)
						local speed = CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t
						local dir = ballistic(origin, target, speed)
						local jitter = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.4, math.random() - 0.5) * math.rad(aimError)
						if BallService.Throw(bot, held, (dir + jitter).Unit, charge) then
							lastThrowAt = now
						end
					end
				end
			end
		else
			local target = ownClaim(bot)
			if not target or not target.Parent or target:GetAttribute("HeldBy") then
				target = claimBall(bot, team, root, now)
			end
			if target then
				humanoid:MoveTo(clampToHalf(target.Position + separation(bot, root), team))
			else
				if now > nextWander then
					nextWander = now + 1.5 + math.random()
					local r = CFG.BotAI.WanderRadius
					wander = Vector3.new((math.random() * 2 - 1) * r, 0, (math.random() * 2 - 1) * r * 0.5)
				end
				humanoid:MoveTo(clampToHalf(anchor + wander + separation(bot, root), team))
			end
		end
	end
end

function BotController.Spawn(team, position)
	local bot = createRig(team)
	if not bot then
		warn("[BotController] rig creation failed, add BotRig to ServerStorage")
		return nil
	end

	slotCount[team] = (slotCount[team] or 0) + 1
	local slot = slotCount[team]
	local laneX = (slot - 2) * CFG.BotAI.LaneSpacing

	local name = pickName()
	bot.Name = "Bot_" .. name
	bot:SetAttribute("Team", team)
	bot:SetAttribute("DisplayName", name)
	bot:SetAttribute("IsBot", true)
	bot:SetAttribute("Benched", false)
	bot:SetAttribute("Ragdolled", false)
	bot.Parent = workspace
	bot:PivotTo(CFrame.new(clampToHalf(Vector3.new(laneX, position.Y, position.Z), team) + Vector3.new(0, 3, 0)))

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
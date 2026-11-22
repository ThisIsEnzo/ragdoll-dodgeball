-- BotController: half-court sports AI.
--
-- Aggression fix: the catch branch used to end in `continue`, which skipped
-- ball pursuit and throwing entirely. A bot without a ball stood frozen,
-- reacting to threats forever. Catching is now an overlay that never blocks
-- the rest of the behaviour, with a real cooldown between attempts.

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

local CATCH_COOLDOWN = 0.9
local CATCH_CHANCE = 0.4

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

local function livingEnemies(character)
	local team = character:GetAttribute("Team")
	local root = character:FindFirstChild("HumanoidRootPart")
	local list = {}
	if not root or (team ~= 1 and team ~= 2) then return list end

	for _, model in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if model:IsA("Model") and model ~= character and model:GetAttribute("Team") ~= team then
			local enemyTeam = model:GetAttribute("Team")
			if (enemyTeam == 1 or enemyTeam == 2)
				and not model:GetAttribute("Benched") and not model:GetAttribute("Ragdolled") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local enemyRoot = model:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and enemyRoot then
					table.insert(list, {
						model = model,
						root = enemyRoot,
						distance = (enemyRoot.Position - root.Position).Magnitude,
					})
				end
			end
		end
	end

	table.sort(list, function(a, b) return a.distance < b.distance end)
	return list
end

-- Ignore teammates, but keep opponents and arena geometry in the raycast.
-- A ray that reaches a different valid opponent retargets to that opponent.
local function resolveTarget(bot, origin, enemies)
	local ballsFolder = workspace:FindFirstChild("Balls")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local team = bot:GetAttribute("Team")
	local ignore = { bot }
	if ballsFolder then table.insert(ignore, ballsFolder) end
	for _, actor in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if actor:IsA("Model") and actor:GetAttribute("Team") == team then
			table.insert(ignore, actor)
		end
	end
	params.FilterDescendantsInstances = ignore

	local byModel = {}
	for _, entry in ipairs(enemies) do
		byModel[entry.model] = entry
	end

	for index, entry in ipairs(enemies) do
		if index > CFG.BotAI.TargetScan then break end

		local velocity = entry.root.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local flightTime = entry.distance / math.max(CFG.Throw.SpeedMax, 1)
		local aim = entry.root.Position + Vector3.new(0, 1, 0)
			+ flatVelocity * flightTime * CFG.BotAI.LeadFactor

		local hit = workspace:Raycast(origin, aim - origin, params)
		if hit == nil then
			return entry, aim
		end

		local struckModel = hit.Instance:FindFirstAncestorOfClass("Model")
		local struckEntry = struckModel and byModel[struckModel]
		if struckEntry then
			return struckEntry, struckEntry.root.Position + Vector3.new(0, 1, 0)
		end
	end

	return nil, nil
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
	local lastThrowAt = -100
	local heldSince = 0
	local wasHolding = false
	local nextRepositionAt = 0
	local strafeSign = 1
	local nextCatchTry = 0
	local wander = Vector3.zero
	local nextWander = 0

	while bot.Parent and humanoid.Health > 0 do
		task.wait(CFG.BotAI.TickSeconds)

		if bot:GetAttribute("Benched") or bot:GetAttribute("Ragdolled") then
			continue
		end

		local now = os.clock()
		purgeClaims(now)

		local held = BallService.GetHeld(bot)

		if held then
			if not wasHolding then
				heldSince = now
				wasHolding = true
				strafeSign = if math.random() < 0.5 then -1 else 1
			end

			local heldFor = now - heldSince
			local origin = root.Position + Vector3.new(0, CFG.Throw.SpawnLift, 0)
			local enemies = livingEnemies(bot)
			local target, aim = resolveTarget(bot, origin, enemies)

			local gapReady = (now - lastThrowAt) >= CFG.BotAI.ThrowInterval
			local cooldownReady = (now - lastThrowAt) >= CFG.BotAI.ThrowCooldown
			local maxHoldReached = heldFor >= CFG.BotAI.MaxHold

			if target and aim and cooldownReady and (gapReady or maxHoldReached) then
				local charge = 0.55 + math.random() * 0.35
				local t = math.clamp((charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1)
				local speed = CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t
				local dir = ballistic(origin, aim, speed)
				local jitter = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.4, math.random() - 0.5) * math.rad(aimError)
				if BallService.Throw(bot, held, (dir + jitter).Unit, charge) then
					lastThrowAt = now
					wasHolding = false
				end
			elseif not target and now >= nextRepositionAt then
				-- Never throw blindly through arena geometry. Reposition and
				-- retry target selection on the next AI tick.
				local step = CFG.BotAI.RepositionStep
				if maxHoldReached then step *= 1.5 end
				local desired = throwLine + Vector3.new(strafeSign * step, 0, 0) + separation(bot, root)
				local clamped = clampToHalf(desired, team)
				if math.abs(clamped.X - desired.X) > 1 then
					strafeSign = -strafeSign
					desired = throwLine + Vector3.new(strafeSign * step, 0, 0) + separation(bot, root)
					clamped = clampToHalf(desired, team)
				else
					strafeSign = -strafeSign
				end
				humanoid:MoveTo(clamped)
				nextRepositionAt = now + 0.8
			end
		else
			wasHolding = false
			-- Empty handed: catching is an overlay, never a replacement for play.
			if now > nextCatchTry then
				local threat, threatDist = BallService.IncomingThreat(root, CFG.BotAI.CatchRange)
				if threat then
					nextCatchTry = now + CATCH_COOLDOWN
					if math.random() < CATCH_CHANCE then
						local flight = threatDist / math.max(threat.AssemblyLinearVelocity.Magnitude, 1)
						CatchService.OpenStance(bot, math.clamp(flight + 0.35, 0.3, 1.4))
					elseif math.random() < CFG.BotAI.EvadeChance then
						local velocity = threat.AssemblyLinearVelocity.Unit
						local side = Vector3.new(-velocity.Z, 0, velocity.X)
						if math.random() < 0.5 then side = -side end
						humanoid:MoveTo(clampToHalf(root.Position + side * CFG.BotAI.EvadeStrafe, team))
					end
				end
			end

			-- Always pursue a ball or hold the lane, even while reacting.
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
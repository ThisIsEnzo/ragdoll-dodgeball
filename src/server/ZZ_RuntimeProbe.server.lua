-- ZZ_RuntimeProbe: read-only runtime diagnostics for bot targeting and bench state.
-- This probe does not change gameplay state. It reports script inventory,
-- the same candidate scan / lead / raycast decision used by BotController,
-- and the position + Humanoid state of benched actors.
--
-- NOTE: Script names do not guarantee Roblox execution order. The 6s delay
-- only gives normal bootstrap time; it is not an execution-order guarantee.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))
local BallService = Resolve.Require(ServerScriptService, "BallService")

local REPORTS = 12
local INTERVAL = 2.5

local function line(message)
	print("[Probe] " .. message)
end

local function warnLine(message)
	warn("[Probe] " .. message)
end

local function inventory()
	line("---- SCRIPT INVENTORY ----")
	local expectedScripts = {
		"Bootstrap", "HitRules", "CourtBarrier", "BenchBehaviour",
		"ZoneImpulse", "SlamService", "ContactFeel", "MatchSummaryService",
		"PartyService", "PlainVisuals", "StyleService", "LoadoutService",
	}
	local found = {}
	for _, item in ipairs(ServerScriptService:GetDescendants()) do
		if item:IsA("Script") or item:IsA("ModuleScript") then
			found[item.Name] = item
		end
	end

	for _, name in ipairs(expectedScripts) do
		local item = found[name]
		if not item then
			warnLine("MISSING script " .. name)
		else
			local state = "ok"
			if item:IsA("Script") and item.Disabled then state = "DISABLED" end
			line(string.format("%-22s %s  %s", name, state, item:GetFullName()))
		end
	end

	for _, name in ipairs({ "HitZones", "SlamCatalog", "FeelCatalog", "Loadout", "RankCatalog" }) do
		local item = Shared:FindFirstChild(name)
		if item and item:IsA("ModuleScript") then
			line("shared module present: " .. name)
		else
			warnLine("MISSING shared ModuleScript " .. name)
		end
	end

	for _, name in ipairs({ "Remotes", "ZoneRemotes", "SlamRemotes", "FeelRemotes", "SummaryRemotes", "PartyRemotes", "StyleRemotes" }) do
		local folder = ReplicatedStorage:FindFirstChild(name)
		if folder then
			line(string.format("remote folder %-16s %d", name, #folder:GetChildren()))
		else
			warnLine("MISSING remote folder " .. name)
		end
	end
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

local function rayParamsFor(bot)
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
	return params
end

local function describeHit(hit, byModel)
	if not hit then return "CLEAR" end
	local struck = hit.Instance
	local struckModel = struck:FindFirstAncestorOfClass("Model")
	local validEnemy = struckModel and byModel[struckModel]
	if validEnemy then
		return string.format("RETARGET opponent=%s via %s", struckModel.Name, struck:GetFullName())
	end

	local ownerName = struckModel and struckModel.Name or "no Model ancestor"
	local details = ""
	if struck:IsA("BasePart") then
		details = string.format(" CanQuery=%s CanCollide=%s",
			tostring(struck.CanQuery), tostring(struck.CanCollide))
	end
	return string.format("BLOCKED by %s (model=%s) at y=%.1f%s",
		struck:GetFullName(), ownerName, hit.Position.Y, details)
end

-- Mirrors BotController.resolveTarget: nearest-first list, TargetScan limit,
-- lead prediction, teammate + held-ball exclusions, and opponent retargeting.
local function diagnoseBot(bot)
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local held = BallService.GetHeld(bot)
	local team = bot:GetAttribute("Team")
	local name = bot:GetAttribute("DisplayName") or bot.Name
	if not held then
		line(string.format("bot %-8s team=%s EMPTY pos=(%.0f,%.0f)",
			name, tostring(team), root.Position.X, root.Position.Z))
		return
	end

	local enemies = livingEnemies(bot)
	if #enemies == 0 then
		warnLine(string.format("bot %-8s HOLDS ball but NO living enemies", name))
		return
	end

	local origin = root.Position + Vector3.new(0, CFG.Throw.SpawnLift, 0)
	local params = rayParamsFor(bot)
	local byModel = {}
	for _, entry in ipairs(enemies) do byModel[entry.model] = entry end

	local limit = math.min(#enemies, CFG.BotAI.TargetScan)
	local foundTarget = false
	for index = 1, limit do
		local entry = enemies[index]
		local velocity = entry.root.AssemblyLinearVelocity
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local flightTime = entry.distance / math.max(CFG.Throw.SpeedMax, 1)
		local aim = entry.root.Position + Vector3.new(0, 1, 0)
			+ flatVelocity * flightTime * CFG.BotAI.LeadFactor

		local hit = workspace:Raycast(origin, aim - origin, params)
		local verdict = describeHit(hit, byModel)
		line(string.format("bot %-8s HOLDS candidate[%d]=%s d=%.1f -> %s",
			name, index, entry.model.Name, entry.distance, verdict))

		-- BotController returns the first unobstructed candidate, or retargets
		-- to a valid opponent that the ray actually intersects.
		if not hit or (hit.Instance:FindFirstAncestorOfClass("Model")
			and byModel[hit.Instance:FindFirstAncestorOfClass("Model")]) then
			foundTarget = true
			break
		end
	end

	if not foundTarget then
		warnLine(string.format("bot %-8s HOLDS: resolveTarget found NO valid target after %d/%d candidates",
			name, limit, #enemies))
	end
end

local function benchPosition(team)
	-- Diagnostic reference derived from the current BalanceConfig bench inset.
	local halfW = CFG.Arena.Width * 0.5
	local halfD = CFG.Arena.Depth * 0.5
	local sign = if team == 2 then 1 else -1
	return Vector3.new(
		sign * (halfW - CFG.Rules.BenchInsetX),
		2.5,
		sign * (halfD - CFG.Rules.BenchInsetZ))
end

local function diagnoseBenched()
	local any = false
	for _, actor in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if actor:IsA("Model") and actor:GetAttribute("Benched") then
			any = true
			local root = actor:FindFirstChild("HumanoidRootPart")
			local humanoid = actor:FindFirstChildOfClass("Humanoid")
			local team = actor:GetAttribute("Team")
			if root and humanoid and typeof(team) == "number" then
				local target = benchPosition(team)
				local flat = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z)
				local name = actor:GetAttribute("DisplayName") or actor.Name
				line(string.format("BENCHED %-8s distToConfigBench=%.1f Sit=%s WalkSpeed=%.1f Ragdolled=%s pos=(%.1f,%.1f,%.1f)",
					name, flat.Magnitude, tostring(humanoid.Sit), humanoid.WalkSpeed,
					tostring(actor:GetAttribute("Ragdolled")),
					root.Position.X, root.Position.Y, root.Position.Z))
			end
		end
	end
	if not any then line("BENCHED none right now") end
end

local function barrierState()
	local barrier = workspace:FindFirstChild("CentreBarrier")
	if not barrier then
		warnLine("CentreBarrier absent from workspace")
		return
	end
	line(string.format("CentreBarrier CanCollide=%s CanQuery=%s",
		tostring(barrier.CanCollide), tostring(barrier.CanQuery)))
end

task.spawn(function()
	task.wait(6)
	inventory()
	barrierState()

	for index = 1, REPORTS do
		line(string.format("---- SAMPLE %d / %d ----", index, REPORTS))
		local bots = 0
		for _, actor in ipairs(CollectionService:GetTagged("DodgeballActor")) do
			if actor:IsA("Model") and actor:GetAttribute("IsBot") and actor.Parent then
				bots += 1
				diagnoseBot(actor)
			end
		end
		if bots == 0 then warnLine("no bots tagged DodgeballActor with IsBot") end
		diagnoseBenched()
		task.wait(INTERVAL)
	end

	line("---- PROBE COMPLETE ----")
	line("paste everything from SCRIPT INVENTORY to PROBE COMPLETE")
end)

print("[Probe] runtime probe armed; first report in 6s")

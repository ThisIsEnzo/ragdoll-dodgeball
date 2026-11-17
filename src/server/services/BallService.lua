-- BallService v0.9.0: у мяча своя гравитация.
--
-- Причина: при мировой гравитации 196 плоский бросок с высоты 4 долетает только 17 studs,
-- а команды стоят в 44 studs друг от друга. Мяч падал, терял Clean, и ловить было нечего.
-- VectorForce компенсирует (1 - GravityScale) мировой гравитации, оставляя мячу лёгкую дугу.
--
-- Перенос остаётся локальным визуалом, попадания считаются sweep-ом.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Collision = require(Shared:WaitForChild("Collision"))

local BallService = {}
BallService.HitDetected = Instance.new("BindableEvent")
BallService.PickedUp = Instance.new("BindableEvent")

local ballsFolder: Folder? = nil
local heldFolder: Folder? = nil
local holder: { [BasePart]: Model } = {}
local heldBy: { [Model]: BasePart } = {}
local heldSince: { [BasePart]: number } = {}
local history: { [BasePart]: { { t: number, p: Vector3 } } } = {}
local previous: { [BasePart]: Vector3 } = {}
local slowSince: { [BasePart]: number } = {}
local lastThrow: { [BasePart]: { actor: Model, at: number } } = {}
local spawnPoints: { Vector3 } = {}
local accumulator = 0

local sweepParams = RaycastParams.new()
sweepParams.FilterType = Enum.RaycastFilterType.Exclude
sweepParams.IgnoreWater = true

local function isActorAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("Benched") then return false end
	if character:GetAttribute("Ragdolled") then return false end
	return true
end

local function setCarrying(actor: Model?, value: boolean)
	if actor and actor.Parent then actor:SetAttribute("Carrying", value) end
end

local function clearTables(ball: BasePart)
	local actor = holder[ball]
	if actor then
		heldBy[actor] = nil
		setCarrying(actor, false)
	end
	holder[ball] = nil
	heldSince[ball] = nil
end

local function release(ball: BasePart)
	clearTables(ball)
	ball:SetAttribute("HeldBy", nil)
	if not ball:IsDescendantOf(game) then return end
	pcall(function() ball.Parent = ballsFolder end)
	ball.Transparency = 0
	ball.Anchored = false
	ball.CanCollide = true
	ball.CanQuery = true
	ball.CollisionGroup = "Balls"
	pcall(function() ball:SetNetworkOwner(nil) end)
end

local function attach(actor: Model, ball: BasePart)
	if heldBy[actor] then return false end
	if holder[ball] then release(ball) end

	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.Transparency = 1
	ball.CollisionGroup = "HeldBalls"

	holder[ball] = actor
	heldBy[actor] = ball
	heldSince[ball] = os.clock()
	ball:SetAttribute("HeldBy", actor.Name)
	ball:SetAttribute("Clean", false)
	setCarrying(actor, true)

	pcall(function() ball.Parent = heldFolder end)

	local player = Players:GetPlayerFromCharacter(actor)
	if player then BallService.PickedUp:Fire(player) end
	return true
end

-- Компенсация гравитации: мяч летит по дуге, пригодной для площадки 90x60
local function applyLift(ball: BasePart)
	local scale = math.clamp(CFG.Ball.GravityScale, 0.05, 1)
	if scale >= 1 then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "LiftAnchor"
	attachment.Parent = ball

	local force = Instance.new("VectorForce")
	force.Name = "BallLift"
	force.Attachment0 = attachment
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.new(0, ball:GetMass() * workspace.Gravity * (1 - scale), 0)
	force.Enabled = true
	force.Parent = ball
end

local function makeBall(position: Vector3): BasePart
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * CFG.Ball.Size
	ball.Color = Color3.fromRGB(255, 197, 61)
	ball.Material = Enum.Material.SmoothPlastic
	ball.CanCollide = true
	ball.CanTouch = false
	ball.CanQuery = true
	ball.CastShadow = false
	ball.CollisionGroup = "Balls"
	ball.CustomPhysicalProperties = PhysicalProperties.new(
		CFG.Ball.Density, CFG.Ball.Friction, CFG.Ball.Elasticity, 1, 1
	)
	ball.CFrame = CFrame.new(position)
	ball:SetAttribute("Clean", false)
	ball:SetAttribute("Uncatchable", false)
	ball.Parent = ballsFolder
	ball:SetNetworkOwner(nil)
	CollectionService:AddTag(ball, "Dodgeball")

	applyLift(ball)

	history[ball] = {}
	previous[ball] = position
	slowSince[ball] = os.clock()

	ball.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearTables(ball)
			history[ball] = nil
			previous[ball] = nil
			slowSince[ball] = nil
			lastThrow[ball] = nil
		end
	end)

	return ball
end

function BallService.Init()
	Collision.Setup()

	local existing = workspace:FindFirstChild("Balls")
	if existing and existing:IsA("Folder") then
		ballsFolder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Balls"
		created.Parent = workspace
		ballsFolder = created
	end
	sweepParams.FilterDescendantsInstances = { ballsFolder }

	local held = ServerStorage:FindFirstChild("HeldBalls")
	if held and held:IsA("Folder") then
		heldFolder = held
	else
		local created = Instance.new("Folder")
		created.Name = "HeldBalls"
		created.Parent = ServerStorage
		heldFolder = created
	end

	local markers = workspace:FindFirstChild("BallSpawns")
	if markers then
		for _, part in ipairs(markers:GetChildren()) do
			if part:IsA("BasePart") then
				table.insert(spawnPoints, part.Position)
				part.Transparency = 1
				part.CanCollide = false
			end
		end
	end
	if #spawnPoints == 0 then
		table.insert(spawnPoints, Vector3.new(0, 5, -8))
		table.insert(spawnPoints, Vector3.new(0, 5, 0))
		table.insert(spawnPoints, Vector3.new(0, 5, 8))
	end
end

function BallService.SpawnAll()
	for _, character in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if character:IsA("Model") then character:SetAttribute("Carrying", false) end
	end
	if heldFolder then heldFolder:ClearAllChildren() end
	if ballsFolder then ballsFolder:ClearAllChildren() end
	table.clear(holder); table.clear(heldBy); table.clear(heldSince)
	for _, position in ipairs(spawnPoints) do
		makeBall(position + Vector3.new(0, 3, 0))
	end
end

function BallService.GetHeld(actor: Model): BasePart?
	return heldBy[actor]
end

function BallService.GiveBall(actor: Model, ball: BasePart): boolean
	return attach(actor, ball)
end

function BallService.ForceRelease(actor: Model)
	local ball = heldBy[actor]
	if ball then
		local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
		release(ball)
		if root then
			ball.CFrame = CFrame.new(root.Position + Vector3.new(0, 1.5, 0))
			previous[ball] = ball.Position
		end
		ball:SetAttribute("Clean", false)
		history[ball] = {}
	end
end

function BallService.LastThrower(ball: BasePart): (Model?, number?)
	local record = lastThrow[ball]
	if record then return record.actor, record.at end
	return nil, nil
end

function BallService.Throw(
	actor: Model, ball: BasePart, direction: Vector3,
	charge: number, speedMul: number?, clientOrigin: Vector3?
): boolean
	if holder[ball] ~= actor then return false end
	if direction.Magnitude < 0.01 then return false end

	local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local dir = direction.Unit
	local t = math.clamp((charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1)
	local speed = (CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t) * (speedMul or 1)

	local base = root.Position
	if typeof(clientOrigin) == "Vector3" then
		if (clientOrigin - root.Position).Magnitude <= CFG.Throw.OriginLeeway then
			base = clientOrigin
		end
	end
	local origin = base + Vector3.new(0, CFG.Throw.SpawnLift, 0)
	local target = origin + dir * CFG.Throw.SpawnOffset

	release(ball)

	local placeParams = RaycastParams.new()
	placeParams.FilterType = Enum.RaycastFilterType.Exclude
	placeParams.FilterDescendantsInstances = { actor, ballsFolder }
	placeParams.IgnoreWater = true

	if workspace:Raycast(origin, target - origin, placeParams) then
		target = origin + dir * 0.9
	end

	ball.CFrame = CFrame.new(target)
	ball.AssemblyLinearVelocity = dir * speed
	ball.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
	ball:SetAttribute("Clean", true)
	ball:SetAttribute("Uncatchable", false)

	lastThrow[ball] = { actor = actor, at = os.clock() }
	previous[ball] = target
	slowSince[ball] = os.clock()
	history[ball] = {}
	return true
end

function BallService.SampleAt(ball: BasePart, t: number): Vector3?
	local samples = history[ball]
	if not samples or #samples == 0 then return nil end
	if t <= samples[1].t then return samples[1].p end
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		if t >= a.t and t <= b.t then
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-6)
			return a.p:Lerp(b.p, alpha)
		end
	end
	return samples[#samples].p
end

function BallService.NearestFree(position: Vector3, maxDistance: number): BasePart?
	local best, bestDist = nil, maxDistance
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and not holder[ball] and ball:IsDescendantOf(workspace) then
			local d = (ball.Position - position).Magnitude
			if d < bestDist then best, bestDist = ball, d end
		end
	end
	return best
end

local function sweepHit(ball: BasePart, from: Vector3, to: Vector3, speed: number)
	local delta = to - from
	if delta.Magnitude < 0.01 then return end

	local result = workspace:Spherecast(from, CFG.Ball.Size * 0.5, delta, sweepParams)
	if not result then return end

	local character = result.Instance:FindFirstAncestorOfClass("Model")
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		ball:SetAttribute("Clean", false)
		return
	end
	if not isActorAlive(character) then return end

	local record = lastThrow[ball]
	if record and record.actor == character and os.clock() - record.at < 0.25 then return end

	ball:SetAttribute("Clean", false)
	BallService.HitDetected:Fire(ball, character, speed, result.Position)
end

local function tryPickup(ball: BasePart, speed: number)
	if holder[ball] or speed > CFG.Ball.PickupMaxSpeed then return end
	local record = lastThrow[ball]

	for _, character in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if character:IsA("Model") and isActorAlive(character) and not heldBy[character] then
			if not (record and record.actor == character and os.clock() - record.at < 0.4) then
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (ball.Position - root.Position).Magnitude <= CFG.Throw.PickupRadius then
					attach(character, ball)
					return
				end
			end
		end
	end
end

function BallService.Start()
	local interval = 1 / CFG.Ball.HistoryRate
	local maxSamples = math.floor(CFG.Ball.HistorySeconds * CFG.Ball.HistoryRate)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()

		for ball, actor in pairs(holder) do
			if not actor.Parent or not ball.Parent then
				clearTables(ball)
			elseif now - (heldSince[ball] or 0) > CFG.Throw.HoldTimeout then
				BallService.ForceRelease(actor)
			end
		end

		for ball in pairs(history) do
			if ball.Parent and not holder[ball] and ball:IsDescendantOf(workspace) then
				local speed = ball.AssemblyLinearVelocity.Magnitude
				local from = previous[ball] or ball.Position
				local to = ball.Position

				if speed >= CFG.Ball.MinHitSpeed then
					slowSince[ball] = now
					sweepHit(ball, from, to, speed)
				else
					if now - (slowSince[ball] or now) > 0.25 then
						ball:SetAttribute("Clean", false)
					end
					tryPickup(ball, speed)
				end

				previous[ball] = to

				if to.Y < CFG.Ball.RespawnBelowY then
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.CFrame = CFrame.new(spawnPoints[math.random(1, #spawnPoints)] + Vector3.new(0, 3, 0))
					ball:SetAttribute("Clean", false)
					previous[ball] = ball.Position
					history[ball] = {}
				end
			end
		end

		accumulator += dt
		if accumulator < interval then return end
		accumulator = 0

		local sampleTime = workspace:GetServerTimeNow()
		for ball, samples in pairs(history) do
			if ball.Parent and not holder[ball] and ball:IsDescendantOf(workspace) then
				table.insert(samples, { t = sampleTime, p = ball.Position })
				if #samples > maxSamples then table.remove(samples, 1) end
			end
		end
	end)
end

return BallService

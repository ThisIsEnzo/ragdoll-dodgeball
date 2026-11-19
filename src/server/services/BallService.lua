-- BallService: ball lifecycle, carry, sweep hits, pickup.
-- Audit fix: a slow rolling ball used to score KOs because MinHitSpeed was 14.
-- A hit now requires both enough speed and a recent throw, so loose balls
-- rolling across the floor are harmless until someone picks them up.

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

local ballsFolder = nil
local heldFolder = nil
local holder = {}
local heldBy = {}
local heldSince = {}
local history = {}
local previous = {}
local slowSince = {}
local lastThrow = {}
local spawnPoints = {}
local accumulator = 0

local sweepParams = RaycastParams.new()
sweepParams.FilterType = Enum.RaycastFilterType.Exclude
sweepParams.IgnoreWater = true

local function alive(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("Benched") then return false end
	if character:GetAttribute("Ragdolled") then return false end
	return true
end

local function setCarrying(actor, value)
	if actor and actor.Parent then actor:SetAttribute("Carrying", value) end
end

local function clearTables(ball)
	local actor = holder[ball]
	if actor then
		heldBy[actor] = nil
		setCarrying(actor, false)
	end
	holder[ball] = nil
	heldSince[ball] = nil
end

local function release(ball)
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

local function attach(actor, ball)
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

local function applyLift(ball)
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

local function makeBall(position)
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
		CFG.Ball.Density, CFG.Ball.Friction, CFG.Ball.Elasticity, 1, 1)
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
		for _, p in ipairs(markers:GetChildren()) do
			if p:IsA("BasePart") then
				table.insert(spawnPoints, p.Position)
				p.Transparency = 1
				p.CanCollide = false
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
	table.clear(holder)
	table.clear(heldBy)
	table.clear(heldSince)
	for _, position in ipairs(spawnPoints) do
		makeBall(position + Vector3.new(0, 3, 0))
	end
end

function BallService.GetHeld(actor) return heldBy[actor] end
function BallService.GiveBall(actor, ball) return attach(actor, ball) end

function BallService.ForceRelease(actor)
	local ball = heldBy[actor]
	if not ball then return end
	local root = actor:FindFirstChild("HumanoidRootPart")
	release(ball)
	if root then
		ball.CFrame = CFrame.new(root.Position + Vector3.new(0, 1.5, 0))
		previous[ball] = ball.Position
	end
	ball:SetAttribute("Clean", false)
	history[ball] = {}
	lastThrow[ball] = nil
end

function BallService.LastThrower(ball)
	local record = lastThrow[ball]
	if record then return record.actor, record.at end
	return nil, nil
end

-- A ball is dangerous only while it is still a live throw.
function BallService.IsLive(ball)
	local record = lastThrow[ball]
	if not record then return false end
	if os.clock() - record.at > CFG.Rules.ThrowLiveWindow then return false end
	if not record.actor or not record.actor.Parent then return false end
	return ball.AssemblyLinearVelocity.Magnitude >= CFG.Ball.MinHitSpeed
end

function BallService.Throw(actor, ball, direction, charge, speedMul, clientOrigin)
	if holder[ball] ~= actor then return false end
	if direction.Magnitude < 0.01 then return false end
	local root = actor:FindFirstChild("HumanoidRootPart")
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

function BallService.SampleAt(ball, t)
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

function BallService.NearestFree(position, maxDistance)
	local best, bestDist = nil, maxDistance
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and not holder[ball] and ball:IsDescendantOf(workspace) then
			local d = (ball.Position - position).Magnitude
			if d < bestDist then best, bestDist = ball, d end
		end
	end
	return best
end

function BallService.IncomingThreat(root, range)
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace) and not holder[ball] then
			if BallService.IsLive(ball) then
				local toTarget = root.Position - ball.Position
				local d = toTarget.Magnitude
				if d > 1 and d < range then
					if ball.AssemblyLinearVelocity.Unit:Dot(toTarget.Unit) > 0.86 then
						return ball, d
					end
				end
			end
		end
	end
	return nil, nil
end

local function sweepHit(ball, from, to, speed)
	local delta = to - from
	if delta.Magnitude < 0.01 then return end
	if not BallService.IsLive(ball) then return end

	local result = workspace:Spherecast(from, CFG.Ball.Size * 0.5, delta, sweepParams)
	if not result then return end

	local character = result.Instance:FindFirstAncestorOfClass("Model")
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		ball:SetAttribute("Clean", false)
		return
	end
	if not alive(character) then return end

	local record = lastThrow[ball]
	if record and record.actor == character and os.clock() - record.at < 0.25 then return end

	BallService.HitDetected:Fire(ball, character, speed, result.Position)
	ball:SetAttribute("Clean", false)
end

local function tryPickup(ball, speed)
	if holder[ball] or speed > CFG.Ball.PickupMaxSpeed then return end
	local record = lastThrow[ball]

	for _, character in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if character:IsA("Model") and alive(character) and not heldBy[character] then
			local blocked = false
			if record and record.actor == character and os.clock() - record.at < 0.4 then
				blocked = true
			end
			if not blocked then
				local root = character:FindFirstChild("HumanoidRootPart")
				if root then
					local offset = ball.Position - root.Position
					local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
					if flat <= CFG.Throw.PickupRadius and math.abs(offset.Y) <= CFG.Ball.PickupVerticalLimit then
						attach(character, ball)
						return
					end
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

				if BallService.IsLive(ball) then
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
					lastThrow[ball] = nil
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
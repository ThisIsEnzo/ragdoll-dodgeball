-- BallService v0.3.0.
-- Перенос: мяч Anchored + CanCollide false + группа HeldBalls. Толкнуть игрока не может.
-- Попадания: Spherecast по пути мяча за кадр (нет туннелинга на 130 studs/s).
-- Подбор: близость к персонажу, только для медленных мячей. Быстрый надо ловить кнопкой.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Collision = require(Shared:WaitForChild("Collision"))

local BallService = {}
BallService.HitDetected = Instance.new("BindableEvent")

local ballsFolder: Folder? = nil
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

local function release(ball: BasePart)
	local actor = holder[ball]
	if actor then heldBy[actor] = nil end
	holder[ball] = nil
	heldSince[ball] = nil
	ball:SetAttribute("HeldBy", nil)
	ball.Anchored = false
	ball.CanCollide = true
	ball.CanQuery = true
	ball.CollisionGroup = "Balls"
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
	ball.CollisionGroup = "HeldBalls"

	holder[ball] = actor
	heldBy[actor] = ball
	heldSince[ball] = os.clock()
	ball:SetAttribute("HeldBy", actor.Name)
	ball:SetAttribute("Clean", false)
	return true
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

	history[ball] = {}
	previous[ball] = position
	slowSince[ball] = os.clock()

	ball.AncestryChanged:Connect(function(_, parent)
		if not parent then
			release(ball)
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
		release(ball)
		ball:SetAttribute("Clean", false)
		previous[ball] = ball.Position
	end
end

function BallService.LastThrower(ball: BasePart): (Model?, number?)
	local record = lastThrow[ball]
	if record then return record.actor, record.at end
	return nil, nil
end

function BallService.Throw(actor: Model, ball: BasePart, direction: Vector3, charge: number, speedMul: number?): boolean
	if holder[ball] ~= actor then return false end
	if direction.Magnitude < 0.01 then return false end

	local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local dir = direction.Unit
	local t = math.clamp((charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1)
	local speed = (CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t) * (speedMul or 1)

	release(ball)

	local origin = root.Position + Vector3.new(0, CFG.Throw.SpawnLift, 0)
	local target = origin + dir * CFG.Throw.SpawnOffset

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
		if ball:IsA("BasePart") and not holder[ball] then
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
			local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and ball.Parent then
				ball.CFrame = root.CFrame * CFrame.new(CFG.Ball.CarryOffset)
				if now - (heldSince[ball] or 0) > CFG.Throw.HoldTimeout then
					BallService.ForceRelease(actor)
				end
			else
				release(ball)
			end
		end

		for ball in pairs(history) do
			if ball.Parent and not holder[ball] then
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
				end
			end
		end

		accumulator += dt
		if accumulator < interval then return end
		accumulator = 0

		local sampleTime = workspace:GetServerTimeNow()
		for ball, samples in pairs(history) do
			if ball.Parent then
				table.insert(samples, { t = sampleTime, p = ball.Position })
				if #samples > maxSamples then table.remove(samples, 1) end
			end
		end
	end)
end

return BallService

-- BallService v0.2: владение по персонажу (поддерживает ботов), Clean-флаг, таймаут удержания.
-- Мяч всегда server-owned. История позиций нужна CatchService для компенсации лага.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local BallService = {}

local ballsFolder: Folder? = nil
local holder: { [BasePart]: Model } = {}
local heldBy: { [Model]: BasePart } = {}
local heldSince: { [BasePart]: number } = {}
local history: { [BasePart]: { { t: number, p: Vector3 } } } = {}
local lastThrow: { [BasePart]: { actor: Model, at: number } } = {}
local spawnPoints: { Vector3 } = {}
local accumulator = 0

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
	ball.CanCollide = true
end

local function attach(actor: Model, ball: BasePart)
	if heldBy[actor] then return false end
	if holder[ball] then release(ball) end
	holder[ball] = actor
	heldBy[actor] = ball
	heldSince[ball] = os.clock()
	ball:SetAttribute("HeldBy", actor.Name)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CanCollide = false
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

	ball.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid then
			if holder[ball] or not isActorAlive(character) then return end
			local record = lastThrow[ball]
			if record and record.actor == character and os.clock() - record.at < 0.4 then return end
			attach(character, ball)
		else
			if holder[ball] == nil then
				ball:SetAttribute("Clean", false)
			end
		end
	end)

	ball.AncestryChanged:Connect(function(_, parent)
		if not parent then
			release(ball)
			history[ball] = nil
			lastThrow[ball] = nil
		end
	end)

	return ball
end

function BallService.Init()
	local existing = workspace:FindFirstChild("Balls")
	if existing and existing:IsA("Folder") then
		ballsFolder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Balls"
		created.Parent = workspace
		ballsFolder = created
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
	end
end

function BallService.LastThrower(ball: BasePart): (Model?, number?)
	local r = lastThrow[ball]
	if r then return r.actor, r.at end
	return nil, nil
end

function BallService.Throw(actor: Model, ball: BasePart, direction: Vector3, charge: number, speedMul: number?): boolean
	if holder[ball] ~= actor then return false end

	local t = math.clamp((charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1)
	local speed = (CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t) * (speedMul or 1)

	release(ball)
	ball.CFrame = CFrame.new(ball.Position + direction.Unit * 2)
	ball.AssemblyLinearVelocity = direction.Unit * speed
	ball.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
	ball:SetAttribute("Clean", true)
	ball:SetAttribute("Uncatchable", false)
	lastThrow[ball] = { actor = actor, at = os.clock() }
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

function BallService.Start()
	local interval = 1 / CFG.Ball.HistoryRate
	local maxSamples = math.floor(CFG.Ball.HistorySeconds * CFG.Ball.HistoryRate)

	RunService.Heartbeat:Connect(function(dt)
		for ball, actor in pairs(holder) do
			local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and ball.Parent then
				ball.CFrame = root.CFrame * CFrame.new(0.9, 0.6, -1.4)
				if os.clock() - (heldSince[ball] or 0) > CFG.Throw.HoldTimeout then
					BallService.ForceRelease(actor)
				end
			else
				release(ball)
			end
		end

		accumulator += dt
		if accumulator < interval then return end
		accumulator = 0

		local now = workspace:GetServerTimeNow()
		for ball, samples in pairs(history) do
			if ball.Parent then
				table.insert(samples, { t = now, p = ball.Position })
				if #samples > maxSamples then table.remove(samples, 1) end
				if ball.Position.Y < CFG.Ball.RespawnBelowY and not holder[ball] then
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.CFrame = CFrame.new(spawnPoints[math.random(1, #spawnPoints)] + Vector3.new(0, 3, 0))
					ball:SetAttribute("Clean", false)
				end
			end
		end
	end)
end

return BallService

-- BallService: спавн мячей, владение, бросок, история позиций для компенсации лага.
-- Мяч всегда server-owned. Клиент только предсказывает картинку.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local BallService = {}

local ballsFolder: Folder? = nil
local holder: { [BasePart]: number } = {}      -- ball -> userId
local heldBy: { [number]: BasePart } = {}      -- userId -> ball
local history: { [BasePart]: { { t: number, p: Vector3 } } } = {}
local lastThrow: { [BasePart]: { userId: number, at: number } } = {}
local spawnPoints: { Vector3 } = {}
local accumulator = 0

local function makeBall(position: Vector3): BasePart
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * CFG.Ball.Size
	ball.Color = Color3.fromRGB(255, 197, 61)
	ball.Material = Enum.Material.SmoothPlastic
	ball.CanCollide = true
	ball.CanQuery = true
	ball.CollisionGroup = "Balls"
	ball.CustomPhysicalProperties = PhysicalProperties.new(
		CFG.Ball.Density, CFG.Ball.Friction, CFG.Ball.Elasticity, 1, 1
	)
	ball.CFrame = CFrame.new(position)
	ball.Parent = ballsFolder
	ball:SetNetworkOwner(nil)
	CollectionService:AddTag(ball, "Dodgeball")

	history[ball] = {}

	ball.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if holder[ball] then
			return
		end
		local player = game:GetService("Players"):GetPlayerFromCharacter(character)
		if not player or heldBy[player.UserId] then
			return
		end
		holder[ball] = player.UserId
		heldBy[player.UserId] = ball
		ball:SetAttribute("HeldBy", player.UserId)
	end)

	ball.AncestryChanged:Connect(function(_, parent)
		if not parent then
			local owner = holder[ball]
			if owner then
				heldBy[owner] = nil
			end
			holder[ball] = nil
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
	for _, position in ipairs(spawnPoints) do
		makeBall(position + Vector3.new(0, 3, 0))
	end
end

function BallService.GetHeld(userId: number): BasePart?
	return heldBy[userId]
end

function BallService.LastThrower(ball: BasePart): (number?, number?)
	local record = lastThrow[ball]
	if record then
		return record.userId, record.at
	end
	return nil, nil
end

-- Серверный бросок. Валидацию charge/dir делает вызывающий слой.
function BallService.Throw(player: Player, ball: BasePart, direction: Vector3, charge: number, speedMul: number?)
	if holder[ball] ~= player.UserId then
		return false
	end

	local t = math.clamp(
		(charge - CFG.Throw.ChargeMin) / (CFG.Throw.ChargeMax - CFG.Throw.ChargeMin), 0, 1
	)
	local speed = CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t
	speed *= (speedMul or 1)

	holder[ball] = nil
	heldBy[player.UserId] = nil
	ball:SetAttribute("HeldBy", nil)

	ball.AssemblyLinearVelocity = direction.Unit * speed
	ball.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
	lastThrow[ball] = { userId = player.UserId, at = os.clock() }

	return true
end

-- Линейная интерполяция позиции мяча в момент времени t (для lag-comp ловли)
function BallService.SampleAt(ball: BasePart, t: number): Vector3?
	local samples = history[ball]
	if not samples or #samples == 0 then
		return nil
	end
	if t <= samples[1].t then
		return samples[1].p
	end
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		if t >= a.t and t <= b.t then
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-6)
			return a.p:Lerp(b.p, alpha)
		end
	end
	return samples[#samples].p
end

function BallService.Start()
	local interval = 1 / CFG.Ball.HistoryRate
	local maxSamples = math.floor(CFG.Ball.HistorySeconds * CFG.Ball.HistoryRate)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = 0

		local now = workspace:GetServerTimeNow()
		for ball, samples in pairs(history) do
			if ball.Parent then
				table.insert(samples, { t = now, p = ball.Position })
				if #samples > maxSamples then
					table.remove(samples, 1)
				end
				if ball.Position.Y < CFG.Ball.RespawnBelowY then
					local owner = holder[ball]
					if owner then
						heldBy[owner] = nil
						holder[ball] = nil
						ball:SetAttribute("HeldBy", nil)
					end
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.CFrame = CFrame.new(spawnPoints[math.random(1, #spawnPoints)] + Vector3.new(0, 3, 0))
				end
			end
		end
	end)
end

return BallService

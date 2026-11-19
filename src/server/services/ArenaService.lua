-- ArenaService: court geometry and markers.
-- Audit fix: bench markers used to sit at x = +/- (halfWidth + 9), outside the
-- walls, so knocked-out players were teleported out of the building. Benches
-- now live inside the court, in the back corner of each team half.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Collision = require(Shared:WaitForChild("Collision"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")

local ArenaService = {}
local walls = {}
local shrinking = false
local alpha = 0

local function part(name, size, position, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Arena"
	p.Parent = parent
	return p
end

local function marker(name, position, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(2, 1, 2)
	p.Position = position
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Parent = parent
	return p
end

function ArenaService.BenchPosition(team)
	local halfW = CFG.Arena.Width * 0.5
	local halfD = CFG.Arena.Depth * 0.5
	local sign = -1
	if team == 2 then sign = 1 end
	return Vector3.new(
		sign * (halfW - CFG.Rules.BenchInsetX),
		2.5,
		sign * (halfD - CFG.Rules.BenchInsetZ)
	)
end

local function build()
	local A = CFG.Arena
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena:SetAttribute("Procedural", true)
	arena.Parent = workspace

	local floor = part("Floor", Vector3.new(A.Width, 1, A.Depth), Vector3.new(0, 0.5, 0), A.FloorColor, arena)
	floor.Material = Enum.Material.Wood

	local halfW, halfD = A.Width * 0.5, A.Depth * 0.5
	local t, h = A.WallThickness, A.WallHeight

	local specs = {
		{ "WallNorth", Vector3.new(A.Width + t * 2, h, t), Vector3.new(0, h * 0.5 + 1, -(halfD + t * 0.5)) },
		{ "WallSouth", Vector3.new(A.Width + t * 2, h, t), Vector3.new(0, h * 0.5 + 1, halfD + t * 0.5) },
		{ "WallWest", Vector3.new(t, h, A.Depth), Vector3.new(-(halfW + t * 0.5), h * 0.5 + 1, 0) },
		{ "WallEast", Vector3.new(t, h, A.Depth), Vector3.new(halfW + t * 0.5, h * 0.5 + 1, 0) },
	}

	for _, spec in ipairs(specs) do
		local wall = part(spec[1], spec[2], spec[3], A.WallColor, arena)
		wall.Material = Enum.Material.Glass
		wall.Transparency = 0.75
		wall.Reflectance = 0.05
		table.insert(walls, { part = wall, basePos = spec[3], baseSize = spec[2] })
	end

	local ceiling = part("Ceiling", Vector3.new(A.Width + t * 2, 1, A.Depth + t * 2),
		Vector3.new(0, A.CeilingHeight, 0), A.WallColor, arena)
	ceiling.Transparency = 1

	for team = 1, 2 do
		local entry = CFG.Teams[team]
		local sign = -1
		if team == 2 then sign = 1 end

		local spawns = Instance.new("Folder")
		spawns.Name = "Team" .. team .. "Spawns"
		spawns.Parent = arena
		local z = sign * (halfD - 8)
		for i = -1, 1 do
			marker("Spawn" .. (i + 2), Vector3.new(i * 10, 2, z), spawns)
		end

		local benchPos = ArenaService.BenchPosition(team)
		marker("Bench" .. team, benchPos, arena)

		local pad = part("BenchPad" .. team, Vector3.new(16, 0.6, 6),
			Vector3.new(benchPos.X, 1.3, benchPos.Z), entry.dark, arena)
		pad.Material = Enum.Material.Fabric
		part("BenchBack" .. team, Vector3.new(16, 2.6, 0.5),
			Vector3.new(benchPos.X, 2.6, benchPos.Z + sign * 3), entry.color, arena)
	end

	local spawns = workspace:FindFirstChild("BallSpawns")
	if not spawns then
		spawns = Instance.new("Folder")
		spawns.Name = "BallSpawns"
		spawns.Parent = workspace
		for i = -1, 1 do
			marker("BallSpawn" .. (i + 2), Vector3.new(0, 3, i * 7), spawns)
		end
	end

	print("[Arena] court built, benches inside the venue")
end

local function adopt(arena)
	for _, child in ipairs(arena:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CastShadow = false
			if string.find(child.Name, "^Wall") then
				child.Transparency = 0.75
				table.insert(walls, { part = child, basePos = child.Position, baseSize = child.Size })
			end
		end
	end
	for team = 1, 2 do
		local existing = arena:FindFirstChild("Bench" .. team)
		local pos = ArenaService.BenchPosition(team)
		if existing then
			existing.Position = pos
		else
			marker("Bench" .. team, pos, arena)
		end
	end
	print("[Arena] existing arena adopted, benches relocated inside")
end

function ArenaService.Init()
	Collision.Setup()
	local existing = workspace:FindFirstChild("Arena")
	if existing then adopt(existing) else build() end
end

function ArenaService.Start()
	RoundService.StateChanged.Event:Connect(function(state)
		shrinking = (state == "SuddenDeath")
	end)

	RunService.Heartbeat:Connect(function(dt)
		if #walls == 0 then return end
		local target = 0
		if shrinking then target = 1 end
		if math.abs(alpha - target) < 0.001 then return end

		local step = dt / math.max(CFG.Arena.ShrinkTime, 0.05)
		if shrinking then
			alpha = math.min(1, alpha + step)
		else
			alpha = math.max(0, alpha - step)
		end

		local scale = 1 - (1 - CFG.Arena.ShrinkScale) * alpha
		local color = CFG.Arena.WallColor:Lerp(CFG.Arena.SuddenColor, alpha)

		for _, entry in ipairs(walls) do
			local p = entry.part
			if p.Parent then
				p.Size = Vector3.new(entry.baseSize.X * scale, entry.baseSize.Y, entry.baseSize.Z * scale)
				p.Position = Vector3.new(entry.basePos.X * scale, entry.basePos.Y, entry.basePos.Z * scale)
				p.Color = color
			end
		end
	end)
end

return ArenaService
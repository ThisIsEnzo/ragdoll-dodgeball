-- ArenaService: процедурный спортзал. Стены держат мячи, трибуны для выбитых,
-- разметка и маркеры спавнов. В sudden death стены сдвигаются внутрь и краснеют.
-- Если в Workspace уже есть своя Arena — не перестраиваем, уважаем ручной билд.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Collision = require(Shared:WaitForChild("Collision"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")

local ArenaService = {}

local walls: { any } = {}
local shrinking = false
local shrinkAlpha = 0

local function part(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Arena"
	p.Parent = parent
	return p
end

local function marker(name: string, position: Vector3, parent: Instance)
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

local function build()
	local A = CFG.Arena
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena:SetAttribute("Procedural", true)
	arena.Parent = workspace

	local floor = part("Floor", Vector3.new(A.Width, 1, A.Depth), Vector3.new(0, 0.5, 0), A.FloorColor, arena)
	floor.Material = Enum.Material.Wood

	part("CenterLine", Vector3.new(A.Width, 0.05, 0.6), Vector3.new(0, 1.03, 0), A.LineColor, arena).CanCollide = false
	local circle = part("CenterCircle", Vector3.new(14, 0.05, 14), Vector3.new(0, 1.02, 0), A.LineColor, arena)
	circle.Shape = Enum.PartType.Cylinder
	circle.Orientation = Vector3.new(0, 0, 90)
	circle.CanCollide = false

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
		wall.Transparency = 0.55
		wall.Reflectance = 0.08
		table.insert(walls, { part = wall, basePos = spec[3], baseSize = spec[2] })
	end

	local ceiling = part("Ceiling", Vector3.new(A.Width + t * 2, 1, A.Depth + t * 2),
		Vector3.new(0, A.CeilingHeight, 0), A.WallColor, arena)
	ceiling.Transparency = 1

	for team = 1, 2 do
		local folder = Instance.new("Folder")
		folder.Name = "Team" .. team .. "Spawns"
		folder.Parent = arena
		local z = if team == 1 then -(halfD - 8) else (halfD - 8)
		for i = -1, 1 do
			marker("Spawn" .. (i + 2), Vector3.new(i * 10, 2, z), folder)
		end

		local benchX = if team == 1 then -(halfW + 9) else (halfW + 9)
		local bench = part("BenchPlatform" .. team, Vector3.new(14, 1, 24),
			Vector3.new(benchX, 2, 0), A.BenchColor, arena)
		bench.Material = Enum.Material.Concrete
		marker("Bench" .. team, Vector3.new(benchX, 3.5, 0), arena)
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

	print("[Arena] Спортзал построен: " .. A.Width .. "x" .. A.Depth .. ", стены и потолок на месте")
end

local function adoptExisting(arena: Instance)
	for _, child in ipairs(arena:GetChildren()) do
		if child:IsA("BasePart") and string.find(child.Name, "^Wall") then
			table.insert(walls, { part = child, basePos = child.Position, baseSize = child.Size })
		end
	end
	print("[Arena] Найдена своя Arena, использую её. Стен для sudden death: " .. #walls)
end

function ArenaService.Init()
	Collision.Setup()
	local existing = workspace:FindFirstChild("Arena")
	if existing then
		adoptExisting(existing)
	else
		build()
	end
end

function ArenaService.Start()
	RoundService.StateChanged.Event:Connect(function(state)
		shrinking = (state == "SuddenDeath")
	end)

	RunService.Heartbeat:Connect(function(dt)
		if #walls == 0 then return end
		local target = if shrinking then 1 else 0
		if math.abs(shrinkAlpha - target) < 0.001 then return end

		local step = dt / math.max(CFG.Arena.ShrinkTime, 0.05)
		shrinkAlpha = if shrinking
			then math.min(1, shrinkAlpha + step)
			else math.max(0, shrinkAlpha - step)

		local scale = 1 - (1 - CFG.Arena.ShrinkScale) * shrinkAlpha
		local color = CFG.Arena.WallColor:Lerp(CFG.Arena.SuddenColor, shrinkAlpha)

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

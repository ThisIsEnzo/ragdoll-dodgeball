-- CourtBarrier: the halfway line is a wall, not a rubber band.
--
-- The old rule applied a backward velocity twelve times a second, so walking
-- toward the centre felt like being shoved. This replaces it with a physical
-- barrier in its own collision group: players and bots stop against it,
-- balls pass straight through.
--
-- The barrier is solid only during Live and SuddenDeath. Between rounds it
-- opens so spawns, benches and revives can move bodies freely.

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")

local GROUP = "CentreBarrier"

local function ensureGroup(name)
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	return ok
end

ensureGroup(GROUP)

local function pair(other, collidable)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GROUP, other, collidable)
	end)
end

-- Players and anything untagged are stopped. Balls fly through.
pair("Players", true)
pair("Default", true)
pair("Balls", false)
pair("HeldBalls", false)
pair("Arena", false)
pair(GROUP, false)

local barrier = Workspace:FindFirstChild("CentreBarrier")
if barrier then barrier:Destroy() end

barrier = Instance.new("Part")
barrier.Name = "CentreBarrier"
barrier.Anchored = true
barrier.Size = Vector3.new(CFG.Arena.Width + 8, 26, 0.6)
barrier.CFrame = CFrame.new(0, 13, 0)
barrier.Transparency = 1
barrier.CanCollide = false
barrier.CanTouch = false
barrier.CanQuery = false
barrier.CastShadow = false
barrier.CollisionGroup = GROUP
barrier.Parent = Workspace

-- A readable line on the floor so the boundary is visible, not a surprise.
local marker = Instance.new("Part")
marker.Name = "CentreLine"
marker.Anchored = true
marker.Size = Vector3.new(CFG.Arena.Width - 2, 0.06, 0.7)
marker.CFrame = CFrame.new(0, 1.12, 0)
marker.Color = Color3.fromRGB(255, 255, 255)
marker.Material = Enum.Material.SmoothPlastic
marker.CanCollide = false
marker.CanTouch = false
marker.CanQuery = false
marker.CastShadow = false
marker.Parent = barrier

local function isLive()
	local state = RoundService.State
	return state == "Live" or state == "SuddenDeath"
end

local function sync()
	local solid = isLive()
	if barrier.CanCollide ~= solid then
		barrier.CanCollide = solid
	end
	marker.Transparency = if solid then 0.25 else 0.75
end

RoundService.StateChanged.Event:Connect(sync)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then return end
	accumulator = 0
	sync()
end)

sync()
print("[Barrier] halfway line is solid for players, open for balls")
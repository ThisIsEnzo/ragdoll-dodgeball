-- CourtBarrier: solid for players, open for balls.
--
-- Previous failure: this script ran before Bootstrap, so Collision.Setup had
-- not registered Balls / HeldBalls yet. Every CollisionGroupSetCollidable call
-- failed inside pcall and an unregistered pair defaults to COLLIDABLE, which
-- made the wall stop the ball too.
--
-- Now the collision module is initialised here first, every group is registered
-- explicitly, pairings are re-asserted for a few seconds, and the actual
-- collidability is printed so it can be verified instead of assumed.

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Collision = require(Shared:WaitForChild("Collision"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")

-- Make sure the shared groups exist before any pairing is attempted.
pcall(function() Collision.Setup() end)

local GROUPS = { "Players", "Balls", "HeldBalls", "Arena", "CentreBarrier" }
for _, name in ipairs(GROUPS) do
	pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
end

local PASS = { Balls = false, HeldBalls = false, Arena = false, CentreBarrier = false }
local BLOCK = { Players = true, Default = true }

local function assertPairs()
	for name, collidable in pairs(PASS) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable("CentreBarrier", name, collidable)
		end)
	end
	for name, collidable in pairs(BLOCK) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable("CentreBarrier", name, collidable)
		end)
	end
end

assertPairs()

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
barrier.CollisionGroup = "CentreBarrier"
barrier.Parent = Workspace

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
	if barrier.CanCollide ~= solid then barrier.CanCollide = solid end
	marker.Transparency = if solid then 0.25 else 0.75
end

RoundService.StateChanged.Event:Connect(sync)

-- Re-assert for the first few seconds: Collision.Setup may run again from
-- another service and reset the matrix.
task.spawn(function()
	for _ = 1, 12 do
		assertPairs()
		task.wait(0.5)
	end

	local function report(a, b)
		local ok, value = pcall(function()
			return PhysicsService:CollisionGroupsAreCollidable(a, b)
		end)
		if ok then return tostring(value) end
		return "unknown"
	end

	print("[Barrier] CentreBarrier vs Balls = " .. report("CentreBarrier", "Balls") .. " (want false)")
	print("[Barrier] CentreBarrier vs Players = " .. report("CentreBarrier", "Players") .. " (want true)")
	print("[Barrier] CentreBarrier vs Default = " .. report("CentreBarrier", "Default") .. " (want true)")
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.5 then return end
	accumulator = 0
	assertPairs()
	sync()
end)

sync()
print("[Barrier] centre wall up, ball pass-through asserted")
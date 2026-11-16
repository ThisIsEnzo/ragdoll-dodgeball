-- PERF SETUP: вставь в Command Bar в режиме EDIT (не Play).
-- Применяет бюджет производительности к Workspace и Lighting, выключает тени у арены.
-- Идемпотентно: можно запускать повторно.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
if not Shared then
	warn("[PerfSetup] ReplicatedStorage.Shared not found. Sync the project first.")
	return
end
local CFG = require(Shared:WaitForChild("BalanceConfig"))

local changed = 0

local function set(object, property, value)
	if object[property] ~= value then
		object[property] = value
		changed += 1
	end
end

set(Workspace, "StreamingEnabled", true)
set(Workspace, "StreamingMinRadius", CFG.Perf.StreamingMinRadius)
set(Workspace, "StreamingTargetRadius", CFG.Perf.StreamingTargetRadius)
set(Workspace, "StreamingIntegrityMode", Enum.StreamingIntegrityMode.MinimumRadiusPause)
set(Workspace, "PhysicsSimulationBudget", 0)

set(Lighting, "GlobalShadows", CFG.Perf.ShadowCasters)
set(Lighting, "Technology", Enum.Technology.Compatibility)
set(Lighting, "EnvironmentDiffuseScale", 0.35)
set(Lighting, "EnvironmentSpecularScale", 0.2)

local arena = Workspace:FindFirstChild("Arena")
local shadowOff, parts = 0, 0
if arena then
	for _, descendant in ipairs(arena:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts += 1
			if descendant.CastShadow then
				descendant.CastShadow = false
				shadowOff += 1
			end
			if not descendant.Anchored then
				descendant.Anchored = true
			end
		end
	end
end

for _, light in ipairs(Lighting:GetDescendants()) do
	if light:IsA("PostEffect") and light.Name ~= "RDImpactCorrection" then
		light.Enabled = false
	end
end

print("=====================================================")
print("  PERF SETUP APPLIED")
print(string.format("  properties changed: %d", changed))
print(string.format("  streaming: %s  min %d  target %d",
	tostring(Workspace.StreamingEnabled), Workspace.StreamingMinRadius, Workspace.StreamingTargetRadius))
print(string.format("  global shadows: %s", tostring(Lighting.GlobalShadows)))
print(string.format("  arena parts: %d   shadows disabled on: %d", parts, shadowOff))
if parts > CFG.Perf.MaxArenaParts then
	warn(string.format("  Arena exceeds budget: %d > %d parts", parts, CFG.Perf.MaxArenaParts))
else
	print("  arena part budget: OK")
end
print("  Save the place now so these settings persist.")
print("=====================================================")

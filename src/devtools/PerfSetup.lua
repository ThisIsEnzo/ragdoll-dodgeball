-- PerfSetup: применяет бюджет производительности. Запускать в EDIT mode, потом сохранить place.
-- Идемпотентно.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfSetup = {}

function PerfSetup.Run()
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if not Shared then
		warn("[PerfSetup] ReplicatedStorage.Shared not found. Sync the project first.")
		return nil
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

	set(Lighting, "GlobalShadows", CFG.Perf.ShadowCasters)
	set(Lighting, "Technology", Enum.Technology.Compatibility)
	set(Lighting, "EnvironmentDiffuseScale", 0.35)
	set(Lighting, "EnvironmentSpecularScale", 0.2)

	local arena = Workspace:FindFirstChild("Arena")
	local parts, shadowOff, anchored = 0, 0, 0
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
					anchored += 1
				end
			end
		end
	end

	print("=====================================================")
	print("  PERF SETUP APPLIED")
	print(string.format("  properties changed   %d", changed))
	print(string.format("  streaming            %s  min %d  target %d",
		tostring(Workspace.StreamingEnabled), Workspace.StreamingMinRadius, Workspace.StreamingTargetRadius))
	print(string.format("  global shadows       %s", tostring(Lighting.GlobalShadows)))
	print(string.format("  arena parts          %d", parts))
	print(string.format("  shadows disabled on  %d", shadowOff))
	print(string.format("  parts anchored       %d", anchored))
	if parts > CFG.Perf.MaxArenaParts then
		warn(string.format("  Arena over budget: %d > %d parts", parts, CFG.Perf.MaxArenaParts))
	else
		print("  arena part budget    OK")
	end
	print("  SAVE THE PLACE NOW so these settings persist.")
	print("=====================================================")

	return { changed = changed, parts = parts, shadowOff = shadowOff }
end

return PerfSetup

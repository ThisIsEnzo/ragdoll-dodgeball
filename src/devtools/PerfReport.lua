-- PerfReport: соблюдение бюджета. Запускать в PLAY mode, Server context.
-- FPS меряется отдельной строкой в Client context, здесь его не будет.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfReport = {}

local function countParts(root)
	local total, unanchored, shadowing = 0, 0, 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			total += 1
			if not descendant.Anchored then unanchored += 1 end
			if descendant.CastShadow then shadowing += 1 end
		end
	end
	return total, unanchored, shadowing
end

function PerfReport.Run()
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if not Shared then
		warn("[PerfReport] ReplicatedStorage.Shared not found.")
		return nil
	end
	local CFG = require(Shared:WaitForChild("BalanceConfig"))
	local Resolve = require(Shared:WaitForChild("Resolve"))

	local arena = Workspace:FindFirstChild("Arena")
	local arenaParts, arenaUnanchored, arenaShadows = 0, 0, 0
	if arena then arenaParts, arenaUnanchored, arenaShadows = countParts(arena) end
	local worldParts = countParts(Workspace)

	local instances, balls, lights = 0, 0, 0
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		instances += 1
		if descendant:IsA("BasePart") and descendant.Name == "Ball" then balls += 1 end
		if descendant:IsA("Light") then lights += 1 end
	end

	local activeRagdolls = 0
	local ok, RagdollService = pcall(function()
		return Resolve.Require(ServerScriptService, "RagdollService", 2)
	end)
	if ok and RagdollService and RagdollService.ActiveCount then
		activeRagdolls = RagdollService.ActiveCount()
	end

	local ping = nil
	local okPing, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if okPing then ping = value end

	print("=====================================================")
	print("  PERF REPORT")
	print("=====================================================")
	print(string.format("  arena parts        %d / %d  %s", arenaParts, CFG.Perf.MaxArenaParts,
		if arenaParts <= CFG.Perf.MaxArenaParts then "OK" else "OVER BUDGET"))
	print(string.format("  arena unanchored   %d  %s", arenaUnanchored,
		if arenaUnanchored == 0 then "OK" else "should be 0"))
	print(string.format("  arena shadow cast  %d  %s", arenaShadows,
		if arenaShadows == 0 then "OK" else "run PerfSetup"))
	print(string.format("  world parts        %d", worldParts))
	print(string.format("  world instances    %d", instances))
	print(string.format("  balls in play      %d", balls))
	print(string.format("  active ragdolls    %d / %d  %s", activeRagdolls, CFG.Round.MaxActiveRagdolls,
		if activeRagdolls <= CFG.Round.MaxActiveRagdolls then "OK" else "OVER"))
	print(string.format("  dynamic lights     %d", lights))
	print(string.format("  streaming          %s  min %d  target %d",
		tostring(Workspace.StreamingEnabled), Workspace.StreamingMinRadius, Workspace.StreamingTargetRadius))
	print(string.format("  global shadows     %s", tostring(Lighting.GlobalShadows)))
	if ping then print(string.format("  ping               %.0f ms", ping)) end
	if RunService:IsClient() then
		local frames, elapsed = 0, 0
		local connection = RunService.RenderStepped:Connect(function(dt)
			frames += 1
			elapsed += dt
		end)
		task.wait(1.2)
		connection:Disconnect()
		if elapsed > 0 then
			local fps = frames / elapsed
			print(string.format("  client FPS         %.1f  target %d  min %d  %s",
				fps, CFG.Perf.TargetFps, CFG.Perf.MinFps,
				if fps >= CFG.Perf.TargetFps then "OK"
				elseif fps >= CFG.Perf.MinFps then "ACCEPTABLE" else "FAIL"))
		end
	else
		print("  client FPS         switch Command Bar to Client and run the FPS probe")
	end
	print("=====================================================")

	return { arenaParts = arenaParts, ragdolls = activeRagdolls, lights = lights }
end

return PerfReport

-- FunnelReport: воронка FTUE. Запускать в PLAY mode, Server context, после матча.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FunnelReport = {}

local function median(list)
	if #list == 0 then return nil end
	table.sort(list)
	local mid = math.floor(#list / 2) + 1
	if #list % 2 == 1 then return list[mid] end
	return (list[mid - 1] + list[mid]) / 2
end

function FunnelReport.Run()
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if not Shared then
		warn("[FunnelReport] ReplicatedStorage.Shared not found. Start Play first.")
		return nil
	end
	local Resolve = require(Shared:WaitForChild("Resolve"))

	local ok, Analytics = pcall(function()
		return Resolve.Require(ServerScriptService, "AnalyticsService", 3)
	end)
	if not ok or not Analytics then
		warn("[FunnelReport] AnalyticsService not found. Is the server running?")
		return nil
	end

	local records = Analytics.GetRecords()
	local live = Analytics.GetLiveSessions()
	local order = Analytics.StepOrder()

	local liveCount = 0
	for _ in pairs(live) do liveCount += 1 end

	print("=====================================================")
	print("  FTUE FUNNEL REPORT")
	print(string.format("  completed sessions: %d   live: %d", #records, liveCount))
	print("=====================================================")

	if #records == 0 and liveCount == 0 then
		print("  No data yet. Play a match, leave, then run again.")
		return nil
	end

	local total = #records
	print("  STEP                REACHED   CONV     MEDIAN")
	print("  ---------------------------------------------------")

	local previousReached = total
	for _, step in ipairs(order) do
		local reached, times = 0, {}
		for _, record in ipairs(records) do
			local value = record.steps[step]
			if typeof(value) == "number" then
				reached += 1
				table.insert(times, value)
			end
		end
		local conv = if total > 0 then (reached / total * 100) else 0
		local stepConv = if previousReached > 0 then (reached / previousReached * 100) else 0
		local med = median(times)

		print(string.format("  %-18s  %5d    %5.1f%%   %s", step, reached, conv,
			if med then string.format("%.1fs", med) else "-"))
		if previousReached > 0 and reached < previousReached and stepConv < 70 then
			print(string.format("      ^ DROP-OFF: %.1f%% of previous step", stepConv))
		end
		previousReached = reached
	end

	print("")
	print("  LAST STEP REACHED")
	local byLast = {}
	for _, record in ipairs(records) do
		byLast[record.lastStep] = (byLast[record.lastStep] or 0) + 1
	end
	for step, count in pairs(byLast) do
		print(string.format("    %-18s %d", step, count))
	end

	local durations = {}
	for _, record in ipairs(records) do table.insert(durations, record.duration) end
	local medDuration = median(durations)
	print("")
	print(string.format("  median session      %s",
		if medDuration then string.format("%.0fs", medDuration) else "-"))

	local short = 0
	for _, d in ipairs(durations) do if d < 60 then short += 1 end end
	if total > 0 then
		print(string.format("  under 60s           %d / %d (%.0f%%)", short, total, short / total * 100))
	end

	print("=====================================================")
	print("  Targets: first_throw <= 8s, match_done >= 70%")
	print("=====================================================")

	return { sessions = total, live = liveCount }
end

return FunnelReport

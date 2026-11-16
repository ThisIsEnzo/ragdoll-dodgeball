-- FunnelReport v0.7.3: воронка FTUE по завершённым И живым сессиям.
-- Запускать в PLAY mode, Server context:
--   require(game.ServerStorage.DevTools.FunnelReport).Run()
--
-- Зачем живые сессии: в соло-Play остановка Play убивает серверный процесс вместе
-- с записями, и отчёт всегда показывал "No data yet". Теперь незавершённые сессии
-- участвуют в конверсии с пометкой LIVE, а отдельный блок показывает точку залипания.

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

local function lastStepOf(steps, order)
	local bestIndex, bestName = 0, "none"
	for index, name in ipairs(order) do
		if typeof(steps[name]) == "number" and index > bestIndex then
			bestIndex, bestName = index, name
		end
	end
	return bestName
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

	local order = Analytics.StepOrder()
	local completed = Analytics.GetRecords()
	local liveMap = Analytics.GetLiveSessions()

	-- Собираем единый список: завершённые как есть, живые приводим к той же форме
	local rows = {}
	for _, record in ipairs(completed) do
		table.insert(rows, {
			name = record.name,
			steps = record.steps,
			duration = record.duration,
			device = record.device,
			lastStep = record.lastStep,
			live = false,
		})
	end

	local liveRows = {}
	for _, session in pairs(liveMap) do
		local row = {
			name = session.name,
			steps = session.steps,
			duration = os.clock() - session.startedAt,
			device = session.device,
			lastStep = lastStepOf(session.steps, order),
			live = true,
		}
		table.insert(rows, row)
		table.insert(liveRows, row)
	end

	local total = #rows
	local liveCount = #liveRows

	print("=====================================================")
	print("  FTUE FUNNEL REPORT")
	print(string.format("  sessions: %d total   %d completed   %d LIVE",
		total, total - liveCount, liveCount))
	print("=====================================================")

	if total == 0 then
		print("  No sessions at all. Press Play and spawn into the arena first.")
		return nil
	end

	print("  STEP                REACHED   CONV     MEDIAN")
	print("  ---------------------------------------------------")

	local previousReached = total
	for _, step in ipairs(order) do
		local reached, times = 0, {}
		for _, row in ipairs(rows) do
			local value = row.steps[step]
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

	if liveCount > 0 then
		print("")
		print("  LIVE SESSIONS (in progress, not drop-offs yet)")
		for _, row in ipairs(liveRows) do
			local nextStep = "complete"
			for _, name in ipairs(order) do
				if typeof(row.steps[name]) ~= "number" then
					nextStep = name
					break
				end
			end
			print(string.format("    %-16s %5.0fs  stuck before: %s",
				row.name, row.duration, nextStep))
		end
		print("  Conversion above includes these; it will move as they progress.")
	end

	print("")
	print("  LAST STEP REACHED")
	local byLast = {}
	for _, row in ipairs(rows) do
		byLast[row.lastStep] = (byLast[row.lastStep] or 0) + 1
	end
	for step, count in pairs(byLast) do
		print(string.format("    %-18s %d", step, count))
	end

	local durations = {}
	for _, row in ipairs(rows) do table.insert(durations, row.duration) end
	local medDuration = median(durations)

	print("")
	print(string.format("  median session      %s",
		if medDuration then string.format("%.0fs", medDuration) else "-"))

	local short, shortTotal = 0, 0
	for _, row in ipairs(rows) do
		if not row.live then
			shortTotal += 1
			if row.duration < 60 then short += 1 end
		end
	end
	if shortTotal > 0 then
		print(string.format("  under 60s (closed)  %d / %d (%.0f%%)",
			short, shortTotal, short / shortTotal * 100))
	else
		print("  under 60s           no closed sessions yet, bounce proxy unavailable")
	end

	print("")
	print("  DEVICE SPLIT")
	local byDevice = {}
	for _, row in ipairs(rows) do
		byDevice[row.device] = (byDevice[row.device] or 0) + 1
	end
	for device, count in pairs(byDevice) do
		print(string.format("    %-10s %d", device, count))
	end

	print("=====================================================")
	print("  Targets: first_throw <= 8s, match_done >= 70%")
	print("  Bounce proxy only counts closed sessions.")
	print("=====================================================")

	return { total = total, live = liveCount, completed = total - liveCount }
end

return FunnelReport

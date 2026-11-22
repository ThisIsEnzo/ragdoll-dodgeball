-- PerfProbe: lightweight client frame-time and scene-cost diagnostic.
--
-- Run on a real published Roblox client for device performance. Studio device
-- emulation changes viewport/input, not the rendering hardware.
-- F7 toggles the panel; DUMP prints a report; RESET starts a fresh sample window.
--
-- Frame-time percentiles are client RenderStepped deltas. 1 / p95 is the
-- 5%-low FPS equivalent (not a true 1%-low metric). Scene counts are suspects,
-- not proof of rendering cost. Heavy scene/memory scans are throttled.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local PROBE_NAME = "RDPerfProbe"
local SAMPLE_CAP = 1800
local SCENE_SCAN_SECONDS = 5
local UI_REFRESH_SECONDS = 1

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE2 = Color3.fromRGB(26, 35, 66)
local TEXT = Color3.fromRGB(234, 240, 255)
local LIME = Color3.fromRGB(150, 255, 60)
local AMBER = Color3.fromRGB(255, 190, 0)
local RED = Color3.fromRGB(255, 58, 58)
local CYAN = Color3.fromRGB(0, 226, 255)

local samples = {}
local windowStart = os.clock()
local worstFrame = 0
local cachedSceneCost = {}
local cachedMemory = {}
local lastSceneScan = 0
local lastData = nil

local gui = Instance.new("ScreenGui")
gui.Name = PROBE_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 99
gui.Parent = playerGui

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local panel = make("Frame", {
	Size = UDim2.fromOffset(276, 176),
	Position = UDim2.new(0, 12, 0, 116),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 11) }, panel)
local panelStroke = make("UIStroke", { Color = LIME, Thickness = 1.5, Transparency = 0.4 }, panel)

make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 18),
	Position = UDim2.fromOffset(8, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	TextColor3 = CYAN,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "PERF PROBE  F7",
}, panel)

local readout = make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 96),
	Position = UDim2.fromOffset(8, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 11,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "collecting...",
}, panel)

local graph = make("Frame", {
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.fromOffset(8, 124),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BorderSizePixel = 0,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 5) }, graph)

local bars = {}
for index = 1, 48 do
	bars[index] = make("Frame", {
		Size = UDim2.fromOffset(4, 2),
		Position = UDim2.new(0, (index - 1) * 5 + 2, 1, -2),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = LIME,
		BorderSizePixel = 0,
	}, graph)
end

local dumpButton = make("TextButton", {
	Size = UDim2.fromOffset(126, 22),
	Position = UDim2.fromOffset(8, 152),
	BackgroundColor3 = LIME,
	TextColor3 = Color3.fromRGB(10, 28, 6),
	Font = Enum.Font.FredokaOne,
	TextSize = 11,
	Text = "DUMP",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, dumpButton)

local resetButton = make("TextButton", {
	Size = UDim2.fromOffset(126, 22),
	Position = UDim2.fromOffset(142, 152),
	BackgroundColor3 = SURFACE2,
	TextColor3 = TEXT,
	Font = Enum.Font.FredokaOne,
	TextSize = 11,
	Text = "RESET WINDOW",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, resetButton)

local function percentile(sorted, fraction)
	if #sorted == 0 then return 0 end
	local index = math.clamp(math.ceil(#sorted * fraction), 1, #sorted)
	return sorted[index]
end

local function scanScene()
	local result = {
		parts = 0, shadowCasters = 0, neon = 0, emitters = 0,
		trails = 0, lights = 0, decals = 0, balls = 0, actors = 0,
	}

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("BasePart") then
			result.parts += 1
			if descendant.CastShadow then result.shadowCasters += 1 end
			if descendant.Material == Enum.Material.Neon then result.neon += 1 end
		elseif descendant:IsA("ParticleEmitter") then
			if descendant.Enabled then result.emitters += 1 end
		elseif descendant:IsA("Trail") then
			if descendant.Enabled then result.trails += 1 end
		elseif descendant:IsA("Light") then
			if descendant.Enabled then result.lights += 1 end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			result.decals += 1
		end
	end

	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace) then result.balls += 1 end
	end
	for _, actor in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if actor:IsA("Model") and actor:IsDescendantOf(workspace) then result.actors += 1 end
	end
	return result
end

local function readMemory()
	local rows = {}
	local ok, total = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if ok and type(total) == "number" then
		table.insert(rows, { name = "TOTAL", mb = total })
	end

	local placeMem = Stats:FindFirstChild("PlaceMem")
	if placeMem then
		for _, child in ipairs(placeMem:GetChildren()) do
			if child:IsA("NumberValue") then
				table.insert(rows, { name = child.Name, mb = child.Value })
			end
		end
	end
	table.sort(rows, function(a, b) return a.mb > b.mb end)
	return rows
end

local function pingMs()
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(value) == "number" then return value end
	return nil
end

local function collectData()
	local sorted = table.clone(samples)
	table.sort(sorted)
	local p50 = percentile(sorted, 0.50)
	local p95 = percentile(sorted, 0.95)
	local p99 = percentile(sorted, 0.99)
	local mean = 0
	for _, value in ipairs(sorted) do mean += value end
	if #sorted > 0 then mean /= #sorted end

	local fpsMedian = if p50 > 0 then 1 / p50 else 0
	local fpsP95Equivalent = if p95 > 0 then 1 / p95 else 0
	local floorFps = CFG.Perf.MinFps
	local targetFps = CFG.Perf.TargetFps
	local verdict = "PASS"
	if fpsMedian < targetFps * 0.7 then
		verdict = "MARGINAL"
	end
	if fpsP95Equivalent < floorFps then
		verdict = "FAIL"
	end

	return {
		p50 = p50, p95 = p95, p99 = p99, mean = mean,
		fpsMedian = fpsMedian, fpsP95Equivalent = fpsP95Equivalent,
		worst = worstFrame, samples = #sorted,
		seconds = os.clock() - windowStart,
		cost = cachedSceneCost, memory = cachedMemory,
		ping = pingMs(), verdict = verdict,
		floorFps = floorFps, targetFps = targetFps,
	}
end

local function refresh()
	local data = collectData()
	lastData = data
	local color = LIME
	if data.verdict == "MARGINAL" then color = AMBER end
	if data.verdict == "FAIL" then color = RED end
	panelStroke.Color = color

	local topMem = "memory n/a"
	if #data.memory > 0 then
		topMem = string.format("%s %.0fMB", data.memory[1].name, data.memory[1].mb)
	end
	local ping = if data.ping then string.format("%.0fms", data.ping) else "n/a"

	readout.Text = string.format(
		"%s  %d frames / %.0fs\nmedian %.0f fps  p95-eq %.0f fps\nframe p50 %.1f  p95 %.1f  p99 %.1fms\nparts %d  shadows %d  emit %d  trails %d\nlights %d  balls %d  actors %d\nping %s  %s",
		data.verdict, data.samples, data.seconds,
		data.fpsMedian, data.fpsP95Equivalent,
		data.p50 * 1000, data.p95 * 1000, data.p99 * 1000,
		data.cost.parts, data.cost.shadowCasters, data.cost.emitters, data.cost.trails,
		data.cost.lights, data.cost.balls, data.cost.actors, ping, topMem
	)
	readout.TextColor3 = color

	local count = #samples
	for index, bar in ipairs(bars) do
		local sourceIndex = count - (#bars - index)
		if sourceIndex >= 1 and sourceIndex <= count then
			local dt = samples[sourceIndex]
			bar.Size = UDim2.fromOffset(4, math.clamp(dt / 0.05, 0.04, 1) * 24)
			bar.BackgroundColor3 = if dt > 1/20 then RED elseif dt > 1/30 then AMBER else LIME
			bar.Visible = true
		else
			bar.Visible = false
		end
	end
end

local function dump()
	local data = collectData()
	print("==== PERF PROBE ====")
	print(string.format("window %.1fs, %d frames, verdict %s (MinFps=%d, TargetFps=%d)",
		data.seconds, data.samples, data.verdict, data.floorFps, data.targetFps))
	print(string.format("fps median %.1f, p95-frame-time equivalent %.1f (NOT 1%% low)",
		data.fpsMedian, data.fpsP95Equivalent))
	print(string.format("frame ms mean %.2f, p50 %.2f, p95 %.2f, p99 %.2f, max %.2f",
		data.mean * 1000, data.p50 * 1000, data.p95 * 1000, data.p99 * 1000, data.worst * 1000))
	print(string.format("scene parts=%d shadowCasters=%d neon=%d emitters=%d trails=%d lights=%d decals=%d",
		data.cost.parts, data.cost.shadowCasters, data.cost.neon,
		data.cost.emitters, data.cost.trails, data.cost.lights, data.cost.decals))
	print(string.format("actors=%d balls=%d ping=%s",
		data.cost.actors, data.cost.balls, data.ping and string.format("%.0fms", data.ping) or "n/a"))
	for _, row in ipairs(data.memory) do
		print(string.format("mem %s = %.1f MB", row.name, row.mb))
	end
	if data.verdict == "FAIL" then
		warn("[PerfProbe] frame-time threshold is below the configured 30 FPS floor.")
		warn("[PerfProbe] Scene counts are investigation leads, not causal attribution.")
	end
	print("==== END PERF ====")
end

dumpButton.Activated:Connect(dump)
resetButton.Activated:Connect(function()
	table.clear(samples)
	worstFrame = 0
	windowStart = os.clock()
	refresh()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F7 then
		panel.Visible = not panel.Visible
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if dt <= 0 then return end
	table.insert(samples, dt)
	if dt > worstFrame then worstFrame = dt end
	if #samples > SAMPLE_CAP then table.remove(samples, 1) end
end)

local uiElapsed = 0
local sceneElapsed = 0
RunService.Heartbeat:Connect(function(dt)
	uiElapsed += dt
	sceneElapsed += dt
	if sceneElapsed >= SCENE_SCAN_SECONDS then
		sceneElapsed = 0
		cachedSceneCost = scanScene()
		cachedMemory = readMemory()
	end
	if uiElapsed >= UI_REFRESH_SECONDS then
		uiElapsed = 0
		if panel.Visible then refresh() end
	end
end)

task.delay(SCENE_SCAN_SECONDS, function()
	cachedSceneCost = scanScene()
	cachedMemory = readMemory()
end)
task.delay(12, dump)

print("[PerfProbe] ready: F7 panel; DUMP for report")

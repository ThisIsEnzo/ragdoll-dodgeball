-- GraphicsLab: fixes the blown-out render and lets you tune it live.
--
-- The screenshot showed a white-hot court: large Neon surfaces plus a low
-- bloom threshold plus ten 3.2-brightness spots turned every accent into a
-- light source that ate the floor. The SAFE preset loads automatically and
-- resolves it; the panel exists so the look can be dialled in without another
-- round of guesswork.
--
-- All writes are client-local. EXPORT prints a block you can paste into
-- WorldService to make the chosen look permanent for everyone.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local INK      = Color3.fromRGB(8, 12, 26)
local SURFACE  = Color3.fromRGB(18, 25, 48)
local SURFACE2 = Color3.fromRGB(26, 35, 66)
local LINE     = Color3.fromRGB(48, 62, 104)
local TEXT     = Color3.fromRGB(234, 240, 255)
local DIM      = Color3.fromRGB(158, 174, 210)
local LIME     = Color3.fromRGB(150, 255, 60)
local CYAN     = Color3.fromRGB(0, 226, 255)
local AMBER    = Color3.fromRGB(255, 190, 0)
local RED      = Color3.fromRGB(255, 58, 58)

-- ---------------------------------------------------------------------------
-- Parameter model
-- ---------------------------------------------------------------------------

local PARAMS = {
	{ key = "exposure",   label = "EXPOSURE",       min = 0.4, max = 3.0, step = 0.05 },
	{ key = "ambient",    label = "AMBIENT",        min = 0,   max = 160, step = 2 },
	{ key = "bloom",      label = "BLOOM",          min = 0,   max = 1.2, step = 0.02 },
	{ key = "threshold",  label = "BLOOM THRESHOLD",min = 0.8, max = 3.0, step = 0.05 },
	{ key = "neon",       label = "NEON TAMING",    min = 0,   max = 1.0, step = 0.02 },
	{ key = "spot",       label = "SPOT POWER",     min = 0,   max = 4.0, step = 0.1 },
	{ key = "range",      label = "SPOT REACH",     min = 20,  max = 80,  step = 1 },
	{ key = "saturation", label = "SATURATION",     min = -0.4,max = 0.5, step = 0.02 },
	{ key = "contrast",   label = "CONTRAST",       min = -0.2,max = 0.5, step = 0.02 },
	{ key = "outline",    label = "OUTLINE ONLY",   min = 0,   max = 1,   step = 1 },
	{ key = "shadows",    label = "SHADOWS",        min = 0,   max = 1,   step = 1 },
	{ key = "crowd",      label = "CROWD",          min = 0,   max = 1,   step = 1 },
}

local PRESETS = {
	SAFE = {
		exposure = 1.45, ambient = 74, bloom = 0.14, threshold = 2.35,
		neon = 0.18, spot = 1.1, range = 44, saturation = 0.1, contrast = 0.14,
		outline = 1, shadows = 1, crowd = 1,
	},
	CINEMATIC = {
		exposure = 1.25, ambient = 52, bloom = 0.3, threshold = 2.0,
		neon = 0.34, spot = 1.6, range = 52, saturation = 0.18, contrast = 0.24,
		outline = 1, shadows = 1, crowd = 1,
	},
	BRIGHT = {
		exposure = 1.9, ambient = 104, bloom = 0.1, threshold = 2.6,
		neon = 0.12, spot = 0.8, range = 40, saturation = 0.14, contrast = 0.08,
		outline = 1, shadows = 1, crowd = 1,
	},
	MOBILE = {
		exposure = 1.6, ambient = 92, bloom = 0, threshold = 3.0,
		neon = 0.08, spot = 0.6, range = 36, saturation = 0.12, contrast = 0.1,
		outline = 1, shadows = 0, crowd = 0,
	},
}

local values = {}
for key, value in pairs(PRESETS.SAFE) do values[key] = value end

-- ---------------------------------------------------------------------------
-- Applying values
-- ---------------------------------------------------------------------------

local neonRegistry = {}
local spotRegistry = {}
local highlightRegistry = {}
local crowdRegistry = {}

local function registerScene()
	table.clear(neonRegistry)
	table.clear(spotRegistry)
	table.clear(crowdRegistry)

	local decor = Workspace:FindFirstChild("WorldDecor")
	if decor then
		for _, item in ipairs(decor:GetDescendants()) do
			if item:IsA("BasePart") then
				if item.Material == Enum.Material.Neon then
					local s = item.Size
					local big = math.max(s.X, s.Y, s.Z) > 8
					table.insert(neonRegistry, { part = item, base = item.Color, big = big })
				end
				if item:IsDescendantOf(decor:FindFirstChild("Crowd") or decor) and item.Parent and item.Parent.Name == "Crowd" then
					table.insert(crowdRegistry, item)
				end
			elseif item:IsA("SpotLight") or item:IsA("PointLight") then
				table.insert(spotRegistry, item)
			end
		end
		local crowdFolder = decor:FindFirstChild("Crowd")
		if crowdFolder then
			table.clear(crowdRegistry)
			for _, item in ipairs(crowdFolder:GetDescendants()) do
				if item:IsA("BasePart") then table.insert(crowdRegistry, item) end
			end
		end
	end

	table.clear(highlightRegistry)
	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("Highlight") then table.insert(highlightRegistry, item) end
	end
end

local function effect(class, name)
	local item = Lighting:FindFirstChild(name)
	if not item then
		item = Instance.new(class)
		item.Name = name
		item.Parent = Lighting
	end
	return item
end

local function apply()
	Lighting.Brightness = values.exposure
	local a = values.ambient
	Lighting.Ambient = Color3.fromRGB(a, a * 1.06, a * 1.3)
	Lighting.OutdoorAmbient = Color3.fromRGB(a * 1.15, a * 1.24, a * 1.5)
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.45
	Lighting.GlobalShadows = values.shadows > 0.5
	Lighting.ShadowSoftness = 0.35

	local bloom = effect("BloomEffect", "RDBloom")
	bloom.Intensity = values.bloom
	bloom.Threshold = values.threshold
	bloom.Size = 20

	local grade = effect("ColorCorrectionEffect", "RDGrade")
	grade.Saturation = values.saturation
	grade.Contrast = values.contrast
	grade.Brightness = 0
	grade.TintColor = Color3.fromRGB(255, 252, 248)

	local rays = Lighting:FindFirstChild("RDRays")
	if rays then rays.Intensity = values.bloom * 0.06 end

	local air = Lighting:FindFirstChild("RDAir")
	if air then
		air.Glare = values.bloom * 0.2
		air.Haze = 1.1
	end

	-- Large emissive slabs become lit plastic; only thin trim keeps glowing.
	local tame = values.neon
	for _, entry in ipairs(neonRegistry) do
		local part = entry.part
		if part.Parent then
			if entry.big or tame < 0.25 then
				part.Material = Enum.Material.SmoothPlastic
				part.Color = entry.base
			else
				part.Material = Enum.Material.Neon
				part.Color = entry.base:Lerp(Color3.new(0, 0, 0), 1 - tame)
			end
		end
	end

	for _, light in ipairs(spotRegistry) do
		if light.Parent then
			light.Brightness = values.spot
			light.Range = values.range
			light.Shadows = false
		end
	end

	for _, highlight in ipairs(highlightRegistry) do
		if highlight.Parent then
			if values.outline > 0.5 then
				highlight.FillTransparency = 1
				highlight.OutlineTransparency = 0
			else
				highlight.FillTransparency = 0.88
				highlight.OutlineTransparency = 0
			end
		end
	end

	for _, part in ipairs(crowdRegistry) do
		if part.Parent then
			part.LocalTransparencyModifier = if values.crowd > 0.5 then 0 else 1
		end
	end
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "RDGraphicsLab"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local toggle = make("TextButton", {
	Size = UDim2.fromOffset(96, 32),
	Position = UDim2.new(1, -16, 0, 212),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = AMBER,
	TextColor3 = Color3.fromRGB(28, 20, 0),
	Font = Enum.Font.FredokaOne,
	TextSize = 12,
	Text = "GRAPHICS",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, toggle)

local panel = make("Frame", {
	Size = UDim2.fromOffset(322, 560),
	Position = UDim2.new(1, -16, 0, 250),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
make("UIStroke", { Color = AMBER, Thickness = 2, Transparency = 0.35 }, panel)

make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 24),
	Position = UDim2.fromOffset(12, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 15,
	TextColor3 = AMBER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "GRAPHICS LAB",
}, panel)

local status = make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.fromOffset(12, 32),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = LIME,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "SAFE preset active â€” blowout corrected",
}, panel)

local presetRow = make("Frame", {
	Size = UDim2.new(1, -24, 0, 28),
	Position = UDim2.fromOffset(12, 52),
	BackgroundTransparency = 1,
}, panel)

local presetOrder = { "SAFE", "CINEMATIC", "BRIGHT", "MOBILE" }
local presetButtons = {}
for index, name in ipairs(presetOrder) do
	local button = make("TextButton", {
		Size = UDim2.fromOffset(71, 26),
		Position = UDim2.fromOffset((index - 1) * 75, 0),
		BackgroundColor3 = SURFACE2,
		TextColor3 = DIM,
		Font = Enum.Font.FredokaOne,
		TextSize = 10,
		Text = name,
		AutoButtonColor = false,
	}, presetRow)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, button)
	presetButtons[name] = button
end

local scroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -160),
	Position = UDim2.fromOffset(12, 88),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = AMBER,
	ScrollBarImageTransparency = 0.3,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

local readouts = {}
local dragging = nil

local function fmt(param, value)
	if param.step >= 1 then
		if param.max == 1 then
			if value > 0.5 then return "ON" end
			return "OFF"
		end
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.2f", value)
end

local function setValue(key, value, silent)
	local param
	for _, p in ipairs(PARAMS) do
		if p.key == key then param = p end
	end
	if not param then return end
	value = math.clamp(value, param.min, param.max)
	if param.step >= 1 then
		value = math.floor(value + 0.5)
	else
		value = math.floor(value / param.step + 0.5) * param.step
	end
	values[key] = value

	local ui = readouts[key]
	if ui then
		local alpha = (value - param.min) / (param.max - param.min)
		ui.fill.Size = UDim2.fromScale(alpha, 1)
		ui.knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		ui.readout.Text = fmt(param, value)
		if param.max == 1 and param.step >= 1 then
			local on = value > 0.5
			ui.fill.BackgroundColor3 = if on then LIME else LINE
			ui.readout.TextColor3 = if on then LIME else DIM
		end
	end

	if not silent then
		apply()
		status.Text = "custom â€” press EXPORT to bake"
		status.TextColor3 = AMBER
		for _, button in pairs(presetButtons) do
			button.BackgroundColor3 = SURFACE2
			button.TextColor3 = DIM
		end
	end
end

for index, param in ipairs(PARAMS) do
	local row = make("Frame", {
		Size = UDim2.new(1, -8, 0, 42),
		BackgroundColor3 = SURFACE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, scroll)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)

	make("TextLabel", {
		Size = UDim2.new(1, -60, 0, 14),
		Position = UDim2.fromOffset(9, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = param.label,
	}, row)

	local readout = make("TextLabel", {
		Size = UDim2.fromOffset(52, 14),
		Position = UDim2.new(1, -9, 0, 5),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 11,
		TextColor3 = CYAN,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	}, row)

	local track = make("Frame", {
		Size = UDim2.new(1, -18, 0, 7),
		Position = UDim2.fromOffset(9, 26),
		BackgroundColor3 = Color3.fromRGB(12, 18, 36),
		BorderSizePixel = 0,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = CYAN,
		BorderSizePixel = 0,
	}, track)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

	local knob = make("TextButton", {
		Size = UDim2.fromOffset(15, 15),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = TEXT,
		Text = "",
		AutoButtonColor = false,
	}, track)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	make("UIStroke", { Color = INK, Thickness = 1.5 }, knob)

	readouts[param.key] = { fill = fill, knob = knob, readout = readout, track = track }

	local function fromX(x)
		local abs = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		if width <= 0 then return end
		local alpha = math.clamp((x - abs) / width, 0, 1)
		setValue(param.key, param.min + alpha * (param.max - param.min))
	end

	local function begin(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = fromX
			fromX(input.Position.X)
		end
	end

	knob.InputBegan:Connect(begin)
	track.InputBegan:Connect(begin)
end

local function makeAction(label, x, width, color, textColor, callback)
	local button = make("TextButton", {
		Size = UDim2.fromOffset(width, 30),
		Position = UDim2.fromOffset(x, 0),
		BackgroundColor3 = color,
		TextColor3 = textColor,
		Font = Enum.Font.FredokaOne,
		TextSize = 11,
		Text = label,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
	button.Activated:Connect(callback)
	return button
end

local actionRow = make("Frame", {
	Size = UDim2.new(1, -24, 0, 30),
	Position = UDim2.new(0, 12, 1, -44),
	BackgroundTransparency = 1,
}, panel)

local function actionIn(parent, label, x, width, color, textColor, callback)
	local button = make("TextButton", {
		Size = UDim2.fromOffset(width, 30),
		Position = UDim2.fromOffset(x, 0),
		BackgroundColor3 = color,
		TextColor3 = textColor,
		Font = Enum.Font.FredokaOne,
		TextSize = 11,
		Text = label,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
	button.Activated:Connect(callback)
	return button
end

local function applyPreset(name)
	local preset = PRESETS[name]
	if not preset then return end
	for key, value in pairs(preset) do
		setValue(key, value, true)
	end
	apply()
	status.Text = name .. " preset active"
	status.TextColor3 = LIME
	for presetName, button in pairs(presetButtons) do
		if presetName == name then
			button.BackgroundColor3 = AMBER
			button.TextColor3 = Color3.fromRGB(28, 20, 0)
		else
			button.BackgroundColor3 = SURFACE2
			button.TextColor3 = DIM
		end
	end
end

for name, button in pairs(presetButtons) do
	button.Activated:Connect(function() applyPreset(name) end)
end

actionIn(actionRow, "RESET", 0, 92, SURFACE2, TEXT, function()
	applyPreset("SAFE")
end)

actionIn(actionRow, "RESCAN", 98, 92, SURFACE2, TEXT, function()
	registerScene()
	apply()
	status.Text = "scene rescanned"
	status.TextColor3 = CYAN
end)

actionIn(actionRow, "EXPORT", 196, 102, LIME, Color3.fromRGB(10, 28, 6), function()
	print("---- GraphicsLab export: paste into WorldService ----")
	print(string.format("Lighting.Brightness = %.2f", values.exposure))
	print(string.format("Lighting.Ambient = Color3.fromRGB(%d, %d, %d)",
		math.floor(values.ambient), math.floor(values.ambient * 1.06), math.floor(values.ambient * 1.3)))
	print(string.format("-- RDBloom Intensity = %.2f, Threshold = %.2f", values.bloom, values.threshold))
	print(string.format("-- RDGrade Saturation = %.2f, Contrast = %.2f", values.saturation, values.contrast))
	print(string.format("-- SpotLight Brightness = %.2f, Range = %d", values.spot, values.range))
	print(string.format("-- neon taming = %.2f (big neon slabs -> SmoothPlastic)", values.neon))
	print(string.format("-- outlineOnly = %s, shadows = %s, crowd = %s",
		tostring(values.outline > 0.5), tostring(values.shadows > 0.5), tostring(values.crowd > 0.5)))
	print("----------------------------------------------------")
	status.Text = "values printed to Output"
	status.TextColor3 = LIME
end)

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		panel.BackgroundTransparency = 0.3
		TweenService:Create(panel, TweenInfo.new(0.16), { BackgroundTransparency = 0.04 }):Play()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = nil
	end
end)

-- ---------------------------------------------------------------------------
-- Boot: correct the blowout immediately, then keep the scene registered
-- ---------------------------------------------------------------------------

local function boot()
	registerScene()
	for key, value in pairs(values) do setValue(key, value, true) end
	applyPreset("SAFE")
end

task.spawn(function()
	Workspace:WaitForChild("WorldDecor", 40)
	task.wait(0.5)
	boot()
end)

boot()

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Highlight") then
		table.insert(highlightRegistry, item)
		if values.outline > 0.5 then
			item.FillTransparency = 1
		end
	elseif item:IsA("SpotLight") or item:IsA("PointLight") then
		table.insert(spotRegistry, item)
		item.Brightness = values.spot
		item.Range = values.range
		item.Shadows = false
	end
end)

local decorWatcher = Workspace:FindFirstChild("WorldDecor")
if decorWatcher then
	decorWatcher:GetAttributeChangedSignal("Theme"):Connect(function()
		task.wait(0.6)
		registerScene()
		apply()
	end)
end

print("[GraphicsLab] SAFE preset applied â€” bloom, neon slabs and spots tamed. GRAPHICS button top-right.")
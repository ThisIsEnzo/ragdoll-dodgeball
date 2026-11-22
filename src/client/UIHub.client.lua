-- UIHub: one responsive home for every panel button.
--
-- Seven controllers each planted a button at a hardcoded y offset in the right
-- column, reaching y=288. On a phone in landscape the viewport is about 390px
-- tall while the action row and ability strip already own the bottom, so
-- FRIENDS sat on THROW and the strip covered STORE and RANKS.
--
-- No controller is edited. Existing buttons are reparented into this container;
-- Activated connections survive reparenting, so panels open exactly as before.
--
-- Two safeguards over the first draft:
--   1. The expanded list is height-capped against the real viewport and scrolls,
--      so ten buttons can never run off a short screen.
--   2. The ability strip is identified by its ULT and DODGE labels, not by being
--      the first Frame found. If it is not present, nothing is moved.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUB_NAME = "RDHub"

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE2 = Color3.fromRGB(26, 35, 66)
local TEXT = Color3.fromRGB(234, 240, 255)
local DIM = Color3.fromRGB(158, 174, 210)
local CYAN = Color3.fromRGB(0, 226, 255)

local MENU_LABELS = {
	CODE = 1,
	SHOP = 2,
	LOADOUT = 3,
	STYLE = 4,
	STORE = 5,
	RANKS = 6,
	FRIENDS = 7,
	GRAPHICS = 8,
	HIGH = 9,
	LOW = 9,
}
local EMOTE_ORDER = 10

local TOP_OFFSET = 10
local MENU_HEIGHT = 34
local MENU_GAP = 6
local MIN_LIST_HEIGHT = 100

local gui = Instance.new("ScreenGui")
gui.Name = HUB_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 6
gui.Parent = playerGui

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local root = make("Frame", {
	Size = UDim2.fromOffset(200, 40),
	Position = UDim2.new(1, -12, 0, TOP_OFFSET),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
}, gui)

local menuButton = make("TextButton", {
	Size = UDim2.fromOffset(100, MENU_HEIGHT),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = CYAN,
	TextColor3 = Color3.fromRGB(4, 22, 30),
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	Text = "MENU",
	Visible = false,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, menuButton)
make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.5 }, menuButton)

local list = make("ScrollingFrame", {
	Size = UDim2.fromOffset(200, 200),
	Position = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = CYAN,
	ScrollBarImageTransparency = 0.35,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.None,
}, root)

local scrollHint = make("TextLabel", {
	Size = UDim2.fromOffset(200, 14),
	Position = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "scroll for more",
	Visible = false,
}, root)

local captured = {}
local ordered = {}
local compact = false
local expanded = false
local abilityStrip = nil

local function orderOf(button)
	local direct = MENU_LABELS[button.Text]
	if direct then return direct end
	if string.find(button.Text, "^EMOTE") then return EMOTE_ORDER end
	return 99
end

local function isMenuButton(instance)
	if not instance:IsA("TextButton") then return false end
	local parent = instance.Parent
	if not parent or not parent:IsA("ScreenGui") then return false end
	if parent == gui then return false end
	if string.sub(parent.Name, 1, 2) ~= "RD" then return false end
	if MENU_LABELS[instance.Text] then return true end
	if string.find(instance.Text, "^EMOTE") then return true end
	return false
end

-- Precise fingerprint: the strip is the frame that holds both ability readouts.
-- An explicit name wins if a later revision adds one.
local function isAbilityStrip(frame)
	if frame.Name == "AbilityStrip" then return true end
	local hasUlt = false
	local hasDodge = false
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local text = string.upper(descendant.Text)
			if string.find(text, "^ULT") then hasUlt = true end
			if string.find(text, "^DODGE") then hasDodge = true end
		end
	end
	return hasUlt and hasDodge
end

local function findAbilityStrip()
	if abilityStrip and abilityStrip.Parent then return abilityStrip end
	abilityStrip = nil
	local cameraGui = playerGui:FindFirstChild("RDCamera")
	if not cameraGui then return nil end
	for _, child in ipairs(cameraGui:GetChildren()) do
		if child:IsA("Frame") and isAbilityStrip(child) then
			abilityStrip = child
			return child
		end
	end
	return nil
end

local function relayout()
	local camera = workspace.CurrentCamera
	local viewport = Vector2.new(1280, 720)
	if camera then viewport = camera.ViewportSize end

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	compact = touch or viewport.X < 760 or viewport.Y < 520

	local buttonWidth = 92
	local buttonHeight = 30
	local gap = 6

	if compact then
		buttonWidth = 100
		buttonHeight = 34
	elseif viewport.X < 1000 then
		buttonWidth = 84
		buttonHeight = 28
	end

	-- Landscape phones are wide but short: two columns keep the list inside the
	-- viewport without scrolling. Narrow portrait screens get one column.
	local columns = 1
	if viewport.X >= 560 then columns = 2 end

	local count = math.max(#ordered, 1)
	local rows = math.ceil(count / columns)
	local contentWidth = columns * buttonWidth + (columns - 1) * gap
	local contentHeight = rows * buttonHeight + math.max(0, rows - 1) * gap

	for index, button in ipairs(ordered) do
		local col = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		button.AnchorPoint = Vector2.new(0, 0)
		button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
		button.Position = UDim2.fromOffset(col * (buttonWidth + gap), row * (buttonHeight + gap))
		button.TextSize = if compact then 13 else 12
	end

	local bottomReserve = if compact then 132 else 96
	local usedTop = TOP_OFFSET
	if compact then usedTop = usedTop + MENU_HEIGHT + MENU_GAP end

	local available = math.floor(viewport.Y - usedTop - bottomReserve)
	local listHeight = math.max(MIN_LIST_HEIGHT, math.min(contentHeight, available))
	local overflowing = contentHeight > listHeight + 1

	local listTop = 0
	if compact then listTop = MENU_HEIGHT + MENU_GAP end

	list.Position = UDim2.fromOffset(0, listTop)
	list.Size = UDim2.fromOffset(contentWidth + (if overflowing then 8 else 0), listHeight)
	list.CanvasSize = UDim2.fromOffset(0, contentHeight)
	list.ScrollBarImageTransparency = if overflowing then 0.35 else 1

	scrollHint.Visible = overflowing and (not compact or expanded)
	scrollHint.Size = UDim2.fromOffset(contentWidth, 14)
	scrollHint.Position = UDim2.fromOffset(0, listTop + listHeight + 2)

	local totalHeight = listTop + listHeight
	if scrollHint.Visible then totalHeight += 16 end

	if compact then
		menuButton.Visible = true
		menuButton.Size = UDim2.fromOffset(buttonWidth, MENU_HEIGHT)
		menuButton.Text = if expanded then "CLOSE" else "MENU"
		menuButton.BackgroundColor3 = if expanded then SURFACE2 else CYAN
		menuButton.TextColor3 = if expanded then TEXT else Color3.fromRGB(4, 22, 30)
		list.Visible = expanded
		root.Size = UDim2.fromOffset(contentWidth, if expanded then totalHeight else MENU_HEIGHT)
	else
		menuButton.Visible = false
		list.Visible = true
		root.Size = UDim2.fromOffset(contentWidth, totalHeight)
	end

	local strip = findAbilityStrip()
	if strip then
		strip.AnchorPoint = Vector2.new(1, 1)
		strip.Position = UDim2.new(1, -12, 1, -128)
	end
end

local function capture(button)
	if captured[button] then return end
	captured[button] = true

	button.AnchorPoint = Vector2.new(0, 0)
	button.Parent = list
	table.insert(ordered, button)

	table.sort(ordered, function(a, b)
		local oa, ob = orderOf(a), orderOf(b)
		if oa ~= ob then return oa < ob end
		return a.Text < b.Text
	end)

	-- One connection per button, made at capture time and never inside a layout
	-- pass, so handlers cannot accumulate the way a render loop would.
	button.Activated:Connect(function()
		if compact then
			expanded = false
			relayout()
		end
	end)

	relayout()
end

local function sweep()
	for _, screenGui in ipairs(playerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui ~= gui then
			for _, child in ipairs(screenGui:GetChildren()) do
				if isMenuButton(child) then capture(child) end
			end
		end
	end
end

menuButton.Activated:Connect(function()
	expanded = not expanded
	relayout()
end)

playerGui.DescendantAdded:Connect(function(instance)
	if instance:IsA("TextButton") then
		task.defer(function()
			if instance.Parent and isMenuButton(instance) then capture(instance) end
		end)
	end
end)

task.spawn(function()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(relayout)
end)

task.spawn(function()
	for _ = 1, 30 do
		sweep()
		relayout()
		task.wait(0.5)
	end
	while true do
		task.wait(5)
		sweep()
		relayout()
	end
end)

sweep()
relayout()
print("[UIHub] responsive menu ready, height-capped and scrolling")

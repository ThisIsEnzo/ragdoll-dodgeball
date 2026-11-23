-- StyleClient: procedural cosmetics shop and replicated cosmetic presentation.
-- The client only requests purchases/equips; the server validates ownership and price.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("StyleCatalog"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("StyleRemotes")
local stateRemote = remotes:WaitForChild("StyleState")
local buyRemote = remotes:WaitForChild("StyleBuy")
local equipRemote = remotes:WaitForChild("StyleEquip")
local requestRemote = remotes:WaitForChild("StyleRequest")

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE = Color3.fromRGB(18, 25, 48)
local SURFACE2 = Color3.fromRGB(26, 35, 66)
local LINE = Color3.fromRGB(48, 62, 104)
local TEXT = Color3.fromRGB(234, 240, 255)
local DIM = Color3.fromRGB(158, 174, 210)
local LIME = Color3.fromRGB(150, 255, 60)
local AMBER = Color3.fromRGB(255, 190, 0)
local CYAN = Color3.fromRGB(0, 226, 255)
local MAGENTA = Color3.fromRGB(255, 70, 210)

local latestState
local activeTab = "TRAILS"
local render

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end

local function round(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local gui = make("ScreenGui", {
	Name = "RDStyle",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	DisplayOrder = 16,
}, player:WaitForChild("PlayerGui"))

local openButton = make("TextButton", {
	Size = UDim2.fromOffset(96, 32),
	Position = UDim2.new(1, -16, 0, 250),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = MAGENTA,
	TextColor3 = Color3.fromRGB(28, 4, 24),
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	Text = "STYLE",
}, gui)
round(openButton, 9)

local panel = make("Frame", {
	Size = UDim2.fromOffset(470, 470),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
round(panel, 16)
make("UIStroke", { Color = MAGENTA, Thickness = 2, Transparency = 0.3 }, panel)
local panelScale = make("UIScale", { Scale = 1 }, panel)

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	panelScale.Scale = math.min(1, viewport.X / 500, viewport.Y / 500)
end
updateScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local titleLabel = make("TextLabel", {
	Size = UDim2.new(1, -60, 0, 28),
	Position = UDim2.fromOffset(16, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 19,
	TextColor3 = MAGENTA,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "STYLE",
}, panel)

local closeButton = make("TextButton", {
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -12, 0, 12),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = SURFACE2,
	TextColor3 = TEXT,
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	Text = "X",
}, panel)
round(closeButton, 8)

local tabButtons = {}
for index, tab in ipairs(Catalog.Tabs) do
	local button = make("TextButton", {
		Size = UDim2.fromOffset(142, 30),
		Position = UDim2.fromOffset(16 + (index - 1) * 148, 46),
		BackgroundColor3 = SURFACE,
		TextColor3 = DIM,
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		Text = tab,
		AutoButtonColor = false,
	}, panel)
	round(button, 8)
	tabButtons[tab] = button
	button.Activated:Connect(function()
		activeTab = tab
		render()
	end)
end

local scroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -32, 1, -100),
	Position = UDim2.fromOffset(16, 86),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = MAGENTA,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(210, 92),
	CellPadding = UDim2.fromOffset(8, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, scroll)

local cards = {}

local function gradientPreview(parent, colors)
	local bar = make("Frame", {
		Size = UDim2.fromOffset(46, 10),
		Position = UDim2.fromOffset(10, 62),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, parent)
	round(bar, 6)
	make("UIGradient", { Color = Catalog.ColorSequence(colors) }, bar)
	return bar
end

local function getCard(index)
	if cards[index] then return cards[index] end
	local frame = make("Frame", {
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, scroll)
	round(frame, 11)
	local outline = make("UIStroke", { Color = LINE, Thickness = 1.5, Transparency = 0.5 }, frame)
	local name = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 15,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, frame)
	local detail = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
	}, frame)
	local action = make("TextButton", {
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(1, -10, 1, -10),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = SURFACE2,
		TextColor3 = TEXT,
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		Text = "",
	}, frame)
	round(action, 7)

	local card = {
		frame = frame, outline = outline, name = name, detail = detail,
		action = action, preview = nil, kind = nil, key = nil,
		owned = false, locked = false,
	}
	action.Activated:Connect(function()
		if card.locked or not card.kind or not card.key then return end
		if card.owned then
			equipRemote:FireServer(card.kind, card.key)
		else
			buyRemote:FireServer(card.kind, card.key)
		end
	end)
	cards[index] = card
	return card
end

render = function()
	if not latestState then
		titleLabel.Text = "STYLE   loading..."
		return
	end
	titleLabel.Text = string.format("STYLE   %d coins   LVL %d", latestState.coins or 0, latestState.level or 1)

	for tab, button in pairs(tabButtons) do
		button.BackgroundColor3 = if tab == activeTab then MAGENTA else SURFACE
		button.TextColor3 = if tab == activeTab then Color3.fromRGB(28, 4, 24) else DIM
	end

	local entries = Catalog.Trails
	local kind = "trail"
	local equipped = latestState.trail
	if activeTab == "EFFECTS" then
		entries, kind, equipped = Catalog.Effects, "effect", latestState.effect
	elseif activeTab == "TITLES" then
		entries, kind, equipped = Catalog.Titles, "title", latestState.title
	end

	local titleUnlocks = {}
	for _, item in ipairs(latestState.titles or {}) do
		titleUnlocks[item.key] = item.unlocked == true
	end

	for index, entry in ipairs(entries) do
		local card = getCard(index)
		card.frame.Visible = true
		card.kind = kind
		card.key = entry.key
		card.owned = false
		card.locked = false
		card.name.Text = if entry.name == "" then "NO TITLE" else entry.name
		card.name.TextColor3 = if kind == "title" then (entry.color or DIM) else TEXT
		if card.preview then card.preview:Destroy() card.preview = nil end

		local isEquipped = equipped == entry.key
		if kind == "title" then
			card.owned = titleUnlocks[entry.key] == true
			card.locked = not card.owned
			if entry.stat then
				local current = latestState.stats and latestState.stats[entry.stat] or 0
				card.detail.Text = string.format("%d / %d %s", current, entry.amount, string.upper(entry.stat))
			elseif entry.level > 1 then
				card.detail.Text = "Reach level " .. entry.level
			else
				card.detail.Text = "Available now"
			end
		else
			card.owned = entry.price == 0 or (latestState.owned or {})[kind .. ":" .. entry.key] == true
			local affordable = (latestState.coins or 0) >= entry.price
			if kind == "trail" then
				card.detail.Text = if entry.width == 0 then "Clean flight, no trail"
					else string.format("Width %.1f  ·  %d colour stops", entry.width, #entry.colors)
			else
				card.detail.Text = string.format("%d particles  ·  %s", entry.count,
					if entry.ring then "with shock ring" else "burst only")
			end
			card.preview = gradientPreview(card.frame, entry.colors)
		end

		if isEquipped then
			card.action.Text = "EQUIPPED"
			card.action.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
			card.action.TextColor3 = LIME
			card.outline.Color = LIME
			card.outline.Transparency = 0.15
		elseif card.locked then
			card.action.Text = "LOCKED"
			card.action.BackgroundColor3 = Color3.fromRGB(36, 42, 68)
			card.action.TextColor3 = DIM
			card.outline.Color = LINE
			card.outline.Transparency = 0.7
		elseif card.owned then
			card.action.Text = "EQUIP"
			card.action.BackgroundColor3 = CYAN
			card.action.TextColor3 = Color3.fromRGB(4, 22, 30)
			card.outline.Color = CYAN
			card.outline.Transparency = 0.4
		else
			card.action.Text = string.format("BUY %d", entry.price)
			local affordable = (latestState.coins or 0) >= entry.price
			card.action.BackgroundColor3 = if affordable then AMBER else Color3.fromRGB(60, 68, 100)
			card.action.TextColor3 = if affordable then Color3.fromRGB(28, 20, 0) else TEXT
			card.outline.Color = if affordable then AMBER else LINE
			card.outline.Transparency = 0.6
		end
	end

	for index = #entries + 1, #cards do
		cards[index].frame.Visible = false
		cards[index].kind = nil
		cards[index].key = nil
	end
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		requestRemote:FireServer()
		panelScale.Scale = 0.92
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		render()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

stateRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	latestState = state
	if panel.Visible then render() end
end)

-- Cosmetic world effects. Each client renders the same replicated event locally.
local fxFolder = make("Folder", { Name = "RDStyleFX" }, Workspace)

local function playerFrom(value)
	if typeof(value) == "Instance" and value:IsA("Model") then
		return Players:GetPlayerFromCharacter(value)
	elseif typeof(value) == "number" then
		return Players:GetPlayerByUserId(value)
	end
	return nil
end

local function colorSequence(colors)
	return Catalog.ColorSequence(colors)
end

local function attachTrail(ball, owner)
	if not ball:IsA("BasePart") then return end
	local key = owner:GetAttribute("TrailId")
	local entry = if typeof(key) == "string" then Catalog.TrailByKey[key] else nil
	if not entry or entry.width <= 0 then return end

	local existing = ball:FindFirstChild("StyleTrail")
	if existing then existing:Destroy() end
	local a0 = ball:FindFirstChild("StyleA") or Instance.new("Attachment")
	a0.Name = "StyleA"
	a0.Position = Vector3.new(0, ball.Size.Y * 0.42, 0)
	a0.Parent = ball
	local a1 = ball:FindFirstChild("StyleB") or Instance.new("Attachment")
	a1.Name = "StyleB"
	a1.Position = Vector3.new(0, -ball.Size.Y * 0.42, 0)
	a1.Parent = ball

	local trail = Instance.new("Trail")
	trail.Name = "StyleTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = colorSequence(entry.colors)
	trail.Lifetime = 0.42
	trail.MinLength = 0.1
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, entry.width),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.7
	trail.FaceCamera = true
	trail.Parent = ball
	task.delay(Catalog.TrailLifetime, function()
		if trail.Parent then trail:Destroy() end
		if a0.Parent then a0:Destroy() end
		if a1.Parent then a1:Destroy() end
	end)
end

local function burst(position, owner)
	local key = owner and owner:GetAttribute("EffectId") or "default"
	local entry = Catalog.EffectByKey[key] or Catalog.EffectByKey.default
	local anchor = Instance.new("Part")
	anchor.Name = "StyleBurst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Parent = fxFolder

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = colorSequence(entry.colors)
	emitter.Lifetime = NumberRange.new(0.35, 0.75)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(entry.speed * 0.6, entry.speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, entry.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.85
	emitter.Parent = attachment
	emitter:Emit(entry.count)

	if entry.ring then
		local ring = Instance.new("Part")
		ring.Name = "StyleShockRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Material = Enum.Material.Neon
		ring.Color = entry.colors[1]
		ring.Size = Vector3.new(0.2, 2, 2)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.35
		ring.Parent = fxFolder
		TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 16, 16),
			Transparency = 1,
		}):Play()
		task.delay(0.5, function()
			if ring.Parent then ring:Destroy() end
		end)
	end

	task.delay(1.2, function()
		if anchor.Parent then anchor:Destroy() end
	end)
end

-- Titles are shown above the character and never replace the existing identity tag.
local titleGuis = {}
local function refreshTitle(character)
	local owner = Players:GetPlayerFromCharacter(character)
	local head = character:FindFirstChild("Head")
	if not owner or not head then return end
	local key = owner:GetAttribute("TitleId")
	local entry = if typeof(key) == "string" then Catalog.TitleByKey[key] else nil
	local existing = titleGuis[character]
	if not entry or entry.name == "" then
		if existing then existing:Destroy() titleGuis[character] = nil end
		return
	end
	if existing and existing.Parent then
		local textLabel = existing:FindFirstChildOfClass("TextLabel")
		if textLabel then
			textLabel.Text = entry.name
			textLabel.TextColor3 = entry.color or TEXT
		end
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StyleTitle"
	billboard.Size = UDim2.fromOffset(150, 20)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 130
	billboard.Adornee = head
	billboard.Parent = head
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = entry.color or TEXT
	textLabel.TextStrokeTransparency = 0.4
	textLabel.Text = entry.name
	textLabel.Parent = billboard
	titleGuis[character] = billboard
end

local function watchPlayer(other)
	local function onCharacter(character)
		character:WaitForChild("Head", 5)
		if character.Parent then refreshTitle(character) end
	end
	other.CharacterAdded:Connect(onCharacter)
	other.CharacterRemoving:Connect(function(character)
		local billboard = titleGuis[character]
		if billboard then billboard:Destroy() end
		titleGuis[character] = nil
	end)
	other:GetAttributeChangedSignal("TitleId"):Connect(function()
		if other.Character then refreshTitle(other.Character) end
	end)
	if other.Character then task.spawn(onCharacter, other.Character) end
end

for _, other in ipairs(Players:GetPlayers()) do watchPlayer(other) end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(other)
	if other.Character then
		local billboard = titleGuis[other.Character]
		if billboard then billboard:Destroy() titleGuis[other.Character] = nil end
	end
end)

local fxRemote = Net.Get("FXEvent")
if fxRemote then
	fxRemote.OnClientEvent:Connect(function(eventKind, first, second)
		if eventKind == "throw" then
			if typeof(first) == "Instance" and first:IsA("BasePart") then
				local owner = playerFrom(second)
				if owner then attachTrail(first, owner) end
			end
		elseif eventKind == "ko" then
			-- MatchService emits an earlier generic KO notification with a reason string.
			-- The later hit event carries the thrower's character and includes the real owner.
			if typeof(second) == "Instance" and second:IsA("Model") then
				local root = first and first:FindFirstChild("HumanoidRootPart")
				if root then burst(root.Position, playerFrom(second)) end
			end
		end
	end)
end

print("[Style] shop and procedural cosmetic FX ready")

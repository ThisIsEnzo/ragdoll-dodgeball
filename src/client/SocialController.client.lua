-- SocialController: rank badge, global leaderboards, career stats and emote wheel.
-- The board panel is the long-term goal surface: it shows where you stand
-- against the whole player base, not just the current server.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("RankCatalog"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local rankRemotes = ReplicatedStorage:WaitForChild("RankRemotes")
local boardRemote = rankRemotes:WaitForChild("BoardState")
local requestRemote = rankRemotes:WaitForChild("BoardRequest")
local emoteRemotes = ReplicatedStorage:WaitForChild("EmoteRemotes")
local emoteRemote = emoteRemotes:WaitForChild("EmoteRequest")

local INK = Color3.fromRGB(10, 15, 30)
local SURFACE = Color3.fromRGB(18, 25, 48)
local SURFACE_2 = Color3.fromRGB(26, 35, 66)
local LINE = Color3.fromRGB(48, 62, 104)
local TEXT = Color3.fromRGB(234, 240, 255)
local DIM = Color3.fromRGB(158, 174, 210)
local GOLD = Color3.fromRGB(255, 190, 0)
local CYAN = Color3.fromRGB(0, 226, 255)
local LIME = Color3.fromRGB(150, 255, 60)
local RED = Color3.fromRGB(255, 58, 58)

local latest = nil
local activeTab = "kos"

local gui = Instance.new("ScreenGui")
gui.Name = "RDSocial"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", {
		Color = color, Thickness = thickness or 1.5,
		Transparency = transparency or 0.5,
	}, parent)
end

-- Rank chip ---------------------------------------------------------------

local rankChip = make("Frame", {
	Size = UDim2.fromOffset(150, 26),
	Position = UDim2.fromOffset(16, 106),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
}, gui)
corner(rankChip, 8)
local rankStroke = stroke(rankChip, GOLD, 1.5, 0.35)

local rankDot = make("Frame", {
	Size = UDim2.fromOffset(10, 10),
	Position = UDim2.fromOffset(9, 8),
	BackgroundColor3 = GOLD,
	BorderSizePixel = 0,
}, rankChip)
corner(rankDot, 5)

local rankLabel = make("TextLabel", {
	Size = UDim2.fromOffset(96, 26),
	Position = UDim2.fromOffset(26, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "BRONZE",
}, rankChip)

local rankWins = make("TextLabel", {
	Size = UDim2.fromOffset(30, 26),
	Position = UDim2.new(1, -8, 0, 0),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0W",
}, rankChip)

-- Board panel -------------------------------------------------------------

local openButton = make("TextButton", {
	Size = UDim2.fromOffset(96, 32),
	Position = UDim2.new(1, -16, 0, 174),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = CYAN,
	TextColor3 = Color3.fromRGB(4, 22, 30),
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	Text = "RANKS",
}, gui)
corner(openButton, 9)

local panel = make("Frame", {
	Size = UDim2.fromOffset(486, 470),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
corner(panel, 18)
stroke(panel, CYAN, 2, 0.3)
local panelScale = make("UIScale", { Scale = 1 }, panel)

make("Frame", {
	Size = UDim2.new(1, 0, 0, 3),
	BackgroundColor3 = CYAN,
	BorderSizePixel = 0,
}, panel)

local title = make("TextLabel", {
	Size = UDim2.new(1, -70, 0, 30),
	Position = UDim2.fromOffset(18, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 21,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "GLOBAL RANKS",
}, panel)

local closeButton = make("TextButton", {
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -12, 0, 14),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = SURFACE_2,
	TextColor3 = TEXT,
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	Text = "X",
}, panel)
corner(closeButton, 8)

-- Rank progress block

local rankBlock = make("Frame", {
	Size = UDim2.new(1, -32, 0, 74),
	Position = UDim2.fromOffset(16, 50),
	BackgroundColor3 = SURFACE,
	BorderSizePixel = 0,
}, panel)
corner(rankBlock, 12)
local blockStroke = stroke(rankBlock, GOLD, 1.5, 0.45)

local bigRank = make("TextLabel", {
	Size = UDim2.fromOffset(200, 26),
	Position = UDim2.fromOffset(14, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "BRONZE",
}, rankBlock)

local rankNext = make("TextLabel", {
	Size = UDim2.new(1, -28, 0, 16),
	Position = UDim2.fromOffset(14, 36),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, rankBlock)

local progressTrack = make("Frame", {
	Size = UDim2.new(1, -28, 0, 8),
	Position = UDim2.fromOffset(14, 56),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BorderSizePixel = 0,
}, rankBlock)
corner(progressTrack, 4)

local progressFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = GOLD,
	BorderSizePixel = 0,
}, progressTrack)
corner(progressFill, 4)

local winCount = make("TextLabel", {
	Size = UDim2.fromOffset(120, 26),
	Position = UDim2.new(1, -14, 0, 10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 18,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0 WINS",
}, rankBlock)

-- Tabs

local tabButtons = {}
for index, board in ipairs(Catalog.Boards) do
	local tab = make("TextButton", {
		Size = UDim2.fromOffset(110, 30),
		Position = UDim2.fromOffset(16 + (index - 1) * 116, 134),
		BackgroundColor3 = SURFACE,
		TextColor3 = DIM,
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		Text = board.label,
		AutoButtonColor = false,
	}, panel)
	corner(tab, 8)
	local tabStroke = stroke(tab, board.accent, 1.5, 0.8)
	tabButtons[board.key] = { button = tab, stroke = tabStroke, accent = board.accent }
	tab.Activated:Connect(function()
		activeTab = board.key
		if latest then
			boardRemote:Fire()
		end
		requestRemote:FireServer()
	end)
end

-- Rows

local list = make("ScrollingFrame", {
	Size = UDim2.new(1, -32, 0, 216),
	Position = UDim2.fromOffset(16, 172),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = CYAN,
	ScrollBarImageTransparency = 0.35,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)

make("UIListLayout", {
	Padding = UDim.new(0, 5),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

local rowPool = {}

local function getRow(index)
	local row = rowPool[index]
	if row then return row end

	local frame = make("Frame", {
		Size = UDim2.new(1, -8, 0, 34),
		BackgroundColor3 = SURFACE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, list)
	corner(frame, 8)
	local rowStroke = stroke(frame, LINE, 1, 0.7)

	local place = make("TextLabel", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 15,
		TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, frame)

	local medal = make("Frame", {
		Size = UDim2.fromOffset(4, 22),
		Position = UDim2.fromOffset(4, 6),
		BackgroundColor3 = LINE,
		BorderSizePixel = 0,
	}, frame)
	corner(medal, 2)

	local name = make("TextLabel", {
		Size = UDim2.new(1, -140, 0, 34),
		Position = UDim2.fromOffset(44, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, frame)

	local value = make("TextLabel", {
		Size = UDim2.fromOffset(90, 34),
		Position = UDim2.new(1, -10, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 15,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	}, frame)

	row = { frame = frame, place = place, name = name, value = value, medal = medal, stroke = rowStroke }
	rowPool[index] = row
	return row
end

-- Career footer

local footer = make("Frame", {
	Size = UDim2.new(1, -32, 0, 58),
	Position = UDim2.fromOffset(16, 396),
	BackgroundColor3 = SURFACE_2,
	BorderSizePixel = 0,
}, panel)
corner(footer, 12)

local careerLabels = { "MATCHES", "KNOCKOUTS", "CATCHES", "REVIVES" }
local careerKeys = { "matches", "kos", "catches", "revives" }
local careerValues = {}

for index, label in ipairs(careerLabels) do
	local x = 12 + (index - 1) * 114
	make("TextLabel", {
		Size = UDim2.fromOffset(104, 14),
		Position = UDim2.fromOffset(x, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = label,
	}, footer)
	local value = make("TextLabel", {
		Size = UDim2.fromOffset(104, 26),
		Position = UDim2.fromOffset(x, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 19,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0",
	}, footer)
	careerValues[careerKeys[index]] = value
end

-- Emote wheel -------------------------------------------------------------

local emoteButton = make("TextButton", {
	Size = UDim2.fromOffset(104, 40),
	Position = UDim2.new(0, 16, 1, -104),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = Color3.fromRGB(255, 70, 210),
	TextColor3 = Color3.fromRGB(28, 4, 24),
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	Text = "EMOTE  G",
}, gui)
corner(emoteButton, 10)

local wheel = make("Frame", {
	Size = UDim2.fromOffset(300, 300),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local wheelScale = make("UIScale", { Scale = 1 }, wheel)

local wheelHub = make("Frame", {
	Size = UDim2.fromOffset(96, 96),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
}, wheel)
corner(wheelHub, 48)
stroke(wheelHub, Color3.fromRGB(255, 70, 210), 2, 0.3)

local hubText = make("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	TextColor3 = DIM,
	TextWrapped = true,
	Text = "PICK ONE",
}, wheelHub)

local emoteCooldownUntil = 0

for index, emote in ipairs(Catalog.Emotes) do
	local angle = (index - 1) / #Catalog.Emotes * math.pi * 2 - math.pi / 2
	local radius = 108
	local cx = 150 + math.cos(angle) * radius
	local cy = 150 + math.sin(angle) * radius

	local button = make("TextButton", {
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.fromOffset(cx, cy),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = SURFACE,
		TextColor3 = TEXT,
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		Text = "",
		AutoButtonColor = false,
	}, wheel)
	corner(button, 38)
	stroke(button, emote.color, 2, 0.35)

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 22,
		TextColor3 = emote.color,
		Text = emote.glyph,
	}, button)

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 11,
		TextColor3 = TEXT,
		Text = emote.name,
	}, button)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { Size = UDim2.fromOffset(86, 86) }):Play()
		hubText.Text = emote.name
		hubText.TextColor3 = emote.color
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { Size = UDim2.fromOffset(76, 76) }):Play()
		hubText.Text = "PICK ONE"
		hubText.TextColor3 = DIM
	end)

	button.Activated:Connect(function()
		if os.clock() < emoteCooldownUntil then return end
		emoteCooldownUntil = os.clock() + Catalog.EmoteCooldown
		emoteRemote:FireServer(emote.key)
		wheel.Visible = false
	end)
end

local function toggleWheel(force)
	local show = force
	if show == nil then show = not wheel.Visible end
	wheel.Visible = show
	if show then
		wheelScale.Scale = 0.85
		TweenService:Create(wheelScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

emoteButton.Activated:Connect(function() toggleWheel() end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.G then
		toggleWheel()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		wheel.Visible = false
		panel.Visible = false
	end
end)

-- Emote playback on every client -----------------------------------------

local emoteByKey = {}
for _, emote in ipairs(Catalog.Emotes) do emoteByKey[emote.key] = emote end

local function playEmote(character, key)
	local emote = emoteByKey[key]
	if not emote then return end
	local head = character:FindFirstChild("Head")
	if not head then return end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = head.CFrame * CFrame.new(0, 2.2, 0)
	anchor.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(emote.color)
	emitter.Lifetime = NumberRange.new(0.5, 1.0)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-160, 160)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.8
	emitter.Parent = attachment
	emitter:Emit(emote.particles)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(150, 62)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	billboard.Parent = anchor

	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = INK
	bubble.BackgroundTransparency = 0.12
	bubble.BorderSizePixel = 0
	bubble.Parent = billboard
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 14)
	Instance.new("UIStroke", bubble).Color = emote.color
	Instance.new("UIStroke", bubble).Thickness = 2

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = bubble
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local glyph = Instance.new("TextLabel")
	glyph.Size = UDim2.new(1, 0, 0, 30)
	glyph.Position = UDim2.fromOffset(0, 4)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.FredokaOne
	glyph.TextSize = 24
	glyph.TextColor3 = emote.color
	glyph.Text = emote.glyph
	glyph.Parent = bubble

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 20)
	caption.Position = UDim2.fromOffset(0, 34)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextSize = 13
	caption.TextColor3 = TEXT
	caption.Text = emote.name
	caption.Parent = bubble

	local weld = Instance.new("WeldConstraint")
	local characterRoot = character:FindFirstChild("HumanoidRootPart")
	if characterRoot then
		anchor.Anchored = false
		weld.Part0 = anchor
		weld.Part1 = characterRoot
		weld.Parent = anchor
		anchor.CFrame = characterRoot.CFrame * CFrame.new(0, 4.4, 0)
	end

	task.delay(2.4, function()
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0.5 }):Play()
		task.wait(0.22)
		anchor:Destroy()
	end)
end

local fx = Net.Get("FXEvent")
if fx then
	fx.OnClientEvent:Connect(function(kind, a, b)
		if kind ~= "emote" then return end
		if typeof(a) == "Instance" and a:IsA("Model") and typeof(b) == "string" then
			playEmote(a, b)
		end
	end)
end

-- Rendering ---------------------------------------------------------------

local function render()
	if not latest then
		title.Text = "GLOBAL RANKS   loading..."
		return
	end

	local rank = latest.rank
	if rank then
		rankLabel.Text = rank.name
		rankLabel.TextColor3 = rank.color
		rankDot.BackgroundColor3 = rank.color
		rankStroke.Color = rank.color
		rankWins.Text = tostring(rank.wins) .. "W"

		bigRank.Text = rank.name
		bigRank.TextColor3 = rank.color
		blockStroke.Color = rank.color
		winCount.Text = tostring(rank.wins) .. " WINS"
		progressFill.BackgroundColor3 = rank.color
		TweenService:Create(progressFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(rank.progress, 1) }):Play()

		if rank.nextName then
			rankNext.Text = tostring(rank.remaining) .. " more wins to " .. rank.nextName
		else
			rankNext.Text = "Top tier reached"
		end
	end

	for key, tab in pairs(tabButtons) do
		if key == activeTab then
			tab.button.BackgroundColor3 = tab.accent
			tab.button.TextColor3 = Color3.fromRGB(6, 14, 26)
			tab.stroke.Transparency = 0
		else
			tab.button.BackgroundColor3 = SURFACE
			tab.button.TextColor3 = DIM
			tab.stroke.Transparency = 0.8
		end
	end

	local accent = CYAN
	for _, board in ipairs(Catalog.Boards) do
		if board.key == activeTab then accent = board.accent end
	end

	local rows = {}
	for _, board in ipairs(latest.boards or {}) do
		if board.key == activeTab then rows = board.rows or {} end
	end

	for index = 1, math.max(#rows, 1) do
		local row = getRow(index)
		local entry = rows[index]
		if entry then
			row.frame.Visible = true
			row.place.Text = "#" .. tostring(entry.place)
			row.name.Text = entry.name
			row.value.Text = tostring(entry.value)
			row.value.TextColor3 = accent

			local isMe = entry.userId == player.UserId
			if entry.place == 1 then
				row.medal.BackgroundColor3 = GOLD
				row.place.TextColor3 = GOLD
			elseif entry.place == 2 then
				row.medal.BackgroundColor3 = Color3.fromRGB(186, 198, 216)
				row.place.TextColor3 = Color3.fromRGB(186, 198, 216)
			elseif entry.place == 3 then
				row.medal.BackgroundColor3 = Color3.fromRGB(198, 132, 74)
				row.place.TextColor3 = Color3.fromRGB(198, 132, 74)
			else
				row.medal.BackgroundColor3 = LINE
				row.place.TextColor3 = DIM
			end

			if isMe then
				row.frame.BackgroundTransparency = 0
				row.frame.BackgroundColor3 = SURFACE_2
				row.stroke.Color = accent
				row.stroke.Transparency = 0.1
				row.name.TextColor3 = accent
				row.name.Text = entry.name .. "  (you)"
			else
				row.frame.BackgroundTransparency = 0.25
				row.frame.BackgroundColor3 = SURFACE
				row.stroke.Color = LINE
				row.stroke.Transparency = 0.7
				row.name.TextColor3 = TEXT
			end
		else
			row.frame.Visible = false
		end
	end

	if #rows == 0 then
		local row = getRow(1)
		row.frame.Visible = true
		row.place.Text = "--"
		row.name.Text = "No entries yet. Play a match to claim a spot."
		row.value.Text = ""
		row.medal.BackgroundColor3 = LINE
	end

	for key, label in pairs(careerValues) do
		local stats = latest.stats or {}
		label.Text = tostring(stats[key] or 0)
	end
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		panelScale.Scale = 0.92
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		requestRemote:FireServer()
		render()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

boardRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	latest = state
	render()
end)

RunService.Heartbeat:Connect(function()
	local left = emoteCooldownUntil - os.clock()
	if left > 0 then
		emoteButton.Text = string.format("%.1fs", left)
		emoteButton.BackgroundColor3 = Color3.fromRGB(70, 78, 112)
		emoteButton.TextColor3 = Color3.fromRGB(214, 224, 245)
	else
		emoteButton.Text = "EMOTE  G"
		emoteButton.BackgroundColor3 = Color3.fromRGB(255, 70, 210)
		emoteButton.TextColor3 = Color3.fromRGB(28, 4, 24)
	end
end)

task.spawn(function()
	task.wait(2)
	requestRemote:FireServer()
end)

print("[Social] ranks, leaderboards and emote wheel ready")
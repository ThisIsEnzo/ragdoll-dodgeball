-- MapVoteController: venue banner and between-match map vote.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("ArenaCatalog"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("MapRemotes")
local stateRemote = remotes:WaitForChild("MapState")
local voteRemote = remotes:WaitForChild("MapVote")

local latest = nil

local gui = Instance.new("ScreenGui")
gui.Name = "RDMap"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local banner = make("TextLabel", {
	Size = UDim2.fromOffset(300, 20),
	Position = UDim2.new(0.5, 0, 0, 96),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(206, 218, 244),
	TextStrokeTransparency = 0.5,
	Text = "",
}, gui)

local panel = make("Frame", {
	Size = UDim2.fromOffset(460, 210),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = Color3.fromRGB(0, 226, 255), Thickness = 2, Transparency = 0.3 }, panel)
local scale = make("UIScale", { Scale = 1 }, panel)

local title = make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 30),
	Position = UDim2.fromOffset(12, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(0, 226, 255),
	Text = "VOTE NEXT VENUE",
}, panel)

local timer = make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 18),
	Position = UDim2.fromOffset(12, 42),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(160, 176, 210),
	Text = "",
}, panel)

local cards = {}
for index = 1, 2 do
	local card = make("TextButton", {
		Size = UDim2.fromOffset(206, 120),
		Position = UDim2.fromOffset(14 + (index - 1) * 226, 72),
		BackgroundColor3 = Color3.fromRGB(22, 30, 58),
		TextColor3 = Color3.fromRGB(234, 240, 255),
		Font = Enum.Font.FredokaOne,
		TextSize = 16,
		Text = "",
		AutoButtonColor = false,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(0, 226, 255), Thickness = 2, Transparency = 0.7 }, card)

	local name = make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "",
	}, card)

	local tagline = make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(170, 186, 220),
		TextWrapped = true,
		Text = "",
	}, card)

	local count = make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 82),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(150, 255, 60),
		Text = "0 votes",
	}, card)

	cards[index] = { button = card, stroke = stroke, name = name, tagline = tagline, count = count, id = nil }

	card.Activated:Connect(function()
		if cards[index].id then
			voteRemote:FireServer(cards[index].id)
		end
	end)
end

local deadline = 0

local function render()
	if not latest then return end
	banner.Text = "VENUE: " .. tostring(latest.currentName)

	if not latest.voting then
		panel.Visible = false
		return
	end

	if not panel.Visible then
		panel.Visible = true
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	for index, card in ipairs(cards) do
		local option = latest.options[index]
		if option then
			card.id = option.id
			card.button.Visible = true
			card.name.Text = option.name
			card.tagline.Text = option.tagline
			card.count.Text = tostring(option.votes) .. " votes"
			local theme = Catalog.Themes[option.id]
			local accent = Color3.fromRGB(0, 226, 255)
			if theme then accent = theme.accent end
			card.stroke.Color = accent
			if latest.myVote == option.id then
				card.stroke.Transparency = 0
				card.button.BackgroundColor3 = Color3.fromRGB(34, 48, 84)
				card.count.TextColor3 = accent
			else
				card.stroke.Transparency = 0.7
				card.button.BackgroundColor3 = Color3.fromRGB(22, 30, 58)
				card.count.TextColor3 = Color3.fromRGB(150, 255, 60)
			end
		else
			card.button.Visible = false
			card.id = nil
		end
	end
end

stateRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	local wasVoting = false
	if latest then wasVoting = latest.voting end
	latest = state
	if state.voting and not wasVoting then
		deadline = os.clock() + Catalog.VoteSeconds
	end
	render()
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		if latest and latest.voting then
			local left = math.max(0, deadline - os.clock())
			timer.Text = string.format("closes in %.1fs", left)
		end
	end
end)

print("[Map] vote UI ready")
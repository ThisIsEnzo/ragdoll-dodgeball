-- LoadoutController: throw type selection panel.
-- Reads the catalog directly so unlock levels and tradeoffs always match
-- what the server enforces.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared:WaitForChild("Loadout"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("LoadoutRemotes")
local stateRemote = remotes:WaitForChild("LoadoutState")
local selectRemote = remotes:WaitForChild("LoadoutSelect")

local ACCENT = {
	amber = Color3.fromRGB(255, 190, 0),
	cyan = Color3.fromRGB(0, 226, 255),
	lime = Color3.fromRGB(150, 255, 60),
	magenta = Color3.fromRGB(255, 70, 210),
}

local latest = nil

local gui = Instance.new("ScreenGui")
gui.Name = "RDLoadout"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 9
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local openButton = make("TextButton", {
	Size = UDim2.fromOffset(96, 32),
	Position = UDim2.new(1, -16, 0, 98),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(0, 226, 255),
	TextColor3 = Color3.fromRGB(4, 22, 30),
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	Text = "LOADOUT",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, openButton)

local panel = make("Frame", {
	Size = UDim2.fromOffset(430, 380),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = Color3.fromRGB(0, 226, 255), Thickness = 2, Transparency = 0.35 }, panel)
local panelScale = make("UIScale", { Scale = 1 }, panel)

local title = make("TextLabel", {
	Size = UDim2.new(1, -60, 0, 30),
	Position = UDim2.fromOffset(16, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 19,
	TextColor3 = Color3.fromRGB(0, 226, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "LOADOUT",
}, panel)

local closeButton = make("TextButton", {
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -10, 0, 10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(40, 48, 80),
	TextColor3 = Color3.fromRGB(234, 240, 255),
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	Text = "X",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, closeButton)

local cards = {}

for index, typeId in ipairs(Loadout.Order) do
	local entry = Loadout.Types[typeId]
	local accent = ACCENT[entry.accent] or ACCENT.amber

	local card = make("Frame", {
		Size = UDim2.new(1, -28, 0, 74),
		Position = UDim2.fromOffset(14, 50 + (index - 1) * 80),
		BackgroundColor3 = Color3.fromRGB(22, 30, 58),
		BorderSizePixel = 0,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 11) }, card)
	local stroke = make("UIStroke", {
		Color = accent, Thickness = 2, Transparency = 0.75,
	}, card)

	make("Frame", {
		Size = UDim2.fromOffset(5, 58),
		Position = UDim2.fromOffset(9, 8),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	}, card)

	make("TextLabel", {
		Size = UDim2.fromOffset(180, 22),
		Position = UDim2.fromOffset(24, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 17,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.name,
	}, card)

	make("TextLabel", {
		Size = UDim2.fromOffset(250, 16),
		Position = UDim2.fromOffset(24, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(206, 218, 244),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.blurb,
	}, card)

	make("TextLabel", {
		Size = UDim2.fromOffset(250, 16),
		Position = UDim2.fromOffset(24, 48),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(150, 255, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.plus .. "   /   " .. entry.minus,
	}, card)

	local action = make("TextButton", {
		Size = UDim2.fromOffset(104, 40),
		Position = UDim2.new(1, -12, 0, 17),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(60, 68, 100),
		TextColor3 = Color3.fromRGB(234, 240, 255),
		Font = Enum.Font.FredokaOne,
		TextSize = 13,
		Text = "SELECT",
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 9) }, action)

	action.Activated:Connect(function()
		if not latest then return end
		if latest.level < entry.level then return end
		selectRemote:FireServer(typeId)
	end)

	cards[typeId] = { action = action, stroke = stroke, entry = entry, accent = accent }
end

local function render()
	if not latest then
		title.Text = "LOADOUT   loading..."
		return
	end
	title.Text = string.format("LOADOUT   LVL %d", latest.level)

	for typeId, card in pairs(cards) do
		local locked = latest.level < card.entry.level
		if locked then
			card.action.Text = "LVL " .. card.entry.level
			card.action.BackgroundColor3 = Color3.fromRGB(36, 42, 68)
			card.action.TextColor3 = Color3.fromRGB(150, 164, 196)
			card.stroke.Transparency = 0.85
		elseif latest.selected == typeId then
			card.action.Text = "EQUIPPED"
			card.action.BackgroundColor3 = card.accent
			card.action.TextColor3 = Color3.fromRGB(8, 16, 28)
			card.stroke.Transparency = 0
		else
			card.action.Text = "SELECT"
			card.action.BackgroundColor3 = Color3.fromRGB(60, 68, 100)
			card.action.TextColor3 = Color3.fromRGB(234, 240, 255)
			card.stroke.Transparency = 0.6
		end
	end
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		panelScale.Scale = 0.9
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		render()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

stateRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	latest = state
	render()
end)

print("[Loadout] UI ready")
-- ShopController: магазин косметики и выбор ульта.
-- render защищён от nil: раньше отсутствие owned обрывало цикл и кнопки оставались пустыми.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("ShopCatalog"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local stateRemote = remotes:WaitForChild("ShopState")
local buyRemote = remotes:WaitForChild("ShopBuyRequest")
local equipRemote = remotes:WaitForChild("ShopEquipRequest")
local ultRemote = remotes:WaitForChild("UltSelectRequest")

local latest = nil

local gui = Instance.new("ScreenGui")
gui.Name = "RDShop"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 8
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local inst = Instance.new(class)
	for key, value in pairs(props) do inst[key] = value end
	inst.Parent = parent
	return inst
end

local openBtn = make("TextButton", {
	Size = UDim2.fromOffset(96, 40),
	Position = UDim2.new(1, -16, 0, 12),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(255, 197, 61),
	TextColor3 = Color3.fromRGB(24, 16, 0),
	Font = Enum.Font.FredokaOne, TextSize = 15, Text = "SHOP",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, openBtn)

local panel = make("Frame", {
	Size = UDim2.fromOffset(420, 400),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(14, 20, 40),
	BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = Color3.fromRGB(255, 197, 61), Thickness = 2, Transparency = 0.3 }, panel)

local title = make("TextLabel", {
	Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(14, 10),
	BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 197, 61), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "SHOP",
}, panel)

local closeBtn = make("TextButton", {
	Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -10, 0, 10),
	AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(40, 48, 80),
	TextColor3 = Color3.fromRGB(234, 240, 255), Font = Enum.Font.FredokaOne,
	TextSize = 16, Text = "X",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, closeBtn)

local rows = {}
for index, item in ipairs(Catalog.Balls) do
	local row = make("Frame", {
		Size = UDim2.new(1, -24, 0, 38), Position = UDim2.fromOffset(12, 46 + (index - 1) * 42),
		BackgroundColor3 = Color3.fromRGB(22, 30, 58), BorderSizePixel = 0,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 9) }, row)

	local swatch = make("Frame", {
		Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(9, 8),
		BackgroundColor3 = item.color, BorderSizePixel = 0,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, swatch)

	make("TextLabel", {
		Size = UDim2.fromOffset(140, 22), Position = UDim2.fromOffset(40, 8),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14,
		TextColor3 = Color3.fromRGB(234, 240, 255), TextXAlignment = Enum.TextXAlignment.Left,
		Text = item.name,
	}, row)

	local action = make("TextButton", {
		Size = UDim2.fromOffset(126, 28), Position = UDim2.new(1, -8, 0, 5),
		AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(60, 68, 100),
		TextColor3 = Color3.fromRGB(234, 240, 255), Font = Enum.Font.FredokaOne,
		TextSize = 13, Text = "...",
	}, row)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, action)

	action.Activated:Connect(function()
		if not latest then return end
		local owned = latest.owned or {}
		if item.price == 0 or owned[item.id] == true then
			equipRemote:FireServer(item.id)
		else
			buyRemote:FireServer(item.id)
		end
	end)

	table.insert(rows, { id = item.id, item = item, action = action })
end

make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 292),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = Color3.fromRGB(160, 176, 210), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "ULTIMATE — unlocked by level, Q uses the selected one",
}, panel)

local ultButtons = {}
for index, ultId in ipairs(Catalog.UltOrder) do
	local btn = make("TextButton", {
		Size = UDim2.fromOffset(94, 40),
		Position = UDim2.fromOffset(12 + (index - 1) * 100, 314),
		BackgroundColor3 = Color3.fromRGB(60, 68, 100),
		TextColor3 = Color3.fromRGB(234, 240, 255),
		Font = Enum.Font.FredokaOne, TextSize = 12, Text = Catalog.UltLabels[ultId],
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 9) }, btn)
	btn.Activated:Connect(function() ultRemote:FireServer(ultId) end)
	table.insert(ultButtons, { id = ultId, btn = btn })
end

local function render()
	if not latest then
		title.Text = "SHOP   loading..."
		return
	end

	local coins = latest.coins or 0
	local level = latest.level or 1
	local owned = latest.owned or {}
	local equipped = latest.equipped or "ball_default"
	local selectedUlt = latest.ult or "Cannon"

	title.Text = string.format("SHOP   %d coins   LVL %d", coins, level)

	for _, entry in ipairs(rows) do
		local item = entry.item
		local isOwned = item.price == 0 or owned[item.id] == true
		local affordable = coins >= item.price

		if equipped == item.id then
			entry.action.Text = "EQUIPPED"
			entry.action.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
			entry.action.TextColor3 = Color3.fromRGB(150, 255, 120)
		elseif isOwned then
			entry.action.Text = "EQUIP"
			entry.action.BackgroundColor3 = Color3.fromRGB(46, 155, 255)
			entry.action.TextColor3 = Color3.fromRGB(6, 20, 36)
		else
			entry.action.Text = string.format("BUY %d", item.price)
			entry.action.BackgroundColor3 = if affordable
				then Color3.fromRGB(255, 197, 61) else Color3.fromRGB(70, 78, 112)
			entry.action.TextColor3 = if affordable
				then Color3.fromRGB(24, 16, 0) else Color3.fromRGB(214, 224, 245)
		end
	end

	for _, entry in ipairs(ultButtons) do
		local required = Catalog.UltLevels[entry.id] or 1
		if level < required then
			entry.btn.Text = "LVL " .. required
			entry.btn.BackgroundColor3 = Color3.fromRGB(40, 46, 72)
			entry.btn.TextColor3 = Color3.fromRGB(170, 182, 212)
		elseif selectedUlt == entry.id then
			entry.btn.Text = Catalog.UltLabels[entry.id]
			entry.btn.BackgroundColor3 = Color3.fromRGB(255, 79, 216)
			entry.btn.TextColor3 = Color3.fromRGB(28, 4, 24)
		else
			entry.btn.Text = Catalog.UltLabels[entry.id]
			entry.btn.BackgroundColor3 = Color3.fromRGB(70, 78, 112)
			entry.btn.TextColor3 = Color3.fromRGB(234, 240, 255)
		end
	end
end

openBtn.Activated:Connect(function()
	panel.Visible = not panel.Visible
	render()
end)
closeBtn.Activated:Connect(function() panel.Visible = false end)

stateRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	latest = state
	render()
end)

render()
print("[Shop] UI ready")
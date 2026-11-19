-- StoreController: gamepass and coin pack storefront.
-- Prices are read live from MarketplaceService so the panel never shows a
-- stale number. Unconfigured items render disabled with a setup hint.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("MonetizationCatalog"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("StoreRemotes")
local stateRemote = remotes:WaitForChild("StoreState")
local refreshRemote = remotes:WaitForChild("StoreRefresh")

local ACCENT = {
	amber = Color3.fromRGB(255, 190, 0),
	cyan = Color3.fromRGB(0, 226, 255),
	lime = Color3.fromRGB(150, 255, 60),
	magenta = Color3.fromRGB(255, 70, 210),
}

local ownership = {}
local priceCache = {}

local gui = Instance.new("ScreenGui")
gui.Name = "RDStore"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 13
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local openButton = make("TextButton", {
	Size = UDim2.fromOffset(96, 32),
	Position = UDim2.new(1, -16, 0, 136),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(255, 190, 0),
	TextColor3 = Color3.fromRGB(28, 20, 0),
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	Text = "STORE",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, openButton)

local vipChip = make("TextLabel", {
	Size = UDim2.fromOffset(54, 22),
	Position = UDim2.fromOffset(16, 78),
	BackgroundColor3 = Color3.fromRGB(255, 190, 0),
	TextColor3 = Color3.fromRGB(28, 20, 0),
	Font = Enum.Font.FredokaOne,
	TextSize = 12,
	Text = "VIP",
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 7) }, vipChip)

local panel = make("Frame", {
	Size = UDim2.fromOffset(470, 452),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 0), Thickness = 2, Transparency = 0.35 }, panel)
local panelScale = make("UIScale", { Scale = 1 }, panel)

local title = make("TextLabel", {
	Size = UDim2.new(1, -60, 0, 30),
	Position = UDim2.fromOffset(16, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(255, 190, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "STORE",
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

make("TextLabel", {
	Size = UDim2.new(1, -28, 0, 16),
	Position = UDim2.fromOffset(14, 44),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(160, 176, 210),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "PERMANENT PASSES",
}, panel)

local passCards = {}

for index, pass in ipairs(Catalog.GamePasses) do
	local accent = ACCENT[pass.accent] or ACCENT.amber
	local card = make("Frame", {
		Size = UDim2.new(1, -28, 0, 74),
		Position = UDim2.fromOffset(14, 62 + (index - 1) * 80),
		BackgroundColor3 = Color3.fromRGB(22, 30, 58),
		BorderSizePixel = 0,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 11) }, card)
	local stroke = make("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.6 }, card)

	make("Frame", {
		Size = UDim2.fromOffset(5, 58),
		Position = UDim2.fromOffset(9, 8),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	}, card)

	make("TextLabel", {
		Size = UDim2.fromOffset(200, 20),
		Position = UDim2.fromOffset(24, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 16,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = pass.name,
	}, card)

	local benefits = make("TextLabel", {
		Size = UDim2.fromOffset(290, 42),
		Position = UDim2.fromOffset(24, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(198, 212, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = table.concat(pass.benefits, "  /  "),
	}, card)

	local action = make("TextButton", {
		Size = UDim2.fromOffset(108, 42),
		Position = UDim2.new(1, -12, 0, 16),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = accent,
		TextColor3 = Color3.fromRGB(10, 16, 28),
		Font = Enum.Font.FredokaOne,
		TextSize = 13,
		Text = "...",
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 9) }, action)

	action.Activated:Connect(function()
		if pass.id <= 0 then return end
		if ownership[pass.key] then return end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end)

	passCards[pass.key] = { action = action, stroke = stroke, pass = pass, accent = accent, benefits = benefits }
end

make("TextLabel", {
	Size = UDim2.new(1, -28, 0, 16),
	Position = UDim2.fromOffset(14, 306),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(160, 176, 210),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "COINS AND EXTRAS",
}, panel)

local productCards = {}

for index, product in ipairs(Catalog.Products) do
	local accent = ACCENT[product.accent] or ACCENT.lime
	local col = (index - 1) % 4
	local card = make("TextButton", {
		Size = UDim2.fromOffset(106, 106),
		Position = UDim2.fromOffset(14 + col * 112, 326),
		BackgroundColor3 = Color3.fromRGB(22, 30, 58),
		TextColor3 = Color3.fromRGB(234, 240, 255),
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		Text = "",
		AutoButtonColor = false,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 11) }, card)
	local stroke = make("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.6 }, card)

	make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.fromOffset(6, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 11,
		TextColor3 = accent,
		TextWrapped = true,
		Text = product.name,
	}, card)

	local detail = "REROLL"
	if product.coins then detail = tostring(product.coins) end
	make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = detail,
	}, card)

	local price = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 74),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		TextColor3 = accent,
		Text = "...",
	}, card)

	if product.best then
		local tag = make("TextLabel", {
			Size = UDim2.fromOffset(52, 16),
			Position = UDim2.new(1, -4, 0, -6),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = accent,
			TextColor3 = Color3.fromRGB(10, 16, 28),
			Font = Enum.Font.FredokaOne,
			TextSize = 9,
			Text = "BEST",
		}, card)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, tag)
	end

	card.Activated:Connect(function()
		if product.id <= 0 then return end
		MarketplaceService:PromptProductPurchase(player, product.id)
	end)

	productCards[product.key] = { price = price, stroke = stroke, product = product, accent = accent }
end

local hint = make("TextLabel", {
	Size = UDim2.new(1, -28, 0, 14),
	Position = UDim2.fromOffset(14, 434),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = Color3.fromRGB(255, 170, 120),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, panel)

local function priceLabel(id, infoType, fallback)
	if id <= 0 then return "SET ID" end
	local cached = priceCache[id]
	if cached then return cached end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		local text = tostring(fallback) .. " R$"
		if ok and typeof(info) == "table" and info.PriceInRobux then
			text = tostring(info.PriceInRobux) .. " R$"
		end
		priceCache[id] = text
		for _, card in pairs(passCards) do
			if card.pass.id == id then card.action.Text = text end
		end
		for _, card in pairs(productCards) do
			if card.product.id == id then card.price.Text = text end
		end
	end)
	return tostring(fallback) .. " R$"
end

local function render()
	local unconfigured = 0

	for key, card in pairs(passCards) do
		local pass = card.pass
		if pass.id <= 0 then
			unconfigured += 1
			card.action.Text = "SET ID"
			card.action.BackgroundColor3 = Color3.fromRGB(40, 46, 72)
			card.action.TextColor3 = Color3.fromRGB(170, 182, 212)
			card.stroke.Transparency = 0.85
		elseif ownership[key] then
			card.action.Text = "OWNED"
			card.action.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
			card.action.TextColor3 = Color3.fromRGB(150, 255, 120)
			card.stroke.Transparency = 0
		else
			card.action.Text = priceLabel(pass.id, Enum.InfoType.GamePass, pass.fallbackPrice)
			card.action.BackgroundColor3 = card.accent
			card.action.TextColor3 = Color3.fromRGB(10, 16, 28)
			card.stroke.Transparency = 0.4
		end
	end

	for _, card in pairs(productCards) do
		local product = card.product
		if product.id <= 0 then
			unconfigured += 1
			card.price.Text = "SET ID"
			card.price.TextColor3 = Color3.fromRGB(170, 182, 212)
			card.stroke.Transparency = 0.85
		else
			card.price.Text = priceLabel(product.id, Enum.InfoType.Product, product.fallbackPrice)
			card.price.TextColor3 = card.accent
			card.stroke.Transparency = 0.4
		end
	end

	if unconfigured > 0 then
		hint.Text = tostring(unconfigured) .. " items need ids from Creator Hub in MonetizationCatalog.lua"
	else
		hint.Text = ""
	end

	vipChip.Visible = player:GetAttribute("VIP") == true
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		panelScale.Scale = 0.92
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		refreshRemote:FireServer()
		render()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

stateRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	for _, entry in ipairs(state.passes or {}) do
		ownership[entry.key] = entry.owned
	end
	render()
end)

player:GetAttributeChangedSignal("VIP"):Connect(render)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
	task.wait(0.5)
	refreshRemote:FireServer()
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function()
	task.wait(0.5)
	refreshRemote:FireServer()
end)

render()
print("[Store] UI ready")
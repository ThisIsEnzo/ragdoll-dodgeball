-- PromoController: code entry panel next to the SHOP button.
-- Self-contained LocalScript, does not touch HUD or ShopController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("PromoRemotes")
local redeemRemote = remotes:WaitForChild("PromoRedeem")
local resultRemote = remotes:WaitForChild("PromoResult")

local gui = Instance.new("ScreenGui")
gui.Name = "RDPromo"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 9
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local openButton = make("TextButton", {
	Size = UDim2.fromOffset(96, 40),
	Position = UDim2.new(1, -120, 0, 12),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(124, 255, 79),
	TextColor3 = Color3.fromRGB(8, 24, 10),
	Font = Enum.Font.FredokaOne,
	TextSize = 15,
	Text = "CODE",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, openButton)

local panel = make("Frame", {
	Size = UDim2.fromOffset(340, 190),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(14, 20, 40),
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", {
	Color = Color3.fromRGB(124, 255, 79),
	Thickness = 2,
	Transparency = 0.3,
}, panel)

make("TextLabel", {
	Size = UDim2.new(1, -60, 0, 28),
	Position = UDim2.fromOffset(14, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(124, 255, 79),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "PROMO CODE",
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

local box = make("TextBox", {
	Size = UDim2.new(1, -28, 0, 44),
	Position = UDim2.fromOffset(14, 52),
	BackgroundColor3 = Color3.fromRGB(22, 30, 58),
	TextColor3 = Color3.fromRGB(234, 240, 255),
	PlaceholderColor3 = Color3.fromRGB(140, 156, 190),
	PlaceholderText = "type a code",
	Text = "",
	Font = Enum.Font.FredokaOne,
	TextSize = 18,
	ClearTextOnFocus = false,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)

local redeemButton = make("TextButton", {
	Size = UDim2.new(1, -28, 0, 40),
	Position = UDim2.fromOffset(14, 104),
	BackgroundColor3 = Color3.fromRGB(124, 255, 79),
	TextColor3 = Color3.fromRGB(8, 24, 10),
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	Text = "REDEEM",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, redeemButton)

local status = make("TextLabel", {
	Size = UDim2.new(1, -28, 0, 22),
	Position = UDim2.fromOffset(14, 150),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(160, 176, 210),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, panel)

local function submit()
	local text = box.Text
	if #text == 0 then
		status.Text = "Enter a code"
		status.TextColor3 = Color3.fromRGB(255, 170, 120)
		return
	end
	status.Text = "Checking..."
	status.TextColor3 = Color3.fromRGB(160, 176, 210)
	redeemRemote:FireServer(text)
end

redeemButton.Activated:Connect(submit)
box.FocusLost:Connect(function(enterPressed)
	if enterPressed then submit() end
end)

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		status.Text = ""
		box.Text = ""
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

resultRemote.OnClientEvent:Connect(function(success, message)
	if success then
		status.TextColor3 = Color3.fromRGB(124, 255, 79)
		box.Text = ""
	else
		status.TextColor3 = Color3.fromRGB(255, 140, 120)
	end
	status.Text = tostring(message)
end)

print("[Promo] UI ready, CODE button top-right")
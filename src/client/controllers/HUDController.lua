-- HUDController: минимальный боевой HUD. Счёт, таймер, заряд, Hype, кнопки, экран результата.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local InputController = require(script.Parent:WaitForChild("InputController"))

local HUDController = {}
local gui, scoreLabel, stateLabel, chargeFill, hypeFill, resultFrame, resultLabel

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function button(text, position, color, callback)
	local btn = make("TextButton", {
		Size = UDim2.fromOffset(96, 62),
		Position = position,
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = color,
		TextColor3 = Color3.fromRGB(10, 14, 26),
		Font = Enum.Font.FredokaOne,
		TextSize = 15,
		Text = text,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, btn)
	btn.Activated:Connect(callback)
	return btn
end

function HUDController.Init()
	gui = make("ScreenGui", {
		Name = "DodgeballHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))

	local top = make("Frame", {
		Size = UDim2.fromOffset(260, 58), Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(12, 18, 38),
		BackgroundTransparency = 0.15, BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, top)

	scoreLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4),
		BackgroundTransparency = 1, Text = "0 : 0", TextColor3 = Color3.fromRGB(255, 197, 61),
		Font = Enum.Font.FredokaOne, TextSize = 24,
	}, top)

	stateLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1, Text = "ожидание", TextColor3 = Color3.fromRGB(143, 160, 201),
		Font = Enum.Font.GothamBold, TextSize = 13,
	}, top)

	local chargeTrack = make("Frame", {
		Size = UDim2.fromOffset(220, 12), Position = UDim2.new(0.5, 0, 1, -26),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(10, 14, 26), BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, chargeTrack)
	chargeFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 197, 61), BorderSizePixel = 0,
	}, chargeTrack)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, chargeFill)

	local hypeTrack = make("Frame", {
		Size = UDim2.fromOffset(160, 12), Position = UDim2.new(0, 16, 1, -26),
		BackgroundColor3 = Color3.fromRGB(10, 14, 26), BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, hypeTrack)
	hypeFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 79, 216), BorderSizePixel = 0,
	}, hypeTrack)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, hypeFill)

	button("CATCH (F)", UDim2.new(1, -16, 1, -16), Color3.fromRGB(124, 255, 79), InputController.Catch)
	button("DODGE", UDim2.new(1, -124, 1, -16), Color3.fromRGB(46, 155, 255), InputController.Dodge)
	button("ULT (Q)", UDim2.new(1, -232, 1, -16), Color3.fromRGB(255, 79, 216), InputController.Ult)

	local throwBtn = button("THROW", UDim2.new(1, -16, 1, -92), Color3.fromRGB(255, 90, 77), function() end)
	throwBtn.Size = UDim2.fromOffset(140, 72)
	throwBtn.MouseButton1Down:Connect(InputController.BeginCharge)
	throwBtn.MouseButton1Up:Connect(InputController.ReleaseCharge)

	resultFrame = make("Frame", {
		Size = UDim2.fromOffset(300, 150), Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(18, 24, 48),
		BorderSizePixel = 0, Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, resultFrame)

	resultLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 16),
		BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.FredokaOne, TextSize = 26,
	}, resultFrame)

	local rematch = make("TextButton", {
		Size = UDim2.fromOffset(200, 48), Position = UDim2.new(0.5, 0, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(255, 197, 61),
		Text = "РЕВАНШ", TextColor3 = Color3.fromRGB(20, 14, 0), Font = Enum.Font.FredokaOne, TextSize = 18,
	}, resultFrame)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, rematch)
	rematch.Activated:Connect(function()
		resultFrame.Visible = false
		InputController.Rematch()
	end)
end

function HUDController.Start()
	RunService.RenderStepped:Connect(function()
		chargeFill.Size = UDim2.new(InputController.GetCharge(), 0, 1, 0)
	end)

	local matchState = Net.Get("MatchState")
	if matchState then
		matchState.OnClientEvent:Connect(function(state)
			if typeof(state) ~= "table" then return end
			scoreLabel.Text = tostring(state.wins1 or 0) .. " : " .. tostring(state.wins2 or 0)
			if state.state == "MatchEnd" then
				resultFrame.Visible = true
				local character = Players.LocalPlayer.Character
				local myTeam = character and character:GetAttribute("Team")
				resultLabel.Text = if myTeam == state.winner then "ПОБЕДА" else "ПОРАЖЕНИЕ"
				stateLabel.Text = "матч завершён"
			else
				stateLabel.Text = tostring(state.state or "") .. "  " .. tostring(state.timer or 0) .. "с"
			end
		end)
	end

	local hypeState = Net.Get("HypeState")
	if hypeState then
		hypeState.OnClientEvent:Connect(function(value, max)
			hypeFill.Size = UDim2.new(math.clamp(value / math.max(max, 1), 0, 1), 0, 1, 0)
		end)
	end
end

return HUDController

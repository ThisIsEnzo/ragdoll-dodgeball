-- SpectatorController: turns bench time into watching time.
-- When your character is benched the camera leaves your body and follows the
-- published highlight. You can cycle targets manually, and control returns
-- to you the instant you are revived or a new round starts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local targetValue = ReplicatedStorage:WaitForChild("SpectateTarget")
local reasonValue = ReplicatedStorage:WaitForChild("SpectateReason")

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE = Color3.fromRGB(18, 25, 48)
local LINE = Color3.fromRGB(48, 62, 104)
local TEXT = Color3.fromRGB(234, 240, 255)
local DIM = Color3.fromRGB(158, 174, 210)
local AMBER = Color3.fromRGB(255, 190, 0)
local LIME = Color3.fromRGB(150, 255, 60)
local CYAN = Color3.fromRGB(0, 226, 255)

local spectating = false
local manualIndex = 0
local manualList = {}
local currentModel = nil
local smoothPos = nil
local lastSwitch = 0

local TIPS = {
	"A catch brings a teammate back from the bench.",
	"Hold your throw longer for more speed and range.",
	"Bounce throws stay live after one wall hit.",
	"Curve throws bend around cover.",
	"Fill the hype meter to fire your ultimate.",
	"Stay on your half. The line is enforced.",
}

-- UI ----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "RDSpectate"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 15
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local bar = make("Frame", {
	Size = UDim2.fromOffset(430, 76),
	Position = UDim2.new(0.5, 0, 0, 118),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, bar)
make("UIStroke", { Color = AMBER, Thickness = 2, Transparency = 0.35 }, bar)

make("Frame", {
	Size = UDim2.fromOffset(5, 56),
	Position = UDim2.fromOffset(10, 10),
	BackgroundColor3 = AMBER,
	BorderSizePixel = 0,
}, bar)

local headline = make("TextLabel", {
	Size = UDim2.new(1, -40, 0, 24),
	Position = UDim2.fromOffset(26, 10),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 18,
	TextColor3 = AMBER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "SPECTATING",
}, bar)

local subline = make("TextLabel", {
	Size = UDim2.new(1, -40, 0, 18),
	Position = UDim2.fromOffset(26, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, bar)

local hintline = make("TextLabel", {
	Size = UDim2.new(1, -40, 0, 16),
	Position = UDim2.fromOffset(26, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "TAB cycles targets  Â·  back in play next round",
}, bar)

local tipCard = make("Frame", {
	Size = UDim2.fromOffset(430, 44),
	Position = UDim2.new(0.5, 0, 0, 202),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 11) }, tipCard)
make("UIStroke", { Color = LINE, Thickness = 1.5, Transparency = 0.5 }, tipCard)

local tipLabel = make("TextLabel", {
	Size = UDim2.new(1, -24, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = LIME,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	Text = "",
}, tipCard)

local aliveStrip = make("Frame", {
	Size = UDim2.fromOffset(430, 30),
	Position = UDim2.new(0.5, 0, 0, 254),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui)

local blueCount = make("TextLabel", {
	Size = UDim2.fromOffset(200, 30),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	TextColor3 = CFG.Teams[1].color,
	Text = "BLUE  3 ALIVE",
}, aliveStrip)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, blueCount)

local redCount = make("TextLabel", {
	Size = UDim2.fromOffset(200, 30),
	Position = UDim2.fromOffset(230, 0),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	TextColor3 = CFG.Teams[2].color,
	Text = "RED  3 ALIVE",
}, aliveStrip)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, redCount)

-- camera ------------------------------------------------------------------

local function aliveActors()
	local list = {}
	for _, model in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		if model:IsA("Model") and model ~= player.Character then
			if not model:GetAttribute("Benched") and not model:GetAttribute("Ragdolled") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local root = model:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and root then
					table.insert(list, model)
				end
			end
		end
	end
	return list
end

local function focusOf(model)
	if not model or not model.Parent then return nil end
	local head = model:FindFirstChild("Head")
	if head then return head.Position end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then return root.Position end
	return nil
end

local function ballFocus()
	local balls = workspace:FindFirstChild("Balls")
	if not balls then return nil end
	local best, bestSpeed = nil, -1
	for _, ball in ipairs(balls:GetChildren()) do
		if ball:IsA("BasePart") then
			local speed = ball.AssemblyLinearVelocity.Magnitude
			if speed > bestSpeed then best, bestSpeed = ball, speed end
		end
	end
	if best and bestSpeed > 12 then return best.Position end
	return nil
end

local function labelFor(model)
	if not model then return "waiting for the next round" end
	local display = model:GetAttribute("DisplayName")
	if typeof(display) == "string" then return display end
	local owner = Players:GetPlayerFromCharacter(model)
	if owner then return owner.DisplayName end
	return model.Name
end

local function desiredFocus()
	if manualIndex > 0 and #manualList > 0 then
		local model = manualList[((manualIndex - 1) % #manualList) + 1]
		local pos = focusOf(model)
		if pos then return pos, labelFor(model), "MANUAL" end
		manualIndex = 0
	end

	local auto = targetValue.Value
	local pos = focusOf(auto)
	if pos then
		return pos, labelFor(auto), reasonValue.Value
	end

	local ballPos = ballFocus()
	if ballPos then return ballPos, "the ball", "LOOSE BALL" end

	return Vector3.new(0, 8, 0), "the court", "ROUND OVER"
end

local function enter()
	if spectating then return end
	spectating = true
	gui.Enabled = true
	manualIndex = 0
	smoothPos = nil
	tipLabel.Text = TIPS[math.random(1, #TIPS)]
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

local function leave()
	if not spectating then return end
	spectating = false
	gui.Enabled = false
	manualIndex = 0
	smoothPos = nil
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then camera.CameraSubject = humanoid end
	end
end

local function syncBench()
	local character = player.Character
	if not character then leave() return end
	if character:GetAttribute("Benched") then enter() else leave() end
end

player.CharacterAdded:Connect(function(character)
	leave()
	task.wait(0.2)
	character:GetAttributeChangedSignal("Benched"):Connect(syncBench)
	syncBench()
end)

if player.Character then
	player.Character:GetAttributeChangedSignal("Benched"):Connect(syncBench)
	syncBench()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not spectating then return end
	if input.KeyCode == Enum.KeyCode.Tab or input.UserInputType == Enum.UserInputType.MouseButton1 then
		manualList = aliveActors()
		if #manualList == 0 then return end
		manualIndex = manualIndex + 1
		if manualIndex > #manualList then manualIndex = 1 end
		lastSwitch = os.clock()
	end
end)

local tipTimer = 0
local aliveTimer = 0

RunService.RenderStepped:Connect(function(dt)
	if not spectating then return end
	local camera = workspace.CurrentCamera
	if not camera then return end

	local focus, name, why = desiredFocus()
	if not smoothPos then smoothPos = focus end
	smoothPos = smoothPos:Lerp(focus, math.clamp(dt * 4.5, 0, 1))

	local orbit = os.clock() * 0.16
	local offset = Vector3.new(math.cos(orbit) * 20, 11, math.sin(orbit) * 20)
	local want = smoothPos + offset
	camera.CFrame = CFrame.lookAt(camera.CFrame.Position:Lerp(want, math.clamp(dt * 3.2, 0, 1)), smoothPos)

	subline.Text = string.format("watching %s  Â·  %s", name, tostring(why))

	tipTimer += dt
	if tipTimer > 6 then
		tipTimer = 0
		tipLabel.Text = TIPS[math.random(1, #TIPS)]
	end

	aliveTimer += dt
	if aliveTimer > 0.5 then
		aliveTimer = 0
		local blue, red = 0, 0
		for _, model in ipairs(CollectionService:GetTagged("DodgeballActor")) do
			if model:IsA("Model") and not model:GetAttribute("Benched") and not model:GetAttribute("Ragdolled") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local team = model:GetAttribute("Team")
					if team == 1 then blue += 1 elseif team == 2 then red += 1 end
				end
			end
		end
		blueCount.Text = string.format("BLUE  %d ALIVE", blue)
		redCount.Text = string.format("RED  %d ALIVE", red)
	end
end)

print("[Spectate] bench camera ready, TAB cycles targets")
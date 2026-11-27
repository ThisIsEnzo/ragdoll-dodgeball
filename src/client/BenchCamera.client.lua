-- BenchCamera: external seated spectator view for knocked-out players.
-- The camera stays behind and above the bench position, looking toward the court.
-- Drag to orbit, use the mouse wheel to change distance, and reset to face the court.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local MIN_DISTANCE, MAX_DISTANCE = 9, 30
local MIN_HEIGHT, MAX_HEIGHT = 3, 18
local FADE_RADIUS = 7
local INK = Color3.fromRGB(8, 12, 26)
local DIM = Color3.fromRGB(158, 174, 210)
local AMBER = Color3.fromRGB(255, 190, 0)
local CYAN = Color3.fromRGB(0, 226, 255)

local active = false
local anchor: Vector3? = nil
local yawOffset = 0
local pitch = 0.3
local distance = 15
local height = 8
local fov = 62
local baseFov = 70
local dragging = false
local lastPointer: Vector2? = nil
local fadedParts = {}
local smoothPosition: Vector3? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "RDBenchCamera"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 15
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className, props, parent)
	local item = Instance.new(className)
	for key, value in pairs(props) do
		(item :: any)[key] = value
	end
	item.Parent = parent
	return item
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local bar = make("Frame", {
	Size = UDim2.fromOffset(430, 46),
	Position = UDim2.new(0.5, 0, 1, -196),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
}, gui)
corner(bar, 12)
make("UIStroke", { Color = AMBER, Thickness = 2, Transparency = 0.3 }, bar)

make("TextLabel", {
	Size = UDim2.fromOffset(180, 20),
	Position = UDim2.fromOffset(24, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	TextColor3 = AMBER,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "ON THE BENCH",
}, bar)

make("TextLabel", {
	Size = UDim2.fromOffset(240, 16),
	Position = UDim2.fromOffset(24, 25),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "drag to orbit  -  wheel for distance  -  catch brings you back",
}, bar)

local blueTag = make("TextLabel", {
	Size = UDim2.fromOffset(80, 20),
	Position = UDim2.new(1, -172, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	TextColor3 = CFG.Teams[1].color,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "BLUE 0",
}, bar)

local redTag = make("TextLabel", {
	Size = UDim2.fromOffset(80, 20),
	Position = UDim2.new(1, -88, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	TextColor3 = CFG.Teams[2].color,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "RED 0",
}, bar)

local panel = make("Frame", {
	Size = UDim2.fromOffset(214, 104),
	Position = UDim2.new(0, 12, 1, -196),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
}, gui)
corner(panel, 12)
make("UIStroke", { Color = CYAN, Thickness = 1.5, Transparency = 0.45 }, panel)

make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 18),
	Position = UDim2.fromOffset(8, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 12,
	TextColor3 = CYAN,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "SEAT VIEW",
}, panel)

local readout = make("TextLabel", {
	Size = UDim2.new(1, -16, 0, 32),
	Position = UDim2.fromOffset(8, 28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = DIM,
	TextWrapped = true,
	Text = "Distance 15  |  Height 8  |  FOV 62",
}, panel)

local resetButton = make("TextButton", {
	Size = UDim2.fromOffset(198, 26),
	Position = UDim2.fromOffset(8, 68),
	BackgroundColor3 = Color3.fromRGB(26, 35, 66),
	TextColor3 = Color3.fromRGB(234, 240, 255),
	Font = Enum.Font.FredokaOne,
	TextSize = 11,
	Text = "RESET VIEW",
	AutoButtonColor = true,
}, panel)
corner(resetButton, 7)

local function updateReadout()
	readout.Text = string.format("Distance %d  |  Height %d  |  FOV %d", distance, height, fov)
end

local function restoreFaded()
	for part in pairs(fadedParts) do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	table.clear(fadedParts)
end

local function fadeOwnAvatar(cameraPosition)
	local character = player.Character
	if not character then
		restoreFaded()
		return
	end

	local keep = {}
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			local radius = math.max(item.Size.X, item.Size.Y, item.Size.Z) * 0.5
			if (item.Position - cameraPosition).Magnitude < FADE_RADIUS + radius then
				keep[item] = true
				item.LocalTransparencyModifier = 1
				fadedParts[item] = true
			end
		end
	end

	for part in pairs(fadedParts) do
		if not keep[part] then
			if part.Parent then
				part.LocalTransparencyModifier = 0
			end
			fadedParts[part] = nil
		end
	end
end

local function enter()
	if active then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	active = true
	anchor = root.Position
	yawOffset = 0
	pitch = 0.3
	smoothPosition = nil
	gui.Enabled = true

	local camera = workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

local function leave()
	if not active then return end
	active = false
	anchor = nil
	gui.Enabled = false
	restoreFaded()

	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = baseFov
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function sync()
	local character = player.Character
	if not character then
		leave()
		return
	end
	if character:GetAttribute("Benched") == true then
		enter()
	else
		leave()
	end
end

player.CharacterAdded:Connect(function(character)
	leave()
	task.wait(0.2)
	character:GetAttributeChangedSignal("Benched"):Connect(sync)
	sync()
end)

if player.Character then
	player.Character:GetAttributeChangedSignal("Benched"):Connect(sync)
	sync()
end

resetButton.Activated:Connect(function()
	distance = 15
	height = 8
	fov = 62
	pitch = 0.3
	yawOffset = 0
	smoothPosition = nil
	updateReadout()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not active or processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		lastPointer = input.Position
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		lastPointer = nil
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		distance = math.clamp(distance - input.Position.Z * 2, MIN_DISTANCE, MAX_DISTANCE)
		updateReadout()
		return
	end

	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local position = input.Position
		if lastPointer then
			local delta = position - lastPointer
			yawOffset -= delta.X * 0.006
			pitch = math.clamp(pitch + delta.Y * 0.004, -0.15, 1.15)
		end
		lastPointer = position
	end
end)

local aliveTimer = 0
RunService.RenderStepped:Connect(function(dt)
	if not active then return end
	local camera = workspace.CurrentCamera
	if not camera then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		anchor = root.Position
	end
	if not anchor then return end

	local toCourt = Vector3.new(0, 4, 0) - anchor
	local baseYaw = math.atan2(-toCourt.X, -toCourt.Z)
	local yaw = baseYaw + yawOffset
	local horizontal = Vector3.new(math.sin(yaw), 0, math.cos(yaw)) * math.max(distance, MIN_DISTANCE)
	local wanted = anchor + horizontal + Vector3.new(0, math.max(height, MIN_HEIGHT) + pitch * 6, 0)

	if not smoothPosition then smoothPosition = wanted end
	smoothPosition = smoothPosition:Lerp(wanted, math.clamp(dt * 7, 0, 1))

	local lookAt = anchor + toCourt * 0.55 + Vector3.new(0, 2, 0)
	camera.CFrame = CFrame.lookAt(smoothPosition, lookAt)
	camera.FieldOfView = fov
	fadeOwnAvatar(camera.CFrame.Position)

	aliveTimer += dt
	if aliveTimer >= 0.4 then
		aliveTimer = 0
		local blue, red = 0, 0
		for _, model in ipairs(CollectionService:GetTagged("DodgeballActor")) do
			if model:IsA("Model") and model:GetAttribute("Benched") ~= true
				and model:GetAttribute("Ragdolled") ~= true then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local team = model:GetAttribute("Team")
					if team == 1 then blue += 1 elseif team == 2 then red += 1 end
				end
			end
		end
		blueTag.Text = "BLUE " .. blue
		redTag.Text = "RED " .. red
	end
end)

print("[BenchCamera] external seat view, orbit and distance, avatar faded when close")

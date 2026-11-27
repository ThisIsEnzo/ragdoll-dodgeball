-- SpectatorController: seated bench camera with free look.
-- The camera stays at the eliminated player's own head; it never chases another actor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))

local player = Players.LocalPlayer
local seated = false
local draggingMouse = false
local activeTouch = nil
local yaw = 0
local pitch = 0
local sensitivity = 0.0028

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE = Color3.fromRGB(18, 25, 48)
local DIM = Color3.fromRGB(158, 174, 210)
local AMBER = Color3.fromRGB(255, 190, 0)

local gui = Instance.new("ScreenGui")
gui.Name = "RDBenchCamera"
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
	Size = UDim2.fromOffset(390, 64),
	Position = UDim2.new(0.5, 0, 0, 26),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 13) }, bar)
make("UIStroke", { Color = AMBER, Thickness = 1.5, Transparency = 0.35 }, bar)

make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 25),
	Position = UDim2.fromOffset(12, 7),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 18,
	TextColor3 = AMBER,
	Text = "ON THE BENCH",
}, bar)

make("TextLabel", {
	Size = UDim2.new(1, -24, 0, 18),
	Position = UDim2.fromOffset(12, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = DIM,
	Text = "DRAG TO LOOK AROUND  ·  BACK IN PLAY NEXT ROUND",
}, bar)

local aliveStrip = make("Frame", {
	Size = UDim2.fromOffset(390, 28),
	Position = UDim2.new(0.5, 0, 0, 98),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui)

local blueCount = make("TextLabel", {
	Size = UDim2.fromOffset(184, 28),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Font = Enum.Font.FredokaOne,
	TextSize = 12,
	TextColor3 = CFG.Teams[1].color,
	Text = "BLUE  0 ALIVE",
}, aliveStrip)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, blueCount)

local redCount = make("TextLabel", {
	Size = UDim2.fromOffset(184, 28),
	Position = UDim2.fromOffset(206, 0),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Font = Enum.Font.FredokaOne,
	TextSize = 12,
	TextColor3 = CFG.Teams[2].color,
	Text = "RED  0 ALIVE",
}, aliveStrip)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, redCount)

local function currentHead()
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function enter()
	if seated then return end
	local head = currentHead()
	if not head then return end

	local look = head.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = 0
	seated = true
	gui.Enabled = true

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 70
	end
end

local function leave()
	if not seated then return end
	seated = false
	gui.Enabled = false
	draggingMouse = false
	activeTouch = nil

	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then camera.CameraSubject = humanoid end
	end
end

local function sync()
	local character = player.Character
	if not character then leave() return end
	if character:GetAttribute("Benched") == true
		and character:GetAttribute("BenchSeated") == true then
		enter()
	else
		leave()
	end
end

local function watchCharacter(character)
	leave()
	character:GetAttributeChangedSignal("Benched"):Connect(sync)
	character:GetAttributeChangedSignal("BenchSeated"):Connect(sync)
	task.defer(sync)
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) end

UserInputService.InputBegan:Connect(function(input, processed)
	if not seated or processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingMouse = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		activeTouch = input
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingMouse = false
	elseif activeTouch and input == activeTouch then
		activeTouch = nil
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not seated then return end
	if draggingMouse and input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * sensitivity
		pitch = math.clamp(pitch - input.Delta.Y * sensitivity, math.rad(-55), math.rad(55))
	elseif activeTouch and input == activeTouch then
		yaw -= input.Delta.X * sensitivity * 1.5
		pitch = math.clamp(pitch - input.Delta.Y * sensitivity * 1.5, math.rad(-55), math.rad(55))
	end
end)

local aliveTimer = 0
RunService.RenderStepped:Connect(function(dt)
	if not seated then return end

	local character = player.Character
	if not character or character:GetAttribute("Benched") ~= true
		or character:GetAttribute("BenchSeated") ~= true then
		leave()
		return
	end

	local head = currentHead()
	local camera = workspace.CurrentCamera
	if not head or not camera then return end

	camera.CameraType = Enum.CameraType.Scriptable
	local origin = head.Position + Vector3.new(0, 0.12, 0)
	local cosPitch = math.cos(pitch)
	local direction = Vector3.new(
		-math.sin(yaw) * cosPitch,
		math.sin(pitch),
		-math.cos(yaw) * cosPitch
	)
	camera.CFrame = CFrame.lookAt(origin, origin + direction)

	aliveTimer += dt
	if aliveTimer >= 0.5 then
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
		blueCount.Text = string.format("BLUE  %d ALIVE", blue)
		redCount.Text = string.format("RED  %d ALIVE", red)
	end
end)

print("[BenchCamera] seated head camera with mouse/touch look")

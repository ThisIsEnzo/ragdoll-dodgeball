-- AimArc: client-side trajectory preview while charging a throw.
-- Additive visualization; uses shared aim-assist and charge state.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local AimAssist = require(Shared:WaitForChild("AimAssist"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local player = Players.LocalPlayer
local InputController = Resolve.Require(player:WaitForChild("PlayerScripts"), "InputController", 20)

local DOT_COUNT = 30
local STEP = 0.045
local MAX_STEPS = 90
local COOL = Color3.fromRGB(120, 200, 255)
local WARM = Color3.fromRGB(255, 190, 0)
local HOT = Color3.fromRGB(255, 70, 60)
local LANDING = Color3.fromRGB(150, 255, 60)

local enabled = true
local visible = false
local folder = Instance.new("Folder")
folder.Name = "RDAimArc"
folder.Parent = workspace

local function makePart(name, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

local dots = {}
for index = 1, DOT_COUNT do
	local dot = makePart("Dot", Vector3.new(0.34, 0.34, 0.34), COOL)
	dot.Shape = Enum.PartType.Ball
	dots[index] = dot
end
local ring = makePart("Landing", Vector3.new(0.16, 4.2, 4.2), LANDING)
ring.Shape = Enum.PartType.Cylinder
local ringInner = makePart("LandingCore", Vector3.new(0.18, 1.5, 1.5), LANDING)
ringInner.Shape = Enum.PartType.Cylinder

local readoutGui = Instance.new("BillboardGui")
readoutGui.Name = "ArcReadout"
readoutGui.Size = UDim2.fromOffset(140, 34)
readoutGui.AlwaysOnTop = false
readoutGui.LightInfluence = 0
readoutGui.MaxDistance = 200
readoutGui.Enabled = false
readoutGui.Parent = ring
local readout = Instance.new("TextLabel")
readout.Size = UDim2.fromScale(1, 1)
readout.BackgroundColor3 = Color3.fromRGB(8, 12, 26)
readout.BackgroundTransparency = 0.25
readout.Font = Enum.Font.FredokaOne
readout.TextSize = 13
readout.TextColor3 = LANDING
readout.TextStrokeTransparency = 0.6
readout.Text = ""
readout.Parent = readoutGui
Instance.new("UICorner", readout).CornerRadius = UDim.new(0, 8)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function chargeFraction()
	if not InputController or typeof(InputController.GetCharge) ~= "function" then return 0 end
	local ok, value = pcall(InputController.GetCharge)
	if not ok or typeof(value) ~= "number" then return 0 end
	return math.clamp(value, 0, 1)
end
local function isCharging()
	if not InputController or typeof(InputController.IsCharging) ~= "function" then return false end
	local ok, value = pcall(InputController.IsCharging)
	return ok and value == true
end
local function speedFor(fraction)
	local raw = math.clamp(fraction * CFG.Throw.ChargeMax, CFG.Throw.ChargeMin, CFG.Throw.ChargeMax)
	local t = math.clamp((raw - CFG.Throw.ChargeMin) / math.max(CFG.Throw.ChargeMax - CFG.Throw.ChargeMin, 1e-6), 0, 1)
	return CFG.Throw.SpeedMin + (CFG.Throw.SpeedMax - CFG.Throw.SpeedMin) * t
end
local function aimDirection()
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	flat = flat.Unit
	local pitch = math.asin(math.clamp(look.Y, -1, 1)) * CFG.Throw.PitchInfluence
	local angle = math.clamp(pitch + math.rad(CFG.Throw.LoftDeg), math.rad(CFG.Throw.MinAngleDeg), math.rad(CFG.Throw.MaxAngleDeg))
	return (flat * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)).Unit
end
local function enemyTargets(character)
	local team = character:GetAttribute("Team")
	local list = {}
	for _, other in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		local otherTeam = other:GetAttribute("Team")
		if other:IsA("Model") and other ~= character and (otherTeam == 1 or otherTeam == 2) and otherTeam ~= team
			and not other:GetAttribute("Benched") and not other:GetAttribute("Ragdolled") then
			local root = other:FindFirstChild("HumanoidRootPart")
			local humanoid = other:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				table.insert(list, { root = root, character = other })
			end
		end
	end
	return list
end
local function hide()
	if not visible then return end
	visible = false
	for _, dot in ipairs(dots) do dot.Transparency = 1 end
	ring.Transparency = 1
	ringInner.Transparency = 1
	readoutGui.Enabled = false
end
local function lerpColor(a, b, t)
	return a:Lerp(b, math.clamp(t, 0, 1))
end
local function draw()
	local character = player.Character
	if not character or character:GetAttribute("Benched") then hide() return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not character:GetAttribute("Carrying") then hide() return end

	local fraction = chargeFraction()
	local speed = speedFor(fraction)
	local origin = root.Position + Vector3.new(0, CFG.Throw.SpawnLift, 0)
	local direction = aimDirection()
	local ballsFolder = workspace:FindFirstChild("Balls")
	local exclude = { character, folder }
	if ballsFolder then table.insert(exclude, ballsFolder) end
	local isMobile = player:GetAttribute("IsMobile") == true
	local ok, adjusted = pcall(function()
		return AimAssist.Adjust(origin, direction, enemyTargets(character), isMobile, exclude)
	end)
	if ok and typeof(adjusted) == "Vector3" and adjusted.Magnitude > 0.01 then direction = adjusted.Unit end

	local launch = origin + direction * CFG.Throw.SpawnOffset
	local velocity = direction * speed
	local gravity = Vector3.new(0, -workspace.Gravity * math.clamp(CFG.Ball.GravityScale, 0.05, 1), 0)
	rayParams.FilterDescendantsInstances = exclude
	local points = {}
	local previous = launch
	local landing, landingNormal
	landingNormal = Vector3.new(0, 1, 0)
	local travelled = 0
	for step = 1, MAX_STEPS do
		local t = step * STEP
		local position = launch + velocity * t + gravity * (0.5 * t * t)
		local segment = position - previous
		local hit = workspace:Raycast(previous, segment, rayParams)
		if hit then
			landing = hit.Position
			landingNormal = hit.Normal
			table.insert(points, hit.Position)
			travelled += (hit.Position - previous).Magnitude
			break
		end
		table.insert(points, position)
		travelled += segment.Magnitude
		previous = position
		if position.Y < -20 then break end
	end
	if #points == 0 then hide() return end
	visible = true
	local hot = lerpColor(COOL, WARM, fraction * 2)
	if fraction > 0.5 then hot = lerpColor(WARM, HOT, (fraction - 0.5) * 2) end
	local spacing = math.max(1, math.floor(#points / DOT_COUNT))
	for index = 1, DOT_COUNT do
		local sourceIndex = index * spacing
		local dot = dots[index]
		if sourceIndex <= #points then
			local position = points[sourceIndex]
			local fade = 1 - (index / DOT_COUNT) * 0.55
			local size = 0.30 + fraction * 0.22
			dot.Size = Vector3.new(size, size, size)
			dot.CFrame = CFrame.new(position)
			dot.Color = hot
			dot.Transparency = math.clamp(0.15 + (1 - fade), 0.1, 0.8)
		else
			dot.Transparency = 1
		end
	end
	if landing then
		local basis = CFrame.lookAt(landing, landing + landingNormal)
		ring.CFrame = basis * CFrame.Angles(0, math.rad(90), 0)
		ringInner.CFrame = ring.CFrame
		local pulse = 0.35 + 0.2 * math.sin(os.clock() * 6)
		ring.Transparency = pulse
		ringInner.Transparency = pulse + 0.2
		ring.Color = LANDING
		ringInner.Color = LANDING
		readout.Text = string.format("%d studs  ·  %d spd", math.floor(travelled), math.floor(speed))
		readoutGui.Enabled = true
	else
		ring.Transparency = 1
		ringInner.Transparency = 1
		readoutGui.Enabled = false
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "RDAimArcUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 8
gui.Parent = player:WaitForChild("PlayerGui")
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(112, 26)
toggle.Position = UDim2.new(1, -12, 1, -178)
toggle.AnchorPoint = Vector2.new(1, 1)
toggle.Font = Enum.Font.FredokaOne
toggle.TextSize = 11
toggle.BorderSizePixel = 0
toggle.Parent = gui
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 7)
local function refreshToggle()
	if enabled then
		toggle.Text = "AIM ARC  T"
		toggle.BackgroundColor3 = LANDING
		toggle.TextColor3 = Color3.fromRGB(10, 28, 6)
	else
		toggle.Text = "ARC OFF  T"
		toggle.BackgroundColor3 = Color3.fromRGB(60, 68, 100)
		toggle.TextColor3 = Color3.fromRGB(214, 224, 245)
	end
end
toggle.Activated:Connect(function()
	enabled = not enabled
	if not enabled then hide() end
	refreshToggle()
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.T then
		enabled = not enabled
		if not enabled then hide() end
		refreshToggle()
	end
end)
refreshToggle()
RunService.RenderStepped:Connect(function()
	if not enabled then hide() return end
	if isCharging() then draw() else hide() end
end)
print("[AimArc] trajectory preview ready, T toggles")

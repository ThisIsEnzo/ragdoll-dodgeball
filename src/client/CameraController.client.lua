-- CameraController: nothing sits between you and your character.
--
-- Rebuild-safe: MapService replaces the entire WorldDecor folder, so this
-- watches Workspace.ChildAdded and re-registers instead of holding a dead
-- reference. SurfaceGuis on occluders are disabled too, because a GUI does
-- not fade with its host part.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

local fadedParts = {}
local disabledGuis = {}
local sceneParts = {}
local registeredRoot = nil

local function register()
	table.clear(sceneParts)
	local roots = {}
	local decor = workspace:FindFirstChild("WorldDecor")
	if decor then table.insert(roots, decor) registeredRoot = decor end
	local arena = workspace:FindFirstChild("Arena")
	if arena then table.insert(roots, arena) end

	for _, root in ipairs(roots) do
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("BasePart") then
				item.CanQuery = true
				table.insert(sceneParts, item)
			end
		end
	end
end

local function hidePart(part)
	if not part.Parent then return end
	part.LocalTransparencyModifier = 1
	fadedParts[part] = true
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceGui") or child:IsA("BillboardGui") then
			if child.Enabled then
				child.Enabled = false
				disabledGuis[child] = true
			end
		end
	end
end

local function restoreAll()
	for part in pairs(fadedParts) do
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
	for gui in pairs(disabledGuis) do
		if gui.Parent then gui.Enabled = true end
	end
	table.clear(fadedParts)
	table.clear(disabledGuis)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "WorldDecor" then
		task.wait(0.35)
		restoreAll()
		register()
	end
end)

local staleCheck = 0
RunService.RenderStepped:Connect(function(dt)
	staleCheck += dt
	if staleCheck > 1 then
		staleCheck = 0
		local decor = workspace:FindFirstChild("WorldDecor")
		if decor ~= registeredRoot then
			restoreAll()
			register()
		end
	end

	local camera = workspace.CurrentCamera
	local character = player.Character
	if not camera or not character then restoreAll() return end

	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then restoreAll() return end

	local keep = {}

	local ok, blockers = pcall(function()
		return camera:GetPartsObscuringTarget({ head.Position }, { character })
	end)
	if ok and typeof(blockers) == "table" then
		for _, part in ipairs(blockers) do
			if part:IsA("BasePart") and not part:IsDescendantOf(character) then
				keep[part] = true
				hidePart(part)
			end
		end
	end

	local camPos = camera.CFrame.Position
	local toHead = head.Position - camPos
	local dist = toHead.Magnitude
	local dir = Vector3.new(0, 0, -1)
	if dist > 0.1 then dir = toHead.Unit end

	for _, part in ipairs(sceneParts) do
		if part.Parent and not keep[part] then
			local offset = part.Position - camPos
			local along = offset:Dot(dir)
			if along > -12 and along < dist + 4 then
				local closest = camPos + dir * math.clamp(along, 0, dist)
				local gap = (part.Position - closest).Magnitude
				local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
				if gap < radius + 6 then
					keep[part] = true
					hidePart(part)
				end
			end
		end
	end

	for part in pairs(fadedParts) do
		if not keep[part] then
			if part.Parent then part.LocalTransparencyModifier = 0 end
			fadedParts[part] = nil
		end
	end
	for gui in pairs(disabledGuis) do
		local host = gui.Parent
		if not host or not keep[host] then
			if gui.Parent then gui.Enabled = true end
			disabledGuis[gui] = nil
		end
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "RDCamera"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 7
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local strip = make("Frame", {
	Size = UDim2.fromOffset(240, 46),
	Position = UDim2.new(1, -16, 1, -190),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, strip)

local function cell(x, width, label)
	local frame = make("Frame", {
		Size = UDim2.fromOffset(width, 34),
		Position = UDim2.fromOffset(x, 6),
		BackgroundColor3 = Color3.fromRGB(28, 36, 62),
		BorderSizePixel = 0,
	}, strip)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	local text = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 13,
		Text = label,
	}, frame)
	return frame, text
end

local ultFrame, ultText = cell(6, 112, "ULT 0%")
local dodgeFrame, dodgeText = cell(124, 110, "DODGE READY")

local hypeValue, hypeMax = 0, CFG.Hype.Max
local hype = Net.Get("HypeState")
if hype then
	hype.OnClientEvent:Connect(function(value, max)
		hypeValue = value or 0
		hypeMax = max or CFG.Hype.Max
	end)
end

RunService.Heartbeat:Connect(function()
	local ratio = math.clamp(hypeValue / math.max(hypeMax, 1), 0, 1)
	if ratio >= 1 then
		ultText.Text = "ULT READY  Q"
		ultFrame.BackgroundColor3 = Color3.fromRGB(255, 79, 216)
		ultText.TextColor3 = Color3.fromRGB(28, 4, 24)
	else
		ultText.Text = string.format("ULT %d%%", math.floor(ratio * 100))
		ultFrame.BackgroundColor3 = Color3.fromRGB(28, 36, 62)
		ultText.TextColor3 = Color3.fromRGB(180, 194, 224)
	end

	local readyAt = player:GetAttribute("DodgeReadyAt")
	local left = 0
	if typeof(readyAt) == "number" then left = math.max(0, readyAt - os.clock()) end
	if left <= 0 then
		dodgeText.Text = "DODGE  SHIFT"
		dodgeFrame.BackgroundColor3 = Color3.fromRGB(46, 155, 255)
		dodgeText.TextColor3 = Color3.fromRGB(6, 20, 36)
	else
		dodgeText.Text = string.format("DODGE %.1fs", left)
		dodgeFrame.BackgroundColor3 = Color3.fromRGB(28, 36, 62)
		dodgeText.TextColor3 = Color3.fromRGB(180, 194, 224)
	end
end)

task.spawn(function()
	workspace:WaitForChild("WorldDecor", 40)
	task.wait(0.4)
	register()
end)

register()
print("[Camera] rebuild-safe occlusion, SurfaceGuis hidden with their host")
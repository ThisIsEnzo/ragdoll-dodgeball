-- CameraController: walls stop blocking the view.
--
-- Root cause of the previous failure: every decorative part was created with
-- CanQuery = false, and GetPartsObscuringTarget is a spatial query. The pads
-- and barriers were invisible to it, so nothing was ever faded. This script
-- re-enables CanQuery locally on scene geometry, then fades occluders.
--
-- A proximity pass covers the case where the camera ends up inside a part,
-- which produces no ray hit at all. LocalTransparencyModifier is client-only,
-- so other players still see solid walls.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

local faded = {}
local occluders = {}
local NEAR_RADIUS = 16

local function sceneRoots()
	local list = {}
	local decor = workspace:FindFirstChild("WorldDecor")
	if decor then table.insert(list, decor) end
	local arena = workspace:FindFirstChild("Arena")
	if arena then table.insert(list, arena) end
	return list
end

local function register()
	table.clear(occluders)
	for _, root in ipairs(sceneRoots()) do
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("BasePart") then
				-- spatial queries skip CanQuery=false parts; restore it locally
				item.CanQuery = true
				local s = item.Size
				local big = (s.X * s.Y * s.Z) > 24
				if big and item.Transparency < 0.9 then
					table.insert(occluders, item)
				end
			end
		end
	end
end

local function restoreAll()
	for part in pairs(faded) do
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
	table.clear(faded)
end

local function fade(part)
	if not part.Parent then return end
	part.LocalTransparencyModifier = 1
	faded[part] = true
end

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	local character = player.Character
	if not camera or not character then restoreAll() return end

	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then restoreAll() return end

	local current = {}

	local ok, blockers = pcall(function()
		return camera:GetPartsObscuringTarget({ head.Position }, { character })
	end)
	if ok and typeof(blockers) == "table" then
		for _, part in ipairs(blockers) do
			if part:IsA("BasePart") and not part:IsDescendantOf(character) then
				current[part] = true
				fade(part)
			end
		end
	end

	-- camera inside or hugging geometry: no ray hit, so fade by proximity
	local camPos = camera.CFrame.Position
	local toHead = head.Position - camPos
	local dist = toHead.Magnitude
	local dir = if dist > 0.1 then toHead.Unit else Vector3.new(0, 0, -1)

	for _, part in ipairs(occluders) do
		if part.Parent and not current[part] then
			local offset = part.Position - camPos
			local along = offset:Dot(dir)
			if along > -6 and along < dist + 6 then
				local closest = camPos + dir * math.clamp(along, 0, dist)
				local gap = (part.Position - closest).Magnitude
				local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
				if gap < radius + NEAR_RADIUS * 0.35 then
					current[part] = true
					fade(part)
				end
			end
		end
	end

	for part in pairs(faded) do
		if not current[part] then
			if part.Parent then part.LocalTransparencyModifier = 0 end
			faded[part] = nil
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Half-court warning + ability readiness strip
-- ---------------------------------------------------------------------------

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

local warning = make("TextLabel", {
	Size = UDim2.fromOffset(360, 34),
	Position = UDim2.new(0.5, 0, 0, 150),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(30, 12, 12),
	BackgroundTransparency = 0.15,
	Font = Enum.Font.FredokaOne,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(255, 140, 120),
	Text = "YOUR HALF ONLY â€” PUSHED BACK",
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, warning)
make("UIStroke", { Color = Color3.fromRGB(255, 58, 58), Thickness = 2, Transparency = 0.3 }, warning)

local warnUntil = 0
local fx = Net.Get("FXEvent")
if fx then
	fx.OnClientEvent:Connect(function(kind)
		if kind == "halfwarn" then
			warnUntil = os.clock() + 1.2
			warning.Visible = true
		end
	end)
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
	if warning.Visible and os.clock() > warnUntil then
		warning.Visible = false
	end

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
	local decor = workspace:FindFirstChild("WorldDecor")
	if decor then
		decor:GetAttributeChangedSignal("Theme"):Connect(function()
			task.wait(0.6)
			restoreAll()
			register()
		end)
	end
end)

register()
print("[Camera] occlusion fixed: CanQuery restored, proximity pass active")
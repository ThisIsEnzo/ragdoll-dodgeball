-- CameraController: fades anything that blocks the view of your character.
-- Audit fix: standing near a wall put the camera behind opaque geometry and
-- the screen went blank. LocalTransparencyModifier is client-only, so fading
-- here does not change what other players see.
-- Also hosts the ability readiness strip so ULT and DODGE stop feeling dead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local faded = {}

local function restoreAll()
	for part in pairs(faded) do
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
	table.clear(faded)
end

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	local character = player.Character
	if not camera or not character then restoreAll() return end

	local subject = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not subject then restoreAll() return end

	local ok, blockers = pcall(function()
		return camera:GetPartsObscuringTarget({ subject.Position, camera.CFrame.Position }, { character })
	end)
	if not ok or typeof(blockers) ~= "table" then return end

	local current = {}
	for _, part in ipairs(blockers) do
		if part:IsA("BasePart") and not part:IsDescendantOf(character) then
			local tagged = part:FindFirstAncestor("WorldDecor") or part:FindFirstAncestor("Arena")
			if tagged then
				current[part] = true
				part.LocalTransparencyModifier = 1
				faded[part] = true
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

local gui = Instance.new("ScreenGui")
gui.Name = "RDCamera"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 7
gui.Parent = player:WaitForChild("PlayerGui")

local strip = Instance.new("Frame")
strip.Size = UDim2.fromOffset(240, 46)
strip.Position = UDim2.new(1, -16, 1, -190)
strip.AnchorPoint = Vector2.new(1, 1)
strip.BackgroundColor3 = Color3.fromRGB(12, 18, 36)
strip.BackgroundTransparency = 0.2
strip.BorderSizePixel = 0
strip.Parent = gui
Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 10)

local function cell(x, width, label)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(width, 34)
	frame.Position = UDim2.fromOffset(x, 6)
	frame.BackgroundColor3 = Color3.fromRGB(28, 36, 62)
	frame.BorderSizePixel = 0
	frame.Parent = strip
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 13
	text.Text = label
	text.Parent = frame
	return frame, text
end

local ultFrame, ultText = cell(6, 112, "ULT 0%")
local dodgeFrame, dodgeText = cell(124, 110, "DODGE READY")

local hypeValue, hypeMax = 0, CFG.Hype.Max

RunService.RenderStepped:Connect(function()
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
	if typeof(readyAt) == "number" then
		left = math.max(0, readyAt - os.clock())
	end
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

local hype = Net.Get("HypeState")
if hype then
	hype.OnClientEvent:Connect(function(value, max)
		hypeValue = value or 0
		hypeMax = max or CFG.Hype.Max
	end)
end

print("[Camera] occlusion fade + ability strip live")
-- QualityController: one visible toggle for render cost.
-- HIGH keeps Future lighting, bloom, sun rays and the crowd.
-- LOW drops to ShadowMap, disables post effects and hides the crowd.
-- Touch devices without a keyboard start on LOW.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "RDQuality"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(96, 32)
button.Position = UDim2.new(1, -16, 0, 60)
button.AnchorPoint = Vector2.new(1, 0)
button.Font = Enum.Font.FredokaOne
button.TextSize = 13
button.BorderSizePixel = 0
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 9)
corner.Parent = button

local high = true

local function setEffect(name, enabled)
	local effect = Lighting:FindFirstChild(name)
	if effect then effect.Enabled = enabled end
end

local function apply()
	if high then
		Lighting.Technology = Enum.Technology.Future
		Lighting.GlobalShadows = true
		setEffect("RDBloom", true)
		setEffect("RDRays", true)
		button.Text = "HIGH"
		button.BackgroundColor3 = Color3.fromRGB(124, 255, 79)
		button.TextColor3 = Color3.fromRGB(8, 24, 10)
	else
		Lighting.Technology = Enum.Technology.ShadowMap
		Lighting.GlobalShadows = false
		setEffect("RDBloom", false)
		setEffect("RDRays", false)
		button.Text = "LOW"
		button.BackgroundColor3 = Color3.fromRGB(70, 78, 112)
		button.TextColor3 = Color3.fromRGB(226, 234, 252)
	end

	local decor = Workspace:FindFirstChild("WorldDecor")
	if decor then
		local crowd = decor:FindFirstChild("Crowd")
		if crowd then
			for _, item in ipairs(crowd:GetDescendants()) do
				if item:IsA("BasePart") then
					item.Transparency = if high then 0 else 1
				end
			end
		end
	end
end

button.Activated:Connect(function()
	high = not high
	apply()
end)

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	high = false
end

task.spawn(function()
	Workspace:WaitForChild("WorldDecor", 30)
	apply()
end)

apply()
print("[Quality] toggle ready, starts on " .. (if high then "HIGH" else "LOW"))
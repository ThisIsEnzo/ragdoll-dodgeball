-- QualityController: render cost toggle.
-- Audit fix: this script used to assign Lighting.Technology, which is a
-- protected property. The write threw, apply() aborted, and the button kept
-- its default "Button" label. Technology is now left to the place settings.

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
gui.DisplayOrder = 11
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(96, 32)
button.Position = UDim2.new(1, -16, 0, 60)
button.AnchorPoint = Vector2.new(1, 0)
button.Font = Enum.Font.FredokaOne
button.TextSize = 13
button.BorderSizePixel = 0
button.Text = "HIGH"
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)

local high = true
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	high = false
end

local function setEffect(name, enabled)
	local effect = Lighting:FindFirstChild(name)
	if effect then effect.Enabled = enabled end
end

local function apply()
	Lighting.GlobalShadows = high
	setEffect("RDBloom", high)
	setEffect("RDRays", high)

	if high then
		button.Text = "HIGH"
		button.BackgroundColor3 = Color3.fromRGB(150, 255, 60)
		button.TextColor3 = Color3.fromRGB(10, 28, 6)
	else
		button.Text = "LOW"
		button.BackgroundColor3 = Color3.fromRGB(120, 136, 166)
		button.TextColor3 = Color3.fromRGB(240, 246, 255)
	end

	local decor = Workspace:FindFirstChild("WorldDecor")
	local crowd = decor and decor:FindFirstChild("Crowd")
	if crowd then
		for _, item in ipairs(crowd:GetDescendants()) do
			if item:IsA("BasePart") then
				if high then
					item.LocalTransparencyModifier = 0
				else
					item.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

button.Activated:Connect(function()
	high = not high
	apply()
end)

task.spawn(function()
	Workspace:WaitForChild("WorldDecor", 30)
	apply()
end)

apply()
print("[Quality] toggle live")
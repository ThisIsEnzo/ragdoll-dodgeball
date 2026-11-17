-- DebugOverlay: живое состояние боя на экране, чтобы не отлаживать вслепую.
-- F9 включает панель: стойка ловли, ближайший мяч, пинг, команда.
-- Отдельный LocalScript: не правит существующие файлы.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Stats = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "RDDebug"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(340, 200)
label.Position = UDim2.fromOffset(16, 130)
label.BackgroundColor3 = Color3.fromRGB(8, 12, 26)
label.BackgroundTransparency = 0.15
label.BorderSizePixel = 0
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextColor3 = Color3.fromRGB(124, 255, 79)
label.Text = ""
label.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingTop = UDim.new(0, 6)
padding.Parent = label

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F9 then
		gui.Enabled = not gui.Enabled
	end
end)

local function nearestBall(root)
	local best, bestDistance = nil, math.huge
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace)
			and not ball:GetAttribute("HeldBy") then
			local d = (ball.Position - root.Position).Magnitude
			if d < bestDistance then best, bestDistance = ball, d end
		end
	end
	return best, bestDistance
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		label.Text = "no character"
		return
	end

	local attempt = player:GetAttribute("CatchAttemptAt")
	local stanceLeft = 0
	if typeof(attempt) == "number" then
		stanceLeft = math.max(0, CFG.Catch.StanceSeconds - (os.clock() - attempt))
	end

	local ball, distance = nearestBall(root)
	local ping = 0
	pcall(function()
		ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)

	local lines = {
		string.format("team     %s", tostring(character:GetAttribute("Team"))),
		string.format("benched  %s", tostring(character:GetAttribute("Benched"))),
		string.format("carrying %s", tostring(character:GetAttribute("Carrying"))),
		string.format("STANCE   %.2fs", stanceLeft),
		string.format("ping     %d ms", math.floor(ping)),
	}
	if ball then
		table.insert(lines, string.format("ball dst %.1f", distance))
		table.insert(lines, string.format("ball spd %d", math.floor(ball.AssemblyLinearVelocity.Magnitude)))

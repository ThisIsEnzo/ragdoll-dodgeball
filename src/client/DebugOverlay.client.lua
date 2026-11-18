-- DebugOverlay: Ð¶Ð¸Ð²Ð¾Ðµ ÑÐ¾ÑÑ‚Ð¾ÑÐ½Ð¸Ðµ Ð±Ð¾Ñ Ð½Ð° ÑÐºÑ€Ð°Ð½Ðµ. F9 Ð²ÐºÐ»ÑŽÑ‡Ð°ÐµÑ‚ Ð¿Ð°Ð½ÐµÐ»ÑŒ.
-- ÐŸÐ¾ÐºÐ°Ð·Ñ‹Ð²Ð°ÐµÑ‚ ÑÑ‚Ð¾Ð¹ÐºÑƒ Ð»Ð¾Ð²Ð»Ð¸, Ð±Ð»Ð¸Ð¶Ð°Ð¹ÑˆÐ¸Ð¹ Ð¼ÑÑ‡, Ð¿Ð¸Ð½Ð³, ÐºÐ¾Ð¼Ð°Ð½Ð´Ñƒ.

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
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(340, 210)
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
	local best = nil
	local bestDistance = math.huge
	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") and ball:IsDescendantOf(workspace) then
			if not ball:GetAttribute("HeldBy") then
				local distance = (ball.Position - root.Position).Magnitude
				if distance < bestDistance then
					best = ball
					bestDistance = distance
				end
			end
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

	local stanceLeft = 0
	local attempt = player:GetAttribute("CatchAttemptAt")
	if typeof(attempt) == "number" then
		stanceLeft = math.max(0, CFG.Catch.StanceSeconds - (os.clock() - attempt))
	end

	local ping = 0
	pcall(function()
		ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)

	local lines = {}
	table.insert(lines, string.format("team     %s", tostring(character:GetAttribute("Team"))))
	table.insert(lines, string.format("benched  %s", tostring(character:GetAttribute("Benched"))))
	table.insert(lines, string.format("carrying %s", tostring(character:GetAttribute("Carrying"))))
	table.insert(lines, string.format("STANCE   %.2fs", stanceLeft))
	table.insert(lines, string.format("ult      %s", tostring(player:GetAttribute("SelectedUlt"))))
	table.insert(lines, string.format("ping     %d ms", math.floor(ping)))

	local ball, distance = nearestBall(root)
	if ball then
		table.insert(lines, string.format("ball dst %.1f", distance))
		table.insert(lines, string.format("ball spd %d", math.floor(ball.AssemblyLinearVelocity.Magnitude)))
		table.insert(lines, string.format("CLEAN    %s", tostring(ball:GetAttribute("Clean"))))
	else
		table.insert(lines, "no free ball")
	end

	label.Text = table.concat(lines, "\n")
end)

print("[DebugOverlay] F9 toggles combat state")
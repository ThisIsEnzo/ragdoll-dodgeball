-- Personal match summary UI. All rewards and stats are display-only profile deltas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SummaryRemotes", 30)
if not remotes then
	warn("[MatchSummary] SummaryRemotes was not created")
	return
end
local summaryRemote = remotes:WaitForChild("MatchSummary", 30)
local netFolder = ReplicatedStorage:WaitForChild("Remotes", 30)
local rematchRemote = netFolder and netFolder:WaitForChild("RematchRequest", 10)
if not summaryRemote then return end

local COLORS = {
	bg = Color3.fromRGB(13, 18, 32),
	panel = Color3.fromRGB(22, 30, 49),
	line = Color3.fromRGB(52, 68, 96),
	text = Color3.fromRGB(242, 246, 255),
	muted = Color3.fromRGB(155, 169, 194),
	green = Color3.fromRGB(150, 255, 110),
	blue = Color3.fromRGB(80, 170, 255),
	gold = Color3.fromRGB(255, 202, 85),
	red = Color3.fromRGB(255, 100, 105),
}

local gui
local currentConnection
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness)
	make("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = 0.25 }, parent)
end

local function label(parent, text, size, color, font)
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Font = font or Enum.Font.GothamBold,
		Text = text,
		TextColor3 = color or COLORS.text,
		TextSize = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end

local function animateNumber(targetLabel, target, prefix, suffix)
	target = math.max(0, math.floor(tonumber(target) or 0))
	local started = os.clock()
	local duration = 0.65
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		targetLabel.Text = (prefix or "") .. tostring(math.floor(target * eased + 0.5)) .. (suffix or "")
		if alpha >= 1 then
			targetLabel.Text = (prefix or "") .. tostring(target) .. (suffix or "")
			connection:Disconnect()
		end
	end)
	return connection
end

local function showSummary(data)
	if gui then gui:Destroy() end
	if currentConnection then currentConnection:Disconnect() currentConnection = nil end

	gui = make("ScreenGui", {
		Name = "PersonalMatchSummary",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
	}, player:WaitForChild("PlayerGui"))

	local scale = make("UIScale", { Scale = 1 }, nil)
	scale.Parent = nil
	local root = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(470, 540),
		BackgroundColor3 = COLORS.bg,
		BackgroundTransparency = 0.04,
	}, gui)
	corner(root, 18)
	stroke(root, COLORS.line, 1.5)
	local uiScale = make("UIScale", { Scale = 1 }, root)
	local function updateScale()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		uiScale.Scale = math.min(1, viewport.X / 510, viewport.Y / 580)
	end
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 94),
		BackgroundColor3 = data.result == "WIN" and Color3.fromRGB(22, 62, 54) or Color3.fromRGB(57, 35, 48),
	}, root)
	corner(header, 18)
	local title = label(header, data.result == "WIN" and "VICTORY!" or "MATCH COMPLETE", 28,
		data.result == "WIN" and COLORS.green or COLORS.gold)
	title.Position = UDim2.fromOffset(22, 14)
	title.Size = UDim2.new(1, -44, 0, 38)
	local score = label(header, string.format("BLUE  %d   —   %d  RED", data.score.blue or 0, data.score.red or 0), 13, COLORS.muted, Enum.Font.Gotham)
	score.Position = UDim2.fromOffset(23, 54)
	score.Size = UDim2.new(1, -46, 0, 22)

	local statsPanel = make("Frame", {
		Position = UDim2.fromOffset(18, 108),
		Size = UDim2.new(1, -36, 0, 168),
		BackgroundColor3 = COLORS.panel,
	}, root)
	corner(statsPanel, 12)
	label(statsPanel, "YOUR PERFORMANCE", 12, COLORS.muted).Position = UDim2.fromOffset(14, 9)
	local statItems = {
		{ "KNOCKOUTS", data.stats.kos or 0 },
		{ "CATCHES", data.stats.catches or 0 },
		{ "REVIVES", data.stats.revives or 0 },
		{ "THROWS", data.stats.throws or 0 },
		{ "ROUND WINS", data.stats.roundWins or 0 },
	}
	for index, item in ipairs(statItems) do
		local col = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local x = 14 + col * 205
		local y = 36 + row * 42
		local name = label(statsPanel, item[1], 10, COLORS.muted, Enum.Font.Gotham)
		name.Position = UDim2.fromOffset(x, y)
		name.Size = UDim2.fromOffset(140, 16)
		local value = label(statsPanel, "0", 20, COLORS.text)
		value.Position = UDim2.fromOffset(x, y + 15)
		value.Size = UDim2.fromOffset(150, 24)
		animateNumber(value, item[2])
	end

	local rewards = make("Frame", {
		Position = UDim2.fromOffset(18, 286),
		Size = UDim2.new(1, -36, 0, 94),
		BackgroundColor3 = COLORS.panel,
	}, root)
	corner(rewards, 12)
	label(rewards, "MATCH REWARDS", 12, COLORS.muted).Position = UDim2.fromOffset(14, 8)
	local coinTitle = label(rewards, "COINS", 10, COLORS.gold, Enum.Font.Gotham)
	coinTitle.Position = UDim2.fromOffset(16, 35)
	local coinValue = label(rewards, "+0", 24, COLORS.gold)
	coinValue.Position = UDim2.fromOffset(16, 50)
	coinValue.Size = UDim2.fromOffset(175, 32)
	animateNumber(coinValue, data.rewards.coins or 0, "+")
	local xpTitle = label(rewards, "XP EARNED", 10, COLORS.blue, Enum.Font.Gotham)
	xpTitle.Position = UDim2.fromOffset(225, 35)
	local xpValue = label(rewards, "+0", 24, COLORS.blue)
	xpValue.Position = UDim2.fromOffset(225, 50)
	xpValue.Size = UDim2.fromOffset(175, 32)
	animateNumber(xpValue, data.rewards.xp or 0, "+")

	local levelPanel = make("Frame", {
		Position = UDim2.fromOffset(18, 390),
		Size = UDim2.new(1, -36, 0, 64),
		BackgroundColor3 = COLORS.panel,
	}, root)
	corner(levelPanel, 12)
	local levelText = label(levelPanel,
		string.format("LEVEL %d%s", data.level.after or 1,
			(data.rewards.levels or 0) > 0 and ("  (+" .. tostring(data.rewards.levels) .. ")") or ""),
		14, COLORS.text)
	levelText.Position = UDim2.fromOffset(14, 7)
	levelText.Size = UDim2.new(1, -28, 0, 20)
	local progressBack = make("Frame", {
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 10),
		BackgroundColor3 = Color3.fromRGB(8, 12, 22),
	}, levelPanel)
	corner(progressBack, 5)
	local progress = make("Frame", {
		Size = UDim2.new(math.clamp((data.level.xp or 0) / math.max(1, data.level.xpToNext or 1), 0, 1), 0, 1, 0),
		BackgroundColor3 = COLORS.blue,
	}, progressBack)
	corner(progress, 5)

	local rank = data.rank or {}
	local rankPanel = make("Frame", {
		Position = UDim2.fromOffset(18, 462),
		Size = UDim2.new(1, -36, 0, 34),
		BackgroundTransparency = 1,
	}, root)
	local rankText = label(rankPanel, "RANK  " .. tostring(rank.name or "BRONZE")
		.. (rank.nextName and ("  •  " .. tostring(rank.wins) .. "/" .. tostring(rank.nextWins) .. " to " .. rank.nextName) or "  •  MAX RANK"),
		12, rank.color or COLORS.gold)
	rankText.Size = UDim2.new(1, 0, 1, 0)

	local buttons = make("Frame", {
		Position = UDim2.fromOffset(18, 500),
		Size = UDim2.new(1, -36, 0, 34),
		BackgroundTransparency = 1,
	}, root)
	local again = make("TextButton", {
		Size = UDim2.new(0.68, -5, 1, 0),
		BackgroundColor3 = Color3.fromRGB(54, 126, 92),
		Text = "PLAY AGAIN",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		AutoButtonColor = true,
	}, buttons)
	corner(again, 9)
	local close = make("TextButton", {
		Position = UDim2.new(0.68, 5, 0, 0),
		Size = UDim2.new(0.32, -5, 1, 0),
		BackgroundColor3 = COLORS.line,
		Text = "CLOSE",
		TextColor3 = COLORS.text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
	}, buttons)
	corner(close, 9)

	again.Activated:Connect(function()
		again.Active = false
		again.Text = "QUEUED"
		if rematchRemote then rematchRemote:FireServer() end
	end)
	close.Activated:Connect(function()
		if gui then gui:Destroy() gui = nil end
	end)

	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(450, 520)
	TweenService:Create(root, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.04,
	}):Play()
end

summaryRemote.OnClientEvent:Connect(showSummary)

-- HUDController v0.5.0: все игроцкие строки через Strings (EN forced).
-- Добавлены: уровень с XP-полосой, монеты, панель дейли-квестов, попап LEVEL UP,
-- предупреждение PROGRESS NOT SAVED в memory-mode.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))
local Strings = require(Shared:WaitForChild("Strings"))

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local InputController = Resolve.Require(PlayerScripts, "InputController")

local HUDController = {}

local gui, scoreLabel, stateLabel, chargeFill, hypeFill, resultFrame, resultLabel
local levelLabel, xpFill, coinsLabel, streakLabel, savedWarning
local questRows = {}
local levelPopup, levelPopupTitle, levelPopupSub

local STATE_KEYS = {
	Warmup = "hud.warmup",
	Live = "hud.live",
	SuddenDeath = "hud.sudden",
	RoundEnd = "hud.roundEnd",
	MatchEnd = "hud.matchEnd",
	Idle = "hud.idle",
}

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function button(text, position, color, callback)
	local btn = make("TextButton", {
		Size = UDim2.fromOffset(96, 62), Position = position, AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = color, TextColor3 = Color3.fromRGB(10, 14, 26),
		Font = Enum.Font.FredokaOne, TextSize = 15, Text = text,
	}, gui)
	corner(btn, 12)
	btn.Activated:Connect(callback)
	return btn
end

local function buildProfile()
	local panel = make("Frame", {
		Size = UDim2.fromOffset(232, 62), Position = UDim2.fromOffset(16, 12),
		BackgroundColor3 = Color3.fromRGB(12, 18, 38), BackgroundTransparency = 0.15, BorderSizePixel = 0,
	}, gui)
	corner(panel, 12)

	levelLabel = make("TextLabel", {
		Size = UDim2.fromOffset(80, 24), Position = UDim2.fromOffset(10, 6),
		BackgroundTransparency = 1, Text = Strings.Get("hud.level", 1),
		TextColor3 = Color3.fromRGB(124, 255, 79), Font = Enum.Font.FredokaOne,
		TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	coinsLabel = make("TextLabel", {
		Size = UDim2.fromOffset(130, 24), Position = UDim2.fromOffset(92, 6),
		BackgroundTransparency = 1, Text = "0", TextColor3 = Color3.fromRGB(255, 197, 61),
		Font = Enum.Font.FredokaOne, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)

	local track = make("Frame", {
		Size = UDim2.fromOffset(212, 8), Position = UDim2.fromOffset(10, 34),
		BackgroundColor3 = Color3.fromRGB(10, 14, 26), BorderSizePixel = 0,
	}, panel)
	corner(track, 4)
	xpFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(124, 255, 79), BorderSizePixel = 0,
	}, track)
	corner(xpFill, 4)

	streakLabel = make("TextLabel", {
		Size = UDim2.fromOffset(212, 14), Position = UDim2.fromOffset(10, 44),
		BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(143, 160, 201),
		Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	savedWarning = make("TextLabel", {
		Size = UDim2.fromOffset(232, 16), Position = UDim2.fromOffset(16, 78),
		BackgroundTransparency = 1, Text = Strings.Get("hud.notSaved"),
		TextColor3 = Color3.fromRGB(255, 120, 90), Font = Enum.Font.GothamBold,
		TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Visible = false,
	}, gui)
end

local function buildQuests()
	local header = make("TextLabel", {
		Size = UDim2.fromOffset(232, 16), Position = UDim2.fromOffset(16, 100),
		BackgroundTransparency = 1, Text = Strings.Get("hud.quests"),
		TextColor3 = Color3.fromRGB(143, 160, 201), Font = Enum.Font.GothamBold,
		TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
	}, gui)
	header.TextTransparency = 0.15

	for index = 1, CFG.Progression.QuestSlots do
		local row = make("Frame", {
			Size = UDim2.fromOffset(232, 46), Position = UDim2.fromOffset(16, 118 + (index - 1) * 52),
			BackgroundColor3 = Color3.fromRGB(12, 18, 38), BackgroundTransparency = 0.25, BorderSizePixel = 0,
		}, gui)
		corner(row, 10)

		local label = make("TextLabel", {
			Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(9, 5),
			BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(234, 240, 255),
			Font = Enum.Font.GothamBold, TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)

		local track = make("Frame", {
			Size = UDim2.fromOffset(150, 6), Position = UDim2.fromOffset(9, 26),
			BackgroundColor3 = Color3.fromRGB(10, 14, 26), BorderSizePixel = 0,
		}, row)
		corner(track, 3)
		local fill = make("Frame", {
			Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(46, 155, 255), BorderSizePixel = 0,
		}, track)
		corner(fill, 3)

		local progress = make("TextLabel", {
			Size = UDim2.fromOffset(150, 12), Position = UDim2.fromOffset(9, 33),
			BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(143, 160, 201),
			Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		local claim = make("TextButton", {
			Size = UDim2.fromOffset(62, 30), Position = UDim2.fromOffset(163, 8),
			BackgroundColor3 = Color3.fromRGB(46, 60, 100), TextColor3 = Color3.fromRGB(143, 160, 201),
			Font = Enum.Font.FredokaOne, TextSize = 12, Text = Strings.Get("hud.claim"),
			AutoButtonColor = false,
		}, row)
		corner(claim, 8)

		claim.Activated:Connect(function()
			local remote = Net.Get("QuestClaim")
			if remote then remote:FireServer(index) end
		end)

		questRows[index] = { row = row, label = label, fill = fill, progress = progress, claim = claim }
	end
end

local function buildLevelPopup()
	levelPopup = make("Frame", {
		Size = UDim2.fromOffset(300, 84), Position = UDim2.new(0.5, 0, 0.32, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(16, 26, 20),
		BackgroundTransparency = 0.08, BorderSizePixel = 0, Visible = false,
	}, gui)
	corner(levelPopup, 14)
	make("UIStroke", { Color = Color3.fromRGB(124, 255, 79), Thickness = 2 }, levelPopup)
	make("UIScale", { Scale = 1 }, levelPopup)

	levelPopupTitle = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 10),
		BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(124, 255, 79),
		Font = Enum.Font.FredokaOne, TextSize = 26,
	}, levelPopup)

	levelPopupSub = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(255, 197, 61),
		Font = Enum.Font.GothamBold, TextSize = 13,
	}, levelPopup)
end

function HUDController.Init()
	if CFG.Locale.Force then
		Strings.SetLocale(CFG.Locale.Force)
	else
		Strings.SetLocale(Players.LocalPlayer.LocaleId)
	end

	gui = make("ScreenGui", {
		Name = "DodgeballHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))

	local top = make("Frame", {
		Size = UDim2.fromOffset(260, 58), Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(12, 18, 38),
		BackgroundTransparency = 0.15, BorderSizePixel = 0,
	}, gui)
	corner(top, 12)

	scoreLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4),
		BackgroundTransparency = 1, Text = "0 : 0", TextColor3 = Color3.fromRGB(255, 197, 61),
		Font = Enum.Font.FredokaOne, TextSize = 24,
	}, top)

	stateLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 1, Text = Strings.Get("hud.waiting"),
		TextColor3 = Color3.fromRGB(143, 160, 201), Font = Enum.Font.GothamBold, TextSize = 13,
	}, top)

	local chargeTrack = make("Frame", {
		Size = UDim2.fromOffset(220, 12), Position = UDim2.new(0.5, 0, 1, -26),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(10, 14, 26), BorderSizePixel = 0,
	}, gui)
	corner(chargeTrack, 6)
	chargeFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 197, 61), BorderSizePixel = 0,
	}, chargeTrack)
	corner(chargeFill, 6)

	local hypeTrack = make("Frame", {
		Size = UDim2.fromOffset(160, 12), Position = UDim2.new(0, 16, 1, -26),
		BackgroundColor3 = Color3.fromRGB(10, 14, 26), BorderSizePixel = 0,
	}, gui)
	corner(hypeTrack, 6)
	hypeFill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 79, 216), BorderSizePixel = 0,
	}, hypeTrack)
	corner(hypeFill, 6)

	button(Strings.Get("hud.catch"), UDim2.new(1, -16, 1, -16), Color3.fromRGB(124, 255, 79), InputController.Catch)
	button(Strings.Get("hud.dodge"), UDim2.new(1, -124, 1, -16), Color3.fromRGB(46, 155, 255), InputController.Dodge)
	button(Strings.Get("hud.ult"), UDim2.new(1, -232, 1, -16), Color3.fromRGB(255, 79, 216), InputController.Ult)

	local throwBtn = button(Strings.Get("hud.throw"), UDim2.new(1, -16, 1, -92), Color3.fromRGB(255, 90, 77), function() end)
	throwBtn.Size = UDim2.fromOffset(140, 72)
	throwBtn.MouseButton1Down:Connect(InputController.BeginCharge)
	throwBtn.MouseButton1Up:Connect(InputController.ReleaseCharge)

	resultFrame = make("Frame", {
		Size = UDim2.fromOffset(300, 150), Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(18, 24, 48),
		BorderSizePixel = 0, Visible = false,
	}, gui)
	corner(resultFrame, 16)

	resultLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 16),
		BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.FredokaOne, TextSize = 26,
	}, resultFrame)

	local rematch = make("TextButton", {
		Size = UDim2.fromOffset(200, 48), Position = UDim2.new(0.5, 0, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(255, 197, 61),
		Text = Strings.Get("hud.rematch"), TextColor3 = Color3.fromRGB(20, 14, 0),
		Font = Enum.Font.FredokaOne, TextSize = 18,
	}, resultFrame)
	corner(rematch, 12)
	rematch.Activated:Connect(function()
		resultFrame.Visible = false
		InputController.Rematch()
	end)

	buildProfile()
	buildQuests()
	buildLevelPopup()
end

function HUDController.Start()
	RunService.RenderStepped:Connect(function()
		chargeFill.Size = UDim2.new(InputController.GetCharge(), 0, 1, 0)
	end)

	local matchState = Net.Get("MatchState")
	if matchState then
		matchState.OnClientEvent:Connect(function(state)
			if typeof(state) ~= "table" then return end
			scoreLabel.Text = tostring(state.wins1 or 0) .. " : " .. tostring(state.wins2 or 0)
			if state.state == "MatchEnd" then
				resultFrame.Visible = true
				local character = Players.LocalPlayer.Character
				local myTeam = character and character:GetAttribute("Team")
				resultLabel.Text = if myTeam == state.winner
					then Strings.Get("hud.victory") else Strings.Get("hud.defeat")
				stateLabel.Text = Strings.Get("hud.matchEnd")
			else
				local key = STATE_KEYS[state.state] or "hud.waiting"
				stateLabel.Text = Strings.Get(key) .. "  " .. Strings.Get("hud.seconds", state.timer or 0)
			end
		end)
	end

	local hypeState = Net.Get("HypeState")
	if hypeState then
		hypeState.OnClientEvent:Connect(function(value, max)
			hypeFill.Size = UDim2.new(math.clamp(value / math.max(max, 1), 0, 1), 0, 1, 0)
		end)
	end

	local profileState = Net.Get("ProfileState")
	if profileState then
		profileState.OnClientEvent:Connect(function(profile)
			if typeof(profile) ~= "table" then return end
			levelLabel.Text = Strings.Get("hud.level", profile.level or 1)
			coinsLabel.Text = tostring(profile.coins or 0)
			local ratio = math.clamp((profile.xp or 0) / math.max(profile.xpToNext or 1, 1), 0, 1)
			TweenService:Create(xpFill, TweenInfo.new(0.35), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
			streakLabel.Text = if (profile.streakDay or 0) > 0
				then Strings.Get("hud.streak", profile.streakDay) else ""
			savedWarning.Visible = profile.persistent == false
		end)
	end

	local questState = Net.Get("QuestState")
	if questState then
		questState.OnClientEvent:Connect(function(list)
			if typeof(list) ~= "table" then return end
			for index, row in ipairs(questRows) do
				local quest = list[index]
				if not quest then
					row.row.Visible = false
				else
					row.row.Visible = true
					row.label.Text = Strings.Get("quest." .. quest.id, quest.target)
					local ratio = math.clamp(quest.progress / math.max(quest.target, 1), 0, 1)
					row.fill.Size = UDim2.new(ratio, 0, 1, 0)
					row.progress.Text = string.format("%d / %d   +%d", quest.progress, quest.target, quest.rewardCoins)

					if quest.claimed then
						row.claim.Text = Strings.Get("hud.claimed")
						row.claim.BackgroundColor3 = Color3.fromRGB(28, 44, 34)
						row.claim.TextColor3 = Color3.fromRGB(124, 255, 79)
						row.fill.BackgroundColor3 = Color3.fromRGB(124, 255, 79)
					elseif ratio >= 1 then
						row.claim.Text = Strings.Get("hud.claim")
						row.claim.BackgroundColor3 = Color3.fromRGB(124, 255, 79)
						row.claim.TextColor3 = Color3.fromRGB(8, 20, 10)
						row.fill.BackgroundColor3 = Color3.fromRGB(124, 255, 79)
					else
						row.claim.Text = Strings.Get("hud.claim")
						row.claim.BackgroundColor3 = Color3.fromRGB(46, 60, 100)
						row.claim.TextColor3 = Color3.fromRGB(143, 160, 201)
						row.fill.BackgroundColor3 = Color3.fromRGB(46, 155, 255)
					end
				end
			end
		end)
	end

	local levelUp = Net.Get("LevelUp")
	if levelUp then
		levelUp.OnClientEvent:Connect(function(level, unlock, coins)
			levelPopupTitle.Text = Strings.Get("hud.levelUp", level)
			levelPopupSub.Text = if unlock
				then Strings.Get("hud.unlocked", unlock)
				else Strings.Get("hud.coinsGain", coins or 0)
			levelPopup.Visible = true
			local scale = levelPopup:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 0.7
				TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			task.delay(2.8, function()
				if levelPopup.Parent then levelPopup.Visible = false end
			end)
		end)
	end
end

return HUDController

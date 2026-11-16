-- ClipController: ловит моменты, которые стоит записать в клип, и подсвечивает их игроку.
-- DOUBLE BONK, CLUTCH CATCH, SUDDEN DEATH WIN. Это подсказка для записи, не автозапись.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local ClipController = {}

local gui, banner, bannerLabel
local recentKOs: { { at: number, thrower: any } } = {}
local moments: { { kind: string, at: number } } = {}
local lastState: any = nil
local wasSuddenDeath = false
local lastBanner = 0

local function myTeam(): number?
	local character = Players.LocalPlayer.Character
	return character and character:GetAttribute("Team")
end

local function myAlive(): number
	if not lastState then return 3 end
	return if myTeam() == 1 then (lastState.alive1 or 3) else (lastState.alive2 or 3)
end

local function showMoment(kind: string)
	local now = os.clock()
	if now - lastBanner < 2 then return end
	lastBanner = now
	table.insert(moments, { kind = kind, at = now })

	bannerLabel.Text = "🎬 " .. kind
	banner.Visible = true
	banner.BackgroundTransparency = 0.1

	local scale = banner:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.7
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	task.delay(2.6, function()
		if banner.Parent then
			TweenService:Create(banner, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(bannerLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			banner.Visible = false
			bannerLabel.TextTransparency = 0
		end
	end)

	print("[Clip] Момент: " .. kind .. " — запиши клип")
end

local function onKO(character: any, second: any)
	local thrower = if typeof(second) == "Instance" then second else nil
	if not thrower then return end

	local me = Players.LocalPlayer.Character
	if thrower ~= me then return end

	local now = os.clock()
	table.insert(recentKOs, { at = now, thrower = thrower })
	for i = #recentKOs, 1, -1 do
		if now - recentKOs[i].at > CFG.Juice.MomentWindow then
			table.remove(recentKOs, i)
		end
	end
	if #recentKOs >= 2 then
		showMoment("DOUBLE BONK")
		table.clear(recentKOs)
	end
end

local function onCatch(character: any)
	if character ~= Players.LocalPlayer.Character then return end
	if myAlive() <= 1 then
		showMoment("CLUTCH CATCH")
	end
end

function ClipController.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "RDClips"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	banner = Instance.new("Frame")
	banner.Size = UDim2.fromOffset(320, 56)
	banner.Position = UDim2.new(0.5, 0, 0, 84)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BackgroundColor3 = Color3.fromRGB(20, 12, 34)
	banner.BackgroundTransparency = 0.1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = banner

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 79, 216)
	stroke.Thickness = 2
	stroke.Parent = banner

	local scale = Instance.new("UIScale")
	scale.Parent = banner

	bannerLabel = Instance.new("TextLabel")
	bannerLabel.Size = UDim2.fromScale(1, 1)
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Font = Enum.Font.FredokaOne
	bannerLabel.TextSize = 22
	bannerLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	bannerLabel.Text = ""
	bannerLabel.Parent = banner
end

function ClipController.Start()
	local fx = Net.Get("FXEvent")
	if fx then
		fx.OnClientEvent:Connect(function(kind, a, b)
			if kind == "ko" then
				onKO(a, b)
			elseif kind == "catch" then
				onCatch(a)
			end
		end)
	end

	local matchState = Net.Get("MatchState")
	if matchState then
		matchState.OnClientEvent:Connect(function(state)
			if typeof(state) ~= "table" then return end
			lastState = state
			if state.state == "SuddenDeath" then
				wasSuddenDeath = true
			elseif state.state == "MatchEnd" then
				if wasSuddenDeath and state.winner == myTeam() then
					showMoment("SUDDEN DEATH WIN")
				end
				wasSuddenDeath = false
			end
		end)
	end
end

function ClipController.GetMoments()
	return moments
end

return ClipController

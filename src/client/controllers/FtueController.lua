-- FtueController: показывает подсказку, которую прислал сервер.
-- Сам ничего не решает и никакой прогресс не отмечает: только рисует.
-- Подсказка живёт над кнопкой THROW, не перекрывает арену, исчезает по шагу.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))

local FtueController = {}

local gui, panel, label, arrow
local currentKey: string? = nil
local pulseTween

local function isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function resolveKey(key: string): string
	if isMobile() then
		if key == "ftue.throw" then return "ftue.throw" end
		if key == "ftue.catch" then return "ftue.catchMobile" end
	else
		if key == "ftue.throw" then return "ftue.throwKey" end
	end
	return key
end

local function hide()
	currentKey = nil
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	if panel then
		panel.Visible = false
	end
end

local function show(key: string)
	if not CFG.FTUE.Enabled then return end
	if key == currentKey then return end
	currentKey = key

	label.Text = Strings.Get(resolveKey(key))
	panel.Visible = true

	local scale = panel:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	if pulseTween then pulseTween:Cancel() end
	pulseTween = TweenService:Create(arrow, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.55,
	})
	pulseTween:Play()

	local remote = Net.Get("UiEvent")
	if remote then remote:FireServer("hint_shown", if isMobile() then "mobile" else "desktop") end
end

function FtueController.Init()
	if CFG.Locale.Force then
		Strings.SetLocale(CFG.Locale.Force)
	else
		Strings.SetLocale(Players.LocalPlayer.LocaleId)
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "RDFtue"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(340, 54)
	panel.Position = UDim2.new(0.5, 0, 1, -180)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.BackgroundColor3 = Color3.fromRGB(14, 20, 40)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 197, 61)
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = panel

	Instance.new("UIScale", panel)

	label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 1, -14)
	label.Position = UDim2.fromOffset(10, 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 17
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 236, 158)
	label.Text = ""
	label.Parent = panel

	arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromOffset(40, 26)
	arrow.Position = UDim2.new(1, -10, 1, 2)
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.FredokaOne
	arrow.TextSize = 22
	arrow.TextColor3 = Color3.fromRGB(255, 197, 61)
	arrow.Text = "▼"
	arrow.Parent = panel
end

function FtueController.Start()
	local remote = Net.Get("FtueState")
	if remote then
		remote.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			if payload.done and payload.hint == nil then
				hide()
				return
			end
			if typeof(payload.hint) == "string" then
				show(payload.hint)
			else
				hide()
			end
		end)
	end

	local device = if isMobile() then "mobile" else "desktop"
	local ui = Net.Get("UiEvent")
	if ui then ui:FireServer("hint_dismissed", device) end
end

return FtueController

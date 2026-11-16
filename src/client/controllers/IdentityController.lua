-- IdentityController: локальный игрок всегда зелёный, со стрелкой и меткой YOU.
-- Плюс плашка YOUR TEAM, чтобы понимать, какая половина счёта твоя.
-- Сервер красит по командам, клиент перекрывает только себя.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Strings = require(Shared:WaitForChild("Strings"))

local IdentityController = {}

local player = Players.LocalPlayer
local gui, teamChip
local selfTag: BillboardGui? = nil
local currentCharacter: Model? = nil

local function teamEntry()
	local character = player.Character
	local team = character and character:GetAttribute("Team")
	return if typeof(team) == "number" then CFG.Teams[team] else nil
end

local function paintSelf(character: Model)
	local highlight = character:FindFirstChild("TeamHighlight") :: Highlight?
	if highlight then
		highlight.OutlineColor = CFG.Teams.Self
		highlight.FillColor = CFG.Teams.Self
	end

	local tag = character:FindFirstChild("IdentityTag")
	if tag then
		local nameLabel = tag:FindFirstChild("NameLabel")
		if nameLabel then nameLabel.TextColor3 = CFG.Teams.Self end
	end
end

local function ensureSelfTag(character: Model)
	if not CFG.Readability.SelfArrow then return end
	if selfTag and selfTag.Parent then return end

	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SelfTag"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(120, 46)
	billboard.StudsOffset = Vector3.new(0, 4.4, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = character

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 18
	label.Text = Strings.Get("tag.you")
	label.TextColor3 = CFG.Teams.Self
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(8, 16, 8)
	label.Parent = billboard

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(1, 0, 0, 22)
	arrow.Position = UDim2.fromOffset(0, 20)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.FredokaOne
	arrow.TextSize = 20
	arrow.Text = "▼"
	arrow.TextColor3 = CFG.Teams.Self
	arrow.TextStrokeTransparency = 0.4
	arrow.Parent = billboard

	selfTag = billboard
end

local function refreshChip()
	local entry = teamEntry()
	if entry then
		teamChip.Text = Strings.Get("hud.yourTeam", entry.name)
		teamChip.TextColor3 = entry.color
		teamChip.Visible = true
	else
		teamChip.Visible = false
	end
end

local function bindCharacter(character: Model)
	currentCharacter = character
	selfTag = nil

	task.spawn(function()
		if not character:FindFirstChild("Head") then
			character:WaitForChild("Head", 8)
		end
		ensureSelfTag(character)
		paintSelf(character)
		refreshChip()
	end)

	character:GetAttributeChangedSignal("Team"):Connect(function()
		paintSelf(character)
		refreshChip()
	end)
	character:GetAttributeChangedSignal("Benched"):Connect(function()
		task.wait(0.05)
		paintSelf(character)
	end)

	-- сервер может перекрасить контур при смене состояния: возвращаем свой цвет
	local highlight = character:WaitForChild("TeamHighlight", 8) :: Highlight?
	if highlight then
		highlight:GetPropertyChangedSignal("OutlineColor"):Connect(function()
			if currentCharacter == character and highlight.OutlineColor ~= CFG.Teams.Self then
				paintSelf(character)
			end
		end)
	end
end

function IdentityController.Init()
	if CFG.Locale.Force then
		Strings.SetLocale(CFG.Locale.Force)
	else
		Strings.SetLocale(player.LocaleId)
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "RDIdentity"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	teamChip = Instance.new("TextLabel")
	teamChip.Size = UDim2.fromOffset(240, 18)
	teamChip.Position = UDim2.new(0.5, 0, 0, 72)
	teamChip.AnchorPoint = Vector2.new(0.5, 0)
	teamChip.BackgroundTransparency = 1
	teamChip.Font = Enum.Font.FredokaOne
	teamChip.TextSize = 14
	teamChip.TextStrokeTransparency = 0.45
	teamChip.TextStrokeColor3 = Color3.fromRGB(8, 10, 18)
	teamChip.Text = ""
	teamChip.Visible = false
	teamChip.Parent = gui
end

function IdentityController.Start()
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then bindCharacter(player.Character) end

	-- дешёвая страховка: раз в полсекунды убеждаемся, что свой контур не перекрашен
	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = player.Character
			if character and character.Parent then
				paintSelf(character)
				if CFG.Readability.SelfArrow and (not selfTag or not selfTag.Parent) then
					ensureSelfTag(character)
				end
			end
		end
	end)
end

return IdentityController

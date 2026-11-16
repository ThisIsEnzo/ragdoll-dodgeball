-- TeamIdentityService: контур команды и ник над головой для всех участников.
-- Работает на сервере, чтобы все клиенты видели одну и ту же картину.
-- Локальный игрок перекрашивается в зелёный на клиенте (IdentityController).
--
-- Схема: BLUE = команда 1, RED = команда 2, OUT = выбит, BOT = управляется ИИ.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Strings = require(Shared:WaitForChild("Strings"))

local TeamIdentityService = {}

local bound: { [Model]: boolean } = {}

local function teamColor(character: Model): Color3
	local team = character:GetAttribute("Team")
	local entry = if typeof(team) == "number" then CFG.Teams[team] else nil
	if not entry then return CFG.Teams.Neutral end
	if character:GetAttribute("Benched") then
		return entry.color:Lerp(Color3.fromRGB(90, 96, 120), 0.65)
	end
	return entry.color
end

local function ensureHighlight(character: Model): Highlight?
	if not CFG.Readability.Highlights then return nil end
	local highlight = character:FindFirstChild("TeamHighlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "TeamHighlight"
		highlight.Adornee = character
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = character
	end
	highlight.FillTransparency = CFG.Readability.FillTransparency
	highlight.OutlineTransparency = CFG.Readability.OutlineTransparency
	return highlight
end

local function ensureTag(character: Model): BillboardGui?
	if not CFG.Readability.NameTags then return nil end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return nil end

	local tag = character:FindFirstChild("IdentityTag")
	if tag then return tag end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "IdentityTag"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(180, 44)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = CFG.Readability.TagMaxDistance
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Parent = character

	local name = Instance.new("TextLabel")
	name.Name = "NameLabel"
	name.Size = UDim2.new(1, 0, 0, 22)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 17
	name.TextStrokeTransparency = 0.35
	name.TextStrokeColor3 = Color3.fromRGB(8, 10, 18)
	name.Text = ""
	name.Parent = billboard

	local status = Instance.new("TextLabel")
	status.Name = "StatusLabel"
	status.Size = UDim2.new(1, 0, 0, 16)
	status.Position = UDim2.fromOffset(0, 23)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextSize = 12
	status.TextStrokeTransparency = 0.5
	status.Text = ""
	status.Parent = billboard

	return billboard
end

local function refresh(character: Model)
	if not character.Parent then return end
	local color = teamColor(character)

	local highlight = ensureHighlight(character)
	if highlight then
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.Enabled = true
	end

	local tag = ensureTag(character)
	if tag then
		local nameLabel = tag:FindFirstChild("NameLabel")
		local statusLabel = tag:FindFirstChild("StatusLabel")

		local displayName = character:GetAttribute("DisplayName")
		if typeof(displayName) ~= "string" then
			local player = Players:GetPlayerFromCharacter(character)
			displayName = if player then player.Name else character.Name
		end

		if nameLabel then
			nameLabel.Text = displayName
			nameLabel.TextColor3 = color
		end
		if statusLabel then
			if character:GetAttribute("Benched") then
				statusLabel.Text = Strings.Get("tag.out")
				statusLabel.TextColor3 = Color3.fromRGB(255, 140, 120)
			elseif character:GetAttribute("IsBot") then
				statusLabel.Text = Strings.Get("tag.bot")
				statusLabel.TextColor3 = Color3.fromRGB(170, 180, 205)
			else
				statusLabel.Text = ""
			end
		end
	end
end

local function bind(character: Instance)
	if not character:IsA("Model") or bound[character] then return end
	bound[character] = true

	-- Head может приехать позже остальных частей
	task.spawn(function()
		if not character:FindFirstChild("Head") then
			character:WaitForChild("Head", 8)
		end
		refresh(character)
	end)

	for _, attribute in ipairs({ "Team", "Benched", "DisplayName", "IsBot" }) do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			refresh(character)
		end)
	end

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then bound[character] = nil end
	end)
end

function TeamIdentityService.Init()
	if CFG.Locale.Force then Strings.SetLocale(CFG.Locale.Force) end
end

function TeamIdentityService.Refresh(character: Model)
	refresh(character)
end

function TeamIdentityService.Start()
	for _, character in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		bind(character)
	end
	CollectionService:GetInstanceAddedSignal("DodgeballActor"):Connect(bind)
end

return TeamIdentityService

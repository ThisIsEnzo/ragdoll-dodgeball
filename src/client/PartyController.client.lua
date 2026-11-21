-- PartyController: friends, party, and the native Roblox invite.
--
-- Three sections in one panel: who is in this server, your current party,
-- and your Roblox friends. Inviting a friend into the experience uses
-- SocialService, which opens Roblox's own invite sheet rather than a custom
-- one, so it works on every platform including mobile.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("PartyRemotes")
local stateRemote = remotes:WaitForChild("PartyState")
local inviteRemote = remotes:WaitForChild("PartyInvite")
local respondRemote = remotes:WaitForChild("PartyRespond")
local leaveRemote = remotes:WaitForChild("PartyLeave")
local friendsRemote = remotes:WaitForChild("PartyFriends")
local offerRemote = remotes:WaitForChild("PartyOffer")

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE = Color3.fromRGB(18, 25, 48)
local SURFACE2 = Color3.fromRGB(26, 35, 66)
local LINE = Color3.fromRGB(48, 62, 104)
local TEXT = Color3.fromRGB(234, 240, 255)
local DIM = Color3.fromRGB(158, 174, 210)
local LIME = Color3.fromRGB(150, 255, 60)
local AMBER = Color3.fromRGB(255, 190, 0)
local CYAN = Color3.fromRGB(0, 226, 255)
local RED = Color3.fromRGB(255, 58, 58)

local latest = nil
local friends = {}
local canInvite = false

local gui = Instance.new("ScreenGui")
gui.Name = "RDParty"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 17
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local openButton = make("TextButton", {
	Size = UDim2.fromOffset(96, 32),
	Position = UDim2.new(1, -16, 0, 288),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = CYAN,
	TextColor3 = Color3.fromRGB(4, 22, 30),
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	Text = "FRIENDS",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, openButton)

local partyChip = make("TextLabel", {
	Size = UDim2.fromOffset(150, 24),
	Position = UDim2.fromOffset(16, 138),
	BackgroundColor3 = SURFACE,
	BackgroundTransparency = 0.1,
	Font = Enum.Font.FredokaOne,
	TextSize = 12,
	TextColor3 = LIME,
	Text = "",
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 7) }, partyChip)
make("UIStroke", { Color = LIME, Thickness = 1.5, Transparency = 0.4 }, partyChip)

local panel = make("Frame", {
	Size = UDim2.fromOffset(452, 486),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = CYAN, Thickness = 2, Transparency = 0.3 }, panel)
local panelScale = make("UIScale", { Scale = 1 }, panel)

local title = make("TextLabel", {
	Size = UDim2.new(1, -60, 0, 28),
	Position = UDim2.fromOffset(16, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 19,
	TextColor3 = CYAN,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "PLAY TOGETHER",
}, panel)

local closeButton = make("TextButton", {
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -12, 0, 12),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = SURFACE2,
	TextColor3 = TEXT,
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	Text = "X",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, closeButton)

local bonusLine = make("TextLabel", {
	Size = UDim2.new(1, -32, 0, 18),
	Position = UDim2.fromOffset(16, 42),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = LIME,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, panel)

local inviteGameButton = make("TextButton", {
	Size = UDim2.new(1, -32, 0, 38),
	Position = UDim2.fromOffset(16, 64),
	BackgroundColor3 = LIME,
	TextColor3 = Color3.fromRGB(10, 28, 6),
	Font = Enum.Font.FredokaOne,
	TextSize = 15,
	Text = "INVITE ROBLOX FRIENDS",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, inviteGameButton)

local scroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -32, 1, -122),
	Position = UDim2.fromOffset(16, 110),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = CYAN,
	ScrollBarImageTransparency = 0.3,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

local rowPool = {}
local order = 0

local function sectionHeader(text)
	order += 1
	local header = make("TextLabel", {
		Size = UDim2.new(1, -8, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		LayoutOrder = order,
	}, scroll)
	return header
end

local function getRow(index)
	local row = rowPool[index]
	if row then return row end

	local frame = make("Frame", {
		Size = UDim2.new(1, -8, 0, 42),
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
	}, scroll)
	make("UICorner", { CornerRadius = UDim.new(0, 9) }, frame)
	local stroke = make("UIStroke", { Color = LINE, Thickness = 1, Transparency = 0.6 }, frame)

	local dot = make("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.fromOffset(10, 17),
		BackgroundColor3 = DIM,
		BorderSizePixel = 0,
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)

	local name = make("TextLabel", {
		Size = UDim2.new(1, -160, 0, 20),
		Position = UDim2.fromOffset(26, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, frame)

	local sub = make("TextLabel", {
		Size = UDim2.new(1, -160, 0, 14),
		Position = UDim2.fromOffset(26, 23),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, frame)

	local action = make("TextButton", {
		Size = UDim2.fromOffset(122, 28),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = SURFACE2,
		TextColor3 = TEXT,
		Font = Enum.Font.FredokaOne,
		TextSize = 11,
		Text = "",
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, action)

	row = { frame = frame, name = name, sub = sub, action = action, dot = dot, stroke = stroke, handler = nil }
	rowPool[index] = row
	-- One permanent connection per pooled row; render swaps handler only.
	action.Activated:Connect(function()
		local handler = row.handler
		if handler then handler() end
	end)
	return row
end

local headers = {}

function render()
	for _, header in ipairs(headers) do
		header:Destroy()
	end
	table.clear(headers)
	order = 0

	local rowIndex = 0
	local myParty = latest and latest.partyId or nil
	local members = latest and latest.members or {}

	if latest and latest.bonusPercent and latest.bonusPercent > 0 then
		bonusLine.Text = string.format("PARTY BONUS ACTIVE  +%d%% coins each match", latest.bonusPercent)
		partyChip.Visible = true
		partyChip.Text = string.format("PARTY %d/%d  +%d%%", #members, latest.maxSize, latest.bonusPercent)
	else
		bonusLine.Text = "Party up with players here to earn bonus coins"
		bonusLine.TextColor3 = DIM
		partyChip.Visible = false
	end

	if #members > 0 then
		table.insert(headers, sectionHeader("YOUR PARTY"))
		for _, member in ipairs(members) do
			rowIndex += 1
			local row = getRow(rowIndex)
			row.frame.Visible = true
			row.frame.LayoutOrder = order
			order += 1
			row.name.Text = member.name
			row.sub.Text = if member.userId == player.UserId then "you" else "party member"
			row.dot.BackgroundColor3 = LIME
			row.stroke.Color = LIME
			row.stroke.Transparency = 0.5
			if member.userId == player.UserId then
				row.action.Text = "LEAVE"
				row.action.BackgroundColor3 = Color3.fromRGB(70, 30, 34)
				row.action.TextColor3 = Color3.fromRGB(255, 160, 150)
				row.handler = function()
				leaveRemote:FireServer()
				end
			else
				row.action.Text = "TOGETHER"
				row.action.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
				row.action.TextColor3 = LIME
			end
		end
	end

	table.insert(headers, sectionHeader("IN THIS SERVER"))
	local shownHere = 0
	for _, entry in ipairs(latest and latest.roster or {}) do
		if entry.userId ~= player.UserId then
			shownHere += 1
			rowIndex += 1
			local row = getRow(rowIndex)
			row.frame.Visible = true
			row.frame.LayoutOrder = order
			order += 1
			row.name.Text = entry.name
			row.sub.Text = "@" .. entry.username
			local sameParty = myParty ~= nil and entry.partyId == myParty
			if sameParty then
				row.dot.BackgroundColor3 = LIME
				row.action.Text = "IN PARTY"
				row.action.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
				row.action.TextColor3 = LIME
			else
				row.dot.BackgroundColor3 = CYAN
				row.action.Text = "INVITE TO PARTY"
				row.action.BackgroundColor3 = CYAN
				row.action.TextColor3 = Color3.fromRGB(4, 22, 30)
				local targetId = entry.userId
				row.handler = function()
					inviteRemote:FireServer(targetId)
					row.action.Text = "SENT"
					row.action.BackgroundColor3 = SURFACE2
					row.action.TextColor3 = DIM
					row.handler = nil
				end
			end
		end
	end
	if shownHere == 0 then
		rowIndex += 1
		local row = getRow(rowIndex)
		row.frame.Visible = true
		row.frame.LayoutOrder = order
		order += 1
		row.name.Text = "Nobody else here yet"
		row.sub.Text = "Invite a friend to fill the court"
		row.dot.BackgroundColor3 = DIM
		row.action.Text = ""
		row.action.BackgroundColor3 = SURFACE
	end

	table.insert(headers, sectionHeader("ROBLOX FRIENDS"))
	if #friends == 0 then
		rowIndex += 1
		local row = getRow(rowIndex)
		row.frame.Visible = true
		row.frame.LayoutOrder = order
		order += 1
		row.name.Text = "Loading friends..."
		row.sub.Text = ""
		row.dot.BackgroundColor3 = DIM
		row.action.Text = ""
		row.action.BackgroundColor3 = SURFACE
	else
		for _, entry in ipairs(friends) do
			rowIndex += 1
			local row = getRow(rowIndex)
			row.frame.Visible = true
			row.frame.LayoutOrder = order
			order += 1
			row.name.Text = entry.name
			row.sub.Text = "@" .. entry.username
			if entry.inThisServer then
				row.dot.BackgroundColor3 = LIME
				row.action.Text = "HERE NOW"
				row.action.BackgroundColor3 = Color3.fromRGB(30, 70, 44)
				row.action.TextColor3 = LIME
		 elseif entry.isOnline then
				row.dot.BackgroundColor3 = AMBER
				row.action.Text = "ONLINE"
				row.action.BackgroundColor3 = SURFACE2
				row.action.TextColor3 = AMBER
		 else
				row.dot.BackgroundColor3 = LINE
				row.action.Text = "OFFLINE"
				row.action.BackgroundColor3 = SURFACE2
				row.action.TextColor3 = DIM
		 end
		end
	end

	for index = rowIndex + 1, #rowPool do
		rowPool[index].frame.Visible = false
	end

	if canInvite then
		inviteGameButton.BackgroundColor3 = LIME
		inviteGameButton.TextColor3 = Color3.fromRGB(10, 28, 6)
		inviteGameButton.Text = "INVITE ROBLOX FRIENDS"
	else
		inviteGameButton.BackgroundColor3 = SURFACE2
		inviteGameButton.TextColor3 = DIM
		inviteGameButton.Text = "INVITES UNAVAILABLE HERE"
	end
end

-- incoming offer ----------------------------------------------------------

local offerCard = make("Frame", {
	Size = UDim2.fromOffset(330, 92),
	Position = UDim2.new(0.5, 0, 0, 190),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 13) }, offerCard)
make("UIStroke", { Color = LIME, Thickness = 2, Transparency = 0.25 }, offerCard)

local offerText = make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 34),
	Position = UDim2.fromOffset(10, 8),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	TextColor3 = TEXT,
	TextWrapped = true,
	Text = "",
}, offerCard)

local acceptButton = make("TextButton", {
	Size = UDim2.fromOffset(148, 32),
	Position = UDim2.fromOffset(10, 50),
	BackgroundColor3 = LIME,
	TextColor3 = Color3.fromRGB(10, 28, 6),
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	Text = "ACCEPT",
}, offerCard)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, acceptButton)

local declineButton = make("TextButton", {
	Size = UDim2.fromOffset(148, 32),
	Position = UDim2.fromOffset(172, 50),
	BackgroundColor3 = SURFACE2,
	TextColor3 = DIM,
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	Text = "DECLINE",
}, offerCard)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, declineButton)

local offerDeadline = 0

offerRemote.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	offerText.Text = string.format("%s wants to party up", tostring(data.name))
	offerDeadline = os.clock() + (data.expires or 20)
	offerCard.Visible = true
end)

acceptButton.Activated:Connect(function()
	respondRemote:FireServer(true)
	offerCard.Visible = false
end)

declineButton.Activated:Connect(function()
	respondRemote:FireServer(false)
	offerCard.Visible = false
end)

-- wiring ------------------------------------------------------------------

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		panelScale.Scale = 0.92
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		friendsRemote:FireServer()
		render()
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

inviteGameButton.Activated:Connect(function()
	if not canInvite then return end
	local ok = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not ok then
		inviteGameButton.Text = "PUBLISH THE PLACE TO INVITE"
		inviteGameButton.BackgroundColor3 = SURFACE2
		inviteGameButton.TextColor3 = AMBER
	end
end)

stateRemote.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	latest = state
	if panel.Visible then render() else
		local members = state.members or {}
		if state.bonusPercent and state.bonusPercent > 0 then
			partyChip.Visible = true
			partyChip.Text = string.format("PARTY %d/%d  +%d%%", #members, state.maxSize, state.bonusPercent)
		else
			partyChip.Visible = false
		end
	end
end)

friendsRemote.OnClientEvent:Connect(function(list)
	if typeof(list) ~= "table" then return end
	friends = list
	if panel.Visible then render() end
end)

task.spawn(function()
	local ok, result = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	canInvite = ok and result == true
	if panel.Visible then render() end
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		if offerCard.Visible and os.clock() > offerDeadline then
			offerCard.Visible = false
		end
	end
end)

print("[Party] friends panel ready")

-- MapService: builds the active venue and rotates it by player vote.
-- Replaces WorldDecor and retunes lighting. Court collision, spawn markers
-- and bench markers are untouched, so a theme swap mid-session is safe.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Catalog = require(Shared:WaitForChild("ArenaCatalog"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")
local AntiCheat = Resolve.Require(ServerScriptService, "AntiCheat")

local BLUE = CFG.Teams[1].color
local RED = CFG.Teams[2].color
local WHITE = Color3.fromRGB(252, 252, 255)

local current = "gym"
local voting = false
local candidates = {}
local tally = {}
local voted = {}

local folder = Instance.new("Folder")
folder.Name = "MapRemotes"
folder.Parent = ReplicatedStorage

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateRemote = makeRemote("MapState")
local voteRemote = makeRemote("MapVote")

local function material(name)
	local ok, value = pcall(function() return Enum.Material[name] end)
	if ok and value then return value end
	return Enum.Material.SmoothPlastic
end

local function part(parent, size, cf, color, mat, shadow)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = shadow == true
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sub(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function text(host, face, label, color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 44
	gui.Parent = host
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	l.Text = label
	l.Parent = gui
	return l
end

local function applyLighting(theme)
	local L = theme.lighting
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ClockTime = L.ClockTime
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	Lighting.ColorShift_Top = L.Top
	Lighting.ColorShift_Bottom = L.Bottom
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.7

	local function effect(class, name, props)
		local item = Lighting:FindFirstChild(name)
		if not item then
			item = Instance.new(class)
			item.Name = name
			item.Parent = Lighting
		end
		for key, value in pairs(props) do item[key] = value end
	end

	effect("Atmosphere", "RDAir", {
		Density = L.Density, Offset = 0.15, Color = L.AirColor,
		Decay = L.Decay, Glare = L.Glare, Haze = L.Haze,
	})
	effect("BloomEffect", "RDBloom", { Intensity = L.Bloom, Size = 24, Threshold = 1.05 })
	effect("ColorCorrectionEffect", "RDGrade", {
		Saturation = L.Saturation, Contrast = L.Contrast, Brightness = 0,
		TintColor = Color3.fromRGB(255, 252, 248),
	})
	effect("SunRaysEffect", "RDRays", { Intensity = 0.04, Spread = 0.5 })
end

local function buildCourt(root, theme)
	local W, D = CFG.Arena.Width, CFG.Arena.Depth
	local court = sub(root, "Court")
	local top = 1.02
	local rng = Random.new(90210)

	part(root, Vector3.new(340, 0.2, 340), CFrame.new(0, 0.05, 0), theme.ground, material("Concrete"))

	local strips = 30
	for i = 1, strips do
		local pw = W / strips
		local x = -W * 0.5 + pw * (i - 0.5)
		local color = theme.floorA
		if i % 2 == 0 then color = theme.floorB end
		if i % 6 == 0 then color = theme.floorC end
		part(court, Vector3.new(pw * 0.95, 0.04, D), CFrame.new(x, top, 0), color, material(theme.floorMaterial))
	end

	local paint = sub(court, "Paint")
	local ly = top + 0.05
	part(paint, Vector3.new(W - 2, 0.04, 0.6), CFrame.new(0, ly, -(D * 0.5 - 1.5)), WHITE)
	part(paint, Vector3.new(W - 2, 0.04, 0.6), CFrame.new(0, ly, D * 0.5 - 1.5), WHITE)
	part(paint, Vector3.new(0.6, 0.04, D - 3), CFrame.new(-(W * 0.5 - 1.5), ly, 0), WHITE)
	part(paint, Vector3.new(0.6, 0.04, D - 3), CFrame.new(W * 0.5 - 1.5, ly, 0), WHITE)

	for team = 1, 2 do
		local col = BLUE
		if team == 2 then col = RED end
		local sign = -1
		if team == 2 then sign = 1 end
		local tint = part(paint, Vector3.new(W - 4, 0.03, D * 0.5 - 3), CFrame.new(0, ly - 0.02, sign * D * 0.25), col)
		tint.Transparency = 0.86
		part(paint, Vector3.new(W - 4, 0.06, 0.55),
			CFrame.new(0, ly, sign * (CFG.BotAI.CenterMargin + CFG.BotAI.ThrowLineOffset)), col, material("Neon"))
	end

	local ring = part(paint, Vector3.new(0.3, 16, 16), CFrame.new(0, ly, 0) * CFrame.Angles(0, 0, math.rad(90)), WHITE)
	ring.Shape = Enum.PartType.Cylinder
	local fill = part(paint, Vector3.new(0.34, 14.4, 14.4), CFrame.new(0, ly + 0.01, 0) * CFrame.Angles(0, 0, math.rad(90)), theme.floorA, material(theme.floorMaterial))
	fill.Shape = Enum.PartType.Cylinder

	if theme.cage then
		for i = -6, 6 do
			part(paint, Vector3.new(0.14, 0.04, D - 4), CFrame.new(i * 7, ly, 0), theme.accent, material("Neon"))
		end
		for i = -4, 4 do
			part(paint, Vector3.new(W - 4, 0.04, 0.14), CFrame.new(0, ly, i * 7), Color3.fromRGB(0, 226, 255), material("Neon"))
		end
	end

	local logo = part(paint, Vector3.new(10, 0.05, 4.4), CFrame.new(0, ly + 0.03, 0), theme.floorC)
	logo.Transparency = 1
	text(logo, Enum.NormalId.Top, "RAGDOLL\nDODGEBALL", WHITE)

	local led = sub(root, "LedRibbon")
	for team = 1, 2 do
		local col = BLUE
		if team == 2 then col = RED end
		local sign = -1
		if team == 2 then sign = 1 end
		part(led, Vector3.new(W + 2, 0.8, 0.3), CFrame.new(0, 1.55, sign * (D * 0.5 + 0.4)), col, material("Neon"))
	end
	for _, s in ipairs({ -1, 1 }) do
		part(led, Vector3.new(0.3, 0.8, D + 2), CFrame.new(s * (W * 0.5 + 0.4), 1.55, 0), theme.accent, material("Neon"))
	end
end

local function buildBarrier(root, theme)
	local W, D = CFG.Arena.Width, CFG.Arena.Depth
	local pads = sub(root, "Barrier")

	for team = 1, 2 do
		local col = BLUE
		if team == 2 then col = RED end
		if theme.pad == "steel" then col = theme.structA end
		if theme.pad == "neon" then col = theme.structB end
		local sign = -1
		if team == 2 then sign = 1 end

		part(pads, Vector3.new(W, 7, 0.7), CFrame.new(0, 4.5, sign * (D * 0.5 - 0.2)), col, material("Fabric"), true)
		local trim = BLUE
		if team == 2 then trim = RED end
		part(pads, Vector3.new(W, 0.4, 0.4), CFrame.new(0, 8.2, sign * (D * 0.5 - 0.5)), trim, material("Neon"))
	end

	for _, s in ipairs({ -1, 1 }) do
		part(pads, Vector3.new(0.7, 7, D), CFrame.new(s * (W * 0.5 - 0.2), 4.5, 0), theme.structA, material("Fabric"), true)
		part(pads, Vector3.new(0.4, 0.4, D), CFrame.new(s * (W * 0.5 - 0.5), 8.2, 0), theme.accent, material("Neon"))
	end

	if theme.cage then
		local bars = sub(root, "CageBars")
		for i = -7, 7 do
			for _, s in ipairs({ -1, 1 }) do
				part(bars, Vector3.new(0.35, 22, 0.35), CFrame.new(i * 6.2, 12, s * (D * 0.5 + 0.6)), theme.accent, material("Neon"))
			end
		end
		for i = -5, 5 do
			for _, s in ipairs({ -1, 1 }) do
				part(bars, Vector3.new(0.35, 22, 0.35), CFrame.new(s * (W * 0.5 + 0.6), 12, i * 5.6), Color3.fromRGB(0, 226, 255), material("Neon"))
			end
		end
		for _, y in ipairs({ 10, 18, 24 }) do
			part(bars, Vector3.new(W + 2, 0.3, 0.3), CFrame.new(0, y, -(D * 0.5 + 0.6)), theme.accent, material("Neon"))
			part(bars, Vector3.new(W + 2, 0.3, 0.3), CFrame.new(0, y, D * 0.5 + 0.6), theme.accent, material("Neon"))
			part(bars, Vector3.new(0.3, 0.3, D + 2), CFrame.new(-(W * 0.5 + 0.6), y, 0), Color3.fromRGB(0, 226, 255), material("Neon"))
			part(bars, Vector3.new(0.3, 0.3, D + 2), CFrame.new(W * 0.5 + 0.6, y, 0), Color3.fromRGB(0, 226, 255), material("Neon"))
		end
	end
end

local function buildStands(root, theme)
	if not theme.stands then return end
	local W, D = CFG.Arena.Width, CFG.Arena.Depth
	local stands = sub(root, "Stands")
	local crowd = sub(root, "Crowd")
	local rng = Random.new(4451207)
	local shirts = {
		Color3.fromRGB(255, 72, 64), Color3.fromRGB(0, 150, 255),
		Color3.fromRGB(255, 206, 40), Color3.fromRGB(140, 255, 80),
		Color3.fromRGB(255, 90, 220), Color3.fromRGB(240, 244, 255),
	}
	local skins = {
		Color3.fromRGB(255, 208, 164), Color3.fromRGB(238, 190, 150),
		Color3.fromRGB(202, 140, 100), Color3.fromRGB(146, 98, 66),
	}

	for _, s in ipairs({ -1, 1 }) do
		local c1 = Color3.fromRGB(20, 86, 190)
		local c2 = Color3.fromRGB(14, 62, 142)
		if s == 1 then
			c1 = Color3.fromRGB(196, 38, 46)
			c2 = Color3.fromRGB(148, 26, 34)
		end
		for row = 1, 5 do
			local z = s * (D * 0.5 + 5 + row * 3.4)
			local y = 1.5 + row * 2.6
			part(stands, Vector3.new(W + 14, 2.6, 3.6), CFrame.new(0, y, z), theme.structA, material("Concrete"), true)
			for seat = 1, 16 do
				local x = -W * 0.5 + 2 + (seat - 1) * ((W - 4) / 15)
				local sc = c1
				if seat % 2 == 0 then sc = c2 end
				part(stands, Vector3.new(2.2, 0.55, 2.2), CFrame.new(x, y + 1.55, z), sc)
				if rng:NextNumber() < 0.6 then
					local sh = shirts[rng:NextInteger(1, #shirts)]
					local sk = skins[rng:NextInteger(1, #skins)]
					local h = rng:NextNumber(1.5, 2.1)
					part(crowd, Vector3.new(1.5, h, 0.9),
						CFrame.new(x, y + 1.8 + h * 0.5, z + s * 0.3) * CFrame.Angles(rng:NextNumber(-0.14, 0.14), 0, 0),
						sh, material("Fabric"))
					part(crowd, Vector3.new(0.95, 0.95, 0.95), CFrame.new(x, y + 1.8 + h + 0.55, z + s * 0.3), sk)
				end
			end
		end
	end
end

local function buildSkyline(root, theme)
	if not theme.skyline then return end
	local city = sub(root, "Skyline")
	local rng = Random.new(31337)
	for i = 1, 34 do
		local angle = (i / 34) * math.pi * 2
		local radius = rng:NextNumber(130, 215)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		local h = rng:NextNumber(40, 130)
		local w = rng:NextNumber(20, 40)
		local tower = part(city, Vector3.new(w, h, w), CFrame.new(x, h * 0.5 - 12, z), theme.structB, material("Concrete"))
		tower.Reflectance = 0.04
		local lit = Color3.fromRGB(255, 214, 140)
		if rng:NextNumber() < 0.4 then lit = Color3.fromRGB(120, 200, 255) end
		for row = 1, 5 do
			part(city, Vector3.new(w * 0.8, 1.1, 0.4),
				CFrame.new(x, h * 0.5 - 12 + (row - 3) * 9, z - w * 0.5 - 0.2), lit, material("Neon"))
		end
	end
	local pad = sub(root, "Helipad")
	local ring = part(pad, Vector3.new(0.4, 26, 26), CFrame.new(0, 0.2, 78) * CFrame.Angles(0, 0, math.rad(90)), theme.accent, material("Neon"))
	ring.Shape = Enum.PartType.Cylinder
	local mark = part(pad, Vector3.new(14, 0.05, 14), CFrame.new(0, 0.26, 78), theme.structB)
	mark.Transparency = 1
	text(mark, Enum.NormalId.Top, "H", theme.accent)
end

local function buildRig(root, theme)
	local W, D, H = CFG.Arena.Width, CFG.Arena.Depth, CFG.Arena.CeilingHeight
	local rig = sub(root, "Rig")

	if theme.trusses then
		for i = 1, 7 do
			local z = -D * 0.5 + 5 + (i - 1) * ((D - 10) / 6)
			part(rig, Vector3.new(W + 12, 0.8, 0.8), CFrame.new(0, H - 2, z), theme.structA, material("Metal"), true)
		end
	end

	local count = 10
	for i = 1, count do
		local x = -W * 0.38 + (i - 1) * ((W * 0.76) / (count - 1))
		local z = -D * 0.22
		if i % 2 == 0 then z = D * 0.22 end
		local y = H - 3.7
		if theme.cage then y = H - 1.5 end
		part(rig, Vector3.new(2.6, 0.9, 2.6), CFrame.new(x, y, z), theme.structB, material("Metal"))
		local lens = part(rig, Vector3.new(2.2, 0.22, 2.2), CFrame.new(x, y - 0.55, z), Color3.fromRGB(255, 246, 226), material("Neon"))
		if theme.cage then lens.Color = theme.accent end
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 80
		spot.Brightness = 3.2
		spot.Range = 62
		spot.Color = lens.Color
		spot.Shadows = false
		spot.Parent = lens
	end
end

local function buildSignage(root, theme)
	local W, D, H = CFG.Arena.Width, CFG.Arena.Depth, CFG.Arena.CeilingHeight
	local signs = sub(root, "Signage")

	local panel = part(signs, Vector3.new(26, 9, 0.6), CFrame.new(0, 14, -(D * 0.5 - 0.9)), Color3.fromRGB(12, 16, 32), material("SmoothPlastic"), true)
	panel.Name = "ScorePanel"
	part(signs, Vector3.new(27, 0.5, 0.9), CFrame.new(0, 18.8, -(D * 0.5 - 0.9)), theme.accent, material("Neon"))
	part(signs, Vector3.new(27, 0.5, 0.9), CFrame.new(0, 9.2, -(D * 0.5 - 0.9)), theme.accent, material("Neon"))

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = panel
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(8, 12, 26)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local a = Instance.new("TextLabel")
	a.Name = "ScoreA"
	a.Size = UDim2.fromScale(0.4, 0.6)
	a.Position = UDim2.fromScale(0.05, 0.08)
	a.BackgroundTransparency = 1
	a.Font = Enum.Font.FredokaOne
	a.TextScaled = true
	a.TextColor3 = BLUE
	a.Text = "0"
	a.Parent = frame
	local b = Instance.new("TextLabel")
	b.Name = "ScoreB"
	b.Size = UDim2.fromScale(0.4, 0.6)
	b.Position = UDim2.fromScale(0.55, 0.08)
	b.BackgroundTransparency = 1
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = RED
	b.Text = "0"
	b.Parent = frame
	local st = Instance.new("TextLabel")
	st.Name = "StateLabel"
	st.Size = UDim2.fromScale(1, 0.24)
	st.Position = UDim2.fromScale(0, 0.72)
	st.BackgroundTransparency = 1
	st.Font = Enum.Font.GothamBold
	st.TextScaled = true
	st.TextColor3 = theme.accent
	st.Text = theme.name
	st.Parent = frame

	for _, s in ipairs({ -1, 1 }) do
		local board = part(signs, Vector3.new(0.3, 5, 24), CFrame.new(s * (W * 0.5 - 1.3), H - 6, 0), theme.structB, material("Fabric"))
		local face = Enum.NormalId.Right
		if s == 1 then face = Enum.NormalId.Left end
		text(board, face, theme.name, theme.accent)
	end
end

local function build(themeId)
	local theme = Catalog.Themes[themeId]
	if not theme then return end

	local old = Workspace:FindFirstChild("WorldDecor")
	if old then old:Destroy() end

	local root = Instance.new("Folder")
	root.Name = "WorldDecor"
	root:SetAttribute("Theme", themeId)
	root.Parent = Workspace

	applyLighting(theme)
	buildCourt(root, theme)
	buildBarrier(root, theme)
	buildStands(root, theme)
	buildSkyline(root, theme)
	buildRig(root, theme)
	buildSignage(root, theme)

	current = themeId
	local count = 0
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then count += 1 end
	end
	print(string.format("[Map] %s built, %d parts", theme.name, count))
end

local function pushState()
	local options = {}
	for _, id in ipairs(candidates) do
		local theme = Catalog.Themes[id]
		table.insert(options, {
			id = id, name = theme.name, tagline = theme.tagline,
			votes = tally[id] or 0,
		})
	end
	local active = Catalog.Themes[current]
	for _, player in ipairs(Players:GetPlayers()) do
		stateRemote:FireClient(player, {
			current = current,
			currentName = active.name,
			voting = voting,
			options = options,
			myVote = voted[player.UserId],
		})
	end
end

local function openVote()
	if voting then return end
	voting = true
	voted = {}
	tally = {}
	candidates = {}

	local pool = {}
	for _, id in ipairs(Catalog.Order) do
		if id ~= current then table.insert(pool, id) end
	end
	for _, id in ipairs(pool) do
		table.insert(candidates, id)
		tally[id] = 0
	end

	pushState()

	task.delay(Catalog.VoteSeconds, function()
		local best, bestVotes = candidates[1], -1
		for _, id in ipairs(candidates) do
			local count = tally[id] or 0
			if count > bestVotes then best, bestVotes = id, count end
		end
		voting = false
		if best and bestVotes > 0 then
			build(best)
		else
			local idx = 1
			for i, id in ipairs(Catalog.Order) do
				if id == current then idx = i end
			end
			build(Catalog.Order[(idx % #Catalog.Order) + 1])
		end
		candidates = {}
		pushState()
	end)
end

voteRemote.OnServerEvent:Connect(function(player, mapId)
	if not AntiCheat.Allow(player, "ShopBuy") then return end
	if not voting then return end
	if typeof(mapId) ~= "string" then return end
	if not tally[mapId] then return end

	local previous = voted[player.UserId]
	if previous and tally[previous] then
		tally[previous] = math.max(0, tally[previous] - 1)
	end
	voted[player.UserId] = mapId
	tally[mapId] = tally[mapId] + 1
	pushState()
end)

Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	pushState()
end)

Players.PlayerRemoving:Connect(function(player)
	local previous = voted[player.UserId]
	if previous and tally[previous] then
		tally[previous] = math.max(0, tally[previous] - 1)
	end
	voted[player.UserId] = nil
end)

RoundService.StateChanged.Event:Connect(function(state)
	if state == "MatchEnd" then
		openVote()
	end
end)

task.spawn(function()
	Workspace:WaitForChild("Arena", 30)
	task.wait(1)
	build(Catalog.Order[math.random(1, #Catalog.Order)])
	pushState()
end)

print("[Map] service up: " .. #Catalog.Order .. " venues, vote on match end")
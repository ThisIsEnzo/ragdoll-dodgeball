-- WorldService: art direction pass.
-- Dramatic lighting plus a procedurally dressed gym: planked court, painted
-- markings, padded walls, neon trim, bleachers with a crowd, ceiling trusses,
-- spot fixtures, hanging banners and ball racks.
--
-- Decorates the arena built by ArenaService without touching its collision,
-- spawn markers or sudden-death walls. Everything here is non-collidable.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))

local P = {
	woodA = Color3.fromRGB(198, 150, 94),
	woodB = Color3.fromRGB(184, 136, 82),
	woodDark = Color3.fromRGB(150, 108, 64),
	paint = Color3.fromRGB(246, 248, 255),
	steel = Color3.fromRGB(58, 66, 92),
	steelDark = Color3.fromRGB(34, 40, 60),
	seatA = Color3.fromRGB(38, 48, 78),
	seatB = Color3.fromRGB(52, 62, 96),
	cloth = Color3.fromRGB(24, 30, 52),
	warm = Color3.fromRGB(255, 214, 168),
}

local CROWD_SHIRTS = {
	Color3.fromRGB(226, 60, 52), Color3.fromRGB(46, 155, 255),
	Color3.fromRGB(255, 197, 61), Color3.fromRGB(124, 255, 79),
	Color3.fromRGB(255, 79, 216), Color3.fromRGB(199, 125, 255),
	Color3.fromRGB(236, 240, 250), Color3.fromRGB(90, 104, 140),
}

local SKIN = {
	Color3.fromRGB(255, 204, 153), Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 134, 96), Color3.fromRGB(140, 92, 62),
}

local rng = Random.new(20261118)

local function part(parent, name, size, cframe, color, material, shadow)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.CFrame = cframe
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.CastShadow = shadow == true
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function folder(parent, name)
	local item = Instance.new("Folder")
	item.Name = name
	item.Parent = parent
	return item
end

local function surfaceText(host, face, text, color, size)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0.15
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = host

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.6
	label.Text = text
	label.Parent = gui

	if size then
		label.TextSize = size
	end
	return gui
end

local function setupLighting()
	Lighting.Technology = Enum.Technology.Future
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.4
	Lighting.ClockTime = 17.2
	Lighting.GeographicLatitude = 18
	Lighting.Brightness = 2.4
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.85
	Lighting.Ambient = Color3.fromRGB(36, 42, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(74, 86, 124)
	Lighting.ColorShift_Top = P.warm
	Lighting.ColorShift_Bottom = Color3.fromRGB(38, 50, 92)

	local atmosphere = Lighting:FindFirstChild("RDAir")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "RDAir"
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(198, 208, 234)
	atmosphere.Decay = Color3.fromRGB(86, 98, 132)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.5

	local bloom = Lighting:FindFirstChild("RDBloom")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "RDBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.5
	bloom.Size = 26
	bloom.Threshold = 1.05

	local grade = Lighting:FindFirstChild("RDGrade")
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "RDGrade"
		grade.Parent = Lighting
	end
	grade.Saturation = 0.14
	grade.Contrast = 0.16
	grade.Brightness = 0.01
	grade.TintColor = Color3.fromRGB(255, 246, 236)

	local rays = Lighting:FindFirstChild("RDRays")
	if not rays then
		rays = Instance.new("SunRaysEffect")
		rays.Name = "RDRays"
		rays.Parent = Lighting
	end
	rays.Intensity = 0.05
	rays.Spread = 0.55
end

local function dressCourt(root, arena)
	local floor = arena:FindFirstChild("Floor")
	if not floor then return end

	floor.Color = P.woodA
	floor.Material = Enum.Material.Wood
	floor.Reflectance = 0.05

	local court = folder(root, "Court")
	local width = CFG.Arena.Width
	local depth = CFG.Arena.Depth
	local top = floor.Position.Y + floor.Size.Y * 0.5

	local planks = 26
	local plankWidth = width / planks
	for index = 1, planks do
		local x = -width * 0.5 + plankWidth * (index - 0.5)
		local shade = P.woodA
		if index % 2 == 0 then shade = P.woodB end
		if index % 7 == 0 then shade = P.woodDark end
		part(court, "Plank", Vector3.new(plankWidth * 0.94, 0.04, depth),
			CFrame.new(x, top + 0.02, 0), shade, Enum.Material.Wood, false)
	end

	local paint = folder(court, "Paint")
	local lineY = top + 0.06

	part(paint, "BoundaryN", Vector3.new(width - 2, 0.04, 0.5),
		CFrame.new(0, lineY, -(depth * 0.5 - 1.5)), P.paint, Enum.Material.SmoothPlastic, false)
	part(paint, "BoundaryS", Vector3.new(width - 2, 0.04, 0.5),
		CFrame.new(0, lineY, depth * 0.5 - 1.5), P.paint, Enum.Material.SmoothPlastic, false)
	part(paint, "BoundaryW", Vector3.new(0.5, 0.04, depth - 3),
		CFrame.new(-(width * 0.5 - 1.5), lineY, 0), P.paint, Enum.Material.SmoothPlastic, false)
	part(paint, "BoundaryE", Vector3.new(0.5, 0.04, depth - 3),
		CFrame.new(width * 0.5 - 1.5, lineY, 0), P.paint, Enum.Material.SmoothPlastic, false)

	for team = 1, 2 do
		local entry = CFG.Teams[team]
		local sign = -1
		if team == 2 then sign = 1 end

		local tint = part(paint, "HalfTint", Vector3.new(width - 4, 0.03, depth * 0.5 - 3),
			CFrame.new(0, lineY - 0.02, sign * depth * 0.25), entry.color, Enum.Material.SmoothPlastic, false)
		tint.Transparency = 0.9

		part(paint, "ThrowLine", Vector3.new(width - 4, 0.05, 0.45),
			CFrame.new(0, lineY, sign * (CFG.BotAI.CenterMargin + CFG.BotAI.ThrowLineOffset)),
			entry.color, Enum.Material.Neon, false)
	end

	local ringOuter = part(paint, "CenterRing", Vector3.new(0.3, 15, 15),
		CFrame.new(0, lineY, 0) * CFrame.Angles(0, 0, math.rad(90)), P.paint, Enum.Material.SmoothPlastic, false)
	ringOuter.Shape = Enum.PartType.Cylinder
	local ringInner = part(paint, "CenterFill", Vector3.new(0.32, 13.6, 13.6),
		CFrame.new(0, lineY + 0.01, 0) * CFrame.Angles(0, 0, math.rad(90)), P.woodA, Enum.Material.Wood, false)
	ringInner.Shape = Enum.PartType.Cylinder

	local logo = part(paint, "CenterLogo", Vector3.new(9, 0.05, 4),
		CFrame.new(0, lineY + 0.03, 0), P.woodDark, Enum.Material.SmoothPlastic, false)
	logo.Transparency = 1
	surfaceText(logo, Enum.NormalId.Top, "RAGDOLL\nDODGEBALL", P.paint)

	local pads = folder(root, "WallPads")
	for team = 1, 2 do
		local entry = CFG.Teams[team]
		local sign = -1
		if team == 2 then sign = 1 end
		local pad = part(pads, "Pad", Vector3.new(width, 6, 0.6),
			CFrame.new(0, 4, sign * (depth * 0.5 - 0.2)), entry.dark, Enum.Material.Fabric, true)
		pad.Reflectance = 0.02
		part(pads, "NeonTrim", Vector3.new(width, 0.28, 0.3),
			CFrame.new(0, 7.1, sign * (depth * 0.5 - 0.5)), entry.color, Enum.Material.Neon, false)
	end

	for _, side in ipairs({ -1, 1 }) do
		part(pads, "SidePad", Vector3.new(0.6, 6, depth),
			CFrame.new(side * (width * 0.5 - 0.2), 4, 0), P.steelDark, Enum.Material.Fabric, true)
		part(pads, "SideTrim", Vector3.new(0.3, 0.28, depth),
			CFrame.new(side * (width * 0.5 - 0.5), 7.1, 0), P.warm, Enum.Material.Neon, false)
	end
end

local function buildBleachers(root)
	local stands = folder(root, "Stands")
	local crowd = folder(root, "Crowd")
	local width = CFG.Arena.Width
	local depth = CFG.Arena.Depth

	for _, side in ipairs({ -1, 1 }) do
		local teamColor = CFG.Teams[1].color
		if side == 1 then teamColor = CFG.Teams[2].color end

		for row = 1, 4 do
			local z = side * (depth * 0.5 + 4 + row * 3.2)
			local y = 1.5 + row * 2.4

			part(stands, "Step", Vector3.new(width + 10, 2.4, 3.4),
				CFrame.new(0, y, z), P.steelDark, Enum.Material.Concrete, true)

			for seat = 1, 14 do
				local x = -width * 0.5 + 3 + (seat - 1) * ((width - 6) / 13)
				local seatColor = P.seatA
				if seat % 2 == 0 then seatColor = P.seatB end
				if seat % 5 == 0 then seatColor = teamColor end

				part(stands, "Seat", Vector3.new(2.1, 0.5, 2.1),
					CFrame.new(x, y + 1.45, z), seatColor, Enum.Material.SmoothPlastic, false)

				if rng:NextNumber() < 0.45 then
					local shirt = CROWD_SHIRTS[rng:NextInteger(1, #CROWD_SHIRTS)]
					local skin = SKIN[rng:NextInteger(1, #SKIN)]
					local height = rng:NextNumber(1.5, 2.0)
					local lean = rng:NextNumber(-0.12, 0.12)

					local torso = part(crowd, "Fan", Vector3.new(1.5, height, 0.9),
						CFrame.new(x, y + 1.7 + height * 0.5, z + side * 0.3) * CFrame.Angles(lean, 0, 0),
						shirt, Enum.Material.Fabric, false)
					torso.Reflectance = 0.01

					part(crowd, "Head", Vector3.new(0.95, 0.95, 0.95),
						CFrame.new(x, y + 1.7 + height + 0.55, z + side * 0.3),
						skin, Enum.Material.SmoothPlastic, false)
				end
			end
		end

		part(stands, "Rail", Vector3.new(width + 10, 0.3, 0.3),
			CFrame.new(0, 4.2, side * (depth * 0.5 + 3)), P.steel, Enum.Material.Metal, false)
	end
end

local function buildCeiling(root)
	local rig = folder(root, "CeilingRig")
	local width = CFG.Arena.Width
	local depth = CFG.Arena.Depth
	local height = CFG.Arena.CeilingHeight - 2

	for index = 1, 6 do
		local z = -depth * 0.5 + 6 + (index - 1) * ((depth - 12) / 5)
		part(rig, "Truss", Vector3.new(width + 8, 0.7, 0.7),
			CFrame.new(0, height, z), P.steel, Enum.Material.Metal, true)
		part(rig, "Brace", Vector3.new(0.4, 2.2, 0.4),
			CFrame.new(-width * 0.25, height - 1.2, z), P.steelDark, Enum.Material.Metal, false)
		part(rig, "Brace", Vector3.new(0.4, 2.2, 0.4),
			CFrame.new(width * 0.25, height - 1.2, z), P.steelDark, Enum.Material.Metal, false)
	end

	for index = 1, 8 do
		local x = -width * 0.36 + (index - 1) * ((width * 0.72) / 7)
		local z = -depth * 0.22
		if index % 2 == 0 then z = depth * 0.22 end

		local fixture = part(rig, "Fixture", Vector3.new(2.4, 0.8, 2.4),
			CFrame.new(x, height - 1.6, z), P.steelDark, Enum.Material.Metal, false)

		local lens = part(rig, "Lens", Vector3.new(2.0, 0.2, 2.0),
			CFrame.new(x, height - 2.1, z), P.warm, Enum.Material.Neon, false)

		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 78
		spot.Brightness = 3.2
		spot.Range = 58
		spot.Color = Color3.fromRGB(255, 238, 214)
		spot.Shadows = false
		spot.Parent = lens
	end
end

local function buildBanners(root)
	local banners = folder(root, "Banners")
	local width = CFG.Arena.Width
	local depth = CFG.Arena.Depth
	local height = CFG.Arena.CeilingHeight - 6

	for team = 1, 2 do
		local entry = CFG.Teams[team]
		local sign = -1
		if team == 2 then sign = 1 end

		local banner = part(banners, "TeamBanner", Vector3.new(16, 7, 0.25),
			CFrame.new(0, height, sign * (depth * 0.5 - 1.2)), entry.dark, Enum.Material.Fabric, false)
		surfaceText(banner, Enum.NormalId.Front, entry.name, entry.color)
		surfaceText(banner, Enum.NormalId.Back, entry.name, entry.color)

		part(banners, "Cord", Vector3.new(0.16, 3, 0.16),
			CFrame.new(-7, height + 5, sign * (depth * 0.5 - 1.2)), P.steel, Enum.Material.Metal, false)
		part(banners, "Cord", Vector3.new(0.16, 3, 0.16),
			CFrame.new(7, height + 5, sign * (depth * 0.5 - 1.2)), P.steel, Enum.Material.Metal, false)
	end

	for _, side in ipairs({ -1, 1 }) do
		local board = part(banners, "SideBoard", Vector3.new(0.3, 5, 22),
			CFrame.new(side * (width * 0.5 - 1.2), height, 0), P.cloth, Enum.Material.Fabric, false)
		local face = Enum.NormalId.Right
		if side == 1 then face = Enum.NormalId.Left end
		surfaceText(board, face, "RAGDOLL DODGEBALL", P.warm)
	end
end

local function buildRacks(root)
	local racks = folder(root, "Racks")
	local width = CFG.Arena.Width

	for _, side in ipairs({ -1, 1 }) do
		local x = side * (width * 0.5 + 6)
		part(racks, "Frame", Vector3.new(6, 0.4, 2.4),
			CFrame.new(x, 3.4, 0), P.steel, Enum.Material.Metal, true)
		part(racks, "Leg", Vector3.new(0.4, 3.4, 0.4),
			CFrame.new(x - 2.6, 1.7, 0), P.steelDark, Enum.Material.Metal, false)
		part(racks, "Leg", Vector3.new(0.4, 3.4, 0.4),
			CFrame.new(x + 2.6, 1.7, 0), P.steelDark, Enum.Material.Metal, false)

		for index = 1, 3 do
			local ball = part(racks, "SpareBall", Vector3.new(2.2, 2.2, 2.2),
				CFrame.new(x - 1.9 + (index - 1) * 1.9, 4.7, 0),
				CFG.Teams[1].color, Enum.Material.SmoothPlastic, false)
			if side == 1 then ball.Color = CFG.Teams[2].color end
			ball.Shape = Enum.PartType.Ball
		end
	end
end

local function build()
	if Workspace:FindFirstChild("WorldDecor") then return end

	local arena = Workspace:WaitForChild("Arena", 30)
	if not arena then
		warn("[World] Arena not found, decoration skipped")
		return
	end

	setupLighting()

	local root = Instance.new("Folder")
	root.Name = "WorldDecor"
	root.Parent = Workspace

	dressCourt(root, arena)
	buildBleachers(root)
	buildCeiling(root)
	buildBanners(root)
	buildRacks(root)

	local count = 0
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then count += 1 end
	end
	print(string.format("[World] art pass live: %d decor parts, Future lighting, 8 spots", count))
end

task.spawn(build)
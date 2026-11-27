-- SlamFX: presentation for the existing Cannon ultimate and zone rewards.
-- ImpactController remains the sole owner of camera shake and FOV.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("SlamCatalog"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SlamRemotes")
local slamRemote = remotes:WaitForChild("SlamHit")
local zoneRemote = remotes:WaitForChild("ZoneReward")
local armedRemote = remotes:WaitForChild("SlamArmed")

local INK = Color3.fromRGB(8, 12, 26)
local DIM = Color3.fromRGB(158, 174, 210)
local HOT = Catalog.Slam.BallColor
local CORE = Catalog.Slam.CoreColor

local worldFolder = workspace:FindFirstChild("RDSlamFX")
if not worldFolder then
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "RDSlamFX"
	worldFolder.Parent = workspace
end

local gui = Instance.new("ScreenGui")
gui.Name = "RDSlamUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 19
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

-- Armed banner -------------------------------------------------------------

local armedBar = make("Frame", {
	Size = UDim2.fromOffset(268, 34),
	Position = UDim2.new(0.5, 0, 0, 128),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 9) }, armedBar)
make("UIStroke", { Color = HOT, Thickness = 2, Transparency = 0.2 }, armedBar)

local armedText = make("TextLabel", {
	Size = UDim2.new(1, -16, 1, 0),
	Position = UDim2.fromOffset(8, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	TextColor3 = HOT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "SLAM ARMED",
}, armedBar)

local armedUntil = 0
armedRemote.OnClientEvent:Connect(function(armed, seconds)
	if armed then
		armedUntil = os.clock() + (typeof(seconds) == "number" and seconds or Catalog.Slam.ArmWindow)
		armedBar.Visible = true
	else
		armedUntil = 0
		armedBar.Visible = false
	end
end)

-- K.O. callout -------------------------------------------------------------

local koFrame = make("Frame", {
	Size = UDim2.fromOffset(420, 150),
	Position = UDim2.new(0.5, 0, 0.34, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local koScale = make("UIScale", { Scale = 0.5 }, koFrame)

local koWord = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 96),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
	TextColor3 = CORE,
	TextStrokeTransparency = 0.15,
	TextStrokeColor3 = Color3.fromRGB(60, 10, 0),
	Text = Catalog.Slam.Label,
}, koFrame)

local koSub = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromOffset(0, 98),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
	TextColor3 = HOT,
	TextStrokeTransparency = 0.4,
	Text = "",
}, koFrame)

local koHideAt = 0
local function showKO(zoneLabel, critical)
	koSub.Text = zoneLabel
	koWord.TextColor3 = critical and Color3.fromRGB(255, 120, 230) or CORE
	koFrame.Visible = true
	koScale.Scale = 0.5
	koHideAt = os.clock() + 1.5
	TweenService:Create(koScale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Zone reward toast --------------------------------------------------------

local rewardCard = make("Frame", {
	Size = UDim2.fromOffset(230, 56),
	Position = UDim2.new(1, -16, 0.5, -40),
	AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 11) }, rewardCard)
local rewardStroke = make("UIStroke", { Color = HOT, Thickness = 2, Transparency = 0.25 }, rewardCard)

local rewardLabel = make("TextLabel", {
	Size = UDim2.new(1, -14, 0, 24),
	Position = UDim2.fromOffset(7, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 16,
	TextColor3 = HOT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, rewardCard)

local rewardDetail = make("TextLabel", {
	Size = UDim2.new(1, -14, 0, 18),
	Position = UDim2.fromOffset(7, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, rewardCard)

local rewardHideAt = 0
zoneRemote.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	rewardLabel.Text = tostring(data.label or "HIT")
	if typeof(data.color) == "Color3" then
		rewardLabel.TextColor3 = data.color
		rewardStroke.Color = data.color
	end
	local parts = {}
	if (data.coins or 0) > 0 then table.insert(parts, "+" .. data.coins .. " coins") end
	if (data.xp or 0) > 0 then table.insert(parts, "+" .. data.xp .. " XP") end
	if (data.hype or 0) > 0 then table.insert(parts, "+" .. data.hype .. " HYPE") end
	if data.slam then table.insert(parts, "SLAM bonus") end
	if #parts == 0 then table.insert(parts, "clean hit") end
	rewardDetail.Text = table.concat(parts, "   ")
	rewardCard.Visible = true
	rewardHideAt = os.clock() + 1.8
end)

-- Ball trail ---------------------------------------------------------------

local function dressBall(ball)
	if not ball:IsA("BasePart") or ball:FindFirstChild("SlamTrail") then return end

	local a0 = Instance.new("Attachment")
	a0.Name = "SlamA"
	a0.Position = Vector3.new(0, ball.Size.Y * 0.45, 0)
	a0.Parent = ball

	local a1 = Instance.new("Attachment")
	a1.Name = "SlamB"
	a1.Position = Vector3.new(0, -ball.Size.Y * 0.45, 0)
	a1.Parent = ball

	local trail = Instance.new("Trail")
	trail.Name = "SlamTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(CORE, HOT)
	trail.Lifetime = 0.5
	trail.MinLength = 0.1
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Catalog.Slam.TrailWidth),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.85
	trail.FaceCamera = true
	trail.Parent = ball

	task.delay(3, function()
		if trail.Parent then trail:Destroy() end
		if a0.Parent then a0:Destroy() end
		if a1.Parent then a1:Destroy() end
	end)
end

local function impactBurst(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = root.CFrame
	anchor.Parent = worldFolder

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(CORE, HOT)
	emitter.Lifetime = NumberRange.new(0.4, 0.85)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(20, 40)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.9
	emitter.Parent = attachment
	emitter:Emit(48)

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = CORE
	ring.Size = Vector3.new(0.2, 3, 3)
	ring.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.25
	ring.Parent = worldFolder
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 30, 30),
		Transparency = 1,
	}):Play()

	task.delay(1.1, function()
		if anchor.Parent then anchor:Destroy() end
		if ring.Parent then ring:Destroy() end
	end)
end

slamRemote.OnClientEvent:Connect(function(kind, a, b, zone)
	if kind == "launch" then
		if typeof(a) == "Instance" and a:IsA("BasePart") then dressBall(a) end
	elseif kind == "impact" then
		if typeof(a) == "Instance" and a:IsA("Model") then impactBurst(a) end
		local entry = Catalog.Zones[zone] or Catalog.Zones[Catalog.DefaultZone]
		if b == player then showKO(entry.label, entry.critical) end
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if armedBar.Visible then
		local left = armedUntil - now
		if left <= 0 then
			armedBar.Visible = false
		else
			armedText.Text = string.format("SLAM ARMED   %.1fs   THROW NOW", left)
		end
	end
	if koFrame.Visible and now > koHideAt then koFrame.Visible = false end
	if rewardCard.Visible and now > rewardHideAt then rewardCard.Visible = false end
end)

print("[SlamFX] Cannon banner, K.O. callout and zone rewards live")

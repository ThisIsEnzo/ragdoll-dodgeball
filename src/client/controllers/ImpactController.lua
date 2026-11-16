-- ImpactController: вся косметика удара. Клиент, ноль влияния на геймплей.
-- Тряска камеры, удар FOV, вспышка, звёзды из головы, комикс-надпись, трейл мяча, звук.
-- ВНИМАНИЕ: звуки ниже — встроенные движковые плейсхолдеры. Замени на свои ассеты до релиза.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local ImpactController = {}

local SFX = {
	hit = "rbxasset://sounds/collide.wav",
	thump = "rbxasset://sounds/bass.wav",
	catch = "rbxasset://sounds/electronicpingshort.wav",
	snap = "rbxasset://sounds/snap.wav",
	whiff = "rbxasset://sounds/hit.wav",
	hurt = "rbxasset://sounds/uuhhh.mp3",
}

local STAR_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local shake = 0
local fovOffset = 0
local correction
local soundsThisFrame = 0
local trailsBound = {}

local function juiceOn()
	return CFG.Juice.Enabled
end

local function cameraDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then return 0 end
	return (camera.CFrame.Position - position).Magnitude
end

local function falloff(position: Vector3): number
	local d = cameraDistance(position)
	return math.clamp(1 - d / CFG.Juice.ShakeMaxDistance, 0.15, 1)
end

local function playSound(id: string, position: Vector3, volume: number, speed: number)
	if soundsThisFrame >= CFG.Juice.MaxSoundsPerFrame then return end
	soundsThisFrame += 1

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume * CFG.Juice.SoundVolume
	sound.PlaybackSpeed = speed
	sound.RollOffMaxDistance = 140
	sound.RollOffMinDistance = 8
	sound.Parent = anchor
	sound:Play()

	Debris:AddItem(anchor, 3)
end

local function comicText(adornee: Instance, text: string, color: Color3, size: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 70)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(20, 12, 0)
	label.TextStrokeTransparency = 0.25
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Rotation = math.random(-12, 12)
	label.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = billboard

	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = size }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		StudsOffset = Vector3.new(0, 6.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.75), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(billboard, 0.95)
end

local function stars(character: Model, color: Color3, count: number)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 0.9, 0)
	attachment.Parent = head

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = STAR_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(count)

	Debris:AddItem(attachment, 1.4)
end

local function punch(power: number, flash: number)
	shake = math.min(2.2, shake + power)
	fovOffset = math.min(CFG.Juice.FovPunch * 1.6, fovOffset + CFG.Juice.FovPunch * power)
	if correction and flash > 0 then
		correction.Brightness = math.min(0.22, correction.Brightness + CFG.Juice.FlashBrightness * flash)
		correction.Saturation = math.min(0.8, correction.Saturation + CFG.Juice.FlashSaturation * flash)
	end
end

local function rootOf(character: any): BasePart?
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return nil end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function onKO(character: any, second: any, speed: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end

	local impactSpeed = if typeof(speed) == "number" then speed else 70
	local heavy = math.clamp(impactSpeed / CFG.Throw.SpeedMax, 0.35, 1)
	local near = falloff(root.Position)

	punch(0.55 + heavy * 0.9 * near, 0.6 + heavy * 0.6)
	stars(character, Color3.fromRGB(255, 220, 120), math.floor(CFG.Juice.StarsCount * heavy))

	local words = CFG.Juice.BonkWords
	comicText(root, words[math.random(1, #words)], Color3.fromRGB(255, 197, 61), 0.9 + heavy * 0.5)

	playSound(SFX.hit, root.Position, 0.75, 0.85 + math.random() * 0.4)
	if heavy > 0.6 then
		playSound(SFX.thump, root.Position, 0.5, 0.9 + math.random() * 0.2)
	end
	if math.random() < 0.35 then
		playSound(SFX.hurt, root.Position, 0.3, 1.1 + math.random() * 0.3)
	end
end

local function onCatch(character: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end

	punch(1.5, 1.4)
	stars(character, Color3.fromRGB(140, 255, 130), CFG.Juice.StarsCount + 6)
	comicText(root, "CAUGHT!", Color3.fromRGB(124, 255, 79), 1.5)
	playSound(SFX.catch, root.Position, 0.8, 1.0)
	playSound(SFX.snap, root.Position, 0.5, 1.4)
end

local function onThrow(ball: any)
	if not juiceOn() then return end
	if typeof(ball) ~= "Instance" or not ball:IsA("BasePart") then return end
	playSound(SFX.snap, ball.Position, 0.28, 1.5 + math.random() * 0.4)
end

local function onWhiff(character: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end
	playSound(SFX.whiff, root.Position, 0.25, 1.6)
end

local function onRevive(character: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end
	stars(character, Color3.fromRGB(124, 255, 79), 12)
	comicText(root, "BACK IN!", Color3.fromRGB(124, 255, 79), 1.1)
	playSound(SFX.catch, root.Position, 0.5, 1.35)
end

local function onDodge(character: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end
	playSound(SFX.snap, root.Position, 0.2, 2.0)
end

local function onUlt(character: any, ultId: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end
	punch(0.9, 1.0)
	comicText(root, tostring(ultId or "ULT"):upper() .. "!", Color3.fromRGB(255, 79, 216), 1.3)
	playSound(SFX.thump, root.Position, 0.6, 1.2)
end

local function onShield(character: any)
	if not juiceOn() then return end
	local root = rootOf(character)
	if not root then return end
	stars(character, Color3.fromRGB(46, 155, 255), 10)
	comicText(root, "BLOCKED", Color3.fromRGB(46, 155, 255), 1.0)
	playSound(SFX.snap, root.Position, 0.4, 0.8)
end

local function onPing(position: any)
	if not juiceOn() then return end
	if typeof(position) ~= "Vector3" then return end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position + Vector3.new(0, 4, 0)
	anchor.Parent = workspace

	comicText(anchor, "!", Color3.fromRGB(255, 79, 216), 1.2)
	playSound(SFX.catch, position, 0.3, 1.8)
	Debris:AddItem(anchor, 1.2)
end

local function bindTrail(ball: Instance)
	if not ball:IsA("BasePart") or trailsBound[ball] then return end
	trailsBound[ball] = true

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, ball.Size.Y * 0.4, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -ball.Size.Y * 0.4, 0)
	a1.Parent = ball

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.22
	trail.MinLength = 0.4
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 77))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = ball

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 197, 61)
	glow.Brightness = 0.7
	glow.Range = 9
	glow.Enabled = false
	glow.Parent = ball

	task.spawn(function()
		while ball.Parent do
			local moving = ball.AssemblyLinearVelocity.Magnitude > CFG.Juice.TrailMinSpeed
			local active = juiceOn() and moving and not ball.Anchored
			trail.Enabled = active
			glow.Enabled = juiceOn()
			task.wait(0.1)
		end
	end)

	ball.AncestryChanged:Connect(function(_, parent)
		if not parent then trailsBound[ball] = nil end
	end)
end

function ImpactController.Init()
	correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "RDImpactCorrection"
	correction.Brightness = 0
	correction.Saturation = 0
	correction.Contrast = 0
	correction.Parent = Lighting
end

function ImpactController.Start()
	local fx = Net.Get("FXEvent")
	if fx then
		fx.OnClientEvent:Connect(function(kind, a, b, c)
			if kind == "ko" then
				onKO(a, b, c)
			elseif kind == "catch" then
				onCatch(a)
			elseif kind == "throw" then
				onThrow(a)
			elseif kind == "whiff" then
				onWhiff(a)
			elseif kind == "revive" then
				onRevive(a)
			elseif kind == "dodge" then
				onDodge(a)
			elseif kind == "ult" then
				onUlt(a, b)
			elseif kind == "shield" then
				onShield(a)
			elseif kind == "ping" then
				onPing(a)
			end
		end)
	end

	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do bindTrail(ball) end
	CollectionService:GetInstanceAddedSignal("Dodgeball"):Connect(bindTrail)

	RunService:BindToRenderStep("RDImpact", Enum.RenderPriority.Camera.Value + 1, function(dt)
		soundsThisFrame = 0
		local camera = workspace.CurrentCamera
		if not camera then return end

		local targetFov = CFG.Juice.FovBase - fovOffset
		camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * math.min(1, dt * CFG.Juice.FovRecover)
		fovOffset = math.max(0, fovOffset - dt * CFG.Juice.FovPunch * 4)

		if shake > 0.01 and juiceOn() then
			local t = os.clock()
			local s = shake * CFG.Juice.ShakeScale
			camera.CFrame = camera.CFrame
				* CFrame.new(math.noise(t * 34, 0, 0) * s * 0.32, math.noise(0, t * 34, 0) * s * 0.32, 0)
				* CFrame.Angles(0, 0, math.noise(0, 0, t * 28) * s * 0.022)
		end
		shake = math.max(0, shake - dt * CFG.Juice.ShakeDecay * (1 + shake))

		if correction then
			correction.Brightness = math.max(0, correction.Brightness - dt * 0.9)
			correction.Saturation = math.max(0, correction.Saturation - dt * 2.4)
		end
	end)
end

return ImpactController

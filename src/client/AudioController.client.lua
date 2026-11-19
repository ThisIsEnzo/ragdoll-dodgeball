-- AudioController: the whole sound design runs on the client.
-- Server events arrive on FXEvent / MatchState / LevelUp and are turned into
-- layered, spatialised, pitch-varied playback through a real mixer.
--
-- Nothing here creates sound without a visible cause: every cue is bound to
-- an event the player can see. One mute control at the top kills all output.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("AudioCatalog"))
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer
local rng = Random.new()

-- Mixer -------------------------------------------------------------------

local groups = {}
local master = Instance.new("SoundGroup")
master.Name = "RDMaster"
master.Volume = Catalog.Defaults.Master
master.Parent = SoundService
groups.Master = master

for _, name in ipairs(Catalog.Groups) do
	local group = Instance.new("SoundGroup")
	group.Name = "RD" .. name
	group.Volume = Catalog.Defaults[name] or 0.8
	group.SoundGroup = master
	group.Parent = SoundService
	groups[name] = group
end

local compressor = Instance.new("CompressorSoundEffect")
compressor.Threshold = -14
compressor.Ratio = 3
compressor.Attack = 0.004
compressor.Release = 0.18
compressor.Parent = master

local reverb = Instance.new("ReverbSoundEffect")
reverb.DecayTime = 1.5
reverb.Density = 0.8
reverb.Diffusion = 0.9
reverb.WetLevel = -14
reverb.Parent = groups.SFX

local muted = false

-- Pools -------------------------------------------------------------------

local flatFolder = Instance.new("Folder")
flatFolder.Name = "RDAudio2D"
flatFolder.Parent = SoundService

local worldFolder = Instance.new("Folder")
worldFolder.Name = "RDAudio3D"
worldFolder.Parent = Workspace

local flatPool = {}
local worldPool = {}

local function takeFlat()
	local sound = table.remove(flatPool)
	if sound then return sound end
	sound = Instance.new("Sound")
	sound.Parent = flatFolder
	return sound
end

local function takeWorld()
	local entry = table.remove(worldPool)
	if entry then return entry end
	local anchor = Instance.new("Part")
	anchor.Name = "AudioAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Parent = worldFolder
	local sound = Instance.new("Sound")
	sound.Parent = anchor
	return { anchor = anchor, sound = sound }
end

local function recycle(entry, isWorld)
	entry.sound:Stop()
	entry.sound.TimePosition = 0
	if isWorld then
		table.insert(worldPool, entry)
	else
		table.insert(flatPool, entry.sound)
	end
end

local function envelope(sound, peak, decay)
	if decay <= 0 then return end
	sound.Volume = peak
	local tween = TweenService:Create(sound, TweenInfo.new(decay, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 })
	tween:Play()
	tween.Completed:Connect(function()
		tween:Destroy()
	end)
end

local function cameraPosition()
	local camera = Workspace.CurrentCamera
	if camera then return camera.CFrame.Position end
	return Vector3.zero
end

local function distanceScale(position)
	if not position then return 1 end
	local d = (cameraPosition() - position).Magnitude
	if d >= Catalog.MaxDistance then return 0 end
	if d <= Catalog.NearDistance then return 1 end
	local t = (d - Catalog.NearDistance) / (Catalog.MaxDistance - Catalog.NearDistance)
	return (1 - t) * (1 - t)
end

local budget = 0

local function play(name, position, pitchBias, volumeBias)
	local def = Catalog.Sounds[name]
	if not def then return end
	if muted then return end

	local scale = distanceScale(position)
	if scale <= 0.01 then return end

	local group = groups[def.group] or groups.SFX
	local bias = pitchBias or 1
	local vol = (volumeBias or 1) * scale

	for _, layer in ipairs(def.layers) do
		if budget < 14 then
			budget += 1
			local isWorld = position ~= nil
			local entry
			local sound
			if isWorld then
				entry = takeWorld()
				sound = entry.sound
				entry.anchor.Position = position
				sound.RollOffMode = Enum.RollOffMode.InverseTapered
				sound.RollOffMinDistance = Catalog.NearDistance
				sound.RollOffMaxDistance = Catalog.MaxDistance
			else
				sound = takeFlat()
			end

			sound.SoundId = layer.id
			sound.SoundGroup = group
			sound.PlaybackSpeed = layer.pitch * bias * (1 + rng:NextNumber(-layer.spread, layer.spread))
			local peak = layer.volume * vol
			sound.Volume = peak
			sound.Looped = false
			sound.TimePosition = 0

			local function fire()
				if not sound.Parent then return end
				sound:Play()
				envelope(sound, peak, layer.decay)
				task.delay(math.max(layer.decay + 0.35, 1.1), function()
					if isWorld then
						recycle(entry, true)
					else
						recycle({ sound = sound }, false)
					end
				end)
			end

			if layer.delay > 0 then
				task.delay(layer.delay, fire)
			else
				fire()
			end
		end
	end
end

-- Ambience ----------------------------------------------------------------

local ambienceAnchor = Instance.new("Part")
ambienceAnchor.Name = "AmbienceAnchor"
ambienceAnchor.Anchored = true
ambienceAnchor.CanCollide = false
ambienceAnchor.CanQuery = false
ambienceAnchor.Transparency = 1
ambienceAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
ambienceAnchor.Position = Vector3.new(0, 6, 0)
ambienceAnchor.Parent = worldFolder

local ambienceVoices = {}
for i = 1, Catalog.Ambience.voices do
	local sound = Instance.new("Sound")
	sound.SoundId = Catalog.Ambience.id
	sound.Looped = true
	sound.SoundGroup = groups.Ambience
	sound.PlaybackSpeed = rng:NextNumber(Catalog.Ambience.pitchMin, Catalog.Ambience.pitchMax)
	sound.Volume = Catalog.Ambience.volume * rng:NextNumber(0.7, 1.3)
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 30
	sound.RollOffMaxDistance = 220
	sound.Parent = ambienceAnchor
	sound:Play()
	pcall(function() sound.TimePosition = rng:NextNumber(0, 1.5) end)
	table.insert(ambienceVoices, sound)
end

-- Venue reverb ------------------------------------------------------------

local function applyVenue(themeId)
	local preset = Catalog.Reverb[themeId]
	if not preset then return end
	for key, value in pairs(preset) do
		reverb[key] = value
	end
end

task.spawn(function()
	local decor = Workspace:WaitForChild("WorldDecor", 40)
	if not decor then return end
	local theme = decor:GetAttribute("Theme")
	if typeof(theme) == "string" then applyVenue(theme) end
	decor:GetAttributeChangedSignal("Theme"):Connect(function()
		local nextTheme = decor:GetAttribute("Theme")
		if typeof(nextTheme) == "string" then applyVenue(nextTheme) end
	end)
end)

-- Event binding -----------------------------------------------------------

local function positionOf(subject)
	if typeof(subject) == "Instance" then
		if subject:IsA("BasePart") then return subject.Position end
		if subject:IsA("Model") then
			local root = subject:FindFirstChild("HumanoidRootPart") or subject:FindFirstChild("Head")
			if root then return root.Position end
		end
	end
	if typeof(subject) == "number" then
		local other = Players:GetPlayerByUserId(subject)
		local character = other and other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then return root.Position end
	end
	return nil
end

local lastState = nil
local lastTimer = -1
local aliveCount = 3

local fx = Net.Get("FXEvent")
if fx then
	fx.OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "throw" then
			play("throw", positionOf(a))
		elseif kind == "ko" then
			local pos = positionOf(a)
			local heavy = false
			if typeof(a) == "Instance" and a:IsA("Model") then
				heavy = false
			end
			if typeof(c) == "number" and c > 55 then heavy = true end
			if heavy then
				play("bonkHeavy", pos)
			else
				play("bonk", pos)
			end
			play("cheer", Vector3.new(0, 8, 0), 1, 0.8)
		elseif kind == "catch" then
			play("catch", positionOf(a))
			play("gasp", Vector3.new(0, 8, 0))
			play("cheer", Vector3.new(0, 8, 0), 1.1, 1.0)
		elseif kind == "whiff" then
			play("whiff", positionOf(a))
		elseif kind == "dodge" then
			play("dodge", positionOf(a))
		elseif kind == "revive" then
			play("revive", positionOf(a))
		elseif kind == "ult" then
			play("ult", positionOf(a))
			play("cheer", Vector3.new(0, 8, 0), 0.9, 0.9)
		elseif kind == "shield" then
			play("shield", positionOf(a))
		elseif kind == "stance" then
			play("pickup", positionOf(a), 1.3, 0.5)
		elseif kind == "ping" then
			if typeof(a) == "Vector3" then play("coin", a) end
		end
	end)
end

local matchState = Net.Get("MatchState")
if matchState then
	matchState.OnClientEvent:Connect(function(state)
		if typeof(state) ~= "table" then return end

		local timer = state.timer or 0
		local phase = state.state

		if phase == "Warmup" and timer ~= lastTimer and timer > 0 and timer <= 3 then
			play("countdown", nil, 1 + (3 - timer) * 0.12)
		end

		if phase == "SuddenDeath" and lastState ~= "SuddenDeath" then
			play("sudden")
			play("gasp", Vector3.new(0, 8, 0), 0.8, 1.2)
		end

		if phase == "MatchEnd" and lastState ~= "MatchEnd" then
			local character = player.Character
			local myTeam = character and character:GetAttribute("Team")
			if myTeam == state.winner then
				play("victory")
				play("cheer", Vector3.new(0, 8, 0), 1.05, 1.4)
			else
				play("defeat")
			end
		end

		local mine = 3
		local character = player.Character
		local team = character and character:GetAttribute("Team")
		if team == 1 then mine = state.alive1 or 3 else mine = state.alive2 or 3 end
		if mine == 1 and aliveCount > 1 and phase == "Live" then
			play("gasp", Vector3.new(0, 8, 0), 0.7, 1.1)
		end
		aliveCount = mine

		lastTimer = timer
		lastState = phase
	end)
end

local levelUp = Net.Get("LevelUp")
if levelUp then
	levelUp.OnClientEvent:Connect(function()
		play("levelUp")
	end)
end

local profile = Net.Get("ProfileState")
local lastCoins = nil
if profile then
	profile.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then return end
		if lastCoins and data.coins and data.coins > lastCoins then
			play("coin")
		end
		lastCoins = data.coins
	end)
end

-- Ball bounce detection, tied to something visible -------------------------

local bounceMemory = {}
task.spawn(function()
	while true do
		task.wait(0.08)
		local balls = Workspace:FindFirstChild("Balls")
		if balls then
			for _, ball in ipairs(balls:GetChildren()) do
				if ball:IsA("BasePart") then
					local v = ball.AssemblyLinearVelocity
					local flat = Vector3.new(v.X, 0, v.Z)
					if flat.Magnitude > 18 then
						local dir = flat.Unit
						local prev = bounceMemory[ball]
						if prev and prev:Dot(dir) < -0.3 then
							play("bounce", ball.Position, 1, 0.7)
						end
						bounceMemory[ball] = dir
					else
						bounceMemory[ball] = nil
					end
				end
			end
		end
	end
end)

-- Mixer UI ----------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "RDAudio"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local muteButton = make("TextButton", {
	Size = UDim2.fromOffset(112, 40),
	Position = UDim2.new(1, -224, 0, 12),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(150, 255, 60),
	TextColor3 = Color3.fromRGB(10, 28, 6),
	Font = Enum.Font.FredokaOne,
	TextSize = 14,
	Text = "SOUND ON",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, muteButton)
make("UIStroke", { Color = Color3.fromRGB(10, 28, 6), Thickness = 1.5, Transparency = 0.6 }, muteButton)

local mixer = make("Frame", {
	Size = UDim2.fromOffset(232, 196),
	Position = UDim2.new(1, -224, 0, 58),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(12, 18, 36),
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, mixer)
make("UIStroke", { Color = Color3.fromRGB(150, 255, 60), Thickness = 2, Transparency = 0.4 }, mixer)

make("TextLabel", {
	Size = UDim2.new(1, -20, 0, 20),
	Position = UDim2.fromOffset(10, 8),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(150, 255, 60),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "MIXER",
}, mixer)

local sliders = {}
local order = { "Master", "SFX", "UI", "Crowd", "Ambience" }

for index, name in ipairs(order) do
	local y = 32 + (index - 1) * 32

	make("TextLabel", {
		Size = UDim2.fromOffset(70, 16),
		Position = UDim2.fromOffset(10, y),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(200, 214, 242),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = string.upper(name),
	}, mixer)

	local track = make("Frame", {
		Size = UDim2.fromOffset(120, 8),
		Position = UDim2.fromOffset(80, y + 5),
		BackgroundColor3 = Color3.fromRGB(28, 36, 62),
		BorderSizePixel = 0,
	}, mixer)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local fill = make("Frame", {
		Size = UDim2.fromScale(Catalog.Defaults[name] or 0.8, 1),
		BackgroundColor3 = Color3.fromRGB(150, 255, 60),
		BorderSizePixel = 0,
	}, track)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

	local knob = make("TextButton", {
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(Catalog.Defaults[name] or 0.8, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(240, 248, 255),
		Text = "",
		AutoButtonColor = false,
	}, track)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	local readout = make("TextLabel", {
		Size = UDim2.fromOffset(30, 16),
		Position = UDim2.fromOffset(202, y),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(150, 255, 60),
		Text = tostring(math.floor((Catalog.Defaults[name] or 0.8) * 100)),
	}, mixer)

	sliders[name] = { track = track, fill = fill, knob = knob, readout = readout }
end

local function setLevel(name, value)
	value = math.clamp(value, 0, 1)
	local group = groups[name]
	if group then group.Volume = value end
	local s = sliders[name]
	if s then
		s.fill.Size = UDim2.fromScale(value, 1)
		s.knob.Position = UDim2.new(value, 0, 0.5, 0)
		s.readout.Text = tostring(math.floor(value * 100))
	end
end

local UserInputService = game:GetService("UserInputService")
local dragging = nil

for name, s in pairs(sliders) do
	local function updateFromInput(x)
		local abs = s.track.AbsolutePosition.X
		local width = s.track.AbsoluteSize.X
		if width <= 0 then return end
		setLevel(name, (x - abs) / width)
	end

	s.knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = name
			updateFromInput(input.Position.X)
		end
	end)

	s.track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = name
			updateFromInput(input.Position.X)
			play("hover")
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local s = sliders[dragging]
		if not s then return end
		local abs = s.track.AbsolutePosition.X
		local width = s.track.AbsoluteSize.X
		if width <= 0 then return end
		setLevel(dragging, (input.Position.X - abs) / width)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			play("click")
			dragging = nil
		end
	end
end)

local function refreshMute()
	if muted then
		master.Volume = 0
		muteButton.Text = "SOUND OFF"
		muteButton.BackgroundColor3 = Color3.fromRGB(120, 136, 166)
		muteButton.TextColor3 = Color3.fromRGB(240, 246, 255)
	else
		master.Volume = Catalog.Defaults.Master
		local s = sliders.Master
		if s then
			master.Volume = groups.Master.Volume
		end
		muteButton.Text = "SOUND ON"
		muteButton.BackgroundColor3 = Color3.fromRGB(150, 255, 60)
		muteButton.TextColor3 = Color3.fromRGB(10, 28, 6)
	end
end

local storedMaster = Catalog.Defaults.Master

muteButton.Activated:Connect(function()
	if not muted then
		storedMaster = groups.Master.Volume
		muted = true
		master.Volume = 0
		muteButton.Text = "SOUND OFF"
		muteButton.BackgroundColor3 = Color3.fromRGB(120, 136, 166)
		muteButton.TextColor3 = Color3.fromRGB(240, 246, 255)
	else
		muted = false
		master.Volume = storedMaster
		muteButton.Text = "SOUND ON"
		muteButton.BackgroundColor3 = Color3.fromRGB(150, 255, 60)
		muteButton.TextColor3 = Color3.fromRGB(10, 28, 6)
		play("click")
	end
end)

muteButton.MouseEnter:Connect(function()
	mixer.Visible = true
end)

local mixerPinned = false
muteButton.MouseButton2Click:Connect(function()
	mixerPinned = not mixerPinned
	mixer.Visible = mixerPinned
end)

gui.DescendantAdded:Connect(function() end)

RunService.Heartbeat:Connect(function()
	budget = 0
	if not mixerPinned then
		local mouse = UserInputService:GetMouseLocation()
		local abs = mixer.AbsolutePosition
		local size = mixer.AbsoluteSize
		local babs = muteButton.AbsolutePosition
		local bsize = muteButton.AbsoluteSize
		local overMixer = mouse.X >= abs.X - 8 and mouse.X <= abs.X + size.X + 8
			and mouse.Y >= abs.Y - 8 and mouse.Y <= abs.Y + size.Y + 8
		local overButton = mouse.X >= babs.X - 8 and mouse.X <= babs.X + bsize.X + 8
			and mouse.Y >= babs.Y - 8 and mouse.Y <= babs.Y + bsize.Y + 8
		mixer.Visible = overMixer or overButton or dragging ~= nil
	end
end)

for name, value in pairs(Catalog.Defaults) do
	setLevel(name, value)
end
refreshMute()

print("[Audio] layered sound design live: mixer, spatial cues, crowd, venue reverb")
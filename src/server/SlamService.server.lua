-- SlamService: rewards precise KOs and presents the existing Cannon as SLAM.
-- The authoritative throw path sets IsSlam synchronously; no polling race.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Catalog = require(Shared:WaitForChild("SlamCatalog"))
local HitZones = require(Shared:WaitForChild("HitZones"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")
local AbilityService = Resolve.Require(ServerScriptService, "AbilityService")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")

local folder = ReplicatedStorage:FindFirstChild("SlamRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "SlamRemotes"
	folder.Parent = ReplicatedStorage
end

local function makeRemote(name)
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local slamRemote = makeRemote("SlamHit")
local zoneRemote = makeRemote("ZoneReward")
local armedRemote = makeRemote("SlamArmed")

-- Dodge charge -------------------------------------------------------------

local lastDodge = {}

local function hookDodge(player)
	player:GetAttributeChangedSignal("DodgeReadyAt"):Connect(function()
		local stamp = player:GetAttribute("DodgeReadyAt")
		if typeof(stamp) ~= "number" or stamp <= 0 then return end
		if lastDodge[player.UserId] == stamp then return end
		lastDodge[player.UserId] = stamp

		local character = player.Character
		if not character or character:GetAttribute("Benched") then return end
		AbilityService.AddHype(player, Catalog.Charge.Dodge)
	end)
end

Players.PlayerAdded:Connect(hookDodge)
for _, player in ipairs(Players:GetPlayers()) do hookDodge(player) end

Players.PlayerRemoving:Connect(function(player)
	lastDodge[player.UserId] = nil
end)

-- Cannon armed state -------------------------------------------------------

local function hookArm(player)
	player:GetAttributeChangedSignal("CannonUntil"):Connect(function()
		local until_ = player:GetAttribute("CannonUntil")
		if typeof(until_) == "number" then
			armedRemote:FireClient(player, true, math.max(0, until_ - os.clock()))
		else
			armedRemote:FireClient(player, false, 0)
		end
	end)
end

Players.PlayerAdded:Connect(hookArm)
for _, player in ipairs(Players:GetPlayers()) do hookArm(player) end

-- Ball presentation --------------------------------------------------------

local BASE_BALL_COLOR = Color3.fromRGB(255, 197, 61)
local dressed = {}

local function resetBall(ball)
	if not ball or not ball.Parent then return end
	ball:SetAttribute("IsSlam", false)
	ball.Color = BASE_BALL_COLOR
	local glow = ball:FindFirstChild("SlamGlow")
	if glow then glow:Destroy() end
	dressed[ball] = nil
end

local function dressBall(ball)
	if not ball:IsA("BasePart") or dressed[ball] then return end
	dressed[ball] = true
	ball.Color = Catalog.Slam.BallColor

	local glow = ball:FindFirstChild("SlamGlow")
	if not glow then
		glow = Instance.new("PointLight")
		glow.Name = "SlamGlow"
		glow.Brightness = 2.2
		glow.Range = 12
		glow.Color = Catalog.Slam.CoreColor
		glow.Shadows = false
		glow.Parent = ball
	end

	local thrower = BallService.LastThrower(ball)
	slamRemote:FireAllClients("launch", ball, thrower)
end

local function watchBall(ball)
	if not ball:IsA("BasePart") then return end
	ball:GetAttributeChangedSignal("IsSlam"):Connect(function()
		if ball:GetAttribute("IsSlam") == true then
			dressBall(ball)
		else
			resetBall(ball)
		end
	end)
	ball:GetAttributeChangedSignal("HeldBy"):Connect(function()
		if ball:GetAttribute("HeldBy") ~= nil and ball:GetAttribute("IsSlam") == true then
			resetBall(ball)
		end
	end)
	if ball:GetAttribute("IsSlam") == true then dressBall(ball) end
end

for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do watchBall(ball) end
CollectionService:GetInstanceAddedSignal("Dodgeball"):Connect(watchBall)

-- Zone rewards -------------------------------------------------------------

BallService.HitDetected.Event:Connect(function(ball, character, speed, impactPosition)
	if not character or not character.Parent or character:GetAttribute("Benched") then return end

	local thrower = BallService.LastThrower(ball)
	if not thrower or thrower == character then return end

	local throwerTeam = thrower:GetAttribute("Team")
	local victimTeam = character:GetAttribute("Team")
	if typeof(throwerTeam) ~= "number" or typeof(victimTeam) ~= "number" then return end
	if throwerTeam == victimTeam then return end

	local zone = Catalog.DefaultZone
	if typeof(impactPosition) == "Vector3" then
		local ok, classified = pcall(HitZones.Classify, character, impactPosition)
		if ok and typeof(classified) == "string" then zone = classified end
	end
	local entry = Catalog.Zones[zone] or Catalog.Zones[Catalog.DefaultZone]
	local isSlam = ball:GetAttribute("IsSlam") == true

	task.defer(function()
		-- Bootstrap resolves catches, shields and invulnerability before ragdoll.
		-- Only pay when that authoritative path actually knocked the target out.
		if not character.Parent or not character:GetAttribute("Ragdolled") then return end
		if ball:GetAttribute("HeldBy") ~= nil then return end

		local throwerPlayer = Players:GetPlayerFromCharacter(thrower)
		if not throwerPlayer then return end

		local extra = math.max(0, entry.multiplier - 1)
		local bonusCoins = math.floor(CFG.Progression.KoCoins * extra)
		local bonusXP = math.floor(CFG.Progression.KoXP * extra)
		local bonusHype = math.floor(CFG.Hype.Hit * extra)

		if isSlam then
			bonusCoins += math.floor(CFG.Progression.KoCoins * 0.5)
			bonusXP += math.floor(CFG.Progression.KoXP * 0.5)
		end

		if bonusCoins > 0 then ProgressionService.AddCoins(throwerPlayer, bonusCoins) end
		if bonusXP > 0 then ProgressionService.AddXP(throwerPlayer, bonusXP) end
		if bonusHype > 0 then AbilityService.AddHype(throwerPlayer, bonusHype) end

		zoneRemote:FireClient(throwerPlayer, {
			zone = zone,
			label = entry.label,
			critical = entry.critical,
			color = entry.color,
			coins = bonusCoins,
			xp = bonusXP,
			hype = bonusHype,
			slam = isSlam,
		})

		if isSlam then
			slamRemote:FireAllClients("impact", character, throwerPlayer, zone, speed)
		end

		print(string.format("[Slam] %s -> %s zone=%s x%.2f slam=%s",
			thrower.Name, character.Name, zone, entry.multiplier, tostring(isSlam)))
	end)
end)

print("[Slam] dodge charge, zone rewards and Cannon presentation live")

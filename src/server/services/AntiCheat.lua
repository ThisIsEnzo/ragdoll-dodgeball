-- AntiCheat v0.7.0: rate-limit, общий бюджет remote, watchdog движения,
-- детект подмены Humanoid, эскалация до кика.
-- Важно: телепорт (раунд, скамейка) не считается читом — одиночный большой скачок пропускается.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local AntiCheat = {}
AntiCheat.Flagged = Instance.new("BindableEvent")

local windows: { [number]: any } = {}
local violations: { [number]: number } = {}
local samples: { [number]: any } = {}
local lastDecay: { [number]: number } = {}
local humanoidCheck: { [number]: number } = {}

local function flag(player: Player, reason: string, weight: number?)
	local userId = player.UserId
	violations[userId] = (violations[userId] or 0) + (weight or 1)
	AntiCheat.Flagged:Fire(player, reason, violations[userId])

	if violations[userId] >= CFG.Security.KickThreshold then
		player:Kick("Exploit detected: " .. reason .. ". Rejoin if you believe this is a mistake.")
	end
end

function AntiCheat.Init()
	for _, player in ipairs(Players:GetPlayers()) do
		violations[player.UserId] = 0
	end
end

function AntiCheat.Allow(player: Player, action: string, limitPerSecond: number?): boolean
	local userId = player.UserId
	local now = os.clock()

	local state = windows[userId]
	if not state then
		state = { actions = {}, total = 0, totalStart = now }
		windows[userId] = state
	end

	if now - state.totalStart >= 1 then
		state.totalStart = now
		state.total = 0
	end
	state.total += 1
	if state.total > CFG.Security.RemoteBudgetPerSecond then
		flag(player, "remote flood", 2)
		return false
	end

	local limit = limitPerSecond or CFG.RateLimits[action]
	if not limit then return true end

	local w = state.actions[action]
	if not w or now - w.start >= 1 then
		state.actions[action] = { start = now, count = 1 }
		return true
	end

	w.count += 1
	if w.count > limit then
		flag(player, "rate limit " .. action, 1)
		return false
	end
	return true
end

function AntiCheat.Violations(player: Player): number
	return violations[player.UserId] or 0
end

function AntiCheat.ValidDirection(dir: any): boolean
	if typeof(dir) ~= "Vector3" then return false end
	local m = dir.Magnitude
	return m == m and m >= 0.001 and m <= 1000
end

function AntiCheat.ValidCharge(charge: any): boolean
	if typeof(charge) ~= "number" or charge ~= charge then return false end
	return charge >= CFG.Throw.ChargeMin - 0.05 and charge <= CFG.Throw.ChargeMax + 0.1
end

-- Позиция для ping должна быть внутри арены и рядом с игроком
function AntiCheat.ValidPingPosition(player: Player, position: any): boolean
	if typeof(position) ~= "Vector3" then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end
	if (position - root.Position).Magnitude > CFG.Security.PingMaxDistance then return false end
	local halfW = CFG.Arena.Width * 0.5 + 24
	local halfD = CFG.Arena.Depth * 0.5 + 24
	return math.abs(position.X) <= halfW and math.abs(position.Z) <= halfD
end

local function sampleMovement(player: Player, now: number)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	if character:GetAttribute("Ragdolled") or character:GetAttribute("Benched") then
		samples[player.UserId] = nil
		return
	end

	local position = root.Position
	local record = samples[player.UserId]
	if not record then
		samples[player.UserId] = { position = position, at = now, streak = 0, safe = position }
		return
	end

	local dt = now - record.at
	if dt <= 0 then return end

	local delta = position - record.position
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	samples[player.UserId] = { position = position, at = now, streak = record.streak, safe = record.safe }
	local entry = samples[player.UserId]

	-- одиночный большой скачок = серверный телепорт, не чит
	if flat > CFG.Security.TeleportDelta then
		entry.streak = 0
		entry.safe = position
		return
	end

	local allowed = math.max(CFG.Movement.WalkSpeed, CFG.Movement.DodgeSpeed)
		* CFG.Security.SpeedTolerance + CFG.Security.SpeedSlack
	local speed = flat / dt

	if speed > allowed then
		entry.streak += 1
		if entry.streak >= CFG.Security.SustainedViolations then
			flag(player, "speed hack", 3)
			character:PivotTo(CFrame.new(entry.safe))
			root.AssemblyLinearVelocity = Vector3.zero
			entry.streak = 0
			entry.position = entry.safe
		end
	else
		entry.streak = 0
		entry.safe = position
	end
end

local function checkHumanoid(player: Player)
	local character = player.Character
	if not character then return end
	if character:GetAttribute("Ragdolled") then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local maxWalk = CFG.Movement.WalkSpeed * CFG.Security.WalkSpeedTolerance
	if humanoid.WalkSpeed > maxWalk then
		humanoid.WalkSpeed = CFG.Movement.WalkSpeed
		flag(player, "walkspeed tamper", 3)
	end
	if humanoid.JumpPower > CFG.Movement.JumpPower * 1.5 then
		humanoid.JumpPower = CFG.Movement.JumpPower
		flag(player, "jump tamper", 2)
	end
end

function AntiCheat.Start()
	Players.PlayerAdded:Connect(function(player)
		violations[player.UserId] = 0
		lastDecay[player.UserId] = os.clock()
		humanoidCheck[player.UserId] = os.clock()
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		windows[userId] = nil
		violations[userId] = nil
		samples[userId] = nil
		lastDecay[userId] = nil
		humanoidCheck[userId] = nil
	end)

	local interval = 1 / CFG.Security.MovementSampleHz
	local accumulator = 0

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < interval then return end
		accumulator = 0

		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId

			sampleMovement(player, now)

			if now - (humanoidCheck[userId] or 0) >= CFG.Security.HumanoidCheckSeconds then
				humanoidCheck[userId] = now
				checkHumanoid(player)
			end

			if now - (lastDecay[userId] or now) >= CFG.Security.ViolationDecaySeconds then
				lastDecay[userId] = now
				if violations[userId] and violations[userId] > 0 then
					violations[userId] -= 1
				end
			end
		end
	end)
end

return AntiCheat

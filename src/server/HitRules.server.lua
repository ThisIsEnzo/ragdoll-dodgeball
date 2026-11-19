-- HitRules: impact rules applied after the hit pipeline resolves.
-- Caps a single ball at two knockouts, kills most of its speed on contact,
-- and adds the Heavy throw bonus. Deferred by one step so the catch and
-- damage decision in Bootstrap always runs first.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Loadout = require(Shared:WaitForChild("Loadout"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")

local MAX_KOS = 2
local KEEP_SPEED = 0.32
local PUSH_DOWN = 14
local WINDOW = 3

local hits = setmetatable({}, { __mode = "k" })

BallService.HitDetected.Event:Connect(function(ball, character, speed)
	local player = Players:GetPlayerFromCharacter(character)
	local attempt = nil
	if player then attempt = player:GetAttribute("CatchAttemptAt") end
	local stanceAge = -1
	if typeof(attempt) == "number" then stanceAge = os.clock() - attempt end

	local heavy = ball:GetAttribute("HeavyBall") == true
	print(string.format("[HitRules] hit %s spd=%d stanceAge=%.2f heavy=%s",
		character.Name, math.floor(speed), stanceAge, tostring(heavy)))

	task.defer(function()
		if not ball.Parent then return end

		if ball:GetAttribute("HeldBy") then
			print("[HitRules] CATCH on " .. character.Name)
			return
		end

		if heavy then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
				local push = Vector3.zero
				if flat.Magnitude > 0.5 then
					push = flat.Unit * Loadout.Heavy.ExtraImpulse
				end
				root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + push
			end
		end

		local record = hits[ball]
		if not record or os.clock() - record.at > WINDOW then
			record = { count = 0, at = os.clock() }
			hits[ball] = record
		end
		record.count += 1
		record.at = os.clock()

		ball:SetAttribute("Clean", false)

		if record.count >= MAX_KOS then
			ball.AssemblyLinearVelocity = Vector3.new(0, -PUSH_DOWN, 0)
			print(string.format("[HitRules] ball spent after %d KOs", record.count))
			return
		end

		local velocity = ball.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z) * KEEP_SPEED
		ball.AssemblyLinearVelocity = Vector3.new(flat.X, -PUSH_DOWN, flat.Z)
		print(string.format("[HitRules] KO %d, speed %d -> %d",
			record.count, math.floor(speed), math.floor(flat.Magnitude)))
	end)
end)

print("[HitRules] multi-KO capped at " .. MAX_KOS .. ", heavy bonus active")
-- HitRules: один мяч не выкашивает всю команду.
-- После выбивания мяч теряет большую часть скорости и уходит вниз, поэтому
-- цепочка возможна только вплотную и читается как приём, а не как баг.
-- Отдельный Script: подключается к HitDetected и не правит существующие файлы.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Resolve = require(Shared:WaitForChild("Resolve"))
local BallService = Resolve.Require(ServerScriptService, "BallService")

local MAX_KOS = 2
local KEEP_SPEED = 0.32
local PUSH_DOWN = 14
local WINDOW = 3

local hits = setmetatable({}, { __mode = "k" })

BallService.HitDetected.Event:Connect(function(ball, character, speed)
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	local attempt = player and player:GetAttribute("CatchAttemptAt")
	local stanceAge = if typeof(attempt) == "number" then os.clock() - attempt else -1
	print(string.format("[HitRules] hit %s spd=%d stanceAge=%.2f clean=%s",
		character.Name, math.floor(speed), stanceAge, tostring(ball:GetAttribute("Clean"))))

	task.defer(function()
	if not ball.Parent then return end
	if ball:GetAttribute("HeldBy") then
		print("[HitRules] CATCH on " .. character.Name)
		return
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

print("[HitRules] multi-KO capped at " .. MAX_KOS)

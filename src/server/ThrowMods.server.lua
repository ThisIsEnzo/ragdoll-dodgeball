-- ThrowMods: applies the thrower's selected throw type to a ball in flight.
-- Detects a fresh throw by Clean flag plus a recent LastThrower timestamp,
-- so it needs no hook inside BallService.
--
-- Straight: untouched. Curve: lateral force for a short window.
-- Bounce: one wall bounce keeps the ball live. Heavy: bigger ball, extra hit.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Loadout = require(Shared:WaitForChild("Loadout"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")

local previousDir = {}
local bounceLeft = {}
local curveUntil = {}

local function clearMods(ball)
	ball:SetAttribute("ModDone", false)
	ball:SetAttribute("HeavyBall", false)
	ball.Size = Vector3.one * CFG.Ball.Size
	local force = ball:FindFirstChild("CurveForce")
	if force then force:Destroy() end
	local anchor = ball:FindFirstChild("CurveAnchor")
	if anchor then anchor:Destroy() end
	previousDir[ball] = nil
	bounceLeft[ball] = nil
	curveUntil[ball] = nil
end

local function applyCurve(ball, velocity)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 1 then return end
	local side = Vector3.new(-flat.Z, 0, flat.X).Unit
	if math.random() < 0.5 then side = -side end

	local anchor = Instance.new("Attachment")
	anchor.Name = "CurveAnchor"
	anchor.Parent = ball

	local force = Instance.new("VectorForce")
	force.Name = "CurveForce"
	force.Attachment0 = anchor
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = side * ball:GetMass() * Loadout.Curve.Acceleration
	force.Parent = ball

	curveUntil[ball] = os.clock() + Loadout.Curve.Duration
end

local function applyMod(ball, thrower)
	local typeId = thrower:GetAttribute("ThrowType")
	if typeof(typeId) ~= "string" then typeId = "Straight" end
	local entry = Loadout.Types[typeId]
	if not entry then entry = Loadout.Types.Straight end

	ball:SetAttribute("ModDone", true)
	ball:SetAttribute("ThrowType", typeId)

	local velocity = ball.AssemblyLinearVelocity
	ball.AssemblyLinearVelocity = velocity * entry.speed

	if typeId == "Curve" then
		applyCurve(ball, velocity)
	elseif typeId == "Bounce" then
		bounceLeft[ball] = 1
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude > 1 then previousDir[ball] = flat.Unit end
	elseif typeId == "Heavy" then
		ball:SetAttribute("HeavyBall", true)
		ball.Size = Vector3.one * CFG.Ball.Size * Loadout.Heavy.SizeScale
		ball.Color = Color3.fromRGB(255, 120, 60)
	end
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()

	for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
		if ball:IsA("BasePart") then
			if ball:GetAttribute("HeldBy") then
				if ball:GetAttribute("ModDone") then clearMods(ball) end
				continue
			end

			if not ball:IsDescendantOf(workspace) then continue end

			if not ball:GetAttribute("ModDone") then
				local thrower, at = BallService.LastThrower(ball)
				if thrower and at and now - at <= 0.25 and ball:GetAttribute("Clean") then
					applyMod(ball, thrower)
				end
				continue
			end

			local until_ = curveUntil[ball]
			if until_ and now > until_ then
				local force = ball:FindFirstChild("CurveForce")
				if force then force:Destroy() end
				local anchor = ball:FindFirstChild("CurveAnchor")
				if anchor then anchor:Destroy() end
				curveUntil[ball] = nil
			end

			local left = bounceLeft[ball]
			if left and left > 0 then
				local velocity = ball.AssemblyLinearVelocity
				local flat = Vector3.new(velocity.X, 0, velocity.Z)
				if flat.Magnitude > 5 then
					local dir = flat.Unit
					local prev = previousDir[ball]
					if prev and prev:Dot(dir) < -0.25 then
						bounceLeft[ball] = left - 1
						ball:SetAttribute("Clean", true)
					end
					previousDir[ball] = dir
				end
			end
		end
	end
end)

print("[ThrowMods] curve, bounce and heavy active")
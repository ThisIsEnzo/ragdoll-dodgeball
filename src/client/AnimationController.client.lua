-- AnimationController: procedural character animation via Motor6D C0 offsets.
-- No uploaded animation assets required. Works on R6 and R15.
--
-- The default Roblox Animate script writes Motor6D.Transform, so editing C0
-- layers on top of it instead of fighting it. Ragdoll states are skipped so
-- physics owns the body completely.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local localPlayer = Players.LocalPlayer

-- Arm swing sign differs by rig because R6 shoulders carry a 90 degree base yaw.
local ARM_AXIS_R15 = "X"
local ARM_AXIS_R6 = "Z"

local tracked = {}
local MAX_TRACKED = 10

local function normalize(name)
	return string.lower((string.gsub(name, "%s+", "")))
end

local function buildRig(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local isR15 = character:FindFirstChild("UpperTorso") ~= nil
	local joints = {}

	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("Motor6D") then
			local key = normalize(item.Name)
			if key == "rightshoulder" or key == "leftshoulder" or key == "root" or key == "rootjoint" then
				joints[key] = { motor = item, base = item.C0 }
			end
		end
	end

	if not joints.rightshoulder or not joints.leftshoulder then return nil end

	return {
		character = character,
		humanoid = humanoid,
		isR15 = isR15,
		joints = joints,
		throwAt = -10,
		catchAt = -10,
		dodgeAt = -10,
		phase = math.random() * 6,
	}
end

local function restore(rig)
	for _, entry in pairs(rig.joints) do
		entry.motor.C0 = entry.base
	end
end

local function armOffset(rig, side, degrees)
	local magnitude = math.rad(degrees)
	if side == "left" and not rig.isR15 then
		magnitude = -magnitude
	end
	if rig.isR15 then
		return CFrame.Angles(magnitude, 0, 0)
	end
	return CFrame.Angles(0, 0, magnitude)
end

local function easeOut(t)
	return 1 - (1 - t) * (1 - t)
end

local function easeIn(t)
	return t * t
end

-- Throw clip: wind up back, snap forward, follow through.
local function throwCurve(t)
	if t < 0.32 then
		return -55 * easeOut(t / 0.32)
	elseif t < 0.5 then
		local k = (t - 0.32) / 0.18
		return -55 + 150 * easeIn(k)
	else
		local k = (t - 0.5) / 0.5
		return 95 - 95 * easeOut(math.clamp(k, 0, 1))
	end
end

local function applyPose(rig, now)
	local character = rig.character
	if not character.Parent then return false end

	if character:GetAttribute("Ragdolled") then
		restore(rig)
		return true
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - root.Position).Magnitude > 150 then
		restore(rig)
		return true
	end

	local benched = character:GetAttribute("Benched") == true
	local carrying = character:GetAttribute("Carrying") == true
	local speed = rig.humanoid.MoveDirection.Magnitude

	local rightAngle = 0
	local leftAngle = 0
	local bob = 0

	-- idle breathing and walk bounce
	local cycle = now * 2.2 + rig.phase
	bob = math.sin(cycle) * 0.05
	if speed > 0.1 then
		bob = math.abs(math.sin(now * 9 + rig.phase)) * 0.12
		rightAngle = math.sin(now * 9 + rig.phase) * 14
		leftAngle = -rightAngle
	end

	if carrying then
		rightAngle = 72
		leftAngle = 12
		bob = bob + 0.04
	end

	if benched then
		rightAngle = -8
		leftAngle = -8
		bob = -0.35
	end

	local throwT = (now - rig.throwAt) / 0.62
	if throwT >= 0 and throwT <= 1 then
		rightAngle = throwCurve(throwT)
		leftAngle = -18 * math.sin(throwT * math.pi)
		bob = bob - 0.12 * math.sin(throwT * math.pi)
	end

	local catchT = (now - rig.catchAt) / 0.5
	if catchT >= 0 and catchT <= 1 then
		local reach = 88 * math.sin(math.clamp(catchT, 0, 1) * math.pi)
		rightAngle = reach
		leftAngle = reach
		bob = bob + 0.08 * reach / 88
	end

	local dodgeT = (now - rig.dodgeAt) / 0.34
	if dodgeT >= 0 and dodgeT <= 1 then
		local tuck = 60 * math.sin(dodgeT * math.pi)
		rightAngle = tuck
		leftAngle = tuck
		bob = bob - 0.45 * math.sin(dodgeT * math.pi)
	end

	local right = rig.joints.rightshoulder
	local left = rig.joints.leftshoulder
	right.motor.C0 = right.base * armOffset(rig, "right", rightAngle)
	left.motor.C0 = left.base * armOffset(rig, "left", leftAngle)

	local rootJoint = rig.joints.root or rig.joints.rootjoint
	if rootJoint then
		rootJoint.motor.C0 = rootJoint.base + Vector3.new(0, bob, 0)
	end

	return true
end

local function track(character)
	if not character:IsA("Model") then return end
	if tracked[character] then return end

	local count = 0
	for _ in pairs(tracked) do count += 1 end
	if count >= MAX_TRACKED then return end

	local rig = buildRig(character)
	if not rig then
		task.spawn(function()
			character:WaitForChild("Humanoid", 5)
			task.wait(0.2)
			local retry = buildRig(character)
			if retry then tracked[character] = retry end
		end)
		return
	end
	tracked[character] = rig
end

local function characterOf(subject)
	if typeof(subject) == "Instance" and subject:IsA("Model") then
		return subject
	end
	if typeof(subject) == "number" then
		local player = Players:GetPlayerByUserId(subject)
		if player then return player.Character end
	end
	return nil
end

local function fire(subject, field)
	local character = characterOf(subject)
	if not character then return end
	local rig = tracked[character]
	if not rig then return end
	rig[field] = os.clock()
end

function _G.RDAnimationDebug()
	local count = 0
	for _ in pairs(tracked) do count += 1 end
	print("[Anim] tracked rigs: " .. count)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for character, rig in pairs(tracked) do
		local ok = applyPose(rig, now)
		if not ok then
			restore(rig)
			tracked[character] = nil
		end
	end
end)

for _, character in ipairs(CollectionService:GetTagged("DodgeballActor")) do
	track(character)
end
CollectionService:GetInstanceAddedSignal("DodgeballActor"):Connect(track)

local fx = Net.Get("FXEvent")
if fx then
	fx.OnClientEvent:Connect(function(kind, a, b)
		if kind == "throw" then
			fire(b, "throwAt")
		elseif kind == "catch" then
			fire(a, "catchAt")
		elseif kind == "stance" then
			fire(a, "catchAt")
		elseif kind == "dodge" then
			fire(a, "dodgeAt")
		elseif kind == "ult" then
			fire(a, "throwAt")
		end
	end)
end

print("[Anim] procedural animation live: throw, catch, dodge, carry, idle")
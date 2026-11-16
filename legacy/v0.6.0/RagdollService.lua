-- RagdollService v0.3.0: контролируемый откат.
-- Скорость ЗАМЕНЯЕТСЯ, а не прибавляется. Вертикаль гасится. Затухание каждый кадр.
-- Все лимбы сети переводятся на сервер на время ragdoll, чтобы не было джиттера.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Collision = require(Shared:WaitForChild("Collision"))

local RagdollService = {}

local rigs: { [Model]: any } = {}
local active: { [Model]: number } = {}
local activeCount = 0

function RagdollService.Init()
	Collision.Setup()
end

local function setOwner(character: Model, owner: Player?)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				part:SetNetworkOwner(owner)
			end)
		end
	end
end

function RagdollService.Prepare(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	Collision.SetParts(character, "Players")
	CollectionService:AddTag(character, "DodgeballActor")

	local motors, constraints = {}, {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = descendant.C0
			a0.Parent = descendant.Part0

			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = descendant.C1
			a1.Parent = descendant.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 60
			socket.Restitution = 0
			socket.Enabled = false
			socket.Parent = descendant.Part0

			table.insert(motors, descendant)
			table.insert(constraints, socket)
		end
	end

	rigs[character] = { motors = motors, constraints = constraints, humanoid = humanoid }

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			rigs[character] = nil
			if active[character] then
				active[character] = nil
				activeCount = math.max(0, activeCount - 1)
			end
		end
	end)
end

function RagdollService.IsActive(character: Model): boolean
	return active[character] ~= nil
end

-- Низкий уровень: impulse уже осмысленный вектор. Всё равно клампится.
function RagdollService.Apply(character: Model, impulse: Vector3): boolean
	local rig = rigs[character]
	if not rig or active[character] then return false end
	if activeCount >= CFG.Round.MaxActiveRagdolls then return false end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local flat = Vector3.new(impulse.X, 0, impulse.Z)
	if flat.Magnitude > CFG.Impact.MaxLaunch then
		flat = flat.Unit * CFG.Impact.MaxLaunch
	end
	local vertical = math.clamp(
		impulse.Y * CFG.Impact.VerticalScale,
		-CFG.Impact.MaxVertical,
		CFG.Impact.MaxVertical
	)

	local humanoid = rig.humanoid
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	for _, motor in ipairs(rig.motors) do motor.Enabled = false end
	for _, socket in ipairs(rig.constraints) do socket.Enabled = true end

	Collision.SetParts(character, "Ragdolls")
	setOwner(character, nil)

	root.AssemblyLinearVelocity = Vector3.new(flat.X, vertical, flat.Z)
	root.AssemblyAngularVelocity = Vector3.new(
		math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
	).Unit * CFG.Impact.Spin

	character:SetAttribute("Ragdolled", true)
	active[character] = os.clock() + CFG.Round.RagdollTime
	activeCount += 1
	return true
end

-- Откат от попадания мячом: сила зависит от скорости мяча, но жёстко ограничена.
function RagdollService.Hit(character: Model, ballVelocity: Vector3): boolean
	local speed = ballVelocity.Magnitude
	if speed < 1 then return false end
	local power = math.clamp(
		speed * CFG.Impact.SpeedToImpulse,
		CFG.Impact.MinLaunch,
		CFG.Impact.MaxLaunch
	)
	return RagdollService.Apply(character, ballVelocity.Unit * power)
end

-- Откат от ловли: направление от ловца к бросавшему.
function RagdollService.Knockback(character: Model, direction: Vector3, power: number?): boolean
	if direction.Magnitude < 0.01 then return false end
	return RagdollService.Apply(character, direction.Unit * (power or CFG.Impact.CatchKnockback))
end

function RagdollService.Restore(character: Model)
	local rig = rigs[character]
	if not rig or not active[character] then return end

	active[character] = nil
	activeCount = math.max(0, activeCount - 1)

	for _, socket in ipairs(rig.constraints) do socket.Enabled = false end
	for _, motor in ipairs(rig.motors) do motor.Enabled = true end

	Collision.SetParts(character, "Players")

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	local humanoid = rig.humanoid
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	character:SetAttribute("Ragdolled", false)
	setOwner(character, Players:GetPlayerFromCharacter(character))
end

function RagdollService.Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local drag = CFG.Impact.DragPerFrame ^ (dt * 60)

		for character, expires in pairs(active) do
			if now >= expires or not character.Parent then
				RagdollService.Restore(character)
			else
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local v = root.AssemblyLinearVelocity
					local flat = Vector3.new(v.X, 0, v.Z)
					if flat.Magnitude <= CFG.Impact.StopSpeed then
						root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
						root.AssemblyAngularVelocity *= drag
					else
						root.AssemblyLinearVelocity = Vector3.new(v.X * drag, v.Y, v.Z * drag)
						root.AssemblyAngularVelocity *= drag
					end
				end
			end
		end
	end)
end

return RagdollService

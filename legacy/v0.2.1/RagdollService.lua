-- RagdollService: Motor6D <-> BallSocketConstraint, импульс, восстановление.
-- Констрейнты строятся один раз при спавне персонажа, переключение дешёвое.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local RagdollService = {}

local rigs: { [Model]: { motors: { Motor6D }, constraints: { BallSocketConstraint }, humanoid: Humanoid } } = {}
local active: { [Model]: number } = {}
local activeCount = 0

local GROUPS = { "Players", "Ragdolls", "Balls", "Arena" }

local function registerGroups()
	for _, name in ipairs(GROUPS) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Ragdolls", false)
	PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Balls", "Ragdolls", true)
end

local function setPartsGroup(character: Model, group: string)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

function RagdollService.Init()
	registerGroups()
end

-- Строим рig один раз на персонажа
function RagdollService.Prepare(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	setPartsGroup(character, "Players")

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

-- impulse: вектор impulses, применяется к торсу. Возвращает false, если лимит исчерпан.
function RagdollService.Apply(character: Model, impulse: Vector3): boolean
	local rig = rigs[character]
	if not rig or active[character] then
		return false
	end
	if activeCount >= CFG.Round.MaxActiveRagdolls then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local humanoid = rig.humanoid
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	for _, motor in ipairs(rig.motors) do
		motor.Enabled = false
	end
	for _, socket in ipairs(rig.constraints) do
		socket.Enabled = true
	end

	setPartsGroup(character, "Ragdolls")
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local capped = impulse
	if capped.Magnitude > CFG.Throw.ImpulseCap then
		capped = capped.Unit * CFG.Throw.ImpulseCap
	end
	root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + capped

	active[character] = os.clock() + CFG.Round.RagdollTime
	activeCount += 1
	return true
end

function RagdollService.Restore(character: Model)
	local rig = rigs[character]
	if not rig or not active[character] then
		return
	end

	active[character] = nil
	activeCount = math.max(0, activeCount - 1)

	for _, socket in ipairs(rig.constraints) do
		socket.Enabled = false
	end
	for _, motor in ipairs(rig.motors) do
		motor.Enabled = true
	end

	setPartsGroup(character, "Players")

	local humanoid = rig.humanoid
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local player = Players:GetPlayerFromCharacter(character)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if player and root then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
end

function RagdollService.Start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for character, expires in pairs(active) do
			if now >= expires or not character.Parent then
				RagdollService.Restore(character)
			end
		end
	end)
end

return RagdollService

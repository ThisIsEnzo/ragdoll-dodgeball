-- BenchBehaviour: KO recovery, walk-to-seat and return movement.
-- MatchService owns KO/revive state. This script owns the physical bench sequence.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))
local ArenaService = Resolve.Require(ServerScriptService, "ArenaService")

local RETURN_SPEED_MULTIPLIER = 1.25
local RETURN_SPEED_SECONDS = 2.2
local SLOT_SPACING_X = 3.8
local SLOT_SPACING_Z = 1.8
local SLOTS_PER_ROW = 4
local ARRIVAL_DISTANCE = 2.4
local WALK_TIMEOUT = 8

local tracked = {}
local slots = { [1] = {}, [2] = {} }

local function claimSlot(team, character)
	local teamSlots = slots[team]
	if not teamSlots then return 0 end
	if teamSlots[character] ~= nil then return teamSlots[character] end

	local used = {}
	for _, index in pairs(teamSlots) do
		used[index] = true
	end
	local index = 0
	while used[index] do
		index += 1
	end
	teamSlots[character] = index
	return index
end

local function releaseSlot(team, character)
	local teamSlots = slots[team]
	if teamSlots then teamSlots[character] = nil end
end

local function benchSlotPosition(team, character)
	local base = ArenaService.BenchPosition(team)
	local index = claimSlot(team, character)
	local column = index % SLOTS_PER_ROW
	local row = math.floor(index / SLOTS_PER_ROW)
	local xOffset = (column - (SLOTS_PER_ROW - 1) * 0.5) * SLOT_SPACING_X
	local sign = if team == 2 then 1 else -1
	local zOffset = sign * row * SLOT_SPACING_Z
	return base + Vector3.new(xOffset, 0, zOffset)
end

local function courtEntry(team)
	local halfDepth = CFG.Arena.Depth * 0.5
	local sign = if team == 2 then 1 else -1
	return Vector3.new(0, 3, sign * (halfDepth - 12))
end

local function waitUntilReady(character, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if not character.Parent then return false end
		if character:GetAttribute("Benched") ~= true then return false end
		if character:GetAttribute("Ragdolled") ~= true then return true end
		task.wait(0.1)
	end
	return character.Parent ~= nil
		and character:GetAttribute("Benched") == true
		and character:GetAttribute("Ragdolled") ~= true
end

local function distanceToTarget(root, target)
	return (Vector3.new(root.Position.X, 0, root.Position.Z)
		- Vector3.new(target.X, 0, target.Z)).Magnitude
end

local function walkToBench(character, humanoid, root, target)
	humanoid.Sit = false
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed * 0.7

	for attempt = 1, 2 do
		if not character.Parent or character:GetAttribute("Benched") ~= true then return false end
		if distanceToTarget(root, target) <= ARRIVAL_DISTANCE then return true end

		humanoid:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))
		local deadline = os.clock() + WALK_TIMEOUT
		while os.clock() < deadline do
			if not character.Parent or character:GetAttribute("Benched") ~= true then return false end
			if distanceToTarget(root, target) <= ARRIVAL_DISTANCE then return true end
			task.wait(0.1)
		end
	end

	return distanceToTarget(root, target) <= ARRIVAL_DISTANCE
end

local function sitAtBench(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local team = character:GetAttribute("Team")
	if not humanoid or not root or typeof(team) ~= "number" then return end
	if not waitUntilReady(character, CFG.Round.RagdollTime + 1.5) then return end

	local target = benchSlotPosition(team, character)
	if not walkToBench(character, humanoid, root, target) then
		warn(string.format("[Bench] %s could not reach seat; leaving actor at safe position", character.Name))
		return
	end

	if not humanoid.Parent or character:GetAttribute("Benched") ~= true then return end
	humanoid:MoveTo(root.Position)
	humanoid.Sit = true
	humanoid.WalkSpeed = 0
	character:SetAttribute("BenchSeated", true)
end

local function standAndReturn(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local team = character:GetAttribute("Team")
	if not humanoid or not root or typeof(team) ~= "number" then return end
	if character:GetAttribute("Benched") == true then return end

	character:SetAttribute("BenchSeated", false)
	releaseSlot(team, character)
	humanoid.Sit = false
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = CFG.Movement.WalkSpeed * RETURN_SPEED_MULTIPLIER
	task.wait(0.1)
	if not humanoid.Parent or character:GetAttribute("Benched") == true then return end

	humanoid.Jump = true
	local entry = courtEntry(team)
	humanoid:MoveTo(Vector3.new(entry.X, root.Position.Y, entry.Z))

	task.delay(RETURN_SPEED_SECONDS, function()
		if humanoid.Parent and character.Parent and character:GetAttribute("Benched") ~= true then
			humanoid.WalkSpeed = CFG.Movement.WalkSpeed
		end
	end)
end

local function watch(character)
	if not character:IsA("Model") or tracked[character] then return end
	tracked[character] = true

	local wasBenched = character:GetAttribute("Benched") == true
	character:GetAttributeChangedSignal("Benched"):Connect(function()
		local isBenched = character:GetAttribute("Benched") == true
		if isBenched == wasBenched then return end
		wasBenched = isBenched

		task.spawn(function()
			if isBenched then
				task.spawn(sitAtBench, character)
			else
				standAndReturn(character)
			end
		end)
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			tracked[character] = nil
			local team = character:GetAttribute("Team")
			if typeof(team) == "number" then releaseSlot(team, character) end
		end
	end)

	if wasBenched then
		task.spawn(sitAtBench, character)
	end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(watch, character)
	end)
	if player.Character then watch(player.Character) end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

-- RagdollService.Prepare tags both player characters and bots as DodgeballActor.
for _, actor in ipairs(CollectionService:GetTagged("DodgeballActor")) do
	watch(actor)
end
CollectionService:GetInstanceAddedSignal("DodgeballActor"):Connect(watch)

print("[Bench] KO fall -> recover -> walk to assigned seat -> sit")

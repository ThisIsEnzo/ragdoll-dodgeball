-- BenchBehaviour: sit benched actors and help revived actors return to court.
-- MatchService owns KO/revive state and teleporting. This script only owns
-- the Humanoid posture and short return movement; it does not duplicate FX
-- or move actors to a second spawn location.

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
local tracked = {}

local function benchPosition(team)
	return ArenaService.BenchPosition(team)
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

local function sitAtBench(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local team = character:GetAttribute("Team")
	if not humanoid or not root or typeof(team) ~= "number" then return end
	if not waitUntilReady(character, CFG.Round.RagdollTime + 1.5) then return end

	local target = benchPosition(team)
	local flatOffset = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z)
	if flatOffset.Magnitude > 3 then
		humanoid.WalkSpeed = CFG.Movement.WalkSpeed * 0.7
		humanoid:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))

		local deadline = os.clock() + 3
		while os.clock() < deadline do
			if not character.Parent or character:GetAttribute("Benched") ~= true then return end
			local remaining = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z)
			if remaining.Magnitude <= 3 then break end
			task.wait(0.15)
		end
	end

	if not humanoid.Parent or character:GetAttribute("Benched") ~= true then return end
	task.wait(0.2)
	if humanoid.Parent and character:GetAttribute("Benched") == true then
		humanoid.Sit = true
		humanoid.WalkSpeed = 0
	end
end

local function standAndReturn(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local team = character:GetAttribute("Team")
	if not humanoid or not root or typeof(team) ~= "number" then return end
	if character:GetAttribute("Benched") == true then return end

	-- MatchService.ReviveOne has already restored and teleported the actor
	-- before this deferred handler resumes.
	humanoid.Sit = false
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
				sitAtBench(character)
			else
				standAndReturn(character)
			end
		end)
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then tracked[character] = nil end
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

print("[Bench] sit on knockout, hop and run back on revive")

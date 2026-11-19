-- SpectatorService: picks the one actor worth watching and publishes it.
-- Every benched player follows the same highlight, so a server full of
-- eliminated players watches one coherent story instead of six random ones.
--
-- Priority: ball carrier, then the ball itself, then the last player to score
-- a knockout, then any surviving actor. Published as an ObjectValue because
-- attributes cannot hold Instance references.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")

local target = ReplicatedStorage:FindFirstChild("SpectateTarget")
if not target then
	target = Instance.new("ObjectValue")
	target.Name = "SpectateTarget"
	target.Parent = ReplicatedStorage
end

local reason = ReplicatedStorage:FindFirstChild("SpectateReason")
if not reason then
	reason = Instance.new("StringValue")
	reason.Name = "SpectateReason"
	reason.Parent = ReplicatedStorage
end

local lastScorer = nil
local lastScorerAt = 0

BallService.HitDetected.Event:Connect(function(ball, character)
	local thrower = BallService.LastThrower(ball)
	if thrower and thrower ~= character then
		lastScorer = thrower
		lastScorerAt = os.clock()
	end
end)

local function isAlive(model)
	if not model or not model.Parent then return false end
	if model:GetAttribute("Benched") then return false end
	if model:GetAttribute("Ragdolled") then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	return true
end

local function pick()
	local actors = CollectionService:GetTagged("DodgeballActor")

	for _, model in ipairs(actors) do
		if model:IsA("Model") and isAlive(model) and model:GetAttribute("Carrying") then
			return model, "BALL CARRIER"
		end
	end

	if lastScorer and isAlive(lastScorer) and os.clock() - lastScorerAt < 6 then
		return lastScorer, "LAST KNOCKOUT"
	end

	local best, bestDist = nil, math.huge
	for _, model in ipairs(actors) do
		if model:IsA("Model") and isAlive(model) then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local d = root.Position.Magnitude
				if d < bestDist then best, bestDist = model, d end
			end
		end
	end
	if best then return best, "CLOSEST SURVIVOR" end

	return nil, "ROUND OVER"
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.4 then return end
	accumulator = 0

	local model, why = pick()
	if target.Value ~= model then target.Value = model end
	if reason.Value ~= why then reason.Value = why end
end)

Players.PlayerRemoving:Connect(function(player)
	if lastScorer and Players:GetPlayerFromCharacter(lastScorer) == player then
		lastScorer = nil
	end
end)

print("[Spectate] highlight director up")
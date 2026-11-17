-- CatchService v0.12.0: ловля перехватывает мяч ДО того, как он будет засчитан как попадание.
--
-- Почему раньше не работало: TryConvert вызывался из обработчика HitDetected,
-- но BallService.sweepHit выставляет Clean = false ПЕРЕД firing события.
-- К моменту проверки мяч уже был грязным, и catchableBall его отклонял.
-- Теперь BallService спрашивает ловлю ДО порчи мяча, через предикат.
--
-- Конус убран: мяч летит с любой стороны, а игрок реагирует на звук и трейл,
-- а не только на то, что в центре экрана. Требование смотреть на мяч делало
-- ловлю нечитаемой при пинге 267 мс.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local BallService = Resolve.Require(ServerScriptService, "BallService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local RoundService = Resolve.Require(ServerScriptService, "RoundService")

local CatchService = {}
CatchService.Caught = Instance.new("BindableEvent")

local MatchService
local AbilityService

local stance = {}
local cooldownUntil = {}

function CatchService.Init(matchService, abilityService)
MatchService = matchService
AbilityService = abilityService
end

local function applyStagger(character)
local humanoid = character:FindFirstChildOfClass("Humanoid")
if not humanoid then return end
humanoid.WalkSpeed = CFG.Movement.WalkSpeed * 0.5
task.delay(CFG.Catch.Stagger, function()
if humanoid.Parent then humanoid.WalkSpeed = CFG.Movement.WalkSpeed end
end)
end

local function succeed(player, character, ball)
local thrower = BallService.LastThrower(ball)
if thrower and thrower.Parent and not RagdollService.IsActive(thrower) then
local throwerRoot = thrower:FindFirstChild("HumanoidRootPart")
local root = character:FindFirstChild("HumanoidRootPart")
if throwerRoot and root then
RagdollService.Knockback(thrower, throwerRoot.Position - root.Position, CFG.Impact.CatchKnockback)
if MatchService then MatchService.OnKO(thrower, "caught") end
end
end

BallService.GiveBall(character, ball)

local team = RoundService.TeamOf(character)
local revived = false
if team and MatchService then revived = MatchService.ReviveOne(team) end
if AbilityService then AbilityService.AddHype(player, CFG.Hype.Catch) end

stance[player.UserId] = nil
CatchService.Caught:Fire(player, revived)
Net.FireAll("FXEvent", "catch", character, thrower)
end

local function speedOk(ball)
local speed = ball.AssemblyLinearVelocity.Magnitude
return speed >= CFG.Ball.MinHitSpeed and speed <= CFG.Catch.MaxSpeed
end

-- Предикат для BallService: вызывается ДО того, как мяч помечается грязным.
-- Возвращает true, если этот игрок в стойке и мяч ему подходит.
function CatchService.InterceptHit(victimPlayer, ball, character)
if not victimPlayer then return false end
local entry = stance[victimPlayer.UserId]
if not entry then return false end
if os.clock() > entry.expires then return false end

if ball:GetAttribute("HeldBy") then return false end
if ball:GetAttribute("Uncatchable") then return false end
if not speedOk(ball) then return false end

if not character or not character.Parent then return false end
if character:GetAttribute("Benched") then return false end
if RagdollService.IsActive(character) then return false end

local thrower = BallService.LastThrower(ball)
if not thrower or thrower == character then return false end
if thrower:GetAttribute("Team") == character:GetAttribute("Team") then return false end

succeed(victimPlayer, character, ball)
return true
end

-- Мгновенная ловля при нажатии: если мяч уже рядом, берём сразу.
function CatchService.Try(player, aimDir)
local character = player.Character
if not character then return false end
local root = character:FindFirstChild("HumanoidRootPart")
local humanoid = character:FindFirstChildOfClass("Humanoid")
if not root or not humanoid or humanoid.Health <= 0 then return false end
if character:GetAttribute("Benched") or RagdollService.IsActive(character) then return false end

local now = os.clock()
if (cooldownUntil[player.UserId] or 0) > now then return false end

local entry = { expires = now + CFG.Catch.StanceSeconds, token = now }
stance[player.UserId] = entry
player:SetAttribute("CatchAttemptAt", now)
Net.FireAll("FXEvent", "stance", character)

local ping = player:GetNetworkPing()
local sampleTime = workspace:GetServerTimeNow() - ping

for _, ball in ipairs(CollectionService:GetTagged("Dodgeball")) do
if ball:IsA("BasePart") and ball:IsDescendantOf(workspace)
and not ball:GetAttribute("HeldBy")
and ball:GetAttribute("Clean")
and not ball:GetAttribute("Uncatchable")
and speedOk(ball) then

local position = BallService.SampleAt(ball, sampleTime) or ball.Position
if (position - root.Position).Magnitude <= CFG.Catch.Distance then
local thrower = BallService.LastThrower(ball)
if thrower and thrower ~= character
and thrower:GetAttribute("Team") ~= character:GetAttribute("Team") then
succeed(player, character, ball)
return true
end
end
end
end

task.delay(CFG.Catch.StanceSeconds, function()
local current = stance[player.UserId]
if current and current.token == entry.token then
stance[player.UserId] = nil
cooldownUntil[player.UserId] = os.clock() + CFG.Catch.WhiffCooldown
if character.Parent and not character:GetAttribute("Benched") then
applyStagger(character)
Net.FireAll("FXEvent", "whiff", character)
end
end
end)

return false
end

function CatchService.InStance(player)
if not player then return false end
local entry = stance[player.UserId]
return entry ~= nil and os.clock() <= entry.expires
end

function CatchService.Start()
Players.PlayerRemoving:Connect(function(player)
stance[player.UserId] = nil
cooldownUntil[player.UserId] = nil
end)
end

return CatchService
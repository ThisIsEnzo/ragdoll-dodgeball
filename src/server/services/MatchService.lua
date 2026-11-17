-- MatchService v0.11.0: команда привязана к игроку, а не к персонажу.
--
-- Было: Team ставился один раз на player.Character при старте матча. Если персонаж
-- респавнился или ещё не существовал, игрок оставался без команды: ботов добивало
-- до 3+3, и игрок мог атаковать обе команды, потому что nil не равен ни 1, ни 2.
-- Теперь команда живёт на игроке и переносится на каждый новый персонаж.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Resolve = require(Shared:WaitForChild("Resolve"))

local RoundService = Resolve.Require(ServerScriptService, "RoundService")
local RagdollService = Resolve.Require(ServerScriptService, "RagdollService")
local BallService = Resolve.Require(ServerScriptService, "BallService")
local BotController = Resolve.Require(ServerScriptService, "BotController")
local ProgressionService = Resolve.Require(ServerScriptService, "ProgressionService")
local FtueService = Resolve.Require(ServerScriptService, "FtueService")

local MatchService = {}

local queue = {}
local inMatch = false
local matchPlayers = {}
local playerTeam = {}
local botTeams = { [1] = {}, [2] = {} }
local downed = { [1] = {}, [2] = {} }
local teamOf = {}
local spawns = { [1] = {}, [2] = {} }
local bench = {}
local running = false
local matchIndexByPlayer = {}
local respawnConnections = {}

local function shuffle(list)
for i = #list, 2, -1 do
local j = math.random(i)
list[i], list[j] = list[j], list[i]
end
end

local function readMarkers()
local arena = workspace:FindFirstChild("Arena")
for team = 1, 2 do
local folder = arena and arena:FindFirstChild("Team" .. team .. "Spawns")
if folder then
for _, part in ipairs(folder:GetChildren()) do
if part:IsA("BasePart") then
table.insert(spawns[team], part.Position)
part.Transparency = 1
part.CanCollide = false
end
end
end
if #spawns[team] == 0 then
for i = -1, 1 do
table.insert(spawns[team], Vector3.new(i * 8, 5, team == 1 and -28 or 28))
end
end
local benchPart = arena and arena:FindFirstChild("Bench" .. team)
bench[team] = benchPart and benchPart.Position or Vector3.new(team == 1 and -40 or 40, 5, 0)
end
end

local function teleport(character, position)
local root = character:FindFirstChild("HumanoidRootPart")
if root then
character:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
root.AssemblyLinearVelocity = Vector3.zero
end
end

local function broadcast()
Net.FireAll("MatchState", {
state = RoundService.State,
timer = math.max(0, math.floor(RoundService.Timer)),
wins1 = RoundService.Wins(1),
wins2 = RoundService.Wins(2),
alive1 = RoundService.AliveCount(1),
alive2 = RoundService.AliveCount(2),
inMatch = inMatch,
})
end

local function spawnPoint(team, index)
local list = spawns[team]
return list[((index - 1) % #list) + 1]
end

local function benchCharacter(character, team)
character:SetAttribute("Benched", true)
character:SetAttribute("Ragdolled", false)
BallService.ForceRelease(character)
if not table.find(downed[team], character) then
table.insert(downed[team], character)
end
teleport(character, bench[team])
end

-- Команда берётся у игрока и переносится на любой его новый персонаж
local function attachCharacter(player, character)
local team = playerTeam[player.UserId]
if not team then return end

teamOf[character] = team
character:SetAttribute("Team", team)
character:SetAttribute("IsBot", false)
character:SetAttribute("DisplayName", player.DisplayName)

local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then humanoid.Health = humanoid.MaxHealth end

local live = RoundService.State == "Live" or RoundService.State == "SuddenDeath"
if live then
benchCharacter(character, team)
else
character:SetAttribute("Benched", false)
character:SetAttribute("Ragdolled", false)
teleport(character, spawnPoint(team, (player.UserId % 3) + 1))
RoundService.Register(character, team)
end
broadcast()
end

local function playersOf(team)
local list = {}
for _, player in ipairs(matchPlayers) do
if playerTeam[player.UserId] == team and player.Parent then
table.insert(list, player)
end
end
return list
end

function MatchService.Init()
readMarkers()
RoundService.StateChanged.Event:Connect(broadcast)
end

function MatchService.Enqueue(player)
if table.find(queue, player) then return end
table.insert(queue, player)
broadcast()
end

function MatchService.Leave(player)
local index = table.find(queue, player)
if index then table.remove(queue, index) end
end

function MatchService.TeamOf(character)
return teamOf[character]
end

function MatchService.IsRunning()
return inMatch
end

function MatchService.OnKO(character, reason)
local team = teamOf[character]
if not team then return end
RoundService.RegisterKO(character)
character:SetAttribute("Ragdolled", true)
BallService.ForceRelease(character)
if not table.find(downed[team], character) then
table.insert(downed[team], character)
end
Net.FireAll("FXEvent", "ko", character, reason)

local victim = Players:GetPlayerFromCharacter(character)
if victim then FtueService.Benched(victim) end

task.delay(CFG.Round.RagdollTime, function()
if not character.Parent then return end
RagdollService.Restore(character)
benchCharacter(character, team)
broadcast()
end)
broadcast()
end

function MatchService.ReviveOne(team)
local character = table.remove(downed[team], 1)
if not character or not character.Parent then return false end
local humanoid = character:FindFirstChildOfClass("Humanoid")
if not humanoid then return false end

RagdollService.Restore(character)
character:SetAttribute("Ragdolled", false)
character:SetAttribute("Benched", false)
humanoid.Health = humanoid.MaxHealth
teleport(character, spawnPoint(team, math.random(1, 3)))
RoundService.Revive(character, team)
Net.FireAll("FXEvent", "revive", character)
broadcast()
return true
end

local function clearMatch()
for _, connection in pairs(respawnConnections) do
connection:Disconnect()
end
table.clear(respawnConnections)

for team = 1, 2 do
for _, bot in ipairs(botTeams[team]) do
teamOf[bot] = nil
end
table.clear(botTeams[team])
table.clear(downed[team])
end
for _, player in ipairs(matchPlayers) do
local character = player.Character
if character then teamOf[character] = nil end
end

BotController.DespawnAll()
RoundService.ResetRound()
table.clear(matchPlayers)
table.clear(playerTeam)
table.clear(matchIndexByPlayer)
inMatch = false
broadcast()
end

local function setupRound()
BallService.SpawnAll()

for team = 1, 2 do
table.clear(downed[team])
end

local slot = { [1] = 0, [2] = 0 }

for _, player in ipairs(matchPlayers) do
local character = player.Character
local team = playerTeam[player.UserId]
if character and team then
slot[team] += 1
teamOf[character] = team
character:SetAttribute("Team", team)
character:SetAttribute("Benched", false)
character:SetAttribute("Ragdolled", false)
character:SetAttribute("Carrying", false)
local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then humanoid.Health = humanoid.MaxHealth end
RagdollService.Restore(character)
teleport(character, spawnPoint(team, slot[team]))
RoundService.Register(character, team)
end
end

for team = 1, 2 do
for _, bot in ipairs(botTeams[team]) do
if bot.Parent then
slot[team] += 1
bot:SetAttribute("Benched", false)
bot:SetAttribute("Ragdolled", false)
bot:SetAttribute("Carrying", false)
local humanoid = bot:FindFirstChildOfClass("Humanoid")
if humanoid then humanoid.Health = humanoid.MaxHealth end
RagdollService.Restore(bot)
teleport(bot, spawnPoint(team, slot[team]))
RoundService.Register(bot, team)
end
end
end

broadcast()
end

function MatchService.StartMatch()
if inMatch then return end
inMatch = true

local participants = {}
for _, player in ipairs(queue) do
if player.Parent then table.insert(participants, player) end
end
table.clear(queue)
shuffle(participants)

matchPlayers = participants

-- команда назначается ИГРОКУ, поэтому переживает респавн персонажа
local counts = { [1] = 0, [2] = 0 }
for _, player in ipairs(matchPlayers) do
local team = if counts[1] <= counts[2] then 1 else 2
counts[team] += 1
playerTeam[player.UserId] = team
matchIndexByPlayer[player.UserId] = (player:GetAttribute("MatchesThisSession") or 0) + 1
player:SetAttribute("MatchesThisSession", matchIndexByPlayer[player.UserId])

respawnConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
if not inMatch then return end
task.wait(0.1)
attachCharacter(player, character)
end)
end

-- боты добивают до 3 на команду по числу ИГРОКОВ, а не наличию персонажей
for team = 1, 2 do
local needed = 3 - counts[team]
for _ = 1, needed do
local bot = BotController.Spawn(team, spawnPoint(team, counts[team] + 1))
if bot then
table.insert(botTeams[team], bot)
teamOf[bot] = team
end
end
end

task.spawn(function()
while RoundService.Wins(1) < CFG.Round.WinsNeeded and RoundService.Wins(2) < CFG.Round.WinsNeeded do
local winner = RoundService.RunRound(setupRound)
if winner == nil then break end
ProgressionService.SettleRound(playersOf(winner))
end

local matchWinner = if RoundService.Wins(1) > RoundService.Wins(2) then 1 else 2
Net.FireAll("MatchState", {
state = "MatchEnd", winner = matchWinner, inMatch = false,
wins1 = RoundService.Wins(1), wins2 = RoundService.Wins(2), timer = 0,
})

local all = {}
for _, player in ipairs(matchPlayers) do
if player.Parent then table.insert(all, player) end
end
ProgressionService.SettleMatch(all, playersOf(matchWinner))
for _, player in ipairs(all) do
FtueService.MatchFinished(player, matchIndexByPlayer[player.UserId] or 1)
end

print("[Match] Team " .. matchWinner .. " won")
task.wait(CFG.Round.MatchEnd)

clearMatch()
for _, player in ipairs(Players:GetPlayers()) do
MatchService.Enqueue(player)
end
end)
end

function MatchService.Start()
Players.PlayerRemoving:Connect(function(player)
MatchService.Leave(player)
local connection = respawnConnections[player.UserId]
if connection then
connection:Disconnect()
respawnConnections[player.UserId] = nil
end
local character = player.Character
if character then
local team = teamOf[character]
if team then
RoundService.RegisterKO(character)
teamOf[character] = nil
end
end
playerTeam[player.UserId] = nil
end)

if running then return end
running = true
task.spawn(function()
while true do
task.wait(1)
if not inMatch and #queue >= CFG.Bots.MinRealPlayersToStart then
MatchService.StartMatch()
end
end
end)
end

return MatchService
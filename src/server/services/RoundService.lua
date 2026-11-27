-- RoundService: конечный автомат раунда, учёт живых, sudden death, победитель.
-- MatchService (следующая веха) будет вызывать RunMatch для серии до 3 побед.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local RoundService = {}

RoundService.State = "Idle"
RoundService.Timer = 0
RoundService.RoundIndex = 0
RoundService.StateChanged = Instance.new("BindableEvent")
RoundService.RoundEnded = Instance.new("BindableEvent")

local alive: { [Model]: number } = {}   -- character -> teamId
local wins: { [number]: number } = { [1] = 0, [2] = 0 }
local suddenDeath = false

local function setState(state: string, duration: number)
	RoundService.State = state
	RoundService.Timer = duration
	RoundService.StateChanged:Fire(state, duration)
end

function RoundService.Init() end

function RoundService.Register(character: Model, teamId: number)
	alive[character] = teamId
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			alive[character] = nil
		end
	end)
end

function RoundService.TeamOf(character: Model): number?
	return alive[character]
end

function RoundService.RegisterKO(character: Model)
	alive[character] = nil
end

function RoundService.Revive(character: Model, teamId: number)
	alive[character] = teamId
end

function RoundService.AliveCount(teamId: number): number
	local count = 0
	for _, team in pairs(alive) do
		if team == teamId then
			count += 1
		end
	end
	return count
end

function RoundService.TeamWiped(): boolean
	return RoundService.AliveCount(1) == 0 or RoundService.AliveCount(2) == 0
end

function RoundService.IsSuddenDeath(): boolean
	return suddenDeath
end

function RoundService.ResolveWinner(): number?
	local a, b = RoundService.AliveCount(1), RoundService.AliveCount(2)
	if a > b then
		return 1
	elseif b > a then
		return 2
	end
	return nil
end

function RoundService.ResetRound()
	suddenDeath = false
	wins = { [1] = 0, [2] = 0 }
	RoundService.RoundIndex = 0
	table.clear(alive)
	setState("Idle", 0)
end

-- Один раунд. onSetup вызывается на старте: спавн мячей, телепорт игроков, раздача команд.
function RoundService.RunRound(onSetup: (() -> ())?)
	RoundService.RoundIndex += 1
	setState("Warmup", CFG.Round.Warmup)
	if onSetup then
		onSetup()
	end
	while RoundService.Timer > 0 do
		task.wait(0.1)
		RoundService.Timer -= 0.1
	end

	setState("Live", CFG.Round.Duration)
	while RoundService.State == "Live" do
		task.wait(0.1)
		RoundService.Timer -= 0.1
		if RoundService.TeamWiped() then
			break
		end
		if RoundService.Timer <= 0 then
			if RoundService.ResolveWinner() == nil then
				suddenDeath = true
				setState("SuddenDeath", CFG.Round.SuddenDeath)
			else
				break
			end
		end
	end

	while RoundService.State == "SuddenDeath" do
		task.wait(0.1)
		RoundService.Timer -= 0.1
		if RoundService.TeamWiped() or RoundService.Timer <= 0 then
			break
		end
	end

	local winner = RoundService.ResolveWinner()
	if winner then
		wins[winner] += 1
	end

	setState("RoundEnd", CFG.Round.RoundEnd)
	RoundService.RoundEnded:Fire(winner, wins[1], wins[2])
	task.wait(CFG.Round.RoundEnd)

	return winner, wins[1], wins[2]
end

function RoundService.Wins(teamId: number): number
	return wins[teamId] or 0
end

function RoundService.Start()
	RunService.Heartbeat:Connect(function() end)
end

return RoundService

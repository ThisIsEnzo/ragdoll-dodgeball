-- AntiCheat: rate-limit по игроку и действию + утилиты sanity-check.
-- Скользящее окно в 1 секунду, счётчики чистятся при выходе игрока.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local AntiCheat = {}

local windows: { [number]: { [string]: { start: number, count: number } } } = {}
local strikes: { [number]: number } = {}

local MAX_STRIKES_PER_MINUTE = 60

function AntiCheat.Init()
	Players.PlayerRemoving:Connect(function(player)
		windows[player.UserId] = nil
		strikes[player.UserId] = nil
	end)
end

-- limitPerSecond: сколько вызовов действия разрешено за секунду
function AntiCheat.Allow(player: Player, action: string, limitPerSecond: number?): boolean
	local limit = limitPerSecond or CFG.RateLimits[action]
	if not limit then
		return true
	end

	local now = os.clock()
	local perPlayer = windows[player.UserId]
	if not perPlayer then
		perPlayer = {}
		windows[player.UserId] = perPlayer
	end

	local w = perPlayer[action]
	if not w or now - w.start >= 1 then
		perPlayer[action] = { start = now, count = 1 }
		return true
	end

	w.count += 1
	if w.count > limit then
		strikes[player.UserId] = (strikes[player.UserId] or 0) + 1
		return false
	end
	return true
end

function AntiCheat.Strikes(player: Player): number
	return strikes[player.UserId] or 0
end

function AntiCheat.IsSuspicious(player: Player): boolean
	return AntiCheat.Strikes(player) > MAX_STRIKES_PER_MINUTE
end

-- Проверка вектора прицела: нормализованный, конечный, не нулевой
function AntiCheat.ValidDirection(dir: any): boolean
	if typeof(dir) ~= "Vector3" then
		return false
	end
	local m = dir.Magnitude
	if m ~= m or m < 0.001 or m > 1000 then
		return false
	end
	return true
end

-- Проверка заряда броска
function AntiCheat.ValidCharge(charge: any): boolean
	if typeof(charge) ~= "number" or charge ~= charge then
		return false
	end
	return charge >= CFG.Throw.ChargeMin - 0.05 and charge <= CFG.Throw.ChargeMax + 0.1
end

function AntiCheat.Start() end

return AntiCheat

-- DataService: сохранение профиля с session-lock и мягким отказом.
-- Если DataStore недоступен (Studio API access выключен) — уходим в memory-mode,
-- игра продолжает работать, клиент получает флаг persistent=false и показывает предупреждение.
-- Никаких внешних зависимостей: только DataStoreService.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local DataService = {}

local STORE_NAME = "RagdollDodgeball_Profile_v1"
local JOB = if RunService:IsStudio() then ("studio:" .. game.JobId) else game.JobId
local store = DataStoreService:GetDataStore(STORE_NAME)

local profiles: { [number]: any } = {}
local warned = false

local TEMPLATE = {
	schema = 1,
	coins = 0,
	xp = 0,
	level = 1,
	matches = 0,
	wins = 0,
	kos = 0,
	catches = 0,
	throws = 0,
	revives = 0,
	roundWins = 0,
	streakDay = 0,
	streakStamp = 0,
	questDay = 0,
	quests = {},
	questProgress = {},
}

local function reconcile(old: any)
	local data = {}
	for key, value in pairs(TEMPLATE) do
		if typeof(old) == "table" and typeof(old[key]) == typeof(value) then
			data[key] = old[key]
		else
			data[key] = if typeof(value) == "table" then {} else value
		end
	end
	if typeof(old) == "table" then
		data.lockJob = old.lockJob
		data.lockUntil = old.lockUntil
	end
	return data
end

local function copyForSave(data: any)
	local payload = {}
	for key, value in pairs(data) do
		if key ~= "lockJob" and key ~= "lockUntil" then
			payload[key] = value
		end
	end
	return payload
end

local function warnOnce(message: string)
	if warned then return end
	warned = true
	warn("[Data] " .. message)
end

function DataService.Init() end

function DataService.Load(player: Player)
	local userId = player.UserId
	local now = os.time()
	local loaded = nil

	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. userId, function(old)
				local data = reconcile(old)
				if data.lockJob and data.lockJob ~= JOB
					and typeof(data.lockUntil) == "number" and data.lockUntil > now then
					return nil
				end
				data.lockJob = JOB
				data.lockUntil = now + CFG.Progression.LockSeconds
				return data
			end)
		end)

		if ok and typeof(result) == "table" then
			loaded = result
			break
		end
		if not ok then
			warnOnce("DataStore unavailable. Progress will NOT persist. "
				.. "Enable Game Settings -> Security -> Enable Studio Access to API Services.")
			break
		end
		task.wait(2)
	end

	if not loaded then
		loaded = reconcile(nil)
		profiles[userId] = { data = loaded, persistent = false }
		warnOnce("Session locked elsewhere or store unavailable; running in memory mode for " .. player.Name)
	else
		profiles[userId] = { data = loaded, persistent = true }
	end

	return profiles[userId].data
end

function DataService.Get(player: Player)
	local profile = profiles[player.UserId]
	return profile and profile.data or nil
end

function DataService.IsPersistent(player: Player): boolean
	local profile = profiles[player.UserId]
	return profile ~= nil and profile.persistent
end

function DataService.Save(userId: number)
	local profile = profiles[userId]
	if not profile or not profile.persistent then return end

	local payload = copyForSave(profile.data)
	local now = os.time()

	pcall(function()
		store:UpdateAsync("u_" .. userId, function(old)
			if typeof(old) == "table" and old.lockJob and old.lockJob ~= JOB
				and typeof(old.lockUntil) == "number" and old.lockUntil > now then
				return nil
			end
			payload.lockJob = JOB
			payload.lockUntil = now + CFG.Progression.LockSeconds
			return payload
		end)
	end)
end

function DataService.Release(userId: number)
	local profile = profiles[userId]
	if not profile then return end
	if profile.persistent then
		DataService.Save(userId)
		pcall(function()
			store:UpdateAsync("u_" .. userId, function(old)
				if typeof(old) == "table" and old.lockJob == JOB then
					old.lockJob = nil
					old.lockUntil = nil
					return old
				end
				return nil
			end)
		end)
	end
	profiles[userId] = nil
end

function DataService.Start()
	Players.PlayerRemoving:Connect(function(player)
		DataService.Release(player.UserId)
	end)

	task.spawn(function()
		while true do
			task.wait(CFG.Progression.AutosaveSeconds)
			for userId in pairs(profiles) do
				DataService.Save(userId)
			end
		end
	end)

	game:BindToClose(function()
		for userId in pairs(profiles) do
			DataService.Save(userId)
		end
		if not RunService:IsStudio() then
			task.wait(3)
		end
	end)
end

return DataService

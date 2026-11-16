-- DOCTOR: вставь целиком в Command Bar в режиме Edit (не Play).
-- Проверяет дерево проекта, типы инстансов, дубликаты и готовность к запуску.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local EXPECTED_SHARED = { "BalanceConfig", "Net", "Resolve" }
local EXPECTED_SERVER = {
	"AntiCheat", "RagdollService", "BallService", "RoundService",
	"AbilityService", "MatchService", "CatchService", "BotController",
}
local EXPECTED_CLIENT = { "InputController", "HUDController" }

local problems = 0

local function index(root)
	local byName, duplicates = {}, {}
	if not root then return byName, duplicates end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			if byName[descendant.Name] then
				table.insert(duplicates, descendant.Name)
			end
			byName[descendant.Name] = descendant
		end
	end
	return byName, duplicates
end

local function check(label, root, expected, wantedClass)
	print("=== " .. label .. " ===")
	if not root then
		warn("  НЕТ КОРНЯ: " .. label)
		problems += 1
		return
	end
	local byName, duplicates = index(root)
	for _, name in ipairs(expected) do
		local instance = byName[name]
		if not instance then
			warn("  ОТСУТСТВУЕТ: " .. name)
			problems += 1
		elseif wantedClass and instance.ClassName ~= wantedClass then
			warn(string.format("  НЕВЕРНЫЙ ТИП: %s это %s, нужен %s", name, instance.ClassName, wantedClass))
			problems += 1
		else
			local path = instance:GetFullName()
			local extra = ""
			if instance:IsA("Script") or instance:IsA("LocalScript") then
				extra = if instance.Disabled then "  [DISABLED!]" else "  [enabled]"
				if instance.Disabled then problems += 1 end
			end
			print(string.format("  OK  %-18s %-14s %s%s", name, instance.ClassName, path, extra))
		end
	end
	for _, name in ipairs(duplicates) do
		warn("  ДУБЛИКАТ ИМЕНИ: " .. name .. " (резолвер возьмёт первый попавшийся)")
		problems += 1
	end
	local total = 0
	for _ in pairs(byName) do total += 1 end
	print("  всего скриптов в дереве: " .. total)
end

local shared = ReplicatedStorage:FindFirstChild("Shared")
local server = ServerScriptService:FindFirstChild("Server")
local client = StarterPlayer.StarterPlayerScripts:FindFirstChild("Client")

check("SHARED (ReplicatedStorage.Shared)", shared, EXPECTED_SHARED, "ModuleScript")
check("SERVER (ServerScriptService.Server)", server, EXPECTED_SERVER, "ModuleScript")
check("CLIENT (StarterPlayerScripts.Client)", client, EXPECTED_CLIENT, "ModuleScript")

print("=== ENTRY POINTS ===")
local bootstrap = server and server:FindFirstChild("Bootstrap")
if bootstrap and bootstrap:IsA("Script") then
	print("  OK  Bootstrap [Script]" .. if bootstrap.Disabled then "  [DISABLED!]" else "  [enabled]")
	if bootstrap.Disabled then problems += 1 end
else
	warn("  Bootstrap отсутствует или не Script")
	problems += 1
end

local clientBootstrap = client and client:FindFirstChild("ClientBootstrap")
if clientBootstrap and clientBootstrap:IsA("LocalScript") then
	print("  OK  ClientBootstrap [LocalScript]" .. if clientBootstrap.Disabled then "  [DISABLED!]" else "  [enabled]")
	if clientBootstrap.Disabled then problems += 1 end
else
	warn("  ClientBootstrap отсутствует или не LocalScript")
	problems += 1
end

print("=== WORLD MARKERS (необязательно, есть фолбэки) ===")
local arena = workspace:FindFirstChild("Arena")
local ballSpawns = workspace:FindFirstChild("BallSpawns")
print("  Arena: " .. (arena and "есть" or "нет, спавны по умолчанию"))
print("  BallSpawns: " .. (ballSpawns and "есть" or "нет, мячи на 0,5,-8 / 0,5,0 / 0,5,8"))
if arena then
	for _, marker in ipairs({ "Team1Spawns", "Team2Spawns", "Bench1", "Bench2" }) do
		print("    " .. marker .. ": " .. (arena:FindFirstChild(marker) and "есть" or "нет"))
	end
end

print("=== ВЕРДИКТ ===")
if problems == 0 then
	print("  ГОТОВО К ЗАПУСКУ. Нажимай Play, в Output жди строку [RagdollDodgeball] v0.2.1 запущен")
else
	warn("  ПРОБЛЕМ: " .. problems .. ". Синхронизируй дерево (rojo serve) или собери place: rojo build")
end

-- Doctor: проверка дерева проекта. Запускать в EDIT mode после синка.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Doctor = {}

local EXPECTED_SHARED = { "BalanceConfig", "Net", "Resolve", "Collision", "Strings", "AimAssist" }
local EXPECTED_SERVER = {
	"AntiCheat", "ArenaService", "RagdollService", "BallService", "RoundService",
	"AbilityService", "AnalyticsService", "DataService", "ProgressionService",
	"FtueService", "MatchService", "CatchService", "BotController",
}
local EXPECTED_CLIENT = {
	"InputController", "HUDController", "CarryController",
	"ImpactController", "ClipController", "FtueController",
}

local function index(root)
	local byName, duplicates = {}, {}
	if not root then return byName, duplicates end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			if byName[descendant.Name] then table.insert(duplicates, descendant.Name) end
			byName[descendant.Name] = descendant
		end
	end
	return byName, duplicates
end

function Doctor.Run()
	local problems = 0

	local function check(label, root, expected, wantedClass)
		print("=== " .. label .. " ===")
		if not root then
			warn("  MISSING ROOT: " .. label)
			problems += 1
			return
		end
		local byName, duplicates = index(root)
		for _, name in ipairs(expected) do
			local instance = byName[name]
			if not instance then
				warn("  MISSING: " .. name)
				problems += 1
			elseif wantedClass and instance.ClassName ~= wantedClass then
				warn(string.format("  WRONG TYPE: %s is %s, expected %s", name, instance.ClassName, wantedClass))
				problems += 1
			else
				print(string.format("  OK  %-20s %s", name, instance.ClassName))
			end
		end
		for _, name in ipairs(duplicates) do
			warn("  DUPLICATE NAME: " .. name .. " (resolver picks the first one)")
			problems += 1
		end
	end

	check("SHARED", ReplicatedStorage:FindFirstChild("Shared"), EXPECTED_SHARED, "ModuleScript")
	check("SERVER", ServerScriptService:FindFirstChild("Server"), EXPECTED_SERVER, "ModuleScript")
	check("CLIENT", StarterPlayer.StarterPlayerScripts:FindFirstChild("Client"), EXPECTED_CLIENT, "ModuleScript")

	print("=== ENTRY POINTS ===")
	local server = ServerScriptService:FindFirstChild("Server")
	local bootstrap = server and server:FindFirstChild("Bootstrap")
	if bootstrap and bootstrap:IsA("Script") then
		print("  OK  Bootstrap [Script]" .. if bootstrap.Disabled then "  DISABLED!" else "  enabled")
		if bootstrap.Disabled then problems += 1 end
	else
		warn("  Bootstrap missing or not a Script")
		problems += 1
	end

	local client = StarterPlayer.StarterPlayerScripts:FindFirstChild("Client")
	local clientBootstrap = client and client:FindFirstChild("ClientBootstrap")
	if clientBootstrap and clientBootstrap:IsA("LocalScript") then
		print("  OK  ClientBootstrap [LocalScript]" .. if clientBootstrap.Disabled then "  DISABLED!" else "  enabled")
		if clientBootstrap.Disabled then problems += 1 end
	else
		warn("  ClientBootstrap missing or not a LocalScript")
		problems += 1
	end

	local devtools = game:GetService("ServerStorage"):FindFirstChild("DevTools")
	print("=== DEVTOOLS ===")
	print("  DevTools module: " .. (devtools and "present" or "MISSING"))
	if not devtools then problems += 1 end

	print("=== VERDICT ===")
	if problems == 0 then
		print("  READY. Press Play and wait for [RagdollDodgeball] v0.7.x server up")
	else
		warn("  PROBLEMS: " .. problems .. ". Finish the Rojo sync or create the missing instances.")
	end

	return problems
end

return Doctor

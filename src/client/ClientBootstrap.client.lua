-- ClientBootstrap: Ð¿Ð¾Ð´Ð½Ð¸Ð¼Ð°ÐµÑ‚ ÐºÐ¾Ð½Ñ‚Ñ€Ð¾Ð»Ð»ÐµÑ€Ñ‹ Ð¸Ð·Ð¾Ð»Ð¸Ñ€Ð¾Ð²Ð°Ð½Ð½Ð¾.
-- Ð Ð°Ð½ÑŒÑˆÐµ Ð¾Ð´Ð½Ð° ÑÐ¸Ð½Ñ‚Ð°ÐºÑÐ¸Ñ‡ÐµÑÐºÐ°Ñ Ð¾ÑˆÐ¸Ð±ÐºÐ° Ð² InputController Ð²Ñ‹ÐºÐ»ÑŽÑ‡Ð°Ð»Ð° Ð²ÐµÑÑŒ ÐºÐ»Ð¸ÐµÐ½Ñ‚:
-- HUD, Ð²Ð¸Ð·ÑƒÐ°Ð» Ð¼ÑÑ‡Ð° Ð² Ñ€ÑƒÐºÐµ, ÑÑ„Ñ„ÐµÐºÑ‚Ñ‹ Ð¸ Ð²Ð²Ð¾Ð´. Ð¢ÐµÐ¿ÐµÑ€ÑŒ ÐºÐ°Ð¶Ð´Ñ‹Ð¹ ÐºÐ¾Ð½Ñ‚Ñ€Ð¾Ð»Ð»ÐµÑ€ Ð² pcall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
if not Shared then
	warn("[Client] ReplicatedStorage.Shared is missing")
	return
end

local Resolve = require(Shared:WaitForChild("Resolve", 20))
local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

local NAMES = {
	"InputController",
	"HUDController",
	"IdentityController",
	"CarryController",
	"ImpactController",
	"ClipController",
	"FtueController",
}

local loaded = {}

for _, name in ipairs(NAMES) do
	local ok, module = pcall(function()
		return Resolve.Require(PlayerScripts, name, 10)
	end)
	if ok and type(module) == "table" then
		loaded[name] = module
	else
		warn("[Client] failed to load " .. name .. ": " .. tostring(module))
	end
end

for _, name in ipairs(NAMES) do
	local module = loaded[name]
	if module and type(module.Init) == "function" then
		local ok, err = pcall(module.Init)
		if not ok then
			warn("[Client] Init failed for " .. name .. ": " .. tostring(err))
		end
	end
end

for _, name in ipairs(NAMES) do
	local module = loaded[name]
	if module and type(module.Start) == "function" then
		local ok, err = pcall(module.Start)
		if not ok then
			warn("[Client] Start failed for " .. name .. ": " .. tostring(err))
		end
	end
end

local count = 0
for _ in pairs(loaded) do count += 1 end
print(string.format("[Client] %d/%d controllers up", count, #NAMES))
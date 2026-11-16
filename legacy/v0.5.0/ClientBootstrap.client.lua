-- ClientBootstrap v0.4.1: порядок важен.
-- Input -> HUD -> Carry -> Impact -> Clips. Carry поднимается до Impact,
-- чтобы визуал мяча существовал раньше, чем косметика начнёт вешать свет и трейлы.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Client] В ReplicatedStorage нет папки Shared")
local Resolve = require(Shared:WaitForChild("Resolve", 20))

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
Resolve.Report(PlayerScripts, "Client")

local InputController = Resolve.Require(PlayerScripts, "InputController")
local HUDController = Resolve.Require(PlayerScripts, "HUDController")
local CarryController = Resolve.Require(PlayerScripts, "CarryController")
local ImpactController = Resolve.Require(PlayerScripts, "ImpactController")
local ClipController = Resolve.Require(PlayerScripts, "ClipController")

local ORDER = { InputController, HUDController, CarryController, ImpactController, ClipController }

for _, controller in ipairs(ORDER) do
	if controller.Init then controller.Init() end
end
for _, controller in ipairs(ORDER) do
	if controller.Start then controller.Start() end
end

print("[RagdollDodgeball] Клиент v0.4.1 готов: мяч в руке приклеен локально")

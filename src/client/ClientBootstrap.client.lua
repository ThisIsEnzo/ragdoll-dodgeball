-- ClientBootstrap v0.2.1: контроллеры ищутся резолвером, папки больше не важны.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Client] В ReplicatedStorage нет папки Shared")
local Resolve = require(Shared:WaitForChild("Resolve", 20))

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
Resolve.Report(PlayerScripts, "Client")

local InputController = Resolve.Require(PlayerScripts, "InputController")
local HUDController = Resolve.Require(PlayerScripts, "HUDController")

local ORDER = { InputController, HUDController }

for _, controller in ipairs(ORDER) do
	if controller.Init then controller.Init() end
end
for _, controller in ipairs(ORDER) do
	if controller.Start then controller.Start() end
end

print("[RagdollDodgeball] Клиент v0.2.1 готов")

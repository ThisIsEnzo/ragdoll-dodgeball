-- ClientBootstrap v0.4.0: контроллеры ищутся резолвером, порядок инициализации важен.
-- Input -> HUD -> Impact -> Clips: косметика подключается после того, как HUD занял экран.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Client] В ReplicatedStorage нет папки Shared")
local Resolve = require(Shared:WaitForChild("Resolve", 20))

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
Resolve.Report(PlayerScripts, "Client")

local InputController = Resolve.Require(PlayerScripts, "InputController")
local HUDController = Resolve.Require(PlayerScripts, "HUDController")
local ImpactController = Resolve.Require(PlayerScripts, "ImpactController")
local ClipController = Resolve.Require(PlayerScripts, "ClipController")

local ORDER = { InputController, HUDController, ImpactController, ClipController }

for _, controller in ipairs(ORDER) do
	if controller.Init then controller.Init() end
end
for _, controller in ipairs(ORDER) do
	if controller.Start then controller.Start() end
end

print("[RagdollDodgeball] Клиент v0.4.0 готов: импакт и детект моментов включены")

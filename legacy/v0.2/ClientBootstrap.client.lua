-- ClientBootstrap: поднимает контроллеры клиента.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")

local controllers = script:WaitForChild("controllers")
local InputController = require(controllers:WaitForChild("InputController"))
local HUDController = require(controllers:WaitForChild("HUDController"))

local ORDER = { InputController, HUDController }

for _, controller in ipairs(ORDER) do
	if controller.Init then controller.Init() end
end
for _, controller in ipairs(ORDER) do
	if controller.Start then controller.Start() end
end

print("[RagdollDodgeball] Клиент v0.2 готов")

-- ClientBootstrap v0.8.0: добавлен IdentityController после HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
assert(Shared, "[Client] ReplicatedStorage.Shared is missing")
local Resolve = require(Shared:WaitForChild("Resolve", 20))

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
Resolve.Report(PlayerScripts, "Client")

local InputController = Resolve.Require(PlayerScripts, "InputController")
local HUDController = Resolve.Require(PlayerScripts, "HUDController")
local IdentityController = Resolve.Require(PlayerScripts, "IdentityController")
local CarryController = Resolve.Require(PlayerScripts, "CarryController")
local ImpactController = Resolve.Require(PlayerScripts, "ImpactController")
local ClipController = Resolve.Require(PlayerScripts, "ClipController")
local FtueController = Resolve.Require(PlayerScripts, "FtueController")

local ORDER = {
	InputController, HUDController, IdentityController,
	CarryController, ImpactController, ClipController, FtueController,
}

for _, controller in ipairs(ORDER) do
	if controller.Init then controller.Init() end
end
for _, controller in ipairs(ORDER) do
	if controller.Start then controller.Start() end
end

print("[RagdollDodgeball] Client v0.8.0 ready: team identity active")

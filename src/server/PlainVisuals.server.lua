-- PlainVisuals: one renderer, no themes, no post effects.
--
-- This is a Script, so it must NOT end with a return statement. The previous
-- WorldService.server.lua returned a table, which is only legal in a
-- ModuleScript. It errored on load and never ran, leaving the neon theme
-- unopposed. That is why the court turned magenta.
--
-- Everything this does: neutral daylight, and keep WorldDecor deleted so the
-- arena is just the wood court ArenaService builds.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local function clearEffects()
	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA("PostEffect") or item:IsA("Atmosphere") or item:IsA("Sky") then
			item:Destroy()
		end
	end
end

local function neutral()
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(90, 90, 95)
	Lighting.OutdoorAmbient = Color3.fromRGB(145, 145, 150)
	Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 41
	Lighting.ExposureCompensation = 0
	Lighting.FogEnd = 100000
	Lighting.FogStart = 0
end

local function removeDecor()
	local decor = Workspace:FindFirstChild("WorldDecor")
	if decor then
		decor:Destroy()
		return true
	end
	return false
end

local function apply()
	clearEffects()
	neutral()
	removeDecor()
end

apply()

Workspace.ChildAdded:Connect(function(child)
	if child.Name == "WorldDecor" then
		task.wait()
		child:Destroy()
		apply()
	end
end)

task.spawn(function()
	while true do
		task.wait(2)
		apply()
	end
end)

print("[Visuals] plain daylight, decor layer removed, no post effects")
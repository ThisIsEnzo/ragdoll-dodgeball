-- WorldService: plain default rendering.
--
-- Rollback. Six lighting passes made the court worse each time, so this now
-- removes every custom effect, restores neutral daylight, turns all neon into
-- ordinary lit plastic and disables the spot fixtures. No bloom, no atmosphere,
-- no colour grading, no glow.
--
-- MapService still tries to apply its own theme lighting on a venue change,
-- so this re-asserts on theme change and on a slow timer.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local WorldService = {}

local EFFECTS = { "RDBloom", "RDGrade", "RDRays", "RDAir", "RDImpactCorrection" }

local function stripEffects()
	for _, name in ipairs(EFFECTS) do
		local item = Lighting:FindFirstChild(name)
		if item then item:Destroy() end
	end
	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA("PostEffect") then item:Destroy() end
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then sky:Destroy() end
end

local function neutralLighting()
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(80, 80, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 41
	Lighting.ExposureCompensation = 0
	Lighting.FogEnd = 100000
	Lighting.FogStart = 0
end

local function plainMaterials()
	local decor = Workspace:FindFirstChild("WorldDecor")
	if not decor then return 0 end
	local changed = 0
	for _, item in ipairs(decor:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.Material == Enum.Material.Neon then
				item.Material = Enum.Material.SmoothPlastic
				changed += 1
			end
			item.Reflectance = 0
			item.LocalTransparencyModifier = 0
		elseif item:IsA("SpotLight") or item:IsA("PointLight") or item:IsA("SurfaceLight") then
			item.Enabled = false
		elseif item:IsA("ParticleEmitter") then
			item.Enabled = false
		end
	end
	return changed
end

local function apply()
	stripEffects()
	neutralLighting()
	local n = plainMaterials()
	return n
end

function WorldService.Init()
	local n = apply()
	print("[World] plain default rendering, " .. n .. " neon parts converted")
end

function WorldService.Start()
	task.spawn(function()
		local decor = Workspace:WaitForChild("WorldDecor", 40)
		if decor then
			decor:GetAttributeChangedSignal("Theme"):Connect(function()
				task.wait(0.8)
				apply()
			end)
			decor.DescendantAdded:Connect(function(item)
				if item:IsA("BasePart") and item.Material == Enum.Material.Neon then
					task.wait()
					item.Material = Enum.Material.SmoothPlastic
				elseif item:IsA("SpotLight") or item:IsA("PointLight") then
					task.wait()
					item.Enabled = false
				end
			end)
		end
		while true do
			task.wait(3)
			apply()
		end
	end)
end

return WorldService
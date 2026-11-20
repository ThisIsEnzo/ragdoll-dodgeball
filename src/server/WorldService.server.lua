-- WorldService: sole authority for rendering, plain daylight.
--
-- MapService destroys and recreates the whole WorldDecor folder on a venue
-- change. Watchers bound to the old folder died with it, so new geometry was
-- never neutralised and the rooftop theme left the court at ClockTime 20.4.
-- This now watches Workspace.ChildAdded, re-applies on every rebuild, and
-- re-asserts twice a second so no theme can hold the scene dark.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local WorldService = {}

local DROP_FOLDERS = { "Skyline", "Helipad", "CageBars" }

local function stripEffects()
	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA("PostEffect") or item:IsA("Atmosphere") or item:IsA("Sky") then
			item:Destroy()
		end
	end
end

local function neutral()
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(96, 96, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 155)
	Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 41
	Lighting.ExposureCompensation = 0
	Lighting.FogEnd = 100000
	Lighting.FogStart = 0
end

local function plainScene()
	local decor = Workspace:FindFirstChild("WorldDecor")
	if not decor then return 0 end

	for _, name in ipairs(DROP_FOLDERS) do
		local folder = decor:FindFirstChild(name)
		if folder then folder:Destroy() end
	end

	local changed = 0
	for _, item in ipairs(decor:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.Material == Enum.Material.Neon then
				item.Material = Enum.Material.SmoothPlastic
				changed += 1
			end
			item.Reflectance = 0
		elseif item:IsA("SpotLight") or item:IsA("PointLight") or item:IsA("SurfaceLight") then
			item.Enabled = false
		elseif item:IsA("SurfaceGui") then
			item.LightInfluence = 1
			local label = item:FindFirstChildWhichIsA("TextLabel", true)
			if label then
				label.TextScaled = false
				label.TextSize = 42
			end
		end
	end
	return changed
end

local function apply()
	stripEffects()
	neutral()
	return plainScene()
end

function WorldService.Init()
	local n = apply()
	print("[World] plain daylight, " .. n .. " neon parts flattened")
end

function WorldService.Start()
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "WorldDecor" then
			task.wait(0.3)
			apply()
			task.wait(0.8)
			apply()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			apply()
		end
	end)
end

return WorldService
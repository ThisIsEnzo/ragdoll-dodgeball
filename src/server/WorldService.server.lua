-- WorldService: lighting only.
-- Audit fix: this script assigned Lighting.Technology (protected) and rebuilt
-- geometry that already lives in the place file. Both removed. Geometry is
-- authored in the place; this service only tunes writable lighting values.

local Lighting = game:GetService("Lighting")

local WorldService = {}

local function effect(class, name, props)
	local item = Lighting:FindFirstChild(name)
	if not item then
		item = Instance.new(class)
		item.Name = name
		item.Parent = Lighting
	end
	for key, value in pairs(props) do
		item[key] = value
	end
	return item
end

function WorldService.Init()
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 14
	Lighting.Brightness = 2.2
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.Ambient = Color3.fromRGB(66, 76, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(92, 106, 136)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 208)
	Lighting.ColorShift_Bottom = Color3.fromRGB(58, 72, 110)

	effect("Atmosphere", "RDAir", {
		Density = 0.28, Offset = 0.15,
		Color = Color3.fromRGB(168, 190, 225),
		Decay = Color3.fromRGB(52, 66, 100),
		Glare = 0.2, Haze = 1.3,
	})
	effect("BloomEffect", "RDBloom", { Intensity = 0.45, Size = 24, Threshold = 1.1 })
	effect("ColorCorrectionEffect", "RDGrade", {
		Saturation = 0.16, Contrast = 0.2, Brightness = 0,
		TintColor = Color3.fromRGB(255, 250, 244),
	})
	effect("SunRaysEffect", "RDRays", { Intensity = 0.045, Spread = 0.5 })

	print("[World] lighting tuned")
end

function WorldService.Start() end

return WorldService
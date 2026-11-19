-- AudioCatalog: layered sound design built from engine-local assets.
-- Every entry is a stack of layers with pitch spread, delay and decay, so a
-- single event reads as one designed sound rather than one raw sample.
--
-- Engine paths are used because they always load with no asset permissions.
-- Drop your own rbxassetid:// strings into Override to replace any layer;
-- the mixer, spatialisation and envelopes keep working unchanged.

local ENGINE = {
	collide = "rbxasset://sounds/collide.wav",
	snap = "rbxasset://sounds/snap.wav",
	bass = "rbxasset://sounds/bass.wav",
	hit = "rbxasset://sounds/hit.wav",
	voice = "rbxasset://sounds/uuhhh.mp3",
	ping = "rbxasset://sounds/electronicpingshort.wav",
}

-- Paste uploaded asset ids here to upgrade any source, e.g. collide = "rbxassetid://123".
local Override = {}

local function src(key)
	if Override[key] then return Override[key] end
	return ENGINE[key]
end

local function layer(key, pitch, volume, delay, decay, spread)
	return {
		id = src(key),
		pitch = pitch,
		volume = volume,
		delay = delay or 0,
		decay = decay or 0,
		spread = spread or 0.06,
	}
end

return {
	Groups = { "SFX", "UI", "Crowd", "Ambience" },

	Defaults = { Master = 0.85, SFX = 0.9, UI = 0.6, Crowd = 0.7, Ambience = 0.5 },

	MaxDistance = 170,
	NearDistance = 12,

	Sounds = {
		throw = { group = "SFX", layers = {
			layer("snap", 2.2, 0.34, 0, 0.14, 0.18),
			layer("collide", 1.7, 0.12, 0.01, 0.1, 0.1),
		} },

		bonk = { group = "SFX", layers = {
			layer("collide", 0.76, 0.9, 0, 0.28, 0.1),
			layer("bass", 0.55, 0.72, 0, 0.34, 0.06),
			layer("snap", 1.5, 0.26, 0.012, 0.12, 0.14),
		} },

		bonkHeavy = { group = "SFX", layers = {
			layer("collide", 0.5, 1.0, 0, 0.4, 0.06),
			layer("bass", 0.34, 0.95, 0, 0.5, 0.04),
			layer("hit", 0.8, 0.5, 0.02, 0.3, 0.08),
		} },

		catch = { group = "SFX", layers = {
			layer("ping", 1.3, 0.6, 0, 0.2, 0.05),
			layer("snap", 1.05, 0.42, 0.008, 0.14, 0.08),
			layer("bass", 0.95, 0.26, 0, 0.22, 0.04),
		} },

		whiff = { group = "SFX", layers = {
			layer("snap", 2.7, 0.2, 0, 0.1, 0.2),
			layer("hit", 1.9, 0.12, 0.01, 0.08, 0.15),
		} },

		dodge = { group = "SFX", layers = {
			layer("snap", 1.95, 0.3, 0, 0.18, 0.16),
			layer("collide", 2.4, 0.1, 0.02, 0.12, 0.12),
		} },

		pickup = { group = "SFX", layers = {
			layer("snap", 1.45, 0.26, 0, 0.1, 0.08),
			layer("ping", 1.85, 0.2, 0.03, 0.12, 0.05),
		} },

		bounce = { group = "SFX", layers = {
			layer("collide", 1.35, 0.3, 0, 0.14, 0.14),
		} },

		ult = { group = "SFX", layers = {
			layer("bass", 0.4, 0.9, 0, 0.55, 0.03),
			layer("ping", 0.72, 0.5, 0.02, 0.4, 0.05),
			layer("collide", 0.62, 0.5, 0.04, 0.45, 0.06),
		} },

		shield = { group = "SFX", layers = {
			layer("ping", 0.92, 0.5, 0, 0.3, 0.04),
			layer("bass", 1.2, 0.3, 0.01, 0.25, 0.05),
		} },

		revive = { group = "SFX", layers = {
			layer("ping", 1.6, 0.4, 0, 0.18, 0.03),
			layer("snap", 2.05, 0.3, 0.07, 0.16, 0.05),
			layer("ping", 2.0, 0.32, 0.14, 0.22, 0.03),
		} },

		levelUp = { group = "UI", layers = {
			layer("ping", 1.0, 0.4, 0, 0.16, 0.02),
			layer("ping", 1.26, 0.4, 0.09, 0.16, 0.02),
			layer("ping", 1.5, 0.46, 0.18, 0.3, 0.02),
			layer("bass", 0.7, 0.3, 0.18, 0.4, 0.02),
		} },

		coin = { group = "UI", layers = {
			layer("ping", 2.1, 0.3, 0, 0.12, 0.06),
			layer("ping", 2.6, 0.22, 0.05, 0.1, 0.06),
		} },

		click = { group = "UI", layers = {
			layer("snap", 2.9, 0.2, 0, 0.06, 0.05),
		} },

		hover = { group = "UI", layers = {
			layer("snap", 3.3, 0.08, 0, 0.04, 0.04),
		} },

		countdown = { group = "UI", layers = {
			layer("ping", 1.4, 0.34, 0, 0.14, 0.01),
		} },

		sudden = { group = "SFX", layers = {
			layer("bass", 0.3, 1.0, 0, 0.9, 0.02),
			layer("collide", 0.44, 0.7, 0.03, 0.8, 0.03),
			layer("ping", 0.55, 0.4, 0.1, 0.7, 0.02),
		} },

		victory = { group = "UI", layers = {
			layer("ping", 1.0, 0.42, 0, 0.2, 0.01),
			layer("ping", 1.33, 0.42, 0.12, 0.2, 0.01),
			layer("ping", 1.6, 0.46, 0.24, 0.24, 0.01),
			layer("ping", 2.0, 0.5, 0.36, 0.5, 0.01),
			layer("bass", 0.6, 0.34, 0.36, 0.6, 0.02),
		} },

		defeat = { group = "UI", layers = {
			layer("bass", 0.62, 0.5, 0, 0.4, 0.02),
			layer("bass", 0.48, 0.46, 0.16, 0.45, 0.02),
			layer("collide", 0.4, 0.34, 0.32, 0.6, 0.03),
		} },

		cheer = { group = "Crowd", layers = {
			layer("voice", 0.92, 0.34, 0, 0.5, 0.16),
			layer("voice", 1.12, 0.3, 0.04, 0.5, 0.18),
			layer("voice", 0.78, 0.28, 0.09, 0.55, 0.14),
			layer("voice", 1.3, 0.26, 0.13, 0.45, 0.2),
			layer("voice", 1.0, 0.3, 0.18, 0.5, 0.16),
			layer("voice", 0.86, 0.24, 0.24, 0.5, 0.18),
		} },

		gasp = { group = "Crowd", layers = {
			layer("voice", 1.35, 0.26, 0, 0.3, 0.16),
			layer("voice", 1.55, 0.22, 0.03, 0.28, 0.18),
			layer("voice", 1.15, 0.2, 0.07, 0.3, 0.14),
		} },
	},

	Ambience = {
		id = src("voice"),
		voices = 8,
		pitchMin = 0.3,
		pitchMax = 0.46,
		volume = 0.035,
	},

	Reverb = {
		gym = { DecayTime = 1.5, Density = 0.8, Diffusion = 0.9, DryLevel = 0, WetLevel = -14 },
		rooftop = { DecayTime = 0.6, Density = 0.5, Diffusion = 0.6, DryLevel = 0, WetLevel = -22 },
		neon = { DecayTime = 2.4, Density = 0.95, Diffusion = 1.0, DryLevel = 0, WetLevel = -10 },
	},
}
-- Loadout: throw type catalog.
-- Sidegrades, not upgrades: every type pays for its trick with speed.
-- Unlock levels here are the single source of truth for the loadout panel.

return {
	Order = { "Straight", "Curve", "Bounce", "Heavy" },

	Types = {
		Straight = {
			name = "STRAIGHT",
			level = 1,
			speed = 1.0,
			impact = 1.0,
			blurb = "Full speed, no tricks",
			plus = "Fastest ball",
			minus = "Predictable line",
			accent = "amber",
		},
		Curve = {
			name = "CURVE",
			level = 5,
			speed = 0.85,
			impact = 1.0,
			blurb = "Bends sideways in flight",
			plus = "Goes around cover",
			minus = "-15% speed",
			accent = "cyan",
		},
		Bounce = {
			name = "BOUNCE",
			level = 12,
			speed = 0.80,
			impact = 1.0,
			blurb = "Stays live after one wall bounce",
			plus = "Bank shots count",
			minus = "-20% speed",
			accent = "lime",
		},
		Heavy = {
			name = "HEAVY",
			level = 20,
			speed = 0.75,
			impact = 1.45,
			blurb = "Bigger ball, much harder hit",
			plus = "+45% knockback",
			minus = "-25% speed",
			accent = "magenta",
		},
	},

	Curve = {
		Acceleration = 34,
		Duration = 1.1,
	},

	Heavy = {
		SizeScale = 1.28,
		ExtraImpulse = 16,
	},
}
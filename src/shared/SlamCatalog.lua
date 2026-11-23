-- SlamCatalog: presentation and reward tuning for the existing Cannon ultimate.
-- Cannon remains the only heavy attack; no second meter or hit-point system.

return {
	Charge = {
		Dodge = 14,
	},

	Slam = {
		BallColor = Color3.fromRGB(255, 96, 40),
		CoreColor = Color3.fromRGB(255, 226, 150),
		TrailWidth = 2.2,
		ArmWindow = 8,
		Label = "K.O.",
	},

	-- These are payout multipliers, implemented as bonuses on top of the
	-- existing KO reward pipeline. Limb hits retain the normal base reward.
	Zones = {
		head  = { multiplier = 1.75, critical = true,  label = "CRITICAL",  color = Color3.fromRGB(255, 70, 210) },
		torso = { multiplier = 1.20, critical = false, label = "BODY SHOT", color = Color3.fromRGB(255, 190, 0) },
		armL  = { multiplier = 1.00, critical = false, label = "ARM HIT",   color = Color3.fromRGB(0, 226, 255) },
		armR  = { multiplier = 1.00, critical = false, label = "ARM HIT",   color = Color3.fromRGB(0, 226, 255) },
		legL  = { multiplier = 1.00, critical = false, label = "LEG HIT",   color = Color3.fromRGB(150, 255, 60) },
		legR  = { multiplier = 1.00, critical = false, label = "LEG HIT",   color = Color3.fromRGB(150, 255, 60) },
	},

	DefaultZone = "torso",
}

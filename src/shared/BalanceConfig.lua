-- BalanceConfig: единственный источник чисел баланса.
-- Читают и сервер, и клиент. Никаких магических чисел в других модулях.

return {
	Movement = {
		WalkSpeed = 18,
		JumpPower = 50,
		DodgeSpeed = 45,
		DodgeTime = 0.30,
		DodgeIFrames = 0.25,
		DodgeCooldown = 3.5,
	},

	Throw = {
		ChargeMin = 0.15,
		ChargeMax = 0.90,
		SpeedMin = 60,
		SpeedMax = 130,
		Cooldown = 0.35,
		PickupRadius = 3.0,
		HoldTimeout = 8,
		HoldWarn = 6,
		ImpulseMul = 1.4,
		ImpulseCap = 220,
	},

	Catch = {
		Window = 0.35,
		WhiffCooldown = 1.2,
		Stagger = 0.4,
		Distance = 4.0,
		ConeDeg = 90,
		MaxSpeed = 110,
	},

	Ball = {
		Size = 2.2,
		Elasticity = 0.6,
		Friction = 0.3,
		Density = 1.0,
		HistorySeconds = 1.5,
		HistoryRate = 30,
		MinHitSpeed = 25,
		RespawnBelowY = -60,
	},

	Round = {
		Warmup = 3,
		Duration = 75,
		WinsNeeded = 3,
		SuddenDeath = 20,
		SuddenDeathShrink = 0.75,
		SuddenDeathSpeedMul = 1.2,
		RoundEnd = 4,
		MatchEnd = 8,
		RagdollTime = 2.5,
		MaxActiveRagdolls = 8,
	},

	Hype = {
		Hit = 25,
		Catch = 40,
		Revive = 20,
		RoundWin = 15,
		Max = 100,
	},

	Economy = {
		MatchWin = 140,
		MatchLoss = 60,
		PartyBonus = 0.20,
		QuestDaily = 150,
		QuestWeekly = 500,
		RewardedVideo = 75,
		RewardedVideoPerDay = 5,
		QuestRerollCost = 100,
	},

	XP = {
		Win = 120,
		Loss = 70,
		Hit = 8,
		Catch = 20,
		Revive = 15,
		ToNext = function(level: number): number
			return math.floor(200 + 60 * level ^ 1.35)
		end,
	},

	Bots = {
		ReactionMin = 0.35,
		ReactionMax = 0.8,
		AimErrorMin = 3,
		AimErrorMax = 12,
		MinRealPlayersToStart = 2,
	},

	RateLimits = {
		Throw = 4,
		Catch = 3,
		Dodge = 2,
		Ult = 1,
		QueueJoin = 0.5,
		ShopBuy = 2,
		QuestClaim = 2,
	},
}

-- BalanceConfig v0.3.0: единственный источник чисел баланса.
-- Новое: секция Impact (модель отката), лёгкий мяч, лимит скорости подбора телом.
-- Убрано: Throw.ImpulseMul / Throw.ImpulseCap — откат больше не считается от массы мяча.

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
		SpawnOffset = 2.6,
		SpawnLift = 1.0,
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
		Density = 0.15,
		Elasticity = 0.35,
		Friction = 0.4,
		HistorySeconds = 1.5,
		HistoryRate = 30,
		MinHitSpeed = 22,
		PickupMaxSpeed = 35,
		RespawnBelowY = -60,
		CarryOffset = Vector3.new(1.15, 0.35, -1.55),
	},

	-- Модель отката. Меняешь ощущения здесь, а не в коде.
	Impact = {
		SpeedToImpulse = 0.28,
		MinLaunch = 14,
		MaxLaunch = 42,
		VerticalScale = 0.35,
		MaxVertical = 12,
		Spin = 8,
		DragPerFrame = 0.90,
		StopSpeed = 2,
		CatchGrace = 0.15,
		HitSlowdown = 0.85,
		CatchKnockback = 26,
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
		MinRealPlayersToStart = 1,
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

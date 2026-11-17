-- BalanceConfig v0.9.0: баллистика мяча и честный rate limit.
-- Ball.GravityScale — мяч летит по своей гравитации, иначе дальность 17 studs при разнице команд 44.
-- Throw.LoftDeg / PitchInfluence — бросок не уходит в пол от наклона камеры.
-- Security.RateLimitStrikes = false — превышение лимита не считается читом.

return {
	Locale = { Default = "en", Force = "en" },

	Teams = {
		[1] = { name = "BLUE", color = Color3.fromRGB(46, 155, 255), dark = Color3.fromRGB(22, 78, 148) },
		[2] = { name = "RED", color = Color3.fromRGB(255, 70, 60), dark = Color3.fromRGB(148, 34, 28) },
		Self = Color3.fromRGB(124, 255, 79),
		Neutral = Color3.fromRGB(150, 160, 190),
	},

	Readability = {
		Highlights = true, FillTransparency = 0.9, OutlineTransparency = 0,
		NameTags = true, TagMaxDistance = 150, SelfArrow = true,
		BotNames = { "Rex", "Nova", "Bolt", "Pip", "Zed", "Milo", "Kira", "Juno", "Axel", "Vex" },
		BotScaleJitter = 0.06,
	},

	Mobile = {
		CompactWidth = 760,
		ActionButton = { w = 104, h = 88 },
		ThrowButton = { w = 136, h = 96 },
		DesktopAction = { w = 96, h = 62 },
		DesktopThrow = { w = 140, h = 72 },
		ChargeSafetySeconds = 3,
		GamepadEnabled = true,
		QuestsCollapsedByDefault = true,
	},

	AimAssist = {
		Enabled = true, DesktopAngleDeg = 7, MobileAngleDeg = 12,
		Strength = 0.55, MaxDistance = 80, RequireLineOfSight = true,
	},

	Perf = {
		TargetFps = 60, MinFps = 30,
		StreamingMinRadius = 64, StreamingTargetRadius = 256,
		MaxArenaParts = 3000,
		RagdollSettleSpeed = 1.2, RagdollSettleSpin = 0.6,
		ProfilePushHz = 5, ShadowCasters = false,
	},

	Security = {
		MovementSampleHz = 5, SpeedTolerance = 1.5, SpeedSlack = 10,
		TeleportDelta = 60, SustainedViolations = 3,
		WalkSpeedTolerance = 1.35, HumanoidCheckSeconds = 2,
		ViolationDecaySeconds = 5, KickThreshold = 15,
		RemoteBudgetPerSecond = 30, PingMaxDistance = 120,
		RateLimitStrikes = false,
		LogRateLimits = false,
	},

	FTUE = {
		Enabled = true, PromptSeconds = 6, FirstThrowTarget = 8,
		Steps = { "pickup", "throw", "ko", "catch", "revive" },
		SkipAfterMatches = 2, BenchedHint = true,
	},

	Analytics = {
		Enabled = true, SendToRoblox = true, FunnelName = "ftue",
		SessionFlushSeconds = 20, KeepSessionSeconds = 900,
		TimingBuckets = { 2, 5, 8, 15, 30, 60, 120 },
	},

	Movement = {
		WalkSpeed = 18, JumpPower = 50, DodgeSpeed = 45,
		DodgeTime = 0.30, DodgeIFrames = 0.25, DodgeCooldown = 3.5,
	},

	Throw = {
		ChargeMin = 0.15, ChargeMax = 0.90, SpeedMin = 65, SpeedMax = 135,
		Cooldown = 0.35, PickupRadius = 3.2, HoldTimeout = 8, HoldWarn = 6,
		SpawnOffset = 2.6, SpawnLift = 1.0, OriginLeeway = 8,
		LoftDeg = 8,
		PitchInfluence = 0.3,
		MinAngleDeg = -10,
		MaxAngleDeg = 35,
	},

	Carry = { ShowGlow = true, GlowBrightness = 0.55, GlowRange = 7 },

	Catch = {
		Window = 0.42, WhiffCooldown = 0.9, Stagger = 0.3,
		Distance = 5.0, ConeDeg = 110, MaxSpeed = 125,
	},

	Ball = {
		Size = 2.2, Density = 0.15, Elasticity = 0.35, Friction = 0.4,
		GravityScale = 0.3,
		HistorySeconds = 1.5, HistoryRate = 30, MinHitSpeed = 22,
		PickupMaxSpeed = 35, RespawnBelowY = -60,
		CarryOffset = Vector3.new(1.15, 0.35, -1.55),
	},

	Impact = {
		SpeedToImpulse = 0.28, MinLaunch = 14, MaxLaunch = 42,
		VerticalScale = 0.35, MaxVertical = 12, Spin = 8,
		DragPerFrame = 0.90, StopSpeed = 2, CatchGrace = 0.22,
		HitSlowdown = 0.85, CatchKnockback = 26,
	},

	Arena = {
		Width = 90, Depth = 60, WallHeight = 24, WallThickness = 2, CeilingHeight = 26,
		FloorColor = Color3.fromRGB(196, 148, 90),
		LineColor = Color3.fromRGB(240, 240, 245),
		WallColor = Color3.fromRGB(130, 180, 225),
		SuddenColor = Color3.fromRGB(230, 70, 60),
		BenchColor = Color3.fromRGB(60, 72, 110),
		ShrinkScale = 0.75, ShrinkTime = 0.6,
	},

	Juice = {
		Enabled = true, ShakeScale = 1.0, ShakeDecay = 6, ShakeMaxDistance = 120,
		FovBase = 70, FovPunch = 8, FovRecover = 10,
		FlashBrightness = 0.09, FlashSaturation = 0.35, StarsCount = 14,
		BonkWords = { "BONK!", "WHAM!", "POW!", "OOF!", "BOOP!", "BONK BONK!" },
		SoundVolume = 0.6, MaxSoundsPerFrame = 5, TrailMinSpeed = 40, MomentWindow = 1.2,
	},

	Progression = {
		MaxLevel = 100, MatchWinCoins = 140, MatchLossCoins = 60,
		MatchWinXP = 120, MatchLossXP = 70,
		KoXP = 8, KoCoins = 6, CatchXP = 20, CatchCoins = 12,
		ReviveXP = 15, ThrowXP = 1, LevelUpCoins = 150,
		StreakCoins = { 100, 150, 200, 250, 300, 400, 500 },
		QuestSlots = 3, QuestRewardCoins = 150, QuestRewardXP = 60,
		AutosaveSeconds = 60, LockSeconds = 900,
	},

	Unlocks = {
		[5] = "Curve Throw", [6] = "Quick Hands", [8] = "Cannon Ult", [10] = "Fleet Foot",
		[12] = "Bounce Throw", [15] = "Magnet Ult", [18] = "Grip", [20] = "Heavy Throw",
		[25] = "Wall Ult", [28] = "Second Wind", [30] = "Ghost Ult",
	},

	QuestPool = {
		{ id = "ko", stat = "kos", target = 12 },
		{ id = "catch", stat = "catches", target = 3 },
		{ id = "win", stat = "roundWins", target = 3 },
		{ id = "throw", stat = "throws", target = 25 },
		{ id = "revive", stat = "revives", target = 2 },
	},

	Round = {
		Warmup = 3, Duration = 75, WinsNeeded = 3,
		SuddenDeath = 20, SuddenDeathShrink = 0.75, SuddenDeathSpeedMul = 1.2,
		RoundEnd = 4, MatchEnd = 8, RagdollTime = 2.5, MaxActiveRagdolls = 8,
	},

	Hype = { Hit = 25, Catch = 40, Revive = 20, RoundWin = 15, Max = 100 },

	Economy = {
		MatchWin = 140, MatchLoss = 60, PartyBonus = 0.20,
		QuestDaily = 150, QuestWeekly = 500,
		RewardedVideo = 75, RewardedVideoPerDay = 5, QuestRerollCost = 100,
	},

	XP = {
		Win = 120, Loss = 70, Hit = 8, Catch = 20, Revive = 15,
		ToNext = function(level: number): number
			return math.floor(200 + 60 * level ^ 1.35)
		end,
	},

	Bots = {
		ReactionMin = 0.35, ReactionMax = 0.8, AimErrorMin = 3, AimErrorMax = 12,
		MinRealPlayersToStart = 1,
	},

	RateLimits = {
		Throw = 4, Catch = 6, Dodge = 2, Ult = 1,
		QueueJoin = 0.5, ShopBuy = 2, QuestClaim = 2, UiEvent = 4, PingRequest = 0.2,
	},
}

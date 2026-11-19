-- RankCatalog: competitive tiers and celebration emotes.
-- Ranks are earned from match wins only, so a long session cannot farm them
-- by padding hit counts. Emotes are pure expression: no hitbox, no i-frames.

return {
	Tiers = {
		{ key = "bronze",   name = "BRONZE",   wins = 0,   color = Color3.fromRGB(198, 132, 74) },
		{ key = "silver",   name = "SILVER",   wins = 5,   color = Color3.fromRGB(186, 198, 216) },
		{ key = "gold",     name = "GOLD",     wins = 15,  color = Color3.fromRGB(255, 190, 0) },
		{ key = "platinum", name = "PLATINUM", wins = 35,  color = Color3.fromRGB(0, 226, 255) },
		{ key = "diamond",  name = "DIAMOND",  wins = 75,  color = Color3.fromRGB(120, 170, 255) },
		{ key = "master",   name = "MASTER",   wins = 150, color = Color3.fromRGB(255, 70, 210) },
		{ key = "legend",   name = "LEGEND",   wins = 300, color = Color3.fromRGB(150, 255, 60) },
	},

	Boards = {
		{ key = "kos",     label = "KNOCKOUTS", stat = "kos",     accent = Color3.fromRGB(255, 58, 58) },
		{ key = "catches", label = "CATCHES",   stat = "catches", accent = Color3.fromRGB(150, 255, 60) },
		{ key = "wins",    label = "WINS",      stat = "wins",    accent = Color3.fromRGB(255, 190, 0) },
		{ key = "level",   label = "LEVEL",     stat = "level",   accent = Color3.fromRGB(0, 226, 255) },
	},

	BoardSize = 10,
	WriteSeconds = 60,
	RefreshSeconds = 120,

	EmoteCooldown = 4,

	Emotes = {
		{ key = "cheer", name = "CHEER", glyph = "\u{1F389}", color = Color3.fromRGB(255, 190, 0),   impulse = "none",  particles = 26 },
		{ key = "spin",  name = "SPIN",  glyph = "\u{1F300}", color = Color3.fromRGB(0, 226, 255),   impulse = "spin",  particles = 18 },
		{ key = "jump",  name = "LEAP",  glyph = "\u{2B06}",  color = Color3.fromRGB(150, 255, 60),  impulse = "jump",  particles = 20 },
		{ key = "flex",  name = "FLEX",  glyph = "\u{1F4AA}", color = Color3.fromRGB(255, 70, 210),  impulse = "none",  particles = 22 },
		{ key = "taunt", name = "TAUNT", glyph = "\u{1F61C}", color = Color3.fromRGB(255, 58, 58),   impulse = "none",  particles = 16 },
		{ key = "gg",    name = "GG",    glyph = "\u{1F91D}", color = Color3.fromRGB(186, 198, 216), impulse = "none",  particles = 14 },
	},
}
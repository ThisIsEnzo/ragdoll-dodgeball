-- MonetizationCatalog: gamepasses and developer products.
--
-- SETUP: create each item in Creator Hub, then paste its numeric id below.
-- An id of 0 means "not configured": the store renders the card in a disabled
-- state with a hint instead of prompting a purchase that would fail.
--
-- Gamepasses are permanent and sell identity plus convenience.
-- Products are consumable and sell currency plus a quest reroll.
-- Nothing here sells aim, damage, hitbox or catch window.

return {
	GamePasses = {
		{
			key = "vip",
			id = 0,
			name = "VIP",
			fallbackPrice = 399,
			accent = "amber",
			benefits = {
				"2x coins from every source",
				"Gold name tag in the arena",
				"A fourth daily quest slot",
				"VIP badge on your profile",
			},
		},
		{
			key = "doublexp",
			id = 0,
			name = "DOUBLE XP",
			fallbackPrice = 249,
			accent = "cyan",
			benefits = {
				"2x XP from hits, catches and matches",
				"Reach throw unlocks twice as fast",
			},
		},
		{
			key = "radio",
			id = 0,
			name = "CROWD RADIO",
			fallbackPrice = 149,
			accent = "magenta",
			benefits = {
				"Your name announced on a big hit",
				"Extra crowd reaction on your plays",
			},
		},
	},

	Products = {
		{
			key = "coins_small",
			id = 0,
			name = "POCKET OF COINS",
			fallbackPrice = 49,
			coins = 1200,
			accent = "lime",
		},
		{
			key = "coins_medium",
			id = 0,
			name = "BAG OF COINS",
			fallbackPrice = 199,
			coins = 5600,
			accent = "cyan",
			best = true,
		},
		{
			key = "coins_large",
			id = 0,
			name = "VAULT OF COINS",
			fallbackPrice = 499,
			coins = 15000,
			accent = "amber",
		},
		{
			key = "reroll",
			id = 0,
			name = "QUEST REROLL",
			fallbackPrice = 29,
			reroll = true,
			accent = "magenta",
		},
	},

	-- Applied server side when ownership is confirmed.
	Effects = {
		vip = { coinMultiplier = 2, questSlots = 4, goldTag = true, badge = true },
		doublexp = { xpMultiplier = 2 },
		radio = { announce = true },
	},
}
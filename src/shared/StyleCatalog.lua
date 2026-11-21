-- StyleCatalog: procedural trails, knockout effects and earned titles.
-- Trails/effects cost coins. Titles are status rewards and cannot be purchased.

local Trails = {
	{ key = "none", name = "NO TRAIL", price = 0, width = 0, colors = { Color3.fromRGB(255,255,255) } },
	{ key = "ember", name = "EMBER", price = 450, width = 1.0, colors = { Color3.fromRGB(255,214,120), Color3.fromRGB(255,90,40), Color3.fromRGB(120,20,10) } },
	{ key = "frost", name = "FROST", price = 650, width = 1.0, colors = { Color3.fromRGB(255,255,255), Color3.fromRGB(120,225,255), Color3.fromRGB(20,90,180) } },
	{ key = "venom", name = "VENOM", price = 800, width = 1.1, colors = { Color3.fromRGB(210,255,140), Color3.fromRGB(120,240,60), Color3.fromRGB(20,90,30) } },
	{ key = "royal", name = "ROYAL", price = 1100, width = 1.1, colors = { Color3.fromRGB(220,180,255), Color3.fromRGB(168,123,255), Color3.fromRGB(60,20,120) } },
	{ key = "gold", name = "GOLD", price = 1500, width = 1.2, colors = { Color3.fromRGB(255,255,235), Color3.fromRGB(255,190,0), Color3.fromRGB(140,80,0) } },
	{ key = "pulse", name = "PULSE", price = 1900, width = 1.2, colors = { Color3.fromRGB(255,70,210), Color3.fromRGB(0,226,255), Color3.fromRGB(255,70,210) } },
	{ key = "shadow", name = "SHADOW", price = 2200, width = 1.3, colors = { Color3.fromRGB(90,96,120), Color3.fromRGB(30,34,50), Color3.fromRGB(8,10,18) } },
	{ key = "comet", name = "COMET", price = 2600, width = 1.4, colors = { Color3.fromRGB(255,255,255), Color3.fromRGB(160,220,255), Color3.fromRGB(40,110,255), Color3.fromRGB(10,30,90) } },
	{ key = "prism", name = "PRISM", price = 3400, width = 1.5, colors = { Color3.fromRGB(255,60,60), Color3.fromRGB(255,190,0), Color3.fromRGB(150,255,60), Color3.fromRGB(0,226,255), Color3.fromRGB(168,123,255), Color3.fromRGB(255,70,210) } },
}

local Effects = {
	{ key = "default", name = "STANDARD", price = 0, count = 18, size = 0.7, speed = 12, colors = { Color3.fromRGB(255,255,255) }, ring = false },
	{ key = "ember", name = "EMBER", price = 600, count = 26, size = 0.9, speed = 16, colors = { Color3.fromRGB(255,200,90), Color3.fromRGB(255,70,30) }, ring = false },
	{ key = "frost", name = "FROST", price = 850, count = 24, size = 0.8, speed = 14, colors = { Color3.fromRGB(255,255,255), Color3.fromRGB(90,210,255) }, ring = true },
	{ key = "venom", name = "VENOM", price = 1000, count = 28, size = 0.8, speed = 15, colors = { Color3.fromRGB(200,255,120), Color3.fromRGB(90,220,50) }, ring = false },
	{ key = "royal", name = "ROYAL", price = 1400, count = 30, size = 1.0, speed = 17, colors = { Color3.fromRGB(220,180,255), Color3.fromRGB(150,90,255) }, ring = true },
	{ key = "gold", name = "GOLD", price = 1800, count = 34, size = 1.0, speed = 18, colors = { Color3.fromRGB(255,255,220), Color3.fromRGB(255,180,0) }, ring = true },
	{ key = "nova", name = "NOVA", price = 2500, count = 46, size = 1.3, speed = 24, colors = { Color3.fromRGB(255,255,255), Color3.fromRGB(0,226,255), Color3.fromRGB(255,70,210) }, ring = true },
	{ key = "glitch", name = "GLITCH", price = 3200, count = 52, size = 0.6, speed = 28, colors = { Color3.fromRGB(255,40,40), Color3.fromRGB(40,255,120), Color3.fromRGB(60,120,255) }, ring = false },
}

-- Every title is unlocked by level or a lifetime stat milestone. No prices.
local Titles = {
	{ key = "none", name = "", level = 1 },
	{ key = "rookie", name = "ROOKIE", level = 1, color = Color3.fromRGB(158,174,210) },
	{ key = "baller", name = "BALLER", level = 5, color = Color3.fromRGB(150,255,60) },
	{ key = "sniper", name = "SNIPER", level = 10, color = Color3.fromRGB(0,226,255) },
	{ key = "wall", name = "THE WALL", level = 15, color = Color3.fromRGB(46,155,255) },
	{ key = "ace", name = "ACE", level = 20, color = Color3.fromRGB(255,190,0) },
	{ key = "captain", name = "CAPTAIN", level = 25, color = Color3.fromRGB(255,140,40) },
	{ key = "veteran", name = "VETERAN", level = 30, color = Color3.fromRGB(168,123,255) },
	{ key = "elite", name = "ELITE", level = 40, color = Color3.fromRGB(255,70,210) },
	{ key = "master", name = "MASTER", level = 50, color = Color3.fromRGB(255,58,58) },
	{ key = "legend", name = "LEGEND", level = 75, color = Color3.fromRGB(255,255,255) },
	{ key = "untouchable", name = "UNTOUCHABLE", level = 1, stat = "catches", amount = 100, color = Color3.fromRGB(150,255,60) },
	{ key = "demolisher", name = "DEMOLISHER", level = 1, stat = "kos", amount = 250, color = Color3.fromRGB(255,58,58) },
	{ key = "lifesaver", name = "LIFESAVER", level = 1, stat = "revives", amount = 60, color = Color3.fromRGB(0,226,255) },
}

local function index(list)
	local result = {}
	for _, entry in ipairs(list) do
		result[entry.key] = entry
	end
	return result
end

return {
	Trails = Trails,
	Effects = Effects,
	Titles = Titles,
	TrailByKey = index(Trails),
	EffectByKey = index(Effects),
	TitleByKey = index(Titles),
	Tabs = { "TRAILS", "EFFECTS", "TITLES" },
	TrailLifetime = 2.6,
}

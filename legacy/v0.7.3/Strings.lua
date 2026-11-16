-- Strings v0.6.0: единственное место, где живут игроцкие тексты.
-- Английский основной и принудительный. Добавлены строки FTUE.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local Strings = {}

local DATA = {
	en = {
		["hud.waiting"] = "WAITING FOR PLAYERS",
		["hud.warmup"] = "GET READY",
		["hud.live"] = "LIVE",
		["hud.sudden"] = "SUDDEN DEATH",
		["hud.roundEnd"] = "ROUND OVER",
		["hud.matchEnd"] = "MATCH OVER",
		["hud.idle"] = "LOBBY",
		["hud.seconds"] = "%ds",
		["hud.victory"] = "VICTORY",
		["hud.defeat"] = "DEFEAT",
		["hud.rematch"] = "REMATCH",
		["hud.level"] = "LVL %d",
		["hud.quests"] = "DAILY QUESTS",
		["hud.claim"] = "CLAIM",
		["hud.claimed"] = "DONE",
		["hud.levelUp"] = "LEVEL %d",
		["hud.unlocked"] = "UNLOCKED: %s",
		["hud.streak"] = "DAY %d STREAK",
		["hud.coinsGain"] = "+%d COINS",
		["hud.notSaved"] = "PROGRESS NOT SAVED",
		["hud.throw"] = "THROW",
		["hud.catch"] = "CATCH",
		["hud.dodge"] = "DODGE",
		["hud.ult"] = "ULT",
		["hud.benched"] = "BENCHED — NEXT ROUND SOON",

		["quest.ko"] = "Knock out %d opponents",
		["quest.catch"] = "Catch %d balls",
		["quest.win"] = "Win %d rounds",
		["quest.throw"] = "Throw %d balls",
		["quest.revive"] = "Revive %d teammates",

		["fx.caught"] = "CAUGHT!",
		["fx.backIn"] = "BACK IN!",
		["fx.blocked"] = "BLOCKED",

		["clip.double"] = "DOUBLE BONK",
		["clip.clutch"] = "CLUTCH CATCH",
		["clip.sudden"] = "SUDDEN DEATH WIN",

		["ftue.pickup"] = "RUN INTO A BALL TO GRAB IT",
		["ftue.throw"] = "HOLD THROW, THEN RELEASE",
		["ftue.throwKey"] = "HOLD LEFT MOUSE, THEN RELEASE",
		["ftue.ko"] = "NICE BONK! NOW DODGE WITH SHIFT",
		["ftue.catch"] = "PRESS F TO CATCH A BALL",
		["ftue.catchMobile"] = "TAP CATCH TO STOP A BALL",
		["ftue.revive"] = "A CATCH BRINGS A TEAMMATE BACK",
		["ftue.benched"] = "YOU ARE OUT — WATCH THE ROUND",
		["ftue.done"] = "YOU KNOW THE GAME. GO WIN.",
	},

	es = {},
	pt = {},
	ru = {},
}

local locale = CFG.Locale.Default or "en"

function Strings.SetLocale(id: string)
	if typeof(id) ~= "string" then return end
	local primary = string.lower(string.split(id, "-")[1])
	if DATA[primary] then locale = primary end
end

function Strings.GetLocale(): string
	return locale
end

function Strings.Get(key: string, ...: any): string
	local table_ = DATA[locale]
	local value = table_ and table_[key]
	if not value then value = DATA.en[key] end
	if not value then return key end
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, value, ...)
		return if ok then formatted else value
	end
	return value
end

return Strings

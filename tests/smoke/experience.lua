-- Experience (Experience.lua, 0.43.21): @experience / @exp / @xp: your experience and rested experience live, your alts'
-- from Terminal's own note of them, their rested filling while away.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[experience]\n")
do
	local X, P = ns.Experience, ns.providers.experience
	local save = { lvl = _G.UnitLevel, xp = _G.UnitXP, xpm = _G.UnitXPMax, ex = _G.GetXPExhaustion, rest = _G.IsResting,
		guid = _G.UnitGUID, cls = _G.UnitClass, realm = _G.GetRealmName, max = _G.GetMaxLevelForPlayerExpansion,
		time = _G.time, chars = ns.db.xpChars, out = ns.Output, easy = ns.db.easyMode }
	check(P and ns:ResolveProvider("experience") == P and ns:ResolveProvider("exp") == P and ns:ResolveProvider("xp") == P,
		"@experience, @exp and @xp")
	local now = 1000000
	_G.time = function() return now end
	local level, xp, rested, resting = 23, 4500, 6300, false
	_G.UnitLevel = function() return level end
	_G.UnitXP = function() return xp end
	_G.UnitXPMax = function() return 11000 end
	_G.GetXPExhaustion = function() return rested end
	_G.IsResting = function() return resting end
	_G.UnitGUID = function() return "Player-1-AAA" end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.GetRealmName = function() return "Forever" end
	_G.GetMaxLevelForPlayerExpansion = function() return 60 end
	ns.db.xpChars = {}
	ns.db.easyMode = false

	-- you, live
	P._dirty = true
	local res = UI:Search("@xp")
	check(#res == 1 and res[1].mine and res[1].level == 23 and res[1].detail:find("level 23, 41%", 1, true)
		and res[1].detail:find("rested 57%", 1, true), "you: level, %, rested %: " .. tostring(res[1] and res[1].detail))
	check(ns.Share.Line(res[1]):find(": level 23, 41% (rested 57%)", 1, true), "sent: " .. tostring(ns.Share.Line(res[1])))
	check(ns:FindCommand("xp").run("")[3]:find("Alts show up", 1, true), ".xp with no alts says how they come")

	-- an alt, noted when last played (logged out resting): its rested filled while away, capped at a level and a half
	ns.db.xpChars["Player-1-BBB"] = { name = "Alt Pally", realm = "Forever", class = "PALADIN", level = 40, xp = 1000,
		max = 50000, rested = 0, resting = true, t = now - 8 * 3600 }
	ns.db.xpChars["Player-1-CCC"] = { name = "Old Mage", realm = "Other", class = "MAGE", level = 12, xp = 10, max = 5000,
		rested = 100, resting = false, t = now - 3600 * 24 * 365 }
	ns.db.xpChars["Player-1-DDD"] = { name = "Maxed Rogue", realm = "Forever", class = "ROGUE", level = 60, maxed = true, rested = 0, t = now }
	P._dirty = true
	res = UI:Search("@xp")
	local by = {}
	for _, e in ipairs(res) do by[e.who] = e end
	check(#res == 4 and res[1].mine and res[2].who == "Maxed Rogue" and res[3].who == "Alt Pally", "you first, then the highest level: "
		.. tostring(res[2] and res[2].who))
	local pally = by["Alt Pally"]
	check(pally and pally.rested == 2500 and pally.estimated and pally.detail:find("~rested 5%", 1, true),
		"8 h resting = 5% of a level, marked as an estimate: " .. tostring(pally and pally.detail))
	local mage = by["Old Mage-Other"]
	check(mage and mage.rested == 7500, "another realm says so; rested caps at a level and a half: " .. tostring(mage and mage.rested))
	check(by["Maxed Rogue"].detail:find("level 60 (max)", 1, true), "max level says so")
	check(#UI:Search("@xp lvl:30-50") == 1, "lvl: works on them")

	-- the note follows you: an experience change rewrites it; logging out keeps where the estimate starts
	xp, resting = 9000, true
	X.Record()
	check(ns.db.xpChars["Player-1-AAA"].xp == 9000 and ns.db.xpChars["Player-1-AAA"].resting == true, "your note follows your experience")
	-- the game answers 0 / 0 at logout (and a moment into a login): the note keeps the last real numbers (0.43.23)
	_G.UnitXPMax, _G.UnitXP = function() return 0 end, function() return 0 end
	now = now + 60
	X.Record()
	local note = ns.db.xpChars["Player-1-AAA"]
	check(note.xp == 9000 and note.max == 11000 and note.t == now, "a 0 / 0 reading keeps the experience, moves the time on: "
		.. tostring(note.xp) .. "/" .. tostring(note.max))
	P._dirty = true
	res = UI:Search("@xp")
	check(res[1].mine and res[1].detail:find("level 23, 82%", 1, true), "your row still shows it: " .. tostring(res[1].detail))
	level = 24 -- (a new level with no numbers yet: the old ones don't belong to it)
	X.Record()
	check(ns.db.xpChars["Player-1-AAA"].level == 24 and ns.db.xpChars["Player-1-AAA"].max == nil, "a new level drops the old numbers")
	level = 23
	_G.UnitXPMax, _G.UnitXP = function() return 11000 end, function() return xp end
	X.Record()
	-- a note written by 0.43.21 at logout (0 / 0): shown as just its level, not "0%"
	ns.db.xpChars["Player-1-EEE"] = { name = "Zero Warr", realm = "Forever", class = "WARRIOR", level = 30, xp = 0, max = 0, rested = 0, t = now }
	P._dirty = true
	res = UI:Search("@xp zero")
	check(res[1] and res[1].who == "Zero Warr" and not res[1].detail:find("0%", 1, true), "a 0 / 0 note shows only its level: " .. tostring(res[1] and res[1].detail))
	ns.db.xpChars["Player-1-EEE"] = nil
	-- your row with rested known but no experience yet (early in a login): no "rested 0%" (0.43.27)
	local keptNote = ns.db.xpChars["Player-1-AAA"]
	ns.db.xpChars["Player-1-AAA"] = nil -- (a first login: no note to keep numbers from)
	_G.UnitXPMax = function() return 0 end
	P._dirty = true
	res = UI:Search("@xp")
	check(res[1].mine and not res[1].detail:find("rested", 1, true), "no experience read yet: no rested %: " .. tostring(res[1].detail))
	_G.UnitXPMax = function() return 11000 end
	ns.db.xpChars["Player-1-AAA"] = keptNote
	-- .xp forget
	local out = ns:FindCommand("xp").run("forget old mage")
	check(ns.db.xpChars["Player-1-CCC"] == nil and out[1]:find("Forgot", 1, true), ".xp forget <name>")
	out = ns:FindCommand("xp").run("forget Nobody")
	check(out[1]:find("No alt", 1, true), ".xp forget an unknown name says so")

	-- Simple mode: under Character
	ns.db.easyMode = true
	local cat
	for _, c in ipairs(ns.Easy.CATEGORIES) do for _, k in ipairs(c.kinds) do if k == "experience" then cat = c.id end end end
	check(cat == "character", "Simple mode: experience is under Character")

	_G.UnitLevel, _G.UnitXP, _G.UnitXPMax, _G.GetXPExhaustion, _G.IsResting = save.lvl, save.xp, save.xpm, save.ex, save.rest
	_G.UnitGUID, _G.UnitClass, _G.GetRealmName, _G.GetMaxLevelForPlayerExpansion = save.guid, save.cls, save.realm, save.max
	_G.time, ns.db.xpChars, ns.db.easyMode = save.time, save.chars, save.easy
	P._dirty = true
end

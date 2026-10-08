-- @combatlog: crits on you and by you, what killed you, your deaths; plain questions (0.43.11)
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local CB = ns.CombatLog
local save = { time = _G.time, zone = _G.GetRealZoneText }
local now = 2000000
_G.time = function() return now end
_G.GetRealZoneText = function() return "Elwynn Forest" end
ns.db.combatLog = {}
CB.SetMe("Player-1")

-- the combat log's values, as CombatLogGetCurrentEventInfo lists them
local function Ev(sub, src, srcName, dst, dstName, ...) CB.OnCombatEvent(0, sub, false, src, srcName, 0, 0, dst, dstName, 0, 0, ...) end
do
	-- SPELL_DAMAGE: spellId, spellName, school, amount, overkill, school, resisted, blocked, absorbed, critical
	Ev("SPELL_DAMAGE", "Creature-1", "Hogger", "Player-1", "Me", 1, "Mortal Strike", 1, 245, -1, 1, 0, 0, 0, true)
	Ev("SPELL_DAMAGE", "Creature-1", "Hogger", "Player-1", "Me", 1, "Rend", 1, 20, -1, 1, 0, 0, 0, false)
	-- SWING_DAMAGE: amount, overkill, school, resisted, blocked, absorbed, critical
	Ev("SWING_DAMAGE", "Player-1", "Me", "Creature-2", "Kobold", 88, -1, 1, 0, 0, 0, true)
	Ev("SWING_DAMAGE", "Player-9", "Bob", "Creature-2", "Kobold", 999, -1, 1, 0, 0, 0, true) -- (not about you)
	now = now + 30
	Ev("SPELL_DAMAGE", "Creature-1", "Hogger", "Player-1", "Me", 1, "Mortal Strike", 1, 300, 55, 1, 0, 0, 0, false)
	Ev("UNIT_DIED", "", "", "Player-1", "Me")
	local log = ns.db.combatLog
	check(#log == 3, "kept: the crit on you, your crit, the killing blow (not the plain hit, not Bob's, not the death twice): " .. #log)
	check(log[1].what == "killed" and log[1].who == "Hogger" and log[1].overkill == 55, "the killing blow: who and how")
	check(CB.Line(log[1]):find("Hogger killed you", 1, true) and CB.Line(log[3]):find("Hogger crit you for 245", 1, true)
		and CB.Line(log[2]):find("You crit Kobold for 88", 1, true), "the lines say it")
	-- questions
	check(CB.Question("what killed me") == "killed" and CB.Question("who crit me") == "crit"
		and CB.Question("my biggest crit") == "critby" and CB.Question("how did i die") == "killed", "questions understood")
	check(CB.Question("hogger") == nil and CB.Question("crit") == nil and CB.Question("who priest undercity") == nil
		and CB.Question("@combatlog hogger") == nil, "searches stay searches")
	local res = UI:SearchText("what killed me")
	check(#res == 1 and res[1].name:find("Hogger killed you", 1, true) and UI.answerNote:find("deaths", 1, true),
		"what killed me: the killing blow: " .. tostring(res[1] and res[1].name))
	res = UI:SearchText("who crit me")
	check(#res == 1 and res[1].what == "crit", "who crit me: the crit on you")
	ns.providers.combatlog._dirty = true
	res = UI:Search("@combatlog mortal")
	check(#res >= 2, "@combatlog mortal: by the spell")
	-- a death with no killing blow seen: the last hit says what
	now = now + 100
	Ev("SPELL_DAMAGE", "Creature-3", "Murloc", "Player-1", "Me", 1, "Bite", 1, 12, -1, 1, 0, 0, 0, false)
	Ev("UNIT_DIED", "", "", "Player-1", "Me")
	check(log[1].what == "died" and log[1].who == "Murloc", "a death: the last hit on you")
	-- secret values: nothing read
	local was = _G.issecretvalue
	_G.issecretvalue = function(v) return v == "SECRET" end
	local n = #log
	Ev("SPELL_DAMAGE", "SECRET", "x", "Player-1", "Me", 1, "x", 1, 1, -1, 1, 0, 0, 0, true)
	_G.issecretvalue = was
	check(#log == n and CB.state.secret > 0, "secret values: skipped and counted")
	-- a long fight's crits never push your deaths out
	for i = 1, CB.MAX + 50 do
		Ev("SWING_DAMAGE", "Player-1", "Me", "Creature-2", "Kobold", i, -1, 1, 0, 0, 0, true)
	end
	local deaths = 0
	for _, x in ipairs(log) do if x.what == "died" or x.what == "killed" then deaths = deaths + 1 end end
	check(#log == CB.MAX and deaths == 2, "over the cap: crits go, deaths stay: " .. #log .. " " .. deaths)
	ns:FindCommand("combatlog").run("clear")
	check(#ns.db.combatLog == 0, ".combatlog clear")
end
_G.time, _G.GetRealZoneText = save.time, save.zone

-- Midnight clients keep the combat log from addons: registering is a forbidden action there (0.43.16), never asked
do
	local regs = {}
	local f = { RegisterEvent = function(_, ev) regs[#regs + 1] = ev end }
	local saveBuild = _G.GetBuildInfo
	_G.GetBuildInfo = function() return "1.60.1", "70291", "Oct 1 2026", 120100 end
	local ok, why = ns.CombatLog.Listen(f)
	check(not ok and #regs == 0 and why:find("not asked", 1, true), "Midnight: the combat log isn't asked for")
	-- WoW Forever: Interface 16001, but Midnight's secret values (0.43.17: the build check alone asked, and was blocked)
	_G.GetBuildInfo = function() return "1.60.1", "70291", "Oct 1 2026", 16001 end
	local saveSecret = _G.issecretvalue
	_G.issecretvalue = function() return false end
	ok, why = ns.CombatLog.Listen(f)
	check(not ok and #regs == 0, "WoW Forever (16001 with secret values): not asked either")
	_G.issecretvalue = saveSecret
	_G.GetBuildInfo = function() return "1.15.4", "1", "x", 11504 end
	ns.db.blockedCalls = {}
	ok = ns.CombatLog.Listen(f)
	check(ok and regs[1] == "COMBAT_LOG_EVENT_UNFILTERED", "an older client: asked (once, guarded)")
	_G.GetBuildInfo = saveBuild
end

-- No combat log (WoW Forever): what killed you from the game's Death Recap (0.43.17)
do
	local CB = ns.CombatLog
	local saveR, saveTime = _G.C_DeathRecap, _G.time
	local t = 3000000
	_G.time = function() return t end
	ns.db.combatLog = {}
	CB.ResetRecaps()
	local RECAPS = { [1] = { { timestamp = 10, sourceName = "Defias Pillager", spellName = "Fireball", amount = 80, overkill = -1 },
		{ timestamp = 12, sourceName = "Defias Thug", spellName = "Heroic Strike", amount = 120, overkill = 35 } } }
	_G.C_DeathRecap = { HasRecapEvents = function(id) return RECAPS[id] ~= nil end, GetRecapEvents = function(id) return RECAPS[id] end }
	CB.OnDeath()
	local log = ns.db.combatLog
	check(#log == 1 and log[1].what == "killed" and log[1].who == "Defias Thug" and log[1].spell == "Heroic Strike" and log[1].overkill == 35,
		"a death: the recap's killing blow: " .. tostring(log[1] and log[1].who))
	-- the next death: the next recap (not the first one again)
	t = t + 600
	RECAPS[2] = { { timestamp = 5, sourceName = "Murloc", spellName = "Bite", amount = 9, overkill = 3 } }
	CB.OnDeath()
	check(#log == 2 and log[1].who == "Murloc", "the next death reads the next recap")
	-- a recap not ready yet: the entry is filled in a moment later
	t = t + 600
	CB.OnDeath()
	check(#log == 3 and log[1].what == "died" and not log[1].who, "no recap yet: a death without a killer for now")
	RECAPS[3] = { { timestamp = 1, environmentalType = "FALLING", amount = 500, overkill = 100 } }
	T.FlushAll()
	check(log[1].what == "killed" and log[1].who == "the world" and log[1].spell == "Falling", "filled in once the recap is in: " .. tostring(log[1].spell))
	-- secret values are left out
	t = t + 600
	local saveSecret = _G.issecretvalue
	_G.issecretvalue = function(v) return v == "SECRET" end
	RECAPS[4] = { { timestamp = 1, sourceName = "SECRET", spellName = "SECRET", amount = 5, overkill = 1 } }
	CB.OnDeath()
	_G.issecretvalue = saveSecret
	check(log[1].what == "died" and log[1].who == nil, "a recap of secret values: no killer named")
	T.FlushAll()
	_G.C_DeathRecap, _G.time = saveR, saveTime
	ns.db.combatLog = {}
	CB.ResetRecaps()
end

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
	ns:FindCommand("combatlog").run("clear")
	check(#ns.db.combatLog == 0, ".combatlog clear")
end
_G.time, _G.GetRealZoneText = save.time, save.zone

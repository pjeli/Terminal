-- Your group (Group.lua, 0.46.7): @group / @party: role, dead, offline, out of range, the group's buffs each member is
-- missing; "who is dead", "who needs fortitude"; what Midnight hides (secret values) shown as hidden, never compared.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[group]\n")
do
	local GR, P = ns.Group, ns.providers.group
	local names = { "GetNumGroupMembers", "IsInRaid", "UnitExists", "UnitName", "UnitClass", "UnitGUID", "UnitLevel",
		"UnitIsDeadOrGhost", "UnitIsGhost", "UnitIsFeignDeath", "UnitIsConnected", "UnitGroupRolesAssigned", "UnitInRange",
		"IsPlayerSpell", "issecretvalue", "C_Secrets", "C_RestrictedActions", "UnitIsUnit", "GetRaidRosterInfo", "C_UnitAuras",
		"RegionalUniqueNamesEnabled" }
	local save = {}
	for _, n in ipairs(names) do save[n] = _G[n] end
	local saveEnum, easyWas, cnameWas = _G.Enum, ns.db.easyMode, ns.CharacterName
	ns.db.easyMode = false
	check(P and ns:ResolveProvider("group") == P and ns:ResolveProvider("party") == P and ns:ResolveProvider("raid") ~= P,
		"@group and @party; @raid stays the raids' entrances")

	local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
	_G.issecretvalue = function(v) return v == SECRET end
	-- the party: you (a warrior tank), Ann (priest healer), Bob (mage, dead), Cid (druid, out of range), Dee (paladin, offline)
	local M = {
		player = { name = "Plamen", sur = "Warr", class = "WARRIOR", lclass = "Warrior", guid = "G-ME", role = "TANK",
			buffs = { "Power Word: Fortitude", "Arcane Intellect" } },
		party1 = { name = "Ann", class = "PRIEST", lclass = "Priest", guid = "G-ANN", role = "HEALER",
			buffs = { "Power Word: Fortitude", "Mark of the Wild", "Arcane Intellect", "Blessing of Kings" } },
		party2 = { name = "Bob", class = "MAGE", lclass = "Mage", guid = "G-BOB", role = "DAMAGER", dead = true, buffs = {} },
		party3 = { name = "Cid", class = "DRUID", lclass = "Druid", guid = "G-CID", role = "DAMAGER", far = true,
			buffs = { "Mark of the Wild" } },
		party4 = { name = "Dee", class = "PALADIN", lclass = "Paladin", guid = "G-DEE", role = "NONE", offline = true, buffs = {} },
	}
	local n, raid = 5, false
	local aurasSecret, rangeSecret, restricted = false, false, {}
	_G.GetNumGroupMembers = function() return n end
	_G.IsInRaid = function() return raid end
	_G.UnitExists = function(u) return M[u] ~= nil end
	_G.UnitName = function(u) local m = M[u] if m then return m.name, m.sur end end
	_G.RegionalUniqueNamesEnabled = function() return true end
	ns.CharacterName = function() return "Plamen Warr" end
	_G.UnitClass = function(u) local m = M[u] if m then return m.lclass, m.class, 1 end end
	_G.UnitGUID = function(u) return M[u] and M[u].guid end
	_G.UnitLevel = function(u) return M[u] and 20 end
	_G.UnitIsDeadOrGhost = function(u) return M[u] and M[u].dead or false end
	_G.UnitIsGhost = function() return false end
	_G.UnitIsFeignDeath = function() return false end
	_G.UnitIsConnected = function(u) return not (M[u] and M[u].offline) end
	_G.UnitGroupRolesAssigned = function(u) return M[u] and M[u].role or "NONE" end
	_G.UnitInRange = function(u)
		if rangeSecret then return SECRET, SECRET end
		local m = M[u]
		if not m or m.offline or u == "player" then return false, false end -- (the game doesn't range-check you)
		return not m.far, true
	end
	local auraCalls = 0
	_G.C_UnitAuras = { GetAuraDataByIndex = function(u, i)
		auraCalls = auraCalls + 1
		local m = M[u]
		local b = m and m.buffs[i]
		if not b then return nil end
		return { name = aurasSecret and SECRET or b }
	end }
	_G.C_Secrets = { ShouldAurasBeSecret = function() return aurasSecret end, ShouldUnitIdentityBeSecret = function() return false end }
	_G.Enum = setmetatable({ AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 } },
		{ __index = saveEnum })
	_G.C_RestrictedActions = { IsAddOnRestrictionActive = function(k) return restricted[k] == true end }
	local known = {}
	_G.IsPlayerSpell = function(id) return known[id] == true end
	GR.ResetNamesForTests()

	local function Rows()
		P._dirty = true
		local by = {}
		for _, e in ipairs(ns:GetEntries(P)) do by[e.name] = e end
		return by
	end
	local by = Rows()
	local me, ann, bob, cid, dee = by["Plamen Warr"], by.Ann, by.Bob, by.Cid, by.Dee
	check(me and ann and bob and cid and dee, "every member, you as your full name")
	check(me.mine and me.inRange and me.role == "TANK" and me.detail:find("Tank", 1, true)
		and me.detail:find("needs Mark of the Wild, a Blessing", 1, true),
		"you: tank, needing the buffs the group's druid and paladin give: " .. tostring(me.detail))
	check(ann.missing and #ann.missing == 0 and not ann.detail:find("needs", 1, true), "Ann has them all")
	check(bob.dead and bob.missing == nil and bob.detail:find("Dead", 1, true), "Bob: dead (a dead member's buffs aren't asked for)")
	check(cid.inRange == false and cid.detail:find("out of range", 1, true) and #cid.missing == 3, "Cid: out of range, needs three")
	check(dee.online == false and dee.role == nil and dee.detail:find("Offline", 1, true), "Dee: offline, no role set")
	check(table.concat(GR.Expected({ { classFile = "WARRIOR" } }), ",") == "", "no buffers in the group: no buff expected")

	-- filters
	local function L(q) return #UI:Search(q) end
	check(L("@group is:dead") == 1 and L("@group is:far") == 1 and L("@group is:healer") == 1 and L("@group is:offline") == 1
		and L("@group is:unbuffed") == 2 and L("@group missing:fortitude") == 1 and L("@group missing:wild") == 1
		and L("@group missing:kings") == 2 and L("@group is:tank") == 1, "is:dead / far / healer / offline / unbuffed / tank, missing:<buff>")
	local leaked = false
	for _, e in ipairs(UI:Search("ann")) do if e.kind == "group" then leaked = true end end
	check(not leaked, "only with @group (or asked, or Simple mode's Group category)")

	-- the question
	local Q = GR.Question
	local function A(text) local rows, note = GR.Answer(Q(text)); local t = {} for i, e in ipairs(rows) do t[i] = e.name end return table.concat(t, ","), note end
	check(A("who is dead") == "Bob" and A("who is out of range") == "Cid" and A("who is offline") == "Dee"
		and A("group healers") == "Ann" and A("who needs fortitude") == "Cid", "who is dead / out of range / offline, healers, who needs fortitude")
	local missing = A("missing buffs")
	check(missing == "Plamen Warr,Cid", "missing buffs: you and Cid: " .. missing)
	check(A("who needs kings") == "Plamen Warr,Cid" and A("who needs shadow protection") == "Plamen Warr,Ann,Cid",
		"any buff by name (Blessing of Kings), Shadow Protection asked for by name")
	check(A("who is in range") == "Plamen Warr,Ann,Bob", "who is in range (Dee offline: not known)")
	check(Q("dead") == nil and Q("group finder") == nil and Q("@group is:dead") == nil and Q("tank") == nil
		and Q("deadmines") == nil, "other searches stay searches")
	local _, note = A("who is dead")
	check(note:find("Dead", 1, true) and note:find("1 of 5", 1, true), "the note: what was asked, how many: " .. tostring(note))
	local rows = UI:Search("who needs fortitude")
	check(#rows == 1 and rows[1].name == "Cid" and UI.answerNote, "asked in the prompt")
	check(ns.Easy.QuestionToAdvanced("who needs fortitude") == "@group missing:fortitude " and ns.Easy.QuestionToAdvanced("who is dead")
		== "@group is:dead " and ns.Easy.QuestionToAdvanced("group healers") == "@group is:healer ", "Alt+` writes it as @group")
	check(ns.Easy.BY_ID.group and table.concat(ns.Easy.BY_ID.group.kinds, ",") == "group", "Simple mode's Group category")

	-- Enter targets (the game presses /target), Shift+Enter casts your buff they lack on them
	check(cid.secure and cid.secure.macro(cid) == "/target party3" and cid.isOpen == ns.Never and cid.secondarySecure == nil,
		"Enter: /target party3; no buff of yours to cast")
	check(table.concat({ ns.Easy.Verbs(cid) }, "/") == "target", "verbs: target")
	known[1243] = true -- (you know Power Word: Fortitude)
	by = Rows()
	cid = by.Cid
	check(cid.buffWith == "Power Word: Fortitude" and cid.secondarySecure.macro(cid) == "/cast [@party3] Power Word: Fortitude"
		and table.concat({ ns.Easy.Verbs(cid) }, "/") == "target/cast Power Word: Fortitude" and by.Ann.buffWith == nil,
		"Shift+Enter: your Fortitude on Cid, who lacks it; nothing on Ann")
	-- the group's order moves: the row's member is found again by GUID
	M.party3, M.party2 = M.party2, M.party3
	check(cid.secondarySecure.macro(cid) == "/cast [@party2] Power Word: Fortitude" and cid.secure.macro(cid) == "/target party2",
		"the group reordered: Cid is party2 now, by GUID")
	M.party3, M.party2 = M.party2, M.party3
	check(ns.Share.Line(cid):find("Cid (Druid, Damage): out of range, needs Fortitude, Intellect, a Blessing", 1, true),
		"sent to chat: " .. tostring(ns.Share.Line(cid)))
	known[1243] = nil

	-- a talent's buff counts once someone has it
	M.party1.buffs[#M.party1.buffs + 1] = "Divine Spirit"
	by = Rows()
	check(by["Plamen Warr"].detail:find("Divine Spirit", 1, true), "Divine Spirit (a talent) expected once someone has it")
	table.remove(M.party1.buffs)

	-- what the game hides: in combat range and buffs are secret: shown as hidden, never compared, and said
	aurasSecret, rangeSecret, restricted[0] = true, true, true
	auraCalls = 0
	by = Rows()
	check(auraCalls == 0, "buffs hidden (C_Secrets says so): not read at all: " .. auraCalls)
	check(by.Cid.rangeHidden and by.Cid.inRange == nil and by.Cid.buffsHidden and by.Cid.detail:find("range hidden", 1, true)
		and by.Cid.detail:find("buffs hidden", 1, true), "hidden: range and buffs said so")
	local lead = P.leadRow(P)
	check(lead and lead.noActivate and lead.name == "Range and buffs hidden by the game right now (in combat)", "the line on top: " .. tostring(lead and lead.name))
	local far, farNote = A("who is out of range")
	check(far == "" and farNote:find("hidden by the game", 1, true), "out of range while hidden: none claimed, the note says why: " .. farNote)
	check(L("@group is:far") == 1 and UI:Search("@group is:far")[1].noActivate, "@group is:far while hidden: only the line saying so")
	restricted[0], restricted[1] = nil, true
	check(GR.Why() == "in a boss fight", "a boss fight named as the reason")
	aurasSecret, rangeSecret, restricted[1] = false, false, nil

	-- alone: only you, and a line says so
	n = 0
	by = Rows()
	check(by["Plamen Warr"] and not by.Ann and P.leadRow(P).name:find("not in a group", 1, true), "alone: you, and a line saying so")
	-- a raid: raid1..N, you among them
	n, raid = 3, true
	M.raid1, M.raid2, M.raid3 = M.party1, M.player, M.party3
	_G.UnitIsUnit = function(a, b) return a == "raid2" and b == "player" end
	_G.GetRaidRosterInfo = function(i) return nil, nil, i == 3 and 2 or 1, 20, nil, nil, "Razorfen Kraul" end
	by = Rows()
	check(by["Plamen Warr"] and by["Plamen Warr"].mine and by.Ann and by.Cid and by.Cid.detail:find("group 2", 1, true)
		and by.Cid.zone == "Razorfen Kraul", "a raid: raid1..3, you among them, subgroup and zone")
	M.raid1, M.raid2, M.raid3 = nil, nil, nil

	for _, k in ipairs(names) do _G[k] = save[k] end
	_G.Enum, ns.db.easyMode, ns.CharacterName = saveEnum, easyWas, cnameWas
	GR.ResetNamesForTests()
	P._dirty = true
end

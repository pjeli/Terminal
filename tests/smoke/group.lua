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
	-- (0.50.7, review) no press set up out of combat: not said to be combat
	do
		local pr, icl, said = ns.Print, _G.InCombatLockdown, ""
		ns.Print = function(_, m) said = tostring(m) end
		_G.InCombatLockdown = function() return false end
		ann.activate(ann)
		check(not said:find("In combat", 1, true) and said:find("Ann", 1, true), "out of combat: not \"In combat\": " .. said)
		_G.InCombatLockdown = function() return true end
		ann.activate(ann)
		check(said:find("In combat", 1, true), "in combat: says so")
		ns.Print, _G.InCombatLockdown = pr, icl
	end
	-- (0.50.7, review) one blessing by name: those without it, not those without any blessing ("blessing" took the family)
	table.insert(M.party3.buffs, "Blessing of Might")
	Rows()
	check(A("who needs blessing of kings") == "Plamen Warr,Cid" and A("who needs greater blessing of might") == "Plamen Warr,Ann,Cid",
		"who needs blessing of kings: Cid (Might, no Kings) too: " .. A("who needs blessing of kings") .. " / " .. A("who needs greater blessing of might"))
	check(GR.ToAdvanced(Q("who needs blessing of kings")):find("missing:blessing_kings", 1, true) and L("@group missing:blessing_kings") == 2,
		"Alt+`: missing:blessing_kings, the same two: " .. GR.ToAdvanced(Q("who needs blessing of kings")))
	check(A("who needs a blessing") == "Plamen Warr", "any blessing still the family: " .. A("who needs a blessing"))
	table.remove(M.party3.buffs)
	Rows()
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

	-- every result at once (0.46.10, the player: "@group >>> party" should list the missing buffs as concisely as
	-- possible): said once per buff, "everyone" / "all but X" of the whole group, dead and offline left out
	local SH = ns.Share
	local function Lines(q) return SH.GroupLines(UI:Search(q), q) end
	local l = Lines("@group")
	check(#l == 1 and l[1] == "Missing buffs: Fortitude (Cid), Intellect (Cid), Mark of the Wild (Plamen), Blessing (all but Ann)",
		"@group >>> party: one line, per buff: " .. tostring(l[1]))
	check(Lines("@group is:dead")[1] == "Dead: Bob" and Lines("@group is:dead|far")[1] == "Dead: Bob  ·  Out of range: Cid"
		and Lines("@group is:healer")[1] == "Healers: Ann", "asked about: who, said once: " .. tostring(Lines("@group is:dead")[1])
		.. " / " .. tostring(Lines("@group is:dead|far")[1]) .. " / " .. tostring(Lines("@group is:healer")[1]))
	check(Lines("@group missing:fortitude")[1] == "Missing buffs: Fortitude (Cid)", "missing:fortitude: " .. tostring(Lines("@group missing:fortitude")[1]))
	check(SH.GroupLines(UI:Search("who needs fortitude"), "who needs fortitude")[1] == "Missing buffs: Fortitude (Cid)", "asked in words")
	check(Lines("@group plamen missing:blessing")[1] == "Missing buffs: Blessing (Plamen)",
		"a name narrows it: only Plamen, not \"all but Ann\": " .. tostring(Lines("@group plamen missing:blessing")[1]))
	check(Lines("@group missing:kings")[1] == "Missing buffs: kings (all but Ann)", "a buff by name: " .. tostring(Lines("@group missing:kings")[1]))
	local all = UI:Search("@group")
	local group = SH.GroupRows(all)
	check(SH.GroupHeader(group, "@group") == l[1], ">>> collapsed: the row says what goes")
	local press = SH.PressLine(all, { cmd = "/s", chat = "SAY" }, "@group")
	check(press == "/s " .. l[1], "say: one line the game presses: " .. tostring(press))
	-- consumables: only when asked
	M.party1.buffs[#M.party1.buffs + 1] = "Well Fed"
	M.party1.buffs[#M.party1.buffs + 1] = "Elixir of the Mongoose"
	M.player.buffs[#M.player.buffs + 1] = "Greater Agility"
	P._dirty = true
	check(L("@group missing:consumables") == 2 and L("@group missing:food") == 2 and L("@group missing:elixir") == 1,
		"missing:consumables / food / elixir")
	check(Lines("@group missing:consumables")[1] == "Missing consumables: food (all but Ann), flask or elixir (Cid)",
		"consumables to chat: " .. tostring(Lines("@group missing:consumables")[1]))
	check(A("missing consumables") == "Plamen Warr,Cid" and A("who needs food") == "Plamen Warr,Cid" and A("who needs flask") == "Cid",
		"asked in words: consumables, food, a flask: " .. A("missing consumables") .. " / " .. A("who needs food") .. " / " .. A("who needs flask"))
	check(ns.Easy.QuestionToAdvanced("missing consumables") == "@group missing:consumables " and ns.Easy.QuestionToAdvanced("who needs food")
		== "@group missing:food ", "Alt+`: missing:consumables / missing:food")
	check(not Lines("@group")[1]:find("food", 1, true), "plain @group: buffs only, no consumables")
	local tipLines = {}
	local fakeTip = { SetText = function() end, AddLine = function(_, s2) tipLines[#tipLines + 1] = s2 end, AddDoubleLine = function() end }
	local annRow
	for _, e in ipairs(UI:Search("@group")) do if e.name == "Ann" then annRow = e end end
	annRow.tooltip(annRow, fakeTip)
	check(table.concat(tipLines, "\n"):find("Consumables: Elixir of the Mongoose, Well Fed", 1, true), "the tooltip names a member's consumables")
	table.remove(M.party1.buffs); table.remove(M.party1.buffs); table.remove(M.player.buffs)
	-- nobody missing; buffs hidden; many names cut to fit a line
	local saved = { M.player.buffs, M.party3.buffs }
	M.player.buffs, M.party3.buffs = M.party1.buffs, M.party1.buffs
	P._dirty = true
	check(Lines("@group")[1] == "Nobody is missing a buff the group can give", "nobody missing: " .. tostring(Lines("@group")[1]))
	M.player.buffs, M.party3.buffs = saved[1], saved[2]
	aurasSecret, restricted[0] = true, true
	P._dirty = true
	check(Lines("@group")[1] == "Buffs hidden by the game right now (in combat)", "hidden: " .. tostring(Lines("@group")[1]))
	aurasSecret, restricted[0] = false, nil
	P._dirty = true
	local many = {}
	for i = 1, 30 do
		many[i] = { kind = "group", name = "Longnamedmember" .. i, online = true, shareGroup = GR.ShareGroupOf,
			buffs = i % 2 == 0 and { ["power word: fortitude"] = "Power Word: Fortitude" } or {} }
	end
	local cut = SH.GroupLines(many, "@group missing:fortitude", 6, 255)
	check(#cut == 1 and #cut[1] <= 255 and cut[1]:find("Fortitude (Longnamedmember1, ", 1, true) and cut[1]:find(" %+%d+%)$"),
		"15 names too long for a line: cut to fit, the rest counted: " .. tostring(cut[1]))

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
	-- (0.50.7, review) where unit comparison is restricted UnitIsUnit's answer is secret: you're found by GUID
	_G.UnitIsUnit = function() return SECRET end
	by = Rows()
	check(by["Plamen Warr"] and by["Plamen Warr"].mine and not by.Ann.mine, "UnitIsUnit secret: you still found (by GUID), never compared")
	M.raid1, M.raid2, M.raid3 = nil, nil, nil
	n, raid = 5, false
	_G.UnitIsUnit, _G.GetRaidRosterInfo = save.UnitIsUnit, save.GetRaidRosterInfo

	-- (0.47.0 review) an item search with a buff or consumable word stays a search ("food buff" listed you as needing
	-- agility; "consumables" is @consumable's own word; typing "consecration" flashed the group up at "cons"); a missing
	-- word with what's missing named still asks
	check(Q("food buff") == nil and Q("agility buff") == nil and Q("stamina buff") == nil and Q("scroll of agility buff") == nil
		and Q("consumables") == nil and Q("cons") == nil and Q("buffs") == nil and Q("missing recipes") == nil,
		"a buff or consumable word alone, or missing with nothing of the group's named: a search")
	check(Q("missing buffs") and Q("missing consumables") and Q("who needs food") and Q("unbuffed") and Q("party consumables")
		and Q("needs fortitude"), "still asked: missing buffs / consumables, who needs food, unbuffed, party consumables, needs fortitude")
	-- "who is missing recipes" is the recipes' question: asked before the group's, in the search and in Alt+` alike
	UI:Search("who is missing recipes")
	check(UI.answerNote and UI.answerNote:find("ecipe"), "who is missing recipes: the recipes' answer: " .. tostring(UI.answerNote))
	check(ns.Easy.QuestionToAdvanced("who is missing recipes"):find("^@recipe"), "and Alt+` writes it as @recipe")
	-- a member whose class didn't read, with a role: said without an error (a nil in table.concat's list stopped it)
	check(ns.Join(", ", nil, "Healer") == "Healer" and ns.Join("  ·  ", "Level 20", nil, "", "Zone") == "Level 20  ·  Zone",
		"ns.Join leaves out what isn't there")
	M.party1.lclass = nil
	local ann = Rows().Ann
	local okLine, line = pcall(ns.Share.Line, ann)
	local tipLines = {}
	local tip = { SetText = function() end, AddLine = function(_, l) tipLines[#tipLines + 1] = l end }
	local okTip = pcall(ann.tooltip, ann, tip)
	check(okLine and tostring(line):find("Ann (Healer)", 1, true) and okTip and tipLines[1] == "Level 20  ·  Healer",
		"no class read: \"Ann (Healer)\" in chat, \"Level 20  ·  Healer\" in the tooltip: " .. tostring(line) .. " / " .. tostring(tipLines[1]))
	M.party1.lclass = "Priest"
	-- three things hidden: "Range, buffs and roles hidden ..."
	GR.hidden = { range = 1, buffs = 1, roles = 1 }
	check(GR.HiddenText():find("^Range, buffs and roles hidden"), "three hidden: " .. tostring(GR.HiddenText()))
	GR.hidden = nil
	-- no per-unit events (they fire for every unit, hundreds a second in a fight, and each dirtied the list): read on open
	local unitEvents = {}
	for _, ev in ipairs(P.events or {}) do if ev:find("^UNIT_") then unitEvents[#unitEvents + 1] = ev end end
	check(#unitEvents == 0 and P.refreshOnOpen, "no per-unit events, read afresh on every open: " .. table.concat(unitEvents, ","))
	-- the footer note and the line sent to chat name the roles alike
	local _, dpsNote = A("group dps")
	check(dpsNote:find("Damage dealers", 1, true) and ns.Share.GroupLines(UI:Search("@group is:dps"), "@group is:dps")[1]:find("^Damage dealers: "),
		"damage dealers named alike in the note and in chat: " .. tostring(dpsNote))

	for _, k in ipairs(names) do _G[k] = save[k] end
	_G.Enum, ns.db.easyMode, ns.CharacterName = saveEnum, easyWas, cnameWas
	GR.ResetNamesForTests()
	P._dirty = true
end

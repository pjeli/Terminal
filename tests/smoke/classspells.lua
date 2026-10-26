-- Every class's spells (0.54.1, a player: "'travel form' doesn't list the spell since I don't currently have it.
-- Ideally it'd tell me that it's a druid spell trainable at level 30"; "upcoming spells", "druid spells" listed nothing;
-- "healing wave" on a druid found only the shaman talent): @classspell (Providers/ClassSpells.lua), its questions
-- (Search/Questions/ClassSpells.lua), the spell ids of every rank. Since 0.56.1 they're What's Training's catalog (WT_API.GetCatalog),
-- not a copy of its data (the player: "I would prefer to rely on WT").
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, CS = ns.L, ns.ClassSpells

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end
local function Kind(rows, kind)
	local t = {}
	for _, e in ipairs(rows) do if e.kind == kind then t[#t + 1] = e.name end end
	return table.concat(t, " | ")
end

-- What's Training's catalog, as its Api.lua makes it: each class's trainer and quest spells, its weapon masters
local function Entry(id, level, extra)
	local e = { id = id, kind = "trainer", level = level, cost = 100, petAbility = false }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end
local CATALOG = {
	WARRIOR = { Entry(100, 4), Entry(9001, 6, { races = { 3 } }), Entry(9002, 10, { kind = "quest", cost = 0, quest = { { races = { 1 }, level = 10 } } }),
		Entry(1180, 1, { kind = "weaponMaster", trainers = { Horde = { { npc = 11868, name = "Sayoc", uiMapId = 1454, x = 81.7, y = 19.6 },
			{ npc = 11870, name = "Archibald", uiMapId = 1458, x = 57.3, y = 32.8 } }, Alliance = { { npc = 11867, name = "Woo Ping", uiMapId = 1453, x = 63.9, y = 69.1 } } } }),
		Entry(200, 20, { kind = "weaponMaster", trainers = { Horde = { { npc = 11870, name = "Archibald", uiMapId = 1458, x = 57.3, y = 32.8 } },
			Alliance = { { npc = 11867, name = "Woo Ping", uiMapId = 1453, x = 57.1, y = 57.7 } } } }) },
	DRUID = { Entry(3029, 28, { requiredTalentId = 16942 }), Entry(783, 30) },
	SHAMAN = { Entry(332, 6), Entry(547, 12) },
	ROGUE = { Entry(1180, 1, { kind = "weaponMaster", trainers = { Horde = { { npc = 11868, name = "Sayoc", uiMapId = 1454, x = 81.7, y = 19.6 } } } }),
		Entry(196, 1, { kind = "weaponMaster", trainers = { Horde = { { npc = 2704, name = "Hanashi", uiMapId = 1454, x = 81.5, y = 19.6 } } } }) },
}
local loads = {}
local function CatalogApi()
	return { version = 1, Status = {}, Event = { CLASS_READY = "ClassReady" }, IsReady = function() return true end,
		GetSpells = function() return {} end, GetSource = function() end, RegisterCallback = function() end,
		GetCatalog = function(cls) return CATALOG[cls] or {} end,
		LoadClass = function(cls) loads[cls] = (loads[cls] or 0) + 1 return true end }
end
T.WTCatalogApi = CatalogApi -- (other tests: a What's Training with its catalog)

io.write("[classspells: every class's spells, known or not]\n")
do
	local P = ns.providers.classspells
	local save = { known = rawget(_G, "IsPlayerSpell"), level = _G.UnitLevel, class = _G.UnitClass, show = ns.ShowText,
		easy = ns.db.easyMode, sub = C_Spell.GetSpellSubtext, api = rawget(_G, "WT_API"), race = _G.UnitRace, name = C_Spell.GetSpellName }
	_G.WT_API = CatalogApi()
	_G.UnitRace = function() return "Human", "Human", 1 end
	C_Spell.GetSpellName = function(id) return ({ [9001] = "Stoneform Strike", [9002] = "Defensive Stance" })[id] or save.name(id) end
	CS.Forget(); CS.ForgetLoads()
	local known = {}
	_G.IsPlayerSpell = function(id) return known[id] == true end
	_G.UnitLevel = function() return 2 end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	C_Spell.GetSpellSubtext = function(id) return ({ [332] = "Rank 2", [547] = "Rank 3" })[id] end
	CS.ForgetRows()
	P._dirty = true
	ns.db.easyMode = false; UI:EasyChanged()

	-- a spell you don't have, of another class: found, with its class and level
	local res = UI:Search("@classspell travel form")
	check(res[1] and res[1].name == "Travel Form" and res[1].classFile == "DRUID" and res[1].detail:find(L["level %d"]:format(30), 1, true),
		"travel form: a druid spell, level 30: " .. tostring(res[1] and res[1].detail))
	res = UI:Search("travel form")
	check(Kind(res, "classspells") == "Travel Form", "found by a plain search too: " .. Names(res))
	res = UI:Search("@classspell healing wave")
	check(res[1] and res[1].name == "Healing Wave" and res[1].classFile == "SHAMAN"
		and res[1].detail:find(L["levels %d-%d (%d ranks)"]:format(6, 12, 2), 1, true), "healing wave: the shaman's, its ranks: " .. tostring(res[1] and res[1].detail))
	-- your own class's: only what you don't know (the spellbook has the rest)
	check(Kind(UI:Search("@classspell charge"), "classspells") == "Charge", "your class's, not known yet: listed")
	known[100] = true
	CS.ForgetRows(); P._dirty = true
	check(Kind(UI:Search("@classspell charge"), "classspells") == "", "known: left to the spellbook")
	known[100] = nil
	CS.ForgetRows(); P._dirty = true
	check(Names(UI:Search("@classspell class:druid")) == "Claw | Travel Form" or Names(UI:Search("@classspell class:druid")) == "Travel Form | Claw",
		"class:druid: " .. Names(UI:Search("@classspell class:druid")))
	-- Enter: the Wowhead page; the tooltip: each rank's level and id
	local shown
	ns.ShowText = function(_, title, text) shown = text end
	local hw = UI:Search("@classspell healing wave")[1]
	hw.activate(hw)
	check(shown == "https://www.wowhead.com/forever/spell=332", "Enter: its Wowhead page: " .. tostring(shown))
	local lines = {}
	local tip = setmetatable({}, { __index = function(_, k)
		if k == "SetText" or k == "AddLine" then return function(_, s) lines[#lines + 1] = tostring(s) end end
		if k == "AddDoubleLine" then return function(_, a, b) lines[#lines + 1] = tostring(a) .. " = " .. tostring(b) end end
		if k == "SetHyperlink" then return function() error("no link") end end
		return function() end
	end })
	hw.tooltip(hw, tip)
	local text = table.concat(lines, "\n")
	check(text:find("Rank 2  " .. L["level %d"]:format(6) .. " = ID 332", 1, true)
		and text:find("Rank 3  " .. L["level %d"]:format(12), 1, true), "the tooltip: each rank's level and id: " .. text)
	-- (0.54.3, the player: cleaner) Enter's and Shift+Enter's hints on lines of their own
	check(text:find("\nEnter: show its Wowhead page\nShift+Enter: link it in chat", 1, true), "the keys: a line each: " .. text)
	-- (0.54.8, the player) no "A Shaman spell" line: the row says whose it is; "ID", as the other tooltips say it
	check(not text:find(" spell\n", 1, true) and not text:find("Shaman", 1, true) and not text:find("= id ", 1, true),
		"no class line, ID in capitals: " .. text)

	-- the questions
	local Q = CS.Q
	local q = Q.Question("druid spells")
	check(q and q.class == "DRUID", "druid spells")
	local rows = Q.Answer(q)
	check(Names(rows) == "Claw | Travel Form", "by level: Claw (28) then Travel Form (30): " .. Names(rows))
	check(Q.Question("spells for druids").class == "DRUID" and Q.Question("shaman spells at level 12").level == 12, "spells for druids, shaman spells at level 12")
	check(Names((Q.Answer(Q.Question("shaman spells at level 12")))) == "Healing Wave", "at a level: the spells learned then")
	q = Q.Question("upcoming spells")
	check(q and q.upcoming, "upcoming spells")
	check(Names((Q.Answer(q))) == "Charge", "your class's next: Charge at 4 (you're 2): " .. Names((Q.Answer(q))))
	check(Names((Q.Answer(Q.Question("spells at level 4")))) == "Charge", "spells at level 4")
	q = Q.Question("when do i learn travel form")
	check(q and Names((Q.Answer(q))) == "Travel Form", "when do i learn travel form: another class's when not yours")
	check(Q.Question("fire spells") == nil and Q.Question("spells not on my bars") == nil and Q.Question("druid talents") == nil
		and Q.Question("@classspell druid") == nil, "not its questions: a search, another question, talents, Advanced syntax")
	check(ns.QuestionToAdvanced("druid spells") == "@spell class:druid ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("druid spells")))
	-- (0.63.7, review) a level (a later rank's), your own class's: kept as said, no Advanced line finds the same
	check(ns.QuestionToAdvanced("shaman spells at level 12") == "shaman spells at level 12 "
		and ns.QuestionToAdvanced("warrior spells") == "warrior spells ",
		"a level, your own class: as said: " .. tostring(ns.QuestionToAdvanced("shaman spells at level 12")) .. " / " .. tostring(ns.QuestionToAdvanced("warrior spells")))
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("druid spells"); FlushAll()
	check(Names(UI.Results()) == "Claw | Travel Form", "Simple mode, typed: " .. Names(UI.Results()))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()

	-- (0.54.6, the player: every class's spells under @spell, as @talent) @spell: your spellbook and the spells you don't
	-- know, any class's; class: narrows; is:known keeps to the spellbook; @classspell is @spell; an action only casts
	do
		local SP = ns.providers.spells
		local book = { { name = "Heroic Strike", spellID = 78 }, { name = "Battle Shout", spellID = 6673 } }
		local spellsWas = SP.collect
		SP.collect = function()
			local out = {}
			for i, b in ipairs(book) do out[i] = { name = b.name, spellID = b.spellID, key = b.name, classFile = "WARRIOR", className = "Warrior" } end
			return out
		end
		SP._dirty = true
		CS.ForgetRows(); P._dirty = true
		local function Kinds(res)
			local t = {}
			for _, e in ipairs(res) do t[#t + 1] = tostring(e.name) .. "/" .. tostring(e.kind) end
			return table.concat(t, " | ")
		end
		local res = UI:Search("@spell")
		check(Kinds(res):find("Heroic Strike/spells", 1, true) and Kinds(res):find("Travel Form/classspells", 1, true)
			and Kinds(res):find("Charge/classspells", 1, true), "@spell: the spellbook and every class's: " .. Kinds(res))
		check(res[1] and res[1].kind == "spells", "your spellbook first: " .. Kinds(res))
		check(Kinds(UI:Search("@spell travel form")) == "Travel Form/classspells", "@spell travel form: the druid's")
		check(Names(UI:Search("@spell class:druid")) == "Claw | Travel Form" or Names(UI:Search("@spell class:druid")) == "Travel Form | Claw",
			"@spell class:druid: " .. Names(UI:Search("@spell class:druid")))
		res = UI:Search("@spell class:mine")
		check(Kinds(res):find("Heroic Strike/spells", 1, true) and Kinds(res):find("Charge/classspells", 1, true)
			and not Kinds(res):find("Travel Form", 1, true), "class:mine: yours, known and not: " .. Kinds(res))
		res = UI:Search("@spell is:known")
		check(Kinds(res) ~= "" and not Kinds(res):find("classspells", 1, true), "is:known: the spellbook only (as @spell was): " .. Kinds(res))
		check(not Kinds(UI:Search("@spell -is:known")):find("/spells", 1, true), "-is:known: what you don't know")
		check(Kinds(UI:Search("@classspell travel form")) == "Travel Form/classspells" and Kinds(UI:Search("@classspell")) == Kinds(UI:Search("@spell")),
			"@classspell: another name for @spell")
		check(not Kinds(UI:Search("@spell do:cast")):find("classspells", 1, true), "do:cast: only what you can cast")
		check(ns:KindName(ns.providers.classspells) == "@spell", "the list is named @spell")
		-- (0.54.7, the player: still "Class spell" on the right) its rows say Spell, as the spellbook's do, in its colour
		check(ns.providers.classspells.label == ns.providers.spells.label and ns.providers.classspells.color == ns.providers.spells.color,
			"labelled Spell: " .. tostring(ns.providers.classspells.label))
		-- "my spells": your spellbook (a question)
		local q = Q.Question("my spells")
		check(q and q.known and Names((Q.Answer(q))) == "Battle Shout | Heroic Strike", "my spells: the spellbook: " .. Names((Q.Answer(q))))
		check(ns.QuestionToAdvanced("my spells") == "@spell is:known ", "my spells as Advanced: " .. tostring(ns.QuestionToAdvanced("my spells")))
		-- (0.55.15, the player's screenshot: "46 results · 46 results") the note says what, the footer how many
		local _, note = Q.Answer(q)
		check(note == ns.L["Your spellbook"], "the note has no count of its own: " .. tostring(note))
		-- (0.55.18, review) Alt+` keeps Advanced words typed after a question
		check(ns.QuestionToAdvanced("my spells sort:name") == "@spell is:known sort:name ", "a question's sort: kept: " .. tostring(ns.QuestionToAdvanced("my spells sort:name")))
		check(Q.Question("my druid spells").class == "DRUID" and not Q.Question("my druid spells").known, "my druid spells: the druid's")
		SP.collect = spellsWas; SP._dirty = true
	end

	-- every rank's spell id
	rows = ns.SpellIds.Answer(ns.SpellIds.Question("spellid healing wave"))
	check(Names(rows) == "Healing Wave (Rank 2) | Healing Wave (Rank 3)" and rows[1].spellID == 332 and rows[2].spellID == 547,
		"spellid healing wave: every rank, from the class data: " .. Names(rows))

	-- (0.56.1) What's Training's catalog: each class's loaded once (its names, ranks and links); your race's and
	-- faction's alone for your class; a quest's spell said so
	check(loads.DRUID == 1 and loads.WARRIOR == 1, "LoadClass: once per class: " .. tostring(loads.DRUID) .. " " .. tostring(loads.WARRIOR))
	CS.ForgetRows(); P._dirty = true
	check(Kind(UI:Search("@classspell stoneform strike"), "classspells") == "", "another race's spell (dwarf): not for your class's rows")
	res = UI:Search("@classspell defensive stance")
	check(res[1] and res[1].name == "Defensive Stance" and res[1].detail:find(L["a quest"], 1, true), "your race's quest spell: listed, a quest: "
		.. tostring(res[1] and res[1].detail))
	_G.UnitClass = function() return "Druid", "DRUID" end
	CS.ForgetRows(); P._dirty = true
	check(Kind(UI:Search("@classspell stoneform strike"), "classspells") == "Stoneform Strike", "another class's: every race's")
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	-- a name the game hasn't loaded yet: What's Training's, once ClassReady says it has it
	C_Spell.GetSpellName = function(id) if id == 783 then return nil end return ({ [9001] = "Stoneform Strike", [9002] = "Defensive Stance" })[id] or save.name(id) end
	CS.Forget(); CS.ForgetRows(); P._dirty = true
	check(Kind(UI:Search("@classspell travel form"), "classspells") == "", "no name yet: not listed")
	CATALOG.DRUID[2].name = "Travel Form"
	ns.WhatsTraining.ClassReady(); FlushAll()
	check(Kind(UI:Search("@classspell travel form"), "classspells") == "Travel Form", "ClassReady: listed by What's Training's name")
	CATALOG.DRUID[2].name = nil

	-- without What's Training: no other class's spells, "druid spells" isn't asked and the footer says to install it;
	-- "my spells" (the spellbook) still answered
	_G.WT_API = nil
	CS.Forget(); CS.ForgetRows(); P._dirty = true
	check(Kind(UI:Search("@spell travel form"), "classspells") == "", "without it: no class spells")
	check(Q.Question("druid spells") == nil and Q.Question("upcoming spells") == nil and Q.Question("my spells") ~= nil,
		"without it: its questions aren't asked, \"my spells\" is")
	ns.db.easyMode = true; UI:EasyChanged()
	local addons = _G.C_AddOns
	_G.C_AddOns = setmetatable({ IsAddOnLoaded = function() return false end }, { __index = addons })
	ns.Integrations.ForgetHint()
	local hint = ns.Integrations.MissingHint("druid spells")
	check(hint and hint:find("What's Training", 1, true) and hint:find(L["Install %s for this."]:sub(1, 7), 1, true), "the hint: install What's Training: " .. tostring(hint))
	-- an older What's Training (its API without the catalog): update it
	_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) return n == "WhatsTraining" end }, { __index = addons })
	ns.Integrations.ForgetHint()
	hint = ns.Integrations.MissingHint("druid spells")
	check(hint and hint:find(L["Update %s for this."]:sub(1, 6), 1, true), "an older What's Training: update it: " .. tostring(hint))
	_G.C_AddOns = addons
	ns.Integrations.ForgetHint()
	check(ns.Integrations.MissingHint("my spells") == nil, "\"my spells\": no hint")
	ns.Integrations.ForgetHint()
	ns.db.easyMode = false; UI:EasyChanged()

	_G.IsPlayerSpell, _G.UnitLevel, _G.UnitClass, ns.ShowText, C_Spell.GetSpellSubtext = save.known, save.level, save.class, save.show, save.sub
	_G.WT_API, _G.UnitRace, C_Spell.GetSpellName = save.api, save.race, save.name
	ns.db.easyMode = save.easy
	CS.Forget(); CS.ForgetRows(); P._dirty = true
	UI:EasyChanged()
end

-- "dagger trainer": What's Training's weapon masters (its catalog, every class's weapon skills; 0.56.1: no copy of its
-- list any more), your faction's; without What's Training, every weapon master
io.write("[classspells: weapon masters from What's Training's catalog]\n")
do
	local I, CS = ns.Integrations, ns.ClassSpells
	local save = { api = rawget(_G, "WT_API"), npcRow = I.NpcRow, npcField = I.NpcField, here = I.Here, dist = I.NpcDistance,
		fac = _G.UnitFactionGroup, easy = ns.db.easyMode }
	_G.WT_API = CatalogApi()
	_G.UnitFactionGroup = function() return "Horde" end
	local NPCS = {
		{ npcID = 11868, key = 11868, kind = "npc", name = "Sayoc", sub = "Weapon Master" },
		{ npcID = 11870, key = 11870, kind = "npc", name = "Archibald", sub = "Weapon Master" },
		{ npcID = 11867, key = 11867, kind = "npc", name = "Woo Ping", sub = "Weapon Master" },
		{ npcID = 2704, key = 2704, kind = "npc", name = "Hanashi", sub = "Weapon Master" },
	}
	local BY, DIST = {}, { [11868] = 50, [2704] = 20, [11870] = 70, [11867] = 90 }
	for _, n in ipairs(NPCS) do BY[n.key] = n end
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function() return NPCS end })
	ns:AliasesChanged()
	I.NpcRow = function(id) return BY[id] end
	I.NpcField = function(id, f)
		if f == "friendlyToFaction" then return "AH" end
		if f == "subName" then return BY[id] and BY[id].sub end
	end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	ns.Pipes.ClearSteps(); ns.Pipes.ForgetTrainers()
	local function Npcs(rows)
		local t = {}
		for _, e in ipairs(rows) do if e.kind == "npc" then t[#t + 1] = e.name end end
		return table.concat(t, " | ")
	end
	local set, list = CS.WeaponMasters({ 1180 })
	check(set[11868] and set[11870] and not set[11867] and not set[2704] and #list == 2 and list[1].npc == 11868,
		"daggers: the Horde's two, each once (the warrior's and the rogue's lists): " .. #list)
	ns.db.easyMode = true; UI:EasyChanged()
	check(Npcs(UI:SearchText("dagger trainer")) == "Sayoc | Archibald", "dagger trainer: the Horde's two (not Woo Ping, not Hanashi), the nearer first: "
		.. Npcs(UI:SearchText("dagger trainer")))
	-- (0.57.1, the player: "polearm trainer" listed every weapon master)
	for _, q in ipairs({ "polearm trainer", "polearms trainer", "polearm trainers", "nearest polearm trainer" }) do
		check(Npcs(UI:SearchText(q)) == "Archibald", q .. ": the Horde's one, Archibald: " .. Npcs(UI:SearchText(q)))
	end
	-- (0.61.1, the player: "it should work for advanced syntax too") trainer:<weapon> in Advanced mode, every way it's
	-- written, as "fist weapons trainer" is in Simple: the masters What's Training (or TrainerSpells) says teach it
	ns.db.easyMode = false; UI:EasyChanged()
	for _, q in ipairs({ "@npc trainer:dagger", "@npc trainer:daggers", "@npc trainer:Daggers sort:distance" }) do
		check(Npcs(UI:SearchText(q)) == "Sayoc | Archibald", q .. ": " .. Npcs(UI:SearchText(q)))
	end
	for _, q in ipairs({ "@npc trainer:polearm", "@npc trainer:polearms" }) do
		check(Npcs(UI:SearchText(q)) == "Archibald", q .. ": " .. Npcs(UI:SearchText(q)))
	end
	for _, w in ipairs({ "fist", "fists", "fistweapons", "staff", "staves" }) do
		check(ns.Filters.WeaponSkillIds(w) ~= nil, "trainer:" .. w .. " names a weapon skill")
	end
	check(ns.Easy.ToAdvanced("nearest fist weapons trainer"):find("trainer:fist ", 1, true), "Simple's words, as Advanced writes them: trainer:fist")
	ns.db.easyMode = true; UI:EasyChanged()
	-- without What's Training: every weapon master
	_G.WT_API = nil
	ns.Pipes.ClearSteps(); ns.Pipes.ForgetTrainers()
	check(CS.WeaponMasters({ 1180 }) == nil, "without it: no list of its own")
	check(Npcs(UI:SearchText("dagger trainer")) == "Hanashi | Sayoc | Archibald | Woo Ping", "without it: every weapon master, the nearest first: "
		.. Npcs(UI:SearchText("dagger trainer")))
	ns.db.easyMode = false; UI:EasyChanged()
	ns.providers.npc = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "npc" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	_G.WT_API, _G.UnitFactionGroup = save.api, save.fac
	I.NpcRow, I.NpcField, I.Here, I.NpcDistance = save.npcRow, save.npcField, save.here, save.dist
	ns.db.easyMode = save.easy
	ns.Pipes.ClearSteps(); ns.Pipes.ForgetTrainers()
	UI:EasyChanged()
end

io.write("[classspells: What's Training's catalog read, never written]\n")
do
	-- (release review) a quest spell's races joined with its variants' were added to What's Training's own list, again on
	-- every rebuild
	local was = rawget(_G, "WT_API")
	local e = Entry(9010, 10, { kind = "quest", cost = 0, races = { 2 }, quest = { { races = { 5 } } } })
	local api = CatalogApi()
	api.GetCatalog = function(cls) return cls == "WARRIOR" and { e } or {} end
	_G.WT_API = api
	CS.Forget(); CS.Data(); CS.Forget()
	local data = CS.Data()
	local mine = data.WARRIOR and data.WARRIOR[1]
	check(#e.races == 1 and mine and mine.races and #mine.races == 2, "its races and its variants' (" .. tostring(mine and mine.races and #mine.races)
		.. "), What's Training's list as it was (" .. #e.races .. ")")
	_G.WT_API = was
	CS.Forget()
end

-- OneForAll's hunter pets (1.0.2, the player's ask; Providers/Integrations/OneForAll/Pets.lua), a hunter's only; no kind of
-- their own since 1.0.37 (the player: "get rid of tame entirely"): @spell has each pet ability's ranks (its level,
-- training points, learned or not, Enter the beasts that teach it; is:ability), @npc's beasts say they're tameable
-- (is:tameable; family, level, the ranks each teaches, the rare ones), and "where to learn bite 2", "cat abilities",
-- "tameable cats", "rare pets in the barrens" answer from OneForAll's beasts; a table not in the shape expected said
-- once; another class, or without OneForAll: none.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L = ns.Integrations, ns.OneForAll, ns.L
local P = OA.Pets

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[oneforall: a hunter's pet abilities and beasts to tame]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"),
		db = rawget(_G, "OneForAllCharDB"), here = I.Here, spot = I.SpotXY, failed = I.failed, on = OA.on, easy = ns.db.easyMode,
		class = _G.UnitClass, level = _G.UnitLevel, walk = UI.WalkTo }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Said(s) for _, m in ipairs(said) do if m:find(s, 1, true) then return m end end end
	local function Fresh()
		for _, id in ipairs({ "book" }) do
			ns.providers[id] = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		end
		I.failed, OA.on = {}, nil
		OA.Forget(); P.TurnOff()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	-- (@spell's rows: the pet ability ranks among them)
	local function Rows()
		local p = ns.providers.spells
		p._dirty = true
		local out = {}
		for _, e in ipairs(ns:GetEntries(p)) do if e.ability then out[#out + 1] = e end end
		return out
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "book" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		local class = "HUNTER"
		_G.UnitClass = function() return "Hunter", class end
		_G.UnitLevel = function() return 20 end
		-- its tables (Data/HunterPets.lua's shape), a few of each
		local known = { Bite = 1 }
		_G.OneForAll = {
			BOOKS = { { name = "A Book", questId = 1, itemId = 2 } },
			PET_FAMILIES = {
				{ name = "Cat", icon = "ability_hunter_pet_cat", diet = { "Meat", "Fish" }, abilities = { "Bite", "Claw", "Dash" }, trainer = { "Growl" },
					note = "Role: Offense.", tames = { { name = "Elder Shadowmaw Panther", level = "42-43", zone = "Stranglethorn Vale", npcID = 768, mapID = 1434, x = 50, y = 50 } } },
				{ name = "Wolf", icon = "ability_hunter_pet_wolf", diet = { "Meat" }, abilities = { "Bite", "Dash", "Furious Howl" }, trainer = { "Growl" },
					tames = { { name = "Prairie Wolf", level = "5-6", zone = "Mulgore", npcID = 2958, mapID = 1412, x = 41.7, y = 67.9 } } },
				{ name = "Boar", abilities = { "Bite", "Charge" }, trainer = { "Growl" }, tames = {} },
				{ name = "Bird of Prey", abilities = { "Claw" }, trainer = { "Growl" }, tames = { { name = "Strigid Owl", level = "5-6", zone = "Teldrassil", npcID = 1995 } } },
				{ tames = "broken" }, -- (not in the shape expected: left out)
			},
			PET_ABILITIES = {
				{ name = "Bite", icon = "ability_druid_ferociousbite", source = "wild", families = { "Cat", "Wolf", "Boar" }, ranks = {
					{ rank = 1, level = 1, tp = 1, desc = "Bite the enemy.", learnFrom = { { name = "Prairie Wolf", level = "5-6", zone = "Mulgore", npcID = 2958, mapID = 1412, x = 41.7, y = 67.9, family = "Wolf" } } },
					{ rank = 2, level = 8, tp = 4, desc = "Bite harder.", learnFrom = {
						{ name = "Prairie Wolf Alpha", level = "9-10", zone = "Mulgore", npcID = 2960, mapID = 1412, x = 52.2, y = 41.5, family = "Wolf" },
						{ name = "Coyote", level = "10-11", zone = "Westfall", npcID = 834, mapID = 1436, x = 50.7, y = 29.2, family = "Wolf" } } },
					{ rank = 3, level = 16, tp = 7, noSource = true, learnFrom = {} } } },
				{ name = "Growl", source = "trainer", families = { "All families" }, ranks = { { rank = 1, level = 1, tp = 0, learnFrom = {} } } },
				{ name = "Charge", source = "wild", families = { "Boar" }, ranks = { { rank = 1, level = 1, tp = 5, learnFrom = {} } } },
				{ name = "Mine!", source = "wild", families = { "Bird of Prey" }, ranks = { { rank = 1, level = 1, tp = 5, learnFrom = {} } } },
			},
			PET_RARES = {
				{ name = "Humar the Pridelord", level = "23", zone = "The Barrens", npcID = 5828, mapID = 1413, x = 62, y = 33.3, family = "Cat",
					why = "Only tameable black lion.", speed = 1.3 },
				{ name = "Echeyakee", level = "16", zone = "The Barrens", npcID = 3475, family = "Cat", why = "White lion skin." },
			},
		}
		function OneForAll:GetKnownPetRank(name) return known[name] end
		_G.OneForAllCharDB = { petAbilitiesScanned = true }
		I.SpotXY = function(ui, c) return ({ [1412] = 1, [1413] = 1, [1436] = 2, [1434] = 2 })[ui], c[1] * 10, c[2] * 10 end
		-- another class: none of it
		class = "MAGE"
		Fresh()
		check(not P.on and #Rows() == 0 and P.Question("tameable cats") == nil and I.NpcExtraText == nil, "a mage: no pet abilities, no beasts, no question")
		-- (1.0.31) why there's none, said in .debug log; and a class not said yet at login: looked at again a moment later
		local traced = {}
		local traceWas = ns.Trace
		ns.Trace = function(_, m) traced[#traced + 1] = tostring(m) end
		class = nil
		Fresh()
		ns.Trace = traceWas
		local said = table.concat(traced, " / ")
		check(said:find("not a hunter", 1, true) and not P.on, "no class said at login: traced, none yet: " .. said)
		class = "HUNTER"
		FlushAll()
		check(P.on, "a moment later, a hunter: its pets added")
		class = "MAGE"

		class = "HUNTER"
		Fresh()
		check(P.on and ns.providers.tame == nil and ns:ResolveProvider("tame") == nil, "a hunter: its pets added, no @tame")
		check(not Said(L["Its pet abilities are unavailable."]) and not Said(L["Its beasts to tame are unavailable."])
			and not Said(L["Its rare beasts are unavailable."]), "its tables as expected: nothing said of the pets: " .. tostring(said[1]))
		-- the ranks: an @spell row each
		local all = Rows()
		local by, tb, nab, nbeast = {}, {}, 0, 0
		for _, e in ipairs(all) do by[e.key] = e; nab = nab + 1 end
		for _, e in ipairs(P.Beasts()) do tb[e.name] = e; nbeast = nbeast + 1 end
		check(nab == 6 and by["pet:Bite#2"] and by["pet:Bite#2"].name == L["%s (Rank %d)"]:format("Bite", 2) and by["pet:Bite#2"].kind == "spells",
			"a row a rank, in @spell: " .. Names(all))
		check(by["pet:Bite#1"].known == true and by["pet:Bite#2"].known == false, "learned: as OneForAll saw your pets' spellbooks")
		check((by["pet:Bite#2"].detail or ""):find(L["%d beasts teach it"]:format(2), 1, true) and (by["pet:Growl#1"].detail or ""):find(L["pet trainer"], 1, true),
			"how each is learned: " .. tostring(by["pet:Bite#2"].detail))
		local res = UI:Search("@spell is:ability is:learned")
		check(#res == 1 and res[1].key == "pet:Bite#1", "@spell is:ability is:learned: the rank your pets know: " .. Names(res))
		res = UI:Search("@spell is:unlearned bite")
		check(#res == 2 and res[1].ability and res[2].ability, "@spell is:unlearned bite: the ranks your pets don't know: " .. Names(res))
		res = UI:Search("@spell is:ability")
		check(#res == 6, "@spell is:ability: the ranks: " .. Names(res))
		res = UI:Search("@spell -is:ability")
		local pets = 0
		for _, e in ipairs(res) do if e.ability then pets = pets + 1 end end
		check(#res > 0 and pets == 0, "@spell -is:ability: your own spells: " .. Names(res))
		check(not ns.Spells.Unplaced(by["pet:Bite#2"]) and not ns.Filters._.IS.learned(by["pet:Bite#2"]) and ns.Easy.Verbs(by["pet:Bite#2"]) ~= L["show in spellbook"],
			"a rank isn't a spell of yours off your bars, nor learned, nor shown in the spellbook")
		local view = setmetatable({}, { __index = by["pet:Bite#2"] })
		check(ns.Filters._.IS.ability(view), "is:ability on a view of a rank (a chain's, a nearest list's): still a rank")
		-- (OneForAll hasn't looked at your pets: learned or not isn't said)
		_G.OneForAllCharDB = nil
		local b1
		for _, e in ipairs(Rows()) do if e.key == "pet:Bite#1" then b1 = e end end
		check(b1 and b1.known == nil and not (b1.detail or ""):find(L["learned"], 1, true), "not looked yet: nothing said of it")
		_G.OneForAllCharDB = { petAbilitiesScanned = true }
		Rows()
		-- the beasts: each once, its family's, the teachers, the rares; NPC rows
		check(nbeast == 7 and tb["Coyote"].kind == "npc" and tb["Coyote"].freqKey == ns:FreqKey("npc", 834), "the beasts, each once, NPC rows: " .. Names(P.Beasts()))
		-- Questie's @npc rows of them: tameable, their family and what they teach
		check(ns.Filters._.IS.tameable({ kind = "npc", npcID = 768 }) and not ns.Filters._.IS.tameable({ kind = "npc", npcID = 1 })
			and ns.Filters._.IS.tameable(tb["Echeyakee"]), "is:tameable: an NPC OneForAll lists, and its own rows")
		check(I.NpcExtraText(2958):find("tameable", 1, true) and I.NpcExtraText(2958):find(L["teaches %s"]:format("bite 1"), 1, true)
			and not I.NpcExtraText(2958):find("mulgore", 1, true) and I.NpcExtraDetail(768):find("Cat", 1, true)
			and type(I.NpcExtraTooltip(5828)) == "function" and I.NpcExtraText(1) == nil, "@npc rows of beasts: their words, detail, tooltip")
		check(tb["Prairie Wolf"].family == "Wolf" and #tb["Prairie Wolf"].teachList == 1 and tb["Prairie Wolf"].teachList[1] == "Bite 1",
			"a beast that teaches a rank: said")
		check(tb["Humar the Pridelord"].rare and tb["Humar the Pridelord"].ui == 1413, "a rare one, on the map")
		check(tb["Echeyakee"].activate and not tb["Echeyakee"].ui, "no spot: Enter says so")
		check(tb["Coyote"].minLevel == 10 and tb["Coyote"].maxLevel == 11, "its levels")
		check(table.concat({ ns.Easy.Verbs(tb["Coyote"]) }, "/") == L["show on map"] .. "/" .. L["set waypoint"], "a beast's verbs: the map's")
		-- Enter on a rank: the beasts that teach it, nearest first (no Questie here: the question, from OneForAll's beasts)
		local walked
		UI.WalkTo = function(_, t) walked = t end
		by["pet:Bite#2"].activate(by["pet:Bite#2"])
		check(walked == "who teaches bite 2", "Enter on Bite 2: its teachers: " .. tostring(walked))
		UI.WalkTo = save.walk
		res = UI:Search(walked)
		check(#res == 2 and (res[1].name == "Prairie Wolf Alpha" or res[1].name == "Coyote") and not (res[3]), walked .. ": the two that teach it: " .. Names(res))
		said = {}
		by["pet:Bite#3"].activate(by["pet:Bite#3"])
		check(Said(L["OneForAll knows no beast that teaches %s."]:format(by["pet:Bite#3"].name)), "a rank no beast is known to teach: said")
		-- the questions
		for _, s in ipairs({ "where to learn bite 2", "who teaches bite 2", "bite 2 teachers", "pet bite", "cat abilities", "what can a boar learn",
			"tameable cats", "where to tame a wolf", "rare pets in the barrens", "rare cats", "what can i tame at my level", "tameable birds of prey",
			"nearest tameable wolves", "pet abilities", "where to learn charge", "bite 2" }) do
			check(P.Question(s) ~= nil, s .. ": the pets question")
		end
		for _, s in ipairs({ "my pets", "bite", "rare ring", "cats eye", "tameable mounts", "growl" }) do
			check(P.Question(s) == nil, s .. ": not it")
		end
		-- (review, 1.0.36) a spell of yours by its name: the spell ("tame beast"), not the beasts
		local spWas = ns.providers.spells
		ns.providers.spells = { id = "spells", label = "Spell", _dirty = true, collect = function() return { { name = "Tame Beast" } } end }
		check(P.Question("tame beast") == nil and P.Question("where to tame a beast") ~= nil, "tame beast: your spell, not the pets question")
		ns.providers.spells = spWas
		-- (1.0.36, 1.0.37) Simple mode: its abilities are Spells, its beasts NPCs (with Questie's same beasts)
		local E = ns.Easy
		E.Reindex()
		check(E.CategoryOf(by["pet:Bite#2"]) == "spells" and E.CategoryOf(tb["Coyote"]) == "npcs", "Simple mode: its abilities Spells, its beasts NPCs")
		check(P.Question("tameable birds of prey").family.name == "Bird of Prey" and P.Question("nearest tameable wolves").family.name == "Wolf"
			and P.Question("tameable foxes") == nil, "families by their plural")
		ns.db.easyMode = true; UI:EasyChanged()
		I.Here = function() return { cont = 1, x = 500, y = 400 } end
		UI:Open("where to learn bite 2"); FlushAll()
		local r = UI.Results()
		check(r[1] and r[1].name == "Prairie Wolf Alpha" and (r[1].detail or ""):find("yd", 1, true) and r[2] and r[2].name == "Coyote",
			"where to learn bite 2: its teachers, nearest first (the other continent's after): " .. Names(r))
		check(rawget(r[1], "nearRest") ~= nil and (r[1].detail or ""):find("^%d+ yd  "), "the distance as the list reads it back (the English yd, then two spaces): " .. tostring(r[1].detail))
		UI:Hide(); FlushAll()
		UI:Open("rare pets in the barrens"); FlushAll()
		r = UI.Results()
		check(#r == 2 and r[1].rare and r[2].rare, "rare pets in the barrens: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("tameable cats"); FlushAll()
		r = UI.Results()
		local ranks = false
		for _, e in ipairs(r) do if e.ability then ranks = true end end
		check(#r == 3 and not ranks, "tameable cats: the beasts, not the ranks cats learn: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("what can i tame at my level"); FlushAll()
		r = UI.Results()
		local over = false
		for _, e in ipairs(r) do if (e.minLevel or 0) > 20 or e.ability then over = true end end
		check(#r > 0 and not over, "at my level: none above it: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("cat abilities"); FlushAll()
		r = UI.Results()
		local names = {}
		for _, e in ipairs(r) do names[e.ability or "?"] = (names[e.ability or "?"] or 0) + 1 end
		check(names.Bite == 1 and names.Growl == 1 and not names.Charge and not names["?"], "cat abilities: each once, not the boar's: " .. Names(r))
		UI:Hide(); FlushAll()
		check(P.ToAdvanced(P.Question("tameable cats")) == "@npc is:tameable cat ", "to Advanced: " .. P.ToAdvanced(P.Question("tameable cats")))
		check(P.ToAdvanced(P.Question("cat abilities")) == "@spell is:ability cat ", "to Advanced: " .. P.ToAdvanced(P.Question("cat abilities")))
		check(P.ToAdvanced(P.Question("who teaches bite 2")) == '@npc "' .. L["teaches %s"]:format("bite 2") .. ';" sort:distance ', "to Advanced: " .. P.ToAdvanced(P.Question("who teaches bite 2")))
		res = UI:Search(P.ToAdvanced(P.Question("cat abilities")))
		check(#res >= 1 and res[1].ability, "@spell is:ability cat: a cat's ranks: " .. Names(res))
		ns.db.easyMode = false; UI:EasyChanged()
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d pet ability ranks (@spell) and %d families of beasts to tame (@npc)"]:format(6, 4), 1, true), ".integrations: " .. lines)

		-- not in the shape expected: said once, the beasts still there
		said = {}
		OneForAll.PET_ABILITIES = "moved"
		Fresh()
		check(P.on and #Rows() == 0 and #P.Beasts() == 5, "abilities changed: the beasts kept (not the ones known only as teachers): " .. #P.Beasts())
		check(Said(L["Its pet abilities are unavailable."]), "said in chat: " .. tostring(said[1]))
		OneForAll.PET_RARES = nil
		said = {}
		OA.Forget()
		check(P.Rares() == nil and not Said(L["Its rare beasts are unavailable."]), "no rares: quiet")
		_G.OneForAll = nil
		Fresh()
		check(not P.on and P.Question("tameable cats") == nil and #Rows() == 0, "without OneForAll: none, no question")
	end)
	_G.OneForAll, _G.OneForAllCharDB = save.lib, save.db
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.Here, I.SpotXY, UI.WalkTo = save.print, save.here, save.spot, save.walk
	I.failed, OA.on, _G.UnitClass, _G.UnitLevel = save.failed, save.on, save.class, save.level
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget(); P.TurnOff()
	if ns.providers.spells then ns.providers.spells._dirty = true end
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall_pets: " .. tostring(err)) end
end

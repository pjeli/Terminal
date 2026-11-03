-- OneForAll's hunter pets (1.0.2, the player's ask; Providers/Integrations/OneForAll/Pets.lua), one kind since 1.0.9 and a hunter's
-- only: @tame lists each pet ability's ranks (its level, training points, learned or not, Enter the beasts that teach
-- it; is:ability) and the beasts to tame (family, level, where, the ranks each teaches, the rare ones); "where to learn
-- bite 2", "cat abilities", "tameable cats", "rare pets in the barrens" in Simple mode; a table not in the shape
-- expected said once; another class, or without OneForAll: none.
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
		for _, id in ipairs({ "book", "tame" }) do
			ns.providers[id] = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		end
		I.failed, OA.on = {}, nil
		OA.Forget(); P.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	local function Rows()
		local p = ns.providers.tame
		p._dirty = true
		return ns:GetEntries(p)
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "book" and id ~= "tame" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
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
		-- another class: no @tame at all
		class = "MAGE"
		Fresh()
		check(ns.providers.tame == nil and ns.providers.petability == nil and P.Question("tameable cats") == nil, "a mage: no @tame, no question")
		class = "HUNTER"
		Fresh()
		local pt = ns.providers.tame
		check(pt and ns:ResolveProvider("petabilities") == pt and ns:ResolveProvider("tameable") == pt and ns.providers.petability == nil,
			"a hunter: one kind, @tame, under both names")
		check(not Said(L["Its pet abilities are unavailable."]) and not Said(L["@tame (its beasts to tame) is unavailable."])
			and not Said(L["Its rare beasts are unavailable."]), "its tables as expected: nothing said of the pets: " .. tostring(said[1]))
		-- the ranks: a row each
		local all = Rows()
		local by, tb, nab, nbeast = {}, {}, 0, 0
		for _, e in ipairs(all) do
			if e.ability then by[e.key] = e; nab = nab + 1 else tb[e.name] = e; nbeast = nbeast + 1 end
		end
		check(nab == 6 and by["Bite#2"] and by["Bite#2"].name == L["%s (Rank %d)"]:format("Bite", 2) and by["Bite#2"].kind == "tame",
			"a row a rank: " .. Names(all))
		check(by["Bite#1"].known == true and by["Bite#2"].known == false, "learned: as OneForAll saw your pets' spellbooks")
		check((by["Bite#2"].detail or ""):find(L["%d beasts teach it"]:format(2), 1, true) and (by["Growl#1"].detail or ""):find(L["pet trainer"], 1, true),
			"how each is learned: " .. tostring(by["Bite#2"].detail))
		local res = UI:Search("@tame is:learned")
		check(#res == 1 and res[1].key == "Bite#1", "@tame is:learned: the rank your pets know, no beast: " .. Names(res))
		res = UI:Search("@tame is:unlearned bite")
		check(#res == 2 and res[1].ability and res[2].ability, "@tame is:unlearned bite: ranks only: " .. Names(res))
		res = UI:Search("@tame is:ability")
		check(#res == 6, "@tame is:ability: the ranks: " .. Names(res))
		-- (OneForAll hasn't looked at your pets: learned or not isn't said)
		_G.OneForAllCharDB = nil
		local b1
		for _, e in ipairs(Rows()) do if e.key == "Bite#1" then b1 = e end end
		check(b1 and b1.known == nil and not (b1.detail or ""):find(L["learned"], 1, true), "not looked yet: nothing said of it")
		_G.OneForAllCharDB = { petAbilitiesScanned = true }
		Rows()
		-- the beasts: each once, its family's, the teachers, the rares
		check(nbeast == 7, "the beasts, each once: " .. Names(all))
		check(tb["Prairie Wolf"].family == "Wolf" and #tb["Prairie Wolf"].teachList == 1 and tb["Prairie Wolf"].teachList[1] == "Bite 1",
			"a beast that teaches a rank: said")
		check(tb["Humar the Pridelord"].rare and tb["Humar the Pridelord"].ui == 1413, "a rare one, on the map")
		check(tb["Echeyakee"].activate and not tb["Echeyakee"].ui, "no spot: Enter says so")
		check(tb["Coyote"].minLevel == 10 and tb["Coyote"].maxLevel == 11, "its levels")
		check(table.concat({ ns.Easy.Verbs(tb["Coyote"]) }, "/") == L["show on map"] .. "/" .. L["set waypoint"], "a beast's verbs: the map's")
		res = UI:Search("@tame -is:ability cat")
		check(#res == 3, "@tame cat, the beasts: " .. Names(res))
		-- Enter on a rank: the beasts that teach it, nearest first
		local walked
		UI.WalkTo = function(_, t) walked = t end
		by["Bite#2"].activate(by["Bite#2"])
		check(walked and walked:find("@tame", 1, true), "Enter on Bite 2: its teachers: " .. tostring(walked))
		UI.WalkTo = save.walk
		res = UI:Search(walked)
		check(#res == 2 and (res[1].name == "Prairie Wolf Alpha" or res[1].name == "Coyote") and not (res[3]), walked .. ": the two that teach it: " .. Names(res))
		said = {}
		by["Bite#3"].activate(by["Bite#3"])
		check(Said(L["OneForAll knows no beast that teaches %s."]:format(by["Bite#3"].name)), "a rank no beast is known to teach: said")
		-- the questions
		for _, s in ipairs({ "where to learn bite 2", "who teaches bite 2", "bite 2 teachers", "pet bite", "cat abilities", "what can a boar learn",
			"tameable cats", "where to tame a wolf", "rare pets in the barrens", "rare cats", "what can i tame at my level", "tameable birds of prey",
			"nearest tameable wolves", "pet abilities", "where to learn charge", "bite 2" }) do
			check(P.Question(s) ~= nil, s .. ": the pets question")
		end
		for _, s in ipairs({ "my pets", "bite", "rare ring", "cats eye", "tameable mounts", "growl" }) do
			check(P.Question(s) == nil, s .. ": not it")
		end
		check(P.Question("tameable birds of prey").family.name == "Bird of Prey" and P.Question("nearest tameable wolves").family.name == "Wolf"
			and P.Question("tameable foxes") == nil, "families by their plural")
		ns.db.easyMode = true; UI:EasyChanged()
		I.Here = function() return { cont = 1, x = 500, y = 400 } end
		UI:Open("where to learn bite 2"); FlushAll()
		local r = UI.Results()
		check(r[1] and r[1].name == "Prairie Wolf Alpha" and (r[1].detail or ""):find("yd", 1, true) and r[2] and r[2].name == "Coyote",
			"where to learn bite 2: its teachers, nearest first (the other continent's after): " .. Names(r))
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
		check(P.ToAdvanced(P.Question("tameable cats")) == "@tame cat ", "to Advanced: " .. P.ToAdvanced(P.Question("tameable cats")))
		check(P.ToAdvanced(P.Question("cat abilities")) == "@tame is:ability cat ", "to Advanced: " .. P.ToAdvanced(P.Question("cat abilities")))
		ns.db.easyMode = false; UI:EasyChanged()
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d pet ability ranks and %d families (@tame)"]:format(6, 4), 1, true), ".integrations: " .. lines)

		-- not in the shape expected: said once, the beasts still there
		said = {}
		OneForAll.PET_ABILITIES = "moved"
		Fresh()
		local beasts = 0
		for _, e in ipairs(Rows()) do if e.ability then beasts = -100 else beasts = beasts + 1 end end
		check(ns.providers.tame and beasts == 5, "abilities changed: @tame keeps its beasts (not the ones known only as teachers): " .. beasts)
		check(Said(L["Its pet abilities are unavailable."]), "said in chat: " .. tostring(said[1]))
		OneForAll.PET_RARES = nil
		said = {}
		OA.Forget()
		check(P.Rares() == nil and not Said(L["Its rare beasts are unavailable."]), "no rares: quiet")
		_G.OneForAll = nil
		Fresh()
		check(not ns.providers.tame and P.Question("tameable cats") == nil, "without OneForAll: none, no question")
	end)
	_G.OneForAll, _G.OneForAllCharDB = save.lib, save.db
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.Here, I.SpotXY, UI.WalkTo = save.print, save.here, save.spot, save.walk
	I.failed, OA.on, _G.UnitClass, _G.UnitLevel = save.failed, save.on, save.class, save.level
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget(); P.Forget()
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall_pets: " .. tostring(err)) end
end

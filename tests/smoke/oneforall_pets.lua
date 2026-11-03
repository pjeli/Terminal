-- OneForAll's hunter pets (1.0.2, the player's ask; Providers/OneForAll/Pets.lua): @petability (each rank: its level,
-- training points, learned or not, Enter the beasts that teach it) and @tame (the beasts to tame: family, level, where,
-- the ranks each teaches, the rare ones); "where to learn bite 2", "cat abilities", "tameable cats", "rare pets in the
-- barrens" in Simple mode; a table not in the shape expected said once; without OneForAll: neither.
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
		for _, id in ipairs({ "book", "petability", "tame" }) do
			ns.providers[id] = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		end
		I.failed, OA.on = {}, nil
		OA.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "book" and id ~= "petability" and id ~= "tame" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		local class = "MAGE"
		_G.UnitClass = function() return "Mage", class end
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
		Fresh()
		local pa, pt = ns.providers.petability, ns.providers.tame
		check(pa and pt and ns:ResolveProvider("petabilities") == pa and ns:ResolveProvider("tameable") == pt, "@petability, @tame")
		check(not Said(L["@petability (its pet abilities) is unavailable."]) and not Said(L["@tame (its beasts to tame) is unavailable."])
			and not Said(L["Its rare beasts are unavailable."]), "its tables as expected: nothing said of the pets: " .. tostring(said[1]))
		-- @petability: a row a rank
		local ab = ns:GetEntries(pa)
		local by = {}
		for _, e in ipairs(ab) do by[e.key] = e end
		check(#ab == 6 and by["Bite#2"] and by["Bite#2"].name == L["%s (Rank %d)"]:format("Bite", 2), "a row a rank: " .. Names(ab))
		check(by["Bite#1"].known == true and by["Bite#2"].known == false, "learned: as OneForAll saw your pets' spellbooks")
		check((by["Bite#2"].detail or ""):find(L["%d beasts teach it"]:format(2), 1, true) and (by["Growl#1"].detail or ""):find(L["pet trainer"], 1, true),
			"how each is learned: " .. tostring(by["Bite#2"].detail))
		local res = UI:Search("@petability is:learned")
		check(#res == 1 and res[1].key == "Bite#1", "@petability is:learned: " .. Names(res))
		res = UI:Search("@petability is:unlearned bite")
		check(#res == 2, "@petability is:unlearned bite: " .. Names(res))
		-- (OneForAll hasn't looked at your pets: learned or not isn't said)
		_G.OneForAllCharDB = nil
		pa._dirty = true
		local b1
		for _, e in ipairs(ns:GetEntries(pa)) do if e.key == "Bite#1" then b1 = e end end
		check(b1 and b1.known == nil and not (b1.detail or ""):find(L["learned"], 1, true), "not looked yet: nothing said of it")
		_G.OneForAllCharDB = { petAbilitiesScanned = true }
		pa._dirty = true
		-- @tame: each beast once, its family's, the teachers, the rares
		local tm = ns:GetEntries(pt)
		local tb = {}
		for _, e in ipairs(tm) do tb[e.name] = e end
		check(#tm == 7, "the beasts, each once: " .. Names(tm))
		check(tb["Prairie Wolf"].family == "Wolf" and #tb["Prairie Wolf"].teachList == 1 and tb["Prairie Wolf"].teachList[1] == "Bite 1",
			"a beast that teaches a rank: said")
		check(tb["Humar the Pridelord"].rare and tb["Humar the Pridelord"].ui == 1413, "a rare one, on the map")
		check(tb["Echeyakee"].activate and not tb["Echeyakee"].ui, "no spot: Enter says so")
		check(tb["Coyote"].minLevel == 10 and tb["Coyote"].maxLevel == 11, "its levels")
		res = UI:Search("@tame cat")
		check(#res == 3, "@tame cat: " .. Names(res))
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
			"nearest tameable wolves", "pet abilities" }) do
			check(P.Question(s) ~= nil, s .. ": the pets question")
		end
		for _, s in ipairs({ "my pets", "bite", "where to learn charge", "rare ring", "cats eye", "tameable mounts", "growl" }) do
			check(P.Question(s) == nil, s .. ": not it")
		end
		class = "HUNTER"
		check(P.Question("where to learn charge") and P.Question("bite 2"), "a hunter: \"where to learn charge\", \"bite 2\" are the pet's")
		class = "MAGE"
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
		UI:Open("what can i tame at my level"); FlushAll()
		r = UI.Results()
		local over = false
		for _, e in ipairs(r) do if (e.minLevel or 0) > 20 then over = true end end
		check(#r > 0 and not over, "at my level: none above it: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("cat abilities"); FlushAll()
		r = UI.Results()
		local names = {}
		for _, e in ipairs(r) do names[e.ability] = (names[e.ability] or 0) + 1 end
		check(names.Bite == 1 and names.Growl == 1 and not names.Charge, "cat abilities: each once, not the boar's: " .. Names(r))
		UI:Hide(); FlushAll()
		check(P.ToAdvanced(P.Question("tameable cats")) == "@tame cat ", "to Advanced: " .. P.ToAdvanced(P.Question("tameable cats")))
		ns.db.easyMode = false; UI:EasyChanged()
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d pet ability ranks (@petability), %d families (@tame)"]:format(6, 4), 1, true), ".integrations: " .. lines)

		-- not in the shape expected: said once, the other list still there
		said = {}
		OneForAll.PET_ABILITIES = "moved"
		Fresh()
		check(not ns.providers.petability and ns.providers.tame, "abilities changed: no @petability, @tame still")
		check(Said(L["@petability (its pet abilities) is unavailable."]), "said in chat: " .. tostring(said[1]))
		OneForAll.PET_RARES = nil
		said = {}
		OA.Forget()
		check(P.Rares() == nil and not Said(L["Its rare beasts are unavailable."]), "no rares: quiet")
		_G.OneForAll = nil
		Fresh()
		check(not ns.providers.petability and not ns.providers.tame and P.Question("tameable cats") == nil, "without OneForAll: neither, no question")
	end)
	_G.OneForAll, _G.OneForAllCharDB = save.lib, save.db
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.Here, I.SpotXY, UI.WalkTo = save.print, save.here, save.spot, save.walk
	I.failed, OA.on, _G.UnitClass, _G.UnitLevel = save.failed, save.on, save.class, save.level
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget()
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall_pets: " .. tostring(err)) end
end

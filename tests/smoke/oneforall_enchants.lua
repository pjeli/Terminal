-- OneForAll's enchants (Providers/Integrations/OneForAll/Enchants.lua): @enchant, a row per enchant option (its slot by the
-- game's slot names, what it gives, how you get it, whether you know it); stat: and slot: read them; one you know opens
-- as its recipe row, one you don't walks to where to learn it, an arcanum to where to get it; "enchants for bracers",
-- "enchants for my weapon", "agility enchants", "enchants i can make"; without OneForAll: none.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L = ns.Integrations, ns.OneForAll, ns.L
local EN = OA.Enchants

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	table.sort(t)
	return table.concat(t, " | ")
end

io.write("[oneforall: enchants]\n")
do

	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"),
		failed = I.failed, on = OA.on, easy = ns.db.easyMode, known = rawget(_G, "IsPlayerSpell"),
		inv = rawget(_G, "GetInventoryItemID"), instant = C_Item.GetItemInfoInstant, walk = UI.WalkTo }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Fresh()
		ns.providers.enchant = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "enchant" then table.remove(ns.providerOrder, i) end end
		I.failed, OA.on = {}, nil
		OA.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
		if ns.Easy.ForgetKinds then ns.Easy.ForgetKinds() end
	end
	local function Row(name)
		for _, e in ipairs(ns:GetEntries(ns.providers.enchant)) do if e.name == name then return e end end
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "enchant" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		-- you know one enchant by your recipe index, one only by the game (its window not read yet)
		-- (a stand-in recipe list: this test's own providers table, the real one put back after)
		local function RecipeOpen() end
		local function RecipeShows() return false end
		ns.providers.recipes = { id = "recipes", label = "Recipe", aliases = { "recipe" }, collect = function() return { { key = 7779, name = "Enchant Bracer - Minor Agility",
			recipeID = 7779, profID = 333, profName = "Enchanting", activate = RecipeOpen, isOpen = RecipeShows, reagents = { { 10940, 2 } } } } end }
		_G.IsPlayerSpell = function(id) return id == 7779 or id == 7457 end
		_G.OneForAll = {
			ENCHANTS = {
				[247] = { "+1 Agility", { ITEM_MOD_AGILITY_SHORT = 1 } }, [66] = { "+3 Stamina", { ITEM_MOD_STAMINA_SHORT = 3 } },
				[1900] = { "Crusader", {}, true }, [805] = { "+2 Weapon Damage", { WEAPON_DAMAGE = 2 } },
				[15] = { "+1 Stamina, +8 Armor", { ITEM_MOD_STAMINA_SHORT = 1, RESISTANCE0_NAME = 8 } },
				[2544] = { "+8 Spell Power, +1% Spell Hit", { ITEM_MOD_SPELL_POWER_SHORT = 8 } },
				[2463] = { "+7 Fire Resistance", { FIRE_RES = 7 } },
			},
			ENCHANT_OPTIONS = {
				{ e = 247, n = "Enchant Bracer - Minor Agility", p = "Enchanting", s = 7779, req = 80, c = 4, t = 512, m = 31 },
				{ e = 66, n = "Enchant Bracer - Minor Stamina", p = "Enchanting", s = 7457, req = 50, c = 4, t = 512, m = 31 },
				{ e = 1900, n = "Enchant Weapon - Crusader", p = "Enchanting", s = 20034, req = 300, c = 2, t = 0, m = 189939 },
				{ e = 805, n = "Enchant 2H Weapon - Minor Impact", p = "Enchanting", s = 7745, req = 100, c = 2, t = 0, m = 1378 },
				{ e = 15, n = "Light Armor Kit", p = "Leatherworking", s = 2152, i = 2304, req = 1, c = 4, t = 1050016, m = 30 },
				{ e = 2544, n = "Arcanum of Focus", i = 18330, src = "Quest: Lorekeeper Lydros (Dire Maul)", c = 4, t = 130, m = 31 },
				{ e = 2463, n = "Enchant Cloak - Fire Resistance", p = "Enchanting", s = 13657, req = 175, c = 4, t = 65536, m = 30, st = 0 },
				{ n = "Broken" }, -- (not in the shape expected: left out)
			},
		}
		Fresh()
		local p = ns.providers.enchant
		check(p ~= nil and #ns:GetEntries(p) == 7, "@enchant: a row per option in the shape expected: " .. (p and #ns:GetEntries(p) or -1))
		local agi, sta, cru, imp, kit, arc, fire = Row("Enchant Bracer - Minor Agility"), Row("Enchant Bracer - Minor Stamina"),
			Row("Enchant Weapon - Crusader"), Row("Enchant 2H Weapon - Minor Impact"), Row("Light Armor Kit"), Row("Arcanum of Focus"),
			Row("Enchant Cloak - Fire Resistance")
		check(agi and agi.detail:find("+1 Agility", 1, true) and agi.detail:find("Enchanting 80", 1, true) and agi.detail:find(L["You know it"], 1, true),
			"its detail: what it gives, how you get it, you know it: " .. tostring(agi and agi.detail))
		check(arc and arc.detail:find("Lorekeeper Lydros", 1, true) and arc.itemID == 18330 and fire.detail:find(L["not in WoW Forever yet"], 1, true),
			"a non-crafted source as OneForAll says; one not in Forever yet: " .. tostring(arc and arc.detail))

		-- slot: and stat: read them
		ns.db.easyMode = false; UI:EasyChanged()
		local function S(q) UI.lastScan, UI.lastOverview = nil, nil; return Names(UI:Search(q)) end
		check(S("@enchant slot:bracers") == "Enchant Bracer - Minor Agility | Enchant Bracer - Minor Stamina", "slot:bracers: " .. S("@enchant slot:bracers"))
		check(S("@enchant slot:2h") == "Enchant 2H Weapon - Minor Impact | Enchant Weapon - Crusader", "slot:2h: " .. S("@enchant slot:2h"))
		check(S("@enchant slot:1h") == "Enchant Weapon - Crusader", "slot:1h: " .. S("@enchant slot:1h"))
		check(S("@enchant slot:legs") == "Arcanum of Focus | Light Armor Kit", "slot:legs: " .. S("@enchant slot:legs"))
		check(S("@enchant stat:agility") == "Enchant Bracer - Minor Agility", "stat:agility: " .. S("@enchant stat:agility"))
		check(S("@enchant stat:stamina>=3") == "Enchant Bracer - Minor Stamina", "stat:stamina>=3: " .. S("@enchant stat:stamina>=3"))
		check(S("@enchant stat:fire") == "Enchant Cloak - Fire Resistance", "stat:fire (its resistance): " .. S("@enchant stat:fire"))
		check(S("@enchant crusader") == "Enchant Weapon - Crusader" and S("@enchant agility bracers") == "Enchant Bracer - Minor Agility",
			"by name, stat and slot words: " .. S("@enchant agility bracers"))
		check(S("@enchant is:known") == "Enchant Bracer - Minor Agility | Enchant Bracer - Minor Stamina", "is:known: " .. S("@enchant is:known"))

		-- Enter: your recipe's row; known but not read; where to learn it; where to get its item
		local rec
		for _, r in ipairs(ns:GetEntries(ns.providers.recipes)) do if r.recipeID == 7779 then rec = r end end
		check(rec and agi.recipeID == 7779 and agi.activate == rec.activate and agi.isOpen == rec.isOpen and agi.reagents == rec.reagents,
			"one you know opens as its recipe row")
		said = {}
		sta.activate(sta)
		check(said[1] == L["Open a profession's window once: Terminal reads its recipes from it"], "known, its window not read: says so: " .. tostring(said[1]))
		local walked
		UI.WalkTo = function(_, text) walked = text end
		cru.activate(cru)
		check(walked == "Enchant Weapon - Crusader > learn" and cru.staysOpen, "one you don't know: where to learn it: " .. tostring(walked))
		arc.activate(arc)
		check(walked == "Arcanum of Focus > sources", "an arcanum: where to get it: " .. tostring(walked))
		UI.WalkTo = save.walk
		-- the learn chain from an enchant: the profession and skill OneForAll says (no AtlasLoot here)
		local learn = ns.Pipes.Run("learn", { cru })
		check(learn[1] and learn[1].name == L["learn at %s %s"]:format("Enchanting", 300), "learn chain: " .. Names(learn))
		UI.lastScan, UI.lastOverview = nil, nil
		local chained = UI:Search("enchant weapon crusader > learn")
		check(chained[1] and chained[1].name == L["learn at %s %s"]:format("Enchanting", 300), "the chain starts from @enchant: " .. Names(chained))

		-- the questions (search questions: their @enchant lines)
		ns.db.easyMode = true; UI:EasyChanged()
		local Q = ns.Questions
		local function Top(line) local r = Q.Ranked(line) return r[1] and r[1].a.id end
		for _, line in ipairs({ "enchants for bracers", "agility enchants", "enchants i can make", "enchants for my weapon" }) do
			check(Top(line) == "Enchants", line .. ": the enchants' question (" .. tostring(Top(line)) .. ")")
		end
		check(EN.Line(EN.Question("enchants for bracers")) == "@enchant slot:bracers sort:list ", "line: " .. EN.Line(EN.Question("enchants for bracers")))
		local function A(line) UI.lastScan, UI.lastOverview = nil, nil; return Names((Q.Answer(line))) end
		check(A("enchants for bracers") == "Enchant Bracer - Minor Agility | Enchant Bracer - Minor Stamina", "enchants for bracers: " .. A("enchants for bracers"))
		check(A("agility enchants") == "Enchant Bracer - Minor Agility", "agility enchants: " .. A("agility enchants"))
		check(A("enchants i can make") == "Enchant Bracer - Minor Agility | Enchant Bracer - Minor Stamina", "enchants i can make: " .. A("enchants i can make"))
		_G.GetInventoryItemID = function(_, slot) return slot == 16 and 1234 or nil end
		C_Item.GetItemInfoInstant = function(id) if id == 1234 then return 1234, "Weapon", "Staves", "INVTYPE_2HWEAPON" end return save.instant(id) end
		check(A("enchants for my weapon") == "Enchant 2H Weapon - Minor Impact | Enchant Weapon - Crusader", "enchants for my weapon (a staff): " .. A("enchants for my weapon"))
		check(EN.Question("enchants") == nil and EN.Question("bracers") == nil, "\"enchants\" alone is the list's name, not the question")
		ns.db.easyMode = false; UI:EasyChanged()

		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d enchants (@enchant)"]:format(7), 1, true), ".integrations: " .. lines)
		-- without OneForAll: no @enchant, no question
		_G.OneForAll = nil
		Fresh()
		check(not ns.providers.enchant and EN.Question("enchants for bracers") == nil, "without OneForAll: none")
	end)
	_G.OneForAll = save.lib
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.failed, OA.on = save.print, save.failed, save.on
	_G.IsPlayerSpell, _G.GetInventoryItemID, C_Item.GetItemInfoInstant, UI.WalkTo = save.known, save.inv, save.instant, save.walk
	if ns.providers.recipes then ns.providers.recipes._dirty = true end
	-- (its learn link and verbs: gone with it)
	local defs = ns.Pipes.relations.learn or {}
	for i = #defs, 1, -1 do if defs[i].seedAlso and defs[i].seedAlso[1] == "enchant" then table.remove(defs, i) end end
	EN.learnRelation, ns.Easy.VERBS.enchant = nil, nil
	if ns.Easy.ForgetKinds then ns.Easy.ForgetKinds() end
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget()
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall_enchants: " .. tostring(err)) end
end

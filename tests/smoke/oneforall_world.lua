-- OneForAll's world (1.0.4, the player's ask; Providers/Integrations/OneForAll/World.lua): its weapon masters when What's Training
-- and TrainerSpells have none (CS.WeaponMasters), its drop chances on AtlasLoot's rows, the Merchant's Favor recipes
-- (on @recipe's unknown ones since 1.0.12: its cost, your faction's vendor; no @favor) and @transport (boats, zeppelins, the tram, the roads out of a zone); "favor recipes
-- i don't know", "nearest boat", "zeppelin to orgrimmar", "zone exits" in Simple mode; without OneForAll: none.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L = ns.Integrations, ns.OneForAll, ns.L
local W = OA.World

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[oneforall: weapon masters, drop chances, Merchant's Favor recipes, boats and roads]\n")
do
	local KINDS = { "book", "tame", "itemset", "transport" }
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"),
		here = I.Here, spot = I.SpotXY, zone = I.ZoneName, failed = I.failed, on = OA.on, easy = ns.db.easyMode, side = _G.UnitFactionGroup,
		store = ns.Professions.Store, pprofs = ns.Professions.PlayerProfessions, cmap = rawget(_G, "C_Map"), wsapi = ns.ClassSpells.Api, tsw = ns.TrainerSpells.WeaponData }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Said(s) for _, m in ipairs(said) do if m:find(s, 1, true) then return m end end end
	local function Fresh()
		for _, id in ipairs(KINDS) do
			ns.providers[id] = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		end
		I.failed, OA.on = {}, nil
		OA.Forget(); W.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	local lootRow
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		local skip = {}
		for _, k in ipairs(KINDS) do skip[k] = true end
		for _, id in ipairs(save.order) do
			if not skip[id] then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		_G.UnitFactionGroup = function() return "Alliance" end
		I.ZoneName = function(ui) return ({ [1437] = "Wetlands", [1439] = "Darkshore", [1453] = "Stormwind City", [1455] = "Ironforge",
			[1433] = "Redridge Mountains", [1417] = "Arathi Highlands", [1434] = "Stranglethorn Vale" })[ui] end
		-- you know one alchemy recipe, your window listed two you don't; no blacksmithing
		ns.Professions.Store = function() return { [171] = { name = "Alchemy", skillLine = 171, list = { { name = "Elixir of Lesser Spirit" } },
			unknown = { { id = 3171, name = "Lesser Mageblood Elixir" }, { id = 3172, name = "Elixir of Wisdom" } } } } end
		ns.Professions.PlayerProfessions = function() return { { name = "Alchemy", skillLine = 171, rank = 80 } } end
		_G.OneForAll = {
			BOOKS = { { name = "A Book", questId = 1, itemId = 2 } },
			MAP_IDS = { ["Redridge Mountains"] = 1433, ["The Barrens"] = 1413 },
			WEAPON_TRAINERS = {
				{ npc = 11867, name = "Woo Ping", side = "A", map = 1453, x = 63.9, y = 69.1, skills = { 6, 7 } },
				{ npc = 11870, name = "Archibald", side = "H", map = 1458, x = 57.3, y = 32.8, skills = { 6 } },
				{ npc = 11865, name = "Buliwyf Stonehand", side = "A", map = 1455, x = 61.2, y = 89.5, skills = { 13 } },
			},
			WEAPON_SKILL_SPELL = { [6] = 200, [7] = 201, [13] = 15590 },
			DUNGEON_DROP_CHANCE = { ["Blackfathom Deeps"] = { ["Aku'mai"] = { [6909] = 20, [6910] = 0.28, [6911] = 4.8 } } },
			TRADE_HUBS = { Alliance = { name = "Azeroth Commerce Authority", zone = "Redridge Mountains", place = "Three Corners", x = 10.5, y = 72.7 },
				Horde = { name = "Durotar Supply & Logistics", zone = "The Barrens", x = 42, y = 34 } },
			PROFESSION_VENDORS = { { profession = "Alchemy", alliance = "Nina Surefire", ax = 10.8, ay = 72.4, horde = "Apothecary Durelle", hx = 49.8, hy = 29.4 } },
			RECIPE_PREFIX = { Alchemy = "Recipe: ", Blacksmithing = "Plans: " },
			MERCHANT_RECIPES = { { profession = "Alchemy", name = "Elixir of Lesser Spirit", skill = 65, cost = 45 },
				{ profession = "Alchemy", name = "Lesser Mageblood Elixir", skill = 75, cost = 45 },
				{ profession = "Blacksmithing", name = "Guard's Chain Belt", skill = 45, cost = 30 } },
			MAP_LANDMARKS = {
				zeppelin = { { 1434, 31.4, 29.9, "Orgrimmar", "Undercity" } },
				ship = { { 1437, 4.5, 56.6, "A", "Southshore, Hillsbrad Foothills", "Auberdine, Darkshore" },
					{ 1439, 30.5, 40.9, "A", "Stormwind Harbor, Stormwind City" }, { 1434, 25.9, 73.1, "AH", "Ratchet, The Barrens" },
					{ 1413, 63.7, 38.6, "H", "Booty Bay, Stranglethorn Vale" } },
				tram = { { 1453, 66.7, 33.2, "Ironforge" } },
			},
			ZONE_TRANSITIONS = { { "bad", 1, 1, 1417 }, { 1437, 50, 10, 1417 }, { 1417, 20, 30, 1437 }, { 1437, 99, 99, 9999 } },
		}
		I.SpotXY = function(ui, c) return ({ [1437] = 2, [1439] = 1, [1453] = 2, [1434] = 2, [1433] = 2, [1417] = 2 })[ui], c[1] * 10, c[2] * 10 end
		Fresh()
		check(not Said(L["Its Merchant's Favor recipes are unavailable."]) and not Said(L["@transport (its boats, zeppelins and the tram) is unavailable."])
			and not Said(L["Its drop chances are unavailable."]) and not Said(L["Its weapon masters are unavailable."]), "its tables as expected: " .. tostring(said[1]))

		-- weapon masters: OneForAll's, with neither What's Training nor TrainerSpells
		ns.ClassSpells.Api = function() return nil end
		ns.TrainerSpells.WeaponData = function() return nil end
		local set = ns.ClassSpells.WeaponMasters({ 200 })
		check(set and set[11867] and not set[11870] and not set[11865], "polearms: your faction's master, OneForAll's")
		ns.ClassSpells.Api, ns.TrainerSpells.WeaponData = save.wsapi, save.tsw

		-- drop chances
		check(W.DropChance("Blackfathom Deeps", "Aku'mai", 6909) == 20 and W.DropChance("blackfathom deeps", "akumai", 6911) == 4.8
			and W.DropChance("Blackfathom Deeps", "Aku'mai", 1) == nil, "by instance, boss and item, names as written or not")
		check(W.ChanceText(20) == L["%s%% to drop"]:format("20") and W.ChanceText(4.8) == L["%s%% to drop"]:format("4.8")
			and W.ChanceText(0.28) == L["%s%% to drop"]:format("0.28"), "said: " .. W.ChanceText(0.28))
		-- (review, 1.0.13) a loot row's instance, read from its detail, isn't "Blackfathom Deeps  ·  20% to drop"
		local withChance = { kind = "loot", itemID = 6909, detail = "Aku'mai  Blackfathom Deeps" .. ns.DETAIL_SEP .. W.ChanceText(20) }
		check(I.LootDetail(withChance.detail) == "Aku'mai  Blackfathom Deeps", "the detail without its chance: " .. tostring(I.LootDetail(withChance.detail)))
		local boss, inst = ns.Share.LootWhere(withChance)
		check(boss == "Aku'mai" and inst == "Blackfathom Deeps", "sent to chat: where, without the chance: " .. tostring(inst))
		local lp = ns.providers.loot
		if lp then
			lootRow = setmetatable({ key = "test:bfd:6909", itemID = 6909, name = "Strike of the Hydra", detail = "Aku'mai  Blackfathom Deeps" },
				{ __index = function() return nil end })
			table.insert(I.loot.rows, lootRow)
			lp._dirty = true
			ns:GetEntries(lp)
			check((lootRow.detail or ""):find(W.ChanceText(20), 1, true) and rawget(lootRow, "dropChance") == nil, "an AtlasLoot row: its chance after where (no field of its own): " .. tostring(lootRow.detail))
			lp._dirty = true
			ns:GetEntries(lp)
			local _, n = lootRow.detail:gsub("%%", "")
			check(n == 1, "said once, however often the list is made: " .. lootRow.detail)
		end

		-- the Merchant's Favor: on the recipes you don't know, no kind of its own
		check(ns.providers.favor == nil, "no @favor")
		local pm = ns.providers.missing
		pm._dirty = true
		local by = {}
		for _, e in ipairs(ns:GetEntries(pm)) do by[e.name] = e end
		local mb = by["Lesser Mageblood Elixir"]
		check(mb and mb.sources.favor and mb.sources.favor.cost == 45 and mb.sources.favor.vendor == "Nina Surefire",
			"a recipe you don't know that the Favor buys: its cost, your faction's vendor")
		check((mb.detail or ""):find(L["%d Merchant's Favor"]:format(45), 1, true) and mb.need == 75, "said in its detail; the skill it needs: " .. tostring(mb.detail))
		check(by["Elixir of Wisdom"] and not by["Elixir of Wisdom"].sources.favor, "one it doesn't buy: nothing said")
		local lines = {}
		local tip = setmetatable({}, { __index = function(_, k)
			if k == "SetText" or k == "AddLine" then return function(_, s) lines[#lines + 1] = tostring(s) end end
			if k == "AddDoubleLine" then return function(_, a, b) lines[#lines + 1] = tostring(a) .. " = " .. tostring(b) end end
			return function() end
		end })
		mb.tooltip(mb, tip)
		check(table.concat(lines, "\n"):find(L["Sold by %s"]:format("Nina Surefire"), 1, true), "its tooltip: the vendor: " .. table.concat(lines, " / "))
		local res = UI:Search("@recipe is:unknown favor")
		check(#res == 1 and res[1].name == "Lesser Mageblood Elixir", "@recipe is:unknown favor: " .. Names(res))

		-- @transport
		local pt = ns.providers.transport
		check(pt and ns:ResolveProvider("boats") == pt and ns:ResolveProvider("zeppelin") == pt, "@transport, @boats, @zeppelin")
		local tr = ns:GetEntries(pt)
		local tn = {}
		for _, e in ipairs(tr) do tn[e.name] = e end
		check(tn[L["Boat to %s"]:format("Auberdine, Darkshore")] and tn[L["Boat to %s"]:format("Southshore, Hillsbrad Foothills")], "a dock's every destination")
		check(not tn[L["Boat to %s"]:format("Booty Bay, Stranglethorn Vale")] and tn[L["Boat to %s"]:format("Ratchet, The Barrens")], "the Horde's left out; both sides' kept")
		check(not tn[L["Zeppelin to %s"]:format("Undercity")] and tn[L["Tram to %s"]:format("Ironforge")],
			"the zeppelins are the Horde's, left out for the Alliance; the tram is both's")
		for _, e in ipairs(tr) do
			check(e.way == "road" or e.target == nil, "a road not in the shape expected tags no other row: " .. tostring(e.name))
		end
		check(tn[L["Road to %s"]:format("Arathi Highlands")] and tn[L["Road to %s"]:format("Arathi Highlands")].ui == 1437, "a road: into the next zone")
		local roads = 0
		for _, e in ipairs(tr) do if e.way == "road" then roads = roads + 1 end end
		check(roads == 2, "a road into a zone not known: left out: " .. roads)

		-- the questions
		for _, s in ipairs({ "favor recipes", "merchant's favor recipes", "alchemy favor recipes", "favor recipes i don't know",
			"nearest boat", "boat to auberdine", "zeppelin to undercity", "where is the tram", "zone exits", "boats" }) do
			check(W.Question(s) ~= nil, s .. ": the world question")
		end
		for _, s in ipairs({ "tailoring favor recipes", "boat shoes", "my boats are great", "favor recipes i know" }) do
			check(W.Question(s) == nil, s .. ": not it")
		end
		ns.db.easyMode = true; UI:EasyChanged()
		I.Here = function() return { cont = 2, x = 50, y = 560 } end
		UI:Open("favor recipes i don't know"); FlushAll()
		local r = UI.Results()
		check(#r == 1 and r[1].name == "Lesser Mageblood Elixir", "favor recipes i don't know: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("boat to auberdine"); FlushAll()
		r = UI.Results()
		check(#r == 1 and r[1].to == "Auberdine, Darkshore", "boat to auberdine: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("nearest boat"); FlushAll()
		r = UI.Results()
		check(r[1] and r[1].ui == 1437 and (r[1].detail or ""):find("yd", 1, true), "nearest boat: Menethil's, how far: " .. Names(r))
		UI:Hide(); FlushAll()
		_G.C_Map = setmetatable({ GetBestMapForUnit = function() return 1437 end }, { __index = save.cmap })
		UI:Open("zone exits"); FlushAll()
		r = UI.Results()
		check(#r == 1 and r[1].way == "road" and r[1].ui == 1437, "zone exits: the roads out of yours: " .. Names(r))
		UI:Hide(); FlushAll()
		_G.C_Map = save.cmap
		check(W.ToAdvanced(W.Question("favor recipes i don't know")) == "@recipe is:unknown favor ", "to Advanced: " .. W.ToAdvanced(W.Question("favor recipes i don't know")))
		ns.db.easyMode = false; UI:EasyChanged()
		lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find(L["%d Merchant's Favor recipes (on the recipes you don't know)"]:format(3), 1, true) and lines:find(L["drop chances on @loot"], 1, true), ".integrations: " .. lines)

		-- optional tables gone: quiet; MAP_LANDMARKS changed: said
		said = {}
		OneForAll.DUNGEON_DROP_CHANCE, OneForAll.WEAPON_TRAINERS, OneForAll.ZONE_TRANSITIONS = nil, nil, nil
		OneForAll.MAP_LANDMARKS = "moved"
		Fresh()
		check(not Said(L["Its drop chances are unavailable."]) and not Said(L["Its weapon masters are unavailable."]), "optional tables gone: quiet")
		check(Said(L["@transport (its boats, zeppelins and the tram) is unavailable."]) and not ns.providers.transport and W.Question("favor recipes"),
			"landmarks changed: said, no @transport, the Favor's still")
		_G.OneForAll = nil
		Fresh()
		check(not ns.providers.transport and W.Question("favor recipes") == nil and W.DropChance("Blackfathom Deeps", "Aku'mai", 6909) == nil,
			"without OneForAll: none")
	end)
	if lootRow then
		for i = #I.loot.rows, 1, -1 do if I.loot.rows[i] == lootRow then table.remove(I.loot.rows, i) end end
		if ns.providers.loot then ns.providers.loot._dirty = true end
		if save.providers.loot then save.providers.loot._dirty = true end
	end
	_G.OneForAll = save.lib
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.Here, I.SpotXY, I.ZoneName = save.print, save.here, save.spot, save.zone
	I.failed, OA.on, _G.UnitFactionGroup = save.failed, save.on, save.side
	ns.Professions.Store, _G.C_Map, ns.Professions.PlayerProfessions = save.store, save.cmap, save.pprofs
	ns.MissingRecipes.FavorOf = nil
	if ns.providers.missing then ns.providers.missing._dirty = true end
	ns.ClassSpells.Api, ns.TrainerSpells.WeaponData = save.wsapi, save.tsw
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget(); W.Forget()
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall_world: " .. tostring(err)) end
end

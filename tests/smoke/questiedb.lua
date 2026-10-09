-- QuestieDB without Questie: @questie, @npc and the Questie filters read the QuestieDB addon's
-- LibQuestieDB directly (a Blizzard-like UI with Questie's data). With Questie installed, they wait for it.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F = ns.Filters
local I, QD = ns.Integrations, ns.QuestieData

local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end
local function Entity(rows)
	local ids = {}
	for id in pairs(rows) do ids[#ids + 1] = id end
	table.sort(ids)
	return {
		Get = function(id, field) return rows[id] and rows[id][field] end,
		GetAllIds = function() return ids end,
	}
end
local function Fresh()
	I.npc.on, I.npc.list, I.npc.names, I.npc.busy = false, nil, nil, false
	I.qdb.list, I.qdb.names, I.qdb.busy = nil, nil, false
	drop("npc"); drop("questie")
	QD.ResetForTests()
	F.ClearCache()
end

io.write("[QuestieDB without Questie]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, map = _G.C_Map }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.LibQuestieDB = {
		Quest = Entity({
			[176] = { name = "Wanted: \"Hogger\"", questLevel = 11, zoneOrSort = 12, startedBy = { { 240 } },
				objectivesText = { "Kill Hogger and bring his claw to Marshal Dughan." } },
		}),
		Npc = Entity({
			[448] = { name = "Hogger", minLevel = 11, maxLevel = 11, spawns = { [12] = { { 27.5, 85.3 } } }, npcFlags = 0 },
			[240] = { name = "Marshal Dughan", minLevel = 25, maxLevel = 25, spawns = { [12] = { { 42.1, 65.9 } } }, npcFlags = 2 },
			[639] = { name = "Edwin VanCleef", spawns = { [1581] = { { 50, 50 } } } },
		}),
		Item = Entity({ [2320] = { name = "Coarse Thread", vendors = { 240 } } }),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
		Support = { Get = function(name)
			if name ~= "ZoneDB" then return nil end
			return { private = {
				areaIdToUiMapId = "return { [12] = 1429, [40] = 1436, [1581] = 0 }",
				areaIdToUiMapIdOverride = "return { [40] = 1436 }",
				-- The Deadmines: its entrance in Westfall (area 40)
				dungeons = { [1581] = { "The Deadmines", nil, 40, { { 40, 42.6, 71.7 } } } },
			} }
		end },
	}
	Fresh()
	check(QD.Ready() and QD.Source() == "QuestieDB", "QuestieDB alone: its data can be read")
	I.Setup(); FlushAll()
	check(ns.providers.npc and ns.providers.questie, "@npc and @questie are there without Questie")
	check(I.npc.list and #I.npc.list == 3 and I.qdb.list and #I.qdb.list == 1, "NPCs and quests indexed from QuestieDB: "
		.. tostring(I.npc.list and #I.npc.list) .. ", " .. tostring(I.qdb.list and #I.qdb.list))
	do
		local q = I.qdb.list and I.qdb.list[1]
		local raw = 0
		if q then for _ in pairs(q) do raw = raw + 1 end end
		check(q and rawget(q, "qid") == nil and q.qid == q.key and raw <= 7, "a quest row: 7 raw fields at most, qid read from its key: " .. raw)
		if q then
			UI:Search("@questie " .. q.name)
			raw = 0
			for _ in pairs(q) do raw = raw + 1 end
			check(rawget(q, "_nameHit") == nil and raw <= 8, "searched: no _nameHit written on it, 8 fields at most: " .. raw)
		end
	end
	local r = UI:Search("@npc hogger")
	check(r[1] and r[1].name == "Hogger", "@npc hogger finds him: " .. tostring(r[1] and r[1].name))
	r = UI:Search("@questie bring his claw")
	check(r[1] and r[1].qid == 176, "@questie searches the objectives text: " .. tostring(r[1] and r[1].name))
	-- his place on the map, from QuestieDB's zone tables (no Questie ZoneDB)
	local placed
	_G.C_Map = { CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function(pt) placed = pt end, GetUserWaypointHyperlink = function() return "pin" end }
	_G.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
	check(I.NpcPinLink({ npcID = 448, name = "Hogger" }) == "pin" and placed and placed.uiMapID == 1429, "Hogger is pinned in Elwynn (area 12 -> map 1429): " .. tostring(placed and placed.uiMapID))
	placed = nil
	I.NpcPinLink({ npcID = 639, name = "Edwin VanCleef" })
	check(placed and placed.uiMapID == 1436, "inside a dungeon: its entrance in Westfall: " .. tostring(placed and placed.uiMapID))
	-- how far an NPC is (for "nearest"): your place and its spawns in world yards (map % * 1000 here; continent 1)
	C_Map.GetBestMapForUnit = function() return 1429 end
	C_Map.GetPlayerMapPosition = function() return { x = 0.30, y = 0.80 } end
	C_Map.GetWorldPosFromMapPos = function(map, p) return (map == 1429 or map == 1436) and 1 or 2, { x = p.x * 1000, y = p.y * 1000 } end
	local here = I.Here()
	check(here and here.cont == 1 and math.abs(here.x - 300) < 0.01, "where you are, in world yards")
	local dh, dd = I.NpcDistance(448, here), I.NpcDistance(240, here)
	check(dh and math.abs(dh - math.sqrt(25 * 25 + 53 * 53)) < 0.01 and dd and dd > dh,
		"Hogger is closer than Marshal Dughan: " .. tostring(dh) .. " / " .. tostring(dd))
	C_Map.GetPlayerMapPosition = function() return nil end
	check(I.Here() == nil, "no position (an instance): nil")
	-- which way: facing north (0), Hogger (south-west of you on the map) is behind and to the left
	C_Map.GetPlayerMapPosition = function() return { x = 0.30, y = 0.80 } end
	_G.GetPlayerFacing = function() return 0 end
	local ang = I.NpcBearing(448)
	check(ang, "a bearing when facing is known")
	-- the mock's world x grows with the map's x (east here), so check the formula on a made-up spot instead:
	-- world x is north, y is west; a spot due west while facing north is a quarter turn to the left
	local b = I.Bearing({ x = 0, y = 0 }, { x = 0, y = 10 }, 0)
	check(math.abs(b - math.pi / 2) < 1e-6, "due west, facing north: a quarter turn left (counter-clockwise): " .. b)
	b = I.Bearing({ x = 0, y = 0 }, { x = 10, y = 0 }, math.pi / 2)
	check(math.abs(b + math.pi / 2) < 1e-6, "due north, facing west: a quarter turn right: " .. b)
	_G.GetPlayerFacing = function() return nil end
	check(I.NpcBearing(448) == nil, "no facing (an instance): no arrow")
	_G.GetPlayerFacing = nil
	-- the NPC list built at login and never searched since is freed like any unused list; the names text stays
	do
		local p = ns.providers.npc
		local usedWas, entriesWas = p._usedAt, p._entries
		p._entries, p._usedAt = nil, GetTime()
		local namesWas = I.npc.names
		local calls = 0
		local real = _G.LibQuestieDB.Npc.Get
		_G.LibQuestieDB.Npc.Get = function(id, f) if f == "npcFlags" then calls = calls + 1 end return real(id, f) end
		QD.ResetForTests()
		I.NpcField(3498, "npcFlags")
		ns:DropIdle(GetTime() + 601)
		check(I.npc.list == nil and I.npc.names == namesWas, "unused for 10 minutes: the NPC list is freed, its names text kept")
		local before = calls
		I.NpcField(3498, "npcFlags")
		check(calls == before + 1, "and the NPCs' cached fields go with it")
		_G.LibQuestieDB.Npc.Get = real
		QD.ResetForTests()
		local easyWas = ns.db.easyMode
		ns.db.easyMode = false
		UI:Search("@npc jazzik"); FlushAll()
		check(I.npc.list ~= nil and #I.npc.list > 0, "the next @npc search builds it again")
		ns.db.easyMode = easyWas
		p._usedAt = usedWas
	end
	-- the filters
	check(I.NpcField(448, "minLevel") == 11, "NPC fields for lvl: and the like")
	local flags = I.NpcFlagDefs()
	check(flags and flags.QUEST_GIVER == 2, "NPC role flags from QuestieDB's rules for this game (Classic's)")
	local sells = F.Parse("sells:coarse_thread")
	check(sells and sells({ kind = "npc", key = 240 }) and not sells({ kind = "npc", key = 448 }), "sells: reads QuestieDB's vendors")

	-- Questie installed but still starting up: nothing read yet; at its ready, indexed
	Fresh()
	local onReady
	_G.Questie = { API = { isReady = false, RegisterOnReady = function(fn) onReady = fn end } }
	_G.QuestieLoader = { ImportModule = function() return nil end }
	check(not QD.Ready(), "with Questie: wait until it's ready (its corrections go into the same data)")
	I.Setup(); FlushAll()
	check(ns.providers.npc and not I.npc.list and onReady, "registered, not indexed yet")
	_G.Questie.API.isReady = true
	onReady(); FlushAll()
	check(I.npc.list and #I.npc.list == 3, "indexed once Questie is ready, from the same data")

	-- Questie's own flag table: its module is looked up until found (Questie may come later), then kept
	do
		QD.ResetForTests()
		local imports, module = 0, nil
		_G.QuestieLoader = { ImportModule = function(_, name) imports = imports + 1 return name == "QuestieDB" and module or nil end }
		local libFlags = QD.DB().npcFlags
		check(libFlags and libFlags.QUEST_GIVER == 2, "no Questie module yet: QuestieDB's own flags")
		QD.DB()
		check(imports == 2, "a missing module is looked up again on the next read: " .. imports)
		module = { npcFlags = { QUEST_GIVER = 99 } }
		check(QD.DB().npcFlags.QUEST_GIVER == 99, "Questie's flags once its module is there")
		imports = 0
		for _ = 1, 50 do QD.DB() end
		check(imports == 0, "found once: never imported again: " .. imports)
		module.npcFlags = { QUEST_GIVER = 98 }
		check(QD.DB().npcFlags.QUEST_GIVER == 98, "its flag table read from the kept module on every read")
		QD.ResetForTests()
		module = nil
		check(QD.DB().npcFlags.QUEST_GIVER == 2, "reset for tests: the module is looked up afresh")
		_G.QuestieLoader = { ImportModule = function() return nil end }
		QD.ResetForTests()
	end

	-- neither: nothing
	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = nil, nil, nil
	I.Setup(); FlushAll()
	check(not ns.providers.npc and not QD.Ready(), "no QuestieDB, no Questie: no @npc")

	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB, _G.C_Map = save.Q, save.L, save.Lib, save.map
	_G.UiMapPoint = nil
end

io.write("[places by name: vendor ratchet]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, map = _G.C_Map, taxi = _G.C_TaxiMap,
		x = _G.C_MapExplorationInfo, easy = ns.db.easyMode }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.LibQuestieDB = {
		Quest = Entity({
			[865] = { name = "Raptor Horns", questLevel = 19, zoneOrSort = 17, startedBy = { { 3442 } },
				objectivesText = { "Bring 5 Raptor Horns to Sputtervalve in Ratchet." }, finishedBy = { { 3442 } } },
			[60] = { name = "Kobold Candles", questLevel = 7, zoneOrSort = 12,
				objectivesText = { "Bring 8 Large Candles to William Pestle in Goldshire." }, finishedBy = { { 253 } } },
			[61] = { name = "Shipment to Stormwind", questLevel = 7, zoneOrSort = 12,
				objectivesText = { "Take the shipment at the farm to someone at Goldshire... no, an \"at\" with nothing after" } },
		}),
		Npc = Entity({
			[3498] = { name = "Jazzik", npcFlags = 4, zoneID = 17, spawns = { [17] = { { 62.4, 37.6 } } } },     -- vendor, Ratchet
			[3496] = { name = "Fuzruckle", subName = "Banker", npcFlags = 0, zoneID = 17, spawns = { [17] = { { 62.6, 37.4 } } } },  -- banker, Ratchet
			[3489] = { name = "Zargh", npcFlags = 4, zoneID = 17, spawns = { [17] = { { 52.6, 29.8 } } } },      -- vendor, Crossroads
			[3442] = { name = "Sputtervalve", npcFlags = 2, zoneID = 17, spawns = { [17] = { { 62.9, 36.3 } } } },
			[295] = { name = "Innkeeper Farley", npcFlags = 4, zoneID = 12, spawns = { [12] = { { 43.8, 65.8 } } } },
			[3357] = { name = "Makaru", subName = "Mining Trainer", npcFlags = 16, friendlyToFaction = "H", zoneID = 1637, spawns = { [1637] = { { 73.1, 26.1 } } } },
			[3555] = { name = "Johan Focht", subName = "Mining Trainer", npcFlags = 16, friendlyToFaction = "A", zoneID = 1537, spawns = { [1537] = { { 50, 50 } } } },
			[253] = { name = "William Pestle", npcFlags = 4, zoneID = 12, spawns = { [12] = { { 43.3, 65.7 } } } },
			[1650] = { name = "Far Elwynn Vendor", npcFlags = 4, zoneID = 12, spawns = { [12] = { { 80.0, 20.0 } } } },
		}),
		Item = Entity({}),
		Object = Entity({
			[32349] = { name = "Mailbox", spawns = { [17] = { { 62.5, 37.0 }, { 52.0, 30.0 } } } }, -- Ratchet's, the Crossroads'
			[142075] = { name = "Mailbox", spawns = { [12] = { { 42.0, 65.0 } } } },               -- Goldshire's (another continent)
			[31] = { name = "Old Lion Statue", spawns = { [17] = { { 62.4, 37.1 } } } },
		}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
		Support = { Get = function(name)
			if name ~= "ZoneDB" then return nil end
			return { private = {
				-- (QuestieDB lists the parts here too: Goldshire -> Elwynn's map, Ratchet -> the Barrens')
				areaIdToUiMapId = "return { [17] = 1413, [12] = 1429, [87] = 1429, [392] = 1413, [1637] = 1454, [1537] = 1455, [15] = 1445 }",
				subZoneToParentZone = "return { [392] = 17, [380] = 17, [87] = 12 }",
				dungeons = {
					[491] = { "Razorfen Kraul", { 1717 }, 17, { { 17, 42.9, 90.2 } } },
					[2159] = { "Onyxia's Lair", nil, 15, { { 15, 52.6, 76.8 } } },
					[3277] = { "Warsong Gulch", nil, 17, { { 17, 46.5, 8.6 } } },
					[3562] = { "Hellfire Ramparts", nil, 3483, { { 3483, 47.7, 53.6 } } }, -- (no such zone here)
				},
			} }
		end },
	}
	local areas = { [1637] = "Orgrimmar", [1537] = "Ironforge", [17] = "The Barrens", [392] = "Ratchet", [380] = "The Crossroads", [12] = "Elwynn Forest", [87] = "Goldshire" }
	-- world yards: the Barrens is about 10000 yards across (1% = 100 yd); Elwynn elsewhere
	_G.C_Map = {
		GetAreaInfo = function(a) return areas[a] end,
		GetWorldPosFromMapPos = function(map, p) return map == 1413 and 1 or 2, { x = p.x * 10000, y = p.y * 10000 } end, -- (Elwynn 2)
		GetBestMapForUnit = function() return 1413 end,
		GetPlayerMapPosition = function() return { x = 0.60, y = 0.38 } end,
		GetMapInfo = function(ui) return { name = ui == 1413 and "The Barrens" or "Elwynn Forest" } end,
	}
	_G.C_TaxiMap = { GetTaxiNodesForMap = function(ui)
		if ui == 1413 then return { { name = "Ratchet, The Barrens", position = { x = 0.631, y = 0.372 } } } end
		return {}
	end }
	_G.C_MapExplorationInfo = nil
	Fresh()
	I.ResetPlacesForTests()
	I.Setup(); FlushAll()
	local place, rest = I.FindPlace({ "vendor", "ratchet" })
	check(place and place.area == 392 and #rest == 1 and rest[1] == "vendor", "\"ratchet\" is a place (a part of the Barrens)")
	place = I.FindPlace({ "trainer", "the", "crossroads" })
	check(place and place.area == 380, "\"the crossroads\": two words, the leading the too")
	place = I.FindPlace({ "goldshire" })
	check(place and place.area == 87 and place.parent == 12, "Goldshire stays a part of Elwynn though it has a map entry: " .. tostring(place and place.parent))
	place = I.FindPlace({ "barrens" })
	check(place and place.area == 17 and not place.parent, "\"barrens\": the zone")
	check(I.NpcInPlace(3498, I.FindPlace({ "ratchet" })), "Jazzik is in Ratchet (near its flight point)")
	check(not I.NpcInPlace(3489, I.FindPlace({ "ratchet" })), "Zargh (the Crossroads) isn't")
	check(I.NpcInPlace(3489, I.FindPlace({ "barrens" })) and not I.NpcInPlace(295, I.FindPlace({ "barrens" })), "the Barrens: its NPCs, not Elwynn's")
	-- no flight point: the map's explored parts tell
	_G.C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function(ui, p)
		if ui == 1429 and math.abs(p.x - 0.438) < 0.01 then return { 87 } end
		return nil
	end }
	check(I.NpcInPlace(295, I.FindPlace({ "goldshire" })), "Goldshire (no flight point): the explored map says where")
	-- nothing to tell by (no flight point read, that spot not explored): the whole zone counts, not nothing
	local taxi = _G.C_TaxiMap
	_G.C_TaxiMap = { GetTaxiNodesForMap = function() return {} end }
	I.ResetPlacesForTests()
	local cross = I.FindPlace({ "crossroads" })
	check(I.NpcInPlace(3498, cross), "the Crossroads unknown (no flight point, no quest names it, unexplored): the Barrens' NPCs rather than none")
	local rat
	_G.C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function(ui, p)
		if ui == 1413 and p.x > 0.6 then return { 392 } end
		if ui == 1413 then return { 380 } end
	end }
	I.ResetPlacesForTests()
	rat = I.FindPlace({ "ratchet" })
	check(I.NpcInPlace(3498, rat) and not I.NpcInPlace(3489, rat), "Ratchet explored: the map tells them apart")
	_G.C_TaxiMap = taxi
	_G.C_MapExplorationInfo = nil
	I.ResetPlacesForTests()
	-- no flight point, nothing explored: the quests' own words place the towns ("... to William Pestle in Goldshire")
	_G.C_TaxiMap = { GetTaxiNodesForMap = function() return {} end }
	_G.C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return nil end }
	I.ResetPlacesForTests()
	local gold = I.FindPlace({ "goldshire" })
	check(I.NpcInPlace(295, gold) and not I.NpcInPlace(1650, gold), "Goldshire from its quests: Farley in, the far vendor out")
	rat = I.FindPlace({ "ratchet" })
	check(I.NpcInPlace(3498, rat) and not I.NpcInPlace(3489, rat), "Ratchet from its quests: Jazzik in, Zargh (the Crossroads) out")
	_G.C_TaxiMap = taxi
	_G.C_MapExplorationInfo = nil
	I.ResetPlacesForTests()
	-- the small fields filters read per row are asked of QuestieDB once per NPC
	do
		local Npc = _G.LibQuestieDB.Npc
		local real, calls = Npc.Get, 0
		Npc.Get = function(id, f) if f == "npcFlags" then calls = calls + 1 end return real(id, f) end
		QD.ResetForTests(); I.ClearNpcFields()
		I.NpcField(3498, "npcFlags"); I.NpcField(3498, "npcFlags"); I.NpcField(3498, "npcFlags")
		check(calls == 1, "npcFlags read once per NPC: " .. calls)
		Npc.Get = real
		QD.ResetForTests()
	end
	-- before Questie's quests are indexed, a town isn't placed from them (that would read every quest's text
	-- at once): not known yet, and not remembered as unknown
	do
		local list = I.qdb.list
		I.qdb.list = nil
		_G.C_TaxiMap = { GetTaxiNodesForMap = function() return {} end }
		_G.C_MapExplorationInfo = nil
		I.ResetPlacesForTests()
		check(I.TownsPending(), "(towns pending while the quests aren't indexed)")
		local gold2 = I.FindPlace({ "goldshire" })
		I.NpcInPlace(1650, gold2)
		-- a zone doesn't wait on the towns: its answers are kept even while they're pending
		local bar = I.FindPlace({ "barrens" })
		I.PlaceFilter(bar)({ kind = "npc", key = 3498 })
		check(bar.npcs and bar.npcs[3498] ~= nil, "a zone's answers are kept while the towns are still pending")
		I.qdb.list = list
		check(I.NpcInPlace(295, gold2) and not I.NpcInPlace(1650, gold2), "once the quests are in, Goldshire is placed (the miss wasn't kept)")
		_G.C_TaxiMap = taxi
		I.ResetPlacesForTests()
	end
	-- Simple mode: "vendor ratchet" lists the vendors there
	ns.db.easyMode = true
	-- "mining trainer in org": the shorthand names the city, the NPCs' titles say what they are
	UI:Open("mining trainer in org")
	local mr = UI.Results()
	check(mr[1] and mr[1].name == "Makaru" and not mr[2], "mining trainer in org: Makaru (not Ironforge's): " .. tostring(mr[1] and mr[1].name) .. "/" .. tostring(mr[2] and mr[2].name))
	UI:Hide(); FlushAll()
	UI:Open("vendor ratchet")
	local r = UI.Results()
	local names = {}
	for _, e in ipairs(r) do names[#names + 1] = tostring(e.name) end
	local list = table.concat(names, ", ")
	check(list:find("Jazzik", 1, true) and not list:find("Zargh", 1, true) and not list:find("Fuzruckle", 1, true),
		"vendor ratchet: Ratchet's vendors: " .. list)
	-- Advanced: sort:nearest puts Questie's NPCs closest first (with how far), near:<yards> keeps those within reach
	ns.db.easyMode = false
	C_Map.GetPlayerMapPosition = function() return { x = 0.62, y = 0.37 } end -- in Ratchet
	local function List(q)
		local out = {}
		for _, e in ipairs(UI:Search(q)) do out[#out + 1] = tostring(e.name) .. "=" .. tostring(e.detail) end
		return out
	end
	local got = List("@npc sort:nearest is:vendor")
	check(got[1] and got[1]:find("^Jazzik=%d+ yd") and got[2] and got[2]:find("^Zargh=%d+ yd") and got[3] and not got[3]:find(" yd"),
		"sort:nearest: Jazzik (Ratchet) first, then Zargh (the Crossroads), then the rest (another continent): " .. table.concat(got, ", "))
	got = List("@npc is:vendor near:300")
	check(#got >= 1 and table.concat(got, ","):find("Jazzik", 1, true) and not table.concat(got, ","):find("Zargh", 1, true), "near:300: only the NPCs within 300 yards: " .. table.concat(got, ", "))
	-- in:<town> knows the towns too (an NPC's zone says the Barrens, not Ratchet): what Alt+` writes for "vendor ratchet"
	got = List("@npc in:ratchet is:vendor")
	check(table.concat(got, ","):find("Jazzik", 1, true) and not table.concat(got, ","):find("Zargh", 1, true),
		"in:ratchet: Ratchet's vendors, as Simple's vendor ratchet: " .. table.concat(got, ", "))
	got = List("@npc in:barrens is:vendor")
	check(table.concat(got, ","):find("Zargh", 1, true) and table.concat(got, ","):find("Jazzik", 1, true) and not table.concat(got, ","):find("Pestle", 1, true),
		"in:barrens: the zone's vendors, not Elwynn's: " .. table.concat(got, ", "))
	local conv = ns.Easy.ToAdvanced("vendor ratchet")
	check(conv == "in:ratchet is:vendor faction:friendly ", "Alt+` writes vendor ratchet as in:ratchet is:vendor faction:friendly: " .. conv)
	-- a role carries faction:friendly into the conversion: "mining trainer in org" is Makaru, never Ironforge's
	conv = ns.Easy.ToAdvanced("mining trainer in org", "npcs")
	check(conv:find("faction:friendly", 1, true) and conv:find("in:orgrimmar", 1, true), "mining trainer in org -> " .. conv)
	local baseFaction = _G.UnitFactionGroup
	_G.UnitFactionGroup = function() return "Horde" end
	got = List(conv)
	check(table.concat(got, ","):find("Makaru", 1, true) and not table.concat(got, ","):find("Johan", 1, true), "and finds Makaru only: " .. table.concat(got, ", "))
	got = List("@npc mining is:trainer faction:friendly")
	check(not table.concat(got, ","):find("Johan", 1, true), "faction:friendly alone leaves out Ironforge's trainer: " .. table.concat(got, ", "))
	_G.UnitFactionGroup = baseFaction
	C_Map.GetPlayerMapPosition = function() return nil end
	UI:Search("@npc sort:nearest is:vendor")
	check(UI.noPosition, "no position: sort:nearest says so (the footer)")
	C_Map.GetPlayerMapPosition = function() return { x = 0.60, y = 0.38 } end
	-- NPC titles are searched and shown: "mining trainer in org" style
	check(I.npc.list and (function() for _, e in ipairs(I.npc.list) do if e.name == "Fuzruckle" then return e.detail == "Banker" end end end)(), "an NPC's title is its detail (Banker)")
	ns.db.easyMode = true
	-- the arrow on the selected NPC row, turning with you
	_G.GetPlayerFacing = function() return 0 end
	local idx
	for i, e in ipairs(r) do if e.name == "Jazzik" then idx = i end end
	if idx and idx ~= 1 then for _ = 1, idx - 1 do T.key("DOWN") end end
	UI:SelectionChanged()
	check(UI.navArrow and UI.navArrow:IsShown(), "the selected NPC row has an arrow")
	UI:Hide(); FlushAll()
	check(not UI.navArrow:IsShown(), "closed: the arrow goes")
	_G.GetPlayerFacing = nil
	-- "nearest mailbox": QuestieDB's objects, each spawn its own row, closest first, Enter pins it
	do
		local easyWas = ns.db.easyMode
		ns.db.easyMode = true
		I.ResetObjectsForTests(); ns.db.objectIndex = nil
		C_Map.GetPlayerMapPosition = function() return { x = 0.62, y = 0.37 } end -- in Ratchet
		-- QuestieDB's objects not readable yet: nothing kept, asked again later
		local allWas = _G.LibQuestieDB.Object.GetAllIds
		_G.LibQuestieDB.Object.GetAllIds = function() return {} end
		QD.ResetForTests()
		check(#I.ObjectRows("mailbox") == 0 and ns.db.objectIndex == nil, "no objects yet: no index saved")
		_G.LibQuestieDB.Object.GetAllIds = allWas
		QD.ResetForTests(); I.ResetObjectsForTests()
		for _, q in ipairs({ "nearest mailbox", "mailbox nearby" }) do
			UI:Open(q)
			local r = UI.Results()
			check(r[1] and r[1].name == "Mailbox" and r[1].kind == "mailbox" and r[1].detail:find("^%d+ yd") and r[2] and r[2]._dist > r[1]._dist,
				q .. ": the mailboxes on your continent, closest first: " .. tostring(r[1] and r[1].detail) .. " / " .. tostring(r[2] and r[2].detail))
			check(#r == 2, "not another continent's, not other objects: " .. #r)
			UI:Hide(); FlushAll()
		end
		-- a place said stays: only Ratchet's mailbox
		UI:Open("nearest mailbox in ratchet")
		local rr = UI.Results()
		check(#rr == 1 and rr[1].name == "Mailbox" and rr[1].py == 37.0, "nearest mailbox in ratchet: only Ratchet's: " .. #rr)
		UI:Hide(); FlushAll()
		-- rows listed before the scan light up this search's words, not the last search's
		UI.posTokens = { "zzz" }
		UI:Open("nearest mailbox")
		local m1 = UI.Results()[1]
		check(UI.posTokens and UI.posTokens[1] == "mailbox" and m1 and type(m1._pos) == "table" and next(m1._pos) ~= nil,
			"nearest mailbox: the row's letters are lit for this search's words: " .. tostring(UI.posTokens and UI.posTokens[1]))
		UI:Hide(); FlushAll()
		check(ns.Easy.ToAdvanced("nearest mailbox in ratchet"):find("in:", 1, true), "Alt+`: the place stays: " .. ns.Easy.ToAdvanced("nearest mailbox in ratchet"))
		-- Advanced: @mailbox is a list like the others: sort:nearest, near:, in: work on it; Alt+` writes it
		ns.db.easyMode = false
		local function L(q) local t = {} for _, e in ipairs(UI:Search(q)) do t[#t + 1] = tostring(e.name) .. "=" .. tostring(e.detail) end return t end
		local got = L("@mailbox sort:nearest")
		check(got[1] and got[1]:find("yd  The Barrens$"), "sort:nearest keeps a spot row's zone: " .. tostring(got[1]))
		check(#got == 3 and got[1]:find("^Mailbox=%d+ yd") and got[2]:find(" yd") and not got[3]:find(" yd"),
			"@mailbox sort:nearest: this continent's closest first, the other after: " .. table.concat(got, ", "))
		got = L("@mailbox near:300")
		check(#got == 1, "@mailbox near:300: only the one in Ratchet: " .. table.concat(got, ", "))
		got = L("@mailbox in:ratchet")
		check(#got == 1, "@mailbox in:ratchet: the one in Ratchet (by its spot): " .. table.concat(got, ", "))
		got = L("@mailbox in:barrens")
		check(#got == 2, "@mailbox in:barrens: both of the Barrens': " .. table.concat(got, ", "))
		ns.db.easyMode = true
		check(ns.Easy.ToAdvanced("nearest mailbox") == "@mailbox sort:nearest ", "Alt+`: nearest mailbox -> @mailbox sort:nearest: " .. ns.Easy.ToAdvanced("nearest mailbox"))
		check(ns.db.objectIndex and ns.db.objectIndex.key:find("/mailbox$"), "the saved index's key names the kinds looked for: " .. tostring(ns.db.objectIndex and ns.db.objectIndex.key))
		check(ns.db.objectIndex and ns.db.objectIndex.ids.mailbox == "32349,142075", "the mailboxes' ids are kept for next time: " .. tostring(ns.db.objectIndex and ns.db.objectIndex.ids.mailbox))
		-- next session: from the saved index, no pass over every object's name
		I.ResetObjectsForTests()
		local names = 0
		local real = _G.LibQuestieDB.Object.Get
		_G.LibQuestieDB.Object.Get = function(id, f) if f == "name" then names = names + 1 end return real(id, f) end
		QD.ResetForTests()
		UI:Open("nearest mailbox")
		check(names == 0 and UI.Results()[1] and UI.Results()[1].name == "Mailbox", "a new session reads the saved index, no names: " .. names)
		-- the selected mailbox gets the direction arrow, as NPCs do
		_G.GetPlayerFacing = function() return 0 end
		UI:SelectionChanged()
		check(UI.navArrow and UI.navArrow:IsShown(), "the selected mailbox has an arrow pointing to it")
		_G.GetPlayerFacing = nil
		-- Enter: the game opens the map on it, as an entrance's does (0.44.11); Shift+Enter: only the map pin on it
		local placed
		local placeWas = ns.Maps.Place
		ns.Maps.Place = function(e) placed = e return "set" end
		UI:Activate(1)
		check(UI.armedEntry and UI.armedEntry.mapID == 1413 and ns.Secure.armed, "Enter: the game opens the map on the nearest mailbox")
		UI:Disarm()
		UI:Activate(1, { secondary = true })
		check(placed and placed.mapID == 1413 and math.abs(placed.pos.x - 0.625) < 0.001, "Shift+Enter: a waypoint on the nearest mailbox")
		-- sent to chat (right-click, Simple mode): "Nearby mailbox: [pin]"
		C_Map.GetUserWaypointHyperlink = function() return "|Hworldmap:1413|h[pin]|h" end
		local line = ns.Share.Line(UI.Results()[1], ns.Easy.ToAdvanced("nearest mailbox"))
		check(line == "Nearby mailbox: |Hworldmap:1413|h[pin]|h", "a mailbox sent to chat: " .. tostring(line))
		-- instance entrances: @dungeon / @raid, nearest, sent with a pin
		ns.db.easyMode = false
		local function N(q) local t = {} for _, e in ipairs(UI:Search(q)) do t[#t + 1] = tostring(e.name) end return table.concat(t, ",") end
		ns.providers.dungeon._dirty, ns.providers.raid._dirty = true, true
		local dn, rd = N("@dungeon"), N("@raid")
		-- WoW Forever's own entrances (Leatrix Maps' data): its new dungeons, no other expansion's
		check(dn:find("Razorfen Kraul", 1, true) and dn:find("The Drowned City", 1, true) and dn:find("The Hall of Thanes", 1, true)
			and not dn:find("Utgarde", 1, true) and not dn:find("Hellfire", 1, true) and not dn:find("Alterac Valley", 1, true)
			and not dn:find("Onyxia", 1, true), "@dungeon: WoW Forever's dungeons only, its own included: " .. dn)
		check(rd:find("Onyxia's Lair", 1, true) and rd:find("Molten Core", 1, true) and rd:find("Temple of Ahn'Qiraj", 1, true)
			and not rd:find("Karazhan", 1, true) and not rd:find("Razorfen", 1, true), "@raid: the raids, one per instance behind a shared door: " .. rd)
		local brd = UI:Search("@dungeon blackrock depths")
		check(#brd >= 2 and brd[1].detail:find("Blackrock Mountain", 1, true), "Blackrock Depths at both of Blackrock Mountain's doors: " .. tostring(brd[1] and brd[1].detail))
		check(UI:Search("@dungeon deadmines")[1].detail:find("Lv 17%-26"), "the level range shown: " .. UI:Search("@dungeon deadmines")[1].detail)
		check(N("rfk"):find("Razorfen Kraul", 1, true), "a plain search finds an entrance by its shorthand: " .. N("rfk"))
		local rfk = UI:Search("@dungeon rfk")[1]
		check(rfk and rfk.ui == 1413 and rfk.px == 42.9, "its entrance's map spot")
		local m = rfk and ns.Secure.Resolve(rfk.secure, rfk)
		check(m and (m.macro or ""):find("SetMapID(1413)", 1, true), "Enter: the game opens the map on its zone: " .. tostring(m and m.macro))
		check(ns.Share.Line(rfk, "@dungeon rfk") == "Razorfen Kraul entrance |Hworldmap:1413|h[pin]|h", "sent: its name and a pin (rfk says nothing more): " .. tostring(ns.Share.Line(rfk, "@dungeon rfk")))
		check(ns.Share.Line(rfk, "@dungeon sort:nearest") == "Nearby dungeon: Razorfen Kraul entrance |Hworldmap:1413|h[pin]|h", "nearby: " .. tostring(ns.Share.Line(rfk, "@dungeon sort:nearest")))
		ns.db.easyMode = true
		UI:Open("nearest dungeon")
		local r = UI.Results()
		check(r[1] and r[1].name == "Wailing Caverns" and r[1].detail:find("^%d+ yd"), "Simple: nearest dungeon (you stand in the Barrens): " .. tostring(r[1] and r[1].name) .. " " .. tostring(r[1] and r[1].detail))
		check(ns.Easy.ToAdvanced("nearest raid") == "@raid sort:nearest ", "Alt+`: nearest raid -> @raid sort:nearest")
		UI:Hide(); FlushAll()
		C_Map.GetUserWaypointHyperlink = nil
		ns.Maps.Place = placeWas
		_G.LibQuestieDB.Object.Get = real
		QD.ResetForTests()
		UI:Hide(); FlushAll()
		ns.db.easyMode = easyWas
	end
	ns.db.easyMode = save.easy
	Fresh()
	I.ResetPlacesForTests()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB, _G.C_Map = save.Q, save.L, save.Lib, save.map
	_G.C_TaxiMap, _G.C_MapExplorationInfo = save.taxi, save.x
	I.Setup(); FlushAll()
end

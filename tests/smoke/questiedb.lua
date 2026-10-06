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
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
		Support = { Get = function(name)
			if name ~= "ZoneDB" then return nil end
			return { private = {
				-- (QuestieDB lists the parts here too: Goldshire -> Elwynn's map, Ratchet -> the Barrens')
				areaIdToUiMapId = "return { [17] = 1413, [12] = 1429, [87] = 1429, [392] = 1413, [1637] = 1454, [1537] = 1455 }",
				subZoneToParentZone = "return { [392] = 17, [380] = 17, [87] = 12 }",
				dungeons = {},
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
	ns.db.easyMode = save.easy
	Fresh()
	I.ResetPlacesForTests()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB, _G.C_Map = save.Q, save.L, save.Lib, save.map
	_G.C_TaxiMap, _G.C_MapExplorationInfo = save.taxi, save.x
	I.Setup(); FlushAll()
end

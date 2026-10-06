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

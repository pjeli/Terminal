-- (0.51.18, the player's ask) an NPC inside a dungeon: Questie has its spawn under the dungeon's area with no spot in
-- the world ({ -1, -1 }); its row says which dungeon it's in, and how far and which way are its entrance's.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, QD, L = ns.Integrations, ns.QuestieData, ns.L

io.write("[dungeonnpc: an NPC in a dungeon points at its entrance]\n")
do
	local save = { db = QD.DB, ui = QD.UiMapOfArea, dl = QD.DungeonLocation, map = _G.C_Map }
	local SPAWNS = {
		[639] = { [1581] = { { -1, -1 } } }, -- Edwin VanCleef: the Deadmines
		[448] = { [12] = { { 27.5, 85.3 } } }, -- Hogger: Elwynn
		[700] = { [1581] = { { -1, -1 } }, [12] = { { 10, 10 } } }, -- in the dungeon and out in the world
	}
	local DB = { QueryNPCSingle = function(id, field) if field == "spawns" then return SPAWNS[id] end end }
	QD.DB = function() return DB end
	QD.UiMapOfArea = function(area) if area == 12 then return 1429 elseif area == 40 then return 1436 end end
	QD.DungeonLocation = function(area) if area == 1581 then return { { 40, 42.5, 71.7 } } end end
	-- (both maps on one continent, map % -> yards * 1000; you in Westfall at 40%, 70%)
	_G.C_Map = {
		GetBestMapForUnit = function() return 1436 end,
		GetPlayerMapPosition = function() return { x = 0.40, y = 0.70 } end,
		GetWorldPosFromMapPos = function(map, p) return 1, { x = p.x * 1000 + (map == 1429 and 5000 or 0), y = p.y * 1000 } end,
		GetAreaInfo = function(area) if area == 1581 then return "The Deadmines" end end,
	}
	I._.ResetDistances()

	check(I.NpcDungeon(639) == "The Deadmines", "an NPC only in a dungeon: which dungeon: " .. tostring(I.NpcDungeon(639)))
	check(I.NpcDungeon(448) == nil and I.NpcDungeon(700) == nil, "one out in the world (too): not said to be in a dungeon")
	local here = I.Here()
	local d, w = I.NpcDistance(639, here)
	check(d and math.abs(d - math.sqrt(25 ^ 2 + 17 ^ 2)) < 0.01 and w and w.cont == 1,
		"how far: its entrance's (Westfall 42.5, 71.7): " .. tostring(d))
	local ui, pos, door = I._.NpcLocation(639)
	check(ui == 1436 and pos and math.abs(pos.x - 0.425) < 1e-6 and math.abs(pos.y - 0.717) < 1e-6 and door,
		"Enter's map: the entrance, said to be one: " .. tostring(ui))
	-- the row: "nearest" says how far, then which dungeon
	local view = UI._Scan.NearView({ kind = "npc", name = "Edwin VanCleef", sub = "Defias Kingpin", inDungeon = "The Deadmines" }, d)
	check(view.detail == "30 yd  Defias Kingpin" .. ns.DETAIL_SEP .. L["in %s"]:format("The Deadmines"),
		"a nearest row: how far (its entrance), what it is, the dungeon: " .. view.detail)

	-- (review, 0.51.25) two entrances: Enter goes to the one the row measures (the nearer), not the first listed
	QD.DungeonLocation = function(area) if area == 1581 then return { { 12, 10, 10 }, { 40, 42.5, 71.7 } } end end
	I._.ResetDistances()
	local ui2, pos2, door2 = I._.NpcLocation(639)
	check(ui2 == 1436 and pos2 and math.abs(pos2.x - 0.425) < 1e-6 and door2, "two entrances: Enter's the nearer one: " .. tostring(ui2))

	QD.DB, QD.UiMapOfArea, QD.DungeonLocation, _G.C_Map = save.db, save.ui, save.dl, save.map
	I._.ResetDistances()
end

local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local SpotXY, ZoneName, PinObject = I.SpotXY, I.ZoneName, I.PinObject

-- Dungeon and raid entrances (@dungeon, @raid): one row per instance (a wing of its own: Dire Maul's, Blackrock Spire's),
-- at the nearer door of two (Blackrock Mountain has two: Searing Gorge and Burning Steppes). Enter: the game opens the map on
-- the entrance's zone, then Terminal pins it (a C API); Shift+Enter only pins; ">>" and the right-click menu send it with a
-- map pin.
local EntranceAfter = I.SpotAfter -- (its pinName: "<name> entrance")
local Safe, Num = ns.Safe, ns.Num

-- WoW Forever's instances (docs/DATA_SOURCES.md): { the game's map ID, name, raid, its Group Finder activities, the area
-- Questie's dungeon list keeps it under, the zones its door is in (uiMap), note }. Which instances there are, and in which
-- zone, is Terminal's own list; the rest is read:
--   - the doors from Questie (its ZoneDB) or QuestieDB at run time (QD.DungeonLocation), where they stand on this
--     client's maps; without either, the spot the game sends your ghost to beside the entrance (I.RUNBACK, its Map table),
--     where that spot is in the instance's own zone;
--   - the levels from the game's Group Finder (C_LFGList.GetActivityInfoTable: its minimum and suggested maximum), else
--     the same numbers as this build carried them (I.ACTIVITY_LEVELS, its GroupFinderActivity table).
-- An instance with no door to show yet (no Questie, no ghost spot) is still listed here, so its name is known (questions,
-- lockouts, the quest log's headers), but gets no row.
I.INSTANCES = {
	{ 2959, "City of Dalaran", false, { 1983 }, 16544, { 1416 } },
	{ 70, "Uldaman", false, { 807 }, 1337, { 1418 } },
	{ 189, "Scarlet Monastery", false, { 805, 827, 828, 829 }, 796, { 1420 } },
	{ 33, "Shadowfang Keep", false, { 800 }, 209, { 1421 } },
	{ 289, "Scholomance", false, { 797 }, 2057, { 1422 } },
	{ 329, "Stratholme", false, { 816, 1603 }, 2017, { 1423 } },
	{ 533, "Naxxramas", true, { 841 }, 3456, { 1423 } },
	{ 90, "Gnomeregan", false, { 803 }, 721, { 1426 } },
	{ 309, "Zul'Gurub", true, { 836 }, 1977, { 1434 } },
	{ 109, "Temple of Atal'Hakkar", false, { 810 }, 1477, { 1435 } },
	{ 36, "The Deadmines", false, { 799 }, 1581, { 1436 } },
	{ 2998, "Excavation Site: Wetlands", false, { 1981 }, 16732, { 1437 } },
	{ 34, "The Stockade", false, { 802 }, 717, { 1453 } },
	{ 3065, "The Hall of Thanes", false, { 1984 }, 16919, { 1455 } },
	{ 2999, "The Ruins of Lordaeron", false, { 1982 }, 16611, { 1458 } },
	{ 43, "Wailing Caverns", false, { 796 }, 718, { 1413 } },
	{ 47, "Razorfen Kraul", false, { 804 }, 491, { 1413 } },
	{ 129, "Razorfen Downs", false, { 806 }, 722, { 1413 } },
	{ 48, "Blackfathom Deeps", false, { 801 }, 719, { 1440 } },
	{ 349, "Maraudon", false, { 809 }, 2100, { 1443 } },
	{ 429, "Dire Maul (North)", false, { 815 }, 10022, { 1444 } },
	{ 429, "Dire Maul (West)", false, { 814 }, 10023, { 1444 } },
	{ 429, "Dire Maul (East)", false, { 813 }, 10026, { 1444 } },
	{ 249, "Onyxia's Lair", true, { 838 }, 2159, { 1445 } },
	{ 209, "Zul'Farrak", false, { 808 }, 1176, { 1446 } },
	{ 509, "Ruins of Ahn'Qiraj", true, { 842 }, 3429, { 1451 } },
	{ 531, "Temple of Ahn'Qiraj", true, { 843 }, 3428, { 1451 } },
	{ 389, "Ragefire Chasm", false, { 798 }, 2437, { 1454 } },
	{ 230, "Blackrock Depths", false, { 811 }, 1584, { 1427, 1428 }, L["Blackrock Mountain"] },
	{ 229, "Lower Blackrock Spire", false, { 812 }, 1583, { 1427, 1428 }, L["Blackrock Mountain"] },
	{ 229, "Upper Blackrock Spire", false, { 837 }, 1583, { 1427, 1428 }, L["Blackrock Mountain"] },
	{ 409, "Molten Core", true, { 839 }, 2717, { 1427, 1428 }, L["Blackrock Mountain"] },
	{ 469, "Blackwing Lair", true, { 840 }, 2677, { 1427, 1428 }, L["Blackrock Mountain"] },
}

-- generated: tests/gen_data.py instances (do not edit by hand)
I.ACTIVITY_LEVELS = {
	[796] = { 15, 24 }, -- Wailing Caverns
	[797] = { 58, 60 }, -- Scholomance
	[798] = { 13, 18 }, -- Ragefire Chasm
	[799] = { 17, 26 }, -- Deadmines
	[800] = { 20, 30 }, -- Shadowfang Keep
	[801] = { 24, 32 }, -- Blackfathom Deeps
	[802] = { 24, 32 }, -- Stormwind Stockades
	[803] = { 29, 38 }, -- Gnomeregan
	[804] = { 29, 38 }, -- Razorfen Kraul
	[805] = { 30, 38 }, -- Scarlet Monastery - Graveyard
	[806] = { 37, 46 }, -- Razorfen Downs
	[807] = { 41, 51 }, -- Uldaman
	[808] = { 44, 54 }, -- Zul'Farrak
	[809] = { 46, 55 }, -- Maraudon
	[810] = { 50, 60 }, -- Sunken Temple
	[811] = { 52, 60 }, -- Blackrock Depths
	[812] = { 55, 60 }, -- Lower Blackrock Spire
	[813] = { 54, 60 }, -- Dire Maul (East)
	[814] = { 56, 60 }, -- Dire Maul (West)
	[815] = { 56, 60 }, -- Dire Maul (North)
	[816] = { 58, 60 }, -- Stratholme (Main Gate)
	[827] = { 36, 44 }, -- Scarlet Monastery - Armory
	[828] = { 38, 46 }, -- Scarlet Monastery - Cathedral
	[829] = { 33, 41 }, -- Scarlet Monastery - Library
	[836] = { 60, 60 }, -- Zul'Gurub
	[837] = { 59, 60 }, -- Upper Blackrock Spire
	[838] = { 60, 60 }, -- Onyxia's Lair
	[839] = { 60, 60 }, -- Molten Core
	[840] = { 60, 60 }, -- Blackwing Lair
	[841] = { 60, 60 }, -- Naxxramas
	[842] = { 60, 60 }, -- Ahn'Qiraj Ruins
	[843] = { 60, 60 }, -- Ahn'Qiraj Temple
	[1603] = { 58, 60 }, -- Stratholme (Service Gate)
	[1981] = { 26, 33 }, -- Excavation Site: Wetlands
	[1982] = { 15, 22 }, -- Ruins of Lordaeron
	[1983] = { 28, 35 }, -- City of Dalaran
	[1984] = { 13, 20 }, -- Hall of Thanes
}
I.RUNBACK = {
	[33] = { 1421, 44.7, 67.8 }, -- Shadowfang Keep
	[34] = { 1453, 50.4, 66.2 }, -- Stormwind Stockade
	[36] = { 1436, 38.2, 77.5 }, -- Deadmines
	[43] = { 1413, 47.7, 35.0 }, -- Wailing Caverns
	[47] = { 1413, 42.3, 89.9 }, -- Razorfen Kraul
	[48] = { 1440, 16.5, 11.0 }, -- Blackfathom Deeps
	[70] = { 1418, 35.2, 10.3 }, -- Uldaman
	[90] = { 1426, 17.7, 39.2 }, -- Gnomeregan
	[109] = { 1435, 77.3, 35.9 }, -- Sunken Temple
	[129] = { 1413, 50.9, 92.9 }, -- Razorfen Downs
	[189] = { 1420, 85.1, 31.4 }, -- Scarlet Monastery
	[209] = { 1446, 38.7, 19.9 }, -- Zul'Farrak
	[229] = { 1427, 40.8, 95.6 }, -- Blackrock Spire
	[230] = { 1427, 27.1, 72.5 }, -- Blackrock Depths
	[249] = { 1445, 52.9, 77.7 }, -- Onyxia's Lair
	[289] = { 1422, 69.1, 73.0 }, -- Scholomance
	[309] = { 1434, 54.0, 17.6 }, -- Zul'Gurub
	[329] = { 1423, 26.1, 10.4 }, -- Stratholme
	[349] = { 1443, 29.1, 62.9 }, -- Maraudon
	[389] = { 1454, 53.0, 48.9 }, -- Ragefire Chasm
	[409] = { 1427, 32.0, 94.8 }, -- Molten Core
	[429] = { 1444, 62.0, 33.3 }, -- Dire Maul
	[469] = { 1428, 32.5, 32.4 }, -- Blackwing Lair
	[509] = { 1451, 29.0, 92.8 }, -- Ruins of Ahn'Qiraj
	[531] = { 1451, 29.0, 92.7 }, -- Ahn'Qiraj Temple
}
-- end of generated: instances

--- An instance's levels: the lowest minimum and the highest suggested maximum of its Group Finder activities, as the
--- game says them now (else as this build carried them), or nil.
local function Levels(acts)
	local lo, hi
	local C = _G.C_LFGList
	for _, id in ipairs(acts) do
		local info = C and C.GetActivityInfoTable and Safe(C.GetActivityInfoTable, id)
		local a, b
		if type(info) == "table" then a, b = Num(info.minLevel), Num(info.maxLevelSuggestion) end
		if not (a and b and a > 0 and b >= a) then
			local g = I.ACTIVITY_LEVELS[id]
			a, b = g and g[1], g and g[2]
		end
		if a and b then lo, hi = math.min(lo or a, a), math.max(hi or b, b) end
	end
	return lo, hi
end

--- An instance's doors: { { uiMap, x %, y % } }: Questie's (or QuestieDB's), else the spot beside it the game sends
--- your ghost to, else none.
local function Doors(inst)
	local out = {}
	local QD = ns.QuestieData
	local locs = QD and QD.DungeonLocation and QD.DungeonLocation(inst[5])
	for _, loc in ipairs(type(locs) == "table" and locs or {}) do
		local ui = type(loc) == "table" and QD.UiMapOfArea(loc[1])
		local x, y = ui and Num(loc[2]), ui and Num(loc[3])
		if ui and x and y then out[#out + 1] = { ui, x, y } end
	end
	if #out == 0 and I.RUNBACK[inst[1]] then out[1] = I.RUNBACK[inst[1]] end
	return out
end

-- The entrances: { name, uiMap, x %, y %, raid, min level, max level, note }, one per door (an instance with none yet:
-- one with no map). Made again from I.INSTANCES whenever the rows are (EntranceRows) and once Questie's data is in; the
-- table itself stays the same (other files keep it).
I.ENTRANCES = {}
function I.BuildEntrances()
	local list = I.ENTRANCES
	for i = #list, 1, -1 do list[i] = nil end
	for _, inst in ipairs(I.INSTANCES) do
		local lo, hi = Levels(inst[4])
		local doors = Doors(inst)
		for _, d in ipairs(doors) do list[#list + 1] = { inst[2], d[1], d[2], d[3], inst[3], lo, hi, inst[7] } end
		if #doors == 0 then list[#list + 1] = { inst[2], nil, nil, nil, inst[3], lo, hi, inst[7] } end
	end
	return list
end
I.BuildEntrances()
if ns.QuestieData and ns.QuestieData.OnReady then
	ns.QuestieData.OnReady(function()
		I.BuildEntrances()
		ns:Changed("dungeon"); ns:Changed("raid")
	end)
end

--- The rows: one per instance (and per door with a note of its own: Dire Maul's Hidden Reach). An instance behind two
--- doors (Blackrock Mountain's, from Searing Gorge and from Burning Steppes) is one row at the nearer door (0.53.3, the
--- player: Molten Core and Blackwing Lair were each listed twice); the lists are made again as you change zones.
function I.EntranceRows(raids)
	local rows = {}
	local count, doors, order = {}, {}, {}
	for _, d in ipairs(I.BuildEntrances()) do
		if d[5] == raids and d[2] then
			local id = d[1] .. "\0" .. (d[8] or "")
			if not doors[id] then doors[id] = {}; order[#order + 1] = id end
			table.insert(doors[id], d)
		end
	end
	local here = I.Here and I.Here()
	for _, id in ipairs(order) do
		local d, best = doors[id][1], nil
		for _, door in ipairs(doors[id]) do
			local cont, x, y = SpotXY(door[2], { door[3], door[4] })
			if here and cont == here.cont then
				local dx, dy = x - here.x, y - here.y
				local yards = dx * dx + dy * dy
				if not best or yards < best then d, best = door, yards end
			end
		end
		local name, ui, px, py, lo, hi, note = d[1], d[2], d[3], d[4], d[6], d[7], d[8]
		count[name] = (count[name] or 0) + 1
		local cont, x, y = SpotXY(ui, { px, py })
		local zone = ZoneName(ui)
		local lv = lo and (lo == hi and L["Lv %d"]:format(lo) or L["Lv %d-%d"]:format(lo, hi)) or nil
		local parts = { raids and L["Raid"] or L["Dungeon"] }
		if lv then parts[#parts + 1] = lv end
		if note then parts[#parts + 1] = note end
		if zone then parts[#parts + 1] = zone end
		rows[#rows + 1] = {
			name = name, key = name .. "-" .. count[name], icon = raids and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_03",
			detail = table.concat(parts, ns.DETAIL_SEP), zone = zone, level = hi, minLevel = lo,
			text = (raids and "raid entrance " or "dungeon instance entrance ") .. (note and (note .. " ") or "") .. (zone or ""),
			ui = ui, mapID = ui, px = px, py = py, wcont = cont, wx = x, wy = y,
			pinName = L["%s entrance"]:format(name), what = raids and L["raid"] or L["dungeon"],
			secure = ns.Maps.SECURE, isOpen = ns.Maps.IsOpenFor, after = EntranceAfter, activate = PinObject,
			secondary = PinObject,
		}
	end
	table.sort(rows, function(a, b) return a.name < b.name or (a.name == b.name and a.key < b.key) end)
	return rows
end

-- @dungeon / @raid: instance entrances (I.ENTRANCES: with Questie or QuestieDB, else beside each where the game has a spot)
ns:RegisterProvider("dungeon", {
	label = L["Dungeon"], color = "ff8fc0ff", aliases = { "dungeon", "dungeons", "instance", "instances" }, lazy = true,
	events = { "ZONE_CHANGED_NEW_AREA" }, -- (the nearer door of two: EntranceRows)
	collect = function() return I.EntranceRows(false) end,
})
ns:RegisterProvider("raid", {
	label = L["Raid"], color = "ffff9f6f", aliases = { "raid", "raids" }, lazy = true,
	events = { "ZONE_CHANGED_NEW_AREA" },
	collect = function() return I.EntranceRows(true) end,
})

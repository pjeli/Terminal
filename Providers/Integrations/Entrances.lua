local ns = select(2, ...)
local I = ns.Integrations
local SpotXY, ZoneName, PinObject = I.SpotXY, I.ZoneName, I.PinObject

-- Dungeon and raid entrances (@dungeon, @raid): QuestieDB's dungeon list, one row per entrance (Blackrock Depths has
-- two: Searing Gorge and Burning Steppes). Enter: the game opens the map on the entrance's zone, then Terminal pins
-- it (a C API); Shift+Enter only pins; ">>" and the right-click menu send it with a map pin. Raids by name (English, as
-- QuestieDB names them); battlegrounds and the non-instances in that list are left out.
local EntranceAfter = I.SpotAfter -- (its pinName: "<name> entrance")
-- Instance entrances on WoW Forever's maps: { name, uiMap, x%, y%, raid, min level, max level, note }. From Leatrix
-- Maps' world map icons (Leatrix_Maps_Icons.lua, its WoW Forever data), which are right for this client: QuestieDB's
-- dungeon list holds every expansion's (Utgarde Keep, Hellfire Ramparts...) and lacks Forever's own (The Drowned
-- City, the Hall of Thanes...). Blackrock Mountain and Ahn'Qiraj are listed once per instance behind the door.
local BRM = { { 1427, 34.8, 85.3, "Searing Gorge" }, { 1428, 29.4, 38.3, "Burning Steppes" } }
I.ENTRANCES = {
	{ "City of Dalaran", 1416, 8.5, 59.3, false, 28, 33 },
	{ "Uldaman", 1418, 44.6, 12.1, false, 41, 51 },
	{ "Scarlet Monastery", 1420, 82.6, 33.8, false, 34, 45 },
	{ "Shadowfang Keep", 1421, 44.8, 67.8, false, 22, 30 },
	{ "Scholomance", 1422, 69.7, 73.2, false, 58, 60 },
	{ "Stratholme (Main Gate)", 1423, 27.8, 11.6, false, 58, 60 },
	{ "Stratholme (Service Gate)", 1423, 43.6, 19.5, false, 58, 60 },
	{ "Naxxramas", 1423, 33.7, 20.7, true, 60, 60 },
	{ "Gnomeregan", 1426, 24.3, 39.8, false, 29, 38 },
	{ "Zul'Gurub", 1434, 53.9, 17.6, true, 60, 60 },
	{ "The Drowned City", 1434, 21.3, 27.8, false, 35, 40 },
	{ "Temple of Atal'Hakkar", 1435, 69.9, 53.6, false, 50, 60 },
	{ "The Deadmines", 1436, 42.5, 71.7, false, 17, 26 },
	{ "Excavation Site: Wetlands", 1437, 47.8, 56.2, false, 24, 29 },
	{ "The Stockade", 1453, 52.4, 70.0, false, 22, 30 },
	{ "The Hall of Thanes", 1455, 27.7, 47.9, false, 13, 18 },
	{ "The Ruins of Lordaeron", 1458, 72.5, 11.4, false, 15, 20 },
	{ "Wailing Caverns", 1413, 46.0, 36.4, false, 17, 24 },
	{ "Razorfen Kraul", 1413, 42.9, 90.2, false, 29, 38 },
	{ "Razorfen Downs", 1413, 49.0, 93.9, false, 37, 46 },
	{ "Blackfathom Deeps", 1440, 14.5, 14.2, false, 24, 32 },
	{ "Maraudon", 1443, 29.1, 62.5, false, 46, 55 },
	{ "Dire Maul (North)", 1444, 62.5, 24.9, false, 56, 60 },
	{ "Dire Maul (West)", 1444, 60.3, 30.2, false, 56, 60 },
	{ "Dire Maul (East)", 1444, 64.8, 30.2, false, 56, 60 },
	{ "Dire Maul (East)", 1444, 77.1, 36.9, false, 56, 60, "The Hidden Reach (needs the Crescent Key)" },
	{ "Onyxia's Lair", 1445, 52.6, 76.8, true, 60, 60 },
	{ "Zul'Farrak", 1446, 38.7, 20.0, false, 44, 54 },
	{ "Ruins of Ahn'Qiraj", 1451, 28.6, 92.4, true, 60, 60 },
	{ "Temple of Ahn'Qiraj", 1451, 28.6, 92.4, true, 60, 60 },
	{ "Ragefire Chasm", 1454, 52.6, 49.0, false, 13, 18 },
}
for _, b in ipairs(BRM) do
	for _, d in ipairs({ { "Blackrock Depths", false }, { "Lower Blackrock Spire", false }, { "Upper Blackrock Spire", false },
		{ "Molten Core", true }, { "Blackwing Lair", true } }) do
		I.ENTRANCES[#I.ENTRANCES + 1] = { d[1], b[1], b[2], b[3], d[2], d[2] and 60 or 52, 60, "Blackrock Mountain" }
	end
end

function I.EntranceRows(raids)
	local rows = {}
	local count = {}
	for _, d in ipairs(I.ENTRANCES) do
		local name, ui, px, py, isRaid, lo, hi, note = d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8]
		if isRaid == raids then
			count[name] = (count[name] or 0) + 1
			local cont, x, y = SpotXY(ui, { px, py })
			local zone = ZoneName(ui)
			local lv = lo and (lo == hi and ("Lv " .. lo) or ("Lv " .. lo .. "-" .. hi)) or nil
			local parts = { raids and "Raid" or "Dungeon" }
			if lv then parts[#parts + 1] = lv end
			if note then parts[#parts + 1] = note end
			if zone then parts[#parts + 1] = zone end
			rows[#rows + 1] = {
				name = name, key = name .. "-" .. count[name], icon = raids and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_03",
				detail = table.concat(parts, "  "), zone = zone, level = hi, minLevel = lo,
				text = (raids and "raid entrance " or "dungeon instance entrance ") .. (note and (note .. " ") or "") .. (zone or ""),
				ui = ui, mapID = ui, px = px, py = py, wcont = cont, wx = x, wy = y,
				pinName = name .. " entrance", what = raids and "raid" or "dungeon",
				secure = ns.Maps.SECURE, isOpen = ns.Maps.IsOpenFor, after = EntranceAfter, activate = PinObject,
				secondary = PinObject,
			}
		end
	end
	table.sort(rows, function(a, b) return a.name < b.name or (a.name == b.name and a.key < b.key) end)
	return rows
end

-- @dungeon / @raid: instance entrances (I.ENTRANCES, WoW Forever's own; no Questie needed)
ns:RegisterProvider("dungeon", {
	label = "Dungeon", color = "ff8fc0ff", aliases = { "dungeon", "dungeons", "instance", "instances" }, lazy = true,
	collect = function() return I.EntranceRows(false) end,
})
ns:RegisterProvider("raid", {
	label = "Raid", color = "ffff9f6f", aliases = { "raid", "raids" }, lazy = true,
	collect = function() return I.EntranceRows(true) end,
})

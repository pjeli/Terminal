local ns = select(2, ...)
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local QD = ns.QuestieData
local function QDB() return QD.DB() end
local AddOnVersion, WaypointLink = I._.AddOnVersion, I._.WaypointLink
local SpotXY, ZoneName = I.SpotXY, I.ZoneName

----------------------------------------------------------------------
-- Game objects found by what they are: "nearest mailbox" (QuestieDB's objects: name, spawns)
----------------------------------------------------------------------

-- words -> the object's name, lowercase (every object of that exact name counts)
I.OBJECT_KINDS = { mailbox = "mailbox", mailboxes = "mailbox", mail = "mailbox", post = "mailbox" }
I.OBJECTS_NEAR = 8 -- (the nearest this many are listed)

-- instance entrances: their own lists (@dungeon, @raid), not QuestieDB objects
I.ENTRANCE_KINDS = { dungeon = "dungeon", dungeons = "dungeon", instance = "dungeon", instances = "dungeon", raid = "raid", raids = "raid" }
--- The kind of thing the search words name ("mailbox", "dungeon"), or nil. Only when that's all they name.
function I.ObjectKind(tokens)
	if not tokens or #tokens ~= 1 then return nil end
	return I.OBJECT_KINDS[tokens[1]] or I.ENTRANCE_KINDS[tokens[1]]
end

-- the object ids of each kind: one pass over QuestieDB's objects (13k names) the first time, kept in the saved
-- variables until QuestieDB changes (`db.objectIndex = { key, ids = { mailbox = "1,2,3" } }`)
local objectIds

--- The saved index's ids into out (kind -> list of ids).
local function SavedObjectIds(out, saved)
	for k, list in pairs(saved.ids) do
		local t = {}
		for id in tostring(list):gmatch("%d+") do t[#t + 1] = tonumber(id) end
		out[k] = t
	end
end

--- Every object's name read once (all = QuestieDB's object ids): the ids of each kind looked for go into out,
--- and the index is saved under key.
local function ReadObjectIds(out, DB, all, kinds, key)
	local want = {}
	for name in pairs(kinds) do want[name] = true; out[name] = {} end
	local t0 = debugprofilestop and debugprofilestop()
	for _, id in ipairs(all) do
		local name = ns.Str(Safe(DB.QueryObjectSingle, id, "name")) -- (Util.lua: a string, not secret; "" names no kind)
		if name then
			local l = ns.Lower(name)
			if want[l] then local t = out[l]; t[#t + 1] = id end
		end
	end
	local ids = {}
	for k, t in pairs(out) do ids[k] = table.concat(t, ",") end
	if ns.db then ns.db.objectIndex = { key = key, ids = ids } end
	ns:Trace(("objects: %d read for their names%s"):format(#all, t0 and (", %.0f ms"):format(debugprofilestop() - t0) or ""))
end

local function ObjectIds(kind)
	local DB = QDB()
	if not (DB and DB.QueryObjectSingle and DB.ObjectIds) then return nil end
	if not objectIds then
		local all = DB.ObjectIds() or {}
		if #all == 0 then return nil end -- (not readable yet: asked again next time, nothing kept)
		-- (the kinds looked for are in the key: a kind added later reads every name again)
		local kinds = {}
		for _, name in pairs(I.OBJECT_KINDS) do kinds[name] = true end
		local names = {}
		for name in pairs(kinds) do names[#names + 1] = name end
		table.sort(names)
		local key = AddOnVersion("QuestieDB") .. "/" .. #all .. "/" .. table.concat(names, ",")
		local saved = ns.db and ns.db.objectIndex
		objectIds = {}
		if type(saved) == "table" and saved.key == key and type(saved.ids) == "table" then
			SavedObjectIds(objectIds, saved)
		else
			ReadObjectIds(objectIds, DB, all, kinds, key)
		end
	end
	return objectIds[kind]
end
I.ResetObjectsForTests = function() objectIds = nil end

-- Shift+Enter on a spot row (a mailbox, an entrance, a vein): the map pin on it (a C API), no map opened; also Enter's
-- fallback when the game can't be handed the press (combat)
local function PinObject(e)
	local M = ns.Maps
	local pin = M and M.Place and M.Place({ name = e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } })
	if pin then
		ns:Print(M.PinLine(pin, e.pinName or e.name, e.zone))
	else
		ns:Print("Can't set a waypoint there.")
	end
end
I.PinObject = PinObject

--- After the game opened the map on a spot row's zone (Maps.SECURE): the pin on the spot, pointed at.
function I.SpotAfter(e)
	ns.Maps.ShowAfter({ name = e.pinName or e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } })
end

-- what every mailbox row does (shared, not on each of thousands of rows): Enter opens the map on it with the pin, as an
-- entrance's does; Shift+Enter only pins it
local SPOT = { icon = "Interface\\Icons\\INV_Letter_15", generic = true, secure = ns.Maps.SECURE, isOpen = ns.Maps.IsOpenFor,
	after = I.SpotAfter, activate = PinObject, secondary = PinObject }
local SPOT_META = { __index = function(t, k)
	if k == "mapID" then return rawget(t, "ui") end -- (the map the press opens: Maps.Target)
	return SPOT[k]
end }
--- A mailbox's row: its own fields, what it does shared (SPOT).
function I.SpotRow(t) return setmetatable(t, SPOT_META) end

--- The nearest spawn of any of these objects (ids) to `here` on your continent, else the first known anywhere: { ui, px,
--- py, wcont, wx, wy, zone, d (yards, when near you) }; nil when QuestieDB knows none.
function I.NearestSpawn(oids, here)
	local DB = QDB()
	if not (DB and DB.QueryObjectSingle) then return nil end
	local best, bestD, first
	for _, oid in ipairs(oids) do
		local spawns = Safe(DB.QueryObjectSingle, oid, "spawns")
		for area, list in pairs(type(spawns) == "table" and spawns or {}) do
			local ui = QD.UiMapOfArea(area)
			if ui and type(list) == "table" then
				for _, c in ipairs(list) do
					if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
						local cont, x, y = SpotXY(ui, c)
						local spot = { ui = ui, px = c[1], py = c[2], wcont = cont, wx = x, wy = y }
						first = first or spot
						if here and x and cont == here.cont then
							local d = math.sqrt((x - here.x) ^ 2 + (y - here.y) ^ 2)
							if not bestD or d < bestD then best, bestD = spot, d end
						end
					end
				end
			end
		end
	end
	local s = best or first
	if s then s.zone, s.d = ZoneName(s.ui), best and bestD or nil end
	return s
end

--- The rows of a kind of object (@mailbox): one per spawn, "Mailbox  Stormwind City", each with its map spot and its
--- place in world yards (for sort:nearest, near:, in: and the direction arrow). {} when QuestieDB has none to read.
function I.ObjectRows(kind)
	local ids = ObjectIds(kind)
	local DB = QDB()
	local rows = {}
	if not (ids and DB) then return rows end
	local label = kind:gsub("^%l", string.upper)
	for _, id in ipairs(ids) do
		local spawns = Safe(DB.QueryObjectSingle, id, "spawns")
		local n = 0
		for area, list in pairs(type(spawns) == "table" and spawns or {}) do
			local ui = QD.UiMapOfArea(area)
			if ui and type(list) == "table" then
				for _, c in ipairs(list) do
					if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
						n = n + 1
						local cont, x, y = SpotXY(ui, c)
						local zone = ZoneName(ui)
						rows[#rows + 1] = I.SpotRow({
							name = label, key = id .. "-" .. n, kind = kind,
							detail = zone, zone = zone, text = zone, ui = ui, px = c[1], py = c[2], area = area,
							wcont = cont, wx = x, wy = y,
						})
					end
				end
			end
		end
	end
	return rows
end

--- A map pin link for a row with a spot of its own (an entrance, a mailbox): the waypoint is set there (a C API).
function I.SpotPinLink(e)
	if not (e and e.ui and e.px and ns.Maps and ns.Maps.Place) then return nil end
	if not ns.Maps.Place({ name = e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } }) then return nil end
	return WaypointLink()
end

--- "nearest mailbox" (Simple mode): the nearest rows of that kind's list (those `keep` keeps: a place said), closest
--- first, "N yd  Zone".
--- nil when there's no such list; an empty list when none is on your continent.
function I.NearestObjectRows(kind, here, keep)
	local p = ns.providers[kind]
	if not p then return nil end
	local found = {}
	for _, e in ipairs(ns:GetEntries(p)) do
		local d = (not keep or keep(e)) and I.RowDistance(e, here) or nil
		if d then found[#found + 1] = { e = e, d = d } end
	end
	table.sort(found, function(a, b) return a.d < b.d end)
	local rows = {}
	for i = 1, math.min(#found, I.OBJECTS_NEAR) do
		local f = found[i]
		rows[i] = setmetatable({ detail = ("%.0f yd"):format(f.d) .. (f.e.zone and ("  " .. f.e.zone) or ""),
			_score = 1e6 - f.d, _dist = f.d, nearRest = f.e.zone }, { __index = f.e })
	end
	return rows
end

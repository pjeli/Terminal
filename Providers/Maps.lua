local ns = select(2, ...)

-- World map locations: continents, zones, dungeons and cities, plus the points of interest
-- the map itself shows (towns, flight points, dungeon entrances). Enter opens the world
-- map on that place; for a point it also drops the map waypoint on it. Shift+Enter sets
-- the waypoint and starts tracking it without opening anything.
--
-- The map is opened the way your own map key opens it (see Secure.lua). Switching the map
-- to the chosen place is attempted once; if the game blocks that, Terminal remembers and
-- only places the waypoint (see .debug).

local M = {}
ns.Maps = M

local TYPES = { [0] = "World", "World", "Continent", "Zone", "Dungeon", "Micro", "Orphan" }
local MAX = 4000

M.SECURE = { binding = "TOGGLEWORLDMAP", buttons = { "MiniMapWorldMapButton", "WorldMapMicroButton" } }

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
end

local function Name(s)
	if type(s) ~= "string" or s == "" then return nil end
	if issecretvalue and issecretvalue(s) then return nil end
	return s
end

local function MapOpen()
	local f = _G.WorldMapFrame
	return f and f.IsVisible and f:IsVisible() or false
end

local function Waypoint(mapID, pos)
	if not (C_Map and C_Map.SetUserWaypoint and pos and pos.x and pos.y) then return false end
	if C_Map.CanSetUserWaypointOnMap and not Safe(C_Map.CanSetUserWaypointOnMap, mapID) then return false end
	local pt
	if UiMapPoint and UiMapPoint.CreateFromCoordinates then
		pt = UiMapPoint.CreateFromCoordinates(mapID, pos.x, pos.y)
	else
		pt = { uiMapID = mapID, position = CreateVector2D and CreateVector2D(pos.x, pos.y) or pos }
	end
	if not pcall(C_Map.SetUserWaypoint, pt) then return false end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
	return true
end

--- The chosen place becomes the map pin. A pin that is already set is removed first, and
--- then replaced even for a whole zone (pinned at its middle), so the pin always follows
--- the last place picked here. With no pin set, only places with a spot of their own get one.
--- Returns "moved", "set" or nil.
local function Place(e)
	local had = C_Map and C_Map.HasUserWaypoint and Safe(C_Map.HasUserWaypoint)
	if had and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	local pos = e.pos or (had and { x = 0.5, y = 0.5 }) or nil
	if pos and Waypoint(e.mapID, pos) then return had and "moved" or "set" end
end

--- Runs once the map is open: show the place, and point at it.
local function ShowAfter(e)
	local f = _G.WorldMapFrame
	local switched = false
	if f and f.SetMapID and not InCombatLockdown() then
		-- attempted until the game blocks it once, then never again (see .debug)
		switched = ns.Professions.Guarded("WorldMapSetMapID", f.SetMapID, f, e.mapID)
	end
	local pin = Place(e)
	if pin and not switched then
		ns:Print("Waypoint " .. (pin == "moved" and "moved to " or "set on ") .. e.name .. " (couldn't switch the map to it).")
	elseif not pin and not switched then
		ns:Print("Opened the map; couldn't switch it to " .. e.name .. ".")
	end
end

local function Direct(e) -- no keybinding: open the map from our own code
	if InCombatLockdown() then
		-- the map's pins are protected in combat: touching it would only be blocked
		ns:Trace("maps: in combat, map left alone")
		if Place(e) then
			ns:Print("In combat: waypoint set on " .. e.name .. " (the map can't be opened now).")
		else
			ns:Print("The map can't be opened in combat.")
		end
		return
	end
	ns:Trace("DIRECT ToggleWorldMap (addon code, may be blocked)")
	if ToggleWorldMap and not MapOpen() then pcall(ToggleWorldMap) end
	C_Timer.After(0.1, function() ShowAfter(e) end)
end

-- for the addon integrations (Integrations.lua), which show places on the map too
M.Place, M.ShowAfter, M.MapOpen = Place, ShowAfter, MapOpen

local function Roots()
	local roots, seen = {}, {}
	local function add(id)
		if id and not seen[id] and Safe(C_Map.GetMapInfo, id) then seen[id] = true; roots[#roots + 1] = id end
	end
	add(946); add(947) -- Cosmic, Azeroth
	-- whatever this client's map hierarchy is, climb from where the player stands
	local id = Safe(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 8 do
		if not id then break end
		add(id)
		local info = Safe(C_Map.GetMapInfo, id)
		id = info and info.parentMapID ~= 0 and info.parentMapID or nil
		if id and seen[id] then break end
	end
	return roots
end

-- Every place shares these (compact entries: each place only holds what's its own)
local function PinOnly(e)
	local pin = Place(e)
	if pin then
		ns:Print("Waypoint " .. (pin == "moved" and "moved to " or "set: ") .. e.name)
	elseif not e.pos then
		ns:Print("Pick a place with a spot on the map to set a waypoint.")
	else
		ns:Print("Can't set a waypoint there.")
	end
end

local PROTO = {
	secure = M.SECURE,
	isOpen = MapOpen,
	after = ShowAfter,
	activate = Direct,
	-- Shift+Enter: waypoint (and tracking) without opening the map
	secondary = PinOnly,
}
local meta -- made once the provider exists (see collect)

local function Entry(o)
	return setmetatable({
		_compact = true,
		key = o.key, name = o.name, _lname = o.name:lower(), icon = o.icon, detail = o.detail,
		_ltext = ((o.path or "") .. " map location " .. (o.kind or "")):lower(),
		mapID = o.mapID, pos = o.pos,
	}, meta)
end

ns:RegisterProvider("maps", {
	label = "Map",
	color = "ff7fd6a8",
	aliases = { "map", "maps", "zone", "zones", "place", "location", "poi", "flight", "dungeon" },
	noCombat = true, -- opening windows is protected in combat
	lazy = true, -- thousands of places: only offered once you type something
	events = { "ZONE_CHANGED_NEW_AREA" },
	guard = 10,
	idleDrop = 600, -- thousands of places: freed after 10 minutes without a map search
	collect = function(p)
		local out = {}
		meta = meta or ns:CompactMeta(p, PROTO)
		if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return out end
		local maps, seen = {}, {}
		local function add(info)
			if type(info) ~= "table" or seen[info.mapID] or not Name(info.name) then return end
			seen[info.mapID] = true
			maps[#maps + 1] = info
		end
		for _, root in ipairs(Roots()) do
			add(Safe(C_Map.GetMapInfo, root))
			for _, info in ipairs(Safe(C_Map.GetMapChildrenInfo, root, nil, true) or {}) do add(info) end
		end
		local names = {}
		for _, info in ipairs(maps) do names[info.mapID] = info end
		local function pathOf(info)
			local parts, id, n = {}, info.parentMapID, 0
			while id and id ~= 0 and n < 6 do
				local p = names[id] or Safe(C_Map.GetMapInfo, id)
				if not p or not Name(p.name) then break end
				names[id] = p
				-- the Cosmic/World roots add nothing
				if p.mapType and p.mapType >= 2 then table.insert(parts, 1, p.name) end
				id, n = p.parentMapID, n + 1
			end
			return table.concat(parts, " > ")
		end
		for _, info in ipairs(maps) do
			if #out >= MAX then break end
			local mtype = info.mapType or 3
			local kind = TYPES[mtype] or "Zone"
			local path = pathOf(info)
			if mtype >= 2 then -- continents and below; not "Cosmic"/"World"
				out[#out + 1] = Entry({
					key = "map:" .. info.mapID, name = info.name, mapID = info.mapID, kind = kind, path = path,
					icon = "Interface\\Icons\\INV_Misc_Map_01",
					detail = kind .. (path ~= "" and ("  " .. path) or ""),
				})
			end
			-- what the map itself marks on this one: points of interest, flight points, entrances
			if mtype >= 2 and mtype <= 4 then
				local poiSeen = {}
				local function poi(id, name, pos, what, icon)
					name = Name(name)
					if not name or #out >= MAX then return end
					local k = what .. ":" .. info.mapID .. ":" .. tostring(id or name)
					if poiSeen[k] then return end
					poiSeen[k] = true
					out[#out + 1] = Entry({
						key = k, name = name, mapID = info.mapID, kind = what, pos = pos, path = info.name .. " " .. path,
						icon = icon,
						detail = what .. "  " .. info.name,
					})
				end
				if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then
					for _, id in ipairs(Safe(C_AreaPoiInfo.GetAreaPOIForMap, info.mapID) or {}) do
						local p = Safe(C_AreaPoiInfo.GetAreaPOIInfo, info.mapID, id)
						if type(p) == "table" then poi(id, p.name, p.position, "Point of interest", "Interface\\Icons\\INV_Misc_Flag_01") end
					end
				end
				if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
					for _, n in ipairs(Safe(C_TaxiMap.GetTaxiNodesForMap, info.mapID) or {}) do
						if type(n) == "table" then poi(n.nodeID, n.name, n.position, "Flight point", "Interface\\Icons\\Ability_Mount_Gryphon_01") end
					end
				end
				local EJ = _G.C_EncounterJournal
				if EJ and EJ.GetDungeonEntrancesForMap then
					for _, d in ipairs(Safe(EJ.GetDungeonEntrancesForMap, info.mapID) or {}) do
						if type(d) == "table" then poi(d.areaPoiID, d.name, d.position, "Dungeon entrance", "Interface\\Icons\\INV_Misc_Key_03") end
					end
				end
			end
		end
		return out
	end,
})

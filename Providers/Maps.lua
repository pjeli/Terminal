local ns = select(2, ...)

-- World map places: continents and zones (cities are zones). Enter opens the world map on
-- that place; Shift+Enter moves an existing map pin there without opening anything.
-- Nothing below zone level: points of interest, flight points and dungeon maps didn't load
-- reliably on this client (flight point addons do that job better), so they're left out.
--
-- Enter (or a click) runs a macro pressed by the game itself (see Secure.lua): it opens the
-- map if it's closed, as the map key does, and switches it to the place. Terminal never
-- calls WorldMapFrame:SetMapID itself: that leaves the map's state written by Terminal, and
-- the map's pins, rebuilt from it later (often in combat), then fail as Terminal's.
-- Afterwards Terminal only places the waypoint (a C call, nothing in the map's Lua).

local M = {}
ns.Maps = M

local TYPES = { [2] = "Continent", [3] = "Zone" } -- the only kinds listed

--- The map a place shows: its own, or one worked out for it (an NPC's or quest giver's zone).
function M.Target(e)
	if type(e) ~= "table" then return nil end
	local id = e.mapTarget or e.mapID
	return type(id) == "number" and id or nil
end

--- The macro the game runs: open the map if it's closed (what the map key runs), then show
--- the place. Nil (no place, or no map yet): the map key's binding is used instead.
local function MapMacro(e)
	local id = M.Target(e)
	if not id or not _G.WorldMapFrame or type(_G.ToggleWorldMap) ~= "function" then return nil end
	return ("/run if not WorldMapFrame:IsShown() then ToggleWorldMap() end WorldMapFrame:SetMapID(%d)"):format(id)
end

M.SECURE = { macro = MapMacro, binding = "TOGGLEWORLDMAP", buttons = { "MiniMapWorldMapButton", "WorldMapMicroButton" } }

local Safe, Name = ns.Safe, ns.Str -- (Util.lua)

local function MapOpen()
	local f = _G.WorldMapFrame
	return f and f.IsVisible and f:IsVisible() or false
end

--- isOpen for map entries: with a macro there's always something to run (it switches the
--- open map too), so only "open" when there's no macro for this place.
local function IsOpenFor(e)
	if MapMacro(e) then return false end
	return MapOpen()
end
M.IsOpenFor = IsOpenFor

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
	-- the game's macro switched the map; here it's only read (never written: see the top)
	local f = _G.WorldMapFrame
	local switched = false
	if f and f.GetMapID then
		local ok, id = pcall(f.GetMapID, f)
		switched = ok and id == (M.Target(e) or e.mapID)
	end
	ns:Trace("maps: the map " .. (switched and "shows " or "doesn't show ") .. tostring(e.name))
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
		-- a zone has no spot of its own: it only moves a waypoint that is already set
		ns:Print("A zone only moves a waypoint you already have; set one on the map first.")
	else
		ns:Print("Can't set a waypoint there.")
	end
end

local PROTO = {
	icon = "Interface\\Icons\\INV_Misc_Map_01", -- (every row's: kept here, not on each row)
	secure = M.SECURE,
	isOpen = IsOpenFor,
	after = ShowAfter,
	activate = Direct,
	-- Shift+Enter: waypoint (and tracking) without opening the map
	secondary = PinOnly,
}
local meta -- made once the provider exists (see collect)

local function Entry(o)
	return setmetatable({
		_compact = true,
		key = o.key, name = o.name, _lname = ns.Lower(o.name), detail = o.detail,
		_ltext = ns.Lower((o.path or "") .. " map location " .. (o.kind or "")),
		mapID = o.mapID,
	}, meta)
end

ns:RegisterProvider("maps", {
	label = "Map",
	color = "ff7fd6a8",
	aliases = { "map", "maps", "zone", "zones", "place", "location", "continent" },
	noCombat = true, -- opening windows is protected in combat
	lazy = true, -- thousands of places: only offered once you type something
	-- (no events: the list of continents and zones doesn't depend on where you are)
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
			local kind = TYPES[info.mapType or 3]
			if kind then -- continents and zones; not "Cosmic"/"World", nothing below a zone
				local path = pathOf(info)
				out[#out + 1] = Entry({
					key = "map:" .. info.mapID, name = info.name, mapID = info.mapID, kind = kind, path = path,
					detail = kind .. (path ~= "" and ("  " .. path) or ""),
				})
			end
		end
		return out
	end,
})

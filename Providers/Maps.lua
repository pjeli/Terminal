local ns = select(2, ...)
local L = ns.L

-- World map places: continents and zones (cities are zones). Enter opens the world map on
-- that place; Shift+Enter moves an existing map pin there without opening anything.
-- Nothing below zone level: points of interest, flight points and dungeon maps didn't load
-- reliably on this client, so they're left out (flight paths and instance entrances have lists
-- of their own, from known spots: Integrations/Flights.lua, Integrations/Entrances.lua).
--
-- Enter (or a click) runs a macro pressed by the game itself (see Secure.lua): one game call,
-- C_Map.OpenWorldMap(id). The game answers it with WORLD_MAP_OPEN, and the map's own code opens
-- the map (or switches the open one) to the place. Nothing in the macro touches the map's Lua:
-- WorldMapFrame:SetMapID leaves the map's zone written by whoever called it, and the map's pins,
-- rebuilt from it later (often in combat), then fail as that caller's. From Terminal's code that
-- was Terminal; from a /run line it is "*** ForceTaint_Strong ***", the game's name for code a
-- /run or /script line runs (0.46.0: Button:SetPassThroughButtons() x14 in combat, after a few
-- NPCs shown on the map). Afterwards Terminal only places the waypoint (a C call) and reads who
-- wrote the map's zone, for .debug log (M.MapWriter).

local M = {}
ns.Maps = M

--- A map row's key: "map:<uiMapID>" (Zones' zone rows are counted as these: review, 0.53.6).
function M.Key(mapID) return "map:" .. tostring(mapID) end

local TYPES = { [2] = "Continent", [3] = "Zone" } -- the only kinds listed
local KIND_SAID = { Continent = L["Continent"], Zone = L["Zone"] } -- (as the rows say it; TYPES stays searchable)

--- The map a place shows: its own, or one worked out for it (an NPC's or quest giver's zone).
function M.Target(e)
	if type(e) ~= "table" then return nil end
	local id = e.mapTarget or e.mapID
	return type(id) == "number" and id or nil
end

--- The macro the game runs: the game's own call that opens the map on the place (see the top). Nil (no place, no map
--- yet, or a client without that call): the map key's binding is used instead, which opens the map on your own zone.
local function MapMacro(e)
	local id = M.Target(e)
	if not id or not _G.WorldMapFrame or not (C_Map and type(C_Map.OpenWorldMap) == "function") then return nil end
	return ("/run C_Map.OpenWorldMap(%d)"):format(id)
end

M.SECURE = { macro = MapMacro, binding = "TOGGLEWORLDMAP", buttons = { "MiniMapWorldMapButton", "WorldMapMicroButton" } }

-- (0.49.2, review: an NPC Questie knows no spot for, or a quest an object or item starts, still pressed the map key: the
-- map opened on your own zone, then the after-step said Questie has no location for it. With no place there's nothing
-- to press, and the row's own action says so.)
local NO_PLACE = { macro = MapMacro }
--- The map spec for a row whose place is worked out when read (an NPC's, a quest giver's): M.SECURE when it has one.
function M.SecureFor(e) return M.Target(e) and M.SECURE or NO_PLACE end

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

--- The game takes a waypoint on that map (a continent doesn't), at a real spot.
local function CanPin(mapID, pos)
	if not (C_Map and C_Map.SetUserWaypoint and pos and pos.x and pos.y) then return false end
	return not (C_Map.CanSetUserWaypointOnMap and not Safe(C_Map.CanSetUserWaypointOnMap, mapID))
end

local function HasPin() return (C_Map and C_Map.HasUserWaypoint and Safe(C_Map.HasUserWaypoint)) and true or false end

local function Waypoint(mapID, pos)
	if not CanPin(mapID, pos) then return false end
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
	local had = HasPin()
	local pos = e.pos or (had and { x = 0.5, y = 0.5 }) or nil
	-- (0.49.2, review: the pin was cleared before asking whether the place takes one: Enter on "@map Kalimdor", a
	-- continent, lost your quest's waypoint without a word. Now it's only cleared when the new one can be set.)
	if not (pos and CanPin(e.mapID, pos)) then return nil end
	if had and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	if Waypoint(e.mapID, pos) then return had and "moved" or "set" end
end

--- The line saying where the map pin went ("set" / "moved": Place's answer): "Waypoint set on Ratchet (The Barrens)",
--- "Waypoint moved to Hogger". Every waypoint line says it this way.
function M.PinLine(pin, name, where)
	return (pin == "moved" and L["Waypoint moved to %s%s"] or L["Waypoint set on %s%s"]):format(tostring(name),
		(type(where) == "string" and where ~= "" and where ~= name) and (" (" .. where .. ")") or "")
end

--- Who last wrote the map's zone (WorldMapFrame.mapID), only read: "the game's own code", else the name the game
--- blames for it ("*** ForceTaint_Strong ***" for a /run line, an addon's name). Nil when this client can't tell.
function M.MapWriter() return ns.Secure.Writer(_G.WorldMapFrame, "mapID") end

--- Runs once the map is open: show the place, and point at it.
local function ShowAfter(e)
	-- the game's macro switched the map; here it's only read (never written: see the top)
	local f = _G.WorldMapFrame
	local switched = false
	if f and f.GetMapID then
		local ok, id = pcall(f.GetMapID, f)
		switched = ok and id == (M.Target(e) or e.mapID)
	end
	local writer = M.MapWriter()
	ns:Trace("maps: the map " .. (switched and "shows " or "doesn't show ") .. tostring(e.name)
		.. (writer and ("; its zone was set by " .. writer) or "")
		.. ((writer and writer ~= ns.Secure.GAME) and " (its pins may be blocked in combat)" or ""))
	local pin = Place(e)
	if pin and not switched then
		ns:Print(L["%s: couldn't switch the map to it."]:format(M.PinLine(pin, e.name)))
	elseif not pin and not switched then
		ns:Print(L["Opened the map; couldn't switch it to %s."]:format(e.name))
	end
end

-- No press could be set up: the map shown already is pointed at; else the place pinned and where to open it said.
-- (0.50.7, review: it opened the map from Terminal's own code, which taints the map's state: no window is opened that way,
-- even as a last resort, as Panels' and the quest log's fallbacks say)
local function Direct(e)
	if InCombatLockdown() then
		-- the map's pins are protected in combat: touching it would only be blocked
		ns:Trace("maps: in combat, map left alone")
		local pin = Place(e)
		if pin then
			ns:Print(L["%s: in combat, the map can't be opened now."]:format(M.PinLine(pin, e.name)))
		else
			ns:Print(L["The map can't be opened in combat."])
		end
		return
	end
	if MapOpen() then C_Timer.After(0.1, function() ShowAfter(e) end) return end
	ns:Trace("maps: nothing to press: pinned, and said where to open the map")
	local pin = Place(e)
	if pin then ns:Print(M.PinLine(pin, e.name)) end
	ns:Print(L["Open %s from its button or key (opening it from Terminal's own code would taint it)."]:format(L["World Map"]))
end

-- for the addon integrations (Providers/Integrations/), which show places on the map too
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
		ns:Print(M.PinLine(pin, e.name))
	elseif not e.pos and not HasPin() then
		-- a zone has no spot of its own: it only moves a waypoint that is already set
		ns:Print(L["A zone only moves a waypoint you already have; set one on the map first."])
	else
		-- (a continent: no waypoint goes there, and the one you have stays; 0.49.2)
		ns:Print(L["Can't set a waypoint there."])
	end
end

--- Shift+Enter's verb for a place (Easy.lua's footer and row menu), as PinOnly will do it: "set waypoint" at a spot of
--- its own, "move waypoint" for a zone while you have one, nothing when nothing would be set (no waypoint to move, or a
--- map that takes none). (0.49.2, review: a zone said "set waypoint" with none set, and then set nothing.)
function M.PinVerb(e)
	local mapID = e.mapID
	if mapID and C_Map and C_Map.CanSetUserWaypointOnMap and not Safe(C_Map.CanSetUserWaypointOnMap, mapID) then return nil end
	if e.pos then return L["set waypoint"] end
	return HasPin() and L["move waypoint"] or nil
end

M.Direct, M.PinOnly = Direct, PinOnly -- (Zones.lua's answers open zones as @map rows do)

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
	label = L["Map"],
	color = "ff7fd6a8",
	aliases = { "map", "maps", "zone", "zones", "place", "location", "continent" },
	noCombat = true, -- opening windows is protected in combat
	lazy = true, -- (only offered once you type something)
	-- (no events: the list of continents and zones doesn't depend on where you are)
	idleDrop = 600, -- (continents and zones: freed after 10 minutes without a map search)
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
				local lv = ns.Zones and ns.Zones.LevelText(ns.Zones.Of(info.mapID))
				out[#out + 1] = Entry({
					key = M.Key(info.mapID), name = info.name, mapID = info.mapID, kind = kind, path = path,
					detail = ns.Detail(KIND_SAID[kind] or kind, lv, path),
				})
			end
		end
		return out
	end,
})

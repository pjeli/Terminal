local ns = select(2, ...)
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local QD = ns.QuestieData
local function QDB() return QD.DB() end

----------------------------------------------------------------------
-- Distances: where you are, where an NPC or a spot is, in world yards
----------------------------------------------------------------------

--- Where you are, in world coordinates (yards): { continent, x, y }, or nil (an instance, no map position).
function I.Here()
	local M = C_Map
	if not (M and M.GetBestMapForUnit and M.GetPlayerMapPosition and M.GetWorldPosFromMapPos) then return nil end
	local map = Safe(M.GetBestMapForUnit, "player")
	local pos = map and Safe(M.GetPlayerMapPosition, map, "player")
	if not pos then return nil end
	local cont, world = Safe(M.GetWorldPosFromMapPos, map, pos)
	if not (cont and world) then return nil end
	local x, y = world.x, world.y
	if world.GetXY then x, y = world:GetXY() end
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end -- (a secret position: unknown)
	return { cont = cont, x = x, y = y }
end

-- Map % -> world yards. A map's world position is a straight (affine) function of its map position, so each
-- map is asked three times once (its corner and one step along each side) and every spot after that is arithmetic.
local xforms = {} -- uiMap -> { cont, ox, oy, xx, xy, yx, yy } or false (the game had no answer)
local function World(ui, x, y)
	local vec = _G.CreateVector2D
	local p = vec and vec(x, y) or { x = x, y = y }
	local cont, world = Safe(C_Map.GetWorldPosFromMapPos, ui, p)
	if not (cont and world) then return nil end
	local wx, wy = world.x, world.y
	if world.GetXY then wx, wy = world:GetXY() end
	if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
	return cont, wx, wy
end
local function Xform(ui)
	if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end -- (no map API: unknown, nothing kept)
	local t = xforms[ui]
	if t ~= nil then return t or nil end
	local c0, ox, oy = World(ui, 0, 0)
	local c1, ax, ay = World(ui, 1, 0)
	local c2, bx, by = World(ui, 0, 1)
	t = (c0 and c1 and c2) and { c0, ox, oy, ax - ox, ay - oy, bx - ox, by - oy } or false
	xforms[ui] = t
	return t or nil
end

-- a spawn's place in world yards (c = { x%, y% } on map ui): cont, x, y (nil: unknown)
local function SpotXY(ui, c)
	local t = Xform(ui)
	if not t then return nil end
	local u, v = c[1] / 100, c[2] / 100
	return t[1], t[2] + u * t[4] + v * t[6], t[3] + u * t[5] + v * t[7]
end
I.SpotXY = SpotXY -- (Zones.lua: how far a zone's middle is)
local function Spot(ui, c)
	local cont, x, y = SpotXY(ui, c)
	return cont and { cont = cont, x = x, y = y } or nil
end

-- each NPC's spawns in world yards, worked out once: id -> flat { cont, x, y, cont, x, y... } (false: none)
local npcSpots, npcSpotCount = {}, 0
local NPC_SPOTS_MAX = 6000 -- (forgotten all at once past this: a session of "nearest" asks a few thousand)
local function NpcSpots(id)
	local t = npcSpots[id]
	if t ~= nil then return t or nil end
	t = false
	local DB = QDB()
	local spawns = DB and Safe(DB.QueryNPCSingle, id, "spawns")
	if type(spawns) == "table" then
		for area, list in pairs(spawns) do
			local ui = QD.UiMapOfArea(area)
			if ui and type(list) == "table" then
				for _, c in ipairs(list) do
					if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
						local cont, x, y = SpotXY(ui, c)
						if cont then
							t = t or {}
							t[#t + 1], t[#t + 2], t[#t + 3] = cont, x, y
						end
					end
				end
			end
		end
	end
	if npcSpotCount >= NPC_SPOTS_MAX then npcSpots, npcSpotCount = {}, 0 end
	npcSpots[id], npcSpotCount = t, npcSpotCount + 1
	return t or nil
end

--- How far an NPC is from `here` (yards, its nearest spawn on your continent), or nil: no known spawn there.
--- Also gives that spawn's world position ({ cont, x, y }: x grows to the north, y to the west).
local function NpcDistance(id, here)
	if not here then return nil end
	local t = NpcSpots(id)
	if not t then return nil end
	local best, bi
	local hc, hx, hy = here.cont, here.x, here.y
	for i = 1, #t, 3 do
		if t[i] == hc then
			local dx, dy = t[i + 1] - hx, t[i + 2] - hy
			local d = dx * dx + dy * dy
			if not best or d < best then best, bi = d, i end
		end
	end
	if not best then return nil end
	return math.sqrt(best), { cont = hc, x = t[bi + 1], y = t[bi + 2] }
end
I.NpcDistance = NpcDistance

--- How far a row is from `here` (yards) and that spot ({ cont, x, y }), or nil: an NPC's nearest spawn on your
--- continent (NpcDistance), or a row that carries its own place in world yards (`wcont`, `wx`, `wy`: @mailbox).
local function RowDistance(e, here)
	if not (e and here) then return nil end
	local wc = e.wcont
	if wc then
		if wc ~= here.cont then return nil end
		local dx, dy = e.wx - here.x, e.wy - here.y
		return math.sqrt(dx * dx + dy * dy), { cont = wc, x = e.wx, y = e.wy }
	end
	local id = e.kind == "npc" and (e.npcID or rawget(e, "key"))
	if type(id) == "number" then return I.NpcDistance(id, here) end
end
I.RowDistance = RowDistance

--- NpcDistance's yards alone: no spot table made.
local function NpcYards(id, here)
	local t = NpcSpots(id)
	if not t then return nil end
	local best
	local hc, hx, hy = here.cont, here.x, here.y
	for i = 1, #t, 3 do
		if t[i] == hc then
			local dx, dy = t[i + 1] - hx, t[i + 2] - hy
			local d = dx * dx + dy * dy
			if not best or d < best then best = d end
		end
	end
	if not best then return nil end
	return math.sqrt(best)
end

--- How far a row is from `here` (yards), or nil: RowDistance's first answer, with no spot table made ("nearest" asks
--- for every NPC that matched, thousands a keystroke: Search.lua's Scan.NearestViews). I.RowDistance or I.NpcDistance
--- put in place of these (tests give NPCs made-up distances that way) is asked instead, as RowDistance would.
function I.RowYards(e, here)
	if I.RowDistance ~= RowDistance then return (I.RowDistance(e, here)) end
	if not (e and here) then return nil end
	local wc = e.wcont
	if wc then
		if wc ~= here.cont then return nil end
		local dx, dy = e.wx - here.x, e.wy - here.y
		return math.sqrt(dx * dx + dy * dy)
	end
	local id = e.kind == "npc" and (e.npcID or rawget(e, "key"))
	if type(id) == "number" then
		if I.NpcDistance ~= NpcDistance then return (I.NpcDistance(id, here)) end
		return NpcYards(id, here)
	end
end

local zoneNames = {}
local function ZoneName(ui)
	local n = zoneNames[ui]
	if n == nil then
		if not (C_Map and C_Map.GetMapInfo) then return nil end -- (no map API: nothing kept)
		local info = Safe(C_Map.GetMapInfo, ui)
		n = type(info) == "table" and type(info.name) == "string" and info.name or false
		zoneNames[ui] = n
	end
	return n or nil
end
I.ZoneName = ZoneName

--- Which way an NPC is from where you face: radians, counter-clockwise from straight ahead (0 = ahead,
--- pi/2 = to your left), and how far (yards); nil when unknown (no position, no facing, not on your continent).
function I.NpcBearing(id)
	local face = I.Facing()
	if not face then return nil end
	local here = I.Here()
	local d, w = I.NpcDistance(id, here)
	if not d then return nil end
	return I.Bearing(here, w, face), d
end

--- Where you face (radians counter-clockwise from north), or nil (unknown, or a secret value).
function I.Facing()
	local face = _G.GetPlayerFacing and Safe(_G.GetPlayerFacing)
	return ns.Num(face)
end

--- The turn from where you face to a spot (world x is north, y is west; facing counter-clockwise from north).
function I.Bearing(here, spot, face)
	return math.atan2(spot.y - here.y, spot.x - here.x) - face
end

I._.Spot = Spot
-- (Places.lua's ResetPlacesForTests: the map transforms and NPC spots are forgotten with the places)
I._.ResetDistances = function() xforms, npcSpots, npcSpotCount = {}, {}, 0 end
I._.ResetZoneNames = function() zoneNames = {} end -- (tests that name their own maps)

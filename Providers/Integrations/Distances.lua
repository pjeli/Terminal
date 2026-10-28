local ns = select(2, ...)
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local QD = ns.QuestieData
local function QDB() return QD.DB() end

----------------------------------------------------------------------
-- Distances: where you are, where an NPC or a spot is, in world yards
----------------------------------------------------------------------

--- Where you are, in world coordinates (yards): { continent, x, y }, or nil (an instance, no map position). While
--- Terminal answers someone's !t question (Core/Ask.lua's ns.Asker): where they are.
function I.Here()
	local a = ns.Asker
	if a then return a.here or nil end
	return I.UnitSpot("player")
end

--- Where a unit is (player, party1, raid3), as I.Here; nil inside, or when the game won't say.
function I.UnitSpot(unit)
	local M = C_Map
	if not (M and M.GetBestMapForUnit and M.GetPlayerMapPosition and M.GetWorldPosFromMapPos) then return nil end
	local map = Safe(M.GetBestMapForUnit, unit)
	local pos = map and Safe(M.GetPlayerMapPosition, map, unit)
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
--- A spot on a map (fx, fy: 0 to 1 across it) in world yards, as I.Here gives yours; nil when unknown. (!t: the
--- middle of a guildie's zone stands for where they are)
function I.MapSpot(ui, fx, fy)
	local cont, x, y = SpotXY(ui, { fx * 100, fy * 100 })
	return cont and { cont = cont, x = x, y = y } or nil
end
local function Spot(ui, c)
	local cont, x, y = SpotXY(ui, c)
	return cont and { cont = cont, x = x, y = y } or nil
end

-- An NPC inside a dungeon (0.51.18, the player's ask): Questie keeps its spawns under the dungeon's area, with no spot
-- in the world (often { -1, -1 }); the dungeon's entrances stand for them: their spots are the NPC's for how far and
-- which way, and its rows say which dungeon it's in. id -> the dungeon's name (false: it's out in the world too, or
-- not in one).
local npcDungeon, npcDungeonCount = {}, 0
--- The entrances of a dungeon area as { ui, { x%, y% } } pairs, or nil when the area isn't a dungeon's.
local function Entrances(area)
	local dl = QD.DungeonLocation(area)
	if type(dl) ~= "table" or not dl[1] then return nil end
	local out = {}
	for _, e in ipairs(dl) do
		local ui = type(e) == "table" and QD.UiMapOfArea(e[1])
		if ui and type(e[2]) == "number" and type(e[3]) == "number" then out[#out + 1] = { ui, { e[2], e[3] } } end
	end
	return #out > 0 and out or nil
end
I.Entrances = Entrances
--- The dungeon an NPC is in (its name, in the client's language), or nil: one with a spawn out in the world isn't.
function I.NpcDungeon(id)
	local d = npcDungeon[id]
	if d ~= nil then return d or nil end
	d = false
	local DB = QDB()
	local spawns = DB and Safe(DB.QueryNPCSingle, id, "spawns")
	if type(spawns) == "table" then
		local name, world
		for area, list in pairs(spawns) do
			if type(list) == "table" and #list > 0 then
				if Entrances(area) then
					if not name then
						local n = C_Map and C_Map.GetAreaInfo and Safe(C_Map.GetAreaInfo, area)
						name = ns.Str(n)
					end
				else
					world = true -- (out in the world too: its spot there)
					break
				end
			end
		end
		d = (not world and name) or false
	end
	if npcDungeonCount >= 13000 then npcDungeon, npcDungeonCount = {}, 0 end
	npcDungeon[id], npcDungeonCount = d, npcDungeonCount + 1
	return d or nil
end

-- each NPC's spawns in world yards, worked out once: id -> flat { cont, x, y, cont, x, y... } (false: none)
local npcSpots, npcSpotCount = {}, 0
-- (forgotten all at once past this. 0.50.7, review: 6000 was under WoW Forever's 11.7k NPCs, so a broad "@npc
-- sort:distance" filled it, emptied it and filled it again in one search, and again on every keystroke; ~4.5 MB at its cap)
local NPC_SPOTS_MAX = 13000
I._.NPC_SPOTS_MAX = NPC_SPOTS_MAX -- (tests)
--- Each spawn in Questie's spawns by area, in world yards: fn(cont, x, y, ui, c, door, area) (c: Questie's { x%, y% };
--- door: true for a dungeon's entrance, which stands for its spawns, as Questie's map shows them; 0.51.18). `noDoors`:
--- the spawns themselves (objects). One walk for every list that reads spawns (review, 0.53.6: NpcSpots and
--- NearestSpawn had a copy each and had drifted apart once, 0.51.25; Objects two more).
local function EachSpot(spawns, fn, noDoors)
	if type(spawns) ~= "table" then return end
	for area, list in pairs(spawns) do
		local ui = QD.UiMapOfArea(area)
		local doors = not noDoors and type(list) == "table" and #list > 0 and Entrances(area)
		if doors then
			for _, door in ipairs(doors) do
				local cont, x, y = SpotXY(door[1], door[2])
				if cont then fn(cont, x, y, door[1], door[2], true, area) end
			end
		elseif ui and type(list) == "table" then
			for _, c in ipairs(list) do
				if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
					local cont, x, y = SpotXY(ui, c)
					fn(cont, x, y, ui, c, nil, area) -- (cont nil: a map with no place in the world)
				end
			end
		end
	end
end
I._.EachSpot = EachSpot

local function NpcSpots(id)
	local t = npcSpots[id]
	if t ~= nil then return t or nil end
	t = false
	local DB = QDB()
	EachSpot(DB and Safe(DB.QueryNPCSingle, id, "spawns"), function(cont, x, y)
		if cont then
			t = t or {}
			t[#t + 1], t[#t + 2], t[#t + 3] = cont, x, y
		end
	end)
	if npcSpotCount >= NPC_SPOTS_MAX then npcSpots, npcSpotCount = {}, 0 end
	npcSpots[id], npcSpotCount = t, npcSpotCount + 1
	return t or nil
end

-- the nearest of an NPC's spots on here's continent: its squared distance and its place in the flat list
local function NearestOf(t, here)
	local best, bi
	local hc, hx, hy = here.cont, here.x, here.y
	for i = 1, #t, 3 do
		if t[i] == hc then
			local dx, dy = t[i + 1] - hx, t[i + 2] - hy
			local d = dx * dx + dy * dy
			if not best or d < best then best, bi = d, i end
		end
	end
	return best, bi
end

--- How far an NPC is from `here` (yards, its nearest spawn on your continent), or nil: no known spawn there.
--- Also gives that spawn's world position ({ cont, x, y }: x grows to the north, y to the west).
local function NpcDistance(id, here)
	if not here then return nil end
	local t = NpcSpots(id)
	if not t then return nil end
	local best, bi = NearestOf(t, here)
	if not best then return nil end
	return math.sqrt(best), { cont = here.cont, x = t[bi + 1], y = t[bi + 2] }
end
I.NpcDistance = NpcDistance

--- The spawn NpcDistance finds (its nearest on your continent), as Questie gives it: the map it's on and its { x%, y% };
--- nil when none is on your continent. `spawns` = Questie's spawns by area. (0.49.2, review: Questie.lua's NpcLocation,
--- where Enter shows the NPC and pins it, took the first area pairs() gave: the row said 10 yd, Enter showed another zone.)
local function NearestSpawn(spawns, here)
	if not (here and type(spawns) == "table") then return nil end
	local best, bui, bc, bdoor
	EachSpot(spawns, function(cont, x, y, ui, c, door)
		if cont == here.cont then
			local dx, dy = x - here.x, y - here.y
			local d = dx * dx + dy * dy
			if not best or d < best then best, bui, bc, bdoor = d, ui, c, door end
		end
	end)
	return bui, bc, bdoor
end

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
	local best = t and NearestOf(t, here)
	return best and math.sqrt(best) or nil
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

--- Where you face (radians counter-clockwise from north), or nil (unknown, or a secret value).
function I.Facing()
	local face = _G.GetPlayerFacing and Safe(_G.GetPlayerFacing)
	return ns.Num(face)
end

--- The turn from where you face to a spot (world x is north, y is west; facing counter-clockwise from north).
function I.Bearing(here, spot, face)
	return math.atan2(spot.y - here.y, spot.x - here.x) - face
end

I._.Spot, I._.NearestSpawn = Spot, NearestSpawn
-- (Places.lua's ResetPlacesForTests: the map transforms and NPC spots are forgotten with the places)
I._.ResetDistances = function() xforms, npcSpots, npcSpotCount, npcDungeon, npcDungeonCount = {}, {}, 0, {}, 0 end
I._.ResetZoneNames = function() zoneNames = {} end -- (tests that name their own maps)

--- A row's view saying how far it is: "N yd  <rest>", scored closest first (sort:distance, "nearest mailbox"; one copy,
--- review 0.53.6: Search.lua's and Objects.lua's).
--- far: scored the farthest first (sort:-distance, "farthest innkeeper"; 0.65.7), under any row's own score (those with
--- no distance known, as if infinitely far, before them).
I.FAR_BASE = -1e7
function I.NearView(e, d, rest, far)
	return setmetatable({ detail = ns.NearDetail(d, rest), _score = far and (I.FAR_BASE + d) or (1e6 - d), _dist = d, nearRest = rest },
		{ __index = e })
end

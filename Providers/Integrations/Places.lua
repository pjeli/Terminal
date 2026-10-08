local ns = select(2, ...)
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local RunSliced = I.RunSliced
local qdb = I.qdb
local QD = ns.QuestieData
local function QDB() return QD.DB() end
local IP = I._
local Spot, ObjectivesText, ResetDistances, ClearNpcFields = IP.Spot, IP.ObjectivesText, IP.ResetDistances, IP.ClearNpcFields

----------------------------------------------------------------------
-- Places by name: zones and their parts (towns, camps), for "vendor ratchet" in Simple mode
----------------------------------------------------------------------

I.TOWN_R = 250 -- yards from a town's flight point that count as in it

local placeIndex -- { byName = lowercase name -> { area, parent, name, key }, words = most words in a name }
local function PlaceIndex()
	if placeIndex then return placeIndex end
	local z = QD.Zones and QD.Zones()
	if not (z and C_Map and C_Map.GetAreaInfo) then return nil end
	local E = ns.Easy
	local idx = { byName = {}, byArea = {}, words = 1 }
	local function add(area, parent)
		local n = Safe(C_Map.GetAreaInfo, area)
		if type(n) ~= "string" or (_G.issecretvalue and _G.issecretvalue(n)) then return end
		local key = ns.Lower(n):gsub("^the ", "")
		if #key < 4 or (E and (E.WORDS[key] or E.STOP[key] or E.ACTIONS[key])) then return end
		local place = { area = area, parent = parent, name = n, key = key }
		idx.byName[key] = place
		idx.byArea[area] = place
		local words = select(2, key:gsub("%S+", ""))
		if words > idx.words then idx.words = words end
	end
	for sub, parent in pairs(z.sub or {}) do if type(sub) == "number" and type(parent) == "number" then add(sub, parent) end end
	-- (a zone wins over a part of another zone with the same name)
	-- (QuestieDB's area -> map table lists the parts too, Goldshire -> Elwynn's map: those stay parts)
	local subs = z.sub or {}
	for area, ui in pairs(z.map or {}) do
		if type(area) == "number" and area > 0 and ui ~= 0 and not subs[area] then add(area, nil) end
	end
	placeIndex = idx
	local n = 0
	for _ in pairs(idx.byName) do n = n + 1 end
	ns:Trace("places: " .. n .. " place names known")
	return idx
end

--- A place named by some of the words (the longest run of them that is a name): place, the other words.
function I.FindPlace(tokens)
	local idx = PlaceIndex()
	if not idx then
		if not I.placeTraced then I.placeTraced = true; ns:Trace("places: no zone tables (QuestieDB) to know places by") end
		return nil
	end
	for len = math.min(idx.words + 1, #tokens), 1, -1 do -- (+1: a leading "the")
		for i = 1, #tokens - len + 1 do
			local name = table.concat(tokens, " ", i, i + len - 1):gsub("^the ", "")
			local place = idx.byName[name]
			if place then
				local rest = {}
				for k = 1, #tokens do if k < i or k >= i + len then rest[#rest + 1] = tokens[k] end end
				return place, rest
			end
		end
	end
	-- shorthand ("org", "sw", "if", "tb": Shorthand.lua) for a place's full name
	local SH = ns.Shorthand
	for i = 1, SH and #tokens or 0 do
		for _, full in ipairs(SH[tokens[i]] or {}) do
			local place = idx.byName[(full:gsub("^the ", ""))]
			if place then
				local rest = {}
				for k = 1, #tokens do if k ~= i then rest[#rest + 1] = tokens[k] end end
				return place, rest
			end
		end
	end
end

-- Towns from the quests' own words: "Speak to Marshal Dughan in Goldshire", "Bring the claw to Sputtervalve in Ratchet":
-- the quest's finisher stands in that town, so the middle (median) of the finishers named "in/at <town>" is the town's
-- middle. QuestieDB has no positions for a zone's parts (its NPCs' zoneID is the whole zone), this finds most towns
-- (Goldshire, Ratchet, the Crossroads...). Worked out once for every town: area -> { x%, y% } on its zone's map.
local textTowns
local function Median(t)
	table.sort(t)
	local n = #t
	if n == 0 then return nil end
	if n % 2 == 1 then return t[(n + 1) / 2] end
	return (t[n / 2] + t[n / 2 + 1]) / 2
end
-- the quests that name each town: area -> { quest ids } (string work only: cheap)
local function TownHits(idx, DB)
	local hits = {}
	local function Scan(qid, text)
		if type(text) ~= "string" then return end
		local at = 1
		while true do
			local s, e = text:find("%f[%w][ai][nt] ", at)
			if not s then break end
			at = e + 1
			local word = text:sub(s, e - 1)
			if word == "in" or word == "at" then
				-- the words after it, longest run first ("booty bay", "the crossroads")
				local words, pos = {}, e + 1
				for _ = 1, idx.words + 1 do
					local w0, w1, w = text:find("^%s*(%S+)", pos)
					if not w0 then break end
					w = w:gsub("[%.,;:!%?%)]+$", "")
					words[#words + 1] = w
					pos = w1 + 1
					if w == "" then break end
				end
				for n = #words, 1, -1 do
					local name = table.concat(words, " ", 1, n):gsub("^the ", "")
					local place = idx.byName[name]
					if place and place.parent then
						local list = hits[place.area] or {}
						hits[place.area] = list
						list[#list + 1] = qid
						break
					end
				end
			end
		end
	end
	local list = qdb.list
	if list then
		for i = 1, #list do Scan(list[i].qid, rawget(list[i], "_ltext")) end
	else
		for _, id in ipairs(DB.QuestIds() or {}) do Scan(id, ObjectivesText(DB, id)) end
	end
	return hits
end

-- one town's middle: the median of its quests' finishers' spawns on its zone's map, or nil
local function TownFromQuests(idx, DB, area, qids)
	local parent = idx.byArea[area] and idx.byArea[area].parent
	local xs, ys, seen = {}, {}, {}
	for _, qid in ipairs(qids) do
		local fin = Safe(DB.QueryQuestSingle, qid, "finishedBy")
		for _, id in ipairs(type(fin) == "table" and type(fin[1]) == "table" and fin[1] or {}) do
			if not seen[id] then
				seen[id] = true
				local sp = Safe(DB.QueryNPCSingle, id, "spawns")
				for _, c in ipairs(type(sp) == "table" and type(sp[parent]) == "table" and sp[parent] or {}) do
					if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
						xs[#xs + 1], ys[#ys + 1] = c[1], c[2]
					end
				end
			end
		end
	end
	if #xs > 0 then return { Median(xs), Median(ys), n = #xs } end
end

local townsBuilding
--- Every town's middle from the quests' words. Built in the background once Questie's quests are indexed
--- (`sliced`: a few towns a frame); asked before that, worked out at once.
local function TextTowns(sliced)
	if textTowns then return textTowns end
	local idx, DB = PlaceIndex(), QDB()
	if not (idx and DB and DB.QueryQuestSingle and DB.QueryNPCSingle) then return nil end
	if sliced and townsBuilding then return nil end
	-- (asked before Questie's quests are indexed: reading every quest's text now would stall the game; later)
	if not sliced and not qdb.list then return nil end
	local t0 = debugprofilestop and debugprofilestop()
	local hits = TownHits(idx, DB)
	local areas = {}
	for area in pairs(hits) do areas[#areas + 1] = area end
	local out = {}
	local function Finish()
		local n = 0
		for _ in pairs(out) do n = n + 1 end
		ns:Trace(("places: %d towns placed from quest texts%s"):format(n,
			(t0 and not sliced) and (" (%.0f ms)"):format(debugprofilestop() - t0) or ""))
	end
	if sliced then
		townsBuilding = true
		RunSliced("places: towns from quest texts", #areas, function(i)
			out[areas[i]] = TownFromQuests(idx, DB, areas[i], hits[areas[i]])
		end, function()
			townsBuilding = nil
			if not textTowns then textTowns = out; Finish() end
		end)
		return nil
	end
	for _, area in ipairs(areas) do out[area] = TownFromQuests(idx, DB, area, hits[area]) end
	textTowns = out
	Finish()
	return textTowns
end
I.BuildTowns = function() return TextTowns(true) end
--- Towns can't be placed from the quests yet (Questie's quests aren't indexed).
function I.TownsPending() return not textTowns and not qdb.list end

-- a town's middle: its flight point (on its zone's map, else a map above it), else where its quests send you,
-- in world yards (false: none)
local centres = {}

--- A town's flight point in world yards (false: none found), looked for on its zone's map, then up to two maps
--- above it; also the maps tried and how many flight points were read (for the trace).
local function FlightPointCentre(place)
	local c = false
	local T = _G.C_TaxiMap
	local ui = place.parent and QD.UiMapOfArea(place.parent)
	local seen, tried = 0, {}
	while ui and ui > 0 and not c and #tried < 3 do
		tried[#tried + 1] = ui
		local nodes = T and T.GetTaxiNodesForMap and Safe(T.GetTaxiNodesForMap, ui)
		for _, n in ipairs(type(nodes) == "table" and nodes or {}) do
			seen = seen + 1
			local name = type(n.name) == "string" and ns.Lower(n.name:match("^[^,]+") or n.name):gsub("^the ", "")
			local p = n.position
			if name == place.key and type(p) == "table" then
				local x, y = p.x, p.y
				if p.GetXY then x, y = p:GetXY() end
				if type(x) == "number" then c = Spot(ui, { x * 100, y * 100 }) or false end
				break
			end
		end
		local info = not c and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, ui)
		ui = type(info) == "table" and info.parentMapID or nil
	end
	return c, tried, seen
end

local function TownCentre(place)
	local c = centres[place.area]
	if c ~= nil then return c or nil end
	local tried, seen
	c, tried, seen = FlightPointCentre(place)
	local from = c and "its flight point" or nil
	if not c then
		local tt = TextTowns()
		local t = tt and tt[place.area]
		local zui = t and QD.UiMapOfArea(place.parent)
		if zui then
			c = Spot(zui, { t[1], t[2] }) or false
			from = c and ("where its quests send you, " .. t.n .. " spots") or nil
		end
	end
	if not c and I.TownsPending() then return nil end -- (not known yet: asked again once the quests are in)
	ns:Trace(("places: %s %s (flight points read on maps %s: %d)"):format(place.name,
		c and ("centre from " .. from .. " " .. math.floor(c.x) .. "," .. math.floor(c.y)) or "has no centre found",
		table.concat(tried, "/"), seen))
	centres[place.area] = c
	return c or nil
end

-- a spawn on the town's zone map: in the town? true / false, or nil when nothing can tell (no flight point,
-- and that spot of the map not explored)
local function SpawnInTown(place, ui, c, centre)
	if centre then
		local w = Spot(ui, c)
		if w and w.cont == centre.cont then
			local dx, dy = w.x - centre.x, w.y - centre.y
			if dx * dx + dy * dy <= I.TOWN_R * I.TOWN_R then return true end
		end
	end
	local X = _G.C_MapExplorationInfo
	if X and X.GetExploredAreaIDsAtPosition then
		local vec = _G.CreateVector2D
		local p = vec and vec(c[1] / 100, c[2] / 100) or { x = c[1] / 100, y = c[2] / 100 }
		local ids = Safe(X.GetExploredAreaIDsAtPosition, ui, p)
		if type(ids) == "table" and #ids > 0 then
			for _, a in ipairs(ids) do if a == place.area then return true end end
			return false
		end
	end
	if centre then return false end
	return nil
end

--- Is a row with a spot of its own (@mailbox: `area`, `ui`, `px`/`py`) in a place? As NpcInPlace, for its one spawn.
function I.RowInPlace(e, place)
	local area = e.area
	if area == place.area then return true end
	if not place.parent then return ((QD.Zones() or {}).sub or {})[area] == place.area end
	if area ~= place.parent then return false end
	return SpawnInTown(place, e.ui, { e.px, e.py }, TownCentre(place)) ~= false -- (unknown: the whole zone counts)
end

--- Is an NPC in a place (I.FindPlace)? A zone: a spawn in it or one of its parts. A town: a spawn in it;
--- when nothing can tell where the town is (no flight point, not explored), its whole zone counts.
function I.NpcInPlace(id, place)
	local DB = QDB()
	local spawns = DB and Safe(DB.QueryNPCSingle, id, "spawns")
	if type(spawns) ~= "table" then return false end
	local subs = (QD.Zones() or {}).sub or {}
	local unknown = false
	for area, list in pairs(spawns) do
		if area == place.area then return true end
		if not place.parent then
			if subs[area] == place.area then return true end
		elseif area == place.parent and type(list) == "table" then
			local ui = QD.UiMapOfArea(area)
			if ui then
				local centre = TownCentre(place)
				for _, c in ipairs(list) do
					if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
						local yes = SpawnInTown(place, ui, c, centre)
						if yes then return true end
						if yes == nil then unknown = true end
					end
				end
			end
		end
	end
	if unknown and not place.guessed then
		place.guessed = true
		ns:Trace("places: nothing tells where " .. place.name .. " is (no flight point, not explored): all of its zone counts")
	end
	return unknown
end

--- The filter for a place: NPCs in it; any other row with the place in its text or where it is (in:).
function I.PlaceFilter(place)
	local F = ns.Filters
	local where = F and F.Parse("in:" .. place.key:gsub(" ", "_"))
	place.npcs = place.npcs or {} -- (kept with the place: the next keystroke asks again)
	local cache = place.npcs
	return function(e)
		local id = e.kind == "npc" and (rawget(e, "key") or e.npcID)
		if id then
			local v = cache[id]
			if v == nil then
				v = I.NpcInPlace(id, place)
				-- (kept once the towns can be known; a zone doesn't wait on them)
				if not place.parent or not I.TownsPending() then cache[id] = v end
			end
			return v
		end
		if e.wcont and e.area then return I.RowInPlace(e, place) end -- (@mailbox: by its spot)
		local t = rawget(e, "_ltext")
		if t and t:find(place.key, 1, true) then return true end
		return where and where(e) or false
	end
end

I.ResetPlacesForTests = function()
	placeIndex, centres, textTowns, townsBuilding = nil, {}, nil, nil
	ResetDistances() -- (Distances.lua: the map transforms and the NPCs' spots)
	ClearNpcFields() -- (Questie.lua: the NPCs' small fields)
end

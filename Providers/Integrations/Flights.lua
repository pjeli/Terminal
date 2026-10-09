local ns = select(2, ...)
local I = ns.Integrations
local Safe, Str, Num, Lower = ns.Safe, ns.Str, ns.Num, ns.Lower
local SpotXY, ZoneName, PinObject = I.SpotXY, I.ZoneName, I.PinObject

----------------------------------------------------------------------
-- Flight paths (@flight; Simple mode: "nearest unlearned flight master", "unlearned flight paths", under Places)
----------------------------------------------------------------------

-- WoW Forever's flight points, yours (your faction's and the neutral ones), each a spot on the map where its flight
-- master stands: Enter opens the map there with a pin (as an instance entrance does), Shift+Enter only sets the pin.
-- Each says whether this character has learned it:
--   - a flight master's map: when one opens (TAXIMAP_OPENED) every node it lists is read with the game's word on it
--     (TaxiNodeGetType) and kept per character (db.flights[GUID]), with the continent it was read on. This client's map
--     is the newer one ("Flight Map"): CURRENT, REACHABLE and UNREACHABLE are nodes you know; DISTANT ones you don't (the
--     map hides them unless a route passes through), and it lists other continents' nodes too, which say nothing there.
--     (The classic map shows DISTANT nodes: there they're known, and only NONE isn't.) A flight path is learned at its
--     flight master, whose map opens then, so what's kept stays true;
--   - else the world map's data (C_TaxiMap.GetTaxiNodesForMap: isUndiscovered), only once it has been seen to tell: it
--     said "undiscovered" of a flight path a flight master's map showed you don't know, and never otherwise than one
--     (on this client it called every node discovered before any flight master's map was opened);
--   - else "not checked yet", which is:unlearned counts in (it may be): "nearest unlearned flight master" lists it, and
--     the footer says no flight master's map has been read on your continent yet (FL.Checked).

local FL = {}
I.Flights = FL

-- The flight points on WoW Forever's maps: { place, the zone in the game's name for it (false: none, "Moonglade"),
-- uiMap, x %, y %, side: "A" Alliance, "H" Horde, "N" both }. From Leatrix Maps' flight point icons
-- (Leatrix_Maps_Icons.lua, its WoW Forever data; private to it, so copied), whose names are the game's own ("Ratchet,
-- The Barrens"). A point both factions have (Booty Bay, Gadgetzan...) is two flight masters a few steps apart.
FL.POINTS = {
	-- Eastern Kingdoms
	{ "Refuge Pointe", "Arathi", 1417, 45.8, 46.1, "A" },
	{ "Hammerfall", "Arathi", 1417, 73.1, 32.6, "H" },
	{ "Kargath", "Badlands", 1418, 4.1, 44.9, "H" },
	{ "Nethergarde Keep", "Blasted Lands", 1419, 65.5, 24.4, "A" },
	{ "The Sepulcher", "Silverpine Forest", 1421, 45.6, 42.4, "H" },
	{ "Chillwind Camp", "Western Plaguelands", 1422, 42.9, 85.0, "A" },
	{ "Light's Hope Chapel", "Eastern Plaguelands", 1423, 71.7, 49.6, "A" },
	{ "Light's Hope Chapel", "Eastern Plaguelands", 1423, 70.4, 47.6, "H" },
	{ "Southshore", "Hillsbrad", 1424, 49.4, 52.1, "A" },
	{ "Tarren Mill", "Hillsbrad", 1424, 60.2, 18.8, "H" },
	{ "Aerie Peak", "The Hinterlands", 1425, 11.1, 46.1, "A" },
	{ "Revantusk Village", "The Hinterlands", 1425, 81.7, 81.9, "H" },
	{ "Thorium Point", "Searing Gorge", 1427, 37.9, 30.4, "A" },
	{ "Thorium Point", "Searing Gorge", 1427, 34.8, 30.6, "H" },
	{ "Morgan's Vigil", "Burning Steppes", 1428, 84.4, 68.3, "A" },
	{ "Flame Crest", "Burning Steppes", 1428, 65.6, 24.2, "H" },
	{ "Darkshire", "Duskwood", 1431, 77.6, 44.4, "A" },
	{ "Thelsamar", "Loch Modan", 1432, 33.9, 50.8, "A" },
	{ "Lakeshire", "Redridge", 1433, 25.3, 59.0, "A" },
	{ "Booty Bay", "Stranglethorn", 1434, 27.5, 77.7, "A" },
	{ "Booty Bay", "Stranglethorn", 1434, 26.8, 77.0, "H" },
	{ "Grom'gol", "Stranglethorn", 1434, 32.5, 29.3, "H" },
	{ "Stonard", "Swamp of Sorrows", 1435, 46.1, 54.7, "H" },
	{ "Sentinel Hill", "Westfall", 1436, 56.6, 52.7, "A" },
	{ "Menethil Harbor", "Wetlands", 1437, 9.5, 59.7, "A" },
	{ "Stormwind", "Elwynn", 1453, 71.6, 72.3, "A" },
	{ "Ironforge", "Dun Morogh", 1455, 55.9, 47.9, "A" },
	{ "Undercity", "Tirisfal", 1458, 63.1, 48.3, "H" },
	{ "Farholde Keep", "Riverglades", 2548, 60.6, 81.6, "A" },
	{ "Rog'mar", "Riverglades", 2548, 59.6, 45.1, "H" },
	-- Kalimdor
	{ "Camp Taurajo", "The Barrens", 1413, 44.5, 59.1, "H" },
	{ "Crossroads", "The Barrens", 1413, 51.5, 30.4, "H" },
	{ "Ratchet", "The Barrens", 1413, 63.1, 37.1, "N" },
	{ "Rut'theran Village", "Teldrassil", 1438, 58.4, 93.9, "A" },
	{ "Auberdine", "Darkshore", 1439, 36.4, 45.6, "A" },
	{ "Astranaar", "Ashenvale", 1440, 34.5, 48.0, "A" },
	{ "Splintertree Post", "Ashenvale", 1440, 73.3, 61.7, "H" },
	{ "Zoram'gar Outpost", "Ashenvale", 1440, 12.2, 33.8, "H" },
	{ "Freewind Post", "Thousand Needles", 1441, 45.0, 49.1, "H" },
	{ "Stonetalon Peak", "Stonetalon Mountains", 1442, 36.5, 7.2, "A" },
	{ "Sun Rock Retreat", "Stonetalon Mountains", 1442, 45.2, 59.9, "H" },
	{ "Nijel's Point", "Desolace", 1443, 64.7, 10.4, "A" },
	{ "Shadowprey Village", "Desolace", 1443, 21.6, 74.0, "H" },
	{ "Feathermoon", "Feralas", 1444, 30.3, 43.3, "A" },
	{ "Thalanaar", "Feralas", 1444, 89.5, 45.9, "A" },
	{ "Camp Mojache", "Feralas", 1444, 75.4, 44.3, "H" },
	{ "Theramore", "Dustwallow Marsh", 1445, 67.5, 51.2, "A" },
	{ "Brackenwall Village", "Dustwallow Marsh", 1445, 35.6, 31.8, "H" },
	{ "Gadgetzan", "Tanaris", 1446, 51.0, 29.3, "A" },
	{ "Gadgetzan", "Tanaris", 1446, 51.6, 25.5, "H" },
	{ "Talrendis Point", "Azshara", 1447, 11.9, 77.5, "A" },
	{ "Valormok", "Azshara", 1447, 22.0, 49.7, "H" },
	{ "Talonbranch Glade", "Felwood", 1448, 62.5, 24.2, "A" },
	{ "Bloodvenom Post", "Felwood", 1448, 34.4, 53.9, "H" },
	{ "Marshal's Refuge", "Un'Goro Crater", 1449, 45.3, 6.0, "N" },
	{ "Moonglade", false, 1450, 47.9, 67.1, "A" },
	{ "Moonglade", false, 1450, 32.2, 66.3, "H" },
	{ "Cenarion Hold", "Silithus", 1451, 50.7, 34.6, "A" },
	{ "Cenarion Hold", "Silithus", 1451, 48.8, 36.7, "H" },
	{ "Everlook", "Winterspring", 1452, 62.3, 36.6, "A" },
	{ "Everlook", "Winterspring", 1452, 60.5, 36.3, "H" },
	{ "Orgrimmar", "Durotar", 1454, 45.3, 63.7, "H" },
	{ "Thunder Bluff", "Mulgore", 1456, 46.7, 49.9, "H" },
	{ "Summit of Eternity", "Mount Hyjal", 2482, 68.6, 44.1, "N" },
	{ "Tainted Foothills", "Mount Hyjal", 2482, 55.1, 82.5, "N" },
}
-- each point's full name as the game says it, and lowercase (the flight masters' maps are kept by that); the points of
-- each name (two for one both sides have)
FL.BY_NAME = {}
for _, p in ipairs(FL.POINTS) do
	p.full = p[2] and (p[1] .. ", " .. p[2]) or p[1]
	p.lfull = Lower(p.full)
	local list = FL.BY_NAME[p.lfull] or {}
	list[#list + 1] = p
	FL.BY_NAME[p.lfull] = list
end
--- The continent a point is on (the game's number, as I.Here gives yours), or nil (no map data).
local function PointCont(p) return (SpotXY(p[3], { p[4], p[5] })) end
--- Is any flight path of that (lowercase) name on that continent?
local function NameOn(l, cont)
	for _, p in ipairs(FL.BY_NAME[l] or {}) do if PointCont(p) == cont then return true end end
	return false
end

local SIDES = { Alliance = "A", Horde = "H" }
local lastSide -- (the last side the game said: a moment it says nothing doesn't list both sides' flight masters)
--- Your side ("A" / "H"), or nil (never said yet: every flight path listed).
function FL.MySide()
	local g = Str(Safe(_G.UnitFactionGroup, "player"))
	if g then lastSide = SIDES[g] end
	return lastSide
end
FL.ForgetSide = function() lastSide = nil end -- (tests)
--- Is a point of this side yours? (neutral ones are everyone's)
local function Fits(side, mine) return not mine or side == "N" or side == mine end

local function Now() return (_G.time and _G.time()) or 0 end
local function MyKey() return Str(Safe(_G.UnitGUID, "player")) end
local function Dirty() local p = ns.providers.flight if p then p._dirty = true end end

--- Every character's note: GUID -> { v, name, class, side, nodes = { [lowercase node name] = known }, conts =
--- { [continent] = when a flight master's map was read there }, t }. Notes of another version are dropped (0.45.1's
--- read the newer map's DISTANT nodes as known: every flight path "learned").
FL.RECORD_V = 2
local function Records()
	local db = ns.db
	if not db then return nil end
	if type(db.flights) ~= "table" then db.flights = {} end
	for k, r in pairs(db.flights) do
		if type(r) ~= "table" or r.v ~= FL.RECORD_V then db.flights[k] = nil end
	end
	return db.flights
end
local function MyRecord()
	local all, key = Records(), MyKey()
	local r = all and key and all[key]
	return type(r) == "table" and r or nil
end
FL.MyRecord = MyRecord

----------------------------------------------------------------------
-- What a flight master's map shows
----------------------------------------------------------------------

--- The flight master's map that is open: { { name, l (lowercase), kind (TaxiNodeGetType's word) } }; nil when it lists
--- none (closed, or a client without the calls).
function FL.ReadTaxiMap()
	local n = Num(Safe(_G.NumTaxiNodes))
	if not n or n <= 0 then return nil end
	local list = {}
	for i = 1, n do
		local name = Str(Safe(_G.TaxiNodeName, i))
		local kind = Str(Safe(_G.TaxiNodeGetType, i))
		if name and kind then list[#list + 1] = { name = name, l = Lower(name), kind = kind } end
	end
	return #list > 0 and list or nil
end

--- Is this client's flight master's map the classic one? (Its DISTANT nodes are ones you know. The newer map, this
--- client's "Flight Map", hides DISTANT nodes, which you don't know, and has UNREACHABLE ones, known but out of reach.)
local function ClassicMap()
	local t = _G.TaxiButtonTypes
	return type(t) == "table" and t.DISTANT ~= nil and t.UNREACHABLE == nil
end
--- A flight master's map's word for a node: true (you know it), false (you don't), nil (it says nothing).
function FL.Known(kind, classic)
	if kind == "CURRENT" or kind == "REACHABLE" or kind == "UNREACHABLE" then return true end
	if kind == "DISTANT" then return classic and true or false end
	if kind == "NONE" then return false end
	return nil
end

--- What a flight master's map showed, into this character's note (other continents' nodes stay as they were), and that
--- a map was read on that continent.
function FL.Keep(nodes, cont)
	local all, key = Records(), MyKey()
	if not (all and key) then return nil end
	local r = all[key]
	if type(r) ~= "table" then r = { v = FL.RECORD_V }; all[key] = r end
	if type(r.nodes) ~= "table" then r.nodes = {} end
	if type(r.conts) ~= "table" then r.conts = {} end
	for l, yes in pairs(nodes) do r.nodes[l] = yes end
	if cont ~= nil then r.conts[cont] = Now() end
	r.name = ns.CharacterName() or r.name
	r.class = Str((select(2, Safe(_G.UnitClass, "player")))) or r.class
	r.side = FL.MySide() or r.side
	r.t = Now()
	return r
end

--- A flight master's map is open: what it shows is kept. "Not known" only of the flight paths on the map's own continent
--- (its CURRENT node's, else where you stand), where the map is the whole story: the other continents' nodes it lists
--- say nothing there. A map that lists only the nodes you know (none not known here) leaves the others out: your points
--- on this continent missing from it are then not known, but only when every node it lists is one of FL.POINTS by name
--- (the names surely match: on another language's client they don't).
function FL.Read()
	local list = FL.ReadTaxiMap()
	if not list then
		ns:Trace("flight paths: a flight master's map opened, no nodes read")
		return nil
	end
	local classic, mine = ClassicMap(), FL.MySide()
	local cont
	for _, n in ipairs(list) do
		if n.kind == "CURRENT" then
			for _, p in ipairs(FL.BY_NAME[n.l] or {}) do cont = cont or PointCont(p) end
		end
	end
	if cont == nil then
		local here = I.Here and I.Here()
		cont = here and here.cont
	end
	local nodes, known, notKnown, elsewhere, named = {}, 0, 0, 0, true
	for _, n in ipairs(list) do
		if not FL.BY_NAME[n.l] then named = false end
		local v = FL.Known(n.kind, classic)
		if v == false and not (cont ~= nil and NameOn(n.l, cont)) then v, elsewhere = nil, elsewhere + 1 end
		if v == true then
			nodes[n.l], known = true, known + 1
		elseif v == false then
			if nodes[n.l] == nil then nodes[n.l] = false end -- (one name twice, the Alliance's and the Horde's: known if either is)
			notKnown = notKnown + 1
		end
	end
	local missing = 0
	if notKnown == 0 and named and cont ~= nil then
		for _, p in ipairs(FL.POINTS) do
			if nodes[p.lfull] == nil and Fits(p[6], mine) and PointCont(p) == cont then
				nodes[p.lfull] = false
				missing = missing + 1
			end
		end
	end
	FL.Keep(nodes, cont)
	ns:Trace(("flight paths: a flight master's map (%s, continent %s): %d nodes, %d known, %d not known here, %d left as they were (another continent's)%s")
		:format(classic and "classic" or "newer", tostring(cont), #list, known, notKnown, elsewhere,
		missing > 0 and (", %d of yours on this continent missing from it (taken as not known)"):format(missing) or ""))
	Dirty()
	return nodes
end

--- Has a flight master's map been read on that continent (or does the world map's data, seen to tell, say)? Then what
--- Terminal says of the flight paths there is what they are; else they're "not checked yet" (FL.trusted: Collect's).
FL.trusted = false
function FL.Checked(cont)
	if cont == nil then return false end
	if FL.trusted then return true end
	local r = MyRecord()
	return (r and type(r.conts) == "table" and r.conts[cont]) and true or false
end
FL.UNCHECKED_NOTE = "not checked here yet: open any flight master's map"

FL.taxiOpen = false
function FL.OnEvent(event)
	if event == "TAXIMAP_OPENED" then
		FL.taxiOpen = true
		FL.Read()
	elseif event == "TAXIMAP_CLOSED" then
		FL.taxiOpen = false
		Dirty() -- (the world map's data may say more now: a flight path just learned)
	elseif event == "TAXI_NODE_STATUS_CHANGED" then
		if FL.taxiOpen then FL.Read() else Dirty() end
	end
end
local ev = CreateFrame("Frame")
for _, name in ipairs({ "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED" }) do pcall(ev.RegisterEvent, ev, name) end
ev:SetScript("OnEvent", function(_, event)
	local ok, err = pcall(FL.OnEvent, event)
	if not ok then ns:Trace("flight paths: " .. tostring(err)) end
end)
FL.frame = ev -- (tests)

----------------------------------------------------------------------
-- What the world map's data says
----------------------------------------------------------------------

local FACTION = { [0] = "N", [1] = "H", [2] = "A" } -- (Enum.FlightPathFaction: Neutral, Horde, Alliance)
local function NodeSide(f)
	local E = _G.Enum and _G.Enum.FlightPathFaction
	if E and f ~= nil then
		if f == E.Alliance then return "A" end
		if f == E.Horde then return "H" end
		if f == E.Neutral then return "N" end
	end
	return f ~= nil and FACTION[f] or nil
end
local function NodeXY(n)
	local p = n.position
	if type(p) ~= "table" then return nil end
	local x, y = p.x, p.y
	if p.GetXY then x, y = p:GetXY() end
	x, y = Num(x), Num(y)
	if not (x and y) then return nil end
	return x * 100, y * 100
end
FL.MATCH = 5 -- (map %: a node this close to a point of its side is that point, whatever its name)

--- The world map's data on each map with a point: point index -> { name = the game's name for it (lowercase),
--- known = true / false / nil }. A node is the point of its map with its name, else the nearest of its side within
--- FL.MATCH. Empty when the client has no such data.
function FL.MapNodes()
	local at = {}
	local T = _G.C_TaxiMap
	if not (T and T.GetTaxiNodesForMap) then return at end
	local byUi = {}
	for i, p in ipairs(FL.POINTS) do
		local list = byUi[p[3]]
		if not list then list = {}; byUi[p[3]] = list end
		list[#list + 1] = i
	end
	for ui, idx in pairs(byUi) do
		local nodes = Safe(T.GetTaxiNodesForMap, ui)
		for _, n in ipairs(type(nodes) == "table" and nodes or {}) do
			local name = type(n) == "table" and Str(n.name)
			local x, y
			if name then x, y = NodeXY(n) end
			if x then
				local l, side = Lower(name), NodeSide(Num(n.faction))
				local best, bestD
				for _, i in ipairs(idx) do
					local p = FL.POINTS[i]
					if not at[i] and (not side or side == "N" or p[6] == "N" or p[6] == side) then
						local d = math.sqrt((p[4] - x) ^ 2 + (p[5] - y) ^ 2)
						if p.lfull == l then d = d - 1000 end -- (its own name first)
						if not bestD or d < bestD then best, bestD = i, d end
					end
				end
				if best and bestD <= FL.MATCH then
					local u, known = n.isUndiscovered, nil
					if not ns.Secret(u) and type(u) == "boolean" then known = not u end
					at[best] = { name = l, known = known }
				end
			end
		end
	end
	return at
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local ICON = { A = "Interface\\Icons\\Ability_Mount_Gryphon_01", H = "Interface\\Icons\\Ability_Mount_Wyvern_01" }
local GREY = "|cff8a8a8a"
FL.RANK = { unlearned = 0.3, unchecked = 0.15, learned = 0 } -- (the list's own order among equal matches: what you lack first)

--- Your other characters' word on a row's flight path (those of its side): { name, who (class-coloured), yes }.
function FL.Alts(e)
	local out, all, me = {}, Records(), MyKey()
	local l = Lower(e.full or e.name)
	for key, r in pairs(all or {}) do
		if key ~= me and type(r) == "table" and type(r.nodes) == "table" and (e.side == "N" or not r.side or r.side == e.side) then
			local v = r.nodes[l]
			if v ~= nil then
				local name = tostring(r.name or "?")
				local hex = ns.ClassHex(r.class)
				out[#out + 1] = { name = name, who = hex and (hex .. name .. "|r") or name, yes = v == true }
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function Tooltip(e, t)
	t:SetText(e.full or e.name, 1, 0.82, 0)
	if e.learned == true then
		t:AddLine("Learned", 0.4, 1, 0.4)
	elseif e.learned == false then
		t:AddLine("Not learned", 1, 0.45, 0.35)
	else
		t:AddLine("Not checked yet", 0.8, 0.8, 0.8)
	end
	if e.how == "flightmaster" then
		local r = MyRecord()
		t:AddLine("As a flight master's map showed it" .. ((r and r.t) and (", " .. ns.Ago(Now() - r.t)) or ""), 0.6, 0.6, 0.6, true)
	elseif e.how == "map" then
		t:AddLine("As the world map's data says (a flight master's map will tell for sure)", 0.6, 0.6, 0.6, true)
	else
		t:AddLine("Talk to any flight master on this continent: its map tells Terminal which you know", 0.6, 0.6, 0.6, true)
	end
	local alts = FL.Alts(e)
	if #alts > 0 then
		t:AddLine("Your other characters:", 0.8, 0.8, 0.8)
		for _, a in ipairs(alts) do
			if a.yes then t:AddDoubleLine(a.who, "learned", 1, 1, 1, 0.4, 1, 0.4)
			else t:AddDoubleLine(a.who, "not learned", 1, 1, 1, 1, 0.45, 0.35) end
		end
	end
	t:AddLine("Enter: show on map    Shift+Enter: set waypoint", 0.6, 0.6, 0.6, true)
end

local STATE = { [true] = "Learned", [false] = "Not learned" }

--- The rows: your flight paths (your side's and the neutral ones), each with what this character knows of it.
function FL.Collect()
	local mine = FL.MySide()
	local rec = MyRecord()
	local nodes = rec and type(rec.nodes) == "table" and rec.nodes or nil
	local at = FL.MapNodes()
	-- what a flight master's map showed of each point (by its name, else by the name the world map's data gives it: a
	-- client in another language), and whether the world map's data says the same wherever both say something
	local said, differ, agreeNot, mapSaid = {}, 0, 0, 0
	for i, p in ipairs(FL.POINTS) do
		local m = at[i]
		local v = nodes and nodes[p.lfull]
		if v == nil and nodes and m then v = nodes[m.name] end
		said[i] = v
		if m and m.known ~= nil then
			mapSaid = mapSaid + 1
			if v ~= nil then
				if v ~= m.known then differ = differ + 1 elseif v == false then agreeNot = agreeNot + 1 end
			end
		end
	end
	-- (the world map's data only once seen to tell: "undiscovered" of one a flight master's map showed you lack, and
	-- never otherwise than one; on this client it called every node discovered before any flight master's map opened)
	local trust = differ == 0 and agreeNot > 0
	FL.trusted = trust
	local rows, counts = {}, { learned = 0, unlearned = 0, unchecked = 0 }
	for i, p in ipairs(FL.POINTS) do
		if Fits(p[6], mine) then
			local learned, how = said[i], nil
			if learned ~= nil then
				how = "flightmaster"
			elseif trust and at[i] and at[i].known ~= nil then
				learned, how = at[i].known, "map"
			end
			local state = learned == nil and "unchecked" or (learned and "learned" or "unlearned")
			counts[state] = counts[state] + 1
			local ui, px, py = p[3], p[4], p[5]
			local cont, x, y = SpotXY(ui, { px, py })
			local zone = ZoneName(ui) or p[2] or p[1]
			rows[#rows + 1] = {
				name = p[1], key = p.lfull .. "|" .. p[6], full = p.full, side = p[6],
				icon = ICON[p[6]] or ICON[mine or "A"], color = learned == false and GREY or nil,
				detail = (STATE[learned] or "Not checked yet") .. "  ·  " .. zone, zone = zone,
				-- (after the distance in a "nearest" list: "120 yd  The Barrens  ·  not checked yet")
				distNote = learned == nil and (zone .. "  ·  not checked yet") or zone,
				learned = learned, how = how, _rank = FL.RANK[state],
				friendlyToFaction = p[6] == "N" and "AH" or p[6], -- (faction:, as Questie's NPCs say it)
				text = "flight path flight master taxi " .. p.full .. " " .. zone,
				ui = ui, mapID = ui, px = px, py = py, wcont = cont, wx = x, wy = y,
				pinName = p[1] .. " flight master", what = "flight path",
				secure = ns.Maps.SECURE, isOpen = ns.Maps.IsOpenFor, after = I.SpotAfter, activate = PinObject,
				secondary = PinObject, tooltip = Tooltip,
			}
		end
	end
	local trustText = mapSaid == 0 and "nothing" or (trust and (mapSaid .. " points, used") or (differ > 0
		and ("%d points, not used: it differs from what flight masters' maps showed on %d"):format(mapSaid, differ)
		or ("%d points, not used: not yet seen to tell (it must agree with a flight master's map on one you lack)"):format(mapSaid)))
	ns:Trace(("flight paths: %d of yours, %d learned, %d not, %d not checked yet; the world map's data: %s"):format(#rows,
		counts.learned, counts.unlearned, counts.unchecked, trustText))
	return rows
end

ns:RegisterProvider("flight", {
	label = "Flight path", color = "ffdb4dff",
	aliases = { "flight", "flights", "flightpath", "flightpaths", "fp", "taxi" },
	lazy = true,
	collect = function() return FL.Collect() end,
})

----------------------------------------------------------------------
-- "nearest unlearned flight master" (Simple mode, Search.lua's Scan.NearestStart; Alt+`: Easy.ToAdvanced)
----------------------------------------------------------------------

-- words naming a flight path itself, its flight master, what you know of it, and words that only fill the phrase
FL.PATH_WORDS = { ["flight path"] = true, ["flight paths"] = true, flightpath = true, flightpaths = true,
	["flight point"] = true, ["flight points"] = true, taxi = true }
FL.ROLE_WORDS = { flight = true, fp = true, flightmaster = true }
FL.UNLEARNED_WORDS = { unlearned = true, missing = true, undiscovered = true, unknown = true }
FL.LEARNED_WORDS = { learned = true, known = true, discovered = true }
FL.FILLER = { master = true, masters = true, path = true, paths = true, point = true, points = true }

--- Does a "nearest ..." search ask for flight paths ("nearest unlearned flight master", "closest flight path")? Then the
--- words left to be in their names or zones (a place: "nearest flight path gadgetzan") and "unlearned"/"learned" when
--- one was said; else nil. Yes for a flight path word; for a flight master word with a learned/unlearned word; for a
--- flight master word alone only with no NPCs to look in (no Questie): "nearest flight master" is still its NPCs.
--- (tokens: the search's words; softWords: Simple mode's everyday words, "flight", "unlearned", "flight path"...)
function I.FlightAsked(tokens, softWords, noNpcs)
	local path, role, state = false, false, nil
	local function Look(w)
		if FL.PATH_WORDS[w] then path = true
		elseif FL.ROLE_WORDS[w] then role = true
		elseif FL.UNLEARNED_WORDS[w] then state = "unlearned"
		elseif FL.LEARNED_WORDS[w] then state = state or "learned" end
	end
	for _, w in ipairs(softWords or {}) do Look(w) end
	for _, w in ipairs(tokens or {}) do Look(w) end
	if not (path or (role and (state or noNpcs))) then return nil end
	local rest = {}
	for _, w in ipairs(tokens or {}) do
		if not (FL.PATH_WORDS[w] or FL.ROLE_WORDS[w] or FL.UNLEARNED_WORDS[w] or FL.LEARNED_WORDS[w] or FL.FILLER[w]) then
			rest[#rest + 1] = w
		end
	end
	return rest, state
end

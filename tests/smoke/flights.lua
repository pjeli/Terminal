-- Flight paths (Integrations/Flights.lua, 0.45.1): WoW Forever's flight points as rows pointing at their flight masters,
-- what this character knows of them (a flight master's map; the world map's data) and Simple mode's "nearest unlearned
-- flight master".
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I = ns.Integrations
local FL = I.Flights
local E = ns.Easy
local P = ns.providers.flight

io.write("[flight paths]\n")

local function Has(res, name) for i, e in ipairs(res) do if e.name == name then return i end end end
local function Show(res)
	local t = {}
	for i = 1, math.min(#res, 8) do t[i] = tostring(res[i].name) .. "=" .. tostring(res[i].detail) end
	return table.concat(t, " | ")
end
--- The list made again, by name (a name two sides share: both rows).
local function Rows()
	P._dirty = true
	local by = {}
	for _, e in ipairs(ns:GetEntries(P)) do
		by[e.name] = by[e.name] or {}
		table.insert(by[e.name], e)
	end
	return by
end

-- Kalimdor's maps are on continent 1, the Eastern Kingdoms' on 0; each map 1000 yards across, apart from the others
local function Cont(ui) return (ui == 1413 or (ui >= 1438 and ui <= 1452) or ui == 1454 or ui == 1456 or ui == 2482) and 1 or 0 end
local NAMES = { [1413] = "The Barrens", [1440] = "Ashenvale", [1446] = "Tanaris", [1454] = "Orgrimmar", [1456] = "Thunder Bluff",
	[1458] = "Undercity" }
local where = { map = 1413, x = 0.62, y = 0.38 } -- (in Ratchet)
local guid = "Player-1-FLY1"

local saved = { map = _G.C_Map, taxi = _G.C_TaxiMap, faction = _G.UnitFactionGroup, guid = _G.UnitGUID, cls = _G.UnitClass,
	num = _G.NumTaxiNodes, tname = _G.TaxiNodeName, ttype = _G.TaxiNodeGetType, easy = ns.db.easyMode, flights = ns.db.flights,
	place = ns.Maps.Place, print = ns.Print, providers = ns.providers, order = ns.providerOrder, field = I.NpcField,
	defs = I.NpcFlagDefs, dist = I.NpcDistance, rcc = _G.RAID_CLASS_COLORS, tbt = _G.TaxiButtonTypes }

local function Taxi(list)
	_G.NumTaxiNodes = function() return #list end
	_G.TaxiNodeName = function(i) return list[i] and list[i][1] end
	_G.TaxiNodeGetType = function(i) return list[i] and list[i][2] end
end
local function MapOpened()
	FL.frame.scripts.OnEvent(FL.frame, "TAXIMAP_OPENED")
	FL.frame.scripts.OnEvent(FL.frame, "TAXIMAP_CLOSED")
	_G.NumTaxiNodes = function() return 0 end -- (closed: the game lists nothing)
end

local function Body()
	_G.C_Map = {
		GetWorldPosFromMapPos = function(ui, pos) return Cont(ui), { x = (ui % 100) * 1000 + pos.x * 1000, y = pos.y * 1000 } end,
		GetMapInfo = function(ui) return { name = NAMES[ui] or ("Zone " .. ui) } end,
		GetBestMapForUnit = function() return where.map end,
		GetPlayerMapPosition = function() return where.map and { x = where.x, y = where.y } or nil end,
		CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function() end, HasUserWaypoint = function() return false end, ClearUserWaypoint = function() end,
		OpenWorldMap = function() end,
		GetUserWaypointHyperlink = function() return "|Hworldmap:1413|h[pin]|h" end,
	}
	_G.C_TaxiMap = nil
	_G.UnitFactionGroup = function() return "Horde" end
	_G.UnitGUID = function() return guid end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.NumTaxiNodes, _G.TaxiNodeName, _G.TaxiNodeGetType = nil, nil, nil
	ns.db.flights = {}
	ns.db.easyMode = false
	I._.ResetDistances(); I._.ResetZoneNames(); FL.ForgetSide()

	check(P and ns:ResolveProvider("flight") == P and ns:ResolveProvider("fp") == P and ns:ResolveProvider("taxi") == P
		and ns:ResolveProvider("flightpath") == P, "@flight, @fp, @taxi, @flightpath")

	-- a Horde character's: the Horde's and the neutral ones, nothing known of them yet
	local by = Rows()
	local n = #ns:GetEntries(P)
	check(n == 34 and by["Ratchet"] and by["Orgrimmar"] and by["Marshal's Refuge"] and not by["Astranaar"] and not by["Stormwind"],
		"Horde: the Horde's flight paths and the neutral ones: " .. n)
	check(by["Gadgetzan"] and #by["Gadgetzan"] == 1 and by["Gadgetzan"][1].side == "H", "one both sides have: only the Horde's flight master")
	_G.UnitFactionGroup = function() return nil end -- (a moment the game says nothing: still the Horde's)
	check(#Rows()["Gadgetzan"] == 1 and #ns:GetEntries(P) == 34, "the game saying nothing for a moment: still your side's")
	_G.UnitFactionGroup = function() return "Horde" end
	local r = by["Ratchet"][1]
	check(r.learned == nil and r.detail == "Not checked yet  ·  The Barrens" and r.kind == "flight" and r.ui == 1413 and r.px == 63.1
		and r.wcont == 1, "nothing known yet: " .. tostring(r.detail))
	_G.UnitFactionGroup = function() return "Alliance" end
	by = Rows()
	check(by["Astranaar"] and by["Ratchet"] and not by["Orgrimmar"] and by["Gadgetzan"] and #by["Gadgetzan"] == 1
		and by["Gadgetzan"][1].side == "A", "Alliance: the Alliance's")
	_G.UnitFactionGroup = function() return "Horde" end

	-- nothing known on this continent yet (no flight master's map read here): the nearest are listed, each saying so, and
	-- the footer says so; nothing is claimed
	check(not FL.Checked(1) and not FL.Checked(0), "no continent checked yet")
	P._dirty = true -- (the Horde's list again)
	E.Set(true)
	UI:Open("nearest unlearned flight master")
	local res = UI.Results()
	check(res[1] and res[1].name == "Ratchet" and res[1].detail == "14 yd  The Barrens  ·  not checked yet" and UI.flightNote == FL.UNCHECKED_NOTE
		and res[2] and res[2].name == "Crossroads"
		and (UI.status:GetText() or ""):find(FL.UNCHECKED_NOTE, 1, true), "nothing checked yet: the nearest, each not checked yet, and the footer says so: "
		.. Show(res) .. " / " .. tostring(UI.status:GetText()))
	UI:Hide(); FlushAll()
	UI:Open("nearest learned flight master")
	res = UI.Results()
	check(#res == 1 and res[1].noActivate and res[1].name:find("doesn't know your flight paths here yet", 1, true),
		"learned ones asked for before any check: it can't know yet, and says so: " .. Show(res))
	UI:Hide(); FlushAll()
	-- (the player's first screenshot) the world map's data called every node discovered before any flight master's map
	-- was opened, and "You know every flight path on this continent" came of it: it's not believed until seen to tell
	local ALL = {}
	for _, p in ipairs(FL.POINTS) do
		ALL[#ALL + 1] = { name = p.full, position = { x = p[4] / 100, y = p[5] / 100 }, ui = p[3], isUndiscovered = false,
			faction = (p[6] == "A" and 2) or (p[6] == "H" and 1) or 0 }
	end
	_G.C_TaxiMap = { GetTaxiNodesForMap = function(ui)
		local t = {}
		for _, nd in ipairs(ALL) do if nd.ui == ui then t[#t + 1] = nd end end
		return t
	end }
	UI:Open("nearest unlearned flight master")
	res = UI.Results()
	check(res[1] and res[1].name == "Ratchet" and res[1].learned == nil and not FL.trusted and UI.flightNote == FL.UNCHECKED_NOTE,
		"the world map's data alone, every node \"discovered\": not believed, nothing claimed: " .. Show(res))
	UI:Hide(); FlushAll()
	_G.C_TaxiMap = nil
	ns.db.easyMode = false; UI:EasyChanged()

	-- a flight master's map (this client's newer one): CURRENT, REACHABLE, UNREACHABLE known; DISTANT and NONE not, on its
	-- own continent; one name twice: known if either is
	Taxi({
		{ "Orgrimmar, Durotar", "REACHABLE" }, { "Crossroads, The Barrens", "CURRENT" }, { "Ratchet, The Barrens", "DISTANT" },
		{ "Camp Taurajo, The Barrens", "NONE" }, { "Gadgetzan, Tanaris", "REACHABLE" }, { "Gadgetzan, Tanaris", "DISTANT" },
		{ "Astranaar, Ashenvale", "NONE" },
	})
	ns:GetEntries(P)
	FL.frame.scripts.OnEvent(FL.frame, "TAXIMAP_OPENED")
	local rec = ns.db.flights[guid]
	check(rec and rec.nodes["ratchet, the barrens"] == false and rec.nodes["camp taurajo, the barrens"] == false
		and rec.nodes["crossroads, the barrens"] == true and rec.nodes["gadgetzan, tanaris"] == true and rec.side == "H"
		and rec.class == "WARRIOR" and rec.v == FL.RECORD_V, "a flight master's map is kept (Gadgetzan: the Horde's known, the Alliance's not)")
	check(FL.Checked(1) and not FL.Checked(0), "the continent it was read on is checked, the other not")
	check(P._dirty, "the list is to be made again")
	FL.frame.scripts.OnEvent(FL.frame, "TAXIMAP_CLOSED")
	_G.NumTaxiNodes = function() return 0 end
	by = Rows()
	r = by["Ratchet"][1]
	check(r.learned == false and r.detail == "Not learned  ·  The Barrens" and r.color, "Ratchet: not learned, greyed: " .. tostring(r.detail))
	check(by["Crossroads"][1].learned == true and by["Crossroads"][1].detail == "Learned  ·  The Barrens"
		and by["Gadgetzan"][1].learned == true, "Crossroads and Gadgetzan: learned")
	check(by["Thunder Bluff"][1].learned == nil, "one that map didn't list: not checked yet")

	-- Simple mode: the closest flight paths you lack, how far (this continent checked: the footer says nothing more)
	E.Set(true)
	for _, q in ipairs({ "nearest unlearned flight master", "nearest unlearned flightmaster", "closest missing flight path",
		"unlearned flight master nearby", "nearest undiscovered fp" }) do
		UI:Open(q)
		res = UI.Results()
		check(res[1] and res[1].name == "Ratchet" and res[1].kind == "flight" and res[1].detail == "14 yd  The Barrens"
			and res[2] and res[2].name == "Camp Taurajo" and UI.flightNote == nil, q .. ": the closest flight path you lack first: " .. Show(res))
		check(not Has(res, "Crossroads") and not Has(res, "Orgrimmar"), q .. ": none you know")
		UI:Hide(); FlushAll()
	end
	UI:Open("nearest unlearned flight master")
	res = UI.Results()
	check(res[3] and res[3].learned == nil and res[3].detail:find("  ·  not checked yet$"),
		"one not checked yet is listed too, and says so: " .. tostring(res[3] and res[3].detail))
	UI:Hide(); FlushAll()
	UI:Open("nearest flight path gadgetzan")
	res = UI.Results()
	check(#res == 1 and res[1].name == "Gadgetzan", "a name with it: that one: " .. Show(res))
	UI:Hide(); FlushAll()
	-- Alt+`: the flight paths' list, not NPCs
	check(E.ToAdvanced("nearest unlearned flight master") == "@flight is:unlearned sort:nearest ",
		"Alt+`: " .. E.ToAdvanced("nearest unlearned flight master"))
	check(E.ToAdvanced("closest missing flight path") == "@flight is:unlearned sort:nearest ",
		"Alt+`: " .. E.ToAdvanced("closest missing flight path"))
	local adv = E.ToAdvanced("nearest flight path gadgetzan")
	check(adv:find("^@flight ") and adv:find("gadgetzan", 1, true) and adv:find("sort:nearest $"), "Alt+`, a name kept: " .. adv)
	-- every one of them, those you lack first
	UI:Open("unlearned flight paths")
	res = UI.Results()
	local all = #res > 0
	for _, e in ipairs(res) do all = all and e.kind == "flight" and e.learned ~= true end
	check(all and UI.category == "places" and Has(res, "Ratchet") and Has(res, "Thunder Bluff") and not Has(res, "Crossroads"),
		"unlearned flight paths: those you lack and those not checked, under Places: " .. Show(res))
	check(res[1] and res[1].learned == false, "those surely not learned first")
	check(E.ToAdvanced("unlearned flight paths", "places", E.ShownKinds(res)) == "@flight is:unlearned is:flightpath ",
		"Alt+`: " .. E.ToAdvanced("unlearned flight paths", "places", E.ShownKinds(res)))
	UI:Hide(); FlushAll()

	-- Advanced: @flight with sort:nearest, is:, faction:, in:, near:
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("@flight is:unlearned sort:nearest")
	check(res[1] and res[1].name == "Ratchet" and res[1].detail == "14 yd  The Barrens" and res[2] and res[2].name == "Camp Taurajo"
		and not Has(res, "Crossroads"), "@flight is:unlearned sort:nearest: " .. Show(res))
	check(res[3] and res[3].learned == nil and res[3].detail:find(" yd  Ashenvale  ·  not checked yet$"),
		"one not checked yet says so after its distance: " .. tostring(res[3] and res[3].detail))
	check(not res[#res].detail:find(" yd", 1, true), "another continent's after them, with no distance: " .. tostring(res[#res].detail))
	check(#UI:Search("@flight is:learned") == 3, "is:learned: Orgrimmar, Crossroads, Gadgetzan: " .. Show(UI:Search("@flight is:learned")))
	check(#UI:Search("@flight faction:neutral") == 4, "faction:neutral: the neutral ones: " .. Show(UI:Search("@flight faction:neutral")))
	check(#UI:Search("@flight in:barrens") == 3, "in:barrens: the Barrens' three: " .. Show(UI:Search("@flight in:barrens")))
	local near = UI:Search("@flight near:200")
	check(#near == 2 and Has(near, "Ratchet") and Has(near, "Crossroads"), "near:200: " .. Show(near))
	local list = UI:Search("@flight")
	check(list[1].learned == false and list[#list].learned == true, "@flight: those you lack first, those you know last")
	check(UI.flightNote == nil, "a flight master's map read on this continent: the footer has nothing to add")

	-- Enter: the game opens the map on it; Shift+Enter: only a waypoint; sent with a pin
	by = Rows()
	r = by["Ratchet"][1]
	local m = ns.Secure.Resolve(r.secure, r)
	check(m and m.macro == "/run C_Map.OpenWorldMap(1413)", "Enter: the game opens the map on Ratchet: " .. tostring(m and m.macro))
	local placed, printed
	ns.Maps.Place = function(e) placed = e return "set" end
	ns.Print = function(_, s) printed = s end
	r.secondary(r)
	ns.Maps.Place, ns.Print = saved.place, saved.print
	check(placed and placed.mapID == 1413 and math.abs(placed.pos.x - 0.631) < 1e-6 and printed == "Waypoint set on Ratchet flight master (The Barrens)",
		"Shift+Enter: a waypoint on its flight master: " .. tostring(printed))
	local v1, v2 = E.Verbs(r)
	check(v1 == "show on map" and v2 == "set waypoint", "verbs: show on map, set waypoint")
	local line = ns.Share.Line(r, "@flight is:unlearned sort:nearest")
	check(line == "Nearby flight path: Ratchet flight master |Hworldmap:1413|h[pin]|h", "sent to chat: " .. tostring(line))

	-- the tooltip: what's known, where from, your other characters' (a neutral one: both sides')
	ns.db.flights["Player-1-ALT1"] = { v = FL.RECORD_V, name = "Plamen Orc", class = "SHAMAN", side = "H",
		nodes = { ["ratchet, the barrens"] = true, ["crossroads, the barrens"] = false } }
	ns.db.flights["Player-1-ALT2"] = { v = FL.RECORD_V, name = "Plamen Pally", class = "PALADIN", side = "A",
		nodes = { ["ratchet, the barrens"] = false, ["crossroads, the barrens"] = true } }
	_G.RAID_CLASS_COLORS = nil
	local lines = {}
	local tip = { SetText = function(_, s) lines[#lines + 1] = s end, AddLine = function(_, s) lines[#lines + 1] = s end,
		AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. "=" .. b end }
	r.tooltip(r, tip)
	local text = table.concat(lines, "\n")
	check(lines[1] == "Ratchet, The Barrens" and lines[2] == "Not learned" and text:find("flight master's map", 1, true)
		and text:find("Plamen Orc=learned", 1, true) and text:find("Plamen Pally=not learned", 1, true), "the tooltip: " .. text)
	lines = {}
	by["Crossroads"][1].tooltip(by["Crossroads"][1], tip)
	text = table.concat(lines, "\n")
	check(text:find("Plamen Orc=not learned", 1, true) and not text:find("Plamen Pally", 1, true), "a Horde one: only Horde alts: " .. text)
	_G.RAID_CLASS_COLORS = saved.rcc

	-- "nearest flight master" is still Questie's NPCs when there are some; flight paths when not, or asked unlearned
	check(I.FlightAsked({ "master" }, { "flight" }, false) == nil and #I.FlightAsked({ "master" }, { "flight" }, true) == 0
		and #I.FlightAsked({ "master" }, { "unlearned", "flight" }, false) == 0, "which \"nearest\" asks for flight paths")
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("flight", P)
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = function()
		return { { name = "Bragok", key = 16227, npcID = 16227, text = "Flight Master", activate = function() end } }
	end })
	I.NpcDistance = function(id) return id == 16227 and 20 or nil end
	I.NpcField = function(id, f) if id == 16227 then return ({ npcFlags = 8, friendlyToFaction = "AH" })[f] end end
	I.NpcFlagDefs = function() return { FLIGHT_MASTER = 8 } end
	ns.Filters.ClearCache()
	UI.lastScan, UI.lastOverview = nil, nil
	E.Set(true)
	UI:Open("nearest flight master")
	res = UI.Results()
	check(res[1] and res[1].name == "Bragok" and res[1].kind == "npc", "nearest flight master: Questie's flight masters, as before: " .. Show(res))
	UI:Hide(); FlushAll()
	UI:Open("nearest unlearned flight master")
	res = UI.Results()
	check(res[1] and res[1].name == "Ratchet" and res[1].kind == "flight", "nearest unlearned flight master: the flight paths: " .. Show(res))
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("flight", P)
	UI.lastScan, UI.lastOverview = nil, nil
	UI:Open("nearest flight master")
	res = UI.Results()
	check(res[1] and res[1].name == "Ratchet" and Has(res, "Crossroads"), "no NPCs to look in: every flight path, closest first: " .. Show(res))
	UI:Hide(); FlushAll()
	check(E.ToAdvanced("nearest flight master") == "@flight sort:nearest ", "Alt+` then: " .. E.ToAdvanced("nearest flight master"))
	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	I.NpcField, I.NpcFlagDefs, I.NpcDistance = saved.field, saved.defs, saved.dist
	ns.Filters.ClearCache()
	UI.lastScan, UI.lastOverview = nil, nil

	-- the world map's data: believed only once seen to tell (it said "undiscovered" of one a flight master's map showed you
	-- lack, and never otherwise than one)
	guid = "Player-1-FLY2"
	ns.db.flights = {}
	local NODES = {
		{ nodeID = 80, name = "Ratchet, The Barrens", position = { x = 0.631, y = 0.371 }, faction = 0, isUndiscovered = false },
		{ nodeID = 22, name = "Camp Taurajo, The Barrens", position = { x = 0.445, y = 0.591 }, faction = 1, isUndiscovered = true },
		{ nodeID = 25, name = "Wegkreuz, Brachland", position = { x = 0.514, y = 0.305 }, faction = 1, isUndiscovered = false },
	}
	_G.C_TaxiMap = { GetTaxiNodesForMap = function(ui) return ui == 1413 and NODES or {} end }
	by = Rows()
	check(by["Ratchet"][1].learned == nil and by["Camp Taurajo"][1].learned == nil and by["Crossroads"][1].learned == nil
		and not FL.trusted, "the world map's data alone: not yet seen to tell, not used")
	ns.db.flights[guid] = { v = FL.RECORD_V, side = "H", conts = { [1] = 1 }, nodes = { ["camp taurajo, the barrens"] = false } }
	by = Rows()
	check(FL.trusted and by["Ratchet"][1].learned == true and by["Ratchet"][1].how == "map" and by["Crossroads"][1].learned == true
		and by["Camp Taurajo"][1].how == "flightmaster", "seen to tell: used where no flight master's map said (Crossroads by where it is, in another language's name)")
	check(by["Thunder Bluff"][1].learned == nil and FL.Checked(0), "nothing said of it: not checked yet; believed, it stands for every continent")
	-- a flight master's map read in that language: kept by the game's name, found through the world map's data
	ns.db.flights[guid] = { v = FL.RECORD_V, side = "H", conts = { [1] = 1 },
		nodes = { ["wegkreuz, brachland"] = false, ["camp taurajo, the barrens"] = false } }
	by = Rows()
	check(by["Crossroads"][1].learned == false and by["Crossroads"][1].how == "flightmaster",
		"a flight master's map in another language: found by the game's name for it")
	check(not FL.trusted and by["Ratchet"][1].learned == nil, "the world map's data said otherwise than a flight master's map: not used at all")
	_G.C_TaxiMap = nil

	-- a flight master's map that lists only the nodes you know: the rest of this continent's yours are not known
	guid = "Player-1-FLY3"
	ns.db.flights = {}
	Taxi({ { "Orgrimmar, Durotar", "REACHABLE" }, { "Crossroads, The Barrens", "CURRENT" }, { "Thunder Bluff, Mulgore", "REACHABLE" } })
	MapOpened()
	by = Rows()
	check(by["Ratchet"][1].learned == false and by["Camp Taurajo"][1].learned == false and by["Crossroads"][1].learned == true
		and by["Undercity"][1].learned == nil, "only the known ones listed: this continent's others not known, another continent's not checked")
	-- with a name Terminal doesn't know among them: the names may not match, so nothing is taken as not known
	guid = "Player-1-FLY4"
	Taxi({ { "Orgrimmar, Durotar", "REACHABLE" }, { "Somewhere New, Nowhere", "CURRENT" } })
	MapOpened()
	by = Rows()
	check(by["Ratchet"][1].learned == nil and by["Orgrimmar"][1].learned == true, "a name it doesn't know: nothing taken as not known")

	-- (the player's second screenshot) the newer map at Orgrimmar lists both continents' nodes: Bloodvenom Post and
	-- Brackenwall Village DISTANT (hidden: not learned), Booty Bay the other continent's (says nothing there), Undercity
	-- known but out of reach. Every one of them had come out "learned".
	guid = "Player-1-FLY6"
	Taxi({ { "Orgrimmar, Durotar", "CURRENT" }, { "Crossroads, The Barrens", "REACHABLE" }, { "Bloodvenom Post, Felwood", "DISTANT" },
		{ "Brackenwall Village, Dustwallow Marsh", "DISTANT" }, { "Booty Bay, Stranglethorn", "DISTANT" },
		{ "Booty Bay, Stranglethorn", "DISTANT" }, { "Undercity, Tirisfal", "UNREACHABLE" } })
	where.map = nil -- (where you stand unknown for a moment: the map's CURRENT node says which continent it is)
	MapOpened()
	where.map = 1413
	by = Rows()
	check(by["Bloodvenom Post"][1].learned == false and by["Brackenwall Village"][1].learned == false and by["Crossroads"][1].learned == true
		and by["Orgrimmar"][1].learned == true, "the newer map: DISTANT is not learned")
	check(by["Booty Bay"][1].learned == nil and by["Undercity"][1].learned == true, "another continent's: DISTANT says nothing, UNREACHABLE is known")
	check(FL.Checked(1) and not FL.Checked(0), "this continent checked, the other not")
	-- the classic map (no UNREACHABLE): its DISTANT nodes are ones you know, NONE ones you don't
	_G.TaxiButtonTypes = { CURRENT = {}, REACHABLE = {}, DISTANT = {} }
	guid = "Player-1-FLY7"
	Taxi({ { "Orgrimmar, Durotar", "CURRENT" }, { "Crossroads, The Barrens", "DISTANT" }, { "Ratchet, The Barrens", "NONE" } })
	MapOpened()
	_G.TaxiButtonTypes = saved.tbt
	by = Rows()
	check(by["Crossroads"][1].learned == true and by["Ratchet"][1].learned == false, "the classic map: DISTANT known, NONE not")
	-- a note from 0.45.1 (it read DISTANT as known): dropped
	guid = "Player-1-FLY8"
	ns.db.flights[guid] = { nodes = { ["ratchet, the barrens"] = true } }
	by = Rows()
	check(by["Ratchet"][1].learned == nil and ns.db.flights[guid] == nil, "an older note: dropped")
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("@flight")
	check(#res > 0 and UI.flightNote == FL.UNCHECKED_NOTE, "@flight with no flight master's map read on this continent: the footer says so")

	-- every one known: says so; none like that: says so; nowhere: says so
	guid = "Player-1-FLY5"
	local nodes = {}
	for _, p in ipairs(FL.POINTS) do nodes[p.lfull] = true end
	ns.db.flights[guid] = { v = FL.RECORD_V, side = "H", conts = { [1] = 1 }, nodes = nodes }
	P._dirty = true
	E.Set(true)
	UI:Open("nearest unlearned flight master")
	res = UI.Results()
	check(#res == 1 and res[1].noActivate and res[1].name == "You know every flight path on this continent.", "all known: " .. Show(res))
	UI:Hide(); FlushAll()
	UI:Open("nearest unlearned flight master zzz")
	res = UI.Results()
	check(#res == 1 and res[1].name == "No flight path like that on this continent.", "none like that: " .. Show(res))
	UI:Hide(); FlushAll()
	where.map = nil
	UI:Open("nearest unlearned flight master")
	res = UI.Results()
	check(res[1] and res[1].noActivate and res[1].name:find("where you are", 1, true), "no position: says so: " .. Show(res))
	UI:Hide(); FlushAll()
	where.map = 1413
end

local ok, err = pcall(Body)
_G.C_Map, _G.C_TaxiMap, _G.UnitFactionGroup, _G.UnitGUID, _G.UnitClass = saved.map, saved.taxi, saved.faction, saved.guid, saved.cls
_G.NumTaxiNodes, _G.TaxiNodeName, _G.TaxiNodeGetType = saved.num, saved.tname, saved.ttype
ns.db.flights = saved.flights
ns.Maps.Place, ns.Print = saved.place, saved.print
ns.providers, ns.providerOrder = saved.providers, saved.order
ns:AliasesChanged()
I.NpcField, I.NpcFlagDefs, I.NpcDistance = saved.field, saved.defs, saved.dist
_G.RAID_CLASS_COLORS, _G.TaxiButtonTypes = saved.rcc, saved.tbt
FL.taxiOpen, FL.trusted = false, false
I._.ResetDistances(); I._.ResetZoneNames(); FL.ForgetSide()
UI:Hide(); FlushAll()
UI.category, UI.lastScan, UI.lastOverview = nil, nil, nil
ns.db.easyMode = saved.easy
UI:EasyChanged()
ns.Filters.ClearCache()
P._dirty = true
if not ok then check(false, "flight paths: " .. tostring(err)) end

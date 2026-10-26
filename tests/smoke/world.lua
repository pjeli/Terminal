-- The world: map places and waypoints, Questie's NPCs on the map, towns, AtlasLoot's saved index, keybindings and panels
-- (0.49.2 review fixes: Maps.lua, Questie.lua, QuestieQuests.lua, QuestieData.lua, Places.lua, Loot.lua, Keybinds.lua,
-- Panels.lua, Simple.lua's map verbs).
local T = ...
local ns, UI, check, Obj, FlushAll = T.ns, T.UI, T.check, T.Obj, T.FlushAll
local I, QD, M, S = ns.Integrations, ns.QuestieData, ns.Maps, ns.Secure

local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end
local function Entity(rows)
	local ids = {}
	for id in pairs(rows) do ids[#ids + 1] = id end
	table.sort(ids)
	return {
		Get = function(id, field) return rows[id] and rows[id][field] end,
		GetAllIds = function() return ids end,
	}
end
local function Fresh()
	I.npc.on, I.npc.list, I.npc.names, I.npc.busy = false, nil, nil, false
	I.qdb.list, I.qdb.names, I.qdb.busy = nil, nil, false
	drop("npc"); drop("questie"); drop("mailbox")
	QD.ResetForTests()
	ns.Filters.ClearCache()
	I.ResetPlacesForTests()
end
local function Traced(text)
	for _, l in ipairs(ns.Debug.trace) do if l.msg:find(text, 1, true) then return true end end
	return false
end
-- (the trace keeps its last lines only: emptied first, so what a block looks for is its own)
local function ClearTrace() local tr = ns.Debug.trace for i = #tr, 1, -1 do tr[i] = nil end end
local function UMP() return { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end } end

io.write("[world: a place that takes no waypoint leaves yours alone]\n")
do -- (Maps.lua's Place cleared your waypoint before asking whether the new place takes one: "@map Kalimdor" lost it)
	local save = { map = _G.C_Map, ump = _G.UiMapPoint, print = ns.Print }
	local pinned, calls, said = true, {}, {}
	_G.C_Map = {
		HasUserWaypoint = function() return pinned end,
		ClearUserWaypoint = function() calls[#calls + 1] = "clear"; pinned = false end,
		CanSetUserWaypointOnMap = function(id) return id ~= 1414 end, -- (Kalimdor, a continent: no waypoints)
		SetUserWaypoint = function(p) calls[#calls + 1] = "set " .. tostring(p.uiMapID); pinned = true end,
	}
	_G.UiMapPoint = UMP()
	ns.Print = function(_, m) said[#said + 1] = m end
	local r = M.Place({ name = "Kalimdor", mapID = 1414 })
	check(r == nil and #calls == 0 and pinned, "a continent: nothing set, and your waypoint stays: " .. table.concat(calls, ", "))
	M.PinOnly({ name = "Kalimdor", mapID = 1414 })
	check(pinned and #calls == 0 and said[#said] == "Can't set a waypoint there.", "Shift+Enter on it says so, yours kept: " .. tostring(said[#said]))
	r = M.Place({ name = "Durotar", mapID = 1411 })
	check(r == "moved" and table.concat(calls, ",") == "clear,set 1411", "a zone: your waypoint moves there: " .. table.concat(calls, ","))
	-- (the footer's verbs as PinOnly does it: a zone moves a waypoint you have, sets none; Simple.lua)
	local function V(e) local a, b = ns.Easy.Verbs(e) return tostring(a) .. "/" .. tostring(b) end
	local zone = { kind = "maps", name = "Durotar", mapID = 1411, secondary = M.PinOnly }
	pinned = false
	check(V(zone) == "show on map/nil", "a zone with no waypoint set: Shift+Enter isn't offered (it would set nothing): " .. V(zone))
	pinned = true
	check(V(zone) == "show on map/move waypoint", "with one set: move waypoint: " .. V(zone))
	check(V({ kind = "maps", name = "Kalimdor", mapID = 1414, secondary = M.PinOnly }) == "show on map/nil", "a continent: none")
	check(V({ kind = "maps", name = "Ratchet", mapID = 1413, pos = { x = 0.6, y = 0.4 }, secondary = M.PinOnly }) == "show on map/set waypoint",
		"a spot of its own: set waypoint")
	ns.Print, _G.C_Map, _G.UiMapPoint = save.print, save.map, save.ump
end

io.write("[world: Questie's NPCs on the map: the spawn the row measures, nothing pressed with none]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, map = _G.C_Map, ump = _G.UiMapPoint,
		wmf = _G.WorldMapFrame, print = ns.Print, bn = _G.BINDING_NAME_TOGGLEWORLDMAP, mmb = _G.MiniMapWorldMapButton }
	_G.Questie, _G.QuestieLoader = nil, nil
	-- (the map key and the minimap's map button are there: what a press of an NPC with no spot fell back to)
	_G.BINDING_NAME_TOGGLEWORLDMAP, _G.MiniMapWorldMapButton = "Toggle World Map", Obj("Button")
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	_G.LibQuestieDB = {
		Quest = Entity({
			[500] = { name = "An Object's Quest", questLevel = 10, zoneOrSort = 12, startedBy = { nil, { 31 } } },
			[501] = { name = "The Guard's Errand", questLevel = 10, zoneOrSort = 12, startedBy = { { 68 } } },
		}),
		Npc = Entity({
			-- a guard in Elwynn (12: one spawn far, one near you) and in Westfall (40)
			[68] = { name = "Stormwind City Guard", spawns = { [40] = { { 50, 50 } }, [12] = { { 90, 10 }, { 30, 80 } } } },
			[69] = { name = "Nowhere Man", spawns = {} },
			-- in a dungeon (area 5, its door in Westfall) and out in Elwynn; and only in the dungeon
			[71] = { name = "Defias Messenger", spawns = { [5] = { { 50, 50 } }, [12] = { { 40, 60 } } } },
			[72] = { name = "Defias Overseer", spawns = { [5] = { { 50, 50 } } } },
		}),
		Item = Entity({}),
		flavor = { rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = {} } } },
		Support = { Get = function(name)
			if name ~= "ZoneDB" then return nil end
			return { private = { areaIdToUiMapId = "return { [12] = 1429, [40] = 1436, [5] = 0 }",
				dungeons = { [5] = { "Test Mines", nil, 40, { { 40, 42.6, 71.7 } } } } } }
		end },
	}
	local placed
	local where = 1429
	_G.C_Map = {
		OpenWorldMap = function() end,
		HasUserWaypoint = function() return false end, CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function(pt) placed = pt end, GetUserWaypointHyperlink = function() return "pin" end,
		GetBestMapForUnit = function() return where end,
		GetPlayerMapPosition = function() return { x = 0.30, y = 0.79 } end,
		GetWorldPosFromMapPos = function(map, p) return 1, { x = p.x * 1000 + (map == 1436 and 5000 or 0), y = p.y * 1000 } end,
		GetMapInfo = function(ui) return { name = ui == 1429 and "Elwynn Forest" or "Westfall" } end,
		GetAreaInfo = function() return nil end,
	}
	_G.UiMapPoint = UMP()
	_G.WorldMapFrame = _G.WorldMapFrame or Obj("Frame")
	Fresh()
	I.Setup(); FlushAll()
	local Loc = I._.NpcLocation
	-- where you are known: the spawn the "N yd" column and the arrow use (the nearest on your continent)
	local d = I.NpcDistance(68, I.Here())
	local row = I.NpcRow(68)
	check(d and math.floor(d + 0.5) == 10 and row and row.mapTarget == 1429, "Enter shows the zone of the spawn 10 yd away: "
		.. tostring(row and row.mapTarget))
	placed = nil
	I.NpcPinLink({ npcID = 68, name = "Stormwind City Guard" })
	check(placed and placed.uiMapID == 1429 and math.abs(placed.position.x - 0.30) < 1e-6 and math.abs(placed.position.y - 0.80) < 1e-6,
		">> party links that spawn: " .. tostring(placed and placed.uiMapID) .. " " .. tostring(placed and placed.position.x) .. "," .. tostring(placed and placed.position.y))
	local r = S.Resolve(row.secure, row)
	check(r and r.macro == "/run C_Map.OpenWorldMap(1429)", "and Enter's press opens the map there: " .. tostring(r and r.macro))
	-- not known (an instance): the areas in order, one out in the world before a dungeon's door
	where = nil
	local ui, pos, door = Loc(71)
	check(ui == 1429 and pos and pos.x == 0.40 and not door, "where you are unknown: a spawn in the world before a dungeon's door: " .. tostring(ui))
	ui, pos, door = Loc(72)
	check(ui == 1436 and pos and math.abs(pos.x - 0.426) < 1e-6 and door == true, "only in the dungeon: its door: " .. tostring(ui))
	where = 1429
	-- no known spot: nothing pressed (the map key opened your own zone first), Enter only says so
	local nobody = I.NpcRow(69)
	check(nobody and S.Resolve(nobody.secure, nobody) == nil and UI.ClickFor(nobody, false) == nil,
		"an NPC with no known spot: no map key, no click on the map button")
	said = {}
	nobody.activate(nobody)
	check(said[#said] == "Questie has no known location for Nowhere Man.", "Enter says Questie doesn't know where: " .. tostring(said[#said]))
	local q = I.QuestRow(500)
	local view = q and UI.SecureView(q, true)
	check(view and S.Resolve(view.secure, view) == nil and UI.ClickFor(q, true) == nil, "a quest an object starts: Shift+Enter presses nothing")
	said = {}
	q.secondary(q)
	check(said[#said] == "An Object's Quest is started by an object.", "and says what starts it: " .. tostring(said[#said]))
	local q2 = I.QuestRow(501)
	local v2 = q2 and UI.SecureView(q2, true)
	local r2 = v2 and S.Resolve(v2.secure, v2)
	check(r2 and r2.macro == "/run C_Map.OpenWorldMap(1429)", "one an NPC starts: Shift+Enter opens the map on the giver: " .. tostring(r2 and r2.macro))
	ns.Print = save.print
	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB, _G.C_Map, _G.UiMapPoint = save.Q, save.L, save.Lib, save.map, save.ump
	_G.WorldMapFrame, _G.BINDING_NAME_TOGGLEWORLDMAP, _G.MiniMapWorldMapButton = save.wmf, save.bn, save.mmb
	I.Setup(); FlushAll()
end

io.write("[world: Questie's ZoneDB: 0 is no map, each area asked once]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader }
	local imports, asks = 0, 0
	local QZ = { GetUiMapIdByAreaId = function(_, a) asks = asks + 1; return ({ [12] = 1429, [1581] = 0 })[a] end,
		GetDungeonLocation = function() return nil end }
	_G.Questie = { API = { isReady = true } }
	_G.QuestieLoader = { ImportModule = function(_, n) imports = imports + 1; if n == "ZoneDB" then return QZ end end }
	QD.ResetForTests()
	check(QD.UiMapOfArea(1581) == nil, "Questie's ZoneDB saying 0: no map, as QuestieDB's tables say it")
	check(QD.UiMapOfArea(12) == 1429, "a map it knows")
	imports, asks = 0, 0
	for _ = 1, 50 do QD.UiMapOfArea(12); QD.UiMapOfArea(1581); QD.UiMapOfArea(77) end
	check(imports == 0 and asks == 1, "asked again: the module isn't looked up again, ZoneDB only for the new area: " .. imports .. " / " .. asks)
	-- another Questie (QuestieLoader): looked up again
	local QZ2 = { GetUiMapIdByAreaId = function(_, a) return a == 12 and 1430 or nil end }
	_G.QuestieLoader = { ImportModule = function(_, n) if n == "ZoneDB" then return QZ2 end end }
	check(QD.UiMapOfArea(12) == 1430, "another QuestieLoader: its ZoneDB's answers")
	_G.Questie, _G.QuestieLoader = save.Q, save.L
	QD.ResetForTests()
end

io.write("[world: towns from quest texts: a fight puts the build off, a search meanwhile doesn't do it]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, map = _G.C_Map, cf = _G.CreateFrame,
		combat = _G.InCombatLockdown }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.LibQuestieDB = {
		Quest = Entity({
			[60] = { name = "Report to Goldshire", questLevel = 5, zoneOrSort = 12, finishedBy = { { 240 } },
				objectivesText = { "Speak to Marshal Dughan in Goldshire." } },
		}),
		Npc = Entity({ [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } } } }),
		Item = Entity({}),
		flavor = { rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = {} } } },
		Support = { Get = function(name)
			if name ~= "ZoneDB" then return nil end
			return { private = { areaIdToUiMapId = "return { [12] = 1429, [87] = 1429 }", subZoneToParentZone = "return { [87] = 12 }",
				dungeons = {} } }
		end },
	}
	_G.C_Map = {
		GetAreaInfo = function(a) return ({ [12] = "Elwynn Forest", [87] = "Goldshire" })[a] end,
		GetWorldPosFromMapPos = function(_, p) return 0, { x = p.x * 1000, y = p.y * 1000 } end,
		GetMapInfo = function() return { name = "Elwynn Forest" } end,
	}
	-- frames made meanwhile hear the events they register (the mock's RegisterEvent does nothing)
	local frames = {}
	_G.CreateFrame = function(...)
		local f = save.cf(...)
		f.events = {}
		f.RegisterEvent = function(self, ev) self.events[ev] = true end
		f.UnregisterEvent = function(self, ev) self.events[ev] = nil end
		frames[#frames + 1] = f
		return f
	end
	local fight = false
	_G.InCombatLockdown = function() return fight end
	Fresh()
	I.Setup()
	-- the quests indexed out of combat; the build, 2 s later, comes in a fight
	for _ = 1, 400 do if I.qdb.list then break end T.Flush() end
	check(I.qdb.list and #I.qdb.list == 1, "the quests indexed")
	fight = true
	ClearTrace()
	for _ = 1, 6 do T.Flush() end
	check(not Traced("towns placed from quest texts"), "in a fight: not built")
	check(I.TownsPending(), "meanwhile the towns are still to come (pending), not missing")
	local place = I.FindPlace({ "goldshire" })
	check(place and place.parent == 12, "Goldshire is a part of Elwynn")
	I.NpcInPlace(240, place)
	check(not Traced("towns placed from quest texts"), "a search for a town meanwhile doesn't work them all out on the keystroke")
	-- the fight ends: built in the background
	fight = false
	for _, f in ipairs(frames) do
		if f.events.PLAYER_REGEN_ENABLED and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED") end
	end
	FlushAll()
	check(Traced("places: 1 towns placed from quest texts") and not I.TownsPending(), "after the fight: built in the background")
	check(I.NpcInPlace(240, place) == true, "and Marshal Dughan is in Goldshire")
	_G.CreateFrame, _G.InCombatLockdown = save.cf, save.combat
	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB, _G.C_Map = save.Q, save.L, save.Lib, save.map
	I.Setup(); FlushAll()
end

io.write("[world: AtlasLoot listing no loot modules keeps the saved index]\n")
do
	local loot = I.loot
	local save = { AL = _G.AtlasLoot, cache = ns.db.lootCache }
	local was = {}
	for _, k in ipairs({ "retries", "modules", "loaded", "done", "building", "cached", "byKey", "startedAt" }) do was[k] = loot[k] end
	local good = { key = "v2 AtlasLoot=1 ALDungeons=1", groups = { { "ALDungeons", "DEADMINES", 1, "The Deadmines", "Edwin VanCleef", "1001.1.0" } } }
	ns.db.lootCache = good
	_G.AtlasLoot = { Loader = { GetLootModuleList = function() return { module = {}, custom = {} } end, LoadModule = function() end },
		ItemDB = { Storage = {} } }
	loot.retries = nil
	ClearTrace()
	I.LoadLootModules(); FlushAll()
	check(ns.db.lootCache == good and #good.groups == 1, "no modules listed after the retries: the saved index isn't written over")
	check(Traced("still lists no loot modules"), "and the trace says why nothing was indexed")
	-- (review, 0.57.7) and it's said in chat, .integrations no longer "still loading"
	check(loot.done and I.failed.AtlasLoot and I.failed.AtlasLoot[1].what == ns.L["@loot (its loot tables) is unavailable."],
		"its module list changed: said, not loading forever")
	I.failed.AtlasLoot = nil
	for k, v in pairs(was) do loot[k] = v end
	_G.AtlasLoot, ns.db.lootCache = save.AL, save.cache
	FlushAll()
end

io.write("[world: Quick Keybind Mode started by the Keybindings page's own button]\n")
do
	local K = ns.Keybinds
	local save = { sp = _G.SettingsPanel, st = _G.Settings, u = _G.C_SettingsUtil, qk = _G.QuickKeybindFrame, mab = _G.MainActionBar,
		qkb = _G.SETTINGS_QUICK_KEYBIND_BUTTON, csk = _G.CHARACTER_SPECIFIC_KEYBINDINGS, sec = _G.issecurevariable,
		hl = ns.GameOptions.HighlightSetting, nb = _G.GetNumBindings }
	_G.Settings = { KEYBINDINGS_CATEGORY_ID = 42 }
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.CHARACTER_SPECIFIC_KEYBINDINGS = "Quick Keybind Mode", "Character Specific Keybindings"
	local opened
	_G.C_SettingsUtil = { OpenSettingsPanel = function(id, name) opened = { id, name } end }
	local qk = Obj("Frame"); qk.shown = false
	_G.QuickKeybindFrame = qk
	local bar = {}
	_G.MainActionBar = bar
	local sp = Obj("Frame"); sp.shown = true
	-- the page: the checkbox, the two buttons (Click Cast Bindings, Quick Keybind Mode), a section
	local function Row(data, onClick)
		local f = Obj("Frame"); f.shown = true
		f.GetElementData = function() return { data = data } end
		if onClick then
			local b = Obj("Button"); b.shown = true
			b.Click = function(self) onClick(self) end
			b.IsObjectType = function(_, t) return t == "Button" end
			b.IsEnabled = function() return true end
			b.HasAccessConstraints = function() return false end
			f.Button = b
		end
		return f
	end
	local clicks = 0
	local frames = {
		Row({ name = "Character Specific Keybindings" }),
		Row({ name = "", buttonText = "Click Cast Bindings" }, function() error("the wrong button") end),
		-- (its own code: SettingsPanel:Close(true), then QuickKeybindFrame:Show(), whose OnShow shows every slot)
		Row({ name = "", buttonText = "Quick Keybind Mode" }, function() clicks = clicks + 1; sp.shown = false; qk.shown = true; bar.showAllButtons = 1 end),
		Row({ name = "Movement Keys", expanded = false }, function() end),
	}
	local box = Obj("Frame"); box.shown = true
	box.GetFrames = function() return frames end
	sp.GetSettingsList = function() return { ScrollBox = box } end
	sp.GetCurrentCategory = function() return { GetID = function() return 42 end } end
	_G.SettingsPanel = sp
	ns.db.navTainted = nil
	local q = { key = "quickkeybind", name = "Quick Keybind Mode", rowText = "Quick Keybind Mode" }
	for _, e in ipairs(ns:GetEntries(ns.providers.keybinds)) do if e.key == "quickkeybind" then q = e end end
	local view = UI.SecureView(q, true)
	local r = view and S.Resolve(view.secure, view)
	local text = r and r.macro or ""
	check(text:find('^/run C_SettingsUtil.OpenSettingsPanel%(42,"Character Specific Keybindings"%)\n/click TerminalNav%d'),
		"Shift+Enter: the game opens Keybindings at its top, then steps: " .. text)
	check(not (text:find("HideUIPanel", 1, true) or text:find("ShowUIPanel", 1, true) or text:find("QuickKeybindFrame", 1, true)),
		"no /run line hides the options window or shows Quick Keybind Mode itself (it ran tainted)")
	-- what the game does with it: the line opens the page; each step's PreClick picks a button, the secure button clicks it
	local function RunMacro(m)
		for line in (m .. "\n"):gmatch("([^\n]*)\n") do
			local code = line:match("^/run (.*)$")
			if code then assert(loadstring(code))() end
			local b = line:match("^/click (%S+)") and _G[line:match("^/click (%S+)")]
			if b and b.attrs and b.attrs.type == "click" then
				if b.scripts.PreClick then b.scripts.PreClick(b, "LeftButton", false) end
				local t = b.attrs.clickbutton
				if t then t:Click("LeftButton") end
			end
		end
	end
	local issec = {}
	_G.issecurevariable = function(t, k) local by = issec[t] and issec[t][k] if by then return false, by end return true end
	RunMacro(text)
	check(opened and opened[1] == 42 and qk.shown and not sp.shown and clicks == 1,
		"the page's Quick Keybind Mode button clicked once: the mode on, the options window closed by its own code (" .. clicks .. " clicks)")
	FlushAll()
	check(S.NavOn("keybinds"), "the bars' grid written by the game: the route stays on")
	-- the click's write left tainted: the route goes off, as for the sections
	qk.shown, sp.shown = false, true
	text = S.Resolve(view.secure, view).macro
	RunMacro(text)
	issec[bar] = { showAllButtons = "*** ForceTaint_Strong ***" }
	FlushAll()
	check(not S.NavOn("keybinds"), "the bars' grid left tainted after the click: the route turned off")
	-- off: the page alone, and its button pointed at
	text = S.Resolve(view.secure, view).macro
	check(text == "/run C_SettingsUtil.OpenSettingsPanel(42)", "route off: only the page: " .. text)
	local pointed
	ns.GameOptions.HighlightSetting = function(name) pointed = name end
	qk.shown = false
	view.after(view)
	check(pointed == "Quick Keybind Mode", "and Quick Keybind Mode's button is pointed at: " .. tostring(pointed))
	ns.db.navTainted = nil
	-- the button scrolled away (the page open further down): nothing clicked
	table.remove(frames, 3)
	qk.shown, sp.shown = false, true
	local b, why = K.QuickStep()
	check(b == nil and why == "its button isn't on screen", "its button not on screen: nothing clicked: " .. tostring(why))
	_G.SettingsPanel, _G.Settings, _G.C_SettingsUtil, _G.QuickKeybindFrame, _G.MainActionBar = save.sp, save.st, save.u, save.qk, save.mab
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.CHARACTER_SPECIFIC_KEYBINDINGS, _G.issecurevariable = save.qkb, save.csk, save.sec
	ns.GameOptions.HighlightSetting, _G.GetNumBindings = save.hl, save.nb
	ns.providers.keybinds._dirty = true
	FlushAll()
end

io.write("[world: panel names in the client's language]\n")
do -- (Legacy Rewards had no translation entry: its row was always in English)
	local fakeL = setmetatable({ ["Legacy Rewards"] = "Legacy-Belohnungen", ["Legacy Tree"] = "Legacy-Baum" },
		{ __index = function(_, k) return k end })
	local def
	local proxy = setmetatable({ L = fakeL, RegisterProvider = function(_, id, d) if id == "panels" then def = d end end }, { __index = ns })
	local saveBtn = _G.LegacyMicroButton
	_G.LegacyMicroButton = saveBtn or Obj("Button")
	local chunk = assert(loadfile("Terminal/Providers/Panels.lua"))
	chunk("Terminal", proxy)
	local names = {}
	for _, e in ipairs(def and def.collect(def) or {}) do names[e.key] = e.name end
	check(names["Legacy Tree"] == "Legacy-Baum" and names["Legacy Rewards"] == "Legacy-Belohnungen",
		"Legacy Rewards in the client's language, as its neighbours: " .. tostring(names["Legacy Rewards"]))
	_G.LegacyMicroButton = saveBtn
end

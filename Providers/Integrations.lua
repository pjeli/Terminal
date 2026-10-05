local ns = select(2, ...)
local H = ns.Highlight

-- Other addons, picked up when you log in:
--
--   AtlasLoot (Classic, Forever, or AtlasLoot Continued)  every item in its loot tables becomes searchable
--       ("Loot": item, "Boss  Instance"). Enter opens AtlasLoot on that boss and difficulty
--       and points at the item.
--   Questie  every quest in its database, searched with @questie (Enter: its Wowhead link, ready
--       to copy; Shift+Enter: the quest log for quests you're on, otherwise the quest giver on
--       the map), and NPCs, searched with @npc.
--       Enter opens the world map on the NPC, puts Questie's marker for it there and drops
--       the map pin; Shift+Enter only moves the pin.
--
-- Neither addon is required; with neither installed this file does nothing. .integrations
-- shows what was found.

local I = {}
ns.Integrations = I

local Safe = ns.Safe -- (Util.lua)

----------------------------------------------------------------------
-- AtlasLoot
----------------------------------------------------------------------

local loot = { rows = {}, byKey = {}, pending = {}, unnamed = {}, modules = 0, loaded = 0, on = false }
I.loot = loot

local function AL() return _G.AtlasLoot end

--- AtlasLoot's own addon is loaded and enabled (not just a leftover AtlasLoot table from a
--- plugin or library), with the loot database Terminal reads.
-- AtlasLoot Continued (AtlasLootContinued, its modules AtlasLootContinued_*) has the same API and
-- the same AtlasLoot table as AtlasLootClassic; only its addon names changed.
local CORE = { "AtlasLootContinued", "AtlasLootClassic", "AtlasLoot", "AtlasLootForever" }
--- The name of AtlasLoot's core addon that's loaded, or nil.
local function LoadedCore()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not isLoaded then return nil end
	for _, name in ipairs(CORE) do
		local ok, yes = pcall(isLoaded, name)
		if ok and yes then return name end
	end
end
I.LoadedCore = LoadedCore

local function AtlasLootPresent()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if isLoaded and not LoadedCore() then return false end
	local a = AL()
	return type(a) == "table" and a.ItemDB and a.ItemDB.Storage and a.Loader and true or false
end

--- The item a loot table's row stands for, or nil. The table's type says what its numbers are:
--- items on "Item" pages; crafting spells on profession pages (Smelt Copper, 2657: read as an item
--- id that's "Test Glaive I"), given as the item the spell makes, the way AtlasLoot shows them; set
--- numbers and icons otherwise, which aren't items at all.
local function RowItem(kind, id, A)
	if kind == "Item" then return id end
	if kind == "Profession" then
		local P = A.Data and A.Data.Profession
		local made = P and Safe(P.GetCreatedItemID, id)
		return type(made) == "number" and made > 0 and made or nil
	end
end

-- The index is kept between sessions (db.lootCache), so a /reload doesn't load every loot module
-- again: rows come from the cache at once and a module is loaded only to open its window. It is
-- rebuilt when AtlasLoot, a module, the game version or this format changes (CacheKey).
local CACHE_FORMAT = 1

--- One loot row (compact: shared fields come from loot.meta); its name is filled in once the
--- server has sent it. page: the page the item is on (AtlasLoot shows 100 positions per page).
local function AddRow(addon, content, boss, diff, page, id, detail, ltext)
	local key = addon .. ":" .. tostring(content) .. ":" .. id
	if loot.byKey[key] then return false end
	local r = setmetatable({ _compact = true, key = key, itemID = id, addon = addon,
		content = content, boss = boss, diff = diff, page = page,
		detail = detail, _ltext = ltext }, loot.meta)
	loot.byKey[key] = r
	loot.rows[#loot.rows + 1] = r
	loot.pending[#loot.pending + 1] = id
	loot.unnamed[id] = true
	return true
end

local function GroupText(inst, bossName)
	return bossName .. "  " .. inst, ns.Lower(inst .. " " .. bossName .. " loot drop atlasloot")
end

--- Rows for one loaded loot module: one per item and instance (the first boss and
--- difficulty it drops on), kept apart from names, which arrive from the server over time.
--- groups: the cache being built, one entry per boss table ({ addon, content, boss, inst,
--- boss name, "id.diff.page ..." }).
local function IndexModule(addon, storage, groups)
	local A = AL()
	local added = 0
	local diffs = Safe(storage.GetDifficultys, storage) or {}
	local ndiff = math.max(#diffs, 1)
	-- A module can hold tables for several game versions: AtlasLoot Continued loads Classic's
	-- (data.lua) and WoW Forever's (data-forever.lua), the same dungeons twice. Only what its own
	-- window shows on this client is indexed: the version it picks for the module, and tables
	-- made for every version (0).
	local version
	if A.GetGameVersion and storage.GetAviableGameVersion then
		version = Safe(storage.GetAviableGameVersion, storage, Safe(A.GetGameVersion, A))
	end
	for content, c in pairs(storage) do
		if type(c) == "table" and type(c.items) == "table"
			and (not version or c.gameVersion == nil or c.gameVersion == 0 or c.gameVersion == version) then
			local inst = Safe(c.GetName, c, true)
			if type(inst) ~= "string" then inst = tostring(content) end
			for boss = 1, #c.items do
				local bossName = Safe(c.GetNameForItemTable, c, boss, true)
				if type(bossName) ~= "string" then bossName = "?" end
				-- the same for every item of this boss
				local detail, ltext = GroupText(inst, bossName)
				local packed = {}
				for d = 1, ndiff do
					local list, typ = Safe(A.ItemDB.GetItemTable, A.ItemDB, addon, content, boss, d)
					local kind = type(typ) == "table" and typ[1] or "Item"
					-- the difficulty actually shown (a missing one falls back to another)
					local diff = type(list) == "table" and (Safe(A.ItemDB.GetDifficulty, A.ItemDB, addon, content, boss, d) or d)
					if type(list) == "table" then
						for _, row in ipairs(list) do
							local id = type(row) == "table" and row[2]
							local pos = type(row) == "table" and tonumber(row[1]) or 1
							id = type(id) == "number" and id > 0 and RowItem(kind, id, A) or nil
							if id then
								local page = math.floor((pos - 1) / 100)
								if AddRow(addon, content, boss, diff, page, id, detail, ltext) then
									added = added + 1
									packed[#packed + 1] = id .. "." .. diff .. "." .. page
								end
							end
						end
					end
				end
				if groups and #packed > 0 then
					groups[#groups + 1] = { addon, content, boss, inst, bossName, table.concat(packed, " ") }
				end
			end
		end
	end
	return added
end

--- What the saved index was built from: AtlasLoot's version and each module's, the game
--- version AtlasLoot picks, and this format. Any change and it's built again.
local function CacheKey(mods)
	local A = AL()
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	local function ver(name) return tostring(meta and Safe(meta, name, "Version") or "?") end
	local core = LoadedCore() or "AtlasLoot"
	local parts = { "v" .. CACHE_FORMAT, core .. "=" .. ver(core), "game=" .. tostring(A.GetGameVersion and Safe(A.GetGameVersion, A)) }
	for _, m in ipairs(mods) do parts[#parts + 1] = m .. "=" .. ver(m) end
	return table.concat(parts, " ")
end

--- Rows from the saved index, without loading any module. False when there's none to use.
local function FromCache(key)
	local c = ns.db and ns.db.lootCache
	if type(c) ~= "table" or c.key ~= key or type(c.groups) ~= "table" then return false end
	for _, g in ipairs(c.groups) do
		local addon, content, boss, inst, bossName, packed = g[1], g[2], g[3], g[4], g[5], g[6]
		if type(addon) == "string" and type(packed) == "string" then
			local detail, ltext = GroupText(tostring(inst), tostring(bossName))
			for id, diff, page in packed:gmatch("(%d+)%.(%d+)%.(%d+)") do
				AddRow(addon, content, boss, tonumber(diff), tonumber(page), tonumber(id), detail, ltext)
			end
		end
	end
	return true
end
I.CacheKey = CacheKey

local function Dirty()
	if ns.providers.loot then ns.providers.loot._dirty = true end
end

-- Ask the server for item names a little at a time; the provider refreshes as they arrive.
local function PumpNames()
	if loot.pumping then return end
	loot.pumping = true
	local i = 1
	local function step()
		if InCombatLockdown() then return C_Timer.After(5, step) end
		local stop = math.min(i + 100, #loot.pending)
		while i <= stop do
			local id = loot.pending[i]
			if not (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) and C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(id)
			end
			i = i + 1
		end
		if i <= #loot.pending then C_Timer.After(0.5, step) else loot.pumping = false; loot.pending = {} end
	end
	step()
end

--- Loads AtlasLoot's loot modules one at a time (they are load-on-demand) so there is no
--- single long pause, indexing each as it arrives.
local LoadLootModules
LoadLootModules = function()
	local A = AL()
	local list = Safe(A.Loader.GetLootModuleList, A.Loader)
	local mods = {}
	for _, m in ipairs(list and list.module or {}) do mods[#mods + 1] = m.addonName end
	for _, m in ipairs(list and list.custom or {}) do mods[#mods + 1] = m.addonName end
	if #mods == 0 and (loot.retries or 0) < 5 then
		-- AtlasLoot builds its module list in its own start-up, which may come after ours: ask again
		loot.retries = (loot.retries or 0) + 1
		ns:Trace("loot: AtlasLoot has no loot modules yet, asking again (" .. loot.retries .. ")")
		return C_Timer.After(3, LoadLootModules)
	end
	loot.modules = #mods
	local key = CacheKey(mods)
	if FromCache(key) then
		loot.loaded, loot.done, loot.cached = #mods, true, true
		loot.byKey = {}
		ns:Trace(("loot: %d rows from the saved index (%s)"):format(#loot.rows, key))
		Dirty()
		return PumpNames()
	end
	ns:Trace("loot: building the index (" .. key .. ")")
	loot.building = true
	local groups = {}
	local i = 0
	local function nextModule()
		if InCombatLockdown() then return C_Timer.After(5, nextModule) end
		i = i + 1
		local addon = mods[i]
		if not addon then
			loot.done, loot.building = true, false
			loot.byKey = {} -- only for skipping duplicates while indexing
			if ns.db then ns.db.lootCache = { key = key, groups = groups } end -- kept for the next session
			Dirty()
			return PumpNames()
		end
		Safe(A.Loader.LoadModule, A.Loader, addon)
		local storage = A.ItemDB.Storage[addon]
		if storage then
			loot.loaded = loot.loaded + 1
			IndexModule(addon, storage, groups)
			Dirty()
		end
		C_Timer.After(1.5, nextModule)
	end
	-- (loading every module is heavy: not in the first seconds after login)
	local wait = (loot.startedAt or 0) + 8 - GetTime()
	if wait > 0 then C_Timer.After(wait, nextModule) else nextModule() end
end
I.LoadLootModules = function() return LoadLootModules() end -- (tests: a new session)

local function OpenLoot(e)
	local A = AL()
	local GUI = A and A.GUI
	if not (GUI and GUI.frame) then
		ns:Print("AtlasLoot's window isn't ready yet.")
		return
	end
	-- rows from the saved index: the module may not be loaded this session yet
	if not (A.ItemDB.Storage and A.ItemDB.Storage[e.addon]) then
		if InCombatLockdown() then
			ns:Print("AtlasLoot's " .. tostring(e.addon) .. " loads after combat; try again then.")
			return
		end
		Safe(A.Loader.LoadModule, A.Loader, e.addon)
		ns:Trace("loot: loaded " .. tostring(e.addon) .. " to open it")
	end
	local f = GUI.frame
	if not f:IsShown() then f:Show() end
	-- the window's own pickers, in the order a player clicks them: each fills the next one's list
	Safe(f.moduleSelect.SetSelected, f.moduleSelect, e.addon)
	Safe(f.subCatSelect.SetSelected, f.subCatSelect, e.content)
	Safe(f.boss.SetSelected, f.boss, e.boss)
	local sel = A.db and A.db.GUI and A.db.GUI.selected
	if type(sel) == "table" and sel[3] ~= e.boss and f.extra then
		-- not a boss: one of the extra tables listed under the bosses (trash, sets...)
		Safe(f.extra.SetSelected, f.extra, e.boss)
	end
	if f.difficulty then Safe(f.difficulty.SetSelected, f.difficulty, e.diff) end
	-- Each pick refreshes the item list, but AtlasLoot skips a refresh within 0.1 s of the last
	-- one, so after these quick picks the list still showed the first (wrong) boss. Refresh it
	-- once more, past that guard, on the page the item is on.
	if type(sel) == "table" then sel[5] = e.page or 0 end
	if GUI.ItemFrame and GUI.ItemFrame.Refresh then Safe(GUI.ItemFrame.Refresh, GUI.ItemFrame, true) end
	ns:Trace(("loot: AtlasLoot on %s / %s / boss %s / difficulty %s / page %s (selected %s / %s / %s / %s)"):format(
		tostring(e.addon), tostring(e.content), tostring(e.boss), tostring(e.diff), tostring(e.page),
		tostring(sel and sel[1]), tostring(sel and sel[2]), tostring(sel and sel[3]), tostring(sel and sel[4])))
	H:When(function()
		local frame = GUI.ItemFrame and GUI.ItemFrame.frame
		for _, b in ipairs(frame and frame.ItemButtons or {}) do
			if b.ItemID == e.itemID and b:IsVisible() then return b end
		end
	end, function(b) H:Show(b, 6) end, 30, function()
		ns:Trace("loot: no button for item " .. tostring(e.itemID) .. " on the page shown")
	end)
end

local function SetupAtlasLoot()
	if loot.on or not AtlasLootPresent() then return end
	loot.on = true
	ns:RegisterProvider("loot", {
		-- only while modules are really being read (not while the saved index is looked at)
		busy = function() return loot.building and ("Indexing AtlasLoot's loot tables (%d of %d)"):format(loot.loaded, loot.modules) or nil end,
		label = "Loot",
		color = "ffd9a441",
		aliases = { "loot", "drop", "drops", "atlasloot", "al" },
		lazy = true,
		-- names arriving: see the frame below (only names of loot rows count)
		collect = function()
			local out = {}
			if not AtlasLootPresent() then return out end -- AtlasLoot went away: no stale loot rows
			for _, r in ipairs(loot.rows) do
				if not rawget(r, "name") then
					local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID)
					if type(name) == "string" and name ~= "" then r.name = name end
				end
				if rawget(r, "name") then out[#out + 1] = r end
			end
			-- what's still unnamed, for the name events (ids, not rows: several rows can share an item)
			loot.unnamed = {}
			for _, r in ipairs(loot.rows) do
				if not rawget(r, "name") then loot.unnamed[r.itemID] = true end
			end
			return out
		end,
	})
	loot.meta = ns:CompactMeta(ns.providers.loot, { activate = OpenLoot }, {
		icon = function(t) return C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.itemID) or nil end,
		link = function(t) return "item:" .. t.itemID end,
	})
	-- the saved index is read at once; building it again (AtlasLoot changed) waits 8 s (LoadLootModules)
	loot.startedAt = GetTime()
	C_Timer.After(1, LoadLootModules)
	-- Item names come in for everything in the game (bags, tooltips...): the loot list is read
	-- again only for names it was waiting on, at most once every 2 s
	local names = CreateFrame("Frame")
	loot.nameFrame = names
	pcall(names.RegisterEvent, names, "GET_ITEM_INFO_RECEIVED")
	names:SetScript("OnEvent", function(_, _, id)
		if id and not loot.unnamed[id] then return end
		if loot.queued then return end
		loot.queued = true
		C_Timer.After(2, function() loot.queued = nil; Dirty() end)
	end)
end

----------------------------------------------------------------------
-- Questie
----------------------------------------------------------------------

local npc = { list = nil, busy = false, on = false }
I.npc = npc
local qdb = { list = nil, busy = false }
I.qdb = qdb

local function QuestieReady()
	local Q = _G.Questie
	return Q and Q.API and Q.API.isReady and _G.QuestieLoader and true or false
end

local function QModule(name) return Safe(_G.QuestieLoader.ImportModule, _G.QuestieLoader, name) end

--- One field of a Questie NPC (minLevel, maxLevel, zoneID, npcFlags...), for the search filters.
function I.NpcField(id, field)
	if not QuestieReady() then return nil end
	local DB = QModule("QuestieDB")
	return DB and Safe(DB.QueryNPCSingle, id, field) or nil
end

--- Questie's names for the NPC flag bits (they differ between game versions).
function I.NpcFlagDefs()
	if not QuestieReady() then return nil end
	local DB = QModule("QuestieDB")
	return DB and DB.npcFlags or nil
end

--- NPC names, a slice at a time so the game doesn't stall while Questie's database is read.
--- Work through n items a few milliseconds per frame (SLICE_MS), however long each takes, so
--- indexing never stalls a frame; then done(). A failing item is skipped and traced. The time
--- taken goes to the trace (.debug log).
local SLICE_MS = 5
local function Now() return _G.debugprofilestop and _G.debugprofilestop() or (GetTime() * 1000) end
local function RunSliced(what, n, each, done)
	local i, started = 1, Now()
	ns.background = (ns.background or 0) + 1 -- (the prewarm waits while indexing runs)
	local function batch()
		local stop = Now() + SLICE_MS
		while i <= n do
			each(i)
			i = i + 1
			if Now() > stop then break end
		end
	end
	local function step()
		local ok, err = pcall(batch)
		if not ok then
			ns:Trace(("%s: item %d failed: %s"):format(what, i, tostring(err)))
			i = i + 1
		end
		if i <= n then return C_Timer.After(0, step) end
		ns:Trace(("%s: %d in %.0f ms"):format(what, n, Now() - started))
		ns.background = math.max(0, (ns.background or 1) - 1)
		done()
	end
	step()
end

I.RunSliced = RunSliced

-- Each list's names are also kept as one text ("\n<name, lowercase>\t<id>" per line), for the
-- "Search Questie for this" rows: built along with the list the first time, and kept when the list
-- is freed, so plain searches never need the list itself (npc.names, qdb.names; FindNames).

local function IndexNPCs(after)
	local function finish() if after then after() end end
	if npc.list or npc.busy or not QuestieReady() then return finish() end
	local DB = QModule("QuestieDB")
	if not (DB and DB.NPCPointers and DB.QueryNPCSingle) then return finish() end
	npc.busy = true
	local ids = {}
	for id in pairs(DB.NPCPointers) do if type(id) == "number" then ids[#ids + 1] = id end end
	table.sort(ids)
	local out, meta = {}, npc.meta
	local names = not npc.names and {} or nil
	RunSliced("questie: NPCs", #ids, function(i)
		local id = ids[i]
		local name = Safe(DB.QueryNPCSingle, id, "name")
		if type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
			-- compact: just the name and id; everything else is shared (npc.meta)
			local lname = ns.Lower(name)
			out[#out + 1] = setmetatable({ _compact = true, key = id, name = name, _lname = lname }, meta)
			if names then names[#names + 1] = "\n" .. lname .. "\t" .. id end
		end
	end, function()
		npc.list, npc.busy = out, false
		if names then npc.names, npc.nameQuery = table.concat(names) .. "\n", "QueryNPCSingle" end
		if ns.providers.npc then ns.providers.npc._dirty = true end
		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
		finish()
	end)
end

--- How many names in the text have every typed word (up to 100) and the first one's id.
--- Scans for the longest word with a plain find (C speed) and checks the others on its line.
--- tick: called every so often (the search's own budget check, which may pause it a frame).
local function FindNames(blob, tokens, tick)
	if type(blob) ~= "string" or #tokens == 0 then return nil, 0 end
	local lead = tokens[1]
	for k = 2, #tokens do if #tokens[k] > #lead then lead = tokens[k] end end
	local pos, count, firstId, looked = 1, 0, nil, 0
	while count < 100 do
		local at = blob:find(lead, pos, true)
		if not at then break end
		local lineEnd = blob:find("\n", at, true) or (#blob + 1)
		local tab = blob:find("\t", at, true)
		if tab and tab < lineEnd then -- (a match in the name, not in the id after it)
			local from = math.max(1, at - 120)
			local back = blob:sub(from, at):match(".*\n()")
			local name = blob:sub(back and (from + back - 1) or at, tab - 1)
			local all = true
			for k = 1, #tokens do
				if tokens[k] ~= lead and not name:find(tokens[k], 1, true) then all = false break end
			end
			if all then
				count = count + 1
				firstId = firstId or tonumber(blob:sub(tab + 1, lineEnd - 1))
			end
		end
		pos = lineEnd
		looked = looked + 1
		if tick and looked % 64 == 0 then tick() end
	end
	return firstId, count
end
I.FindNames = FindNames

--- The provider's hintFind: the first matching name (as the game writes it) and the count.
local function HintFind(t, tokens, tick)
	local id, count = FindNames(t.names, tokens, tick)
	if not id then return nil, 0 end
	local DB = QModule("QuestieDB")
	local name = DB and t.nameQuery and Safe(DB[t.nameQuery], id, "name")
	return type(name) == "string" and name or tostring(id), count
end

--- Where the NPC stands: uiMapID, position {x,y} (0-1), and whether that's a dungeon's
--- entrance rather than the NPC itself.
local function NpcLocation(id)
	local DB, Z = QModule("QuestieDB"), QModule("ZoneDB")
	local n = DB and Safe(DB.GetNPC, DB, id)
	if not (n and n.spawns and Z) then return end
	for zone, spawns in pairs(n.spawns) do
		local c = spawns and spawns[1]
		if c and c[1] and c[1] >= 0 then
			local dl = Safe(Z.GetDungeonLocation, Z, zone)
			if type(dl) == "table" and dl[1] then
				local ui = Safe(Z.GetUiMapIdByAreaId, Z, dl[1][1])
				if ui then return ui, { x = dl[1][2] / 100, y = dl[1][3] / 100 }, true end
			else
				local ui = Safe(Z.GetUiMapIdByAreaId, Z, zone)
				if ui then return ui, { x = c[1] / 100, y = c[2] / 100 } end
			end
		end
	end
end

local function ShowNpc(e)
	local M = ns.Maps
	local mapID, pos, dungeon = NpcLocation(e.npcID)
	if not mapID then
		ns:Print("Questie has no known location for " .. (e.npcName or e.name) .. ".")
		return
	end
	if not InCombatLockdown() then
		-- Questie's own marker for it on the map
		local QM = QModule("QuestieMap")
		if QM and QM.ShowNPC then Safe(QM.ShowNPC, QM, e.npcID) end
	end
	M.ShowAfter({ name = (e.npcName or e.name) .. (dungeon and " (dungeon entrance)" or ""), mapID = mapID, pos = pos })
end

local function NpcPin(e)
	local mapID, pos = NpcLocation(e.npcID)
	local name = e.npcName or e.name
	if not mapID then
		ns:Print("Questie has no known location for " .. name .. ".")
	elseif ns.Maps.Place({ name = name, mapID = mapID, pos = pos }) then
		ns:Print("Waypoint set: " .. name)
	else
		ns:Print("Can't set a waypoint there.")
	end
end

--- A map pin link where the NPC stands, for chat (>> party): the waypoint is set (a C API), then its link.
function I.NpcPinLink(e)
	local mapID, pos = NpcLocation(e.npcID)
	if not (mapID and pos and ns.Maps and ns.Maps.Place and ns.Maps.Place({ name = e.name, mapID = mapID, pos = pos })) then return nil end
	local link = C_Map and C_Map.GetUserWaypointHyperlink and Safe(C_Map.GetUserWaypointHyperlink)
	return type(link) == "string" and link ~= "" and link or nil
end

-- Shift+Enter targets the NPC: "/targetexact <name>" on the secure macro button, pressed by the game
-- (targeting is protected: never from Terminal's code). The waypoint stays on Enter (the map opens on
-- the NPC and pins it, Maps.ShowAfter); without the press (in combat: Enter can't be bound then),
-- Shift+Enter says so and only pins it.
local function TargetMacro(e) return "/targetexact " .. (e.npcName or e.name) end
local NPC_TARGET = { macro = TargetMacro }
local function NeverTargeted() return false end
local function TargetFallback(e)
	if InCombatLockdown() then ns:Print("In combat: can't target " .. tostring(e.name) .. " from here; pinning it instead.") end
	NpcPin(e)
end

local function OpenNpcDirect(e)
	-- no map keybinding to ride on: open the map ourselves (never in combat)
	if InCombatLockdown() then ns:Print("In combat: can't open " .. e.name .. " now.") return end
	if not NpcLocation(e.npcID) then -- nowhere to show it: leave the map alone
		ns:Print("Questie has no known location for " .. (e.npcName or e.name) .. ".")
		return
	end
	if ToggleWorldMap and not ns.Maps.MapOpen() then pcall(ToggleWorldMap) end
	C_Timer.After(0.1, function() ShowNpc(e) end)
end

--- A quest's objectives ("Bring Sharptalon's Claw to Senani Thunderheart...") from Questie's
--- database, lowercased for the search, or nil. Questie keeps them as a list of lines.
local function ObjectivesText(DB, id)
	local t = Safe(DB.QueryQuestSingle, id, "objectivesText")
	if type(t) == "table" then
		local parts = {}
		for _, line in ipairs(t) do
			if type(line) == "string" and not (issecretvalue and issecretvalue(line)) then parts[#parts + 1] = line end
		end
		t = table.concat(parts, " ")
	end
	if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then return ns.Lower(t) end
end

--- Quest names, levels, zones and objectives from Questie's database, a slice at a time.
local function IndexQuests()
	if qdb.list or qdb.busy or not QuestieReady() then return end
	local DB = QModule("QuestieDB")
	if not (DB and DB.QuestPointers and DB.QueryQuestSingle) then return end
	qdb.busy = true
	local ids = {}
	for id in pairs(DB.QuestPointers) do if type(id) == "number" then ids[#ids + 1] = id end end
	table.sort(ids)
	local out = {}
	local zones = {} -- zoneOrSort -> { name, searchable text }: thousands of quests share a few hundred zones
	local function Zone(zone)
		local z = zones[zone]
		if not z then
			local zname = type(zone) == "number" and zone > 0 and C_Map and C_Map.GetAreaInfo and Safe(C_Map.GetAreaInfo, zone) or nil
			zname = type(zname) == "string" and zname or nil
			z = { zname, ns.Lower("quest questie " .. (zname or "")) }
			zones[zone] = z
		end
		return z
	end
	local names = not qdb.names and {} or nil
	RunSliced("questie: quests", #ids, function(i)
		local id = ids[i]
		local name = Safe(DB.QueryQuestSingle, id, "name")
		if type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
			local z = Zone(Safe(DB.QueryQuestSingle, id, "zoneOrSort") or 0)
			-- searched too: who to talk to, what to kill or bring, where
			local obj = ObjectivesText(DB, id)
			local lname = ns.Lower(name)
			out[#out + 1] = setmetatable({
				_compact = true, key = id, qid = id, name = name, _lname = lname,
				level = Safe(DB.QueryQuestSingle, id, "questLevel"),
				zone = z[1],
				_ltext = obj and (z[2] .. " " .. obj) or z[2],
			}, qdb.meta)
			if names then names[#names + 1] = "\n" .. lname .. "\t" .. id end
		end
	end, function()
		qdb.list, qdb.busy = out, false
		if names then qdb.names, qdb.nameQuery = table.concat(names) .. "\n", "QueryQuestSingle" end
		if ns.providers.questie then ns.providers.questie._dirty = true end
		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
	end)
end

--- Who starts a quest: an NPC id, or a word for what else does ("an object", "an item").
local function QuestGiver(id)
	local DB = QModule("QuestieDB")
	local by = DB and Safe(DB.QueryQuestSingle, id, "startedBy")
	if type(by) ~= "table" then return nil end
	if type(by[1]) == "table" and by[1][1] then
		local name = Safe(DB.QueryNPCSingle, by[1][1], "name")
		return by[1][1], type(name) == "string" and name or nil
	end
	if type(by[2]) == "table" and by[2][1] then return nil, nil, "an object" end
	if type(by[3]) == "table" and by[3][1] then return nil, nil, "an item" end
end

local function InLog(id)
	return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) and true or false
end

local function Done(id)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and Safe(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false
end

--- A quest from Questie's database. Enter (or a click) shows its Wowhead link, selected in a small
--- window: Ctrl+C copies it (addons can't put text on the clipboard themselves) and the window
--- closes. Shift+Enter opens it in the game: the quest log for a quest you're on (as @questlog
--- does), otherwise its quest giver on the map. Entries are compact: these are shared, and
--- worked out when read (the quest's state can change).
local function LogEntry(id)
	local p = ns.providers.quests
	if not p then return nil end
	for _, l in ipairs(ns:GetEntries(p)) do
		if l.questID == id then return l end
	end
end

-- Wowhead has a WoW Forever section (/forever), with pages in the same form as its others.
I.WOWHEAD_QUEST = "https://www.wowhead.com/forever/quest=%d"

local function CopyQuestLink(t)
	local url = I.WOWHEAD_QUEST:format(t.qid)
	ns:ShowText("Wowhead: " .. tostring(t.name), url, { compact = true })
end

--- What a quest is sent to chat as, the way Questie links one: the game's own quest link when there is one
--- (anyone can click it; Questie turns it into its own link for players who have Questie), else Questie's
--- "[[level] Name (id)]", which Questie's chat filter makes a clickable link with its tooltip. (Questie's own
--- "|Hquestie:" links are only made on the receiving end: chat doesn't carry links it doesn't know.) Nil without Questie.
function I.QuestieQuestLink(id)
	id = tonumber(id)
	if not (id and _G.QuestieLoader) then return nil end
	local L = QModule("QuestieLink")
	if L then
		local s = Safe(L.GetNativeQuestLinkStringById, id) or Safe(L.GetQuestLinkStringById, id)
		if type(s) == "string" and s ~= "" then return s end
	end
	-- (an older Questie without those: the same bracket text, which its chat filter reads)
	local DB = QModule("QuestieDB")
	local name = DB and Safe(DB.QueryQuestSingle, id, "name")
	if type(name) ~= "string" or name == "" then return nil end
	if issecretvalue and issecretvalue(name) then return nil end
	return "[" .. name .. " (" .. id .. ")]"
end
local function QuestieShareLink(t) return I.QuestieQuestLink(t.qid) end

local function Status(id)
	return InLog(id) and "in log" or (Done(id) and "done" or nil)
end

local function Giver(fn)
	return function(entry)
		local npcID, npcName, other = QuestGiver(entry.qid)
		if not npcID then
			ns:Print(entry.name .. (other and (" is started by " .. other .. ".") or ": Questie doesn't know who starts it."))
			return
		end
		fn({ name = entry.name, npcID = npcID, npcName = (npcName or "quest giver") .. " (" .. entry.name .. ")" })
	end
end
local GIVER_AFTER, GIVER_OPEN, GIVER_PIN = Giver(ShowNpc), Giver(OpenNpcDirect), Giver(NpcPin)

-- a field that comes from the quest log entry while the quest is in the log
local function FromLog(field, otherwise)
	return function(t)
		local l = InLog(t.qid) and LogEntry(t.qid)
		if l then return l[field] end
		return otherwise
	end
end

local QUESTIE_LAZY = {
	detail = function(t)
		local parts = {}
		if t.level and t.level > 0 then parts[#parts + 1] = "Lv " .. t.level end
		if t.zone then parts[#parts + 1] = t.zone end
		local st = Status(t.qid)
		if st then parts[#parts + 1] = st end
		return table.concat(parts, "  ")
	end,
	icon = function(t)
		return Done(t.qid) and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\GossipFrame\\AvailableQuestIcon"
	end,
	-- Shift+Enter: the quest in the game (log, or the giver on the map), through the game's own key
	-- (Maps.lua loads before this file, so its specs are there to read; made once, not per lazy read)
	secondarySecure = FromLog("secure", ns.Maps.SECURE),
	secondaryIsOpen = FromLog("isOpen", ns.Maps.IsOpenFor),
	-- the zone the map switches to for a quest you don't have: its giver's
	mapTarget = function(t)
		local npcID = QuestGiver(t.qid)
		return npcID and (NpcLocation(npcID)) or nil
	end,
	secondaryAfter = FromLog("after", GIVER_AFTER),
	secondary = FromLog("activate", GIVER_OPEN),
}

local function SetupQuestie()
	if npc.on or not (_G.Questie and _G.QuestieLoader) then return end
	npc.on = true
	ns:RegisterProvider("npc", {
		busy = function() return npc.busy and "Indexing Questie's NPCs" or nil end,
		hintFind = function(_, tokens, tick) return HintFind(npc, tokens, tick) end,
		label = "NPC",
		color = "ffe0a060",
		aliases = { "npc", "npcs", "n", "mob", "vendor" },
		hintLabel = "Questie's NPCs",
		explicit = true, -- tens of thousands of names: only searched with @npc
		noCombat = true,
		idleDrop = 600, -- freed after 10 minutes without an @npc search; re-read when next wanted
		onDrop = function() npc.list = nil end,
		collect = function()
			if not npc.list then IndexNPCs() end
			return npc.list or {}
		end,
	})
	npc.meta = ns:CompactMeta(ns.providers.npc, {
		icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
		secure = ns.Maps.SECURE,
		isOpen = ns.Maps.IsOpenFor,
		after = ShowNpc,
		activate = OpenNpcDirect,
		secondarySecure = NPC_TARGET,
		secondaryIsOpen = NeverTargeted,
		secondary = TargetFallback,
	}, {
		npcID = function(t) return rawget(t, "key") end,
		detail = function(t) return "NPC  #" .. t.npcID end,
		mapTarget = function(t) return (NpcLocation(t.npcID)) end, -- the zone the map switches to
	})
	ns:RegisterProvider("questie", {
		label = "Questie",
		color = "ffb48cff",
		aliases = { "questie", "questdb", "allquests" },
		hintLabel = "Questie's quests",
		explicit = true, -- every quest in the game: only searched with @questie
		busy = function() return qdb.busy and "Indexing Questie's quests" or nil end,
		hintFind = function(_, tokens, tick) return HintFind(qdb, tokens, tick) end,
		-- Enter only shows a link (fine in combat); Shift+Enter opens windows (not in combat).
		-- No quest events: a quest's state (in log, done) is read when its row is drawn.
		-- (kept: a few thousand quests, and their objectives are the slow part to read again)
		collect = function()
			if not qdb.list then IndexQuests() end
			return qdb.list or {}
		end,
	})
	qdb.meta = ns:CompactMeta(ns.providers.questie, { activate = CopyQuestLink, shareLink = QuestieShareLink, noCombatSecondary = true }, QUESTIE_LAZY)
	-- built in the background after login (with their names text); the NPC list is freed when
	-- unused and built again for the next @npc search, the quest list (a few thousand) is kept
	-- one after the other (both at once doubled the work per frame right after login)
	local function index()
		C_Timer.After(2, function() IndexNPCs(IndexQuests) end)
	end
	if QuestieReady() then
		index()
	elseif _G.Questie.API and _G.Questie.API.RegisterOnReady then
		Safe(_G.Questie.API.RegisterOnReady, index)
	end
end

----------------------------------------------------------------------

function I.Setup()
	SetupAtlasLoot()
	SetupQuestie()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() I.Setup() end)

ns:RegisterCommand("integrations", {
	desc = "Show which other addons Terminal found (AtlasLoot, Questie)",
	run = function()
		local lines = { "Integrations:" }
		lines[#lines + 1] = "  AtlasLoot: " .. (loot.on
			and ("found (" .. tostring(LoadedCore() or "AtlasLoot") .. "). %d loot modules, %d indexed, %d items%s"):format(loot.modules, loot.loaded, #loot.rows, loot.done and "" or " (still loading)")
			or "not found")
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and ("found. %d NPCs (@npc), %s quests (@questie)"):format(#npc.list, qdb.list and #qdb.list or "indexing")
				or (QuestieReady() and "found, indexing NPCs..." or "found, waiting for Questie to finish loading"))
			or "not found")
		if ns.Stored then lines[#lines + 1] = "  Alts and banks: " .. ns.Stored.Status() end
		return lines
	end,
})

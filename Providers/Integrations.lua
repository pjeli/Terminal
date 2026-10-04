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

local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

----------------------------------------------------------------------
-- AtlasLoot
----------------------------------------------------------------------

local loot = { rows = {}, byKey = {}, pending = {}, modules = 0, loaded = 0, on = false }
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

--- Rows for one loaded loot module: one per item and instance (the first boss and
--- difficulty it drops on), kept apart from names, which arrive from the server over time.
local function IndexModule(addon, storage)
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
				for d = 1, ndiff do
					local list = Safe(A.ItemDB.GetItemTable, A.ItemDB, addon, content, boss, d)
					if type(list) == "table" then
						for _, row in ipairs(list) do
							local id = type(row) == "table" and row[2]
							local pos = type(row) == "table" and tonumber(row[1]) or 1
							if type(id) == "number" and id > 0 then
								local key = addon .. ":" .. tostring(content) .. ":" .. id
								if not loot.byKey[key] then
									-- the row is the entry (compact: shared fields come from loot.meta);
									-- its name is filled in once the server has sent it
									-- the difficulty actually shown (a missing one falls back to another), and the
									-- page the item is on (AtlasLoot shows 100 positions per page)
									local diff = Safe(A.ItemDB.GetDifficulty, A.ItemDB, addon, content, boss, d) or d
									local r = setmetatable({ _compact = true, key = key, itemID = id, addon = addon,
										content = content, boss = boss, diff = diff, page = math.floor((pos - 1) / 100),
										detail = bossName .. "  " .. inst,
										_ltext = ns.Lower(inst .. " " .. bossName .. " loot drop atlasloot") }, loot.meta)
									loot.byKey[key] = r
									loot.rows[#loot.rows + 1] = r
									loot.pending[#loot.pending + 1] = id
									added = added + 1
								end
							end
						end
					end
				end
			end
		end
	end
	return added
end

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
	local i = 0
	local function nextModule()
		if InCombatLockdown() then return C_Timer.After(5, nextModule) end
		i = i + 1
		local addon = mods[i]
		if not addon then
			loot.done = true
			Dirty()
			return PumpNames()
		end
		Safe(A.Loader.LoadModule, A.Loader, addon)
		local storage = A.ItemDB.Storage[addon]
		if storage then
			loot.loaded = loot.loaded + 1
			IndexModule(addon, storage)
			Dirty()
		end
		C_Timer.After(1.5, nextModule)
	end
	nextModule()
end

local function OpenLoot(e)
	local A = AL()
	local GUI = A and A.GUI
	if not (GUI and GUI.frame) then
		ns:Print("AtlasLoot's window isn't ready yet.")
		return
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
		busy = function() return loot.on and not loot.done and ("Indexing AtlasLoot's loot tables (%d of %d)"):format(loot.loaded, loot.modules) or nil end,
		label = "Loot",
		color = "ffd9a441",
		aliases = { "loot", "drop", "drops", "atlasloot", "al" },
		lazy = true,
		events = { "GET_ITEM_INFO_RECEIVED" },
		guard = 5,
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
			return out
		end,
	})
	loot.meta = ns:CompactMeta(ns.providers.loot, { activate = OpenLoot }, {
		icon = function(t) return C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.itemID) or nil end,
		link = function(t) return "item:" .. t.itemID end,
	})
	C_Timer.After(8, LoadLootModules)
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

--- NPC names, a slice at a time so the game doesn't stall while Questie's database is read.
local function IndexNPCs()
	if npc.list or npc.busy or not QuestieReady() then return end
	local DB = QModule("QuestieDB")
	if not (DB and DB.NPCPointers and DB.QueryNPCSingle) then return end
	npc.busy = true
	local ids = {}
	for id in pairs(DB.NPCPointers) do if type(id) == "number" then ids[#ids + 1] = id end end
	table.sort(ids)
	local out, i = {}, 1
	local meta = npc.meta
	local function step()
		local stop = math.min(i + 1500, #ids)
		while i <= stop do
			local id = ids[i]
			local name = Safe(DB.QueryNPCSingle, id, "name")
			if type(name) == "string" and name ~= "" then
				-- compact: just the name and id; everything else is shared (npc.meta)
				out[#out + 1] = setmetatable({ _compact = true, key = id, npcID = id, name = name }, meta)
			end
			i = i + 1
		end
		if i <= #ids then
			C_Timer.After(0, step)
		else
			npc.list, npc.busy = out, false
			if ns.providers.npc then ns.providers.npc._dirty = true end
			if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
		end
	end
	step()
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
	if not mapID then
		ns:Print("Questie has no known location for " .. e.name .. ".")
	elseif ns.Maps.Place({ name = e.name, mapID = mapID, pos = pos }) then
		ns:Print("Waypoint set: " .. e.name)
	else
		ns:Print("Can't set a waypoint there.")
	end
end

local function OpenNpcDirect(e)
	-- no map keybinding to ride on: open the map ourselves (never in combat)
	if InCombatLockdown() then ns:Print("In combat: can't open " .. e.name .. " now.") return end
	if ToggleWorldMap and not ns.Maps.MapOpen() then pcall(ToggleWorldMap) end
	C_Timer.After(0.1, function() ShowNpc(e) end)
end

--- Quest names, levels and zones from Questie's database, a slice at a time.
local function IndexQuests()
	if qdb.list or qdb.busy or not QuestieReady() then return end
	local DB = QModule("QuestieDB")
	if not (DB and DB.QuestPointers and DB.QueryQuestSingle) then return end
	qdb.busy = true
	local ids = {}
	for id in pairs(DB.QuestPointers) do if type(id) == "number" then ids[#ids + 1] = id end end
	table.sort(ids)
	local out, i = {}, 1
	local function step()
		local stop = math.min(i + 800, #ids)
		while i <= stop do
			local id = ids[i]
			local name = Safe(DB.QueryQuestSingle, id, "name")
			if type(name) == "string" and name ~= "" then
				local zone = Safe(DB.QueryQuestSingle, id, "zoneOrSort")
				local zname = type(zone) == "number" and zone > 0 and C_Map and C_Map.GetAreaInfo and Safe(C_Map.GetAreaInfo, zone) or nil
				local zoneName = type(zname) == "string" and zname or nil
				out[#out + 1] = setmetatable({
					_compact = true, key = id, qid = id, name = name,
					level = Safe(DB.QueryQuestSingle, id, "questLevel"),
					zone = zoneName,
					_ltext = ns.Lower("quest questie " .. (zoneName or "")),
				}, qdb.meta)
			end
			i = i + 1
		end
		if i <= #ids then
			C_Timer.After(0, step)
		else
			qdb.list, qdb.busy = out, false
			if ns.providers.questie then ns.providers.questie._dirty = true end
			if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
		end
	end
	step()
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
	secondarySecure = function(t) return FromLog("secure", ns.Maps.SECURE)(t) end,
	secondaryIsOpen = function(t) return FromLog("isOpen", ns.Maps.IsOpenFor)(t) end,
	-- the zone the map switches to for a quest you don't have: its giver's
	mapTarget = function(t)
		local npcID = QuestGiver(t.qid)
		return npcID and (NpcLocation(npcID)) or nil
	end,
	secondaryAfter = function(t) return FromLog("after", GIVER_AFTER)(t) end,
	secondary = function(t) return FromLog("activate", GIVER_OPEN)(t) end,
}

local function SetupQuestie()
	if npc.on or not (_G.Questie and _G.QuestieLoader) then return end
	npc.on = true
	ns:RegisterProvider("npc", {
		busy = function() return npc.busy and "Indexing Questie's NPCs" or nil end,
		label = "NPC",
		color = "ffe0a060",
		aliases = { "npc", "npcs", "n", "mob", "vendor" },
		explicit = true, -- tens of thousands of names: only searched with @npc
		noCombat = true,
		guard = 10,
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
		secondary = NpcPin,
	}, {
		detail = function(t) return "NPC  #" .. t.npcID end,
		mapTarget = function(t) return (NpcLocation(t.npcID)) end, -- the zone the map switches to
	})
	ns:RegisterProvider("questie", {
		label = "Questie",
		color = "ffb48cff",
		aliases = { "questie", "questdb", "allquests" },
		explicit = true, -- every quest in the game: only searched with @questie
		-- Enter only shows a link (fine in combat); Shift+Enter opens windows (not in combat)
		events = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" },
		guard = 5,
		idleDrop = 600, -- freed after 10 minutes without a @questie search; re-read when next wanted
		onDrop = function() qdb.list = nil end,
		collect = function()
			if not qdb.list then IndexQuests() end
			return qdb.list or {}
		end,
	})
	qdb.meta = ns:CompactMeta(ns.providers.questie, { activate = CopyQuestLink, noCombatSecondary = true }, QUESTIE_LAZY)
	local function index()
		C_Timer.After(2, IndexNPCs)
		C_Timer.After(4, IndexQuests)
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

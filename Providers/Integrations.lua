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
I.HINT_FEW = 2 -- (UI.HINT_FEW: a list with this many matches or fewer shows them as results)

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
	-- AtlasLoot Forever puts an icon and colour codes in some instance names ("Wailing Caverns|cffffffff|T...|t|r")
	inst = ns.Plain(inst):gsub("%s+$", "")
	return bossName .. "  " .. inst, ns.Lower(inst .. " " .. bossName .. " loot drop atlasloot")
end

--- Rows for one loaded loot module: one per item and instance (the first boss and
--- difficulty it drops on), kept apart from names, which arrive from the server over time.
--- groups: the cache being built, one entry per boss table ({ addon, content, boss, inst,
--- boss name, "id.diff.page ..." }).
I.GroupText = function(...) return GroupText(...) end -- (tests)

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

--- An item's name if the client has it: GetItemNameByID, or one GetItemInfo gave the name pump. With `ask`
--- (the pump only, a batch at a time) GetItemInfo is tried too: it makes the client fetch the item, so reading the
--- whole list with it (collect, .integrations) would send every outstanding ask at once. nil while unknown.
loot.got = {}
local function LootName(id, ask)
	local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if type(n) ~= "string" or n == "" then n = loot.got[id] end
	if (type(n) ~= "string" or n == "") and ask then
		local gii = C_Item.GetItemInfo or _G.GetItemInfo
		n = gii and Safe(gii, id)
		if type(n) == "string" and n ~= "" and not ns.Secret(n) then loot.got[id] = n end
	end
	if type(n) == "string" and n ~= "" and not ns.Secret(n) then return n end
end
I.LootName = LootName -- (tests)

-- Ask the server for item names a little at a time; the provider refreshes as they arrive.
-- WoW Forever's own items (Snake Eye Kaleidoscope, 273088) aren't in the client's item data: their
-- names come only from the server, which drops asks when thousands come at once. So whatever is
-- still unnamed after a round is asked for again (NAME_ROUNDS rounds, NAME_RETRY s apart).
I.NAME_BATCH, I.NAME_ROUNDS, I.NAME_RETRY = 50, 4, 20
local function PumpNames(round, gen)
	if not round then
		-- a new pump (the list was built or read again): any retry still waiting from an older one stops
		loot.pumpGen = (loot.pumpGen or 0) + 1
		loot.pumping = false
		round, gen = 1, loot.pumpGen
	end
	if gen ~= loot.pumpGen or loot.pumping then return end
	loot.pumping = true
	-- the ids to ask for: each once, only those without a name yet
	local ids, seen = {}, {}
	local source = round == 1 and loot.pending or nil
	if source then
		for _, id in ipairs(source) do
			if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
		end
	else
		for _, r in ipairs(loot.rows) do
			local id = r.itemID
			if not rawget(r, "name") and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
		end
	end
	loot.pending = {}
	local i, asked = 1, 0
	local function step()
		if gen ~= loot.pumpGen then return end -- (a newer pump took over)
		if InCombatLockdown() then return C_Timer.After(5, step) end
		local stop = math.min(i + I.NAME_BATCH - 1, #ids)
		while i <= stop do
			local id = ids[i]
			if LootName(id, true) then
				loot.unnamed[id] = nil
			else
				loot.unnamed[id] = true
				asked = asked + 1
				if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			end
			i = i + 1
		end
		if i <= #ids then return C_Timer.After(0.5, step) end
		loot.pumping = false
		ns:Trace(("loot: names round %d: asked the server for %d of %d items"):format(round, asked, #ids))
		if asked > 0 and round < I.NAME_ROUNDS then
			C_Timer.After(I.NAME_RETRY, function()
				-- what came in meanwhile is named by collect; the rest is asked for again
				if gen ~= loot.pumpGen then return end
				Dirty()
				PumpNames(round + 1, gen)
			end)
		elseif asked > 0 then
			local first = {}
			for id in pairs(loot.unnamed) do first[#first + 1] = id; if #first >= 5 then break end end
			ns:Trace(("loot: %d items still have no name after %d rounds (e.g. %s)"):format(asked, round, table.concat(first, ", ")))
		end
	end
	step()
end

--- How many loot items still have no name, asked now (loot.unnamed is tidied only when the list is read).
function I.LootWaiting()
	local n, seen = 0, {}
	for _, r in ipairs(loot.rows) do
		local id = r.itemID
		if not seen[id] then
			seen[id] = true
			if not rawget(r, "name") and not LootName(id) then n = n + 1 else loot.unnamed[id] = nil end
		end
	end
	return n
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
					local name = LootName(r.itemID)
					if name then r.name = name end
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
	pcall(names.RegisterEvent, names, "ITEM_DATA_LOAD_RESULT") -- (what RequestLoadItemDataByID answers with)
	names:SetScript("OnEvent", function(_, _, id, ok)
		if id and not loot.unnamed[id] then return end
		if ok == false then return end
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
local ObjectivesText -- (with the quest index, below)
I.qdb = qdb

-- The data comes from QuestieData.lua: the QuestieDB addon alone, or through Questie (same data).
local QD = ns.QuestieData
local QuestieReady = QD.Ready -- (the data can be read: QuestieDB loaded, and Questie ready if installed)
local function QDB() return QD.DB() end

--- One field of a Questie NPC (minLevel, maxLevel, zoneID, npcFlags...), for the search filters.
-- the small fields filters ask of every NPC row on every keystroke ("vendor", "nearest repair"): read once per NPC
local SMALL = { npcFlags = true, friendlyToFaction = true, minLevel = true, maxLevel = true, zoneID = true, subName = true }
local fieldCache, NONE, fieldFrom = {}, {}, nil
function I.NpcField(id, field)
	local DB = QDB()
	if not DB then return nil end
	if not SMALL[field] then return Safe(DB.QueryNPCSingle, id, field) or nil end
	if fieldFrom ~= DB then fieldCache, fieldFrom = {}, DB end -- (another database: QuestieDB reloaded, tests)
	local byId = fieldCache[field]
	if not byId then byId = {}; fieldCache[field] = byId end
	local v = byId[id]
	if v == nil then
		v = Safe(DB.QueryNPCSingle, id, field)
		if v == nil then v = NONE end
		byId[id] = v
	end
	if v == NONE then return nil end
	return v
end
I.ClearNpcFields = function() fieldCache = {} end

--- Questie's names for the NPC flag bits (they differ between game versions).
function I.NpcFlagDefs()
	local DB = QDB()
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

-- an NPC's title ("Mining Trainer", "Banker"), lowercase too: searched as the row's text ("mining trainer in org")
local function NpcSub(DB, id)
	local sub = Safe(DB.QueryNPCSingle, id, "subName")
	if type(sub) ~= "string" or sub == "" or (issecretvalue and issecretvalue(sub)) then return nil end
	return sub, ns.Lower(sub)
end

local function NpcListRow(DB, id, name, meta)
	local lname = ns.Lower(name)
	local sub, lsub = NpcSub(DB, id)
	return setmetatable({ _compact = true, key = id, name = name, _lname = lname, sub = sub, _ltext = lsub }, meta), lname, lsub
end

local function IndexNPCs(after)
	local function finish() if after then after() end end
	if npc.list or npc.busy or not QuestieReady() then return finish() end
	local DB = QDB()
	if not (DB and DB.QueryNPCSingle) then return finish() end
	npc.busy = true
	local ids = DB.NpcIds()
	local out, meta = {}, npc.meta
	local names = not npc.names and {} or nil
	RunSliced("questie: NPCs", #ids, function(i)
		local id = ids[i]
		local name = Safe(DB.QueryNPCSingle, id, "name")
		if type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
			-- compact: the name, title and id; everything else is shared (npc.meta)
			local row, lname, lsub = NpcListRow(DB, id, name, meta)
			out[#out + 1] = row
			-- (the title on the name's line: "mining trainer" finds Makaru; the name shown comes from the id)
			if names then names[#names + 1] = "\n" .. lname .. (lsub and (" <" .. lsub .. ">") or "") .. "\t" .. id end
		end
	end, function()
		npc.list, npc.busy = out, false
		if names then npc.names, npc.nameQuery = table.concat(names) .. "\n", "QueryNPCSingle" end
		local p = ns.providers.npc
		if p then
			p._dirty = true
			-- built at login, never searched: freed like an unused list (~5 MB for WoW Forever's 11.7k NPCs); the names
			-- text stays for the hint rows, and the next @npc search builds it again
			if not p._usedAt then p._usedAt = GetTime() end
		end
		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
		finish()
	end)
end

--- How many names in the text have every typed word (up to 100), the first one's id, and the
--- first FEW ids (a list with only one or two matches shows them as results, not as a hint).
--- Scans for the longest word with a plain find (C speed) and checks the others on its line.
--- tick: called every so often (the search's own budget check, which may pause it a frame).
local function FindNames(blob, tokens, tick)
	if type(blob) ~= "string" or #tokens == 0 then return nil, 0 end
	local lead = tokens[1]
	for k = 2, #tokens do if #tokens[k] > #lead then lead = tokens[k] end end
	local pos, count, firstId, looked, ids = 1, 0, nil, 0, {}
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
				local id = tonumber(blob:sub(tab + 1, lineEnd - 1))
				firstId = firstId or id
				if id and #ids < I.HINT_FEW then ids[#ids + 1] = id end
			end
		end
		pos = lineEnd
		looked = looked + 1
		if tick and looked % 64 == 0 then tick() end
	end
	return firstId, count, ids
end
I.FindNames = FindNames

--- The provider's hintFind: the first matching name (as the game writes it), the count, and the
--- first ids (UI shows those rows themselves when there are only a few: hintRow).
local function HintFind(t, tokens, tick)
	local id, count, ids = FindNames(t.names, tokens, tick)
	if not id then return nil, 0 end
	local DB = QDB()
	local name = DB and t.nameQuery and Safe(DB[t.nameQuery], id, "name")
	return type(name) == "string" and name or tostring(id), count, ids
end

--- A list's row by id: from the list when it's built (sorted by id: a binary search), else made
--- on the spot like the list makes it (the NPC list may have been freed; quests still indexing).
local function ListRow(list, id)
	if not list then return nil end
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local k = rawget(list[mid], "key")
		if k == id then return list[mid] elseif k < id then lo = mid + 1 else hi = mid - 1 end
	end
end

local function NpcHintRow(_, id)
	local row = ListRow(npc.list, id)
	if row then return row end
	local DB = QDB()
	local name = DB and Safe(DB.QueryNPCSingle, id, "name")
	if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
	return (NpcListRow(DB, id, name, npc.meta))
end

local function QuestHintRow(_, id)
	local row = ListRow(qdb.list, id)
	if row then return row end
	local DB = QDB()
	local name = DB and Safe(DB.QueryQuestSingle, id, "name")
	if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
	return setmetatable({ _compact = true, key = id, name = name, _lname = ns.Lower(name),
		level = Safe(DB.QueryQuestSingle, id, "questLevel"), _ltext = "quest questie" }, qdb.meta)
end

--- Where the NPC stands: uiMapID, position {x,y} (0-1), and whether that's a dungeon's
--- entrance rather than the NPC itself.
local function NpcLocation(id)
	local DB = QDB()
	local spawnsByZone = DB and Safe(DB.QueryNPCSingle, id, "spawns")
	if type(spawnsByZone) ~= "table" and DB and DB.GetNPC then
		local n = Safe(DB.GetNPC, DB, id)
		spawnsByZone = type(n) == "table" and n.spawns or nil
	end
	if type(spawnsByZone) ~= "table" then return end
	for zone, spawns in pairs(spawnsByZone) do
		local c = type(spawns) == "table" and spawns[1]
		if type(c) == "table" and c[1] and c[1] >= 0 then
			local dl = QD.DungeonLocation(zone)
			if type(dl) == "table" and dl[1] then
				local ui = QD.UiMapOfArea(dl[1][1])
				if ui then return ui, { x = dl[1][2] / 100, y = dl[1][3] / 100 }, true end
			else
				local ui = QD.UiMapOfArea(zone)
				if ui then return ui, { x = c[1] / 100, y = c[2] / 100 } end
			end
		end
	end
end

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
function I.NpcDistance(id, here)
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

----------------------------------------------------------------------
-- Game objects found by what they are: "nearest mailbox" (QuestieDB's objects: name, spawns)
----------------------------------------------------------------------

-- words -> the object's name, lowercase (every object of that exact name counts)
I.OBJECT_KINDS = { mailbox = "mailbox", mailboxes = "mailbox", mail = "mailbox", post = "mailbox" }
I.OBJECTS_NEAR = 8 -- (the nearest this many are listed)

-- instance entrances: their own lists (@dungeon, @raid), not QuestieDB objects
I.ENTRANCE_KINDS = { dungeon = "dungeon", dungeons = "dungeon", instance = "dungeon", instances = "dungeon", raid = "raid", raids = "raid" }
--- The kind of thing the search words name ("mailbox", "dungeon"), or nil. Only when that's all they name.
function I.ObjectKind(tokens)
	if not tokens or #tokens ~= 1 then return nil end
	return I.OBJECT_KINDS[tokens[1]] or I.ENTRANCE_KINDS[tokens[1]]
end

-- the object ids of each kind: one pass over QuestieDB's objects (13k names) the first time, kept in the saved
-- variables until QuestieDB changes (`db.objectIndex = { key, ids = { mailbox = "1,2,3" } }`)
local objectIds
local function ObjectIds(kind)
	local DB = QDB()
	if not (DB and DB.QueryObjectSingle and DB.ObjectIds) then return nil end
	if not objectIds then
		local all = DB.ObjectIds() or {}
		if #all == 0 then return nil end -- (not readable yet: asked again next time, nothing kept)
		local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
		-- (the kinds looked for are in the key: a kind added later reads every name again)
		local kinds = {}
		for _, name in pairs(I.OBJECT_KINDS) do kinds[name] = true end
		local names = {}
		for name in pairs(kinds) do names[#names + 1] = name end
		table.sort(names)
		local key = tostring(meta and Safe(meta, "QuestieDB", "Version") or "?") .. "/" .. #all .. "/" .. table.concat(names, ",")
		local saved = ns.db and ns.db.objectIndex
		objectIds = {}
		if type(saved) == "table" and saved.key == key and type(saved.ids) == "table" then
			for k, list in pairs(saved.ids) do
				local t = {}
				for id in tostring(list):gmatch("%d+") do t[#t + 1] = tonumber(id) end
				objectIds[k] = t
			end
		else
			local want = {}
			for name in pairs(kinds) do want[name] = true; objectIds[name] = {} end
			local t0 = debugprofilestop and debugprofilestop()
			for _, id in ipairs(all) do
				local name = Safe(DB.QueryObjectSingle, id, "name")
				if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
					local l = ns.Lower(name)
					if want[l] then local t = objectIds[l]; t[#t + 1] = id end
				end
			end
			local ids = {}
			for k, t in pairs(objectIds) do ids[k] = table.concat(t, ",") end
			if ns.db then ns.db.objectIndex = { key = key, ids = ids } end
			ns:Trace(("objects: %d read for their names%s"):format(#all, t0 and (", %.0f ms"):format(debugprofilestop() - t0) or ""))
		end
	end
	return objectIds[kind]
end
I.ResetObjectsForTests = function() objectIds = nil end

--- How far a row is from `here` (yards) and that spot ({ cont, x, y }), or nil: an NPC's nearest spawn on your
--- continent (NpcDistance), or a row that carries its own place in world yards (`wcont`, `wx`, `wy`: @mailbox).
function I.RowDistance(e, here)
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

local zoneNames = {}
local function ZoneName(ui)
	local n = zoneNames[ui]
	if n == nil then
		local info = C_Map and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, ui)
		n = type(info) == "table" and type(info.name) == "string" and info.name or false
		zoneNames[ui] = n
	end
	return n or nil
end

-- Enter on a mailbox: the map pin on it (a C API)
local function PinObject(e)
	if ns.Maps and ns.Maps.Place and ns.Maps.Place({ name = e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } }) then
		ns:Print(("Waypoint set: %s, %s"):format(e.name, e.detail or ""))
	else
		ns:Print("Can't set a waypoint there.")
	end
end
I.PinObject = PinObject

--- The rows of a kind of object (@mailbox): one per spawn, "Mailbox  Stormwind City", each with its map spot and its
--- place in world yards (for sort:nearest, near:, in: and the direction arrow). {} when QuestieDB has none to read.
function I.ObjectRows(kind)
	local ids = ObjectIds(kind)
	local DB = QDB()
	local rows = {}
	if not (ids and DB) then return rows end
	local label = kind:gsub("^%l", string.upper)
	for _, id in ipairs(ids) do
		local spawns = Safe(DB.QueryObjectSingle, id, "spawns")
		local n = 0
		for area, list in pairs(type(spawns) == "table" and spawns or {}) do
			local ui = QD.UiMapOfArea(area)
			if ui and type(list) == "table" then
				for _, c in ipairs(list) do
					if type(c) == "table" and type(c[1]) == "number" and c[1] >= 0 then
						n = n + 1
						local cont, x, y = SpotXY(ui, c)
						local zone = ZoneName(ui)
						rows[#rows + 1] = {
							name = label, key = id .. "-" .. n, kind = kind, icon = "Interface\\Icons\\INV_Letter_15",
							detail = zone, zone = zone, text = zone, ui = ui, px = c[1], py = c[2], area = area,
							wcont = cont, wx = x, wy = y, activate = PinObject, generic = true,
						}
					end
				end
			end
		end
	end
	return rows
end

-- Dungeon and raid entrances (@dungeon, @raid): QuestieDB's dungeon list, one row per entrance (Blackrock Depths has
-- two: Searing Gorge and Burning Steppes). Enter: the game opens the map on the entrance's zone, then Terminal pins
-- it (a C API); Shift+Enter only pins; ">>" and the right-click menu send it with a map pin. Raids by name (English, as
-- QuestieDB names them); battlegrounds and the non-instances in that list are left out.
I.RAIDS = {
	["molten core"] = true, ["onyxia's lair"] = true, ["blackwing lair"] = true, ["zul'gurub"] = true,
	["ruins of ahn'qiraj"] = true, ["temple of ahn'qiraj"] = true, ["naxxramas"] = true, ["karazhan"] = true,
	["gruul's lair"] = true, ["magtheridon's lair"] = true, ["serpentshrine cavern"] = true, ["serpentshire cavern"] = true,
	["tempest keep"] = true, ["hyjal summit"] = true, ["black temple"] = true, ["sunwell plateau"] = true,
	["zul'aman"] = true, ["the eye of eternity"] = true, ["the obsidian sanctum"] = true, ["vault of archavon"] = true,
	["ulduar"] = true, ["trial of the crusader"] = true, ["icecrown citadel"] = true, ["the ruby sanctum"] = true,
}
I.NOT_INSTANCES = {
	["deeprun tram"] = true, ["hall of legends"] = true, ["champions' hall"] = true,
	["alterac valley"] = true, ["warsong gulch"] = true, ["arathi basin"] = true, ["eye of the storm"] = true,
	["strand of the ancients"] = true, ["isle of conquest"] = true,
}
local function EntranceAfter(e)
	ns.Maps.ShowAfter({ name = e.name .. " entrance", mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } })
end
function I.EntranceRows(raids)
	local rows = {}
	local list = QD.Dungeons()
	if not list then return rows end
	local Lower = ns.Lower
	for areaId, d in pairs(list) do
		local name = type(d) == "table" and ns.Str(d[1])
		local lname = name and Lower(name)
		if lname and not I.NOT_INSTANCES[lname] and (I.RAIDS[lname] and true or false) == raids and type(d[4]) == "table" then
			local n = 0
			for _, c in ipairs(d[4]) do
				local ui = type(c) == "table" and type(c[2]) == "number" and QD.UiMapOfArea(c[1])
				if ui then
					n = n + 1
					local cont, x, y = SpotXY(ui, { c[2], c[3] })
					local zone = ZoneName(ui)
					rows[#rows + 1] = {
						name = name, key = areaId .. "-" .. n, icon = raids and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_03",
						detail = (raids and "Raid" or "Dungeon") .. (zone and ("  " .. zone) or ""), zone = zone,
						text = (raids and "raid entrance " or "dungeon instance entrance ") .. (zone or ""),
						ui = ui, mapID = ui, px = c[2], py = c[3], area = c[1], wcont = cont, wx = x, wy = y,
						pinName = name .. " entrance", what = raids and "raid" or "dungeon",
						secure = ns.Maps.SECURE, isOpen = ns.Maps.IsOpenFor, after = EntranceAfter, activate = PinObject,
						secondary = PinObject,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.name < b.name or (a.name == b.name and a.key < b.key) end)
	return rows
end

--- A map pin link for a row with a spot of its own (an entrance, a mailbox): the waypoint is set there (a C API).
function I.SpotPinLink(e)
	if not (e and e.ui and e.px and ns.Maps and ns.Maps.Place) then return nil end
	if not ns.Maps.Place({ name = e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } }) then return nil end
	local link = C_Map and C_Map.GetUserWaypointHyperlink and Safe(C_Map.GetUserWaypointHyperlink)
	return type(link) == "string" and link ~= "" and link or nil
end

--- "nearest mailbox" (Simple mode): the nearest rows of that kind's list (those `keep` keeps: a place said), closest
--- first, "N yd  Zone".
--- nil when there's no such list; an empty list when none is on your continent.
function I.NearestObjectRows(kind, here, keep)
	local p = ns.providers[kind]
	if not p then return nil end
	local found = {}
	for _, e in ipairs(ns:GetEntries(p)) do
		local d = (not keep or keep(e)) and I.RowDistance(e, here) or nil
		if d then found[#found + 1] = { e = e, d = d } end
	end
	table.sort(found, function(a, b) return a.d < b.d end)
	local rows = {}
	for i = 1, math.min(#found, I.OBJECTS_NEAR) do
		local f = found[i]
		rows[i] = setmetatable({ detail = ("%.0f yd"):format(f.d) .. (f.e.zone and ("  " .. f.e.zone) or ""),
			_score = 1e6 - f.d, _dist = f.d }, { __index = f.e })
	end
	return rows
end

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
	if type(face) ~= "number" or (_G.issecretvalue and _G.issecretvalue(face)) then return nil end
	return face
end

--- The turn from where you face to a spot (world x is north, y is west; facing counter-clockwise from north).
function I.Bearing(here, spot, face)
	return math.atan2(spot.y - here.y, spot.x - here.x) - face
end

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
local function TownCentre(place)
	local c = centres[place.area]
	if c ~= nil then return c or nil end
	c = false
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
	xforms, npcSpots, npcSpotCount = {}, {}, 0
	fieldCache = {}
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
		local QM = QD.Module("QuestieMap")
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
function ObjectivesText(DB, id)
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
	local DB = QDB()
	if not (DB and DB.QueryQuestSingle) then return end
	qdb.busy = true
	local ids = DB.QuestIds()
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
				_compact = true, key = id, name = name, _lname = lname,
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
		-- the towns' middles from the quests' words, for "vendor goldshire" (a few a frame, a little later)
		C_Timer.After(2, function() if not InCombatLockdown() then I.BuildTowns() end end)
		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
	end)
end

--- Who starts a quest: an NPC id, or a word for what else does ("an object", "an item").
local function QuestGiver(id)
	local DB = QDB()
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
	if not id then return nil end
	local L = QD.AnyModule("QuestieLink")
	if L then
		local s = Safe(L.GetNativeQuestLinkStringById, id) or Safe(L.GetQuestLinkStringById, id)
		if type(s) == "string" and s ~= "" then return s end
	end
	-- (an older Questie without those: the same bracket text, which its chat filter reads)
	local DB = QDB() or QD.AnyModule("QuestieDB")
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

-- (qid is the row's key, read through here: a row of 8 raw fields grew to a 16-slot table the first time a search
-- wrote its score on it, ~1.6 MB over 5000 quests; 7 leave room)
local QUESTIE_LAZY = {
	qid = function(t) return rawget(t, "key") end,
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
	-- Questie, or the QuestieDB addon alone (a Blizzard-like UI with Questie's data)
	if npc.on or not (QD.HasQuestie() or QD.Lib()) then return end
	npc.on = true
	ns:RegisterProvider("npc", {
		busy = function() return npc.busy and "Indexing Questie's NPCs" or nil end,
		hintFind = function(_, tokens, tick) return HintFind(npc, tokens, tick) end,
		hintRow = NpcHintRow,
		label = "NPC",
		color = "ffe0a060",
		aliases = { "npc", "npcs", "n", "mob", "vendor" },
		hintLabel = "Questie's NPCs",
		explicit = true, -- tens of thousands of names: only searched with @npc
		noCombat = true,
		idleDrop = 600, -- freed after 10 minutes without an @npc search; re-read when next wanted
		held = function() return npc.list ~= nil end,
		onDrop = function() npc.list = nil; fieldCache = {} end, -- (and the NPCs' small fields the filters read)
		collect = function()
			if not npc.list then IndexNPCs() end
			return npc.list or {}
		end,
	})
	-- @mailbox: every mailbox QuestieDB knows (its objects), one row per spot; sort:nearest, near:, in: work on it
	if QD.Lib() and type(QD.Lib().Object) == "table" or (QDB() and QDB().QueryObjectSingle) then
		ns:RegisterProvider("mailbox", {
			label = "Mailbox",
			color = "ffc9a0dc",
			aliases = { "mailbox", "mailboxes", "mail" },
			explicit = true, -- (only with @mailbox, or "nearest mailbox" in Simple mode)
			lazy = true,
			collect = function() return I.ObjectRows("mailbox") end,
		})
	end
	-- @dungeon / @raid: instance entrances (QuestieDB's dungeon list)
	if QD.Dungeons() then
		ns:RegisterProvider("dungeon", {
			label = "Dungeon", color = "ff8fc0ff", aliases = { "dungeon", "dungeons", "instance", "instances" }, lazy = true,
			collect = function() return I.EntranceRows(false) end,
		})
		ns:RegisterProvider("raid", {
			label = "Raid", color = "ffff9f6f", aliases = { "raid", "raids" }, lazy = true,
			collect = function() return I.EntranceRows(true) end,
		})
	end
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
		detail = function(t) return rawget(t, "sub") or ("NPC  #" .. t.npcID) end,
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
		hintRow = QuestHintRow,
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
	QD.OnReady(index)
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
			and ("found (" .. tostring(LoadedCore() or "AtlasLoot") .. "). %d loot modules, %d indexed, %d items%s%s"):format(loot.modules, loot.loaded, #loot.rows, loot.done and "" or " (still loading)",
				(function()
					local n = I.LootWaiting()
					return n > 0 and (", %d waiting for their names from the server"):format(n) or ""
				end)())
			or "not found")
		local src = QD.Source()
		local found = src == "QuestieDB" and "QuestieDB found (without Questie)" or "found"
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and ("%s. %d NPCs (@npc), %s quests (@questie)"):format(found, #npc.list, qdb.list and #qdb.list or "indexing")
				or (QuestieReady() and (found .. ", indexing NPCs...") or "found, waiting for Questie to finish loading"))
			or "not found")
		if ns.Stored then lines[#lines + 1] = "  Alts and banks: " .. ns.Stored.Status() end
		return lines
	end,
})

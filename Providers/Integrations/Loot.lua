local ns = select(2, ...)
local H = ns.Highlight
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local AddOnVersion = I._.AddOnVersion

----------------------------------------------------------------------
-- AtlasLoot
----------------------------------------------------------------------

local loot = { rows = {}, byKey = {}, pending = {}, unnamed = {}, failed = {}, modules = 0, loaded = 0, on = false }
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
local CACHE_FORMAT = 2 -- (2: indexed for the window's game version, I.WindowVersion)

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
I.GroupText = GroupText -- (tests)

--- The game version a module's tables are indexed for: the one AtlasLoot's window shows. That's the window's own pick
--- (db.GUI.selectedGameVersion) when the module has it, else the game's, else Classic. Not GetAviableGameVersion(the
--- game's) alone: WoW Forever reports itself as retail (99), which no module has, and that falls back to the module's
--- LAST loaded version, data-tbc.lua: only Burning Crusade dungeons were indexed, while AtlasLoot Forever's window
--- always shows Classic (and WoW Forever's own dungeons, which live in Classic's tables: the Ruins of Lordaeron).
function I.WindowVersion(A, storage)
	if not storage.GetAviableGameVersion then return nil end
	local function Has(v)
		if type(v) ~= "number" then return false end
		if storage.IsGameVersionAviable then return Safe(storage.IsGameVersionAviable, storage, v) == true end
		return Safe(storage.GetAviableGameVersion, storage, v) == v
	end
	local gui = type(A.db) == "table" and type(A.db.GUI) == "table" and A.db.GUI.selectedGameVersion
	local game = A.GetGameVersion and Safe(A.GetGameVersion, A)
	local classic = A.CLASSIC_VERSION_NUM or 1
	if Has(gui) then return gui end
	if Has(game) then return game end
	if Has(classic) then return classic end
	return Safe(storage.GetAviableGameVersion, storage, game)
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
	local version = I.WindowVersion(A, storage)
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
	local ver = AddOnVersion
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
-- After the quick rounds it keeps asking, slowly (NAME_SLOW s apart, NAME_SLOW_ROUNDS more: about an hour): before
-- 0.43.25 it gave up after the fourth, and items the server hadn't answered stayed out of @loot for the session.
I.NAME_BATCH, I.NAME_ROUNDS, I.NAME_RETRY = 50, 4, 20
I.NAME_SLOW, I.NAME_SLOW_ROUNDS = 120, 30
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
		-- (the ids still waiting, not a walk over every row; ones the server said it doesn't have aren't asked again)
		for id in pairs(loot.unnamed) do
			if not loot.failed[id] and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
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
		if asked > 0 and round < I.NAME_ROUNDS + I.NAME_SLOW_ROUNDS then
			C_Timer.After(round < I.NAME_ROUNDS and I.NAME_RETRY or I.NAME_SLOW, function()
				-- what came in meanwhile was already marked by the name frame (no rebuild of the whole list for
				-- nothing: a 30k-row rebuild every round was a stall); the rest is asked for again
				if gen ~= loot.pumpGen then return end
				for id in pairs(loot.unnamed) do
					if LootName(id) then loot.unnamed[id] = nil; loot.renamed = true end
				end
				if loot.renamed then loot.renamed = nil; Dirty() end
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
	end, function(b) H:Show(b) end, 30, function()
		ns:Trace("loot: no button for item " .. tostring(e.itemID) .. " on the page shown")
	end)
end

-- Shift+Enter: the item's link in the chat box, with where it drops ("[Corpsemaker] dropped by Overlord Ramtusk in
-- Razorfen Kraul", Share.Text), opened by the game (Core.lua's ChatBoxSpec); in combat, Terminal's own
local function LootLinkText(e) return ns.Share and ns.Share.Text(e) or e.name end
local LOOT_CHATBOX = ns.ChatBoxSpec(LootLinkText)
local function LinkLoot(e) ns.LinkInChat(LootLinkText(e)) end

local function SetupAtlasLoot()
	if loot.on or not AtlasLootPresent() then return end
	loot.on = true
	ns:RegisterProvider("loot", {
		-- only while modules are really being read (not while the saved index is looked at)
		busy = function() return loot.building and ("Indexing AtlasLoot's loot tables (%d of %d)"):format(loot.loaded, loot.modules) or nil end,
		label = "Loot",
		color = "ffd9a441",
		aliases = { "loot", "atlasloot", "al" }, -- (@drop is the loot log: what dropped for you)
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
	loot.meta = ns:CompactMeta(ns.providers.loot, { activate = OpenLoot, secondary = LinkLoot, secondarySecure = LOOT_CHATBOX,
		secondaryIsOpen = ns.Never }, {
		icon = function(t) return C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.itemID) or nil end,
		link = function(t) return "item:" .. t.itemID end,
		-- (read when drawn: its quality's colour, as bag items show; nothing kept on the row)
		color = function(t)
			local q = C_Item.GetItemQualityByID and ns.Safe(C_Item.GetItemQualityByID, t.itemID)
			return ns.QualityHex(q)
		end,
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
		if ok == false then loot.failed[id] = true return end -- (the server doesn't have it: not asked again)
		if loot.queued then return end
		loot.queued = true
		C_Timer.After(2, function() loot.queued = nil; Dirty() end)
	end)
end
I._.SetupAtlasLoot = SetupAtlasLoot

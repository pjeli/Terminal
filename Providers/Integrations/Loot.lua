local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local AddOnVersion = I._.AddOnVersion

----------------------------------------------------------------------
-- AtlasLoot
----------------------------------------------------------------------

local loot = { rows = {}, byKey = {}, pending = {}, unnamed = {}, failed = {}, modules = 0, loaded = 0, on = false,
	places = {} } -- (places[addon][content]: what kind of place it is, the level to enter it; I.LootPlace)
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
local CACHE_FORMAT = 5 -- (2: indexed for the window's game version, I.WindowVersion; 3: each place's kind and level;
-- 4: Enchanting's spells that make no item, the enchants, kept beside the groups: @enchant, OneForAll/Enchants.lua;
-- 5: where each item set is listed, kept beside them: Enter on @itemset opens it there, OneForAll/Armory.lua)

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

-- What kind of place a loot table is: "dungeon" (AtlasLoot's Dungeons and WoW Forever's own), "raid", or "other"
-- (professions, PvP, factions, collections, world events...), by the name of its AtlasLoot content type; and the level
-- it can be entered at (its LevelRange's first number).
local DUNGEON_TYPES, RAID_TYPES = { "Dungeons", "Forever Dungeons" }, { "20 Raids", "40 Raids", "Forever Raids", "Raids" }
function I.PlaceKind(A, c)
	local name = Safe(c.GetContentType, c)
	local enter = type(c.LevelRange) == "table" and tonumber(c.LevelRange[1]) or nil
	if type(name) ~= "string" then return "other", enter end
	local locales = A.Locales
	local function Is(list)
		for _, w in ipairs(list) do
			if name == w then return true end
			local ok, v = pcall(function() return locales[w] end) -- (its own language's name; a missing one may be the word itself)
			if ok and name == v then return true end
		end
	end
	if Is(DUNGEON_TYPES) then return "dungeon", enter end
	if Is(RAID_TYPES) then return "raid", enter end
	return "other", enter
end
function I.NotePlace(addon, content, kind, enter)
	if content == nil then return end
	-- AtlasLoot files Azuregos, Kazzak and the dragons under its 40-player raids: bosses out in the world, no instance
	if content == "WorldBosses" then kind = "world" end
	local t = loot.places[addon]
	if not t then t = {}; loot.places[addon] = t end
	local p, k, n = t[content], kind or "other", tonumber(enter)
	if p and p.kind == k and p.enter == n then return end -- (once per instance, not per boss)
	t[content] = { kind = k, enter = n }
end
--- A loot row's place: { kind = "dungeon" / "raid" / "world" (World Bosses) / "other", enter = level } (nil: not known, an index from before 0.51.9).
function I.LootPlace(e)
	-- (OneForAll's: its dungeon's or raid's, the level it gives; a quest's, a recipe's, a faction's: none, as AtlasLoot's
	-- crafting and factions have none)
	local s = rawget(e, "lootSource")
	if s then return (s == "dungeon" or s == "raid") and { kind = s, enter = rawget(e, "lootLevel") } or nil end
	local t = loot.places[e.addon]
	return t and t[e.content] or nil
end

--- AtlasLoot's faction loot as @reputation's rewards: each item of its Factions module, saying its faction and the
--- standing it needs ("Brood of Nozdormu  ·  Exalted", as its tables are filed: "<standing>  <faction>"), whether yours
--- allows it, Enter opening AtlasLoot on it as @loot's row does (a view on that row). `mine`: lowercase faction name ->
--- your standing (1-8); `have`: item ids listed already (OneForAll's, which say their quartermaster). (AtlasLoot's own
--- rows, not @loot's list: building @loot inside @reputation's collect was most of its 86 ms at login, and again on
--- every rep gain; its faction rows found once per index, each one's standing and faction read then.)
function I.FactionLoot(mine, have)
	local out = {}
	local lp = ns.providers.loot
	if not lp then return out end
	local F = ns.Filters
	local words = F and F._ and F._.StandingWords and F._.StandingWords() or {}
	local SEP = ns.DETAIL_SEP
	local function Read(r, into) -- (a faction table's row: its standing and faction, from "<standing>  <faction>")
		if r.itemID and I.LootSource(r) == "reputation" then
			local st, fac = I.LootSplit(r.detail)
			local need = st and words[ns.Lower(st)]
			if need and fac then into[#into + 1] = { r = r, st = st, fac = fac, lfac = ns.Lower(fac), need = need } end
		end
	end
	local fl
	if lp.atlasLoot then
		fl = loot.factionRows
		if not (fl and fl.of == loot.rows and fl.n == #loot.rows and fl.words == words) then
			fl = { of = loot.rows, n = #loot.rows, words = words }
			for _, r in ipairs(loot.rows) do Read(r, fl) end
			loot.factionRows = fl
		end
	else -- (another list called loot: tests')
		fl = {}
		for _, r in ipairs(ns:GetEntries(lp)) do Read(r, fl) end
	end
	for _, x in ipairs(fl) do
		local r = x.r
		local id = r.itemID
		local name = rawget(r, "name")
		if not name and I.LootName then -- (named as @loot's collect names them: @loot may not be built yet)
			name = I.LootName(id)
			if name then r.name = name end
		end
		if type(name) == "string" and not (have and have[id]) then
			local my = mine and mine[x.lfac]
			local need = x.need
			local can = my ~= nil and my >= need
			-- (said as OneForAll's are: the game's name for the standing, "you can buy it", the words its filters and
			-- Group read. ns.StandingName, OneForAll on or not: review)
			local st = ns.StandingName(need) or x.st
			out[#out + 1] = setmetatable({ key = "al:" .. id .. ":" .. tostring(r.content), name = name, repReward = true, namesOnly = true,
				faction = x.fac, reaction = need, mine = my, canBuy = can,
				detail = x.fac .. SEP .. st .. (can and (SEP .. L["you can buy it"]) or ""),
				text = ns.Lower(L["reputation reward"] .. " reputation reward rep " .. x.fac .. " " .. st .. " " .. x.st .. (can and " canbuy" or "")) },
				{ __index = r })
		end
	end
	return out
end

--- Where a loot row's item comes from (source:): dungeon, raid, world (a world boss), quest, crafted, reputation, pvp,
--- collection, or other. AtlasLoot's by its module (Crafting, Factions, PvP, Collections) and its place; OneForAll's
--- planner's as it says.
local sourceOf = {} -- addon -> content -> source (AtlasLoot's index doesn't change in a session; LootPlace's places neither)
function I.LootSource(e)
	local s = rawget(e, "lootSource")
	if s then return s end
	local byAddon = sourceOf[e.addon or ""]
	local got = byAddon and byAddon[e.content or ""]
	if got then return got end
	got = I.LootSourceOf(e)
	if e.addon then
		byAddon = byAddon or {}
		sourceOf[e.addon] = byAddon
		byAddon[e.content or ""] = got
	end
	return got
end
function I.ForgetLootSources() sourceOf = {} end -- (tests; the index made again)
function I.LootSourceOf(e)
	local addon = tostring(e.addon or "")
	if addon:find("Crafting", 1, true) then return "crafted" end
	if addon:find("Faction", 1, true) then return "reputation" end
	if addon:find("PvP", 1, true) then return "pvp" end
	if addon:find("Collection", 1, true) then return "collection" end
	local p = I.LootPlace(e)
	local k = p and p.kind
	return (k == "dungeon" or k == "raid" or k == "world") and k or "other"
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
			local kind, enter = I.PlaceKind(A, c)
			I.NotePlace(addon, content, kind, enter)
			if type(inst) ~= "string" then inst = tostring(content) end
			for boss = 1, #c.items do
				local bossName = Safe(c.GetNameForItemTable, c, boss, true)
				if type(bossName) ~= "string" then bossName = "?" end
				-- the same for every item of this boss
				local detail, ltext = GroupText(inst, bossName)
				local packed = {}
				for d = 1, ndiff do
					local list, typ = Safe(A.ItemDB.GetItemTable, A.ItemDB, addon, content, boss, d)
					local tableKind = type(typ) == "table" and typ[1] or "Item" -- (not the place's kind, below)
					-- the difficulty actually shown (a missing one falls back to another)
					local diff = type(list) == "table" and (Safe(A.ItemDB.GetDifficulty, A.ItemDB, addon, content, boss, d) or d)
					if type(list) == "table" then
						for _, row in ipairs(list) do
							local id = type(row) == "table" and row[2]
							local pos = type(row) == "table" and tonumber(row[1]) or 1
							-- (an Enchanting spell that makes no item is an enchant: noted for @enchant, 1.3.10)
							if tableKind == "Profession" and type(id) == "number" then I._.NoteEnchant(id, A) end
							-- (a set page's numbers are item sets: where each is listed, for @itemset's Enter, 1.4.10)
							if tableKind == "Set" and type(id) == "number" then I._.NoteSet(id, addon, content, boss, diff, math.floor((pos - 1) / 100)) end
							id = type(id) == "number" and id > 0 and RowItem(tableKind, id, A) or nil
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
					groups[#groups + 1] = { addon, content, boss, inst, bossName, table.concat(packed, " "), kind, enter }
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
	-- (and the window's own pick, which I.WindowVersion indexes first)
	local gui = type(A.db) == "table" and type(A.db.GUI) == "table" and A.db.GUI.selectedGameVersion or nil
	local parts = { "v" .. CACHE_FORMAT, core .. "=" .. ver(core), "game=" .. tostring(A.GetGameVersion and Safe(A.GetGameVersion, A)),
		"win=" .. tostring(gui) }
	for _, m in ipairs(mods) do parts[#parts + 1] = m .. "=" .. ver(m) end
	return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- AtlasLoot's enchants (1.3.10, the player: "Have Atlasloot's data be the primary; and OFA be the fallback"): the
-- Enchanting spells on its crafting pages that make no item, kept with the index (`enchants`, ids) and read by @enchant
----------------------------------------------------------------------

loot.enchants = {} -- spell id -> true
I.ENCHANTING = 10 -- (AtlasLoot's profession number for Enchanting: P.AL_PROFS)
--- A crafting page's spell: kept when it's Enchanting's and makes no item.
function I._.NoteEnchant(id, A)
	local P = A and A.Data and A.Data.Profession
	if not (P and P.GetProfessionData) then return end
	local d = Safe(P.GetProfessionData, id)
	if type(d) == "table" and d[2] == I.ENCHANTING and not (type(d[1]) == "number" and d[1] > 0) then loot.enchants[id] = true end
end
--- AtlasLoot's enchants: their spell ids, lowest first (none until its index is read or built).
function I.LootEnchants()
	local out = {}
	for id in pairs(loot.enchants) do out[#out + 1] = id end
	table.sort(out)
	return out
end
function I.EnchantsText() return table.concat(I.LootEnchants(), " ") end
function I._.ForgetEnchants() for k in pairs(loot.enchants) do loot.enchants[k] = nil end end -- (tests)

-- Where AtlasLoot lists each item set (1.4.10, the player: Enter on a set "is not opening Atlasloot ... to show the
-- actual itemset"): its set pages ("Set" tables: the Collections module's tier sets, a dungeon's own) hold set numbers,
-- not items. The first page met for a set is kept: { addon, content, boss, diff, page }, saved with the index (`sets`).
loot.sets = {} -- set id -> place
function I._.NoteSet(id, addon, content, boss, diff, page)
	if loot.sets[id] or type(addon) ~= "string" or content == nil or type(boss) ~= "number" then return end
	loot.sets[id] = { addon = addon, content = content, boss = boss, diff = tonumber(diff) or 1, page = tonumber(page) or 0 }
end
--- The set places as one text for the saved index: "id\taddon\tcontent\tboss\tdiff\tpage" a line.
function I.SetPlacesText()
	local ids = {}
	for id in pairs(loot.sets) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		local p = loot.sets[id]
		out[#out + 1] = table.concat({ id, p.addon, tostring(p.content), p.boss, p.diff, p.page }, "\t")
	end
	return table.concat(out, "\n")
end
function I._.ReadSetPlaces(text)
	if type(text) ~= "string" then return end
	for line in text:gmatch("[^\n]+") do
		local id, addon, content, boss, diff, page = line:match("^(%d+)\t([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)$")
		if id then I._.NoteSet(tonumber(id), addon, tonumber(content) or content, tonumber(boss), diff, page) end
	end
end
--- Where AtlasLoot lists this item set, or nil (no set page of it in the modules read).
function I.LootSetPlace(id) return loot.sets[id] end
function I._.ForgetSets() for k in pairs(loot.sets) do loot.sets[k] = nil end end -- (tests)

--- Rows from the saved index, without loading any module. False when there's none to use.
local function FromCache(key)
	local c = ns.db and ns.db.lootCache
	if type(c) ~= "table" or c.key ~= key or type(c.groups) ~= "table" then return false end
	if type(c.enchants) == "string" then
		for id in c.enchants:gmatch("%d+") do loot.enchants[tonumber(id)] = true end
	end
	I._.ReadSetPlaces(c.sets)
	for _, g in ipairs(c.groups) do
		local addon, content, boss, inst, bossName, packed = g[1], g[2], g[3], g[4], g[5], g[6]
		if type(addon) == "string" and type(packed) == "string" then
			I.NotePlace(addon, content, g[7], g[8])
			local detail, ltext = GroupText(tostring(inst), tostring(bossName))
			for id, diff, page in packed:gmatch("(%d+)%.(%d+)%.(%d+)") do
				AddRow(addon, content, boss, tonumber(diff), tonumber(page), tonumber(id), detail, ltext)
			end
		end
	end
	return true
end

local function Dirty() ns:Changed("loot") end

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
	if #mods == 0 then
		ns:Trace("loot: AtlasLoot still lists no loot modules after " .. tostring(loot.retries) .. " tries: nothing indexed, the saved index kept")
		-- (its module list changed: said, and .integrations no longer says "still loading")
		loot.done = true
		I.Failed("AtlasLoot", L["@loot (its loot tables) is unavailable."], "Loader.GetLootModuleList: no loot modules")
		return
	end
	loot.modules = #mods
	local key = CacheKey(mods)
	if FromCache(key) then
		loot.loaded, loot.done, loot.cached = #mods, true, true
		loot.byKey = {}
		ns:Changed("enchant")
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
			if #groups == 0 and loot.loaded > 0 then
				-- (modules loaded, no item read from them: its item tables changed; said, and no empty index kept)
				I.Failed("AtlasLoot", L["@loot (its loot tables) is unavailable."], "ItemDB.GetItemTable gave no items")
			elseif ns.db then
				ns.db.lootCache = { key = key, groups = groups, enchants = I.EnchantsText(), sets = I.SetPlacesText() } -- kept for the next session
			end
			Dirty()
			ns:Changed("enchant") -- (AtlasLoot's enchants are in: @enchant made again from them)
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
	-- (its pickers too: an AtlasLoot whose window has other fields said "not ready" instead of an error)
	local f = GUI and GUI.frame
	if not (type(f) == "table" and type(f.moduleSelect) == "table") then
		ns:Trace("loot: AtlasLoot's window or its module picker isn't there")
		ns:Print(L["AtlasLoot's window isn't ready yet."])
		return
	end
	local function Pick(w, v) if type(w) == "table" then Safe(w.SetSelected, w, v) end end
	-- rows from the saved index: the module may not be loaded this session yet
	local storage = type(A.ItemDB) == "table" and A.ItemDB.Storage
	if not (storage and storage[e.addon]) and type(A.Loader) == "table" then
		if InCombatLockdown() then
			ns:Print(L["AtlasLoot's %s loads after combat; try again then."]:format(tostring(e.addon)))
			return
		end
		Safe(A.Loader.LoadModule, A.Loader, e.addon)
		ns:Trace("loot: loaded " .. tostring(e.addon) .. " to open it")
	end
	if not f:IsShown() then f:Show() end
	-- the window's own pickers, in the order a player clicks them: each fills the next one's list
	Pick(f.moduleSelect, e.addon)
	Pick(f.subCatSelect, e.content)
	Pick(f.boss, e.boss)
	local sel = A.db and A.db.GUI and A.db.GUI.selected
	if type(sel) == "table" and sel[3] ~= e.boss then
		-- not a boss: one of the extra tables listed under the bosses (trash, sets...)
		Pick(f.extra, e.boss)
	end
	Pick(f.difficulty, e.diff)
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
			-- (an item's button by its item; a set's by its set: a set's button has no ItemID, never matched as nil == nil)
			local mine = (e.itemID and b.ItemID == e.itemID) or (e.setID and b.SetID == e.setID)
			if mine and b:IsVisible() then return b end
		end
	end, function(b)
		H:Show(b)
		-- a set: its items shown too, as a click on it does (AtlasLoot's own window: its Set button's OnClickItemList)
		local Btn = A.Button
		if e.setID and b.ExtraFrameData and type(Btn) == "table" and type(Btn.ExtraItemFrame_GetFrame) == "function" then
			b.ExtraFrameShown = true
			local ok = pcall(Btn.ExtraItemFrame_GetFrame, Btn, b, b.ExtraFrameData)
			ns:Trace("loot: set " .. tostring(e.setID) .. "'s items " .. (ok and "shown" or "not shown (its item list failed)"))
		end
	end, 30, function()
		ns:Trace("loot: no button for " .. (e.setID and ("set " .. tostring(e.setID)) or ("item " .. tostring(e.itemID))) .. " on the page shown")
	end)
end

--- Opens AtlasLoot on the page that lists this item set, pointing at it and showing its items; false when AtlasLoot
--- lists it on no set page Terminal has read.
function I.OpenLootSet(id)
	local p = loot.sets[id]
	if not p then return false end
	OpenLoot({ addon = p.addon, content = p.content, boss = p.boss, diff = p.diff, page = p.page, setID = id })
	return true
end

-- Shift+Enter: the item's link in the chat box, with where it drops ("[Corpsemaker] dropped by Overlord Ramtusk in
-- Razorfen Kraul", Share.Text), opened by the game (Core.lua's ChatBoxSpec); in combat, Terminal's own
local function LootLinkText(e) return ns.Share and ns.Share.Text(e) or e.name end
local LOOT_CHATBOX = ns.ChatBoxSpec(LootLinkText)
local function LinkLoot(e) ns.LinkInChat(LootLinkText(e)) end

--- A loot row's detail as GroupText made it, "<boss>  <instance>": without the drop chance said after it (1.0.4,
--- OneForAll's), which isn't part of the instance.
function I.LootDetail(d)
	if type(d) ~= "string" then return d end
	local cut = d:find(ns.DETAIL_SEP, 1, true)
	return cut and d:sub(1, cut - 1) or d
end

--- A loot row's detail as its two parts, "<boss>  <instance>" (or a faction table's "<standing>  <faction>"): without a
--- drop chance, colour codes and the spaces around; nil and the whole of it when it has one part. (One copy since
--- 1.0.44: Aggregate's LootParts, Share's LootWhere, the Console's LootPlace and I.FactionLoot each split it; the
--- player's ask. GroupText above makes it.)
function I.LootSplit(d)
	if type(d) ~= "string" then return nil, nil end
	d = ns.Plain(I.LootDetail(d)):match("^%s*(.-)%s*$") -- (trimmed first: "  Onyxia  " is one part)
	local a, b = d:match("^(.-)%s%s+(.+)$")
	if a then return a, b end
	return nil, d
end

--- The NPC a loot row's boss table is (AtlasLoot's npcID; a table of them: the first), or nil: its module not loaded
--- this session (rows from the saved index) or a table that isn't a boss.
function I.LootNpc(e)
	local A = AL()
	local st = type(A) == "table" and type(A.ItemDB) == "table" and type(A.ItemDB.Storage) == "table" and A.ItemDB.Storage[e.addon]
	local c = type(st) == "table" and st[e.content]
	local b = type(c) == "table" and type(c.items) == "table" and c.items[e.boss]
	local npc = type(b) == "table" and b.npcID
	if type(npc) == "table" then npc = npc[1] end
	return ns.Num(npc)
end

--- A loot row's tooltip lines after the item's (UI/Tooltip.lua's tipMore): its boss's level, creature type and whether
--- it's summoned (OneForAll's, Bosses.lua), and AtlasLoot's drop rate when OneForAll gave the row none (its detail says
--- that one). Nothing when neither knows; the drop rate only while the boss's module is loaded (AtlasLoot keeps its
--- rates in the module).
function I.LootTipMore(e, t)
	local d = rawget(e, "detail")
	local boss, inst = I.LootSplit(d)
	local npc = I.LootNpc(e)
	local B = ns.OneForAllBosses
	local rec = B and B.Find and B.Find(boss, inst, npc)
	local said = rec and B.Said(rec)
	local pct
	if npc and not (type(d) == "string" and d:find(ns.DETAIL_SEP, 1, true)) then
		local A = AL()
		local DR = type(A) == "table" and type(A.Data) == "table" and A.Data.Droprate
		pct = type(DR) == "table" and ns.Num(Safe(DR.GetData, DR, npc, e.itemID)) or nil
	end
	if not (said or pct) then return end
	t:AddLine(" ")
	if said then t:AddLine((boss or rec.name) .. ": " .. said, 1, 0.82, 0, true) end
	if pct then
		local W = ns.OneForAllWorld
		local s = W and W.ChanceText and W.ChanceText(pct) or L["%s%% to drop"]:format(tostring(pct))
		t:AddLine(s .. ns.DETAIL_SEP .. "AtlasLoot", 1, 1, 1)
	end
end

local function SetupAtlasLoot()
	if loot.on or not AtlasLootPresent() then return end
	loot.on = true
	ns:RegisterProvider("loot", {
		-- only while modules are really being read (not while the saved index is looked at)
		busy = function() return loot.building and L["Indexing AtlasLoot's loot tables (%d of %d)"]:format(loot.loaded, loot.modules) or nil end,
		label = L["Loot"],
		color = "ffd9a441",
		aliases = { "loot", "atlasloot", "al" }, -- (@drop is the loot log: what dropped for you)
		atlasLoot = true, -- (its rows are loot.rows: I.FactionLoot reads them there)
		lazy = true,
		-- names arriving: see the frame below (only names of loot rows count)
		collect = function()
			local out = {}
			if not AtlasLootPresent() then return out end -- AtlasLoot went away: no stale loot rows
			local W = ns.OneForAllWorld
			local chances = W and W.DropChances()
			-- (a boss's rows share their detail: its chances looked up once a session, made again only when OneForAll's
			-- table is another; review, 1.0.13 and 1.0.21)
			if loot.chancesOf ~= chances then loot.chancesOf, loot.chanceAt = chances, {} end
			local byDetail = loot.chanceAt or {}
			for _, r in ipairs(loot.rows) do
				if not rawget(r, "name") then
					local name = LootName(r.itemID)
					if name then r.name = name end
				end
				local d = chances and rawget(r, "detail")
				if type(d) == "string" and not d:find(ns.DETAIL_SEP, 1, true) then -- (said already: not again)
					local at = byDetail[d]
					if at == nil then
						local boss, inst = I.LootSplit(d) -- (the one reading of "Boss  Instance")
						at = boss and W.BossChances(inst, boss) or false
						byDetail[d] = at
					end
					-- (the boss not found by name: by the item alone, when OneForAll lists it once; W.ItemChance)
					local pct = (at and at[r.itemID]) or (not at and W.ItemChance and W.ItemChance(r.itemID)) or nil
					if pct then r.detail = d .. ns.DETAIL_SEP .. W.ChanceText(pct) end
				end
				if rawget(r, "name") then out[#out + 1] = r end
			end
			-- OneForAll's planner's gear AtlasLoot doesn't list: quest rewards, reputation, crafted, its dungeons'
			local G = ns.OneForAllGear
			if G and G.on and G.Rows then
				-- (every AtlasLoot row's item, named yet or not: one whose name hasn't come isn't OneForAll's twice;
				-- made once per index, so OneForAll's rows are too: review)
				if loot.listedOf ~= loot.rows or loot.listedN ~= #loot.rows then
					local listed = {}
					for _, r in ipairs(loot.rows) do listed[r.itemID] = true end
					loot.listed, loot.listedOf, loot.listedN = listed, loot.rows, #loot.rows
				end
				for _, r in ipairs(G.Rows(loot.listed)) do out[#out + 1] = r end
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
		secondaryIsOpen = ns.Never, tipMore = function(e, t) return I.LootTipMore(e, t) end }, {
		icon = function(t) return C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.itemID) or nil end,
		link = function(t) return "item:" .. t.itemID end,
		-- (read when drawn: its quality's colour, as bag items show; nothing kept on the row)
		color = function(t)
			return ns.QualityHex(ns.ItemQuality(t.itemID)) -- (as said once: the game may have let go of it since)
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

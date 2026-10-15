-- "upgrades" in Simple mode said 18 in Dungeon loot, then listed 8 there, and changed with each step in and out (the
-- player's report, 0.51.6): the client lets go of items it loaded a while ago, and a loot row it no longer had was left
-- out; an item whose stats hadn't come was kept as having none (judged by item level alone) until the cache moved on.
-- What is:upgrade read of an item is kept for the session; stats not in yet aren't kept as none.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F = ns.Filters

io.write("[upgrades: the same items, whether or not the client still has them]\n")
do
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel, inv = _G.GetInventoryItemLink,
		can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo, class = _G.UnitClass, inst = C_Item.GetItemInfoInstant,
		invId = _G.GetInventoryItemID, cached = C_Item.IsItemDataCachedByID, req = C_Item.RequestLoadItemDataByID,
		providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	local ITEMS = {
		[60] = { "Worn Helm", "|Hitem:60|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[61] = { "Helm of Might", "|Hitem:61|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[62] = { "Helm of Valor", "|Hitem:62|h", 2, 21, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[63] = { "Helm of Rage", "|Hitem:63|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[64] = { "Shiny Helm of the Owl", "|Hitem:64|h", 2, 25, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" }, -- (caster: not one)
		[65] = { "Late Helm", "|Hitem:65|h", 2, 24, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[70] = { "Bag Boots", "|Hitem:70|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_FEET" },
	}
	local STATS = {
		[60] = { ITEM_MOD_STRENGTH_SHORT = 3 }, [61] = { ITEM_MOD_STRENGTH_SHORT = 6 }, [62] = { ITEM_MOD_STRENGTH_SHORT = 7 },
		[63] = { ITEM_MOD_STRENGTH_SHORT = 8 }, [64] = { ITEM_MOD_INTELLECT_SHORT = 9, ITEM_MOD_STRENGTH_SHORT = 1 },
		[65] = { ITEM_MOD_INTELLECT_SHORT = 9, ITEM_MOD_STRENGTH_SHORT = 1 },
		[70] = { ITEM_MOD_STRENGTH_SHORT = 4 },
	}
	local has = {} -- item id -> the client has it (default: yes)
	local statsIn = { [65] = false } -- (65's stats not come yet)
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemStats = function(link)
		local id = idOf(link)
		if statsIn[id] == false then return nil end
		return STATS[id]
	end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	C_Item.IsItemDataCachedByID = function(id) return has[id] ~= false end
	C_Item.RequestLoadItemDataByID = function() end
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	C_PlayerInfo.CanUseItem = function(id) return has[id] ~= false end -- (the game can't say for an item it hasn't got)
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:60|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 60 end end
	F.ClearCache()

	local function up(id, kind) return F.GearFit()({ itemID = id, kind = kind or "loot" }) end
	check(up(61) and up(62) and up(63) and not up(64), "the strength helms are a warrior's upgrades, the caster's isn't")
	-- the client lets go of them (it loaded thousands since)
	has[61], has[62], has[64] = false, false, false
	check(up(61) and up(62) and not up(64), "...and still are once the client has let go of them (as read when it had them)")
	check(up(63), "...the one it still has, too")
	-- an item whose stats haven't come: not kept as having none (it was judged by item level alone, till the cache
	-- moved on: then by its stats)
	has[65], statsIn[65] = false, false
	check(F._.Stats({ itemID = 65 }) == nil, "stats not come and the client hasn't the item: nil, not kept as none")
	has[65], statsIn[65] = nil, nil
	check(type(F._.Stats({ itemID = 65 })) == "table" and F._.Stats({ itemID = 65 }).ITEM_MOD_INTELLECT_SHORT == 9,
		"...its stats read once they come")
	check(not up(65), "...and the caster's helm isn't a warrior's upgrade")
	-- what you can use is asked again whenever the client has the item (you may have learned to wear mail since)
	has[61] = nil
	local canWas = C_PlayerInfo.CanUseItem
	C_PlayerInfo.CanUseItem = function() return false end
	check(not up(61), "the client has it again: what you can use asked again")
	C_PlayerInfo.CanUseItem = canWas
	check(up(61), "...and kept")
	-- (0.51.8) only gear about your level, and never a shirt or tabard
	ITEMS[66] = { "Helm of Old Might", "|Hitem:66|h", 2, 16, 10, "Armor", "Mail", 1, "INVTYPE_HEAD" } -- (needs 10: you're 20)
	ITEMS[67] = { "Fine Shirt", "|Hitem:67|h", 2, 20, 15, "Armor", "Miscellaneous", 1, "INVTYPE_BODY" }
	ITEMS[68] = { "Guild Tabard", "|Hitem:68|h", 2, 20, 15, "Armor", "Miscellaneous", 1, "INVTYPE_TABARD" }
	ITEMS[69] = { "Plain Cap", "|Hitem:69|h", 2, 12, 0, "Armor", "Mail", 1, "INVTYPE_HEAD" } -- (needs nothing, item level 12)
	STATS[66], STATS[67], STATS[68], STATS[69] = { ITEM_MOD_STRENGTH_SHORT = 9 }, {}, {}, { ITEM_MOD_STRENGTH_SHORT = 9 }
	check(not up(66), "a better helm, but for level 10 (you're 20): not one")
	check(not up(69), "one that needs no level, its item level 12: not one either")
	F.GEAR_NEAR = 12
	check(up(66), "(with GEAR_NEAR 12 it is)")
	F.GEAR_NEAR = 6
	check(not up(67) and not up(68), "a shirt or tabard, nothing worn there: never an upgrade")
	-- (0.51.9, the player: Naxxramas gear, engineers' trinkets and cosmetic helms for a level 30 warrior) only what you can
	-- get: loot from a dungeon you can enter; an item only an alt holds, if it can be sent you
	local NotePlace = ns.Integrations.NotePlace or function() end
	NotePlace("AL_Dungeons", "Deadmines", "dungeon", 10)
	NotePlace("AL_Dungeons", "Naxxramas", "raid", 60)
	NotePlace("AL_Dungeons", "Scholomance", "dungeon", 45)
	NotePlace("AL_Crafting", "Engineering", "other", nil)
	if ns.Integrations.PlaceKind then
		local A = { Locales = setmetatable({ ["Dungeons"] = "Verliese" }, { __index = function(_, k) return k end }) }
		local function C(name, range) return { GetContentType = function() return name end, LevelRange = range } end
		local PK = ns.Integrations.PlaceKind
		local k1, e1 = PK(A, C("Verliese", { 17, 20, 24 }))
		local k2, e2 = PK(A, C("40 Raids", { 60, 60, 60 }))
		check(k1 == "dungeon" and e1 == 17 and k2 == "raid" and e2 == 60 and PK(A, C("Forever Dungeons")) == "dungeon"
			and PK(A, C("Professions")) == "other" and PK(A, {}) == "other",
			"AtlasLoot's places: a dungeon (in the client's language), a raid, the rest; the level to enter")
	end
	local function From(id, content, addon) return F.GearFit()({ kind = "loot", itemID = id, addon = addon or "AL_Dungeons", content = content }) end
	check(From(61, "Deadmines"), "a dungeon you can enter: its loot counts")
	check(not From(61, "Naxxramas"), "a raid's: not")
	check(not From(61, "Engineering", "AL_Crafting"), "a profession's: not")
	check(not From(61, "Scholomance"), "a dungeon you can't enter yet (45, you're 20): not")
	ITEMS[71] = { "Bound Helm", "|Hitem:71|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD", 1, 1, 4, 3, 1 } -- (bound when picked up)
	ITEMS[72] = { "Loose Helm", "|Hitem:72|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD", 1, 1, 4, 3, 2 } -- (bound when worn)
	STATS[71], STATS[72] = { ITEM_MOD_STRENGTH_SHORT = 9 }, { ITEM_MOD_STRENGTH_SHORT = 9 }
	local alt, me = { a = { who = "Alt", where = "bags", mine = false } }, { b = { who = "Me", where = "bank", mine = true } }
	local function Held(id, holders) return F.GearFit()({ kind = "stored", itemID = id, holders = holders }) end
	check(not Held(71, alt), "bound when picked up, on an alt: not one (it can't be sent you)")
	check(Held(72, alt), "bound when worn, on an alt: one (mail it over)")
	check(Held(71, me), "bound when picked up, in your own bank: one")
	-- an item the game hasn't got: asked for in the background, the search not run again for it
	has[73] = false
	F.loading = nil
	F.GearFit()({ kind = "stored", itemID = 73, holders = alt })
	check(not F.loading, "an item still loading: the search isn't marked to run again (as @loot is:upgrade isn't)")
	has[73] = nil
	-- an item's colour kept once the game said it (it lets go of items it loaded a while ago)
	local qWas, q = C_Item.GetItemQualityByID, 4
	C_Item.GetItemQualityByID = function(id) if id == 990077 then return q end end
	local Quality = ns.ItemQuality or function(id) return C_Item.GetItemQualityByID(id) end
	check(Quality(990077) == 4, "quality: as the game says")
	q = nil
	check(Quality(990077) == 4, "...and as it said, once it no longer says")
	C_Item.GetItemQualityByID = qWas

	-- in Simple mode: the count the overview gave is what the category lists, the client letting go meanwhile
	F.ClearCache()
	for k in pairs(has) do has[k] = nil end
	local function Rows(list)
		return function()
			local out = {}
			for i, r in ipairs(list) do
				local e = {}
				for k, v in pairs(r) do e[k] = v end
				e.key = e.key or i
				out[i] = e
			end
			return out
		end
	end
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Bag Boots", itemID = 70 } }) })
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
		{ name = "Helm of Might", itemID = 61, kind = "loot" }, { name = "Helm of Valor", itemID = 62, kind = "loot" },
		{ name = "Helm of Rage", itemID = 63, kind = "loot" }, { name = "Shiny Helm of the Owl", itemID = 64, kind = "loot" } }) })
	UI.lastScan, UI.lastOverview = nil, nil
	ns.Easy.Set(true)
	UI.category = nil
	UI:Open("upgrades")
	local ov = UI.Results()
	local said
	for _, e in ipairs(ov) do
		if e.catId == "loot" then said = 1 + (tonumber(tostring(e.detail):match("(%d+)")) or 0) end
	end
	check(said == 3, "the overview: 3 upgrades in Dungeon loot: " .. tostring(said))
	has[61], has[62] = false, false
	UI:SetCategory("loot")
	local res = UI.Results()
	local n = 0
	for _, e in ipairs(res) do if e.itemID then n = n + 1 end end
	check(n == said, "stepping in, the client having let go of two meanwhile: the same 3 listed: " .. n)
	check(not tostring(UI.status:GetText()):find("stepped in", 1, true), "the number it said: no note")
	UI:SetCategory(nil)
	UI:Hide(); FlushAll()
	-- (0.51.11, the player: "Dungeon loot" said 100+, stepping in listed a steady 52) another number than its row said:
	-- the footer says the list was updated, for a few seconds
	UI:Open("upgrades")
	FlushAll()
	local canWas2 = C_PlayerInfo.CanUseItem
	C_PlayerInfo.CanUseItem = function(id) return id ~= 63 and has[id] ~= false end -- (63 no longer one, meanwhile)
	UI:SetCategory("loot")
	local foot = tostring(UI.status:GetText())
	check(foot:find("updated as you stepped in", 1, true) and foot:find("3", 1, true), "another number than it said: the footer says so: " .. foot)
	FlushAll()
	check(not tostring(UI.status:GetText()):find("stepped in", 1, true), "...for a few seconds")
	C_PlayerInfo.CanUseItem = canWas2
	UI:SetCategory(nil)
	UI:Hide(); FlushAll()

	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview, UI.category = nil, nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID, C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = save.invId, save.cached, save.req
	F.ClearCache()
	UI:Hide(); FlushAll()
end

-- (0.51.7, the player) "upgrades" said 133 in Dungeon loot and listed 100 there; and while item data came in, the list
-- was searched again every couple of seconds, its first frame's best put up meanwhile and the selection back on top
io.write("[upgrades: a list's every match; searched again as data comes in, the list and selection stay]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	local function Rows(n, fmt, base)
		local rows
		return function()
			if rows then return rows end -- (the same rows each read, as a list that didn't change)
			rows = {}
			for i = 1, n do rows[i] = { name = fmt:format(i), itemID = base + i, key = i } end
			return rows
		end
	end
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = Rows(150, "Helm %03d", 30000) })
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows(3000, "Pebble %04d", 40000) })
	ns.Easy.Set(true)
	UI.lastScan, UI.lastOverview = nil, nil
	UI:Open("helm")
	FlushAll()
	UI:SetCategory("loot")
	FlushAll()
	check(#UI.results == 150, "Simple mode, Dungeon loot: all 150 helms, not the best 100: " .. #UI.results)
	UI:SetCategory(nil)
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Open("pebble")
	FlushAll()
	check(#UI.results == 100, "a search of every list: still its best 100: " .. #UI.results)
	UI:Hide(); FlushAll()
	-- searched again because item data came in (RetryWhenLoaded), the search going over frames
	UI:Open("pebble")
	FlushAll()
	UI.sel, UI.offset = 40, 35
	local shown, picked = UI.results, UI.results[40]
	local realClock, ms = _G.debugprofilestop, 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end -- every look at the clock: 1 ms
	UI.lastScan = nil
	UI.refreshedAt, UI.searchedText = nil, nil
	UI.quietRedo = true
	UI:Refresh()
	local going = UI.searchJob ~= nil
	check(going and UI.results == shown and UI.sel == 40 and UI.offset == 35,
		"searched again, still going: the list shown stays, the row selected too (" .. tostring(going) .. ", sel " .. UI.sel .. ")")
	FlushAll()
	_G.debugprofilestop = realClock
	check(UI.results[UI.sel] == picked and UI.sel - UI.offset == 5, "done: the same row selected, where it was on screen: "
		.. tostring(UI.results[UI.sel] and UI.results[UI.sel].name))
	-- (0.51.8, the player: "generate a result list and stick with it") what it found new waits for F5
	local items = ns.providers.items
	local list = ns:GetEntries(items)
	table.insert(list, 1, { name = "Pebble 0000", itemID = 39999, key = 0 })
	shown = UI.results
	ms = 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	UI.lastScan, UI.refreshedAt, UI.searchedText = nil, nil, nil
	UI.quietRedo = true
	UI:Refresh()
	FlushAll()
	_G.debugprofilestop = realClock
	check(UI.results == shown and UI.held and UI.results[UI.sel] == picked, "found more in the background: the list shown stays ("
		.. tostring(UI.held ~= nil) .. ")")
	check(tostring(UI.status:GetText()):find("F5", 1, true), "...the footer says F5 shows them: " .. tostring(UI.status:GetText()))
	T.key("F5")
	FlushAll()
	check(UI.results[1].name == "Pebble 0000" and not UI.held and UI.results[UI.sel] == picked,
		"F5: the new results, the same row selected: " .. tostring(UI.results[1].name))
	check(not tostring(UI.status:GetText()):find("F5", 1, true), "...and the footer no longer says so")
	-- F5 with nothing new: nothing changes (0.51.9, the player: pressing it again unsettled the list)
	shown = UI.results
	T.key("F5")
	check(UI.results == shown and not UI.searchJob, "F5, nothing new: the list as it was, no search run")
	-- the same text searched again (a category picked, a list read again): the list shown stays till it's done
	ms = 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	UI.lastScan = nil
	UI:Research()
	check(UI.searchJob and UI.results == shown, "searched again, still going: the list shown stays till it's done")
	FlushAll()
	_G.debugprofilestop = realClock
	-- found the same: nothing held, nothing said
	UI.lastScan, UI.refreshedAt, UI.searchedText = nil, nil, nil
	UI.quietRedo = true
	UI:Refresh()
	FlushAll()
	check(not UI.held, "searched again, the same found: nothing held")
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview, UI.category = nil, nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end

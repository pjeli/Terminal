-- (0.51.15, the player's ask) upgrades from quests: "quest upgrades" lists the quests near your level you can still take
-- whose reward is an upgrade for you, the biggest first, with what it rewards and how far its giver is; @questie
-- is:upgrade judges a quest by its rewards.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, QD, QR, F = ns.Integrations, ns.QuestieData, ns.QuestRewards, ns.Filters

local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end
local function Entity(rows)
	local ids = {}
	for id in pairs(rows) do ids[#ids + 1] = id end
	table.sort(ids)
	return { Get = function(id, field) return rows[id] and rows[id][field] end, GetAllIds = function() return ids end }
end
local function Fresh()
	I.npc.on, I.npc.list, I.npc.names, I.npc.busy = false, nil, nil, false
	I.qdb.list, I.qdb.names, I.qdb.busy = nil, nil, false
	drop("npc"); drop("questie")
	QD.ResetForTests()
	F.ClearCache()
	QR.Forget()
end
local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[questupgrades: quests whose reward is an upgrade]\n")

io.write("[vendorupgrades: upgrades you can buy, nearest vendor first]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
		easy = ns.db.easyMode, info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel,
		inv = _G.GetInventoryItemLink, can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo,
		inst = C_Item.GetItemInfoInstant, invId = _G.GetInventoryItemID, name = C_Item.GetItemNameByID,
		here = I.Here, dist = I.NpcDistance, head = _G.INVTYPE_HEAD, str = _G.ITEM_MOD_STRENGTH_SHORT,
		group = _G.UnitFactionGroup, tti = _G.C_TooltipInfo }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.UnitFactionGroup = function() return "Alliance" end
	_G.LibQuestieDB = {
		Quest = Entity({}),
		Npc = Entity({
			[300] = { name = "Near Smith", spawns = { [12] = { { 40, 60 } } }, npcFlags = 4, friendlyToFaction = "AH" },
			[301] = { name = "Far Quartermaster", spawns = { [12] = { { 10, 10 } } }, npcFlags = 4, friendlyToFaction = "A" },
			[302] = { name = "Horde Smith", spawns = { [12] = { { 50, 50 } } }, npcFlags = 4, friendlyToFaction = "H" },
			[303] = { name = "Junk Seller", spawns = { [12] = { { 45, 45 } } }, npcFlags = 4, friendlyToFaction = "AH" },
		}),
		Item = Entity({
			[9601] = { name = "Smith's Helm", vendors = { 300 } },
			[9602] = { name = "Timbermaw Helm", vendors = { 301, 302 } },
			[9603] = { name = "Weak Helm", vendors = { 303 } },
			[9604] = { name = "Linen Cloth", vendors = { 303 } },
		}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	local ITEMS = {
		[9600] = { "Worn Helm", "|Hitem:9600|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9601] = { "Smith's Helm", "|Hitem:9601|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9602] = { "Timbermaw Helm", "|Hitem:9602|h", 3, 24, 18, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9603] = { "Weak Helm", "|Hitem:9603|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9604] = { "Linen Cloth", "|Hitem:9604|h", 1, 5, 0, "Trade Goods", "Cloth", 20, "" },
	}
	local STATS = { [9600] = { ITEM_MOD_STRENGTH_SHORT = 3 }, [9601] = { ITEM_MOD_STRENGTH_SHORT = 6 },
		[9602] = { ITEM_MOD_STRENGTH_SHORT = 12 }, [9603] = { ITEM_MOD_STRENGTH_SHORT = 2 } }
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemNameByID = function(id) local t = ITEMS[idOf(id) or 0] return t and t[1] end
	C_Item.GetItemStats = function(link) return STATS[idOf(link)] end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	_G.UnitLevel = function() return 20 end
	C_PlayerInfo.CanUseItem = function() return true end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9600|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 9600 end end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	local DIST = { [300] = 40, [301] = 900, [302] = 60, [303] = 30 }
	I.NpcDistance = function(id) local d = DIST[id] if d then return d, { cont = 1, x = d, y = 0 } end end
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT = "Head", "Strength"
	_G.C_TooltipInfo = { GetItemByID = function(id)
		if id == 9602 then return { lines = { { leftText = "Timbermaw Helm" }, { leftText = "Requires Timbermaw Hold - Honored" } } } end
		return { lines = { { leftText = "x" } } }
	end }
	Fresh()
	QR.ForgetVendorItems()
	I.Setup(); FlushAll()

	for _, s in ipairs({ "upgrades i can buy", "vendor upgrades", "buyable upgrades", "upgrades for sale", "upgrades to buy nearby" }) do
		check(QR.BuyQuestion(s), s .. ": upgrades to buy")
	end
	for _, s in ipairs({ "upgrades", "quest upgrades", "vendor", "buy linen" }) do check(not QR.BuyQuestion(s), s .. ": not that question") end
	local items = QR.VendorItems()
	check(items and #items == 3, "equipment vendors sell (not cloth): " .. tostring(items and #items))
	ns.db.easyMode = true
	UI:Hide(); FlushAll()
	UI:Open("upgrades i can buy"); FlushAll()
	local res = UI.Results()
	check(Names(res) == "Near Smith | Far Quartermaster", "the friendly vendors selling an upgrade, nearest first: " .. Names(res))
	check(res[1] and res[1].detail:find("Sells Smith's Helm (+3)", 1, true), "what it sells, and what it gains: " .. tostring(res[1] and res[1].detail))
	check(res[2] and res[2].detail:find("needs Honored with Timbermaw Hold", 1, true), "a standing it needs: " .. tostring(res[2] and res[2].detail))
	check(ns.Easy.ToAdvanced("upgrades i can buy") == "@npc sells:upgrade faction:friendly sort:distance ", "Alt+`: " .. ns.Easy.ToAdvanced("upgrades i can buy"))
	UI:Hide(); FlushAll()
	-- (review) an item still coming from the server: the Advanced form is searched again once it's in, as the answer is
	local saveCached, saveReq = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID
	C_Item.IsItemDataCachedByID = function(id) if id == 9602 then return false end return true end
	C_Item.RequestLoadItemDataByID = function() end
	F.ClearCache(); QR.ForgetVendorItems()
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("@npc sells:upgrade faction:friendly sort:distance ")
	check(F.loading == true, "Advanced @npc sells:upgrade: searched again once the items are in: " .. tostring(F.loading))
	UI:Hide(); FlushAll()
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID = saveCached, saveReq
	F.ClearCache(); QR.ForgetVendorItems()
	-- Advanced: sells:upgrade
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Open("@npc sells:upgrade faction:friendly sort:distance "); FlushAll()
	res = UI.Results()
	local names = {}
	for _, e in ipairs(res) do if e.npcID or rawget(e, "key") then names[#names + 1] = tostring(e.name) end end
	check(table.concat(names, " | ") == "Near Smith | Far Quartermaster", "@npc sells:upgrade: the same: " .. table.concat(names, " | "))
	UI:Hide(); FlushAll()
	-- (review) a long stock judged over several frames: never inside the filter's pcall (a yield there is an error, and
	-- every vendor was dropped)
	local Item = _G.LibQuestieDB.Item
	local rows = {}
	for _, id in ipairs(Item.GetAllIds()) do rows[id] = { name = Item.Get(id, "name"), vendors = Item.Get(id, "vendors") } end
	for i = 20000, 20300 do rows[i] = { name = "Filler " .. i, vendors = { 303 } } end
	local realLib, copy = _G.LibQuestieDB, {}
	for k, v in pairs(realLib) do copy[k] = v end
	copy.Item = Entity(rows)
	_G.LibQuestieDB = copy
	for i = 20000, 20300 do ITEMS[i] = { "Filler " .. i, "|Hitem:" .. i .. "|h", 1, 10, 5, "Armor", "Mail", 1, "INVTYPE_HEAD" } end
	Fresh(); QR.ForgetVendorItems(); I.Setup(); FlushAll()
	local realClock, ms = _G.debugprofilestop, 0
	_G.debugprofilestop = function() ms = ms + 5; return ms end
	UI:Open("@npc sells:upgrade faction:friendly sort:distance "); FlushAll()
	names = {}
	for _, e in ipairs(UI.Results()) do if e.npcID or rawget(e, "key") then names[#names + 1] = tostring(e.name) end end
	check(table.concat(names, " | ") == "Near Smith | Far Quartermaster", "a long stock, over several frames: the same: " .. table.concat(names, " | "))
	_G.debugprofilestop = realClock
	UI:Hide(); FlushAll()
	_G.LibQuestieDB = realLib
	for i = 20000, 20300 do ITEMS[i] = nil end
	Fresh(); QR.ForgetVendorItems(); I.Setup(); FlushAll()
	-- (review) the kept judging is for what you wear and the weights: a new helm put on is judged at once, not after
	-- two seconds
	local by = QR.VendorUpgrades()
	check(by and by[300] ~= nil, "the smith sells an upgrade over the worn helm")
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9602|h[Timbermaw Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 9602 end end
	by = QR.VendorUpgrades()
	check(by and by[300] == nil, "the Timbermaw helm put on: the smith's helm isn't one any more, at once")
	-- (review) a worn helm whose stats aren't known (a random suffix's, none read): helms better by item level alone
	-- aren't "upgrades you can buy", as on the auction house's list
	local realStats = C_Item.GetItemStats
	C_Item.GetItemStats = function(link) if tostring(link):find("of the Owl", 1, true) then return {} end return realStats(link) end
	ITEMS[9606] = { "Odd Helm", "|Hitem:9606|h", 2, 10, 5, "Armor", "Mail", 1, "INVTYPE_HEAD" }
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9606::::::-20|h[Odd Helm of the Owl]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 9606 end end
	by = QR.VendorUpgrades()
	check(by and next(by) == nil, "over a helm whose stats aren't known: none by item level alone")
	C_Item.GetItemStats, ITEMS[9606] = realStats, nil
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9600|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 9600 end end
	F.ClearCache(); QR.ForgetVendorItems()

	Fresh()
	QR.ForgetVendorItems()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
	_G.UnitRace, _G.UnitClass, ns.db.easyMode = save.race, save.class, save.easy
	UI:EasyChanged()
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, C_Item.GetItemInfoInstant = save.can, save.det, save.inst
	_G.GetInventoryItemID, C_Item.GetItemNameByID = save.invId, save.name
	I.Here, I.NpcDistance, _G.UnitFactionGroup, _G.C_TooltipInfo = save.here, save.dist, save.group, save.tti
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT = save.head, save.str
	I.Setup(); FlushAll()
end

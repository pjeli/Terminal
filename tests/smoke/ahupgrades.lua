-- The cheapest upgrades on the auction house (0.66.13, the player): "ah upgrades", "cheapest upgrades on the ah":
-- AtlasLoot's bind-on-equip items that are clear upgrades, at Auctionator's last-scanned price, the most gain per gold
-- first. AuctionValues.lua (AN.Upgrades).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local AN, F = ns.Auctionator, ns.Filters
local L = ns.L

io.write("[ahupgrades: upgrades on the auction house, the most gain per gold first]\n")
do
	local AHU = ns.AhUpgradesQ
	check(AHU.Question("ah upgrades") == nil, "without Auctionator: not asked")
	local save = { ac = rawget(_G, "Auctionator"), addons = _G.C_AddOns, info = C_Item.GetItemInfo, stats = C_Item.GetItemStats,
		level = _G.UnitLevel, inv = _G.GetInventoryItemLink, invId = _G.GetInventoryItemID, can = C_PlayerInfo.CanUseItem,
		det = C_Item.GetDetailedItemLevelInfo, inst = C_Item.GetItemInfoInstant, class = _G.UnitClass,
		providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, str = _G.ITEM_MOD_STRENGTH_SHORT,
		points = ns.Talents.Points }
	local PRICES = { [9701] = 30000, [9702] = 5000, [9703] = 1000, [9704] = 900, [9705] = 2000 }
	local AGES = { [9701] = 4 }
	_G.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(_, id) return PRICES[id] end,
		GetAuctionPriceByItemLink = function(_, link) return PRICES[tonumber(link:match("|Hitem:(%d+)"))] end,
		GetAuctionAgeByItemID = function(_, id) return AGES[id] end,
		GetAuctionAgeByItemLink = function(_, link) return AGES[tonumber(link:match("|Hitem:(%d+)"))] end,
	} } }
	_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) return n == "Auctionator" or save.addons.IsAddOnLoaded(n) end },
		{ __index = save.addons })
	-- name, link, quality, ilvl, minLevel, type, subtype, stack, equipLoc, icon, sell, class, subclass, bindType
	local ITEMS = {
		[9700] = { "Worn Helm", 20, 15, "INVTYPE_HEAD", 2 },
		[9701] = { "Pricey Helm", 24, 18, "INVTYPE_HEAD", 2 }, -- (+9 for 3g: 3 per gold)
		[9702] = { "Bargain Helm", 22, 16, "INVTYPE_HEAD", 2 }, -- (+4 for 50s: 8 per gold)
		[9703] = { "Bound Helm", 22, 16, "INVTYPE_HEAD", 1 }, -- (bound when picked up: never on the auction house)
		[9704] = { "Weak Helm", 22, 16, "INVTYPE_HEAD", 2 }, -- (no upgrade)
		[9705] = { "Bargain Boots", 22, 16, "INVTYPE_FEET", 2 }, -- (nothing worn there: +5 for 20s, 25 per gold)
	}
	local STATS = { [9700] = { ITEM_MOD_STRENGTH_SHORT = 3 }, [9701] = { ITEM_MOD_STRENGTH_SHORT = 12 },
		[9702] = { ITEM_MOD_STRENGTH_SHORT = 7 }, [9703] = { ITEM_MOD_STRENGTH_SHORT = 20 }, [9704] = { ITEM_MOD_STRENGTH_SHORT = 2 },
		[9705] = { ITEM_MOD_STRENGTH_SHORT = 5 } }
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id)
		local t = ITEMS[idOf(id) or 0]
		if not t then return save.info(id) end
		local n = idOf(id)
		return t[1], "|Hitem:" .. n .. "|h", 2, t[2], t[3], "Armor", "Mail", 1, t[4], 0, 10, 4, 3, t[5]
	end
	C_Item.GetItemStats = function(link) return STATS[idOf(link)] end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[2] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), "Armor", "Mail", t and t[4] end
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	ns.Talents.Points = function() return {} end
	C_PlayerInfo.CanUseItem = function() return true end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9700|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 9700 end end
	_G.ITEM_MOD_STRENGTH_SHORT = "Strength"
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
		local out = {}
		-- (as AtlasLoot's rows are: compact, their Enter and link from their metatable; review)
		local meta = ns:CompactMeta(ns.providers.loot, { activate = function() end }, { link = function(t) return "item:" .. t.itemID end })
		for id, t in pairs(ITEMS) do if id ~= 9700 then out[#out + 1] = setmetatable({ name = t[1], itemID = id, key = id, detail = "Boss  Dungeon" }, meta) end end
		return out
	end })
	ns:AliasesChanged()
	F.ClearCache()
	AN.Forget()
	UI.lastScan, UI.lastExtra = nil, nil

	for _, s in ipairs({ "ah upgrades", "cheapest upgrades on the ah", "upgrades on the auction house", "upgrades i can buy on the ah" }) do
		check(AHU.Question(s), s .. ": the auction house's upgrades")
	end
	check(not AHU.Question("upgrades") and not AHU.Question("ah value of my mats") and not AHU.Question("vendor upgrades"), "not those")
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("cheapest upgrades on the ah"); FlushAll()
	local names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = tostring(e.name) end
	check(table.concat(names, " | ") == "Bargain Boots | Bargain Helm | Pricey Helm", "the most gain per gold first, BoE only: " .. table.concat(names, " | "))
	local r = UI.Results()
	check(r[2] and r[2].detail:find("+4 for", 1, true) and r[3] and r[3].detail:find(L["seen %d days ago"]:format(4), 1, true),
		"each says its gain and price, and when it was seen: " .. tostring(r[2] and r[2].detail) .. " / " .. tostring(r[3] and r[3].detail))
	check(tostring(UI.status:GetText()):find(L["at Auctionator's last-scanned prices"], 1, true), "the footer says whose prices")
	check(F.GainOf(r[2]) ~= nil, "its tooltip compares it (the gain kept)")
	check(r[2] and r[2].kind == "loot" and r[2].activate ~= nil and r[2].link ~= nil, "a view of the loot row: its Enter and link kept (review)")
	UI:Hide(); FlushAll()
	-- (0.66.x, the player's screenshot) the worn piece's own link gives no stats (an empty table): its plain item's are
	-- read, not "nothing worn there to beat"; none at all: not compared against nothing
	local realStats = C_Item.GetItemStats
	C_Item.GetItemStats = function(link)
		if tostring(link):find("[Worn Helm]", 1, true) then return {} end
		return realStats(link)
	end
	F.ClearCache(); F.ClearFit()
	UI:Open(""); FlushAll()
	UI:SetQuery("ah upgrades"); FlushAll()
	names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = tostring(e.name) end
	check(table.concat(names, " | ") == "Bargain Boots | Bargain Helm | Pricey Helm", "the worn helm's stats from its plain item: " .. table.concat(names, " | "))
	local gotHelm
	for _, e in ipairs(UI.Results()) do if e.name == "Bargain Helm" then gotHelm = F.GainOf(e) end end
	check(gotHelm and math.abs(gotHelm.gain - 4) < 1e-6, "Bargain Helm gains +4 over the worn helm's +3, not +7 over nothing: " .. tostring(gotHelm and gotHelm.gain))
	C_Item.GetItemStats = function(link)
		if tostring(link):find("item:9700", 1, true) then return {} end
		return realStats(link)
	end
	F.ClearCache(); F.ClearFit()
	UI:SetQuery("cheapest upgrades on the ah"); FlushAll()
	names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = tostring(e.name) end
	check(not table.concat(names, " | "):find("Helm", 1, true), "no stats for the worn helm at all: no helm judged against nothing: " .. table.concat(names, " | "))
	-- (review) a worn piece with a random suffix ("of the Monkey"): its plain item has armor alone, not its stats, so
	-- they aren't read for it; not known, it's not judged against the plain item's
	C_Item.GetItemStats = function(link)
		if tostring(link):find("[Worn Helm of the Monkey]", 1, true) then return {} end
		return realStats(link)
	end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9700::::::-15|h[Worn Helm of the Monkey]|h" end end
	F.ClearCache(); F.ClearFit()
	UI:SetQuery("ah upgrades"); FlushAll()
	names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = tostring(e.name) end
	check(not table.concat(names, " | "):find("Helm", 1, true), "a random suffix's worn helm: not judged by its plain item's stats: " .. table.concat(names, " | "))
	C_Item.GetItemStats = realStats
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9700|h[Worn Helm]|h" end end
	UI:Hide(); FlushAll()

	-- (review) trinkets: worn ones with no stats at all (as many have) are believed, and kept, not read again on every
	-- search; a statless trinket a few item levels up is an upgrade by item level alone, which the auction house's list
	-- of gains per gold leaves out (two slots: it was said as +10 "gain", over real stat upgrades)
	ITEMS[9710] = { "Old Charm", 20, 15, "INVTYPE_TRINKET", 2 }
	ITEMS[9711] = { "Old Token", 20, 15, "INVTYPE_TRINKET", 2 }
	ITEMS[9712] = { "Shiny Charm", 30, 20, "INVTYPE_TRINKET", 2 }
	STATS[9710], STATS[9711], STATS[9712] = {}, {}, nil
	PRICES[9712] = 10000
	local reads = 0
	C_Item.GetItemStats = function(link)
		if tostring(link):find("Old ", 1, true) then reads = reads + 1 end
		return realStats(link)
	end
	_G.GetInventoryItemLink = function(_, slot)
		if slot == 1 then return "|Hitem:9700|h[Worn Helm]|h" end
		if slot == 13 then return "|Hitem:9710|h[Old Charm]|h" end
		if slot == 14 then return "|Hitem:9711|h[Old Token]|h" end
	end
	F.ClearCache(); F.ClearFit()
	ns:Changed("loot") -- (AtlasLoot's rows: the trinkets among them)
	F.GearFit()
	local firstReads = reads
	F.GearFit()
	check(firstReads > 0 and reads == firstReads, "worn trinkets with no stats: read once, kept: " .. firstReads .. " then " .. reads)
	UI:SetQuery("cheapest upgrades on the ah"); FlushAll()
	names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = tostring(e.name) end
	check(table.concat(names, " | ") == "Bargain Boots | Bargain Helm | Pricey Helm", "a trinket better by item level alone: not a gain per gold: " .. table.concat(names, " | "))
	-- (review) AtlasLoot's equipment worked out once, not again on each search made again as items arrive
	local realInst, instCalls = C_Item.GetItemInfoInstant, 0
	C_Item.GetItemInfoInstant = function(id) instCalls = instCalls + 1 return realInst(id) end
	ns:Changed("loot")
	ns.AhUpgradesQ.Answer()
	local firstInst = instCalls
	instCalls = 0
	ns.AhUpgradesQ.Answer()
	check(instCalls < firstInst, "the equipment among AtlasLoot's rows: worked out once: " .. firstInst .. " then " .. instCalls)
	C_Item.GetItemInfoInstant = realInst
	ITEMS[9710], ITEMS[9711], ITEMS[9712], PRICES[9712] = nil, nil, nil, nil
	ns:Changed("loot")
	C_Item.GetItemStats = realStats
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9700|h[Worn Helm]|h" end end
	F.ClearCache(); F.ClearFit()
	UI:Hide(); FlushAll()

	_G.Auctionator, _G.C_AddOns = save.ac, save.addons
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	_G.GetInventoryItemID, C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo = save.invId, save.can, save.det
	C_Item.GetItemInfoInstant, _G.UnitClass, _G.ITEM_MOD_STRENGTH_SHORT = save.inst, save.class, save.str
	ns.Talents.Points = save.points
	ns.providers, ns.providerOrder, ns.db.easyMode = save.providers, save.order, save.easy
	ns:AliasesChanged(); UI:EasyChanged()
	F.ClearCache()
	AN.Forget()
	UI.lastScan, UI.lastExtra = nil, nil
end

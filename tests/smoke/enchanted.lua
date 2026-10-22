-- is:enchanted and is:unenchanted (0.64.2, the player: "an is:enchanted filter for gear in bags and bank"): each copy's
-- link says its enchant; a row stands for every copy of an item, so a copy with one and one without answer both.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F = ns.Filters

io.write("[is:enchanted, is:unenchanted]\n")
do
	local function L(id, ench, name) return ("|cff1eff00|Hitem:%d:%s::::::::|h[%s]|h|r"):format(id, ench or "", name) end
	check(ns.LinkEnchant(L(1, "1897", "x")) == 1897 and ns.LinkEnchant(L(1, nil, "x")) == 0 and ns.LinkEnchant("item:5:0:0") == 0
		and ns.LinkEnchant("1234:1897:0") == 1897 and ns.LinkEnchant(nil) == nil, "an enchant read from a link, an item string, BagBrother's")
	local E, U = F.Parse("is:enchanted"), F.Parse("is:unenchanted")
	-- a row with only a link (loot, a friend's): what its link says
	local sword = { itemID = 1, link = L(1, "1897", "Sword") }
	check(E(sword) and not U(sword), "a link with an enchant: enchanted")
	-- a row of yours that knows its copies
	check(E({ itemID = 1, enchanted = true, unenchanted = true }) and E({ itemID = 1, enchanted = true }), "one copy enchanted: enchanted")
	check(not E({ itemID = 1, unenchanted = true }), "none: not")

	-- your bags: one sword enchanted, one not; a plain cloak; cloth (not gear: never unenchanted)
	local saveC, saveBagIDs, saveInstant = _G.C_Container, ns.Bags.BagIDs, C_Item.GetItemInfoInstant
	local bag = {
		{ itemID = 9001, hyperlink = L(9001, "1897", "Zzench Sword"), stackCount = 1, iconFileID = 1, quality = 2 },
		{ itemID = 9001, hyperlink = L(9001, nil, "Zzench Sword"), stackCount = 1, iconFileID = 1, quality = 2 },
		{ itemID = 9002, hyperlink = L(9002, nil, "Zzench Cloak"), stackCount = 1, iconFileID = 1, quality = 2 },
		{ itemID = 9003, hyperlink = L(9003, "1843", "Zzench Helm"), stackCount = 1, iconFileID = 1, quality = 2 },
		{ itemID = 9004, hyperlink = L(9004, nil, "Zzench Cloth"), stackCount = 20, iconFileID = 1, quality = 1 },
	}
	_G.C_Container = setmetatable({ GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end,
		GetContainerItemInfo = function(b, s) return b == 0 and bag[s] or nil end }, { __index = saveC })
	ns.Bags.BagIDs = function() return { 0 } end
	local GEAR = { [9001] = "INVTYPE_WEAPON", [9002] = "INVTYPE_CLOAK", [9003] = "INVTYPE_HEAD" }
	C_Item.GetItemInfoInstant = function(id)
		if GEAR[id] then return id, "Armor", "Misc", GEAR[id], 1, 4, 0 end
		if id == 9004 then return id, "Trade Goods", "Cloth", "", 1, 7, 5 end
		return saveInstant(id)
	end
	ns.providers.items._dirty = true
	local easy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	local function Names(q)
		UI.lastScan = nil
		local t = {}
		for _, e in ipairs(UI:Search(q)) do t[#t + 1] = e.name end
		table.sort(t)
		return table.concat(t, " | ")
	end
	check(Names("@item zzench is:enchanted") == "Zzench Helm | Zzench Sword", "is:enchanted in your bags: " .. Names("@item zzench is:enchanted"))
	check(Names("@item zzench is:unenchanted") == "Zzench Cloak | Zzench Sword", "is:unenchanted: gear without one (not the cloth): "
		.. Names("@item zzench is:unenchanted"))
	_G.C_Container, ns.Bags.BagIDs, C_Item.GetItemInfoInstant = saveC, saveBagIDs, saveInstant
	ns.providers.items._dirty = true

	-- your bank (Syndicator's records): each copy's link, by where it is
	local S = ns.Stored
	local saveSyn, saveSource = rawget(_G, "Syndicator"), S.Source
	local function it(id, ench, name) return { itemID = id, itemCount = 1, itemLink = L(id, ench, name), quality = 2 } end
	local CH = {
		["Me-Forever"] = { details = { character = "Me" }, bags = {}, mail = {}, equipped = {},
			bank = { { it(9101, "1897", "Zzbank Sword"), it(9102, nil, "Zzbank Gloves") } } },
		["Alt-Forever"] = { details = { character = "Alt" }, bank = {}, mail = {}, equipped = {},
			bags = { { it(9102, "2564", "Zzbank Gloves") } } },
	}
	_G.Syndicator = { API = {
		IsReady = function() return true end,
		GetCurrentCharacter = function() return "Me-Forever" end,
		GetAllCharacters = function() return { "Me-Forever", "Alt-Forever" } end,
		GetByCharacterFullName = function(n) return CH[n] end,
		GetInventoryInfoByItemID = function(id)
			local res = { characters = {}, guilds = {}, warband = { 0 } }
			for full, c in pairs(CH) do
				local r = { character = c.details.character, realmNormalized = "Forever", bags = 0, bank = 0, mail = 0, equipped = 0, void = 0, auctions = 0 }
				for _, b in ipairs(c.bags) do for _, x in ipairs(b) do if x.itemID == id then r.bags = r.bags + 1 end end end
				for _, b in ipairs(c.bank) do for _, x in ipairs(b) do if x.itemID == id then r.bank = r.bank + 1 end end end
				if r.bags + r.bank > 0 then res.characters[#res.characters + 1] = r end
			end
			return res
		end,
	} }
	S.Source = function() return "Syndicator" end
	C_Item.GetItemInfoInstant = function(id)
		if id == 9101 or id == 9102 then return id, "Armor", "Misc", id == 9101 and "INVTYPE_WEAPON" or "INVTYPE_HAND", 1, 4, 0 end
		return saveInstant(id)
	end
	ns.providers.stored._dirty = true
	ns.providers.bank._dirty = true
	check(Names("@bank zzbank is:enchanted") == "Zzbank Sword", "is:enchanted in your bank: " .. Names("@bank zzbank is:enchanted"))
	check(Names("@bank zzbank is:unenchanted") == "Zzbank Gloves", "your bank's gloves aren't, though your alt's are: " .. Names("@bank zzbank is:unenchanted"))
	check(Names("@stored zzbank is:enchanted") == "Zzbank Gloves | Zzbank Sword", "@stored: any copy anywhere: " .. Names("@stored zzbank is:enchanted"))
	_G.Syndicator, S.Source, C_Item.GetItemInfoInstant = saveSyn, saveSource, saveInstant
	ns.providers.stored._dirty = true
	ns.providers.bank._dirty = true
	ns.db.easyMode = easy; UI:EasyChanged()
	UI.lastScan = nil
end

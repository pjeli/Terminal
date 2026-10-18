-- Upgrades judged by what you want (0.56.14, the player: "upgrades from quests" offered a warrior Snake Hoop, Intellect
-- and Spell Power, over rings of Strength and Agility). An item whose stats are all ones your weights don't count is
-- worth nothing to you, not unknown: no item level makes it an upgrade, nor an empty slot.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local F = ns.Filters

io.write("[upgradestats: stats you don't want are worth nothing]\n")
do
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel, inv = _G.GetInventoryItemLink,
		can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo, class = _G.UnitClass, inst = C_Item.GetItemInfoInstant,
		invId = _G.GetInventoryItemID, providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode,
		roles = ns.db.upgradeRoles, dual = _G.CanDualWield }
	local ITEMS = {
		[90] = { "Band of the Fist", "|Hitem:90|h", 2, 25, 20, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" },
		[91] = { "Seal of Sylvanas", "|Hitem:91|h", 2, 25, 20, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" },
		[92] = { "Iron Helm", "|Hitem:92|h", 2, 25, 20, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[93] = { "Snake Hoop", "|Hitem:93|h", 2, 32, 28, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" },
		[94] = { "Sage's Cap", "|Hitem:94|h", 2, 32, 28, "Armor", "Cloth", 1, "INVTYPE_HEAD" },
		[95] = { "Tiger Band", "|Hitem:95|h", 2, 32, 28, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" },
		[96] = { "Mystic Pendant", "|Hitem:96|h", 2, 30, 28, "Armor", "Miscellaneous", 1, "INVTYPE_NECK" },
		[97] = { "Brute Pendant", "|Hitem:97|h", 2, 30, 28, "Armor", "Miscellaneous", 1, "INVTYPE_NECK" },
	}
	local STATS = {
		[90] = { ITEM_MOD_AGILITY_SHORT = 4, ITEM_MOD_STRENGTH_SHORT = 4 },
		[91] = { ITEM_MOD_ATTACK_POWER_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 8 },
		[92] = { ITEM_MOD_STRENGTH_SHORT = 5, RESISTANCE0_NAME = 150 },
		[93] = { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPELL_POWER_SHORT = 6 },
		[94] = { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPIRIT_SHORT = 4 },
		[95] = { ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_AGILITY_SHORT = 5 },
		[96] = { ITEM_MOD_INTELLECT_SHORT = 6 },
		[97] = { ITEM_MOD_STRENGTH_SHORT = 6 },
	}
	local WORN = { [1] = 92, [11] = 90, [12] = 91 }
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemStats = function(link) return STATS[idOf(link)] end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	_G.UnitLevel = function() return 30 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.CanDualWield = function() return true end
	C_PlayerInfo.CanUseItem = function() return true end
	_G.GetInventoryItemLink = function(_, slot) local id = WORN[slot] return id and ("|Hitem:" .. id .. "|h[" .. ITEMS[id][1] .. "]|h") or nil end
	_G.GetInventoryItemID = function(_, slot) return WORN[slot] end
	F.ClearCache()
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
		local out = {}
		for id = 93, 97 do out[#out + 1] = { name = ITEMS[id][1], itemID = id, key = id, link = "item:" .. id } end
		return out
	end })
	ns.db.easyMode = false
	local function Upgrades()
		local t = {}
		for _, e in ipairs(UI:Search("@loot is:upgrade")) do if e.itemID then t[#t + 1] = e.name end end
		table.sort(t)
		return table.concat(t, ", ")
	end
	for _, roles in ipairs({ { "all-round", nil }, { "damage", { "dps" } }, { "tank", { "tank" } } }) do
		ns.db.upgradeRoles = nil
		if roles[2] then F.SetRoles(roles[2]) end
		F.ClearCache()
		local got = Upgrades()
		-- (Tiger Band: Strength and Agility over both rings; Brute Pendant: Strength in an empty neck slot)
		check(got == "Brute Pendant, Tiger Band", roles[1] .. ": the Strength ring and pendant, never the Intellect ones "
			.. "(a higher item level, an empty slot): " .. got)
	end
	local k = F.StatKinds({ ITEM_MOD_HIT_SPELL_RATING_SHORT = 1, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 1, ITEM_MOD_HIT_RATING_SHORT = 2,
		ITEM_MOD_FERAL_ATTACK_POWER_SHORT = 30, ITEM_MOD_ATTACK_POWER_SHORT = 10 })
	check(k.spellhit == 1 and k.spellcrit == 1 and k.hit == 2 and k.feralap == 30 and k.ap == 10,
		"spells' hit and crit, and feral attack power, are their own stats (not a warrior's hit, crit or attack power)")
	check(F.Worth({ spellhit = 1, feralap = 30 }, F.WEIGHTS.WARRIOR) == 0 and F.Worth({ spellhit = 1 }, F.WEIGHTS.MAGE) > 0
		and F.Worth({ feralap = 30 }, F.ROLES.DRUID[3][2]) > 0, "worth to whom they're for")
	check(F.Worth({ int = 5, sp = 6 }, F.ROLES.WARRIOR[1][2]) == 0 and F.Worth({}, F.WEIGHTS.WARRIOR) == nil
		and F.Worth({ str = 2 }, F.WEIGHTS.WARRIOR) == 2, "worth: 0 when none of its stats are wanted, nil with none to weigh")

	-- (release review) a healer's weights have no dps: a plain wand isn't worth 0 (item levels decide), unless it would
	-- replace one with stats a healer weighs
	ITEMS[110] = { "Plain Wand", "|Hitem:110|h", 2, 24, 20, "Weapon", "Wands", 1, "INVTYPE_RANGEDRIGHT" }
	ITEMS[111] = { "Better Plain Wand", "|Hitem:111|h", 2, 32, 28, "Weapon", "Wands", 1, "INVTYPE_RANGEDRIGHT" }
	ITEMS[112] = { "Sage's Wand", "|Hitem:112|h", 2, 24, 20, "Weapon", "Wands", 1, "INVTYPE_RANGEDRIGHT" }
	STATS[110], STATS[111] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 }
	STATS[112] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9, ITEM_MOD_INTELLECT_SHORT = 4 }
	check(F.Worth({ dps = 15 }, F.ROLES.PRIEST[1][2]) == nil, "a plain weapon to a healer: unweighed (item levels decide), not worth 0")
	_G.UnitClass = function() return "Priest", "PRIEST", 5 end
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
		return { { name = "Better Plain Wand", itemID = 111, key = 111, link = "item:111" } }
	end })
	ns.db.upgradeRoles = nil
	F.SetRoles({ "healer" })
	WORN = { [18] = 110 }
	F.ClearCache()
	check(Upgrades() == "Better Plain Wand", "a healer: a plain wand of a higher level over a plain one: " .. Upgrades())
	WORN = { [18] = 112 }
	F.ClearCache()
	check(Upgrades() == "", "over a wand with Intellect: not one: " .. Upgrades())

	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID, ns.providers, ns.providerOrder, ns.db.easyMode = save.invId, save.providers, save.order, save.easy
	ns.db.upgradeRoles, _G.CanDualWield = save.roles, save.dual
	F.ClearCache()
end

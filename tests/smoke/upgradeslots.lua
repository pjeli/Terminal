-- (release review, 0.53.0) two slots an item could go in (rings, trinkets, dual wielding): an upgrade over either piece is
-- one, not only over the weaker by worth; a random suffix's copy of what you wear ("of the Monkey" while you wear "of the
-- Eagle") is another item.
local T = ...
local ns, check = T.ns, T.check
local F = ns.Filters

io.write("[upgrade slots: either ring, suffix copies]\n")
local save = { gii = C_Item.GetItemInfo, gis = C_Item.GetItemStats, gdl = C_Item.GetDetailedItemLevelInfo,
	gii2 = C_Item.GetItemInfoInstant, cached = C_Item.IsItemDataCachedByID, level = _G.UnitLevel, class = _G.UnitClass,
	can = C_PlayerInfo.CanUseItem, link = _G.GetInventoryItemLink, id = _G.GetInventoryItemID }
local ITEMS = {
	[980] = { "Agi Ring", "|Hitem:980|h", 2, 20, 15, "Armor", "Misc", 1, "INVTYPE_FINGER" },
	[981] = { "Str Ring", "|Hitem:981|h", 2, 20, 15, "Armor", "Misc", 1, "INVTYPE_FINGER" },
	[982] = { "Better Str Ring", "|Hitem:982|h", 2, 20, 15, "Armor", "Misc", 1, "INVTYPE_FINGER" },
}
local STATS = { [980] = { ITEM_MOD_AGILITY_SHORT = 8 }, [981] = { ITEM_MOD_STRENGTH_SHORT = 7 },
	[982] = { ITEM_MOD_STRENGTH_SHORT = 10 } }
local function IdOf(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
C_Item.GetItemInfo = function(id) local t = ITEMS[IdOf(id) or 0] if t then return unpack(t) end end
C_Item.GetItemStats = function(link)
	-- (a suffix's copy: "of the Monkey" (suffix 7) has far more)
	if tostring(link):find("item:981:0:0:0:0:0:7", 1, true) then return { ITEM_MOD_STRENGTH_SHORT = 20 } end
	return STATS[IdOf(link)]
end
C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[IdOf(link)] return t and t[4] end
C_Item.GetItemInfoInstant = function(id) local t = ITEMS[IdOf(id)] return IdOf(id), t and t[6], t and t[7], t and t[9] end
C_Item.IsItemDataCachedByID = function() return true end
_G.UnitLevel = function() return 20 end
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
C_PlayerInfo.CanUseItem = function() return true end
_G.GetInventoryItemLink = function(_, slot)
	if slot == 11 then return "|Hitem:980|h[Agi Ring]|h" end
	if slot == 12 then return "|Hitem:981:0:0:0:0:0:3|h[Str Ring of the Eagle]|h" end
end
_G.GetInventoryItemID = function(_, slot) if slot == 11 then return 980 elseif slot == 12 then return 981 end end
F.ClearCache()
local fit = F.GearFit()
check(fit({ itemID = 982, kind = "items" }), "+3 Strength over your Strength ring, nothing lost: an upgrade, though it'd give up "
	.. "more against your Agility ring")
local g = F.GainOf({ itemID = 982 }) -- (a new row: no gain of its own)
check(g == nil, "(gains are kept per row)")
check(not fit({ itemID = 981, kind = "items", link = "|Hitem:981:0:0:0:0:0:3|h[Str Ring of the Eagle]|h" }),
	"the very copy you wear: never an upgrade")
check(fit({ itemID = 981, kind = "items", link = "|Hitem:981:0:0:0:0:0:7|h[Str Ring of the Monkey]|h" }),
	"the same ring with another suffix, much better: an upgrade")

C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.GetDetailedItemLevelInfo = save.gii, save.gis, save.gdl
C_Item.GetItemInfoInstant, C_Item.IsItemDataCachedByID = save.gii2, save.cached
_G.UnitLevel, _G.UnitClass, C_PlayerInfo.CanUseItem = save.level, save.class, save.can
_G.GetInventoryItemLink, _G.GetInventoryItemID = save.link, save.id
F.ClearCache()

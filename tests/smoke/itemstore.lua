-- (0.51.13, the player's ask) what Terminal learned of items is kept between sessions: after a /reload "upgrades" and
-- the loot list's colours are right from the first search, not filled in as the game sends its items again.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F = ns.Filters
local S = ns.ItemStore

io.write("[itemstore: item details kept between sessions]\n")
do
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel, inv = _G.GetInventoryItemLink,
		can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo, class = _G.UnitClass, uname = _G.UnitName, inst = C_Item.GetItemInfoInstant,
		invId = _G.GetInventoryItemID, cached = C_Item.IsItemDataCachedByID, q = C_Item.GetItemQualityByID, build = _G.GetBuildInfo }
	local ITEMS = {
		[80] = { "Worn Helm", "|Hitem:80|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD", 1, 1, 4, 3, 2 },
		[81] = { "Helm of Might", "|Hitem:81|h", 3, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD", 1, 1, 4, 3, 2 },
	}
	local STATS = { [80] = { ITEM_MOD_STRENGTH_SHORT = 3 }, [81] = { ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 4 } }
	local has, answers = {}, true -- (the client has the item; the server answers)
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = answers and ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemStats = function(link) return answers and STATS[idOf(link)] or nil end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	C_Item.IsItemDataCachedByID = function(id) return has[id] ~= false end
	C_Item.GetItemQualityByID = function(id) if has[id] ~= false then local t = ITEMS[id] return t and t[3] end end
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.UnitName = function() return "Grom" end
	C_PlayerInfo.CanUseItem = function(id) return has[id] ~= false end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:80|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 80 end end
	_G.GetBuildInfo = function() return "1.60.1", "70001", "Oct 1 2026", 16001 end
	F.ClearCache()
	S.Clear("quality")

	local function up(id) return F.GearFit()({ kind = "loot", itemID = id }) end
	check(up(81), "a helm better for a warrior: an upgrade")
	local rec = S.Get("facts", 81)
	check(type(rec) == "string" and rec:find("INVTYPE_HEAD;16;22;2;", 1, true) and rec:find("str=7", 1, true)
		and rec:find("sta=4", 1, true) and rec:find(";Grom+", 1, true), "kept: its slot, levels, binding, stats, usable by this character: " .. tostring(rec))
	check(ns.ItemQuality(81) == 3, "its quality as the game says")
	-- a /reload: what the session knew is gone, the game hasn't sent the item again, the server doesn't answer yet
	F.ForgetSessionFit()
	ns.ForgetSessionQualities()
	has[81], answers = false, false
	check(up(81), "the next session, the game not having it yet: still an upgrade, as kept")
	check(ns.ItemQuality(81) == 3, "...and its colour from the first search")
	-- (review, 0.51.25) another character on the account, even of the same class: what Grom can use isn't said for them
	-- (a hunter wears mail from 40, another not yet), nor for a name Grom's begins
	for _, other in ipairs({ "Thrall", "Gromm", "Gro" }) do
		_G.UnitName = function() return other end
		F.ForgetSessionFit()
		check(not up(81), other .. ": not one (who can use it is kept per character; " .. other .. " was never asked)")
	end
	_G.UnitName = function() return "Grom" end
	F.ForgetSessionFit()
	check(up(81), "Grom again: as kept")
	-- (review, 0.51.25) mana per 5 kept too (its name has a digit)
	S.Put("facts", 82, "INVTYPE_HEAD;16;22;2;int=5,mp5=4,sta=3;Grom+")
	ITEMS[82] = ITEMS[81]
	F.ForgetSessionFit()
	F.GearFit()({ kind = "loot", itemID = 82 })
	check(F._fit()[82] and F._fit()[82].kinds.mp5 == 4 and F._fit()[82].kinds.int == 5, "a kept record's mp5 read back")
	-- a patch: everything kept is let go (items may have changed)
	_G.GetBuildInfo = function() return "1.61.0", "70500", "Nov 1 2026", 16001 end
	S.NewSession()
	check(S.Get("facts", 81) == nil and S.Get("quality", 81) == nil, "a new build of the game: what was kept is let go")
	-- a size limit: two generations at most
	local cap = S.CAP.quality
	S.CAP.quality = 3
	for i = 1, 10 do S.Put("quality", 900 + i, 2) end
	check(S.Count("quality") <= 6 and S.Get("quality", 910) == 2 and S.Get("quality", 901) == nil,
		"kept two generations of a few at most: " .. S.Count("quality"))
	S.CAP.quality = cap

	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.UnitName = save.uname
	_G.GetInventoryItemID, C_Item.IsItemDataCachedByID, C_Item.GetItemQualityByID = save.invId, save.cached, save.q
	_G.GetBuildInfo = save.build
	F.ClearCache()
	S.Clear("quality")
	ns.ForgetSessionQualities()
end

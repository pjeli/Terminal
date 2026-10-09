local ns = select(2, ...)

-- is:upgrade: gear that suits you now, weighed against what you wear (Core.lua's KEYS.is asks F.GearFit()).

local F = ns.Filters
local P = F._
local ItemInfo, ItemOf, Stats, SLOTS = P.ItemInfo, F.ItemOf, P.Stats, F.SLOTS
local Secret = ns.Secret

-- is:upgrade (Simple mode: "upgrades", "helm upgrades"): gear you can equip now (its required level is yours or lower,
-- and the game says you can use it: class, armour and weapon kind), not worn already, and better than what you wear
-- there (0.43.8). Better = more of what your class wants: the item's stats weighed for your class (F.WEIGHTS, a rough
-- Pawn-like scale: a warrior's strength, a mage's intellect and spell power, a weapon's damage per second), against
-- the piece you wear there (the weaker of two rings or trinkets; a two-hander against your main and off hand
-- together). When either side has no stats to weigh (most trinkets, plain white gear) or they aren't loaded yet:
-- a higher item level. Nothing worn there: within GEAR_EMPTY of your level. (0.41.28-0.43.7 only asked for an item
-- level within GEAR_BELOW of your weakest piece: lots of "upgrades" that weren't.)
F.GEAR_BELOW, F.GEAR_EMPTY, F.GEAR_ASK = 5, 10, 40

-- what a stat key is (ITEM_MOD_STRENGTH_SHORT -> "str"): the first part of the key that matches, in this order
local STAT_KINDS = {
	{ "RANGED_ATTACK_POWER", "rap" }, { "ATTACK_POWER", "ap" }, { "STRENGTH", "str" }, { "AGILITY", "agi" },
	{ "STAMINA", "sta" }, { "INTELLECT", "int" }, { "SPIRIT", "spi" }, { "HEALING", "heal" }, { "SPELL_DAMAGE", "sp" },
	{ "SPELL_POWER", "sp" }, { "CRIT", "crit" }, { "HIT", "hit" }, { "HASTE", "haste" }, { "REGEN", "mp5" },
	{ "DAMAGE_PER_SECOND", "dps" }, { "RESISTANCE0", "armor" }, { "DEFENSE", "def" }, { "DODGE", "dodge" },
	{ "PARRY", "parry" }, { "BLOCK", "block" },
}
local statKind = {}
local function StatKind(key)
	local k = statKind[key]
	if k == nil then
		k = false
		for _, p in ipairs(STAT_KINDS) do
			if key:find(p[1], 1, true) then k = p[2] break end
		end
		statKind[key] = k
	end
	return k or nil
end

-- how much each stat is worth to a class (rough: what it wants most is 1)
local GENERIC = { str = 0.6, agi = 0.6, int = 0.6, spi = 0.3, sta = 0.5, ap = 0.3, rap = 0.2, sp = 0.4, heal = 0.3,
	crit = 0.5, hit = 0.5, haste = 0.4, mp5 = 0.5, dps = 1.5, armor = 0.01, def = 0.3, dodge = 0.3, parry = 0.3, block = 0.2 }
F.WEIGHTS = {
	WARRIOR = { str = 1, agi = 0.7, sta = 0.6, ap = 0.5, crit = 0.8, hit = 0.8, haste = 0.5, dps = 3, armor = 0.02,
		def = 0.5, dodge = 0.5, parry = 0.5, block = 0.3 },
	PALADIN = { str = 1, int = 0.6, sta = 0.6, spi = 0.2, agi = 0.4, ap = 0.4, sp = 0.6, heal = 0.5, crit = 0.7,
		hit = 0.6, mp5 = 1, dps = 2.5, armor = 0.02, def = 0.4, block = 0.2 },
	HUNTER = { agi = 1, ap = 0.4, rap = 0.5, sta = 0.5, int = 0.3, spi = 0.1, crit = 0.8, hit = 0.8, haste = 0.5,
		dps = 2, armor = 0.01 },
	ROGUE = { agi = 1, str = 0.5, ap = 0.5, sta = 0.5, crit = 0.8, hit = 0.8, haste = 0.6, dps = 3, armor = 0.01 },
	PRIEST = { int = 1, spi = 0.8, sta = 0.5, sp = 0.8, heal = 0.8, crit = 0.5, haste = 0.4, mp5 = 1.2, dps = 0.3,
		armor = 0.005 },
	MAGE = { int = 1, spi = 0.5, sta = 0.5, sp = 1, crit = 0.7, hit = 0.8, haste = 0.5, mp5 = 0.8, dps = 0.3,
		armor = 0.005 },
	WARLOCK = { int = 0.8, spi = 0.4, sta = 0.7, sp = 1, crit = 0.5, hit = 0.8, haste = 0.5, mp5 = 0.6, dps = 0.3,
		armor = 0.005 },
	SHAMAN = { int = 0.8, str = 0.6, agi = 0.5, sta = 0.5, spi = 0.3, sp = 0.7, heal = 0.6, ap = 0.4, crit = 0.6,
		hit = 0.5, mp5 = 1, dps = 2, armor = 0.015 },
	DRUID = { int = 0.7, agi = 0.6, str = 0.6, sta = 0.5, spi = 0.4, sp = 0.6, heal = 0.6, ap = 0.4, crit = 0.6,
		mp5 = 1, dps = 0.5, armor = 0.01 },
}
F.WEIGHTS.DEATHKNIGHT, F.WEIGHTS.MONK, F.WEIGHTS.DEMONHUNTER = F.WEIGHTS.WARRIOR, F.WEIGHTS.ROGUE, F.WEIGHTS.ROGUE
F.WEIGHTS.EVOKER = F.WEIGHTS.MAGE
F.WEIGHTS.GENERIC = GENERIC

--- Your class's weights (F.WEIGHTS), or the generic ones.
function F.MyWeights()
	if not _G.UnitClass then return GENERIC end
	local ok, _, class = pcall(_G.UnitClass, "player")
	if not ok or type(class) ~= "string" or Secret(class) then return GENERIC end
	return F.WEIGHTS[class] or GENERIC
end

--- An item's worth to you: its stats (the game's table) weighed (nil when there are none to weigh).
function F.StatValue(stats, w)
	if type(stats) ~= "table" then return nil end
	w = w or GENERIC
	local v, any = 0, false
	for key, amount in pairs(stats) do
		local k = type(key) == "string" and type(amount) == "number" and StatKind(key)
		if k and w[k] then v, any = v + w[k] * amount, true end
	end
	return any and v or nil
end

--- What you wear in each equipment slot (1-18), read once per filter: item levels, and their weighed stats.
local function WornGear(w)
	local levels, values = {}, {}
	local link = _G.GetInventoryItemLink
	local detailed = C_Item and C_Item.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
	local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	for slot = 1, 18 do
		local ok, l = pcall(link or function() end, "player", slot)
		if ok and type(l) == "string" and not Secret(l) then
			local lvl = detailed and select(2, pcall(detailed, l))
			if type(lvl) ~= "number" then
				local id = tonumber(l:match("item:(%d+)"))
				local info = id and ItemInfo(id)
				lvl = info and info.ilvl
			end
			if type(lvl) == "number" then levels[slot] = lvl end
			-- (by its own link: a worn piece's random suffix and enchant are its own)
			if get then
				local okS, st = pcall(get, l)
				-- (nil when it has none to weigh: then item levels are compared, not any stat against nothing)
				if okS and type(st) == "table" then values[slot] = F.StatValue(st, w) end
			end
		end
	end
	-- a two-hander fills the off hand too: a one-hander or shield there is weighed against it, not an empty slot
	if levels[16] and not levels[17] and C_Item and C_Item.GetItemInfoInstant and _G.GetInventoryItemID then
		local okId, mh = pcall(_G.GetInventoryItemID, "player", 16)
		local ok, _, _, _, loc = false
		if okId and mh then ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, mh) end
		if ok and loc == "INVTYPE_2HWEAPON" then levels[17], values[17], values.twoHand = levels[16], values[16], true end
	end
	return levels, values
end

--- A filter: the item is an upgrade for you now (see above). Items the game hasn't loaded yet wait (F.loading: searched
--- again).
function F.GearFit()
	local me = _G.UnitLevel and _G.UnitLevel("player") or nil -- (unknown: no level checks)
	if type(me) ~= "number" or me <= 0 then me = nil end
	local weights = F.MyWeights()
	local worn, wornValue = WornGear(weights)
	local asked = 0 -- (items asked of the server by this filter: a few at a time, F.GEAR_ASK per search)
	local instant = C_Item and C_Item.GetItemInfoInstant
	local cached = C_Item and C_Item.IsItemDataCachedByID
	return function(e)
		if e.slotId then return false end -- (worn already)
		local id = ItemOf(e)
		if not id then return false end
		-- not equipment, by the client's own data (no server ask): most rows go here
		if instant then
			local ok, _, _, _, loc = pcall(instant, id)
			if ok and type(loc) == "string" and not SLOTS[loc] then return false end
		end
		-- an item the client hasn't got: GetItemInfo would ask the server for it. AtlasLoot's thousands of items are
		-- never asked from here (its own name pump does that, a batch at a time); others a few per search
		if cached and not cached(id) then
			if e.kind == "loot" or asked >= F.GEAR_ASK then return false end
			asked = asked + 1
			if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			F.loading = true
			return false
		end
		local info = ItemInfo(id)
		if not info then
			F.loading = true
			return false
		end
		local loc = info.equipLoc or ""
		local slots = SLOTS[loc]
		if not slots then return false end
		local need = type(info.minLevel) == "number" and info.minLevel or 0
		if me and need > me then return false end
		-- (a kind you can't use: plate on a mage, another class's item)
		if C_PlayerInfo and C_PlayerInfo.CanUseItem then
			local ok, yes = pcall(C_PlayerInfo.CanUseItem, id)
			if ok and yes == false then return false end
		end
		local ilvl = type(info.ilvl) == "number" and info.ilvl or 0
		-- what it would replace: the weaker of its slots (by worth when known, else item level)
		local wLvl, wVal, empty
		if loc == "INVTYPE_2HWEAPON" then
			-- both hands go: against main hand and off hand together
			if not worn[16] then empty = true
			else
				wLvl = worn[16]
				local mv, ov = wornValue[16], 0
				if not wornValue.twoHand and worn[17] then ov = wornValue[17] end -- (nil: the off hand's worth unknown)
				wVal = (mv and ov) and (mv + ov) or nil
			end
		else
			for _, slot in ipairs(slots) do
				local l = worn[slot]
				if not l then empty = true break end -- (an empty slot: anything fitting is an upgrade)
				local v = wornValue[slot]
				local weaker
				if wLvl == nil then weaker = true
				elseif v ~= nil and wVal ~= nil then weaker = v < wVal
				else weaker = l < wLvl end
				if weaker then wLvl, wVal = l, v end
			end
		end
		if empty then return not me or ilvl >= me - F.GEAR_EMPTY end
		local mine = F.StatValue(Stats(e), weights)
		if mine and wVal and (mine > 0 or wVal > 0) then return mine > wVal end
		return ilvl > wLvl
	end
end

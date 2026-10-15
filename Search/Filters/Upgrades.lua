local ns = select(2, ...)

-- is:upgrade: gear that suits you now, weighed against what you wear (Core.lua's KEYS.is asks F.GearFit()).

local F = ns.Filters
local L = ns.L
local P = F._
local ItemInfo, ItemOf, Stats, StatKey, SLOTS = P.ItemInfo, F.ItemOf, P.Stats, P.StatKey, F.SLOTS
local MAIN_ONLY = { 16 } -- (a one-hander for a class that can't dual-wield)
local Secret = ns.Secret

-- is:upgrade (Simple mode: "upgrades", "helm upgrades"): gear you can equip now (its required level is yours or lower,
-- and the game says you can use it: class, armour and weapon kind), not worn already, and better than what you wear
-- there (0.43.8). Better = more of what your class wants: the item's stats weighed for your class (F.WEIGHTS, a rough
-- Pawn-like scale: a warrior's strength, a mage's intellect and spell power, a weapon's damage per second), against
-- the piece you wear there (the weaker of two rings or trinkets; a two-hander against your main and off hand
-- together). When either side has no stats to weigh (most trinkets, plain white gear) or they aren't loaded yet:
-- a higher item level. Nothing worn there: within GEAR_EMPTY of your level. (0.41.28-0.43.7 only asked for an item
-- level within 5 of your weakest piece: lots of "upgrades" that weren't.)
F.GEAR_EMPTY, F.GEAR_ASK = 10, 40
-- Only gear for about your level (0.51.8, the player: "upgrades" listed far too much, a level 30's old greens beaten by
-- anything from Ragefire Chasm on): its required level at most GEAR_NEAR below yours (gear needing none: its item
-- level). Shirts and tabards never: they have nothing to weigh, and an empty shirt slot took any.
F.GEAR_NEAR = 6
local NEVER = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

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

--- An item's stats (the game's table) by kind: { str = 7, sta = 4 } (kinds Terminal weighs; others left out).
function F.StatKinds(stats)
	if type(stats) ~= "table" then return nil end
	local out = {}
	for key, amount in pairs(stats) do
		local k = type(key) == "string" and type(amount) == "number" and StatKind(key)
		if k then out[k] = (out[k] or 0) + amount end
	end
	return out
end
--- Stats by kind weighed (nil when there are none to weigh).
function F.KindsValue(kinds, w)
	if type(kinds) ~= "table" then return nil end
	w = w or GENERIC
	local v, any = 0, false
	for k, amount in pairs(kinds) do
		if w[k] then v, any = v + w[k] * amount, true end
	end
	return any and v or nil
end
--- An item's worth to you: its stats (the game's table) weighed (nil when there are none to weigh).
function F.StatValue(stats, w) return F.KindsValue(F.StatKinds(stats), w) end

--- What you wear in each equipment slot (1-18), read once per filter: item levels, their weighed stats, and their
--- stats by kind (kinds[slot]; for "why" an upgrade is one, F.UpgradeWhy).
local function WornGear(w)
	local levels, values, kinds, locs, names = {}, {}, {}, {}, {}
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
			names[slot] = l:match("|h%[(.-)%]|h") -- (its name, for "why": over which of two it is)
			-- (what kind it is: a shield or an off-hand item in the off hand isn't a weapon a one-hander replaces)
			if (slot == 16 or slot == 17) and C_Item and C_Item.GetItemInfoInstant then
				local okI, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, l)
				if okI and type(loc) == "string" then locs[slot] = loc end
			end
			-- (by its own link: a worn piece's random suffix and enchant are its own)
			if get then
				local okS, st = pcall(get, l)
				-- (nil when it has none to weigh: then item levels are compared, not any stat against nothing)
				if okS and type(st) == "table" then
					kinds[slot] = F.StatKinds(st)
					values[slot] = F.KindsValue(kinds[slot], w)
				end
			end
		end
	end
	-- a two-hander fills the off hand too: a one-hander or shield there is weighed against it, not an empty slot
	if levels[16] and not levels[17] and C_Item and C_Item.GetItemInfoInstant and _G.GetInventoryItemID then
		local okId, mh = pcall(_G.GetInventoryItemID, "player", 16)
		local ok, _, _, _, loc = false
		if okId and mh then ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, mh) end
		if ok and loc == "INVTYPE_2HWEAPON" then
			levels[17], values[17], kinds[17], names[17], values.twoHand = levels[16], values[16], kinds[16], names[16], true
		end
	end
	return levels, values, kinds, locs, names
end

-- What is:upgrade has read of each item, kept for the session (0.51.7): { slot type, required level, item level, usable
-- by you, -, -, how it binds (GetItemInfo's bindType); kinds = its stats by kind (nil: not read yet) }. The
-- client lets go of items it loaded a while ago (AtlasLoot's name pump asks for thousands): a row it no longer had was
-- left out ("not loaded": a loot row) or asked for again, so the same search said 18 upgrades in Dungeon loot and
-- then listed 8, and changed again with each step in and out. Read again whenever the client has the item (what you
-- can use changes as you learn to wear mail); used as it was when it doesn't.
-- Kept between sessions too (0.51.13, the player's ask; ns.ItemStore "facts", by item id): after a /reload, items
-- the game hasn't sent again are judged as before, and items it has aren't read again. The record, one string:
-- "slot type;required level;item level;binding;str=7,sta=4;Grom+,Jaina-" (the last: usable by each of your characters
-- it was asked for). A change to this record or to the stat kinds (STAT_KINDS) needs ItemStore's S.VERSION raised. A row's own copy with a random suffix ("of the Monkey") is kept for the session only.
local fit = {}
F.ClearFit = function() fit = {}; if ns.ItemStore then ns.ItemStore.Clear("facts") end end
F.ForgetSessionFit = function() fit = {} end -- (tests: a new session, what was kept between sessions still there)
F._fit = function() return fit end -- (tests)
--- Is something known of this item, kept this session or from another (is:upgrade can judge it without the game)?
function F.Known(id) return fit[id] ~= nil or (ns.ItemStore ~= nil and ns.ItemStore.Get("facts", id) ~= nil) end

-- How much each upgrade the last search found beats what you wear (0.51.14, the player's ask: the best first, and the
-- tooltip saying why): row -> { gain, kinds (its stats), worn (what it replaces: its stats), loc, ilvl, wLvl, empty }.
-- gain: weighed stats over the replaced piece's, else item levels over its; nothing worn there: its own worth.
local gains = setmetatable({}, { __mode = "k" })
function F.GainOf(e) return gains[e] end
--- A view of a row made after the search (a quest's, Rewards.lua) says why as its row does.
function F.SetGain(e, g) gains[e] = g end

--- Who "usable by you" is kept for: this character (by name). Not the class (review, 0.51.25): one hunter wears mail
--- from 40, another not yet; weapon skills are each one's own. (Names have no ; , + or -.)
local function MyName()
	local ok, name = pcall(_G.UnitName or function() end, "player")
	if not (ok and type(name) == "string" and not Secret(name) and name ~= "" and not name:find("[;,%+%-@]")) then return nil end
	-- (and the realm, its letters only: two of the same name on two realms aren't one)
	local okR, realm = pcall(_G.GetRealmName or function() end)
	realm = okR and type(realm) == "string" and not Secret(realm) and realm:gsub("[%s%p]", "") or ""
	return realm ~= "" and (name .. "@" .. realm) or name
end
local function Escaped(s) return (s:gsub("%p", "%%%0")) end
local function Encode(f, class, old)
	local kinds = {}
	for k, v in pairs(f.kinds or {}) do kinds[#kinds + 1] = k .. "=" .. (math.floor(v * 100 + 0.5) / 100) end
	table.sort(kinds)
	-- (what each other class could use, as it was kept: only this class's is told again)
	local can = type(old) == "string" and old:match(";([^;]*)$") or ""
	if class and f[4] ~= nil then
		can = ("," .. can):gsub("," .. Escaped(class) .. "[%+%-]", ""):gsub("^,", "") -- (its own entry told again)
		can = (can ~= "" and (can .. ",") or "") .. class .. (f[4] and "+" or "-")
	end
	return table.concat({ f[1], tostring(f[2] or ""), tostring(f[3] or ""), tostring(f[7] or ""), table.concat(kinds, ","), can }, ";")
end
local function Decode(rec, class)
	if type(rec) ~= "string" then return nil end
	local loc, need, ilvl, bind, stats, can = rec:match("^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$")
	if not loc or not SLOTS[loc] then return nil end
	local kinds = {}
	for k, v in stats:gmatch("([%a%d]+)=([%-%d%.]+)") do kinds[k] = tonumber(v) end -- (mp5 too: review, 0.51.25)
	local mine = class and ("," .. can):match("," .. Escaped(class) .. "([%+%-])")
	return { loc, tonumber(need), tonumber(ilvl), mine == "+" or (mine ~= "-" and nil), nil, nil, tonumber(bind),
		kinds = kinds, kept = rec }
end
--- What's kept of an item between sessions (nil: nothing; or a row's own suffixed copy).
local function Remembered(key, class)
	if type(key) ~= "number" or not ns.ItemStore then return nil end
	return Decode(ns.ItemStore.Get("facts", key), class)
end
--- Keep what's known of it (its stats read: the record is whole).
local function Remember(key, f, class)
	if type(key) ~= "number" or not ns.ItemStore or not f.kinds then return end
	local rec = Encode(f, class, f.kept)
	if rec ~= f.kept then
		f.kept = rec
		ns.ItemStore.Put("facts", key, rec)
	end
end

--- A filter: the item is an upgrade for you now (see above). Items the game hasn't loaded yet aren't, for now.
function F.GearFit()
	local me = _G.UnitLevel and _G.UnitLevel("player") or nil -- (unknown: no level checks)
	if type(me) ~= "number" or me <= 0 then me = nil end
	local weights = F.MyWeights()
	local worn, wornValue, wornKinds, wornLocs, wornNames = WornGear(weights)
	-- a one-hander replaces a weapon: the main hand, and the off hand only when it holds one (dual wielding); a shield
	-- or an off-hand item stays (0.51.17, the player: a mace was weighed against main hand and shield together)
	local offWeapon = not (wornLocs[17] == "INVTYPE_SHIELD" or wornLocs[17] == "INVTYPE_HOLDABLE")
	F.fitMade = true -- (this search weighs upgrades: their tooltips say why, F.UpgradeWhy)
	local asked = 0 -- (items asked of the server by this filter: a few at a time, F.GEAR_ASK per search)
	local instant = C_Item and C_Item.GetItemInfoInstant
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local LootPlace = ns.Integrations and ns.Integrations.LootPlace
	local class = MyName() -- (this character: who "usable" is kept for)
	local Fit
	local probes = {} -- item id -> a row of its own, for a quest's rewards
	-- a quest (Questie's, your log's): one of its rewards is an upgrade (0.51.15, the player's ask; Rewards.lua knows
	-- what each quest rewards): the best of them, by name
	local function QuestFit(e)
		gains[e] = nil -- (a gain from an earlier search isn't this one's: review, 0.51.25)
		local QR = ns.QuestRewards
		local qid = QR and QR.QuestIdOf and QR.QuestIdOf(e)
		local items = qid and QR.RewardsOf and QR.RewardsOf(qid)
		if not items then return false end
		local best, bestName
		for _, it in ipairs(items) do
			local probe = probes[it.id]
			if not probe then probe = { kind = "reward", itemID = it.id }; probes[it.id] = probe end
			if Fit(probe) then
				local g = gains[probe]
				if g and (not best or g.gain > best.gain) then best, bestName = g, it.name end
			end
		end
		if not best then return false end
		local g = {}
		for k, v in pairs(best) do g[k] = v end
		g.item = bestName
		gains[e] = g
		return true
	end
	Fit = function(e)
		if e.kind == "questie" or e.kind == "quests" then return QuestFit(e) end
		gains[e] = nil -- (a gain from an earlier search isn't this one's: review, 0.51.25)
		if e.slotId then return false end -- (worn already)
		local id = ItemOf(e)
		if not id then return false end
		-- not equipment, by the client's own data (no server ask): most rows go here
		if instant then
			local ok, _, _, _, loc = pcall(instant, id)
			if ok and type(loc) == "string" and not SLOTS[loc] then return false end
		end
		-- only what you can get (0.51.9, the player: Naxxramas gear, engineers' trinkets and cosmetic helms for a level 30
		-- warrior): AtlasLoot's dungeons you can enter (not raids, professions, PvP, factions, collections or events)
		if e.kind == "loot" then
			local place = LootPlace and LootPlace(e)
			if place and (place.kind ~= "dungeon" or (me and place.enter and place.enter > me)) then return false end
		end
		local key = StatKey(e)
		local f = fit[key]
		if not f then
			f = Remembered(key, class) -- (as kept from another session)
			if f then fit[key] = f end
		end
		local live = not (cached and not cached(id)) -- (the client has it: read now)
		if not live then
			-- an item the client hasn't got (or no longer has): as read when it had it
			if not f then
				-- never read: not one for now. AtlasLoot's thousands of items are never asked for from here (its own name
				-- pump does that, a batch at a time); others a few per search, in the background: the search isn't run
				-- again for them (0.51.9, the player: Simple mode's "upgrades", which looks at your alts' bags too, was
				-- searched again every second or so while they came in, where "@loot is:upgrade" stood still; they're
				-- in the next search)
				if e.kind == "loot" or asked >= F.GEAR_ASK then return false end
				asked = asked + 1
				if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
				return false
			end
		elseif not f then
			local info = ItemInfo(id)
			if not info then
				F.loading = true
				return false
			end
			local loc = info.equipLoc or ""
			if not SLOTS[loc] then return false end
			f = { loc, info.minLevel, info.ilvl, nil, nil, nil, info.bindType }
			fit[key] = f
		end
		local loc = f[1]
		if NEVER[loc] then return false end
		-- one only other characters hold (your alts' bags, Syndicator): only if it can be sent you, not bound to them
		-- (bound when picked up, a quest item)
		if (f[7] == 1 or f[7] == 4) and type(e.holders) == "table" then
			local yours = false
			for _, h in pairs(e.holders) do if type(h) == "table" and h.mine then yours = true break end end
			if not yours then return false end
		end
		local slots = SLOTS[loc]
		-- a one-hander goes in the main hand only for a class that can't dual-wield (0.50.7, review: an empty off hand made
		-- every usable one-hander an upgrade for a mage, a priest)
		-- (a two-hander worn: against it once, not as two weapons; review, 0.51.25)
		if loc == "INVTYPE_WEAPON" and (ns.Safe(_G.CanDualWield) == false or not offWeapon or wornValue.twoHand) then
			slots = MAIN_ONLY
		end
		local need = type(f[2]) == "number" and f[2] or 0
		if me and need > me then return false end
		local ilvl = type(f[3]) == "number" and f[3] or 0
		if me and (need > 1 and need or ilvl) < me - F.GEAR_NEAR then return false end -- (well below your level)
		-- (a kind you can't use: plate on a mage, another class's item; asked whenever the client has the item, as you
		-- may have learned to wear mail since; not asked yet: not one)
		if live then
			local can = true
			if C_PlayerInfo and C_PlayerInfo.CanUseItem then
				local ok, yes = pcall(C_PlayerInfo.CanUseItem, id)
				if ok and yes == false then can = false end
			end
			if f[4] ~= can then
				f[4] = can
				Remember(key, f, class)
			end
		end
		if not f[4] then return false end
		-- what it would replace: the weaker of its slots (by worth when known, else item level)
		local wLvl, wVal, wKinds, empty
		if loc == "INVTYPE_2HWEAPON" then
			-- both hands go: against main hand and off hand together
			if not worn[16] then empty = true
			else
				wLvl = worn[16]
				local mv, ov = wornValue[16], 0
				if not wornValue.twoHand and worn[17] then ov = wornValue[17] end -- (nil: the off hand's worth unknown)
				wVal = (mv and ov) and (mv + ov) or nil
				wKinds = {}
				for k, v in pairs(wornKinds[16] or {}) do wKinds[k] = v end
				if not wornValue.twoHand then
					for k, v in pairs(wornKinds[17] or {}) do wKinds[k] = (wKinds[k] or 0) + v end
				end
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
				if weaker then wLvl, wVal, wKinds = l, v, wornKinds[slot] end
			end
		end
		if empty then
			local yes = not me or ilvl >= me - F.GEAR_EMPTY
			if yes then
				if not f.kinds and live then
					local st = Stats(e)
					if st then f.kinds = F.StatKinds(st); Remember(key, f, class) end
				end
				-- (its stats' worth; none to weigh: after those, by item level, not item levels against stat points: an empty
				-- trinket slot's every trinket went above real upgrades; review, 0.51.25)
				gains[e] = { gain = F.KindsValue(f.kinds, weights) or ilvl / 100, kinds = f.kinds, loc = loc, ilvl = ilvl, empty = true }
			end
			return yes
		end
		-- its stats: read once (the client has it: else they wait, and item levels decide meanwhile), then kept
		if not f.kinds and live then
			local st = Stats(e)
			if st then
				f.kinds = F.StatKinds(st)
				Remember(key, f, class)
			end
		end
		local mine = F.KindsValue(f.kinds, weights)
		local up, g
		if mine and wVal and (mine > 0 or wVal > 0) then
			if mine > wVal then
				up, g = true, { gain = mine - wVal, kinds = f.kinds, worn = wKinds, loc = loc, ilvl = ilvl, wLvl = wLvl }
			end
		elseif ilvl > wLvl then
			up, g = true, { gain = ilvl - wLvl, loc = loc, ilvl = ilvl, wLvl = wLvl, byLevel = true }
		end
		if not up then return false end
		-- two slots it could go in (dual wielding, rings, trinkets): against each piece it beats, by name; one it doesn't
		-- beat isn't said (0.51.19, the player's ask); sorted by the bigger gain
		if #slots > 1 and loc ~= "INVTYPE_2HWEAPON" then
			local vs = {}
			for _, slot in ipairs(slots) do
				local v, l = wornValue[slot], worn[slot]
				local one
				if mine and v and (mine > 0 or v > 0) then
					if mine > v then one = { gain = mine - v, kinds = f.kinds, worn = wornKinds[slot], ilvl = ilvl, wLvl = l } end
				elseif l and ilvl > l then
					one = { gain = ilvl - l, ilvl = ilvl, wLvl = l, byLevel = true }
				end
				if one then
					one.loc, one.name = loc, wornNames[slot]
					vs[#vs + 1] = one
				end
			end
			if #vs > 0 then
				table.sort(vs, function(a, b) return a.gain > b.gain end)
				g.vs, g.gain = vs, vs[1].gain
			end
		end
		gains[e] = g
		return true
	end
	return Fit
end

-- the stats' names in "why" (the game's own, in its language)
local KIND_NAME = { str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
	int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT", ap = "ITEM_MOD_ATTACK_POWER_SHORT",
	rap = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", sp = "ITEM_MOD_SPELL_POWER_SHORT", heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
	crit = "ITEM_MOD_CRIT_RATING_SHORT", hit = "ITEM_MOD_HIT_RATING_SHORT", haste = "ITEM_MOD_HASTE_RATING_SHORT",
	mp5 = "ITEM_MOD_MANA_REGENERATION_SHORT", dps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", armor = "ARMOR",
	def = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", dodge = "ITEM_MOD_DODGE_RATING_SHORT", parry = "ITEM_MOD_PARRY_RATING_SHORT",
	block = "ITEM_MOD_BLOCK_RATING_SHORT" }
local KIND_FALLBACK = { str = "Str", agi = "Agi", sta = "Sta", int = "Int", spi = "Spi", ap = "AP", rap = "RAP", sp = "SP",
	heal = "Healing", crit = "Crit", hit = "Hit", haste = "Haste", mp5 = "MP5", dps = "DPS", armor = "Armor", def = "Defense",
	dodge = "Dodge", parry = "Parry", block = "Block" }
local function KindName(k)
	local g = KIND_NAME[k] and _G[KIND_NAME[k]]
	if type(g) == "string" and g ~= "" and not Secret(g) then return g end
	return KIND_FALLBACK[k] or k
end
local function Num(v)
	if v == math.floor(v) then return tostring(v) end
	return ("%.1f"):format(v)
end

--- Why the row is an upgrade, lines for its tooltip: { text, good } each, the first what it's weighed against ("Over
--- what you wear (slot: head):"; a quest: its reward named first), then a line per stat: gains first (good = true, drawn
--- green), the biggest first, then losses (good = false, red). nil when the last search didn't weigh upgrades, or found
--- it no upgrade. (0.51.17, the player: one green line of every stat read badly; gains and losses apart.)
function F.UpgradeWhy(e)
	local g = F.fitMade and gains[e]
	if not g then return nil end
	local lines = F.WhyLines(g)
	if g.item then table.insert(lines, 1, { text = g.item }) end -- (a quest's reward)
	return lines
end
--- The lines for a gain (UpgradeWhy).
function F.WhyLines(g)
	if g.vs then -- (against each of two it could replace, each it beats: its own heading, then its lines)
		local lines = {}
		for _, one in ipairs(g.vs) do
			local part = F.WhyLines(one)
			if one.name then
				local head = { text = L["Over %s:"]:format(one.name) }
				if part[1] and part[1].good == nil then part[1] = head else table.insert(part, 1, head) end
			end
			for _, l in ipairs(part) do lines[#lines + 1] = l end
		end
		return lines
	end
	local slotName = _G[g.loc]
	slotName = type(slotName) == "string" and not Secret(slotName) and slotName:lower() or g.loc
	if g.empty then return { { text = L["nothing worn there (slot: %s)"]:format(slotName), good = true } } end
	local byLevel = { { text = L["item level %d over %d (slot: %s)"]:format(g.ilvl or 0, g.wLvl or 0, slotName), good = true } }
	if g.byLevel then return byLevel end
	local w = F.MyWeights()
	local ups, downs, seen = {}, {}, {}
	local function add(k)
		if seen[k] or not w[k] then return end
		seen[k] = true
		local d = ((g.kinds or {})[k] or 0) - ((g.worn or {})[k] or 0)
		if math.abs(d) < 0.05 then return end
		local t = d > 0 and ups or downs
		t[#t + 1] = { k = k, d = d, weight = math.abs(d) * w[k] }
	end
	for k in pairs(g.kinds or {}) do add(k) end
	for k in pairs(g.worn or {}) do add(k) end
	if #ups + #downs == 0 then return byLevel end
	local function Biggest(a, b) if a.weight ~= b.weight then return a.weight > b.weight end return a.k < b.k end
	table.sort(ups, Biggest)
	table.sort(downs, Biggest)
	local lines = { { text = L["Over what you wear (slot: %s):"]:format(slotName) } }
	for _, list in ipairs({ ups, downs }) do
		for _, d in ipairs(list) do
			lines[#lines + 1] = { text = (d.d > 0 and "+" or "-") .. Num(math.abs(d.d)) .. " " .. KindName(d.k), good = d.d > 0 }
		end
	end
	return lines
end

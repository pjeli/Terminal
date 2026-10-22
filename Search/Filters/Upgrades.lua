local ns = select(2, ...)

-- is:upgrade: gear that suits you now, weighed against what you wear (Core.lua's KEYS.is asks F.GearFit()).

local F = ns.Filters
local P = F._
local ItemInfo, ItemOf, Stats, StatKey, SLOTS, ItemKey = P.ItemInfo, F.ItemOf, P.Stats, P.StatKey, F.SLOTS, P.ItemKey
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

-- what a stat key is (ITEM_MOD_STRENGTH_SHORT -> "str"): the first part of the key that matches, in this order (not
-- HEALTH_REGEN: hp5 isn't mp5; review, 0.53.6). Spells' hit and crit and a druid's feral attack power are their own
-- (0.56.14: a warrior's weights counted a caster's +1% spell hit as hit, a feral staff's attack power in forms as his)
local STAT_KINDS = {
	{ "FERAL_ATTACK_POWER", "feralap" }, { "RANGED_ATTACK_POWER", "rap" }, { "ATTACK_POWER", "ap" }, { "STRENGTH", "str" },
	{ "AGILITY", "agi" }, { "STAMINA", "sta" }, { "INTELLECT", "int" }, { "SPIRIT", "spi" }, { "HEALING", "heal" },
	{ "SPELL_DAMAGE", "sp" }, { "SPELL_POWER", "sp" }, { "HIT_SPELL", "spellhit" }, { "CRIT_SPELL", "spellcrit" },
	{ "SPELL_HIT", "spellhit" }, { "SPELL_CRIT", "spellcrit" },
	{ "CRIT", "crit" }, { "HIT", "hit" }, { "HASTE", "haste" }, { "MANA_REGEN", "mp5" }, { "POWER_REGEN0", "mp5" },
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
	crit = 0.5, hit = 0.5, spellhit = 0.4, spellcrit = 0.4, haste = 0.4, mp5 = 0.5, dps = 1.5, armor = 0.01, def = 0.3,
	dodge = 0.3, parry = 0.3, block = 0.2 }
F.WEIGHTS = {
	WARRIOR = { str = 1, agi = 0.7, sta = 0.6, ap = 0.5, crit = 0.8, hit = 0.8, haste = 0.5, dps = 3, armor = 0.02,
		def = 0.5, dodge = 0.5, parry = 0.5, block = 0.3 },
	PALADIN = { str = 1, int = 0.6, sta = 0.6, spi = 0.2, agi = 0.4, ap = 0.4, sp = 0.6, heal = 0.5, crit = 0.7,
		hit = 0.6, spellcrit = 0.4, mp5 = 1, dps = 2.5, armor = 0.02, def = 0.4, block = 0.2 },
	HUNTER = { agi = 1, ap = 0.4, rap = 0.5, sta = 0.5, int = 0.3, spi = 0.1, crit = 0.8, hit = 0.8, haste = 0.5,
		dps = 2, armor = 0.01 },
	ROGUE = { agi = 1, str = 0.5, ap = 0.5, sta = 0.5, crit = 0.8, hit = 0.8, haste = 0.6, dps = 3, armor = 0.01 },
	PRIEST = { int = 1, spi = 0.8, sta = 0.5, sp = 0.8, heal = 0.8, crit = 0.5, spellcrit = 0.5, spellhit = 0.3, haste = 0.4,
		mp5 = 1.2, dps = 0.3, armor = 0.005 },
	MAGE = { int = 1, spi = 0.5, sta = 0.5, sp = 1, crit = 0.7, hit = 0.8, spellcrit = 0.7, spellhit = 0.8, haste = 0.5,
		mp5 = 0.8, dps = 0.3, armor = 0.005 },
	WARLOCK = { int = 0.8, spi = 0.4, sta = 0.7, sp = 1, crit = 0.5, hit = 0.8, spellcrit = 0.5, spellhit = 0.8, haste = 0.5,
		mp5 = 0.6, dps = 0.3, armor = 0.005 },
	SHAMAN = { int = 0.8, str = 0.6, agi = 0.5, sta = 0.5, spi = 0.3, sp = 0.7, heal = 0.6, ap = 0.4, crit = 0.6,
		hit = 0.5, spellcrit = 0.5, spellhit = 0.4, mp5 = 1, dps = 2, armor = 0.015 },
	DRUID = { int = 0.7, agi = 0.6, str = 0.6, sta = 0.5, spi = 0.4, sp = 0.6, heal = 0.6, ap = 0.4, feralap = 0.4,
		crit = 0.6, spellcrit = 0.5, spellhit = 0.3, mp5 = 1, dps = 0.5, armor = 0.01 },
}
F.WEIGHTS.DEATHKNIGHT, F.WEIGHTS.MONK, F.WEIGHTS.DEMONHUNTER = F.WEIGHTS.WARRIOR, F.WEIGHTS.ROGUE, F.WEIGHTS.ROGUE
F.WEIGHTS.EVOKER = F.WEIGHTS.MAGE
F.WEIGHTS.GENERIC = GENERIC

-- Roles (0.54.1, a player's ask: "How does the addon score upgrades? Can I control it? On a druid I care about both feral
-- and resto gear"): each class's ways to play, each with its own weights. `.weights` shows them and picks yours (one or
-- more, kept per character); an item is an upgrade when it's a clear one for any role picked, said in its tooltip. None
-- picked: the class's all-round weights above.
local L = ns.L
local TANK = { sta = 1, def = 1, dodge = 0.8, parry = 0.7, block = 0.5, armor = 0.04, str = 0.6, agi = 0.5, hit = 0.3, dps = 1.5 }
local HEALER = { int = 0.8, spi = 0.7, heal = 1, sp = 0.5, mp5 = 1.2, sta = 0.3, crit = 0.4, spellcrit = 0.4, haste = 0.3,
	armor = 0.005 }
local CASTER = { int = 0.8, sp = 1, crit = 0.7, hit = 0.9, spellcrit = 0.7, spellhit = 0.9, haste = 0.5, sta = 0.4, spi = 0.3,
	mp5 = 0.5, dps = 0.2, armor = 0.005 }
local STR_MELEE = { str = 1, agi = 0.6, ap = 0.5, crit = 0.8, hit = 0.8, haste = 0.5, sta = 0.4, dps = 3, armor = 0.01 }
F.ROLES = {
	WARRIOR = { { "dps", STR_MELEE }, { "tank", TANK } },
	PALADIN = { { "healer", HEALER }, { "tank", TANK },
		{ "melee", { str = 1, agi = 0.5, int = 0.3, ap = 0.5, crit = 0.8, hit = 0.8, sta = 0.4, dps = 3, armor = 0.01 } } },
	HUNTER = { { "ranged", F.WEIGHTS.HUNTER } },
	ROGUE = { { "melee", F.WEIGHTS.ROGUE } },
	PRIEST = { { "healer", HEALER }, { "caster", CASTER } },
	MAGE = { { "caster", F.WEIGHTS.MAGE } },
	WARLOCK = { { "caster", F.WEIGHTS.WARLOCK } },
	SHAMAN = { { "healer", HEALER }, { "caster", CASTER },
		{ "melee", { str = 1, agi = 0.8, ap = 0.5, int = 0.2, crit = 0.8, hit = 0.8, sta = 0.4, dps = 3, armor = 0.01 } } },
	DRUID = { { "healer", HEALER }, { "caster", CASTER },
		{ "feral", { agi = 1, str = 0.9, ap = 0.5, feralap = 0.5, sta = 0.6, crit = 0.8, hit = 0.8, armor = 0.03, def = 0.3,
			dodge = 0.4 } } },
}
F.ROLE_SAY = { dps = L["damage"], tank = L["tank"], healer = L["healer"], melee = L["melee"], ranged = L["ranged"],
	caster = L["caster"], feral = L["feral"], custom = L["your own weights"] }
-- (what each role's word may be typed as: ".weights resto feral")
F.ROLE_WORDS = { damage = "dps", dps = "dps", fury = "dps", arms = "dps", tank = "tank", prot = "tank", protection = "tank",
	bear = "tank", heal = "healer", healer = "healer", healing = "healer", holy = "healer", resto = "healer",
	restoration = "healer", disc = "healer", melee = "melee", ret = "melee", retribution = "melee", enh = "melee",
	enhancement = "melee", combat = "melee", ranged = "ranged", caster = "caster", spell = "caster", balance = "caster",
	boomkin = "caster", elemental = "caster", ele = "caster", shadow = "caster", feral = "feral", cat = "feral",
	custom = "custom", own = "custom", mine = "custom" }

local function MyClass()
	if not _G.UnitClass then return nil end
	local ok, _, class = pcall(_G.UnitClass, "player")
	if not ok or type(class) ~= "string" or Secret(class) then return nil end
	return class
end

----------------------------------------------------------------------
-- Your own weights (0.65.8, the player: "let's add custom weights; and support for the Pawn scale strings"): .weights
-- set str=2 agi=1 sta=0.5, or a Pawn scale string; a role of their own ("custom") beside your class's, picked when set,
-- kept per character. Weighed scaled so their most wanted stat is 1, as the class's are (a clear upgrade gains at least
-- one point of your main stat: F.UPGRADE_MIN_ABS); said as typed.
----------------------------------------------------------------------
-- the words a stat may be typed as (.weights set)
F.STAT_WORDS = { str = "str", strength = "str", agi = "agi", agility = "agi", sta = "sta", stamina = "sta", int = "int",
	intellect = "int", spi = "spi", spirit = "spi", ap = "ap", attackpower = "ap", rap = "rap", rangedap = "rap",
	rangedattackpower = "rap", feralap = "feralap", sp = "sp", spellpower = "sp", spelldamage = "sp", heal = "heal",
	healing = "heal", crit = "crit", hit = "hit", spellhit = "spellhit", spellcrit = "spellcrit", haste = "haste", mp5 = "mp5",
	dps = "dps", armor = "armor", def = "def", defense = "def", dodge = "dodge", parry = "parry", block = "block" }
F.STAT_LIST = "str agi sta int spi ap rap feralap sp heal crit hit spellhit spellcrit haste mp5 dps armor def dodge parry block"
-- Pawn's names for them (its scale strings: "( Pawn: v1: "Name": Strength=2, HitRating=1.5, Ap=0.8 )"); a rating and the
-- plain stat alike (Classic's "+1% hit" is its HitRating), its weapon DPS kinds as one
local PAWN = { strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi", ap = "ap", rap = "rap",
	feralap = "feralap", spelldamage = "sp", spellpower = "sp", healing = "heal", hit = "hit", hitrating = "hit", crit = "crit",
	critrating = "crit", spellhit = "spellhit", spellhitrating = "spellhit", spellcrit = "spellcrit",
	spellcritrating = "spellcrit", haste = "haste", hasterating = "haste", spellhasterating = "haste", mp5 = "mp5", dps = "dps",
	meleedps = "dps", rangeddps = "dps", armor = "armor", defense = "def", defenserating = "def", dodge = "dodge",
	dodgerating = "dodge", parry = "parry", parryrating = "parry", block = "block", blockrating = "block", blockvalue = "block" }
F.PAWN_STATS = PAWN

--- "str=2 agi=1.5, sta 0.5" -> { str = 2, agi = 1.5, sta = 0.5 }, and the words that aren't a stat and its number.
function F.ParseWeights(text)
	local w, bad, any = {}, {}, false
	local words = {}
	for t in tostring(text or ""):gsub(",", " "):gmatch("%S+") do words[#words + 1] = t end
	local i = 1
	while i <= #words do
		local t = words[i]
		local k, v = t:match("^(%a[%w_]*)[=:](%-?[%d%.]+)$")
		if not k and t:match("^%a[%w_]*$") and words[i + 1] and tonumber(words[i + 1]) then k, v = t, words[i + 1]; i = i + 1 end
		local kind = k and F.STAT_WORDS[ns.Lower(k)]
		local n = v and tonumber(v)
		if kind and n then w[kind] = n; any = true else bad[#bad + 1] = t end
		i = i + 1
	end
	return any and w or nil, bad
end

--- A Pawn scale string -> its weights, its name, and the stats Terminal doesn't weigh (sockets, expertise...); nil when
--- it isn't one ("( Pawn: v1: "Name": Strength=2, ... )").
function F.ParsePawn(text)
	local name, body = tostring(text or ""):match('%(%s*Pawn%s*:%s*v%d+%s*:%s*"([^"]*)"%s*:(.-)%)')
	if not body then return nil end
	local w, ignored, any = {}, {}, false
	for piece in body:gmatch("[^,]+") do
		local k, v = piece:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		local n = v and tonumber(v)
		if k and n then
			local kind = PAWN[ns.Lower(k)]
			if kind then
				if w[kind] == nil or n > w[kind] then w[kind] = n end -- (melee and ranged DPS, rating and value: the more)
				any = true
			elseif n ~= 0 then
				ignored[#ignored + 1] = k
			end
		end
	end
	if not any then return nil end
	return w, name ~= "" and name or nil, ignored
end

--- Your own weights for this character: { w = { str = 2, ... }, name = a Pawn scale's } or nil.
function F.CustomWeights()
	local db, key = ns.db, F._MyName and F._MyName()
	local c = db and key and type(db.upgradeCustom) == "table" and db.upgradeCustom[key]
	return type(c) == "table" and type(c.w) == "table" and next(c.w) ~= nil and c or nil
end
--- Keep (or forget: nil) your own weights for this character; forgotten, they're no longer one of the roles picked.
function F.SetCustomWeights(w, name)
	local db, key = ns.db, F._MyName and F._MyName()
	if not (db and key) then return end
	db.upgradeCustom = type(db.upgradeCustom) == "table" and db.upgradeCustom or {}
	db.upgradeCustom[key] = w and { w = w, name = name } or nil
	if not w and type(db.upgradeRoles) == "table" and type(db.upgradeRoles[key]) == "table" then
		local kept = {}
		for _, id in ipairs(db.upgradeRoles[key]) do if id ~= "custom" then kept[#kept + 1] = id end end
		db.upgradeRoles[key] = #kept > 0 and kept or nil
	end
end

-- (scaled, made once per weights kept: the worn gear's values are kept per weights table)
local scaled = setmetatable({}, { __mode = "k" })
--- Weights scaled so their most wanted stat (not weapon DPS or armor, which come in other amounts) is 1.
function F.Scaled(w)
	local s = scaled[w]
	if s then return s end
	local top = 0
	for k, v in pairs(w) do if k ~= "dps" and k ~= "armor" and v > top then top = v end end
	if top <= 0 then for _, v in pairs(w) do if v > top then top = v end end end
	s = {}
	for k, v in pairs(w) do s[k] = top > 0 and v / top or v end
	scaled[w] = s
	return s
end

--- Your class's roles, and yours ("custom") after them when you've set your own: { { id, weights } ... }.
local function RolesOf(class)
	local list = F.ROLES[class or ""] or {}
	local c = F.CustomWeights()
	if not c then return list end
	local out = {}
	for i, r in ipairs(list) do out[i] = r end
	out[#out + 1] = { "custom", F.Scaled(c.w) }
	return out
end
F.RolesOf = RolesOf

--- The roles you picked (their ids, in your class's order), or nil: none (the all-round weights).
function F.MyRoles()
	local db, key = ns.db, F._MyName and F._MyName()
	local saved = db and key and type(db.upgradeRoles) == "table" and db.upgradeRoles[key]
	if type(saved) ~= "table" then return nil end
	local out = {}
	for _, r in ipairs(RolesOf(MyClass())) do
		for _, id in ipairs(saved) do if id == r[1] then out[#out + 1] = id end end
	end
	return #out > 0 and out or nil
end
--- Pick roles for this character (a list of ids; nil or empty: the all-round weights again).
function F.SetRoles(ids)
	local db, key = ns.db, F._MyName and F._MyName()
	if not (db and key) then return end
	db.upgradeRoles = type(db.upgradeRoles) == "table" and db.upgradeRoles or {}
	db.upgradeRoles[key] = (ids and #ids > 0) and ids or nil
end

--- The weights to judge by: { { weights, role } ... } (role nil: the all-round ones).
function F.MyWeightSets()
	local class = MyClass()
	local roles = F.MyRoles()
	if not roles then return { { class and F.WEIGHTS[class] or GENERIC } } end
	local out = {}
	for _, r in ipairs(RolesOf(class)) do
		for _, id in ipairs(roles) do if id == r[1] then out[#out + 1] = { r[2], id } end end
	end
	return #out > 0 and out or { { F.WEIGHTS[class] or GENERIC } }
end

--- Your class's weights (the first role you picked, else the all-round ones; F.WEIGHTS), or the generic ones.
function F.MyWeights()
	return F.MyWeightSets()[1][1]
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
--- What an item's stats by kind are worth to you: weighed; 0 when it has stats but none of them are ones you want; nil
--- when it has none to weigh (then item levels decide). 0.56.14, the player: a warrior was offered Snake Hoop
--- (Intellect, Spell Power) over rings of Strength and Agility: stats none of which were wanted were taken as unknown,
--- and its higher item level made it an upgrade (an empty slot took any such item too).
-- (what every piece has, not a stat a class picks it for: a plain weapon's damage or a white helm's armour, unweighed,
-- leave item levels to decide; release review: a healer's weights have no dps, and a wand was never an upgrade)
local PLAIN = { dps = true, armor = true }
function F.Worth(kinds, w)
	local v = F.KindsValue(kinds, w)
	if v == nil and type(kinds) == "table" then
		for k in pairs(kinds) do if not PLAIN[k] then return 0 end end
	end
	return v
end
-- A clear upgrade (0.52.7, the player: "pretty clear upgrades over what I'm wearing now; only slight trade-offs"): what it
-- gives up, weighed, at most F.UPGRADE_LOSS of what it gains (+3 Strength for -2 Agility is one; +1 Strength +2 Stamina
-- for -2 Agility isn't), and what it adds at least F.UPGRADE_MIN of what you wear there is worth (at least
-- F.UPGRADE_MIN_ABS: one point of your main stat). Only item levels known: at least F.LEVEL_CLEAR above.
F.UPGRADE_LOSS, F.UPGRADE_MIN, F.UPGRADE_MIN_ABS, F.LEVEL_CLEAR = 0.5, 0.05, 1, 2
--- What the item's stats add over the worn piece's, weighed (its gain), when it's a clear upgrade; else nil.
function F.ClearGain(mine, worn, w)
	if type(mine) ~= "table" then return nil end
	worn = type(worn) == "table" and worn or {}
	w = w or GENERIC
	local up, down = 0, 0
	local function Add(k)
		local wk = w[k]
		if not wk then return end
		local d = (mine[k] or 0) - (worn[k] or 0)
		if d > 0 then up = up + wk * d elseif d < 0 then down = down - wk * d end
	end
	for k in pairs(mine) do Add(k) end
	for k in pairs(worn) do if mine[k] == nil then Add(k) end end
	local net = up - down
	if net <= 0 or down > F.UPGRADE_LOSS * up then return nil end
	if net < math.max(F.UPGRADE_MIN_ABS, F.UPGRADE_MIN * (F.KindsValue(worn, w) or 0)) then return nil end
	return net
end

--- What you wear in each equipment slot (1-18), read once per filter: item levels, their weighed stats, and their
--- stats by kind (kinds[slot]).
--- Kept while you wear the same (by the links, which a new piece or enchant changes) and the weights are the same: the
--- search's filter is made on every keystroke (review, 0.53.6: 18 slots' stats and item levels read each time). Only
--- once every piece was read whole (an item the client is still loading is read again next time).
-- (one per weights table: with two roles picked each judged its own, and a single kept copy was read again for each,
-- every keystroke; 0.56.14)
local wornKept = {}
local function WornGear(w)
	local link = _G.GetInventoryItemLink
	local links = {}
	for slot = 1, 18 do
		local ok, l = pcall(link or function() end, "player", slot)
		links[slot] = (ok and type(l) == "string" and not Secret(l)) and l or ""
	end
	local key = table.concat(links, "\001", 1, 18)
	local kept = wornKept[w]
	if kept and kept.key == key then return unpack(kept.r, 1, 6) end
	local levels, values, kinds, locs, names, ids = {}, {}, {}, {}, {}, {}
	local detailed = C_Item and C_Item.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
	local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	local whole = true
	for slot = 1, 18 do
		local l = links[slot]
		if l ~= "" then
			local lvl = detailed and select(2, pcall(detailed, l))
			if type(lvl) ~= "number" then
				local id = tonumber(l:match("item:(%d+)"))
				local info = id and ItemInfo(id)
				lvl = info and info.ilvl
			end
			if type(lvl) == "number" then levels[slot] = lvl else whole = false end
			names[slot] = l:match("|h%[(.-)%]|h") -- (its name, for "why": over which of two it is)
			local wid = tonumber(l:match("item:(%d+)"))
			-- (what you wear is never an upgrade: 0.52.7, the player. Kept as is:upgrade keys its items, StatKey: a
			-- random suffix's copy, "of the Monkey" while you wear "of the Eagle", is another item; release review)
			if wid then ids[ItemKey(wid, l)] = true end
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
					values[slot] = F.Worth(kinds[slot], w)
				elseif C_Item and C_Item.IsItemDataCachedByID and wid and C_Item.IsItemDataCachedByID(wid) == false then
					whole = false -- (no stats yet: still loading)
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
	wornKept[w] = whole and { key = key, r = { levels, values, kinds, locs, names, ids } } or nil
	return levels, values, kinds, locs, names, ids
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
F.ClearFit = function() fit = {}; wornKept = {}; if ns.ItemStore then ns.ItemStore.Clear("facts") end end
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
	-- (with its surname where characters have one: "Plamen Warr" and "Plamen Mage" are two. Review, 0.53.6)
	local ok, name = pcall(ns.CharacterName)
	if not (ok and type(name) == "string" and name ~= "" and not name:find("[;,%+%-@]")) then return nil end
	-- (and the realm, its letters only: two of the same name on two realms aren't one)
	local okR, realm = pcall(_G.GetRealmName or function() end)
	realm = okR and type(realm) == "string" and not Secret(realm) and realm:gsub("[%s%p]", "") or ""
	return realm ~= "" and (name .. "@" .. realm) or name
end
F._MyName = MyName -- (tests)
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

local GearFitWith
--- A filter: the item is an upgrade for you now (see above). Items the game hasn't loaded yet aren't, for now. With
--- several roles picked (.weights): a clear upgrade for any of them, the biggest gain kept and its role said.
function F.GearFit()
	local sets = F.MyWeightSets()
	if #sets == 1 then return GearFitWith(sets[1][1], sets[1][2]) end
	local fits = {}
	for i, set in ipairs(sets) do fits[i] = GearFitWith(set[1], set[2]) end
	return function(e)
		local best, any
		for i, fitOne in ipairs(fits) do
			if fitOne(e) then
				any = true
				local g = gains[e]
				if g and (not best or (g.gain or 0) > (best.gain or 0)) then
					best = {}
					for k, v in pairs(g) do best[k] = v end
					best.role = sets[i][2]
				end
			end
		end
		gains[e] = best
		return any or false
	end
end

GearFitWith = function(weights, role)
	local me = _G.UnitLevel and _G.UnitLevel("player") or nil -- (unknown: no level checks)
	if type(me) ~= "number" or me <= 0 then me = nil end
	local worn, wornValue, wornKinds, wornLocs, wornNames, wornIds = WornGear(weights)
	-- a one-hander replaces a weapon: the main hand, and the off hand only when it holds one (dual wielding); a shield
	-- or an off-hand item stays (0.51.17, the player: a mace was weighed against main hand and shield together)
	local offWeapon = not (wornLocs[17] == "INVTYPE_SHIELD" or wornLocs[17] == "INVTYPE_HOLDABLE")
	F.fitMade = true -- (this search weighs upgrades: their tooltips compare them, F.UpgradeItem)
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
		local best, bestName, bestId
		for _, it in ipairs(items) do
			local probe = probes[it.id]
			if not probe then probe = { kind = "reward", itemID = it.id }; probes[it.id] = probe end
			if Fit(probe) then
				local g = gains[probe]
				if g and (not best or g.gain > best.gain) then best, bestName, bestId = g, it.name, it.id end
			end
		end
		if not best then return false end
		local g = {}
		for k, v in pairs(best) do g[k] = v end
		g.item, g.itemID = bestName, bestId -- (the reward: what the tooltip has the game compare)
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
		local key = StatKey(e)
		-- (one you wear already: not an upgrade, though it beats your other ring, trinket or weapon; 0.52.7, the player)
		if wornIds[key] then return false end
		-- only what you can get (0.51.9, the player: Naxxramas gear, engineers' trinkets and cosmetic helms for a level 30
		-- warrior): AtlasLoot's dungeons you can enter (not raids, professions, PvP, factions, collections or events)
		if e.kind == "loot" then
			local place = LootPlace and LootPlace(e)
			if place and (place.kind ~= "dungeon" or (me and place.enter and place.enter > me)) then return false end
		end
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
				-- (nothing you want on it: not one, even for an empty slot)
				local worth = F.Worth(f.kinds, weights)
				if worth == 0 then return false end
				-- (its stats' worth; none to weigh: after those, by item level, not item levels against stat points: an empty
				-- trinket slot's every trinket went above real upgrades; review, 0.51.25)
				gains[e] = { gain = worth or ilvl / 100, kinds = f.kinds, loc = loc, ilvl = ilvl, empty = true,
					role = role, byLevel = worth == nil or nil }
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
		local mine = F.Worth(f.kinds, weights)
		if mine == 0 then return false end -- (stats, none of them ones you want: whatever its item level)
		-- (the worn piece's stats read but none of them wanted: worth nothing, not unknown; a role's weights leave many out,
		-- a healer's an agility helm's: 0.54.1)
		if wVal == nil and mine and wKinds then wVal = 0 end
		local up, g
		-- two slots it could go in (dual wielding, rings, trinkets): an upgrade over either piece is one (release review:
		-- against only the weaker by worth, a ring of +3 Strength over your Strength ring and nothing lost wasn't one, as
		-- it gives up more against an Agility ring); below
		local multi = #slots > 1 and loc ~= "INVTYPE_2HWEAPON"
		if multi then
			up = true
		elseif mine and wVal and (mine > 0 or wVal > 0) then
			local gain = F.ClearGain(f.kinds, wKinds, weights) -- (a clear upgrade only: slight trade-offs at most)
			if gain then
				up, g = true, { gain = gain, kinds = f.kinds, worn = wKinds, loc = loc, ilvl = ilvl, wLvl = wLvl }
			end
		elseif mine == nil and f.kinds and wVal and wVal > 0 then
			-- (nothing on it you weigh, a plain weapon's damage for a healer, over a piece that has some: never by its level)
		elseif ilvl >= wLvl + F.LEVEL_CLEAR then
			up, g = true, { gain = ilvl - wLvl, loc = loc, ilvl = ilvl, wLvl = wLvl, byLevel = true }
		end
		if not up then return false end
		-- two slots: against each piece it beats, by name; one it doesn't beat isn't said (0.51.19, the player's ask);
		-- sorted by the bigger gain. None beaten: not an upgrade.
		if multi then
			local vs = {}
			for _, slot in ipairs(slots) do
				local v, l = wornValue[slot], worn[slot]
				if v == nil and mine and wornKinds[slot] then v = 0 end
				local one
				if mine and v and (mine > 0 or v > 0) then
					local gain = F.ClearGain(f.kinds, wornKinds[slot], weights)
					if gain then one = { gain = gain, kinds = f.kinds, worn = wornKinds[slot], ilvl = ilvl, wLvl = l } end
				elseif mine == nil and f.kinds and v and v > 0 then
					-- (nothing you weigh on it, over a piece that has some: not one; as above)
				elseif l and ilvl >= l + F.LEVEL_CLEAR then
					one = { gain = ilvl - l, ilvl = ilvl, wLvl = l, byLevel = true }
				end
				if one then
					one.loc, one.name = loc, wornNames[slot]
					vs[#vs + 1] = one
				end
			end
			if #vs == 0 then return false end
			table.sort(vs, function(a, b) return a.gain > b.gain end)
			g = { gain = vs[1].gain, vs = vs, kinds = f.kinds, loc = loc, ilvl = ilvl, wLvl = vs[1].wLvl }
		end
		if g then g.role = role end
		gains[e] = g
		return true
	end
	return Fit
end

--- The item the game compares for an upgrade row (the tooltip, UI/Tooltip.lua): the row's own, or for a quest the
--- reward that is the upgrade. nil when the last search didn't find it one.
function F.UpgradeItem(e)
	local g = F.fitMade and gains[e]
	if not g then return nil end
	return tonumber(g.itemID) or tonumber(e.itemID), g.item
end

----------------------------------------------------------------------
-- .weights: how upgrades are judged, and the roles they're judged for (0.54.1, a player's ask)
----------------------------------------------------------------------

--- A weights table as words, the most wanted first: "agi 1, str 0.9, crit 0.8".
function F.WeightsText(w, most)
	local list = {}
	for k, v in pairs(w or {}) do list[#list + 1] = { k, v } end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	local out = {}
	for i = 1, math.min(#list, most or 6) do out[i] = list[i][1] .. " " .. (math.floor(list[i][2] * 100 + 0.5) / 100) end
	return table.concat(out, ", ")
end

--- The role ids these words pick for your class, and the words that pick none.
function F.RolesFor(words)
	local class = MyClass()
	local mine, ids, bad = {}, {}, {}
	for _, r in ipairs(RolesOf(class)) do mine[r[1]] = true end
	for w in tostring(words or ""):gmatch("%S+") do
		local id = F.ROLE_WORDS[ns.Lower(w)]
		if id and mine[id] then
			local dup = false
			for _, x in ipairs(ids) do if x == id then dup = true end end
			if not dup then ids[#ids + 1] = id end
		else
			bad[#bad + 1] = w
		end
	end
	return ids, bad
end

--- A Pawn scale string taken: your own weights, picked. ok, and the line to say.
function F.ApplyPawn(text)
	local w, name, ignored = F.ParsePawn(text)
	if not w then return false, L["Not a Pawn scale string: it starts with ( Pawn: v1:"] end
	F.SetCustomWeights(w, name)
	F.SetRoles({ "custom" })
	local say = L["Upgrades: judged by your Pawn scale %s: %s"]:format(name and ('"' .. name .. '"') or "", F.WeightsText(w))
	if #ignored > 0 then say = say .. " " .. L["(not weighed here: %s)"]:format(table.concat(ignored, ", ")) end
	return true, say
end

ns:RegisterCommand("weights", {
	desc = L["How upgrades are judged: the stats your class wants. .weights feral healer judges them for those roles (any of them counts); .weights set str=2 agi=1 or a Pawn scale string for your own; .weights all for all-round"],
	aliases = { "roles", "role" },
	complete = function()
		local out = {}
		for _, r in ipairs(F.RolesOf(MyClass())) do
			out[#out + 1] = { r[1], r[1] == "custom" and F.WeightsText(F.CustomWeights().w, 4) or F.WeightsText(r[2], 4) }
		end
		out[#out + 1] = { "all", L["all-round (your class's weights)"] }
		out[#out + 1] = { "set", L["your own: .weights set str=2 agi=1 sta=0.5"] }
		out[#out + 1] = { "pawn", L["paste a Pawn scale string"] }
		if F.CustomWeights() then out[#out + 1] = { "clear", L["forget your own weights"] } end
		return out
	end,
	run = function(args)
		local class = MyClass()
		args = tostring(args or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local lines = {}
		local low = ns.Lower(args)
		local first, rest = low:match("^(%S+)%s*(.-)$")
		local restRaw = args:match("^%S+%s*(.-)$") or ""
		if args ~= "" then
			if low == "all" or low == "reset" or low == "none" or low == "allround" then
				F.SetRoles(nil)
				lines[#lines + 1] = L["Upgrades: judged all-round again."]
			elseif first == "set" then
				-- (0.65.8) your own: .weights set str=2 agi=1 sta=0.5
				local w, bad = F.ParseWeights(rest)
				if #bad > 0 or not w then
					return { (#bad > 0 and L["Not a stat and its weight: %s"]:format(table.concat(bad, " ")) or L["Which stats? .weights set str=2 agi=1 sta=0.5"]),
						"  " .. L["Stats: %s"]:format(F.STAT_LIST) }
				end
				F.SetCustomWeights(w, nil)
				F.SetRoles({ "custom" })
				lines[#lines + 1] = L["Upgrades: judged by your own weights: %s"]:format(F.WeightsText(w, 30))
			elseif first == "pawn" or args:find("^%(%s*[Pp]awn") then
				-- (0.65.8) a Pawn scale string: typed after it, or pasted in a window (they're often longer than the prompt
				-- takes)
				local text = first == "pawn" and restRaw or args
				if text == "" then
					local O = ns.Options
					if O and O.PasteDialog then
						O.PasteDialog(L["Your Pawn scale"], L["Paste a Pawn scale string (Ctrl+V): it starts with ( Pawn: v1:"], F.ApplyPawn)
						return { L["Paste your Pawn scale string into the window (Ctrl+V), then Enter."] }
					end
					return { L["Not a Pawn scale string: it starts with ( Pawn: v1:"] }
				end
				local ok, say = F.ApplyPawn(text)
				if not ok then return { say } end
				lines[#lines + 1] = say
			elseif first == "clear" or first == "forget" then
				F.SetCustomWeights(nil)
				lines[#lines + 1] = L["Your own weights forgotten."]
			else
				local ids, bad = F.RolesFor(args)
				if #bad > 0 then
					local names = {}
					for _, r in ipairs(F.RolesOf(class)) do names[#names + 1] = r[1] end
					return { L["Not a role of your class: %s. Yours: %s"]:format(table.concat(bad, ", "), table.concat(names, ", ")) }
				end
				F.SetRoles(ids)
				local said = {}
				for _, id in ipairs(ids) do said[#said + 1] = F.ROLE_SAY[id] or id end
				lines[#lines + 1] = L["Upgrades: judged for %s (a clear upgrade for any of them counts)."]:format(table.concat(said, ", "))
			end
		end
		lines[#lines + 1] = L["How upgrades are judged: an item's stats weighed for what you want, against the piece you wear there; a clear upgrade gains more than it gives up."]
		local picked = F.MyRoles()
		local on = {}
		for _, id in ipairs(picked or {}) do on[id] = true end
		if not picked then lines[#lines + 1] = "  " .. L["All-round (now): %s"]:format(F.WeightsText(class and F.WEIGHTS[class] or GENERIC)) end
		local custom = F.CustomWeights()
		for _, r in ipairs(F.RolesOf(class)) do
			local id, w = r[1], r[2]
			local label = F.ROLE_SAY[id] or id
			-- (your own: as you set them, and the Pawn scale's name)
			if id == "custom" then
				w = custom.w
				if custom.name then label = label .. ' "' .. custom.name .. '"' end
			end
			lines[#lines + 1] = "  " .. (on[id] and "|cff40ff40" or "") .. label .. (on[id] and (" " .. L["(now)"] .. "|r") or "")
				.. ": " .. F.WeightsText(w, id == "custom" and 30 or nil)
		end
		lines[#lines + 1] = L[".weights <role> [role...] picks them (.weights feral healer); .weights all goes back to all-round."]
		lines[#lines + 1] = L["Your own: .weights set str=2 agi=1 sta=0.5, or .weights pawn and paste a Pawn scale string; .weights custom picks them again, .weights clear forgets them."]
		return lines
	end,
})

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
	-- (a school's spell damage, "+12 Frost Spell Damage": its own, weighed for the trees that cast it; first, so a name
	-- with SPELL_DAMAGE in it is read as its school too; 0.65.11)
	{ "FIRE_DAMAGE", "fire" }, { "FROST_DAMAGE", "frost" }, { "ARCANE_DAMAGE", "arcane" }, { "NATURE_DAMAGE", "nature" },
	{ "SHADOW_DAMAGE", "shadow" }, { "HOLY_DAMAGE", "holy" },
	{ "FERAL_ATTACK_POWER", "feralap" }, { "RANGED_ATTACK_POWER", "rap" }, { "ATTACK_POWER", "ap" }, { "STRENGTH", "str" },
	{ "AGILITY", "agi" }, { "STAMINA", "sta" }, { "INTELLECT", "int" }, { "SPIRIT", "spi" }, { "HEALING", "heal" },
	{ "SPELL_DAMAGE", "sp" }, { "SPELL_POWER", "sp" }, { "HIT_SPELL", "spellhit" }, { "CRIT_SPELL", "spellcrit" },
	{ "SPELL_HIT", "spellhit" }, { "SPELL_CRIT", "spellcrit" },
	{ "CRIT", "crit" }, { "HIT", "hit" }, { "HASTE", "haste" }, { "MANA_REGEN", "mp5" }, { "POWER_REGEN0", "mp5" },
	{ "DAMAGE_PER_SECOND", "dps" }, { "RESISTANCE0", "armor" }, { "DEFENSE", "def" }, { "DODGE", "dodge" },
	-- (a shield's block value is points, its block chance per cent: apart, 0.65.11: 30 block value counted as 30% block)
	{ "PARRY", "parry" }, { "BLOCK_VALUE", "blockv" }, { "BLOCK", "block" },
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

-- How much each stat is worth, by talent tree (0.65.11, the player: "our own single role profile, split by talent tree
-- (.weights fury vs .weights arms), a single simplified stat weight scale good enough for 1-60"). Terminal's own scale:
-- the tree's main stat is 1, the rest rounded to what a player can read at a glance. Hit, crit, dodge, parry and block
-- chance are per 1% (as WoW Forever's gear gives them), defense per skill point, the rest per point. Percent stats are
-- worth more the higher you are (1% hit is about 3 Strength at 20, 12 at 60): one scale for every level sets them for
-- the levels gear changes most, the 30s and 40s. Weighed from how the stats work (2 attack power per Strength for the
-- plate and mail melee, a weapon's DPS about 14 attack power, Agility's crit and armor) and checked against what the
-- wowsims Forever simulations make of them; on Forever, healing is its own stat (spell damage doesn't heal) and a
-- feral's weapon DPS counts in forms.
local GENERIC = { str = 0.6, agi = 0.6, int = 0.6, spi = 0.3, sta = 0.5, ap = 0.3, rap = 0.2, sp = 0.4, heal = 0.3,
	crit = 3, hit = 3, spellhit = 3, spellcrit = 3, haste = 2, mp5 = 0.5, dps = 2, rdps = 1, armor = 0.01, def = 0.3,
	dodge = 1, parry = 1, block = 0.5, blockv = 0.05 }

-- shared shapes
local function With(base, more) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(more or {}) do t[k] = v end return t end
-- a plate or mail fighter's: Strength 2 attack power, Agility crit and armor
-- (Spirit only regenerates health out of combat for them: little; Stamina more; a bow or thrown weapon little)
local STR_MELEE = { str = 1, agi = 0.5, ap = 0.5, crit = 6, hit = 7, haste = 4, dps = 7, rdps = 0.5, sta = 0.4, spi = 0.2,
	dodge = 0.8, parry = 0.8, armor = 0.01 }
-- a tank's: Stamina first, then avoidance; hit and crit for the threat
local TANK = { sta = 1, str = 0.6, agi = 0.6, def = 0.8, dodge = 4, parry = 4, block = 2, blockv = 0.3, armor = 0.03,
	hit = 4, crit = 3, haste = 2, ap = 0.3, dps = 4, rdps = 0.3 }
-- a caster's: Intellect 1, spell damage what the spells hit with, hit and crit per 1%; a wand's DPS while levelling, a
-- staff's or dagger's next to nothing
local CASTER = { int = 1, sp = 3, spellhit = 8, spellcrit = 6, crit = 6, haste = 4, spi = 0.5, mp5 = 1, sta = 0.4, rdps = 1,
	dps = 0.2 }
-- a healer's: healing (its own stat on Forever), mana, crit; no weapon DPS (a plain wand goes by its item level: release
-- review)
local HEALER = { int = 1, heal = 1, spi = 0.6, mp5 = 1.2, spellcrit = 4, crit = 4, haste = 3, sta = 0.3 }

F.ROLES = {
	WARRIOR = {
		{ "arms", STR_MELEE },
		{ "fury", With(STR_MELEE, { dps = 5 }) }, -- (two weapons: each one's DPS counts less)
		{ "protection", TANK },
	},
	PALADIN = {
		{ "holy", With(HEALER, { spi = 0.4 }) },
		{ "protection", With(TANK, { int = 0.4, sp = 0.6, holy = 0.6, mp5 = 0.5, spellhit = 2 }) }, -- (holy damage holds threat)
		{ "retribution", With(STR_MELEE, { int = 0.2, sp = 0.4, holy = 0.4, mp5 = 0.2 }) },
	},
	HUNTER = {
		-- (Agility 2 ranged attack power and a little crit: ranged attack power 0.45 each; mana matters: Intellect and mp5;
		-- the bow's DPS, the melee weapon's little)
		{ "beastmastery", { agi = 1, rap = 0.45, ap = 0.45, crit = 6, hit = 7, haste = 4, rdps = 5, dps = 0.5, int = 0.6, mp5 = 1.5,
			spi = 0.6, sta = 0.3, armor = 0.01 } },
		{ "marksmanship", { agi = 1, rap = 0.45, ap = 0.45, crit = 6, hit = 7, haste = 4, rdps = 5, dps = 0.5, int = 0.6, mp5 = 1.5,
			spi = 0.6, sta = 0.3, armor = 0.01 } },
		-- (Forever's survival fights in melee too: both weapons)
		{ "survival", { agi = 1, ap = 0.5, rap = 0.4, str = 0.5, crit = 6, hit = 7, haste = 4, dps = 6, rdps = 3, int = 0.5,
			mp5 = 1.2, spi = 0.6, dodge = 1.5, sta = 0.4, armor = 0.01 } },
	},
	ROGUE = (function()
		local R = { agi = 1, str = 0.5, ap = 0.5, crit = 6, hit = 7, haste = 4, dps = 5, rdps = 0.5, spi = 0.2, dodge = 1, parry = 1,
			sta = 0.4, armor = 0.01 }
		return { { "assassination", R }, { "combat", R }, { "subtlety", R } }
	end)(),
	PRIEST = {
		{ "discipline", With(HEALER, { spi = 1 }) },
		{ "holy", With(HEALER, { spi = 1 }) },
		{ "shadow", With(CASTER, { shadow = 3, spi = 1, sta = 0.5, rdps = 2 }) }, -- (Spirit Tap, a wand while levelling)
	},
	MAGE = {
		{ "arcane", With(CASTER, { arcane = 3, spi = 1 }) },
		{ "fire", With(CASTER, { fire = 3, spi = 1 }) },
		{ "frost", With(CASTER, { frost = 3, spi = 1 }) },
	},
	WARLOCK = {
		{ "affliction", With(CASTER, { shadow = 3, sta = 0.8, spi = 0.3 }) }, -- (Life Tap: Stamina for mana)
		{ "demonology", With(CASTER, { shadow = 3, sta = 0.8, spi = 0.3 }) },
		{ "destruction", With(CASTER, { shadow = 2.5, fire = 2.5, sta = 0.6, spi = 0.3 }) },
	},
	SHAMAN = {
		{ "elemental", With(CASTER, { nature = 3, fire = 1, mp5 = 1.2, rdps = 0, dps = 0.3 }) }, -- (no wand)
		{ "enhancement", With(STR_MELEE, { crit = 7, int = 0.3, sp = 0.3, nature = 0.3, mp5 = 0.8, rdps = 0 }) },
		{ "restoration", With(HEALER, { spi = 0.5, mp5 = 1.5 }) },
	},
	DRUID = {
		{ "balance", With(CASTER, { arcane = 3, nature = 3, spi = 0.6 }) },
		-- (a cat: Strength 2 attack power, Agility 1 and crit; on Forever the weapon's DPS counts in forms)
		{ "feral", { str = 1, agi = 0.9, ap = 0.5, feralap = 0.5, crit = 6, hit = 6, haste = 4, dps = 4.5, sta = 0.4, spi = 0.2,
			int = 0.2, dodge = 0.8, armor = 0.02 } },
		{ "bear", With(TANK, { agi = 0.8, str = 0.6, parry = 0, block = 0, blockv = 0, armor = 0.08, feralap = 0.3, dps = 4,
			rdps = 0 }) },
		{ "restoration", With(HEALER, { spi = 0.9 }) },
	},
}
-- the tree each class is judged for when none is picked (the one most level with)
F.DEFAULT_TREE = { WARRIOR = "arms", PALADIN = "retribution", HUNTER = "beastmastery", ROGUE = "combat", PRIEST = "shadow",
	MAGE = "frost", WARLOCK = "affliction", SHAMAN = "enhancement", DRUID = "feral" }
F.WEIGHTS = {}
for class, list in pairs(F.ROLES) do
	for _, r in ipairs(list) do if r[1] == F.DEFAULT_TREE[class] then F.WEIGHTS[class] = r[2] end end
end
F.WEIGHTS.DEATHKNIGHT, F.WEIGHTS.MONK, F.WEIGHTS.DEMONHUNTER = F.WEIGHTS.WARRIOR, F.WEIGHTS.ROGUE, F.WEIGHTS.ROGUE
F.WEIGHTS.EVOKER = F.WEIGHTS.MAGE
F.WEIGHTS.GENERIC = GENERIC

-- Roles (0.54.1, a player's ask: "How does the addon score upgrades? Can I control it?"): .weights picks one tree (or
-- your own weights), kept per character; none picked, the class's levelling tree above.
local L = ns.L
F.ROLE_SAY = { arms = L["Arms"], fury = L["Fury"], protection = L["Protection"], holy = L["Holy"],
	retribution = L["Retribution"], beastmastery = L["Beast Mastery"], marksmanship = L["Marksmanship"],
	survival = L["Survival"], assassination = L["Assassination"], combat = L["Combat"], subtlety = L["Subtlety"],
	discipline = L["Discipline"], shadow = L["Shadow"], arcane = L["Arcane"], fire = L["Fire"], frost = L["Frost"],
	affliction = L["Affliction"], demonology = L["Demonology"], destruction = L["Destruction"], elemental = L["Elemental"],
	enhancement = L["Enhancement"], restoration = L["Restoration"], balance = L["Balance"], feral = L["Feral"],
	bear = L["Bear"], custom = L["your own weights"] }
-- (what each tree may be typed as: ".weights prot", ".weights resto"; a role's word, the tree that plays it for your class:
-- ".weights tank", ".weights healer"; the roles kept before 0.65.11 read so too)
F.ROLE_WORDS = { arms = "arms", fury = "fury", prot = "protection", protection = "protection", holy = "holy",
	ret = "retribution", retribution = "retribution", bm = "beastmastery", beastmastery = "beastmastery",
	beast = "beastmastery", mm = "marksmanship", marks = "marksmanship", marksmanship = "marksmanship", surv = "survival",
	survival = "survival", sv = "survival", assa = "assassination", assassination = "assassination", mut = "assassination",
	mutilate = "assassination", combat = "combat", sub = "subtlety", subtlety = "subtlety", disc = "discipline",
	discipline = "discipline", shadow = "shadow", spriest = "shadow", arcane = "arcane", fire = "fire", frost = "frost",
	aff = "affliction", affli = "affliction", affliction = "affliction", demo = "demonology", demonology = "demonology",
	destro = "destruction", destruction = "destruction", ele = "elemental", elemental = "elemental", enh = "enhancement",
	enhance = "enhancement", enhancement = "enhancement", resto = "restoration", restoration = "restoration",
	balance = "balance", boomkin = "balance", moonkin = "balance", feral = "feral", cat = "feral", bear = "bear",
	custom = "custom", own = "custom", mine = "custom" }
-- a role said as a role: the tree that plays it, for each class
F.ROLE_TREES = {
	tank = { WARRIOR = "protection", PALADIN = "protection", DRUID = "bear" },
	healer = { PALADIN = "holy", PRIEST = "holy", SHAMAN = "restoration", DRUID = "restoration" },
	heal = "healer", healing = "healer",
	dps = { WARRIOR = "arms", PALADIN = "retribution", HUNTER = "beastmastery", ROGUE = "combat", PRIEST = "shadow",
		MAGE = "frost", WARLOCK = "affliction", SHAMAN = "enhancement", DRUID = "feral" },
	damage = "dps",
	melee = { WARRIOR = "arms", PALADIN = "retribution", HUNTER = "survival", ROGUE = "combat", SHAMAN = "enhancement",
		DRUID = "feral" },
	ranged = { HUNTER = "beastmastery" },
	caster = { PRIEST = "shadow", MAGE = "frost", WARLOCK = "affliction", SHAMAN = "elemental", DRUID = "balance" },
	spell = "caster",
}
--- The tree a word names for a class: "prot" -> "protection", "tank" -> a druid's "bear"; nil when none.
-- (a tree's word for a class whose tree that plays it is named otherwise: "prot" for a druid is its bear, "holy" for a
-- shaman its restoration, "resto" for a priest its holy; 0.65.x review)
local AS_ROLE = { prot = "tank", protection = "tank", holy = "healer", resto = "healer", restoration = "healer",
	disc = "healer", discipline = "healer" }
function F.TreeOf(word, class)
	word = ns.Lower(tostring(word or ""))
	local id = F.ROLE_WORDS[word]
	if id and (not class or not F.ROLES[class]) then return id end
	if id then
		for _, r in ipairs(F.ROLES[class]) do if r[1] == id then return id end end
		if AS_ROLE[word] then word = AS_ROLE[word] else return id end
	end
	local t = F.ROLE_TREES[word]
	if type(t) == "string" then t = F.ROLE_TREES[t] end
	return type(t) == "table" and t[class or ""] or nil
end

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
	dps = "dps", armor = "armor", def = "def", defense = "def", dodge = "dodge", parry = "parry", block = "block",
	blockv = "blockv", blockvalue = "blockv", rdps = "rdps", rangeddps = "rdps", fire = "fire", frost = "frost", arcane = "arcane", nature = "nature",
	shadow = "shadow", holy = "holy" }
F.STAT_LIST = "str agi sta int spi ap rap feralap sp heal crit hit spellhit spellcrit haste mp5 dps rdps armor def dodge parry block blockv fire frost arcane nature shadow holy"
-- Pawn's names for them (its scale strings: "( Pawn: v1: "Name": Strength=2, HitRating=1.5, Ap=0.8 )"); a rating and the
-- plain stat alike (Classic's "+1% hit" is its HitRating), its weapon DPS kinds as one
local PAWN = { strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi", ap = "ap", rap = "rap",
	feralap = "feralap", spelldamage = "sp", spellpower = "sp", healing = "heal", hit = "hit", hitrating = "hit", crit = "crit",
	critrating = "crit", spellhit = "spellhit", spellhitrating = "spellhit", spellcrit = "spellcrit",
	spellcritrating = "spellcrit", haste = "haste", hasterating = "haste", spellhasterating = "haste", mp5 = "mp5", dps = "dps",
	meleedps = "dps", rangeddps = "rdps", armor = "armor", defense = "def", defenserating = "def", dodge = "dodge",
	dodgerating = "dodge", parry = "parry", parryrating = "parry", block = "block", blockrating = "block", blockvalue = "blockv",
	firespelldamage = "fire", frostspelldamage = "frost", arcanespelldamage = "arcane", naturespelldamage = "nature",
	shadowspelldamage = "shadow", holyspelldamage = "holy" }
F.PAWN_STATS = PAWN

--- "str=2 agi=1.5, sta 0.5" -> { str = 2, agi = 1.5, sta = 0.5 }, and the words that aren't a stat and its number.
function F.ParseWeights(text)
	local w, bad, any = {}, {}, false
	local words = {}
	-- ("str = 2" spaced, "str=1,5" a decimal comma: read as typed; 0.65.x review)
	text = tostring(text or ""):gsub("%s*([=:])%s*", "%1"):gsub("(%d),(%d)", "%1.%2")
	for t in text:gsub(",", " "):gmatch("%S+") do words[#words + 1] = t end
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
-- (a Pawn string's entries that aren't stats: not said as stats Terminal doesn't weigh; 0.65.x review)
local PAWN_NOT_STATS = { class = true, spec = true, specid = true, gemqualitylevel = true, metagemqualitylevel = true,
	speedbaseline = true, unusable = true }
function F.ParsePawn(text)
	-- (any case: "( pawn: v1: ..."; 0.65.x review)
	local name, body = tostring(text or ""):match('%(%s*[Pp][Aa][Ww][Nn]%s*:%s*[Vv]%d+%s*:%s*"([^"]*)"%s*:(.-)%)')
	if not body then return nil end
	local w, ignored, any = {}, {}, false
	for piece in body:gmatch("[^,]+") do
		local k, v = piece:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		local n = v and tonumber(v)
		if k and n then
			local kind = PAWN[ns.Lower(k)]
			if kind then
				if w[kind] == nil or n > w[kind] then w[kind] = n end -- (melee and ranged DPS, rating and value: the more)
				-- (its plain Dps: a weapon's, either slot)
				if ns.Lower(k) == "dps" and (w.rdps == nil or n > w.rdps) then w.rdps = n end
				any = true
			elseif n ~= 0 and not PAWN_NOT_STATS[ns.Lower(k)] then
				ignored[#ignored + 1] = k
			end
		end
	end
	if not any then return nil end
	return w, name ~= "" and name or nil, ignored
end

--- Does a weights table weigh anything (some stat above 0)? (0.65.x review: str=0 agi=0 was taken, and nothing could be
--- an upgrade again.)
function F.WeighsAny(w)
	for _, v in pairs(w or {}) do if type(v) == "number" and v > 0 then return true end end
	return false
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
-- the main stats: what a scale is scaled by (not 1% hit, which Pawn and the simulations weigh at 10 to 25 Strength: a scale
-- whose hit is 1 made +3 Strength no upgrade at all; 0.65.11)
local MAIN_STATS = { "str", "agi", "int", "spi", "sta" }
--- Weights scaled so their main stat (the most of Strength, Agility, Intellect, Spirit or Stamina; else of spell damage,
--- healing, attack power; else the most wanted of any) is 1, as the trees' own are.
function F.Scaled(w)
	local s = scaled[w]
	if s then return s end
	local top = 0
	for _, k in ipairs(MAIN_STATS) do if (w[k] or 0) > top then top = w[k] end end
	-- (spell damage, healing or attack power far above every main stat, Intellect 0.05 next to Healing 1: by that one,
	-- else a point of the tiny one would be a whole upgrade; 0.65.x review)
	local power = 0
	for _, k in ipairs({ "sp", "heal", "ap", "rap", "feralap" }) do if (w[k] or 0) > power then power = w[k] end end
	if top <= 0 or power > 5 * top then top = power end
	if top <= 0 then for k, v in pairs(w) do if k ~= "dps" and k ~= "armor" and v > top then top = v end end end
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
	-- (one role at a time, 0.65.9, the player: "only let .weights define one role; easiest on the computation too";
	-- several kept from before: the first of them that's still a role of yours)
	local mine = {}
	for _, r in ipairs(RolesOf(MyClass())) do mine[r[1]] = true end
	-- (a role kept before 0.65.11, "healer", "tank": the tree that plays it now)
	local class = MyClass()
	for _, id in ipairs(saved) do
		local t = mine[id] and id or F.TreeOf(id, class)
		if t and mine[t] then return { t } end
	end
	return nil
end
--- Pick the role for this character (a list of one id; nil or empty: the all-round weights again).
function F.SetRoles(ids)
	local db, key = ns.db, F._MyName and F._MyName()
	if not (db and key) then return end
	db.upgradeRoles = type(db.upgradeRoles) == "table" and db.upgradeRoles or {}
	db.upgradeRoles[key] = (ids and ids[1]) and { ids[1] } or nil
end

-- Your talents pick the tree when you haven't (0.66.2, the player): the one holding most of your points, by the talent
-- window's tab name (English: "Feral Combat" is feral, the cat; .weights bear for a bear), else its place in the window
-- (the trees' order, the classic one). A tie, or no points yet: the class's levelling tree.
local TAB_ORDER = { DRUID = { "balance", "feral", "restoration" } }
--- The tree id for the talent window's tab `name` (the `index`th) of `class`, or nil.
function F.TreeOfTab(name, index, class)
	local roles = F.ROLES[class or ""]
	if not roles then return nil end
	local mine = {}
	for _, r in ipairs(roles) do mine[r[1]] = true end
	local low = type(name) == "string" and ns.Lower(name) or ""
	local function Ok(id) return id and mine[id] and id or nil end
	local id = Ok(F.ROLE_WORDS[(low:gsub("%s+", ""))]) or Ok(F.ROLE_WORDS[low:match("^%S+") or ""])
	if id then return id end
	-- (another language: the tree's own name as Terminal says it)
	for _, r in ipairs(roles) do
		local say = F.ROLE_SAY[r[1]]
		if say and low ~= "" and low:sub(1, #say) == ns.Lower(say) then return r[1] end
	end
	local order = TAB_ORDER[class]
	return order and Ok(order[index]) or (roles[index] and roles[index][1]) or nil
end
--- The tree your talent points are in (its id), or nil: none spent, a tie, or not read.
function F.TalentTree(class)
	local TL = ns.Talents
	local points = TL and TL.Points and TL.Points()
	if type(points) ~= "table" then return nil end
	local best, second
	for _, t in ipairs(points) do
		if not best or t.points > best.points then best, second = t, best
		elseif not second or t.points > second.points then second = t end
	end
	if not best or best.points <= 0 or (second and second.points == best.points) then return nil end
	return F.TreeOfTab(best.name, best.index, class)
end

--- The tree judged by when none is picked: your talents' (and true), else the class's levelling tree.
function F.UnpickedTree(class)
	local t = F.TalentTree(class)
	if t then return t, true end
	return class and F.DEFAULT_TREE[class] or nil, false
end

--- The weights to judge by: { { weights, role } ... } (role nil: the all-round ones).
function F.MyWeightSets()
	local class = MyClass()
	local roles = F.MyRoles()
	if not roles then
		local t = F.TalentTree(class)
		if t then
			for _, r in ipairs(F.ROLES[class] or {}) do if r[1] == t then return { { r[2], t } } end end
		end
		return { { class and F.WEIGHTS[class] or GENERIC } }
	end
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

-- the ranged slot's items: their weapon DPS is a ranged weapon's (a hunter's bow, a caster's wand), not a melee one's
local RANGED_LOC = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
F.RANGED_LOC = RANGED_LOC
--- An item's stats (the game's table) by kind: { str = 7, sta = 4 } (kinds Terminal weighs; others left out). `ranged`:
--- it's for the ranged slot, its weapon DPS "rdps" (0.65.x review: a hunter's melee stat stick's DPS weighed as a bow's).
function F.StatKinds(stats, ranged)
	if type(stats) ~= "table" then return nil end
	local out = {}
	for key, amount in pairs(stats) do
		local k = type(key) == "string" and type(amount) == "number" and StatKind(key)
		if k == "dps" and ranged then k = "rdps" end
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
local PLAIN = { dps = true, rdps = true, armor = true } -- (a wand's or bow's too: 0.65.11)
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
-- Hit over the cap counts for nothing (0.66.3, the player: "weights that know your hit cap"): your hit chance now, from
-- gear and talents as the game says it, against the chance to miss: a mob of your level below 60 (5% melee and ranged,
-- 3% spells: a spell always keeps 1% to miss), a boss three levels above at 60 (9%, 16%). An item's hit counts only up to the cap, after the piece it
-- replaces gives its own up. The game not saying (or keeping it secret): hit counts in full, as before.
F.HIT_CAP = { hit = 5, spellhit = 3 } -- (spells always keep 1% to miss: 3 of a same-level mob's 4; review)
F.HIT_CAP_60 = { hit = 9, spellhit = 16 }
F.HIT_FNS = { hit = "GetHitModifier", spellhit = "GetSpellHitModifier" }
--- Your hit chances now and their caps: { hit = { now, cap }, spellhit = { now, cap } }, a kind left out when unknown.
function F.HitNow()
	local okL, me = pcall(_G.UnitLevel or function() end, "player")
	me = okL and type(me) == "number" and not Secret(me) and me or nil
	if not me or me <= 0 then return {} end
	local caps = me >= 60 and F.HIT_CAP_60 or F.HIT_CAP
	local out = {}
	for kind, fn in pairs(F.HIT_FNS) do
		local f = _G[fn]
		if type(f) == "function" then
			local ok, v = pcall(f)
			-- (a chance in per cent: a number past 100 isn't one)
			if ok and type(v) == "number" and not Secret(v) and v >= 0 and v <= 100 then out[kind] = { v, caps[kind] } end
		end
	end
	return out
end
local hitNow -- (this search's: GearFitWith)
function F.SetHitNow(h) hitNow = h end -- (tests, and the searches that weigh upgrades)

--- What the item's stats add over the worn piece's, weighed (its gain), when it's a clear upgrade; else nil. Also true
--- when hit past your cap counted for less.
function F.ClearGain(mine, worn, w)
	if type(mine) ~= "table" then return nil end
	worn = type(worn) == "table" and worn or {}
	w = w or GENERIC
	local up, down, capped = 0, 0, false
	local function Add(k)
		local wk = w[k]
		if not wk then return end
		local d = (mine[k] or 0) - (worn[k] or 0)
		local hc = hitNow and hitNow[k]
		if hc then
			-- (only the hit under the cap: with the worn piece's given up, against what you have now)
			local now, cap = hc[1], hc[2]
			local useful = math.min(now - (worn[k] or 0) + (mine[k] or 0), cap) - math.min(now, cap)
			if useful < d - 1e-6 then capped = true end -- (a fraction's rounding isn't hit past the cap; review)
			d = useful
		end
		if d > 0 then up = up + wk * d elseif d < 0 then down = down - wk * d end
	end
	for k in pairs(mine) do Add(k) end
	for k in pairs(worn) do if mine[k] == nil then Add(k) end end
	local net = up - down
	if net <= 0 or down > F.UPGRADE_LOSS * up then return nil end
	if net < math.max(F.UPGRADE_MIN_ABS, F.UPGRADE_MIN * (F.KindsValue(worn, w) or 0)) then return nil end
	return net, capped
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
					kinds[slot] = F.StatKinds(st, slot == 18)
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
	local set = F.MyWeightSets()[1] -- (one role at a time: 0.65.9)
	return GearFitWith(set[1], set[2])
end

GearFitWith = function(weights, role)
	local me = _G.UnitLevel and _G.UnitLevel("player") or nil -- (unknown: no level checks)
	if type(me) ~= "number" or me <= 0 then me = nil end
	local worn, wornValue, wornKinds, wornLocs, wornNames, wornIds = WornGear(weights)
	hitNow = F.HitNow() -- (your hit chance now: hit past the cap counts for nothing)
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
					if st then f.kinds = F.StatKinds(st, RANGED_LOC[loc]); Remember(key, f, class) end
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
				f.kinds = F.StatKinds(st, RANGED_LOC[loc])
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
			local gain, capped = F.ClearGain(f.kinds, wKinds, weights) -- (a clear upgrade only: slight trade-offs at most)
			if gain then
				up, g = true, { gain = gain, kinds = f.kinds, worn = wKinds, loc = loc, ilvl = ilvl, wLvl = wLvl, capped = capped }
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
					local gain, capped = F.ClearGain(f.kinds, wornKinds[slot], weights)
					if gain then one = { gain = gain, kinds = f.kinds, worn = wornKinds[slot], ilvl = ilvl, wLvl = l, capped = capped } end
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
			g = { gain = vs[1].gain, vs = vs, kinds = f.kinds, loc = loc, ilvl = ilvl, wLvl = vs[1].wLvl, capped = vs[1].capped }
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
		local id = F.TreeOf(w, class)
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
	-- (not one, or cut off by the prompt's length: the window takes a whole one; 0.65.x review)
	if not w then return false, L["Not a whole Pawn scale string: ( Pawn: v1: \"Name\": Strength=1, ... ). A long one is cut off in the prompt: .weights pawn opens a window to paste it into."] end
	if not F.WeighsAny(w) then return false, L["No stat in it weighs anything (all 0 or less)."] end
	F.SetCustomWeights(w, name)
	if not F.CustomWeights() then return false, L["No character to keep them for yet: try again in a moment."] end
	F.SetRoles({ "custom" })
	local say = name and L["Upgrades: judged by your Pawn scale %s: %s"]:format('"' .. name .. '"', F.WeightsText(w, 30))
		or L["Upgrades: judged by your Pawn scale: %s"]:format(F.WeightsText(w, 30))
	if #ignored > 0 then say = say .. " " .. L["(not weighed here: %s)"]:format(table.concat(ignored, ", ")) end
	return true, say
end

ns:RegisterCommand("weights", {
	desc = L["How upgrades are judged: the stats your talent tree wants. .weights arms, .weights resto, .weights tank picks a tree; .weights set str=2 agi=1 or a Pawn scale string for your own; .weights all for the tree your talent points are in"],
	aliases = { "roles", "role" },
	complete = function()
		local out = {}
		for _, r in ipairs(F.RolesOf(MyClass())) do
			out[#out + 1] = { r[1], r[1] == "custom" and F.WeightsText(F.CustomWeights().w, 4) or F.WeightsText(r[2], 4) }
		end
		out[#out + 1] = { "all", L["the tree your talent points are in"] }
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
			if low == "all" or low == "reset" or low == "none" or low == "allround" or low == "auto" or low == "talents" then
				F.SetRoles(nil)
				lines[#lines + 1] = L["Upgrades: judged for the tree your talent points are in again."]
			elseif first == "set" then
				-- (0.65.8) your own: .weights set str=2 agi=1 sta=0.5
				local w, bad = F.ParseWeights(rest)
				if #bad > 0 or not w then
					return { (#bad > 0 and L["Not a stat and its weight: %s"]:format(table.concat(bad, " ")) or L["Which stats? .weights set str=2 agi=1 sta=0.5"]),
						"  " .. L["Stats: %s"]:format(F.STAT_LIST) }
				end
				if not F.WeighsAny(w) then return { L["No stat in it weighs anything (all 0 or less)."] } end
				F.SetCustomWeights(w, nil)
				F.SetRoles({ "custom" })
				lines[#lines + 1] = L["Upgrades: judged by your own weights: %s"]:format(F.WeightsText(w, 30))
			elseif first == "pawn" or args:find("^%(%s*[Pp][Aa][Ww][Nn]") then
				-- (0.65.8) a Pawn scale string: typed after it, or pasted in a window (they're often longer than the prompt
				-- takes)
				local text = first == "pawn" and restRaw or args
				if text == "" then
					local O = ns.Options
					if O and O.PasteDialog then
						O.PasteDialog(L["Your Pawn scale"], L["Paste a Pawn scale string (Ctrl+V): it starts with ( Pawn: v1:"], F.ApplyPawn)
						return { L["Paste your Pawn scale string into the window (Ctrl+V), then Enter."] }
					end
					return { L["Not a whole Pawn scale string: ( Pawn: v1: \"Name\": Strength=1, ... ). A long one is cut off in the prompt: .weights pawn opens a window to paste it into."] }
				end
				local ok, say = F.ApplyPawn(text)
				if not ok then return { say } end
				lines[#lines + 1] = say
			elseif first == "clear" or first == "forget" then
				F.SetCustomWeights(nil)
				lines[#lines + 1] = L["Your own weights forgotten."]
			else
				local ids, bad = F.RolesFor(args)
				local names = {}
				for _, r in ipairs(F.RolesOf(class)) do names[#names + 1] = r[1] end
				if #bad > 0 then
					return { L["Not a role of your class: %s. Yours: %s"]:format(table.concat(bad, ", "), table.concat(names, ", ")) }
				end
				-- (one role at a time, 0.65.9)
				if #ids > 1 then return { L["One role at a time: .weights %s. Yours: %s"]:format(ids[1], table.concat(names, ", ")) } end
				F.SetRoles(ids)
				lines[#lines + 1] = L["Upgrades: judged for %s."]:format(F.ROLE_SAY[ids[1]] or ids[1])
			end
		end
		lines[#lines + 1] = L["How upgrades are judged: an item's stats weighed for what you want, against the piece you wear there; a clear upgrade gains more than it gives up."]
		local picked = F.MyRoles()
		local on = {}
		for _, id in ipairs(picked or {}) do on[id] = true end
		-- (none picked: the class's levelling tree is the one used, said so on its line; 0.65.x review: an "All-round" line
		-- repeated it under another name)
		local default, fromTalents
		if not picked then default, fromTalents = F.UnpickedTree(class) end
		if not picked and not default then lines[#lines + 1] = "  " .. L["Now: %s"]:format(F.WeightsText(GENERIC, 30)) end
		if default then on[default] = true end
		local custom = F.CustomWeights()
		for _, r in ipairs(F.RolesOf(class)) do
			local id, w = r[1], r[2]
			local label = F.ROLE_SAY[id] or id
			-- (your own: as you set them, and the Pawn scale's name)
			if id == "custom" then
				w = custom.w
				if custom.name then label = label .. ' "' .. custom.name .. '"' end
			end
			local now = on[id] and ((id == default) and (fromTalents and L["(now: from your talents)"]
				or L["(now: your class's levelling tree)"]) or L["(now)"])
			-- (every stat: the top few were the per-1% ones, and a tree's main stat never showed; 0.65.x review)
			lines[#lines + 1] = "  " .. (now and "|cff40ff40" or "") .. label .. (now and (" " .. now .. "|r") or "")
				.. ": " .. F.WeightsText(w, 30)
		end
		lines[#lines + 1] = L[".weights <tree> picks one (.weights %s); .weights all goes back to the tree your talent points are in (none spent: your class's levelling tree)."]:format(
			(F.ROLES[class or ""] and F.ROLES[class][1] and F.ROLES[class][1][1]) or "arms")
		lines[#lines + 1] = "  " .. L["Hit, crit, dodge, parry and block per 1%; defense per point of skill; the rest per point."]
		-- (the hit cap: what you have now against it; 0.66.3)
		local h = F.HitNow()
		local function Pct(v) return (("%.1f"):format(v):gsub("%.0$", "")) end
		if h.hit then
			lines[#lines + 1] = "  " .. L["Hit counts up to your cap: %s%% of %s%% now"]:format(Pct(h.hit[1]), Pct(h.hit[2]))
				.. (h.spellhit and (" " .. L["(spells: %s%% of %s%%)"]:format(Pct(h.spellhit[1]), Pct(h.spellhit[2]))) or "")
		elseif h.spellhit then
			lines[#lines + 1] = "  " .. L["Spell hit counts up to your cap: %s%% of %s%% now"]:format(Pct(h.spellhit[1]), Pct(h.spellhit[2]))
		end
		lines[#lines + 1] = L["Your own: .weights set str=2 agi=1 sta=0.5, or .weights pawn and paste a Pawn scale string; .weights custom picks them again, .weights clear forgets them."]
		return lines
	end,
})

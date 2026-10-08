local ns = select(2, ...)

-- Filters typed into the search as key:value words, alongside the words matched by name. Each
-- works on the kinds that have what it looks at; a row it can't judge is left out. Unknown keys or
-- values stay ordinary search words. (".filters" lists them in the game.)
--
--   lvl:20-30 lvl:<30 lvl:40-    quest level, NPC level, the level an item needs
--   ilvl:60+                     item level
--   q:rare  q:rare+              item quality (poor common uncommon rare epic legendary, or 0-5)
--   stat:stamina  stat:sta>=10   an item stat, or what a consumable's effect gives (stamina, strength, agility, intellect, spirit,
--                                armor, attack power, spell power, crit, hit, dodge, mp5, fire...)
--   slot:wrist                   an item's equipment slot
--   type:mail  type:sword        item type or subtype
--   in:bank  in:deadmines        where: bags/bank/mail/guild (stored), a quest's or NPC's zone,
--                                a loot item's dungeon or boss (zone: and from: are the same)
--   on:plamen                    stored on that character (or guild, warband)
--   count:20+                    how many (bags, alts and banks)
--   trainer:mage trainer:class   Questie trainers by what they teach (a class, a profession, pet,
--                                riding; class = your class, mine = mining); is:classtrainer, is:proftrainer
--   faction:horde                Questie NPCs friendly to the Horde (alliance, neutral = both,
--                                friendly = to your own faction)
--   standing:honored+            reputations by standing (names or 1-8; <friendly, 4-6, honored-exalted)
--   sells:linen_cloth            Questie NPCs that sell an item (its name, part of it, or its id)
--   is:done is:todo is:complete  quests: finished / not yet / ready to turn in; achievements: done / todo
--   is:usable is:equippable      items you can use / wear
--   is:upgrade                   gear that suits you now: your level, your class, near what you wear there or better
--   is:quest is:soulbound is:boe items: quest items, bound ones, bind on equip not yet bound
--   is:ready is:passive          spells off cooldown (quests: = is:complete) / passive spells
--   is:capped                    currencies at their cap (or this week's)
--   is:craftable                 recipes you have every reagent for
--   is:skillup                   recipes that still give skill (orange or yellow; also is:orange/yellow/green/grey)
--   is:vendor is:trainer ...     Questie NPCs by what they do

local F = {}
ns.Filters = F

local Lower = ns.Lower

-- an item's info, kept per item id (it doesn't change; filters ask for it on every matching row
-- of every search): a table each time was garbage for thousands of loot rows
local infoCache, infoCount = {}, 0
local function ItemInfo(id)
	local get = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not (get and id) then return nil end
	local c = infoCache[id]
	if c then return c end
	local ok, name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc, _, _, _, _, bindType = pcall(get, id)
	if ok and name then -- (not known to the client yet: asked again next time)
		c = { link = link, quality = quality, ilvl = ilvl, minLevel = minLevel, type = itemType, subType = subType, equipLoc = equipLoc,
			bindType = type(bindType) == "number" and bindType or nil }
		if infoCount > 4000 then infoCache, infoCount = {}, 0 end
		if type(id) == "number" then infoCache[id], infoCount = c, infoCount + 1 end
		return c
	end
end
-- The item a row stands for: its own, or the item a recipe makes (a crafted piece: its stats, slot, item
-- level, quality). Enchants make none. Recipe rows carry makesItem when indexed; older indexes are asked
-- of the game (GetRecipeSchematic's outputItemID), once per recipe.
local recipeItem = {}
local function MadeBy(e)
	local r = e.recipeID
	if not r then return nil end
	if type(e.makesItem) == "number" then return e.makesItem end
	local c = recipeItem[r]
	if c ~= nil then return c or nil end
	local TS = C_TradeSkillUI
	if not (TS and TS.GetRecipeSchematic) then return nil end
	local ok, sch = pcall(TS.GetRecipeSchematic, r, false)
	if not ok or type(sch) ~= "table" then return nil end -- (no answer yet: asked again, not taken for an enchant)
	local id = type(sch.outputItemID) == "number" and sch.outputItemID > 0 and sch.outputItemID or nil
	recipeItem[r] = id or false
	return id
end
local function ItemOf(e) return e.itemID or MadeBy(e) end
F.ItemOf = ItemOf

-- (tests: every cache, so a block doesn't depend on what earlier ones asked for)
F.ClearCache = function()
	infoCache, infoCount = {}, 0
	recipeItem = {}
	if F.ClearStats then F.ClearStats() end
	if F.ClearEffects then F.ClearEffects() end
	if F.ClearPlaces then F.ClearPlaces() end
	if F.ClearSold then F.ClearSold() end
end

--- The quest a row is (not a quest item that merely belongs to one).
local function QuestOf(e)
	local q = rawget(e, "qid") or e.qid
	if q then return q end
	if e.kind == "quests" then return e.questID end
end

local function NpcID(e) return e.kind == "npc" and (rawget(e, "key") or e.npcID) or nil end
local function NpcField(e, field)
	local id = NpcID(e)
	local I = ns.Integrations
	return id and I and I.NpcField and I.NpcField(id, field) or nil
end

--- A number range from "20", "20-30", "20-", "-30", "20+", "<30", "<=30", ">20", ">=20" ("30-20" is 20-30).
local function Range(v)
	local lo, hi
	local a, b = v:match("^(%d*)%-(%d*)$")
	if a then
		lo, hi = tonumber(a), tonumber(b)
		if not lo and not hi then return nil end
		if lo and hi and lo > hi then lo, hi = hi, lo end
	elseif v:match("^%d+%+$") then
		lo = tonumber(v:match("%d+"))
	elseif v:match("^<=?%d+$") then
		hi = tonumber(v:match("%d+")) - (v:find("=", 1, true) and 0 or 1)
	elseif v:match("^>=?%d+$") then
		lo = tonumber(v:match("%d+")) + (v:find("=", 1, true) and 0 or 1)
	elseif v:match("^=?%d+$") then
		lo = tonumber(v:match("%d+")); hi = lo
	else
		return nil
	end
	return function(x) return type(x) == "number" and (not lo or x >= lo) and (not hi or x <= hi) end
end
F.Range = Range

----------------------------------------------------------------------
-- What rows know
----------------------------------------------------------------------

--- Level range of a row: items (the level they need), quests, Questie NPCs, dungeons, zones.
local function Levels(e)
	if e.itemID then
		local info = ItemInfo(e.itemID)
		local l = info and info.minLevel
		if type(l) == "number" then return l, l end
		return nil
	end
	if NpcID(e) then
		local lo, hi = NpcField(e, "minLevel"), NpcField(e, "maxLevel")
		if type(lo) == "number" then return lo, type(hi) == "number" and hi or lo end
		return nil
	end
	local l = e.level
	if type(l) == "number" then
		local lo = e.minLevel -- (dungeons and raids: their range)
		if type(lo) == "number" and lo <= l then return lo, l end
		return l, l
	end
	if e.kind == "maps" and ns.Zones then -- (zones: their level band)
		local z = ns.Zones.Of(e.mapID)
		if z and z.min then return z.min, z.max end
	end
end

local statCache, statCount = {}, 0
local statNames = {} -- stat key (ITEM_MOD_STAMINA_SHORT) -> { its shown name, lowercase (false: none); the key, lowercase }
--- An item's stats (the game's: { ITEM_MOD_STAMINA_SHORT = 7, ... }), or nil until known.
local function Stats(e)
	local id = ItemOf(e)
	if not id then return nil end
	local c = statCache[id]
	if c ~= nil then return c end
	local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	local info = ItemInfo(id)
	local own = e.itemID and type(e.link) == "string" and e.link:find("|H", 1, true) and e.link
	local link = own or (info and info.link) or ("item:" .. id)
	if not (get and info) then return nil end -- (not known to the client yet: asked again next time)
	local ok, t = pcall(get, link)
	t = ok and type(t) == "table" and t or {}
	if statCount > 4000 then statCache, statCount = {}, 0 end
	statCache[id], statCount = t, statCount + 1
	return t
end
F.ClearStats = function() statCache, statCount, statNames = {}, 0, {} end

-- short names for stats -> part of the game's stat key
local STAT_WORDS = {
	str = "STRENGTH", strength = "STRENGTH", agi = "AGILITY", agility = "AGILITY",
	sta = "STAMINA", stam = "STAMINA", stamina = "STAMINA", int = "INTELLECT", intellect = "INTELLECT",
	spi = "SPIRIT", spirit = "SPIRIT", armor = "RESISTANCE0", armour = "RESISTANCE0",
	ap = "ATTACK_POWER", attackpower = "ATTACK_POWER", sp = "SPELL_POWER", spellpower = "SPELL_POWER",
	heal = "HEAL", healing = "HEAL", crit = "CRIT", hit = "HIT", haste = "HASTE", dodge = "DODGE",
	parry = "PARRY", block = "BLOCK", def = "DEFENSE", defense = "DEFENSE", mp5 = "REGEN",
	dps = "DAMAGE_PER_SECOND", holy = "RESISTANCE1", fire = "RESISTANCE2", nature = "RESISTANCE3",
	frost = "RESISTANCE4", shadow = "RESISTANCE5", arcane = "RESISTANCE6",
	-- weapon damage: no item stat has it (StatIs never matches it); sharpening stones, weightstones: their effect text
	weapondamage = "WEAPON_DAMAGE", wdmg = "WEAPON_DAMAGE", weapon_damage = "WEAPON_DAMAGE",
}
F.STATS = { "stamina", "strength", "agility", "intellect", "spirit", "armor", "ap", "sp", "healing",
	"crit", "hit", "haste", "dodge", "parry", "block", "defense", "mp5", "dps", "fire", "frost",
	"nature", "shadow", "arcane", "holy", "weapondamage" }

--- Does this stat key (ITEM_MOD_STAMINA_SHORT) answer to the typed word?
local function StatIs(key, word)
	local part = STAT_WORDS[word]
	if part then return key:find(part, 1, true) ~= nil end
	local n = statNames[key] -- (lowercased once per key, not per stat per row per keystroke)
	if not n then
		local shown = _G[key]
		n = { type(shown) == "string" and Lower(shown) or false, Lower(key) }
		statNames[key] = n
	end
	return (n[1] and n[1]:find(word, 1, true)) or n[2]:find(word, 1, true) and true or false
end

-- Consumables (elixirs, potions, food, scrolls) have no item stats: their effect is the text of their
-- use spell ("Increases Strength by 8 for 1 hour", food's "well fed and gain 6 Stamina and Spirit"),
-- and their tooltip's lines. Read once per item, lowercase; nil while the game is still loading it.
local Secret = ns.Secret
local effectCache, effectCount = {}, 0
local effectRetry = {} -- item id -> when to read it again (its item or spell data was still loading)
local RETRY = 1 -- seconds
--- Adds the text of the item's use spell to parts; true when that text is still loading (asked for).
local function SpellText(id, parts)
	local getSpell = (C_Item and C_Item.GetItemSpell) or _G.GetItemSpell
	local spellID
	if getSpell then
		local ok, _, sid = pcall(getSpell, id)
		if ok and type(sid) == "number" and not Secret(sid) then spellID = sid end
	end
	if spellID and C_Spell and C_Spell.GetSpellDescription then
		local ok, d = pcall(C_Spell.GetSpellDescription, spellID)
		if ok and type(d) == "string" and not Secret(d) and d ~= "" then
			parts[#parts + 1] = d
		elseif not (C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(spellID)) then
			if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
			return true -- (the spell's text is still loading: asked for, read again in a moment)
		end
	end
	return false
end
--- Adds the item's tooltip lines (their left text) to parts.
local function TooltipLines(id, parts)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return end
	local ok, info = pcall(C_TooltipInfo.GetItemByID, id)
	if ok and type(info) == "table" and type(info.lines) == "table" then
		for _, l in ipairs(info.lines) do
			local t = type(l) == "table" and l.leftText
			if type(t) == "string" and not Secret(t) then parts[#parts + 1] = t end
		end
	end
end
local function EffectText(e)
	local id = ItemOf(e)
	if not id then return nil end
	local c = effectCache[id]
	if c ~= nil then return c or nil end
	local now = GetTime()
	if effectRetry[id] and now < effectRetry[id] then F.loading = true return nil end
	-- an item the client hasn't got yet has no spell and a "Retrieving item information" tooltip: never kept
	if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then
		if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		effectRetry[id] = now + RETRY
		F.loading = true -- (the search asks again in a moment: UI:RetryWhenLoaded)
		return nil
	end
	local parts = {}
	local pending = SpellText(id, parts)
	TooltipLines(id, parts)
	local text = #parts > 0 and Lower(table.concat(parts, "\n")) or nil
	if pending then
		effectRetry[id] = now + RETRY -- (not every keystroke: once a second until it's in)
		F.loading = true
	else
		if effectCount > 4000 then effectCache, effectCount = {}, 0 end
		effectCache[id], effectCount = text or false, effectCount + 1
		effectRetry[id] = nil
	end
	return text
end
F.EffectText = EffectText

local CONSUMABLE = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local QUESTITEM = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
local classes, classCount = {}, 0 -- item id -> its item class (asked once per item: filters ask per row, per search)
--- An item's class id (GetItemInfoInstant), or nil when the game can't say yet (not kept then).
local function ClassID(id)
	local c = classes[id]
	if c ~= nil then return c end
	local get = C_Item and C_Item.GetItemInfoInstant
	if not get then return nil end
	local ok, _, _, _, _, _, classID = pcall(get, id)
	if not ok or type(classID) ~= "number" then return nil end
	if classCount > 4000 then classes, classCount = {}, 0 end
	classes[id], classCount = classID, classCount + 1
	return classID
end
-- (not known: taken for one, so its effect is still read)
local function IsConsumable(id) local c = ClassID(id); return c == nil or c == CONSUMABLE end
-- sharpening stones and weightstones are Trade Goods on classic-era item data (Consumable later): both are read
local TRADEGOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local function IsConsumableOrGoods(id) local c = ClassID(id); return c == nil or c == CONSUMABLE or c == TRADEGOODS end

--- Asks the game, ahead of any search, for the text of every consumable in a list (the prewarm calls it for your
--- bags): "stamina food" right after login then finds the food at once instead of after a retry.
function F.WarmEffects(list)
	local n = 0
	for _, e in ipairs(list or {}) do
		local id = ItemOf(e)
		if id and ClassID(id) == CONSUMABLE then EffectText(e); n = n + 1 end
	end
	F.loading = nil -- (no search is waiting on these)
	return n
end
F.ClearEffects = function() effectCache, effectCount, effectRetry, classes, classCount = {}, 0, {}, {}, 0 end

-- how an effect text names each stat when the game's own name isn't there (English)
local EFFECT_ENGLISH = {
	STRENGTH = "strength", AGILITY = "agility", STAMINA = "stamina", INTELLECT = "intellect", SPIRIT = "spirit",
	RESISTANCE0 = "armor", ATTACK_POWER = "attack power", SPELL_POWER = "spell power", HEAL = "healing",
	CRIT = "critical strike", HIT = "hit rating", HASTE = "haste", DODGE = "dodge", PARRY = "parry", BLOCK = "block",
	DEFENSE = "defense", REGEN = "mana every 5", RESISTANCE1 = "holy resistance", RESISTANCE2 = "fire resistance",
	RESISTANCE3 = "nature resistance", RESISTANCE4 = "frost resistance", RESISTANCE5 = "shadow resistance",
	RESISTANCE6 = "arcane resistance",
	-- "Increase sharp weapon damage by 2", "Increase the damage of a blunt weapon by 2"
	WEAPON_DAMAGE = { "weapon damage", "blunt weapon", "sharp weapon", "damage of a weapon", "damage of your weapon" },
}
--- The words an effect text uses for a typed stat: the game's own names first (its language), then English.
local function EffectNames(word)
	local part = STAT_WORDS[word]
	if not part then return { word } end
	local names = {}
	for _, k in ipairs({ "SPELL_STAT_" .. part, "ITEM_MOD_" .. part .. "_SHORT", "ITEM_MOD_" .. part .. "_RATING_SHORT" }) do
		local g = _G[k]
		if type(g) == "string" and g ~= "" and not g:find("%", 1, true) then names[#names + 1] = Lower(g) end
	end
	local stat = ({ STRENGTH = 1, AGILITY = 2, STAMINA = 3, INTELLECT = 4, SPIRIT = 5 })[part]
	local g = stat and _G["SPELL_STAT" .. stat .. "_NAME"]
	if type(g) == "string" and g ~= "" then names[#names + 1] = Lower(g) end
	local en = EFFECT_ENGLISH[part]
	if type(en) == "table" then
		for _, w in ipairs(en) do names[#names + 1] = w end
	elseif en then
		names[#names + 1] = en
	end
	return names
end

--- Does the effect text name the stat (names: EffectNames of it; and, with cmp, give it an amount that passes)?
local function EffectHas(text, names, cmp)
	for _, name in ipairs(names) do
		local from = 1
		while true do
			local at, last = text:find(name, from, true)
			if not at then break end
			if not cmp then return true end
			-- "+6 Stamina", "6 Strength" (right before it), or "Strength by 25" (soon after it)
			local n = tonumber(text:sub(math.max(1, at - 10), at - 1):match("(%d+)%s*$"))
				or tonumber(text:sub(last + 1, last + 24):match("^%D-(%d+)"))
			if n and cmp(n) then return true end
			from = last + 1
		end
	end
	return false
end

-- A recipe's own words, lowercase: its name and its spell's text ("Enchant Bracer - Stamina",
-- "Permanently enchant bracers to increase Stamina by 3."). Kept once the text has loaded.
local recipeText, recipeEarly = {}, {}
local function RecipeText(e)
	local r = e.recipeID
	if not r then return nil end
	local c = recipeText[r]
	if c then return c end
	local early = recipeEarly[r] -- (its text was still loading a moment ago: the name alone, asked again later)
	if early and GetTime() < early[2] then return early[1] end
	local name = type(e.name) == "string" and e.name or ""
	local desc
	if C_Spell and C_Spell.GetSpellDescription then
		local ok, d = pcall(C_Spell.GetSpellDescription, r)
		if ok and type(d) == "string" and d ~= "" and not Secret(d) then
			desc = d
		elseif C_Spell.RequestLoadSpellData then
			pcall(C_Spell.RequestLoadSpellData, r)
		end
	end
	local text = Lower(name .. (desc and ("\n" .. desc) or ""))
	if desc then recipeText[r], recipeEarly[r] = text, nil else recipeEarly[r] = { text, GetTime() + 1 } end
	return text
end

-- slot: the everyday words for slots -> the word the game's slot name has ("Wrist", "Feet"...)
local SLOT_ALIAS = {
	bracer = "wrist", bracers = "wrist", wrists = "wrist", boot = "feet", boots = "feet", foot = "feet",
	glove = "hands", gloves = "hands", gauntlets = "hands", hand = "hands", cloak = "back", cape = "back",
	helm = "head", helmet = "head", hat = "head", pants = "legs", leg = "legs", leggings = "legs",
	belt = "waist", girdle = "waist", ring = "finger", rings = "finger", necklace = "neck", amulet = "neck",
	shoulders = "shoulder", pauldrons = "shoulder", spaulders = "shoulder", robe = "chest",
	["2h"] = "two-hand", twohand = "two-hand", ["two-handed"] = "two-hand", ["1h"] = "one-hand",
	onehand = "one-hand", offhand = "off hand", mainhand = "main hand", trinkets = "trinket",
	weapons = "weapon",
}
-- an item slot type's own letters for a slot word the game's name may not have (Two-Hand: 2hweapon)
local SLOT_LOC = { ["two-hand"] = "2hweapon", ["off hand"] = "offhand", ["main hand"] = "mainhand", ["one-hand"] = "invtype_weapon" }
-- how enchants name the slot they go on
local ENCHANT_WORDS = {
	wrist = { "bracer", "wrist" }, feet = { "boots", "boot", "feet" }, hands = { "gloves", "glove", "hands" },
	back = { "cloak", "back" }, head = { "helm", "head" }, legs = { "leg", "pants" }, chest = { "chest" },
	shoulder = { "shoulder" }, finger = { "ring" }, shield = { "shield" }, waist = { "belt", "waist" },
	weapon = { "weapon" }, ["two-hand"] = { "2h weapon", "two-handed", "two-hand" }, ["off hand"] = { "off-hand", "shield" },
}
local function SlotWant(v) return SLOT_ALIAS[v] or v end
local locWords = {} -- INVTYPE_x -> { its shown name, lowercase; itself, lowercase } (a few dozen, kept)
--- Does this item slot type answer to the slot word? flat: want without spaces or dashes (worked out once).
local function SlotIs(loc, want, flat)
	local w = locWords[loc]
	if not w then
		local shown = _G[loc]
		w = { type(shown) == "string" and Lower(shown) or "", loc:lower() }
		locWords[loc] = w
	end
	if w[1]:find(want, 1, true) or w[2]:find(flat, 1, true) then return true end
	local extra = SLOT_LOC[want]
	return extra and w[2]:find(extra, 1, true) and (want ~= "one-hand" or w[2] == "invtype_weapon") and true or false
end

local QUALITY = { poor = 0, grey = 0, gray = 0, junk = 0, common = 1, white = 1, uncommon = 2, green = 2,
	rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5, artifact = 6, heirloom = 7 }
F.QUALITIES = { "poor", "common", "uncommon", "rare", "epic", "legendary" }

local function QualityOf(e)
	local q = e.quality
	if type(q) == "number" then return q end
	local id = ItemOf(e)
	local info = id and ItemInfo(id)
	return info and info.quality
end

-- equipment slot ids an INVTYPE goes in (is:equippable)
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

F.SLOTS = SLOTS -- (@gear: what counts as equipment)

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
				if okS and type(st) == "table" then values[slot] = F.StatValue(st, w) or 0 end
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

local function Usable(e)
	local id = e.itemID
	if not id then return false end
	local info = ItemInfo(id)
	if info and type(info.minLevel) == "number" and info.minLevel > (UnitLevel("player") or 0) then return false end
	if C_PlayerInfo and C_PlayerInfo.CanUseItem then
		local ok, yes = pcall(C_PlayerInfo.CanUseItem, id)
		if ok then return yes and true or false end
	end
	return true
end

local function Equippable(e)
	local info = e.itemID and ItemInfo(e.itemID)
	return info and SLOTS[info.equipLoc or ""] and true or false
end

local function Count(e)
	local n = e.total or e.count
	return type(n) == "number" and n or nil
end

local function Craftable(e)
	local rg = e.reagents
	if type(rg) ~= "table" or #rg == 0 then return false end
	local count = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not count then return false end
	for _, r in ipairs(rg) do
		local have = count(r[1], true) or 0
		if have < (r[2] or 1) then return false end
	end
	return true
end

-- Recipe difficulty, as the profession window colours it: Enum.TradeskillRelativeDifficulty (Optimal 0 = orange,
-- Medium 1 = yellow, Easy 2 = green, Trivial 3 = grey). Kept with each recipe when its window was last read
-- (Professions.lua: `diff`, refreshed whenever the window's list updates, as it does after a skill-up).
local DIFF = (Enum and Enum.TradeskillRelativeDifficulty) or {}
F.DIFF = {
	orange = DIFF.Optimal or 0, yellow = DIFF.Medium or 1, green = DIFF.Easy or 2, grey = DIFF.Trivial or 3,
}
local function Difficulty(e)
	local d = e.recipeID and e.difficulty
	return type(d) == "number" and d or nil
end
local function DiffIs(which) return function(e) return Difficulty(e) == F.DIFF[which] end end
local function SkillUp(e)
	local d = Difficulty(e)
	return d ~= nil and (d == F.DIFF.orange or d == F.DIFF.yellow)
end
-- is: values only recipes answer: "@profession is:skillup" searches the recipes too
F.RECIPE_IS = { skillup = true, skillups = true, orange = true, yellow = true, green = true, grey = true, gray = true,
	trivial = true, craftable = true }
--- Does this typed word filter by something only recipes have (is:skillup, is:orange|yellow, -is:grey)?
function F.RecipeWord(w)
	for v in Lower(w):gmatch("is:(%a+)") do if F.RECIPE_IS[v] then return true end end
	return false
end

local function Done(q)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) and true or false
end

local function Complete(e)
	if e.kind ~= "quests" or not e.questID then return false end
	local f = C_QuestLog and (C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete)
	return f and f(e.questID) and true or false
end

--- Does the NPC have this role (Questie's npcFlags; its numbers differ between game versions)?
local function NpcRole(e, flagName)
	if not NpcID(e) then return false end
	local flags = NpcField(e, "npcFlags")
	local I = ns.Integrations
	local defs = I and I.NpcFlagDefs and I.NpcFlagDefs()
	local bit = defs and defs[flagName]
	if type(flags) ~= "number" or type(bit) ~= "number" or bit <= 0 then return false end
	return math.floor(flags / bit) % 2 == 1
end

-- An area's name, lowercase, by area id (C_Map.GetAreaInfo per NPC row, per search, was the cost of in:)
local areaNames = {}
local function AreaName(area)
	local name = areaNames[area]
	if name == nil then
		local got = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
		name = type(got) == "string" and Lower(got) or false
		areaNames[area] = name
	end
	return name or nil
end
F.ClearPlaces = function() areaNames = {} end
--- The lowercase copy of a row's text field, kept on the row (like _ltext) while the field's text is the same.
local function LowerField(e, field, lkey, srcKey)
	local s = e[field]
	if type(s) ~= "string" then return nil end
	if rawget(e, srcKey) ~= s then e[srcKey], e[lkey] = s, Lower(s) end
	return rawget(e, lkey)
end
--- Where a row is, as text to match: a zone, an NPC's zone, a stored item's places, or the
--- row's own detail ("Edwin VanCleef  The Deadmines", "x5  Backpack", "[12] Elwynn Forest").
local function Places(e, v)
	local zone = LowerField(e, "zone", "_lzone", "_lzoneOf")
	if zone and zone:find(v, 1, true) then return true end
	if NpcID(e) then
		local area = NpcField(e, "zoneID")
		local name = type(area) == "number" and area > 0 and AreaName(area)
		return name and name:find(v, 1, true) and true or false
	end
	if type(e.holders) == "table" then
		for _, h in pairs(e.holders) do
			if (h.count or 1) > 0 and type(h.where) == "string" and h.where:find(v, 1, true) then return true end
		end
		return false
	end
	if e.slotId and ("equipped"):find(v, 1, true) then return true end
	local d = LowerField(e, "detail", "_ldetail", "_ldetailOf")
	return d and d:find(v, 1, true) and true or false
end

local function Holder(e, v)
	if type(e.holders) ~= "table" then return false end
	for _, h in pairs(e.holders) do
		if (h.count or 1) > 0 then
			if (v == "me" or v == "you") and h.mine then return true end
			if type(h.who) == "string" and Lower(h.who):find(v, 1, true) then return true end
		end
	end
	return false
end

-- Binding. Item rows know whether the stacks in your bags (or the worn piece) are bound: bound = some stack is,
-- unbound = some stack isn't (Items.lua; rows are one per item, so a bound and a tradable copy answer both).
-- Rows with no stacks of yours (loot, recipes, stored) only have the item's bind type.
local BIND_EQUIP = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
local BIND_QUEST = Enum and Enum.ItemBind and Enum.ItemBind.Quest or 4

local function Soulbound(e) return e.itemID ~= nil and e.bound == true end

--- Bind on equip and not bound yet: one of your stacks still free, or (no stacks of yours) the item binds on equip.
local function BoE(e)
	local id = ItemOf(e)
	local info = id and ItemInfo(id)
	if not (info and info.bindType == BIND_EQUIP) then return false end
	if e.bound ~= nil or e.unbound ~= nil then return e.unbound == true end
	return true
end

--- A quest item: tied to a quest (Items.lua: questID, questItem), or quest-class, or it binds as a quest item.
local function QuestItem(e)
	local id = ItemOf(e)
	if not id then return false end
	if e.itemID and (e.questItem or e.questID) then return true end
	if ClassID(id) == QUESTITEM then return true end
	local info = ItemInfo(id)
	return info ~= nil and info.bindType == BIND_QUEST
end

-- A spell off cooldown now (not cached: it changes). The global cooldown doesn't count; passives are never
-- ready; a cooldown the game keeps secret (in combat) can't be judged.
local GCD = 1.5
local function SpellReady(e)
	if e.kind ~= "spells" or e.passive or type(e.spellID) ~= "number" then return false end
	local start, duration, enabled
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, cd = pcall(C_Spell.GetSpellCooldown, e.spellID)
		if not ok or type(cd) ~= "table" then return false end
		start, duration, enabled = cd.startTime, cd.duration, cd.isEnabled
	elseif _G.GetSpellCooldown then
		local ok, s, d, en = pcall(_G.GetSpellCooldown, e.spellID)
		if not ok then return false end
		start, duration, enabled = s, d, en
	else
		return false
	end
	if Secret(start) or Secret(duration) or Secret(enabled) then return false end
	if enabled == false or enabled == 0 then return false end -- (waits for something to end first: not ready)
	if type(duration) ~= "number" or type(start) ~= "number" then return false end
	if duration <= GCD or start <= 0 then return true end
	return start + duration <= GetTime()
end

--- is:ready: a spell off cooldown, or a quest ready to turn in.
local function Ready(e)
	if e.kind == "spells" then return SpellReady(e) end
	return Complete(e)
end

-- Currencies (rows: quantity, maxQuantity; maxWeeklyQuantity, quantityEarnedThisWeek): at the cap, or this week's.
local Number = ns.Num
local function Capped(e)
	if e.kind ~= "currency" then return false end
	local n, max = Number(e.quantity), Number(e.maxQuantity)
	if n and max and max > 0 and n >= max then return true end
	local week, wmax = Number(e.quantityEarnedThisWeek), Number(e.maxWeeklyQuantity)
	return week ~= nil and wmax ~= nil and wmax > 0 and week >= wmax
end

--- Done / not done: quests by the game's record; achievements by their row's completed (rows without it aren't judged).
local function DoneOf(e)
	local q = QuestOf(e)
	if q then return Done(q) end
	if e.kind == "achievements" and type(e.completed) == "boolean" then return e.completed end
	return nil
end

-- Reputation standings 1-8 (Hated .. Exalted): the game's names (both genders' where they differ), and English
-- always. Rows carry reaction (Reputation.lua); friendship and renown factions have none and are left out.
local STANDING_ENGLISH = { "hated", "hostile", "unfriendly", "neutral", "friendly", "honored", "revered", "exalted" }
local standingWords -- lowercase name -> 1-8 (made on first use: the game's globals are all in by then)
local function StandingWords()
	if standingWords then return standingWords end
	standingWords = {}
	for i, w in ipairs(STANDING_ENGLISH) do standingWords[w] = i end
	for i = 1, 8 do
		for _, g in ipairs({ _G["FACTION_STANDING_LABEL" .. i], _G["FACTION_STANDING_LABEL" .. i .. "_FEMALE"] }) do
			if type(g) == "string" and g ~= "" then standingWords[Lower(g)] = i end
		end
	end
	return standingWords
end
--- The standing names for Tab: the game's own (lowercase), else English.
local function StandingNames()
	local out = {}
	for i = 1, 8 do
		local g = _G["FACTION_STANDING_LABEL" .. i]
		out[i] = type(g) == "string" and g ~= "" and Lower(g):gsub(" ", "_") or STANDING_ENGLISH[i]
	end
	return out
end
--- A standing value as a range: names stand for their numbers (honored+ = 6+, <friendly = <5, honored-exalted = 6-8).
local function StandingRange(v)
	local words = StandingWords()
	local bad = false
	local text = v:gsub("[^%d%-%+<>=]+", function(w)
		local n = words[(w:gsub("^%s+", ""):gsub("%s+$", ""))]
		if not n then bad = true return w end
		return tostring(n)
	end)
	if bad then return nil end
	return Range(text)
end

-- sells: the Questie NPCs selling an item. Questie keeps vendors per item (its item field "vendors": NPC ids).
-- The value is an item name (or id): items you carry are matched by name first (no scan); else Questie's item
-- names, read once per session into one lowercase text (one cold read per item, ~15k on WoW Forever: tens of
-- ms the first time sells: is used, timed in .debug log). An exact name wins; else every item whose name holds
-- the words (sells:copper: Copper Rod, Copper Bar...), at most MAX_SOLD items. Unknown item: no NPC passes.
local MAX_SOLD = 200
local itemNames -- "\n<lowercase name>\t<id>" per Questie item
local soldBy, soldCount = {}, 0 -- value -> { [npc id] = true }

-- Questie's data: the QuestieDB addon alone, or through Questie (QuestieData.lua)
local function QuestieDB()
	local DB = ns.QuestieData and ns.QuestieData.DB()
	return DB and DB.QueryItemSingle and DB or nil
end

local function ItemNames(DB)
	if itemNames then return itemNames end
	local started = _G.debugprofilestop and _G.debugprofilestop()
	local parts, n = {}, 0
	local function add(id)
		local ok, name = pcall(DB.QueryItemSingle, id, "name")
		if ok and type(name) == "string" and name ~= "" then
			n = n + 1
			parts[n] = "\n" .. Lower(name) .. "\t" .. id
		end
	end
	local ids = DB.ItemIds and DB.ItemIds() or {}
	for i = 1, #ids do add(ids[i]) end
	itemNames = table.concat(parts) .. "\n"
	ns:Trace(("filters: %d Questie item names read for sells:%s"):format(n,
		started and (" in %.0f ms"):format(_G.debugprofilestop() - started) or ""))
	return itemNames
end
F.ClearSold = function() itemNames, soldBy, soldCount, standingWords = nil, {}, 0, nil end

--- The item ids a sells: value names.
local function SoldItems(v, DB)
	local id = tonumber(v)
	if id then return { id } end
	local ids = {}
	-- your own items by name: no scan
	local items = ns.providers and ns.providers.items
	for _, e in ipairs(items and items._entries or {}) do
		if e.itemID and type(e.name) == "string" and Lower(e.name) == v then ids[#ids + 1] = e.itemID end
	end
	if #ids > 0 then return ids end
	local text = ItemNames(DB)
	for found in text:gmatch("\n" .. v:gsub("%p", "%%%0") .. "\t(%d+)") do ids[#ids + 1] = tonumber(found) end
	if #ids > 0 then return ids end
	local from = 1
	while #ids < MAX_SOLD do
		local at = text:find(v, from, true)
		if not at then break end
		local lineEnd = text:find("\n", at, true) or #text
		local tab = text:find("\t", at, true)
		if tab and tab < lineEnd then ids[#ids + 1] = tonumber(text:sub(tab + 1, lineEnd - 1)) end
		from = lineEnd
	end
	return ids
end

--- Questie's items with exactly this (lowercase) name: their ids ({} when none, or without Questie). (Pipes.lua: a
--- chain started from an item you don't carry, "where to get copper ore".)
function F.QuestieItemIds(lname)
	local DB = QuestieDB()
	if not DB or type(lname) ~= "string" or lname == "" then return {} end
	local ids = {}
	for found in ItemNames(DB):gmatch("\n" .. lname:gsub("%p", "%%%0") .. "\t(%d+)") do ids[#ids + 1] = tonumber(found) end
	return ids
end

--- The NPC ids selling what the value names, or nil while Questie isn't there (asked again then).
local function Sellers(v)
	local c = soldBy[v]
	if c then return c end
	local DB = QuestieDB()
	if not DB then return nil end
	c = {}
	for _, id in ipairs(SoldItems(v, DB)) do
		local ok, vendors = pcall(DB.QueryItemSingle, id, "vendors")
		if ok and type(vendors) == "table" then
			for _, npc in pairs(vendors) do c[npc] = true end
		end
	end
	if soldCount > 50 then soldBy, soldCount = {}, 0 end
	soldBy[v], soldCount = c, soldCount + 1
	return c
end

----------------------------------------------------------------------
-- Keys: key -> function(value) giving a test, or nil when the value isn't one this key takes
----------------------------------------------------------------------

local KEYS = {}

KEYS.lvl = function(v)
	local r = Range(v)
	return r and function(e)
		local lo, hi = Levels(e)
		if not lo then return false end
		if lo == hi then return r(lo) end
		for l = lo, hi do if r(l) then return true end end -- (an NPC of levels 10-12)
		return false
	end
end
KEYS.level = KEYS.lvl

KEYS.ilvl = function(v)
	local r = Range(v)
	return r and function(e)
		local id = ItemOf(e)
		local info = id and ItemInfo(id)
		return info and r(info.ilvl) or false
	end
end
KEYS.itemlevel = KEYS.ilvl

KEYS.q = function(v)
	local atLeast = v:sub(-1) == "+"
	local word = atLeast and v:sub(1, -2) or v
	local want = QUALITY[word] or tonumber(word)
	if not want then
		for i = 0, 7 do
			local g = _G["ITEM_QUALITY" .. i .. "_DESC"]
			if type(g) == "string" and Lower(g) == word then want = i break end
		end
	end
	if not want then return nil end
	return function(e)
		local q = QualityOf(e)
		if type(q) ~= "number" then return false end
		return atLeast and q >= want or q == want
	end
end
KEYS.quality = KEYS.q

KEYS.stat = function(v)
	local word, op, n = v:match("^([%a_][%w_]*)([<>=]+)(%d+)$") -- (mp5 has a digit)
	if not word then word = v:match("^([%a_][%w_]*)$") end
	if not word then return nil end
	local cmp = op and Range(op .. n)
	if op and not cmp then return nil end
	local names -- (how effect texts name it: worked out once, when first needed)
	return function(e)
		local stats = Stats(e)
		if stats and next(stats) then
			for key, value in pairs(stats) do
				if type(key) == "string" and StatIs(key, word) and (not cmp or cmp(value)) then return true end
			end
			return false
		end
		local id = ItemOf(e)
		-- an enchant (a recipe making no item): what its name and text say it gives
		if not id then
			local text = e.recipeID and RecipeText(e)
			if not text then return false end
			names = names or EffectNames(word)
			return EffectHas(text, names, cmp)
		end
		-- no item stats (an elixir, a potion, food...): what its effect says it gives. Only consumables are
		-- read (a tooltip per item: thousands of loot rows mustn't each be read)
		if not (IsConsumable(id) or (STAT_WORDS[word] == "WEAPON_DAMAGE" and IsConsumableOrGoods(id))) then return false end
		local text = EffectText(e)
		if not text then return false end
		names = names or EffectNames(word)
		return EffectHas(text, names, cmp)
	end
end
KEYS.stats = KEYS.stat

KEYS.slot = function(v)
	if v == "" then return nil end
	local want = SlotWant(v)
	local flat = want:gsub("[%s%-]", "")
	local words = ENCHANT_WORDS[want] or { want }
	return function(e)
		local id = ItemOf(e)
		if not id then
			-- an enchant: the slot its name or text names ("Enchant Bracer", "enchant boots")
			local text = e.recipeID and RecipeText(e)
			if not text then return false end
			for _, w in ipairs(words) do
				if text:find(w, 1, true) then return true end
			end
			return false
		end
		local info = ItemInfo(id)
		local loc = info and info.equipLoc
		if type(loc) ~= "string" or loc == "" then return false end
		return SlotIs(loc, want, flat)
	end
end

KEYS.type = function(v)
	if v == "" then return nil end
	return function(e)
		local id = ItemOf(e)
		local info = id and ItemInfo(id)
		if not info then return false end
		-- (lowercased once per item, kept in its info: not per row per keystroke)
		local lt, lst = info.ltype, info.lsubType
		if lt == nil then
			local t, st = info.type, info.subType
			lt, lst = type(t) == "string" and Lower(t) or false, type(st) == "string" and Lower(st) or false
			info.ltype, info.lsubType = lt, lst
		end
		if lt and lt:find(v, 1, true) then return true end
		return lst and lst:find(v, 1, true) or false
	end
end

local placing -- (building a place's filter: in:<place> inside it is the plain one)
KEYS["in"] = function(v)
	if v == "" then return nil end
	-- a place Terminal knows by name (a zone, or a town in one: in:goldshire, in:ratchet, in:org): its NPCs by where
	-- they stand, as Simple mode's "vendor goldshire" (an NPC's zone alone says Elwynn Forest, never Goldshire)
	local I = ns.Integrations
	if I and I.FindPlace and I.PlaceFilter and not placing then -- (PlaceFilter parses in:<place> itself: no loop)
		local words = {}
		for w in v:gmatch("%S+") do words[#words + 1] = w end
		local place, rest = I.FindPlace(words)
		if place and rest and #rest == 0 then
			placing = true
			local ok, inPlace = pcall(I.PlaceFilter, place)
			placing = false
			if not ok then return function(e) return Places(e, v) end end
			-- (other rows: the place filter already ends in this same Places test, by the place's own name;
			-- NPCs: their zone by name too, as before)
			return function(e) return inPlace(e) or (NpcID(e) ~= nil and Places(e, v)) end
		end
	end
	return function(e) return Places(e, v) end
end
KEYS.zone, KEYS.from, KEYS.where = KEYS["in"], KEYS["in"], KEYS["in"]

KEYS.on = function(v)
	if v == "" then return nil end
	return function(e) return Holder(e, v) end
end
KEYS.who = KEYS.on

-- Trainers, by what they teach: Questie's subtitle for the NPC ("Warrior Trainer", "Journeyman
-- Blacksmith", "Herbalism Trainer", "Pet Trainer"). Profession names map to the part every rank's
-- title shares (blacksmithing -> "blacksmith": Journeyman/Expert/Artisan Blacksmith). English
-- titles, as Questie's database has them.
local CLASSES = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid",
	"death knight", "monk", "demon hunter", "evoker" }
-- each profession: the words its trainers' titles use (Journeyman Blacksmith, Herbalist, Miner, Fisherman, Physician...)
local PROFS = {
	blacksmithing = { "blacksmith", "armor crafter", "weapon crafter" }, leatherworking = { "leatherwork", "leathercraft" },
	tailoring = { "tailor" }, alchemy = { "alchemist", "alchemy" }, engineering = { "engineer" }, enchanting = { "enchant" },
	jewelcrafting = { "jewelcraft" }, inscription = { "scribe", "inscription" }, herbalism = { "herbalis" },
	mining = { "mining", "miner" }, mine = { "mining", "miner" }, skinning = { "skinning", "skinner" }, cooking = { "cook", "butcher" },
	fishing = { "fishing", "fisherman" }, firstaid = { "first aid", "physician", "trauma surgeon" },
	cartography = { "cartograph" },
}
PROFS["first aid"] = PROFS.firstaid

-- a trainer's title, lowercase ("warrior trainer", "journeyman blacksmith", "fisherman"), or nil for any other row:
-- the title says trainer, or Questie's flags do (Herbalist, Miner, Physician have no "trainer" in theirs)
local function TrainerTitle(e)
	if not NpcID(e) then return nil end
	local sub = rawget(e, "sub") or NpcField(e, "subName")
	if type(sub) ~= "string" or sub == "" then return nil end
	sub = Lower(sub)
	if sub:find("trainer", 1, true) or sub:find("instructor", 1, true) or NpcRole(e, "TRAINER") then return sub end
end

-- PvP NPCs (0.43.5): "nearby battlemaster" listed anything with "battle" in it, of either faction
local function NpcTitle(e)
	if not NpcID(e) then return nil end
	local sub = rawget(e, "sub") or NpcField(e, "subName")
	return type(sub) == "string" and sub ~= "" and Lower(sub) or nil
end
local function Battlemaster(e)
	if NpcRole(e, "BATTLEMASTER") then return true end
	local t = NpcTitle(e)
	return t ~= nil and t:find("battlemaster", 1, true) ~= nil
end
-- honor (rank) vendors and the battlegrounds' reputation vendors, by their titles (English: Questie's subName)
F.PVP_VENDOR_TITLES = { "armor quartermaster", "weapons quartermaster", "accessories quartermaster",
	"mount quartermaster", "supply officer", "stormpike quartermaster", "frostwolf quartermaster" }
local function PvpVendor(e)
	local t = NpcTitle(e)
	if not t then return false end
	for _, w in ipairs(F.PVP_VENDOR_TITLES) do if t:find(w, 1, true) then return true end end
	return false
end
F.Battlemaster, F.PvpVendor = Battlemaster, PvpVendor

local function ClassOf(sub)
	for _, c in ipairs(CLASSES) do
		-- "Warrior Trainer", "Undead Mage Trainer", "Master Mage", "Grand Master Rogue", "High Priest" (whole words)
		if sub:find("%f[%a]" .. c .. "%f[%A]") then return c end
	end
end

local function ProfOf(sub)
	for name, words in pairs(PROFS) do
		for _, w in ipairs(words) do
			if sub:find(w, 1, true) then return name end
		end
	end
end

--- Your class as the trainers' titles write it ("warrior", "death knight"), from the game's class token.
local function MyClass()
	local token = UnitClass and select(2, UnitClass("player")) -- (WARRIOR: the same in every language)
	if type(token) ~= "string" then return nil end
	return (token:lower():gsub("deathknight", "death knight"):gsub("demonhunter", "demon hunter"))
end

--- A profession by its name or the start of it (blacksm -> blacksmithing), or nil.
local function ProfNamed(v)
	if PROFS[v] then return v end
	if #v < 4 then return nil end
	for name in pairs(PROFS) do
		if name:sub(1, #v) == v then return name end
	end
end

local function AnyClassTrainer(e) local sub = TrainerTitle(e); return sub and ClassOf(sub) ~= nil or false end
local function AnyProfTrainer(e) local sub = TrainerTitle(e); return sub and ProfOf(sub) ~= nil or false end

local CLASS_SET = {}
for _, c in ipairs(CLASSES) do CLASS_SET[c] = true end

KEYS.trainer = function(v)
	if v == "" then return nil end
	-- your class's trainers: trainer:class (you mean the one you can learn from); trainer:mine is mining
	if v == "class" or v == "my" or v == "me" or v == "myclass" then
		local ok, cls = pcall(MyClass) -- (once per filter; not known yet: asked per row, as before)
		local myClass = ok and cls or nil
		return function(e)
			local sub = TrainerTitle(e)
			local mine = sub and (myClass or MyClass())
			return mine and ClassOf(sub) == mine or false
		end
	elseif v == "classes" or v == "anyclass" then
		return AnyClassTrainer
	elseif v == "profession" or v == "professions" or v == "prof" then
		return AnyProfTrainer
	end
	if CLASS_SET[v] then
		return function(e) local sub = TrainerTitle(e); return sub and ClassOf(sub) == v or false end
	end
	local prof = ProfNamed(v)
	if prof then
		local words = PROFS[prof]
		return function(e)
			local sub = TrainerTitle(e)
			if not sub then return false end
			for _, w in ipairs(words) do if sub:find(w, 1, true) then return true end end
			return false
		end
	end
	-- anything else: a word of the title (pet, riding, weapon, portal, demon...)
	return function(e)
		local sub = TrainerTitle(e)
		return sub and sub:find(v, 1, true) and true or false
	end
end

-- faction: who a Questie NPC is friendly to ("A", "H" or "AH"; most monsters have nothing)
local FACTION = { horde = { H = true, AH = true }, h = { H = true, AH = true },
	alliance = { A = true, AH = true }, a = { A = true, AH = true },
	neutral = { AH = true }, both = { AH = true } }
KEYS.faction = function(v)
	local want = FACTION[v]
	local mine = v == "friendly" or v == "mine" or v == "me"
	if not (want or mine) then return nil end
	return function(e)
		if not NpcID(e) then return false end
		local f = NpcField(e, "friendlyToFaction")
		if type(f) ~= "string" then return false end
		local w = want
		if mine then
			local g = UnitFactionGroup and UnitFactionGroup("player")
			w = FACTION[g == "Horde" and "horde" or g == "Alliance" and "alliance" or "neutral"]
		end
		return w[f] or false
	end
end

-- near: Questie NPCs within that many yards of you (near:500, near:<300, near:200-800); where you are is asked once
-- per search (the parse), each NPC's nearest spawn on your continent (Integrations.NpcDistance)
KEYS.near = function(v)
	local r = v:match("^%d+$") and Range("<=" .. v) or Range(v)
	if not r then return nil end
	local I = ns.Integrations
	local here
	return function(e)
		if not (I and I.RowDistance) or not (NpcID(e) or e.wcont) then return false end
		if here == nil then here = I.Here and I.Here() or false end
		local d = here and I.RowDistance(e, here) -- (Questie's NPCs, and @mailbox rows)
		return d and r(d) or false
	end
end
KEYS.within, KEYS.dist = KEYS.near, KEYS.near

-- sort:nearest: not a filter (every row stays); SearchText reads it and puts Questie NPCs closest first, with how far
F.SORTS = { nearest = "nearest", near = "nearest", closest = "nearest", distance = "nearest", dist = "nearest" }
KEYS.sort = function(v)
	if not F.SORTS[v] then return nil end
	return function() return true end
end
--- "sort:nearest" -> "nearest", else nil.
function F.SortOf(word)
	if type(word) ~= "string" then return nil end
	local k, v = word:match("^(%a+):(%a+)$")
	if k and Lower(k) == "sort" then return F.SORTS[Lower(v)] end
end

KEYS.count = function(v)
	local r = Range(v)
	return r and function(e) return r(Count(e)) end
end
KEYS.qty = KEYS.count

KEYS.standing = function(v)
	local r = StandingRange(v)
	return r and function(e) return e.kind == "reputation" and r(e.reaction) or false end
end
KEYS.rep = KEYS.standing

KEYS.sells = function(v)
	if v == "" then return nil end
	local set -- (looked up on the first NPC row, then kept for the search: up to 20k rows ask)
	return function(e)
		local id = NpcID(e)
		if not id then return false end
		set = set or Sellers(v)
		return set ~= nil and set[id] == true
	end
end
KEYS.sold = KEYS.sells

local IS = {
	done = function(e) return DoneOf(e) == true end,
	todo = function(e) return DoneOf(e) == false end,
	complete = Complete,
	ready = Ready,
	quest = QuestItem,
	soulbound = Soulbound,
	boe = BoE,
	passive = function(e) return e.kind == "spells" and e.passive == true end,
	capped = Capped,
	usable = Usable,
	equippable = Equippable,
	craftable = Craftable,
	skillup = SkillUp, orange = DiffIs("orange"), yellow = DiffIs("yellow"), green = DiffIs("green"), grey = DiffIs("grey"),
	-- guild members and friends (Social.lua)
	online = function(e) return e.online == true end,
	offline = function(e) return e.online == false end,
	classtrainer = AnyClassTrainer,
	proftrainer = AnyProfTrainer,
	battlemaster = Battlemaster,
	pvpvendor = PvpVendor,
	pvp = function(e) return Battlemaster(e) or PvpVendor(e) end,
}
local ROLES = { vendor = "VENDOR", trainer = "TRAINER", flightmaster = "FLIGHT_MASTER", flight = "FLIGHT_MASTER",
	innkeeper = "INNKEEPER", inn = "INNKEEPER", banker = "BANKER", bank = "BANKER", repair = "REPAIR",
	auctioneer = "AUCTIONEER", questgiver = "QUEST_GIVER", stablemaster = "STABLEMASTER" }
for word, flag in pairs(ROLES) do IS[word] = function(e) return NpcRole(e, flag) end end
IS.notdone, IS.undone, IS.use, IS.wearable = IS.todo, IS.todo, IS.usable, IS.equippable
IS.bound, IS.questitem, IS.maxed, IS.offcooldown = IS.soulbound, IS.quest, IS.capped, IS.ready
IS.professiontrainer = IS.proftrainer
IS.battlemasters, IS.honorvendor, IS.pvpvendors = IS.battlemaster, IS.pvpvendor, IS.pvpvendor
IS.skillups, IS.gray, IS.trivial = IS.skillup, IS.grey, IS.grey
KEYS.is = function(v)
	-- (worn item levels are read once per filter: a new one per search)
	if v == "upgrade" or v == "upgrades" then return F.GearFit() end
	return IS[v]
end

-- the values Tab offers after "key:" (the main spellings only)
F.VALUES = {
	is = { "done", "todo", "complete", "ready", "usable", "equippable", "upgrade", "online", "offline", "quest", "soulbound", "boe", "craftable", "skillup",
		"orange", "yellow", "green", "grey", "passive",
		"capped", "vendor", "trainer", "classtrainer", "proftrainer", "flightmaster", "innkeeper", "banker", "repair",
		"auctioneer", "questgiver", "stablemaster", "battlemaster", "pvpvendor", "pvp" },
	standing = StandingNames(),
	q = F.QUALITIES, quality = F.QUALITIES,
	stat = F.STATS, stats = F.STATS,
	["in"] = { "bags", "bank", "mail", "guild", "warband", "equipped" },
	faction = { "horde", "alliance", "neutral", "friendly" },
	sort = { "nearest" },
	near = { "100", "300", "500", "1000" },
	trainer = { "class", "classes", "profession", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage",
		"warlock", "druid", "blacksmithing", "leatherworking", "tailoring", "alchemy", "engineering", "enchanting",
		"herbalism", "mining", "skinning", "cooking", "fishing", "firstaid", "pet", "riding" },
}

-- the keys, in the order .filters lists them, with an example each
F.HELP = {
	{ "lvl:20-30", "quest/NPC level, or the level an item needs (also lvl:<30, lvl:40-, lvl:20+)" },
	{ "ilvl:60+", "item level" },
	{ "q:rare+", "item quality: poor common uncommon rare epic legendary" },
	{ "stat:stamina", "an item stat, or what a consumable gives (elixirs, potions, food); with a number: stat:sta>=10 (str agi sta int spi armor ap sp crit hit mp5 fire...)" },
	{ "slot:wrist", "item slot, or what a recipe makes or enchants (bracers boots gloves cloak helm ring 2h...)" },
	{ "type:mail", "item type or subtype (cloth, sword, potion...)" },
	{ "in:bank", "where: bags/bank/mail/guild, a quest's or NPC's zone, a loot item's dungeon or boss" },
	{ "on:name", "@stored: on that character (or guild, warband)" },
	{ "count:20+", "how many you have" },
	{ "trainer:mage", "@npc trainers by what they teach: a class, a profession (trainer:mining finds Miners too), class (your class), classes (any), profession, pet, riding, weapon" },
	{ "faction:horde", "@npc: friendly to the Horde / alliance / neutral (both) / friendly (to you)" },
	{ "standing:honored+", "reputation standing: hated hostile unfriendly neutral friendly honored revered exalted (also standing:<friendly, standing:4-6)" },
	{ "near:500", "@npc: within that many yards of you (near:<300, near:200-800)" },
	{ "sort:nearest", "Questie NPCs closest to you first, with how far (the other rows stay, after them)" },
	{ "sells:linen_cloth", "@npc: Questie vendors selling an item (its name, part of it, or its id; nothing for an unknown item)" },
	{ "is:todo", "quests: done todo complete (ready = complete); achievements: done todo; items: usable equippable quest soulbound boe; recipes: craftable skillup (orange or yellow) orange yellow green grey" },
	{ "is:ready", "spells: ready (off cooldown) passive; currencies: capped; NPCs: vendor trainer classtrainer proftrainer flightmaster innkeeper banker repair..." },
	{ "in:elwynn_forest", "a value of several words: _ for the space (in:elwynn_forest, type:one-handed_swords)" },
	{ "-is:soulbound", "not that: - or ! before a filter or a word (-is:boe, !q:poor, -cloth)" },
	{ "q:rare|epic", "any of them: | between values, filters or words (slot:head|chest, is:boe|q:epic, sword|axe)" },
	{ "q:rare&type:sword|q:epic&type:axe", "& joins what must all hold inside a | list (each piece can have its own -)" },
}

--- Is this a filter key (lvl, stat, is...)? For the prompt's colours.
function F.IsKey(key) return KEYS[Lower(key or "")] ~= nil end

-- the keys whose value is matched as text: a _ in it stands for a space (the search splits on spaces,
-- so "in:elwynn forest" can't reach us whole; stat words keep their _: attack_power is the game's key)
local SPACED = { ["in"] = true, zone = true, from = true, where = true, on = true, who = true, type = true,
	trainer = true, slot = true, sells = true, sold = true, standing = true, rep = true }

local traced -- a failing filter has been traced for this search (the parse of a search's words starts the next)

--- A filter for one typed word, or nil when it isn't one (then it's searched as text).
local function ParseOne(word)
	local key, value = word:match("^(%a+):(.+)$")
	if not key then return nil end
	key = Lower(key)
	local make = KEYS[key]
	if not make then return nil end
	value = Lower(value)
	if SPACED[key] then value = value:gsub("_", " ") end
	return make(value) or nil
end

--- Does the row have this (lowercase) text in its name or its searchable text? (-word, a|b words)
local function RowHas(e, lw)
	local ln = rawget(e, "_lname")
	if not ln then
		local n = e.name
		ln = type(n) == "string" and Lower(n) or ""
	end
	if ln:find(lw, 1, true) then return true end
	local lt = rawget(e, "_ltext")
	if not lt then
		local t = rawget(e, "text")
		lt = type(t) == "string" and Lower(t) or nil
	end
	return lt and lt:find(lw, 1, true) and true or false
end
F.RowHas = RowHas

--- A word's filter, or nil when it's a plain search word. key:value ("q:rare"), and ways to combine:
---   -key:value / !key:value / -word   not that ("-is:soulbound", "-cloth", "!q:poor")
---   key:a|b, key:a|key2:b, word|word  any of them ("q:rare|epic", "slot:head|chest", "sword|axe", "is:boe|q:epic")
---   a&b inside a | list               all of them ("q:rare&type:sword|q:epic&type:axe"; Simple's "rare sword or
---                                     epic axe" is made into rare&sword|epic&axe)
--- Each piece can carry its own - ("sword|-boe"). A bare piece takes the word's first key when that makes a filter
--- ("q:rare|epic" = q:rare or q:epic); else it's a plain word, which matches rows with it in their name or text, or,
--- with `plain`, what plain(word) gives (Simple mode's everyday words: "-junk" = not grey). A plain word alone
--- (no -, | or &) stays a search word: nil. A bad keyed piece makes the whole word a search word.
local function Piece(atom, key, plain)
	local neg = false
	if atom:find("^[-!]%a") then neg, atom = true, atom:sub(2) end
	local f
	if atom:find("^%a+:") then
		f = ParseOne(atom)
		if not f then return nil end
	else
		f = key and ParseOne(key .. ":" .. atom)
		if not f then -- (a plain word: "is:boe|cloak")
			local lw = Lower(atom)
			f = plain and plain(lw) or function(e) return RowHas(e, lw) end
		end
	end
	if neg then
		local g = f
		return function(e) return not g(e) end
	end
	return f
end

local function All(list)
	if #list == 1 then return list[1] end
	return function(e)
		for i = 1, #list do if not list[i](e) then return false end end
		return true
	end
end

local function Any(list)
	if #list == 1 then return list[1] end
	return function(e)
		for i = 1, #list do if list[i](e) then return true end end
		return false
	end
end

function F.Parse(word, plain)
	traced = false
	if type(word) ~= "string" or word == "" then return nil end
	local neg = false
	if word:find("^[-!]%a") then neg, word = true, word:sub(2) end
	local f
	if word:find("[|&]") then
		local key = word:match("^(%a+):")
		local ors = {}
		for part in (word .. "|"):gmatch("([^|]*)|") do
			local ands = {}
			for atom in (part .. "&"):gmatch("([^&]*)&") do
				if atom ~= "" then
					local pf = Piece(atom, key, plain)
					if not pf then return nil end -- (still being typed, or not a filter: a search word)
					ands[#ands + 1] = pf
				end
			end
			if #ands > 0 then ors[#ors + 1] = All(ands) end
		end
		if #ors == 0 then return nil end
		f = Any(ors)
	else
		f = ParseOne(word)
		if not f and neg and not word:find(":", 1, true) then f = Piece(word, nil, plain) end
	end
	if not f then return nil end
	if neg then
		local g = f
		return function(e) return not g(e) end
	end
	return f
end

--- Every filter passes this row. A filter that errors leaves the row out, and says so once per search
--- in .debug log (rows silently dropped looked like "the filter finds nothing").
function F.Pass(e, filters)
	for i = 1, #filters do
		local ok, yes = pcall(filters[i], e)
		if not ok then
			if not traced then
				traced = true
				ns:Trace("filter error: " .. tostring(yes) .. " (row " .. tostring(rawget(e, "name") or e.name) .. ")")
			end
			return false
		end
		if not yes then return false end
	end
	return true
end

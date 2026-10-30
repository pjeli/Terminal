local ns = select(2, ...)

-- Item data for the filters: item info and stats (cached per item), what consumables' and enchants' texts say
-- they give, slots, quality, binding; the keys ilvl:, q:, stat:, slot:, type: and the items' is: values.

local F = ns.Filters
local P = F._
local KEYS, IS = P.KEYS, P.IS
local Range = F.Range
local Lower = ns.Lower
local Generations, Keep, Kept, Forget = P.Generations, P.Keep, P.Kept, P.Forget

-- how many items each cache below keeps in a generation (two generations: P.Generations)
local CACHE_MAX = P.CACHE_MAX

-- An item the client hasn't loaded: asking its info makes the client fetch it from the server (review, 0.48.6:
-- "epic", "q:rare", "boe" asked for every AtlasLoot row on every keystroke, thousands at once, and the rows it said
-- nothing of were left out for good). At most F.ITEM_ASK such asks per search; past that nothing is asked, and both
-- ways F.loading is set: the search runs again once they're in (UI:RetryWhenLoaded), asking for the next ones.
F.ITEM_ASK = 40
local asksLeft = F.ITEM_ASK
function F.ResetAsks() asksLeft = F.ITEM_ASK end
--- May an item the client hasn't loaded be asked for now (F.ITEM_ASK per search)? Loaded (or the client can't say):
--- true. Not loaded: F.loading set either way (the search runs again once it's in).
local function MayAsk(id)
	local cached = C_Item and C_Item.IsItemDataCachedByID
	if not cached or type(id) ~= "number" then return true end
	local ok, yes = pcall(cached, id)
	if not ok or yes ~= false then return true end -- (loaded, or the client can't say)
	F.loading = true
	if asksLeft <= 0 then return false end
	asksLeft = asksLeft - 1
	return true
end
F.MayAsk = MayAsk -- (Rewards.lua: a bag's slots)

-- an item's info, kept per item id (it doesn't change; filters ask for it on every matching row
-- of every search): a table each time was garbage for thousands of loot rows
local infos = Generations(CACHE_MAX)
local function ItemInfo(id)
	local get = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not (get and id) then return nil end
	local c = infos.new[id]
	if c then return c end
	c = infos.old[id] -- (in use again: back into the current table below)
	if not c then
		if not MayAsk(id) then return nil end
		local ok, name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc, _, sellPrice, classID, subID, bindType = pcall(get, id)
		if not (ok and name) then return nil end -- (not known to the client yet: asked again next time)
		c = { link = link, quality = quality, ilvl = ilvl, minLevel = minLevel, type = itemType, subType = subType, equipLoc = equipLoc,
			classID = type(classID) == "number" and classID or nil, subID = type(subID) == "number" and subID or nil,
			bindType = type(bindType) == "number" and bindType or nil,
			sell = type(sellPrice) == "number" and sellPrice or nil } -- (a vendor's price for one: "| sum value", Aggregate.lua)
		if type(id) ~= "number" then return c end
		ns.NoteQuality(id, quality) -- (its colour, should the game let go of it: Util.lua)
	end
	-- (Keep, written out: this runs for every row of every item filter, and past the caps on every keystroke)
	local n = infos.n
	if n >= CACHE_MAX then infos.old, infos.new, n = infos.new, {}, 0 end
	infos.new[id], infos.n = c, n + 1
	return c
end

-- What the client's own item data says (GetItemInfoInstant: no server ask, no table made, and it knows items the
-- client hasn't loaded): an item's type, subtype and equipment slot type. Nothing when it has nothing for the item
-- (WoW Forever's own items: only the server knows those) or answers for another one.
local function Instant(id)
	local get = C_Item and C_Item.GetItemInfoInstant
	if not get then return nil end
	local ok, iid, itemType, subType, equipLoc, _, classID, subID = pcall(get, id)
	if not ok or iid ~= id then return nil end
	return itemType, subType, equipLoc, classID, subID
end
--- type:, slot: and is:equippable: test(itemType, subType, equipLoc, classID, subclassID) -> true (or a number) / false, or nil when what it
--- was given can't say. On the item's full info when it's kept already (no call to the game, as before); else on what
--- the client's own item data says (Instant: the same type, subtype and slot type in the game), so the full info of
--- thousands of loot items isn't asked for on every keystroke any more, and items the client hasn't loaded are judged
--- too (their full info would only have asked the server). Nothing from Instant: the full info, as before.
local function Judge(id, test)
	local info = infos.new[id] or (infos.old[id] and ItemInfo(id)) -- (from the older table: ItemInfo keeps it again)
	if not info then
		local yes = test(Instant(id))
		if yes ~= nil then return yes end
		info = ItemInfo(id)
		if not info then return false end
	end
	return test(info.type, info.subType, info.equipLoc, info.classID, info.subID) or false
end

-- type and subtype names, lowercase (a few dozen in the game: lowercased once each, not per row per keystroke)
local lowerWords, lowerCount = {}, 0
local function LowerWord(s)
	if type(s) ~= "string" then return false end
	local l = lowerWords[s]
	if not l then
		if lowerCount >= CACHE_MAX then lowerWords, lowerCount = {}, 0 end -- (odd data only)
		l = Lower(s)
		lowerWords[s], lowerCount = l, lowerCount + 1
	end
	return l
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
	Forget(infos)
	lowerWords, lowerCount = {}, 0
	recipeItem = {}
	if F.ClearStats then F.ClearStats() end
	if F.ClearEffects then F.ClearEffects() end
	if F.ClearPlaces then F.ClearPlaces() end
	if F.ClearSold then F.ClearSold() end
	if F.ClearSlotNames then F.ClearSlotNames() end
end
P.ItemInfo = ItemInfo

local stats = Generations(CACHE_MAX)
local statNames = {} -- stat key (ITEM_MOD_STAMINA_SHORT) -> { its shown name, lowercase (false: none); the key, lowercase }
--- The key an item row's stats are kept under (and its own link, if it has one): the item id, or with a row's own link
--- with a random suffix, "of the Monkey", the id and the suffix (that copy's stats; under the id alone every copy got
--- the first one read, an AtlasLoot base link's had none; 0.49.2, review). nil: not an item.
--- An item's key by its link: the id, or with a random suffix ("of the Monkey") "id:suffix" (that copy's own stats).
local function ItemKey(id, link)
	local suffix = type(link) == "string" and link:match("|Hitem:%-?%d+:[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*:(%-?%d+)")
	return (suffix and suffix ~= "0") and (id .. ":" .. suffix) or id
end
P.ItemKey = ItemKey
local function StatKey(e)
	local id = ItemOf(e)
	if not id then return nil end
	-- (the row's own link only: a loot row's is made on each read, "item:<id>", which has no suffix anyway; review,
	-- 0.53.6: a new string per row per keystroke, twice per row for is:upgrade)
	local link = e.itemID and rawget(e, "link")
	local own = type(link) == "string" and link:find("|H", 1, true) and link
	return own and ItemKey(id, own) or id, id, own
end
P.StatKey = StatKey
--- An item's stats (the game's: { ITEM_MOD_STAMINA_SHORT = 7, ... }), or nil until known.
local function Stats(e)
	local key, id, own = StatKey(e)
	if not key then return nil end
	local c = stats.new[key]
	if c then return c end
	c = stats.old[key]
	if c then return Keep(stats, key, c) end -- (in use again: back into the current table)
	local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	local info = ItemInfo(id)
	local link = own or (info and info.link) or ("item:" .. id)
	if not (get and info) then return nil end -- (not known to the client yet: asked again next time)
	local ok, t = pcall(get, link)
	if not (ok and type(t) == "table") then
		-- no stats: the item has none only when the client has it; else they're still coming (0.51.7: kept as none,
		-- is:upgrade judged it by item level alone until the cache moved on, then by its stats: counts that changed)
		local cached = C_Item and C_Item.IsItemDataCachedByID
		if cached and type(id) == "number" then
			local okC, yes = pcall(cached, id)
			if okC and yes == false then
				-- (the client let go of it since its info was kept: asked again, and the search runs again once it's in,
				-- as for its info; review, 0.53.6: the row was left out with nothing asked)
				if MayAsk(id) and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
				return nil
			end
		end
		t = {}
	end
	return Keep(stats, key, t)
end
F.ClearStats = function() Forget(stats); statNames = {}; if F.ClearFit then F.ClearFit() end end
P.Stats = Stats

-- short names for stats -> part of the game's stat key
local STAT_WORDS = {
	str = "STRENGTH", strength = "STRENGTH", agi = "AGILITY", agility = "AGILITY",
	sta = "STAMINA", stam = "STAMINA", stamina = "STAMINA", int = "INTELLECT", intellect = "INTELLECT",
	spi = "SPIRIT", spirit = "SPIRIT", armor = "RESISTANCE0", armour = "RESISTANCE0",
	ap = "ATTACK_POWER", attackpower = "ATTACK_POWER", sp = "SPELL_POWER", spellpower = "SPELL_POWER",
	rap = "RANGED_ATTACK_POWER", rangedattackpower = "RANGED_ATTACK_POWER",
	heal = "HEAL", healing = "HEAL", crit = "CRIT", hit = "HIT", haste = "HASTE", dodge = "DODGE",
	parry = "PARRY", block = "BLOCK", def = "DEFENSE", defense = "DEFENSE", mp5 = "REGEN",
	dps = "DAMAGE_PER_SECOND", holy = "RESISTANCE1", fire = "RESISTANCE2", nature = "RESISTANCE3",
	frost = "RESISTANCE4", shadow = "RESISTANCE5", arcane = "RESISTANCE6",
	-- weapon damage: no item stat has it (StatIs never matches it); sharpening stones, weightstones: their effect text
	weapondamage = "WEAPON_DAMAGE", wdmg = "WEAPON_DAMAGE", weapon_damage = "WEAPON_DAMAGE",
}
F.STATS = { "stamina", "strength", "agility", "intellect", "spirit", "armor", "ap", "rap", "sp", "healing",
	"crit", "hit", "haste", "dodge", "parry", "block", "defense", "mp5", "dps", "fire", "frost",
	"nature", "shadow", "arcane", "holy", "weapondamage" }

-- a stat word's part, where the part alone also names other stats in the game's keys (review, 0.53.6: mp5 found
-- HEALTH_REGEN, hp5; healing found HEALTH; ap ranged attack power, which has its own word; sp missed the older
-- SPELL_DAMAGE_DONE). Upgrades.lua's STAT_KINDS tells them apart the same way.
local KEY_PARTS = {
	REGEN = { "MANA_REGEN", "POWER_REGEN0" }, HEAL = { "HEALING" }, SPELL_POWER = { "SPELL_POWER", "SPELL_DAMAGE" },
	ATTACK_POWER = { "MOD_ATTACK_POWER", "FERAL_ATTACK_POWER" },
}
--- Does this stat key (ITEM_MOD_STAMINA_SHORT) answer to the typed word?
local function StatIs(key, word)
	local part = STAT_WORDS[word]
	if part then
		for _, p in ipairs(KEY_PARTS[part] or { part }) do
			if key:find(p, 1, true) then return true end
		end
		return false
	end
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
local effects = Generations(CACHE_MAX) -- item id -> its effect text, lowercase (false: none)
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
	local c = Kept(effects, id)
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
		Keep(effects, id, text or false)
		effectRetry[id] = nil
	end
	return text
end

local CONSUMABLE = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local QUESTITEM = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
local classes = Generations(CACHE_MAX) -- item id -> its item class (asked once per item: filters ask per row, per search)
--- An item's class id (GetItemInfoInstant), or nil when the game can't say yet (not kept then).
local function ClassID(id)
	local c = Kept(classes, id)
	if c ~= nil then return c end
	local get = C_Item and C_Item.GetItemInfoInstant
	if not get then return nil end
	local ok, _, _, _, _, _, classID = pcall(get, id)
	if not ok or type(classID) ~= "number" then return nil end
	return Keep(classes, id, classID)
end
-- (not known: taken for one, so its effect is still read)
local function IsConsumable(id) local c = ClassID(id); return c == nil or c == CONSUMABLE end
-- sharpening stones and weightstones are Trade Goods on classic-era item data (Consumable later): both are read
local TRADEGOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local function IsConsumableOrGoods(id) local c = ClassID(id); return c == nil or c == CONSUMABLE or c == TRADEGOODS end

-- What an item is, by the game's numbers (0.47.12): GetItemInfoInstant's class and subclass, the same in every language.
-- type: took only the names (the client's own: "One-Handed Swords", "Einhandschwerter"), so "sword" and Simple mode's
-- everyday words found nothing in another client's language. Each English word: its class * 100 + subclass numbers
-- (Enum.ItemWeaponSubclass, Enum.ItemArmorSubclass, the consumables'); a whole class by CLASS_WORDS.
local TYPE_IDS = {
	axe = { 200, 201 }, bow = { 202 }, gun = { 203 }, mace = { 204, 205 }, polearm = { 206 }, sword = { 207, 208 },
	stave = { 210 }, staff = { 210 }, fist = { 213 }, ["fist weapon"] = { 213 }, dagger = { 215 }, thrown = { 216 },
	crossbow = { 218 }, wand = { 219 }, ["fishing pole"] = { 220 },
	cloth = { 401 }, leather = { 402 }, mail = { 403 }, plate = { 404 }, shield = { 406 }, libram = { 407 }, idol = { 408 },
	totem = { 409 }, relic = { 411 },
	potion = { 1 }, elixir = { 2 }, flask = { 3 }, scroll = { 4 }, food = { 5 }, drink = { 5 }, bandage = { 7 },
}
local CLASS_WORDS = { consumable = 0, container = 1, bag = 1, weapon = 2, gem = 3, armor = 4, armour = 4, reagent = 5,
	projectile = 6, ammo = 6, recipe = 9, quiver = 11, quest = 12, key = 13 }
F.TYPE_IDS, F.CLASS_WORDS = TYPE_IDS, CLASS_WORDS -- (Simple.lua: the game's own names for them, in Simple mode)
--- The numbers an English type word stands for (plural or not), or nil: a set of class * 100 + subclass, a class.
local function TypeIds(v)
	local list = TYPE_IDS[v] or TYPE_IDS[(v:gsub("es$", ""))] or TYPE_IDS[(v:gsub("s$", ""))]
	local cls = CLASS_WORDS[v] or CLASS_WORDS[(v:gsub("s$", ""))]
	if not (list or cls) then return nil end
	local set
	if list then set = {} for _, n in ipairs(list) do set[n] = true end end
	return set, cls
end

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
F.ClearEffects = function() Forget(effects); effectRetry = {}; Forget(classes) end

-- the game's own names for each stat, in the client's language (as AtlasLoot's IngameLocales reads them): what an
-- effect text says ("Erhöht Ausdauer um 6") and Simple mode's words in that language ("Ausdauer Essen"; Words.lua)
local STAT_GLOBALS = {
	STRENGTH = { "ITEM_MOD_STRENGTH_SHORT", "SPELL_STAT1_NAME" }, AGILITY = { "ITEM_MOD_AGILITY_SHORT", "SPELL_STAT2_NAME" },
	STAMINA = { "ITEM_MOD_STAMINA_SHORT", "SPELL_STAT3_NAME" }, INTELLECT = { "ITEM_MOD_INTELLECT_SHORT", "SPELL_STAT4_NAME" },
	SPIRIT = { "ITEM_MOD_SPIRIT_SHORT", "SPELL_STAT5_NAME" }, RESISTANCE0 = { "RESISTANCE0_NAME", "ARMOR" },
	ATTACK_POWER = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" },
	RANGED_ATTACK_POWER = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
	SPELL_POWER = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
	HEAL = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" }, CRIT = { "ITEM_MOD_CRIT_RATING_SHORT" },
	HIT = { "ITEM_MOD_HIT_RATING_SHORT" }, HASTE = { "ITEM_MOD_HASTE_RATING_SHORT" }, DODGE = { "ITEM_MOD_DODGE_RATING_SHORT" },
	PARRY = { "ITEM_MOD_PARRY_RATING_SHORT" }, BLOCK = { "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT" },
	DEFENSE = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
	REGEN = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" },
	DAMAGE_PER_SECOND = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
	RESISTANCE1 = { "RESISTANCE1_NAME" }, RESISTANCE2 = { "RESISTANCE2_NAME" }, RESISTANCE3 = { "RESISTANCE3_NAME" },
	RESISTANCE4 = { "RESISTANCE4_NAME" }, RESISTANCE5 = { "RESISTANCE5_NAME" }, RESISTANCE6 = { "RESISTANCE6_NAME" },
}
--- A stat word's names as the game says them in the client's language, lowercase (none: an empty list).
function F.StatGameNames(word)
	local out, seen = {}, {}
	local function Put(g)
		if type(g) == "string" and g ~= "" and not g:find("%", 1, true) then
			local l = Lower(g)
			if not seen[l] then seen[l], out[#out + 1] = true, l end
		end
	end
	local part = STAT_WORDS[word]
	if not part then return out end
	for _, k in ipairs(STAT_GLOBALS[part] or {}) do Put(_G[k]) end
	for _, k in ipairs({ "SPELL_STAT_" .. part, "ITEM_MOD_" .. part .. "_SHORT", "ITEM_MOD_" .. part .. "_RATING_SHORT" }) do Put(_G[k]) end
	return out
end

-- (Russian bends its words: an effect text says "выносливости", "силу атаки", not the names as they stand. A name in
-- Cyrillic is looked for by each word's stem, its last vowel or soft sign dropped, any ending after it)
local CYR_END = { ["а"] = true, ["е"] = true, ["и"] = true, ["о"] = true, ["у"] = true, ["ы"] = true, ["э"] = true,
	["ю"] = true, ["я"] = true, ["ь"] = true, ["й"] = true }
local PATTERN_MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"
local function Stemmed(name)
	if not name:find("[\208\209]") then return name end
	local words = {}
	for w in name:gmatch("%S+") do
		if #w > 4 and CYR_END[w:sub(-2)] then w = w:sub(1, -3) end
		words[#words + 1] = w:gsub(PATTERN_MAGIC, "%%%0") .. "[\128-\191\208\209]*"
	end
	return { pat = table.concat(words, "%s+") }
end
F.Stemmed = Stemmed

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
--- The words an effect text uses for a typed stat: the game's own names first (its language), then English. A name in
--- Cyrillic is a pattern of its stems ({ pat = ... }: Stemmed).
local function EffectNames(word)
	local part = STAT_WORDS[word]
	if not part then return { Stemmed(word) } end
	local names = {}
	for _, g in ipairs(F.StatGameNames(word)) do names[#names + 1] = Stemmed(g) end
	-- (weapon damage has no name of its own in the game: on another client, the game's words for weapon and for damage,
	-- both in the text, say it: "den Schaden einer Waffe", "les dégâts d'une arme", "урон оружия", "武器伤害"; 0.69.6)
	if part == "WEAPON_DAMAGE" then
		local lang = ns.LOCALE
		local weapon, damage = _G.WEAPON, _G.DAMAGE
		if lang and lang ~= "enUS" and lang ~= "enGB" and type(weapon) == "string" and weapon ~= "" and type(damage) == "string" and damage ~= "" then
			names[#names + 1] = { both = { Stemmed(Lower(weapon)), Stemmed(Lower(damage)) }, notWith = F.StatGameNames("sp") }
		end
	end
	local en = EFFECT_ENGLISH[part]
	if type(en) == "table" then
		for _, w in ipairs(en) do names[#names + 1] = w end
	elseif en then
		names[#names + 1] = en
	end
	return names
end

--- Where a name (a word, or a pattern of stems: Stemmed) is in the text from `from`: its first and last byte.
local function FindName(text, name, from)
	if type(name) == "table" then return text:find(name.pat, from) end
	return text:find(name, from, true)
end
--- Does the effect text name the stat (names: EffectNames of it; and, with cmp, give it an amount that passes)?
local function EffectHas(text, names, cmp)
	for _, name in ipairs(names) do
		-- (two words both in the text, the amount by the second: weapon damage on another client; not a text that names a
		-- stat of its own with them, a wizard oil's spell damage)
		if type(name) == "table" and name.both then
			local other = false
			for _, n in ipairs(name.notWith or {}) do if text:find(n, 1, true) then other = true end end
			local w = not other and FindName(text, name.both[1], 1)
			local at, last = nil, nil
			if w then at, last = FindName(text, name.both[2], 1) end
			if at then
				if not cmp then return true end
				local n = tonumber(text:sub(math.max(1, at - 10), at - 1):match("(%d+)%s*$"))
					or tonumber(text:sub(last + 1, last + 40):match("^%D-(%d+)"))
				if n and cmp(n) then return true end
			end
			name = nil
		end
		if name then
			local from = 1
			local pat = type(name) == "table" and name.pat
			while true do
				local at, last
				if pat then at, last = text:find(pat, from) else at, last = text:find(name, from, true) end
				if not at then break end
				if not cmp then return true end
				-- "+6 Stamina", "6 Strength" (right before it), or "Strength by 25" (soon after it)
				local n = tonumber(text:sub(math.max(1, at - 10), at - 1):match("(%d+)%s*$"))
					or tonumber(text:sub(last + 1, last + 24):match("^%D-(%d+)"))
				if n and cmp(n) then return true end
				from = last + 1
			end
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
-- (0.47.12) slot words whose item slot types don't hold them: matched by the English client's names only, so "back",
-- "hands" and "chest" found nothing in another language (INVTYPE_CLOAK is "Rücken" there)
local SLOT_TOKENS = { back = { invtype_cloak = true }, hands = { invtype_hand = true }, chest = { invtype_robe = true },
	["off hand"] = { invtype_holdable = true }, ranged = { invtype_rangedright = true, invtype_thrown = true },
	shirt = { invtype_body = true }, shirts = { invtype_body = true } } -- (shirt: INVTYPE_BODY; review, 0.53.6)
-- how enchants name the slot they go on
local ENCHANT_WORDS = {
	wrist = { "bracer", "wrist" }, feet = { "boots", "boot", "feet" }, hands = { "gloves", "glove", "hands" },
	back = { "cloak", "back" }, head = { "helm", "head" }, legs = { "leg", "pants" }, chest = { "chest" },
	shoulder = { "shoulder" }, finger = { "ring" }, shield = { "shield" }, waist = { "belt", "waist" },
	weapon = { "weapon" }, ["two-hand"] = { "2h weapon", "two-handed", "two-hand" }, ["off hand"] = { "off-hand", "shield" },
}
F.SLOT_ALIAS = SLOT_ALIAS -- (slot:boots is the feet: Share.Describe says it so)
local function SlotWant(v) return SLOT_ALIAS[v] or v end
local locWords = {} -- INVTYPE_x -> { its shown name, lowercase; itself, lowercase } (a few dozen, kept)
F.ClearSlotNames = function() locWords = {} end
--- Does this item slot type answer to the slot word? flat: want without spaces or dashes (worked out once).
local function SlotIs(loc, want, flat)
	local w = locWords[loc]
	if not w then
		local shown = _G[loc]
		w = { type(shown) == "string" and Lower(shown) or "", loc:lower() }
		locWords[loc] = w
	end
	if w[1]:find(want, 1, true) or w[2]:find(flat, 1, true) then return true end
	if SLOT_TOKENS[want] and SLOT_TOKENS[want][w[2]] then return true end
	local extra = SLOT_LOC[want]
	return extra and w[2]:find(extra, 1, true) and (want ~= "one-hand" or w[2] == "invtype_weapon") and true or false
end

local QUALITY = { poor = 0, grey = 0, gray = 0, junk = 0, common = 1, white = 1, uncommon = 2, green = 2,
	rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5, artifact = 6, heirloom = 7 }
F.QUALITIES = { "poor", "common", "uncommon", "rare", "epic", "legendary" }
F.QUALITY = QUALITY -- (the q: filter's words: Share.Describe says them)

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

-- ("" for an item that isn't worn: an answer too)
local function WornIn(_, _, loc)
	if type(loc) ~= "string" then return nil end
	return SLOTS[loc] ~= nil
end
local function Equippable(e)
	local id = e.itemID
	if not id then return false end
	return Judge(id, WornIn)
end

-- Binding. Item rows know whether the stacks in your bags (or the worn piece) are bound: bound = some stack is,
-- unbound = some stack isn't (Items.lua; rows are one per item, so a bound and a tradable copy answer both).
-- Rows with no stacks of yours (loot, recipes, stored) only have the item's bind type.
local BIND_EQUIP = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
local BIND_QUEST = Enum and Enum.ItemBind and Enum.ItemBind.Quest or 4

local function Soulbound(e) return e.itemID ~= nil and e.bound == true end

--- Enchanted gear (0.64.2, the player's ask: "is:enchanted for gear in bags and bank"): rows of yours know whether a copy
--- is enchanted or not (enchanted / unenchanted: Items.lua, Stored.lua; one row per item, so two copies answer both);
--- else the row's link says. is:unenchanted: gear without one (-is:enchanted would take in cloth and potions too).
local function Enchanted(e)
	if not e.itemID then return false end
	if e.enchanted ~= nil or e.unenchanted ~= nil then return e.enchanted == true end
	local ench = ns.LinkEnchant(e.link)
	return ench ~= nil and ench ~= 0
end
-- (the slots an enchant goes on: not a shirt, tabard, neck, ring, trinket, held off-hand, relic or thrown; review, 0.64.3)
local ENCHANTABLE = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
	INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_CLOAK = true,
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_SHIELD = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }
local WAND = 19 -- (a weapon subclass: no scope fits one)
local function EnchantSlot(_, _, loc, classID, subID)
	if type(loc) ~= "string" then return nil end
	return ENCHANTABLE[loc] == true and not (classID == 2 and subID == WAND)
end
local function Unenchanted(e)
	if not e.itemID or not Judge(e.itemID, EnchantSlot) then return false end
	if e.enchanted ~= nil or e.unenchanted ~= nil then return e.unenchanted == true end
	return ns.LinkEnchant(e.link) == 0
end

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

----------------------------------------------------------------------
-- Keys for items
----------------------------------------------------------------------

KEYS.ilvl = function(v)
	local r = Range(v)
	return r and function(e)
		local id = ItemOf(e)
		local info = id and ItemInfo(id)
		return info and r(info.ilvl) or false
	end
end
KEYS.itemlevel = KEYS.ilvl

-- value:>1g: what the row sells to a vendor for (a stack: all of it), as sort:value and | sum value count it (0.66.5:
-- "items worth more than 1g" in plain words)
KEYS.value = function(v)
	local r = F.MoneyRange(v)
	return r and function(e)
		local A = ns.Aggregate
		local f = A and A.FIELDS and A.FIELDS.value
		local ok, n = false, nil
		if f then ok, n = pcall(f.num, e) end
		return ok and r(n) or false
	end
end
KEYS.worth = KEYS.value

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
	-- (mp5 has a digit; a stat's name in the game's language too, "stat:выносливость": 0.49.2, review)
	local word, op, n = v:match("^([%a_\128-\255][%w_\128-\255]*)([<>=]+)(%d+)$")
	if not word then word = v:match("^([%a_\128-\255][%w_\128-\255]*)$") end
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
	local function Fits(_, _, loc)
		if type(loc) ~= "string" then return nil end
		return loc ~= "" and SlotIs(loc, want, flat)
	end
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
		return Judge(id, Fits)
	end
end

KEYS.type = function(v)
	if v == "" then return nil end
	-- (type and subtype lowercased once per name: LowerWord)
	local set, cls = TypeIds(v) -- (an English word: the game's numbers too, in any client's language)
	local function Is(t, st, _, c, sc)
		if (set or cls) and type(c) == "number" then
			if cls == c or (set and type(sc) == "number" and set[c * 100 + sc]) then return true end
		end
		if type(t) ~= "string" and type(st) ~= "string" then return nil end
		local lt, lst = LowerWord(t), LowerWord(st)
		if lt and lt:find(v, 1, true) then return true end
		return lst and lst:find(v, 1, true) or false
	end
	return function(e)
		local id = ItemOf(e)
		if not id then return false end
		return Judge(id, Is)
	end
end

-- is: values for items
IS.quest = QuestItem
IS.soulbound = Soulbound
IS.enchanted, IS.unenchanted = Enchanted, Unenchanted
IS.boe = BoE
IS.usable = Usable
IS.equippable = Equippable
IS.use, IS.wearable = IS.usable, IS.equippable
IS.bound, IS.questitem = IS.soulbound, IS.quest

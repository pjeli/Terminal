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
		local ok, name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc, _, _, _, _, bindType = pcall(get, id)
		if not (ok and name) then return nil end -- (not known to the client yet: asked again next time)
		c = { link = link, quality = quality, ilvl = ilvl, minLevel = minLevel, type = itemType, subType = subType, equipLoc = equipLoc,
			bindType = type(bindType) == "number" and bindType or nil }
		if type(id) ~= "number" then return c end
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
	local ok, iid, itemType, subType, equipLoc = pcall(get, id)
	if not ok or iid ~= id then return nil end
	return itemType, subType, equipLoc
end
--- type:, slot: and is:equippable: test(itemType, subType, equipLoc) -> true (or a number) / false, or nil when what it
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
	return test(info.type, info.subType, info.equipLoc) or false
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
end
P.ItemInfo = ItemInfo

local stats = Generations(CACHE_MAX)
local statNames = {} -- stat key (ITEM_MOD_STAMINA_SHORT) -> { its shown name, lowercase (false: none); the key, lowercase }
--- An item's stats (the game's: { ITEM_MOD_STAMINA_SHORT = 7, ... }), or nil until known.
local function Stats(e)
	local id = ItemOf(e)
	if not id then return nil end
	local c = stats.new[id]
	if c then return c end
	c = stats.old[id]
	if c then return Keep(stats, id, c) end -- (in use again: back into the current table)
	local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	local info = ItemInfo(id)
	local own = e.itemID and type(e.link) == "string" and e.link:find("|H", 1, true) and e.link
	local link = own or (info and info.link) or ("item:" .. id)
	if not (get and info) then return nil end -- (not known to the client yet: asked again next time)
	local ok, t = pcall(get, link)
	t = ok and type(t) == "table" and t or {}
	return Keep(stats, id, t)
end
F.ClearStats = function() Forget(stats); statNames = {} end
P.Stats = Stats

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
F.EffectText = EffectText

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
P.ClassID = ClassID

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
F.SLOT_ALIAS = SLOT_ALIAS -- (slot:boots is the feet: Share.Describe says it so)
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
	local function Is(t, st)
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
IS.boe = BoE
IS.usable = Usable
IS.equippable = Equippable
IS.use, IS.wearable = IS.usable, IS.equippable
IS.bound, IS.questitem = IS.soulbound, IS.quest

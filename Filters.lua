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
--   is:usable is:equippable      items you can use / wear (no is:upgrade: item level alone can't tell)
--   is:quest is:soulbound is:boe items: quest items, bound ones, bind on equip not yet bound
--   is:ready is:passive          spells off cooldown (quests: = is:complete) / passive spells
--   is:capped                    currencies at their cap (or this week's)
--   is:craftable                 recipes you have every reagent for
--   is:vendor is:trainer ...     Questie NPCs by what they do

local F = {}
ns.Filters = F

local function Lower(s) return ns.Lower(s) end

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

--- Level range of a row: items (the level they need), quests, Questie NPCs.
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
	if type(l) == "number" then return l, l end
end

local statCache, statCount = {}, 0
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
F.ClearStats = function() statCache, statCount = {}, 0 end

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
}
F.STATS = { "stamina", "strength", "agility", "intellect", "spirit", "armor", "ap", "sp", "healing",
	"crit", "hit", "haste", "dodge", "parry", "block", "defense", "mp5", "dps", "fire", "frost",
	"nature", "shadow", "arcane", "holy" }

--- Does this stat key (ITEM_MOD_STAMINA_SHORT) answer to the typed word?
local function StatIs(key, word)
	local part = STAT_WORDS[word]
	if part then return key:find(part, 1, true) ~= nil end
	local shown = _G[key]
	return (type(shown) == "string" and Lower(shown):find(word, 1, true)) or Lower(key):find(word, 1, true) and true or false
end

-- Consumables (elixirs, potions, food, scrolls) have no item stats: their effect is the text of their
-- use spell ("Increases Strength by 8 for 1 hour", food's "well fed and gain 6 Stamina and Spirit"),
-- and their tooltip's lines. Read once per item, lowercase; nil while the game is still loading it.
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local effectCache, effectCount = {}, 0
local effectRetry = {} -- item id -> when to read it again (its item or spell data was still loading)
local RETRY = 1 -- seconds
local function EffectText(e)
	local id = ItemOf(e)
	if not id then return nil end
	local c = effectCache[id]
	if c ~= nil then return c or nil end
	local now = GetTime()
	if effectRetry[id] and now < effectRetry[id] then return nil end
	-- an item the client hasn't got yet has no spell and a "Retrieving item information" tooltip: never kept
	if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then
		if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		effectRetry[id] = now + RETRY
		return nil
	end
	local parts, pending = {}, false
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
			pending = true -- (the spell's text is still loading: asked for, read again in a moment)
			if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
		end
	end
	if C_TooltipInfo and C_TooltipInfo.GetItemByID then
		local ok, info = pcall(C_TooltipInfo.GetItemByID, id)
		if ok and type(info) == "table" and type(info.lines) == "table" then
			for _, l in ipairs(info.lines) do
				local t = type(l) == "table" and l.leftText
				if type(t) == "string" and not Secret(t) then parts[#parts + 1] = t end
			end
		end
	end
	local text = #parts > 0 and Lower(table.concat(parts, "\n")) or nil
	if pending then
		effectRetry[id] = now + RETRY -- (not every keystroke: once a second until it's in)
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
F.ClearEffects = function() effectCache, effectCount, effectRetry, classes, classCount = {}, 0, {}, {}, 0 end

-- how an effect text names each stat when the game's own name isn't there (English)
local EFFECT_ENGLISH = {
	STRENGTH = "strength", AGILITY = "agility", STAMINA = "stamina", INTELLECT = "intellect", SPIRIT = "spirit",
	RESISTANCE0 = "armor", ATTACK_POWER = "attack power", SPELL_POWER = "spell power", HEAL = "healing",
	CRIT = "critical strike", HIT = "hit rating", HASTE = "haste", DODGE = "dodge", PARRY = "parry", BLOCK = "block",
	DEFENSE = "defense", REGEN = "mana every 5", RESISTANCE1 = "holy resistance", RESISTANCE2 = "fire resistance",
	RESISTANCE3 = "nature resistance", RESISTANCE4 = "frost resistance", RESISTANCE5 = "shadow resistance",
	RESISTANCE6 = "arcane resistance",
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
	if EFFECT_ENGLISH[part] then names[#names + 1] = EFFECT_ENGLISH[part] end
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
local function Number(v) return type(v) == "number" and not Secret(v) and v or nil end
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
		if not IsConsumable(id) then return false end
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
		local t, st = info.type, info.subType
		if type(t) == "string" and Lower(t):find(v, 1, true) then return true end
		return type(st) == "string" and Lower(st):find(v, 1, true) or false
	end
end

KEYS["in"] = function(v)
	if v == "" then return nil end
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

local CLASS_SET = {}
for _, c in ipairs(CLASSES) do CLASS_SET[c] = true end

KEYS.trainer = function(v)
	if v == "" then return nil end
	-- your class's trainers: trainer:class (you mean the one you can learn from); trainer:mine is mining
	if v == "class" or v == "my" or v == "me" or v == "myclass" then
		return function(e)
			local sub = TrainerTitle(e)
			local mine = sub and MyClass()
			return mine and ClassOf(sub) == mine or false
		end
	elseif v == "classes" or v == "anyclass" then
		return function(e) local sub = TrainerTitle(e); return sub and ClassOf(sub) ~= nil or false end
	elseif v == "profession" or v == "professions" or v == "prof" then
		return function(e) local sub = TrainerTitle(e); return sub and ProfOf(sub) ~= nil or false end
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
		local id = NpcID(e)
		if not (id and I and I.NpcDistance) then return false end
		if here == nil then here = I.Here and I.Here() or false end
		local d = here and I.NpcDistance(id, here)
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
	classtrainer = function(e) local sub = TrainerTitle(e); return sub and ClassOf(sub) ~= nil or false end,
	proftrainer = function(e) local sub = TrainerTitle(e); return sub and ProfOf(sub) ~= nil or false end,
}
local ROLES = { vendor = "VENDOR", trainer = "TRAINER", flightmaster = "FLIGHT_MASTER", flight = "FLIGHT_MASTER",
	innkeeper = "INNKEEPER", inn = "INNKEEPER", banker = "BANKER", bank = "BANKER", repair = "REPAIR",
	auctioneer = "AUCTIONEER", questgiver = "QUEST_GIVER", stablemaster = "STABLEMASTER" }
for word, flag in pairs(ROLES) do IS[word] = function(e) return NpcRole(e, flag) end end
IS.notdone, IS.undone, IS.use, IS.wearable = IS.todo, IS.todo, IS.usable, IS.equippable
IS.bound, IS.questitem, IS.maxed, IS.offcooldown = IS.soulbound, IS.quest, IS.capped, IS.ready
IS.professiontrainer = IS.proftrainer
KEYS.is = function(v) return IS[v] end

-- the values Tab offers after "key:" (the main spellings only)
F.VALUES = {
	is = { "done", "todo", "complete", "ready", "usable", "equippable", "quest", "soulbound", "boe", "craftable", "passive",
		"capped", "vendor", "trainer", "classtrainer", "proftrainer", "flightmaster", "innkeeper", "banker", "repair",
		"auctioneer", "questgiver", "stablemaster" },
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
	{ "is:todo", "quests: done todo complete (ready = complete); achievements: done todo; items: usable equippable quest soulbound boe; recipes: craftable" },
	{ "is:ready", "spells: ready (off cooldown) passive; currencies: capped; NPCs: vendor trainer classtrainer proftrainer flightmaster innkeeper banker repair..." },
	{ "in:elwynn_forest", "a value of several words: _ for the space (in:elwynn_forest, type:one-handed_swords)" },
}

--- Is this a filter key (lvl, stat, is...)? For the prompt's colours.
function F.IsKey(key) return KEYS[Lower(key or "")] ~= nil end

-- the keys whose value is matched as text: a _ in it stands for a space (the search splits on spaces,
-- so "in:elwynn forest" can't reach us whole; stat words keep their _: attack_power is the game's key)
local SPACED = { ["in"] = true, zone = true, from = true, where = true, on = true, who = true, type = true,
	trainer = true, slot = true, sells = true, sold = true, standing = true, rep = true }

local traced -- a failing filter has been traced for this search (the parse of a search's words starts the next)

--- A filter for one typed word, or nil when it isn't one (then it's searched as text).
function F.Parse(word)
	traced = false
	local key, value = word:match("^(%a+):(.+)$")
	if not key then return nil end
	key = Lower(key)
	local make = KEYS[key]
	if not make then return nil end
	value = Lower(value)
	if SPACED[key] then value = value:gsub("_", " ") end
	return make(value) or nil
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

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
--   trainer:mage trainer:mine    Questie trainers by what they teach (a class, a profession, pet,
--                                riding; mine = your class); is:classtrainer, is:proftrainer
--   faction:horde                Questie NPCs friendly to the Horde (alliance, neutral = both,
--                                friendly = to your own faction)
--   is:done is:todo is:complete  quests: finished / not yet / ready to turn in
--   is:usable is:equippable      items you can use / wear (no is:upgrade: item level alone can't tell)
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
	local ok, name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc = pcall(get, id)
	if ok and name then -- (not known to the client yet: asked again next time)
		c = { link = link, quality = quality, ilvl = ilvl, minLevel = minLevel, type = itemType, subType = subType, equipLoc = equipLoc }
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
	local id
	if TS and TS.GetRecipeSchematic then
		local ok, sch = pcall(TS.GetRecipeSchematic, r, false)
		if ok and type(sch) == "table" and type(sch.outputItemID) == "number" and sch.outputItemID > 0 then id = sch.outputItemID end
	end
	recipeItem[r] = id or false
	return id
end
local function ItemOf(e) return e.itemID or MadeBy(e) end
F.ItemOf = ItemOf

F.ClearCache = function() infoCache, infoCount = {}, 0; recipeItem = {}; if F.ClearEffects then F.ClearEffects() end end -- (tests)

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

--- A number range from "20", "20-30", "20-", "-30", "20+", "<30", "<=30", ">20", ">=20".
local function Range(v)
	local lo, hi
	local a, b = v:match("^(%d*)%-(%d*)$")
	if a then
		lo, hi = tonumber(a), tonumber(b)
		if not lo and not hi then return nil end
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
local function EffectText(e)
	local id = ItemOf(e)
	if not id then return nil end
	local c = effectCache[id]
	if c ~= nil then return c or nil end
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
		else
			pending = true -- (the spell's text isn't loaded yet: asked for, and read again next time)
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
	if text or not pending then
		if effectCount > 4000 then effectCache, effectCount = {}, 0 end
		effectCache[id], effectCount = text or false, effectCount + 1
	end
	return text
end
F.EffectText = EffectText
F.ClearEffects = function() effectCache, effectCount = {}, 0 end

local CONSUMABLE = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local function IsConsumable(id)
	local get = C_Item and C_Item.GetItemInfoInstant
	if not get then return true end
	local ok, _, _, _, _, _, classID = pcall(get, id)
	return not ok or classID == nil or classID == CONSUMABLE
end

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

--- Does the effect text name the stat (and, with cmp, give it an amount that passes)?
local function EffectHas(text, word, cmp)
	for _, name in ipairs(EffectNames(word)) do
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
local recipeText = {}
local function RecipeText(e)
	local r = e.recipeID
	if not r then return nil end
	local c = recipeText[r]
	if c then return c end
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
	if desc then recipeText[r] = text end -- (without its text yet: only the name, and asked again next time)
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
local function SlotIs(loc, want)
	local shown = _G[loc]
	if type(shown) == "string" and Lower(shown):find(want, 1, true) then return true end
	local l = loc:lower()
	return l:find((want:gsub("[%s%-]", "")), 1, true) ~= nil or (SLOT_LOC[want] and l:find(SLOT_LOC[want], 1, true) and
		(want ~= "one-hand" or l == "invtype_weapon")) or false
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

--- Where a row is, as text to match: a zone, an NPC's zone, a stored item's places, or the
--- row's own detail ("Edwin VanCleef  The Deadmines", "x5  Backpack", "[12] Elwynn Forest").
local function Places(e, v)
	if type(e.zone) == "string" and Lower(e.zone):find(v, 1, true) then return true end
	if NpcID(e) then
		local area = NpcField(e, "zoneID")
		local name = type(area) == "number" and area > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
		return type(name) == "string" and Lower(name):find(v, 1, true) and true or false
	end
	if type(e.holders) == "table" then
		for _, h in pairs(e.holders) do
			if (h.count or 1) > 0 and type(h.where) == "string" and h.where:find(v, 1, true) then return true end
		end
		return false
	end
	if e.slotId and ("equipped"):find(v, 1, true) then return true end
	local d = e.detail
	return type(d) == "string" and Lower(d):find(v, 1, true) and true or false
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
	local word, op, n = v:match("^([%a_]+)([<>=]+)(%d+)$")
	if not word then word = v:match("^([%a_]+)$") end
	if not word then return nil end
	local cmp = op and Range(op .. n)
	if op and not cmp then return nil end
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
			return text and EffectHas(text, word, cmp) or false
		end
		-- no item stats (an elixir, a potion, food...): what its effect says it gives. Only consumables are
		-- read (a tooltip per item: thousands of loot rows mustn't each be read)
		if not IsConsumable(id) then return false end
		local text = EffectText(e)
		return text and EffectHas(text, word, cmp) or false
	end
end
KEYS.stats = KEYS.stat

KEYS.slot = function(v)
	if v == "" then return nil end
	local want = SlotWant(v)
	return function(e)
		local id = ItemOf(e)
		if not id then
			-- an enchant: the slot its name or text names ("Enchant Bracer", "enchant boots")
			local text = e.recipeID and RecipeText(e)
			if not text then return false end
			for _, w in ipairs(ENCHANT_WORDS[want] or { want }) do
				if text:find(w, 1, true) then return true end
			end
			return false
		end
		local info = ItemInfo(id)
		local loc = info and info.equipLoc
		if type(loc) ~= "string" or loc == "" then return false end
		return SlotIs(loc, want)
	end
end

KEYS.type = function(v)
	if v == "" then return nil end
	return function(e)
		local id = ItemOf(e)
		local info = id and ItemInfo(id)
		if not info then return false end
		for _, t in ipairs({ info.type, info.subType }) do
			if type(t) == "string" and Lower(t):find(v, 1, true) then return true end
		end
		return false
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
local PROFS = { blacksmithing = "blacksmith", leatherworking = "leatherwork", tailoring = "tailor",
	alchemy = "alchemist", engineering = "engineer", enchanting = "enchant", jewelcrafting = "jewelcraft",
	inscription = "scribe", herbalism = "herbalism", mining = "mining", skinning = "skinning",
	cooking = "cook", fishing = "fishing", firstaid = "first aid", cartography = "cartograph" }

local function TrainerTitle(e)
	if not NpcID(e) then return nil end
	local sub = NpcField(e, "subName")
	if type(sub) ~= "string" or sub == "" then return nil end
	sub = Lower(sub)
	if sub:find("trainer", 1, true) or NpcRole(e, "TRAINER") then return sub end
end

local function ClassOf(sub)
	for _, c in ipairs(CLASSES) do
		if sub:find(c .. " trainer", 1, true) then return c end
	end
end

local function ProfOf(sub)
	for _, stem in pairs(PROFS) do
		if sub:find(stem, 1, true) then return stem end
	end
end

--- The word a trainer: filter looks for in the title (a profession name gives its shared part).
local function TrainerWord(v)
	if PROFS[v] then return PROFS[v] end
	for name, stem in pairs(PROFS) do
		if #v >= 4 and name:sub(1, #v) == v then return stem end -- (blacksm -> blacksmith)
	end
	return v
end

KEYS.trainer = function(v)
	if v == "" then return nil end
	if v == "mine" or v == "me" or v == "my" then
		return function(e)
			local sub = TrainerTitle(e)
			local token
			if UnitClass then token = select(2, UnitClass("player")) end -- (WARRIOR: the same in every language)
			local mine = type(token) == "string" and (token:lower():gsub("deathknight", "death knight"):gsub("demonhunter", "demon hunter"))
			return sub and mine and ClassOf(sub) == mine or false
		end
	elseif v == "class" then
		return function(e) local sub = TrainerTitle(e); return sub and ClassOf(sub) ~= nil or false end
	elseif v == "profession" or v == "prof" then
		return function(e) local sub = TrainerTitle(e); return sub and ProfOf(sub) ~= nil or false end
	end
	local word = TrainerWord(v)
	return function(e)
		local sub = TrainerTitle(e)
		return sub and sub:find(word, 1, true) and true or false
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

KEYS.count = function(v)
	local r = Range(v)
	return r and function(e) return r(Count(e)) end
end
KEYS.qty = KEYS.count

local IS = {
	done = function(e) local q = QuestOf(e); return q ~= nil and Done(q) end,
	todo = function(e) local q = QuestOf(e); return q ~= nil and not Done(q) end,
	complete = Complete,
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
IS.notdone, IS.undone, IS.use, IS.wearable, IS.ready = IS.todo, IS.todo, IS.usable, IS.equippable, IS.complete
IS.professiontrainer = IS.proftrainer
KEYS.is = function(v) return IS[v] end

-- the values Tab offers after "key:" (the main spellings only)
F.VALUES = {
	is = { "done", "todo", "complete", "usable", "equippable", "craftable", "vendor", "trainer", "classtrainer", "proftrainer",
		"flightmaster", "innkeeper", "banker", "repair", "auctioneer", "questgiver", "stablemaster" },
	q = F.QUALITIES, quality = F.QUALITIES,
	stat = F.STATS, stats = F.STATS,
	["in"] = { "bags", "bank", "mail", "guild", "warband", "equipped" },
	faction = { "horde", "alliance", "neutral", "friendly" },
	trainer = { "mine", "class", "profession", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage",
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
	{ "trainer:mage", "@npc trainers by what they teach: a class, a profession (trainer:blacksmithing), mine (your class), class, profession, pet, riding" },
	{ "faction:horde", "@npc: friendly to the Horde / alliance / neutral (both) / friendly (to you)" },
	{ "is:todo", "quests: done todo complete; items: usable equippable; recipes: craftable; NPCs: vendor trainer classtrainer proftrainer flightmaster innkeeper banker repair..." },
}

--- Is this a filter key (lvl, stat, is...)? For the prompt's colours.
function F.IsKey(key) return KEYS[Lower(key or "")] ~= nil end

--- A filter for one typed word, or nil when it isn't one (then it's searched as text).
function F.Parse(word)
	local key, value = word:match("^(%a+):(.+)$")
	if not key then return nil end
	local make = KEYS[Lower(key)]
	return make and make(Lower(value)) or nil
end

--- Every filter passes this row.
function F.Pass(e, filters)
	for i = 1, #filters do
		local ok, yes = pcall(filters[i], e)
		if not (ok and yes) then return false end
	end
	return true
end

F.KEYS = KEYS

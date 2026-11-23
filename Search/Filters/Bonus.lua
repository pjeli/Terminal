local ns = select(2, ...)
local L = ns.L

-- Bonuses that hang on where you are or what you fight (1.8.1, the player: WoW Forever "has a lot of items and gear pieces
-- that have certain effects depending on what biome you are in or target you are fighting"). Read from the item's own
-- tooltip, the game's text, once per item:
--   area types   "This effect is doubled in Marsh and Swamp areas.", "Increases Spirit by 16 in Cavernous or Underground
--                areas.", "Healing is doubled in Strongholds and Cities."
--   creatures    "+45 Attack Power when fighting Undead.", "Increases damage done to Demons by ...", "+18 Attack Power
--                against Beasts.", Forever's species ("against Trolls", "against the Naga")
-- bonus:haunted, bonus:undead, bonus:troll, bonus:area (any area type), bonus:creature (any creature), is:bonus (either);
-- "| group by bonus" (an item with two goes in both groups: Aggregate.lua's texts). The wording read is English: on other
-- clients nothing is found. Which area types you stand in isn't asked here: the game doesn't say, and Blizzard hasn't
-- published which zones are which.

local F = ns.Filters
local P = F._
local KEYS, IS = P.KEYS, P.IS
local Lower = ns.Lower
local Secret = ns.Secret

local BN = {}
ns.Bonus = BN

-- The area types, in the order the game's tooltips list them, each with the words a tooltip names it by.
BN.AREAS = {
	{ key = "forest", label = L["Forest and Grassland"], words = { "forest", "forests", "grassland", "grasslands" } },
	{ key = "swamp", label = L["Swamp"], words = { "swamp", "swamps", "marsh", "marshes" } },
	{ key = "wasteland", label = L["Wasteland"], words = { "wasteland", "wastelands" } },
	{ key = "haunted", label = L["Haunted"], words = { "haunted" } },
	{ key = "mountainous", label = L["Mountainous"], words = { "mountainous", "mountain", "mountains" } },
	{ key = "snowy", label = L["Snowy"], words = { "snowy", "snow" } },
	{ key = "desert", label = L["Desert"], words = { "desert", "deserts" } },
	{ key = "stronghold", label = L["Strongholds and Cities"], words = { "stronghold", "strongholds", "city", "cities" } },
	{ key = "cavern", label = L["Cavernous or Underground"], words = { "cavernous", "cavern", "caverns", "underground" } },
	{ key = "volcanic", label = L["Volcanic"], words = { "volcanic" } },
}
local AREA_OF = {} -- a tooltip's word -> its area type
local AREA_BY_KEY = {}
for _, a in ipairs(BN.AREAS) do
	AREA_BY_KEY[a.key] = a
	for _, w in ipairs(a.words) do AREA_OF[w] = a.key end
end

-- The game's creature types, and the species Forever's items name, by the words a tooltip uses (lowercase: a set bonus
-- writes "against undead"). Any other capitalised word after "against", "when fighting" or "done to" counts too
-- ("against the Naga"), unless it's one of NOT_CREATURE.
BN.CREATURES = {
	beast = { "beast", "beasts" }, demon = { "demon", "demons" }, dragonkin = { "dragonkin", "dragon", "dragons" },
	elemental = { "elemental", "elementals" }, giant = { "giant", "giants" }, humanoid = { "humanoid", "humanoids" },
	mechanical = { "mechanical", "mechanicals" }, undead = { "undead" }, critter = { "critter", "critters" },
	troll = { "troll", "trolls" }, ogre = { "ogre", "ogres" }, naga = { "naga", "nagas" }, murloc = { "murloc", "murlocs" },
	gnoll = { "gnoll", "gnolls" }, kobold = { "kobold", "kobolds" }, harpy = { "harpy", "harpies" },
	centaur = { "centaur", "centaurs" }, satyr = { "satyr", "satyrs" }, quilboar = { "quilboar", "quilboars" },
	trogg = { "trogg", "troggs" }, furbolg = { "furbolg", "furbolgs" }, scourge = { "scourge" },
}
local CREATURE_OF = {}
for key, words in pairs(BN.CREATURES) do for _, w in ipairs(words) do CREATURE_OF[w] = key end end
-- (what follows "against" that isn't a foe: you, schools, kinds of attack, sides)
local NOT_CREATURE = {}
for w in ([[you your yourself them it its him her all any a an that this these those each other enemy enemies target
	targets foe foes opponent opponents player players creature creatures monster monsters magic spell spells attack
	attacks ranged melee physical fire frost shadow nature arcane holy fear stun stuns silence poison poisons disease
	diseases curse curses horde alliance damage harm critical falling up nearby your]]):gmatch("%a+") do NOT_CREATURE[w] = true end

-- the words before a foe: "+45 Attack Power when fighting Undead", "damage done to Demons", "vs. Beasts"
local FOE_LEADS = { "when fighting ", "against ", "done to ", "versus ", "vs. ", "vs " }
-- the words of a place list: joining words, the word that closes it ("areas"), words that end it after an area word
local JOIN = { ["and"] = true, ["or"] = true, the = true }
local LEAD = { all = true, any = true } -- (only before the first area word: "in all Forest areas")
local CLOSERS = { area = true, areas = true, region = true, regions = true, zone = true, zones = true }
local ENDS = { ["while"] = true, when = true, during = true, ["for"] = true, ["if"] = true, by = true }

--- A word's key for its species: lowercase, a plural's s off ("trolls" troll, "harpies" harpy).
local function Stem(w)
	w = Lower(w)
	if CREATURE_OF[w] then return CREATURE_OF[w] end
	if #w > 4 and w:sub(-3) == "ies" then return w:sub(1, -4) .. "y" end
	if #w > 3 and w:sub(-1) == "s" and w:sub(-2) ~= "ss" then return w:sub(1, -2) end
	return w
end
BN.Stem = Stem

--- The area types one place list names, right after an " in " ("Marsh and Swamp areas while mounted"), or nil when it
--- isn't one ("Stormwind City", "the city of Ironforge").
local function PlaceList(clause, found)
	local any, closed, got = false, false, {}
	for word in clause:gmatch("[%a']+") do
		local k = AREA_OF[word]
		if k then
			got[#got + 1] = k
			any, closed = true, false
		elseif CLOSERS[word] and any then
			closed = true
		elseif JOIN[word] or (LEAD[word] and not any) then
			-- (joining: "Marsh and Swamp", "Forest areas and Swamp areas")
		elseif any and (closed or ENDS[word]) then
			break
		else
			return false
		end
	end
	if not any then return false end
	for _, k in ipairs(got) do found[k] = true end
	return true
end

local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

--- What one tooltip line gives a bonus for: adds area keys to `areas` and creature keys to `foes` (key -> its word as
--- the tooltip writes it).
function BN.ReadLine(text, areas, foes)
	if type(text) ~= "string" or text == "" then return end
	local plain = Plain(text)
	local low = Lower(plain)
	if low:find('^%s*"') then return end -- (flavour text is quoted: never a bonus)
	-- places: each " in " followed by a list of area types only
	local from = 1
	while true do
		local _, b = low:find(" in ", from, true)
		if not b then break end
		local clause = low:sub(b + 1):match("^[^%.;:,%(]*") or ""
		PlaceList(clause, areas)
		from = b
	end
	-- foes: the word after "against", "when fighting", "done to" (a leading "the" passed over)
	local same = #low == #plain -- (an English line lowercases byte for byte: the word's own capitals can be read)
	for _, lead in ipairs(FOE_LEADS) do
		local at = 1
		while true do
			local _, b = low:find(lead, at, true)
			if not b then break end
			at = b + 1
			local s = b + 1
			local the = low:match("^the%s+", s)
			if the then s = s + #the end
			local word = low:match("^[%a'%-]+", s)
			if word then
				word = word:gsub("'s$", ""):gsub("'$", "")
				local key = CREATURE_OF[word]
				local shown = same and plain:sub(s, s + #word - 1) or word
				if not key and same and shown:find("^%u") and not NOT_CREATURE[word] and #word > 2 then key = Stem(word) end
				if key and not foes[key] then foes[key] = shown end
			end
		end
	end
end

-- item id -> its bonuses ({ { key = "haunted", area = true }, { key = "undead" } ... }), or false: none. Kept for good
-- (a tooltip's text doesn't change); an item still loading isn't kept. Only gear, weapons and consumables are read (a
-- tooltip per item: AtlasLoot's thousands of recipes and materials never have one).
local kept = {}
local labels = {} -- a creature key -> how its first tooltip wrote it ("Undead", "Trolls")
local READ = { [0] = true, [2] = true, [4] = true } -- (Consumable, Weapon, Armor)
F.ClearBonuses = function() kept = {} end
function BN.ForgetForTests() kept, labels = {}, {} end

local function Lines(id)
	local TI = C_TooltipInfo
	if not (TI and TI.GetItemByID) then return nil end
	local ok, info = pcall(TI.GetItemByID, id)
	if not (ok and type(info) == "table" and type(info.lines) == "table") then return nil end
	return info.lines
end

--- An item's bonuses (a list, or false for none), or nil while the game is still loading it (asked for; F.loading set,
--- the search runs again once it's in).
function BN.Of(id)
	if type(id) ~= "number" then return false end
	local c = kept[id]
	if c ~= nil then return c end
	local get = C_Item and C_Item.GetItemInfoInstant
	if get then
		local ok, iid, _, _, _, _, classID = pcall(get, id)
		if ok and iid == id and type(classID) == "number" and not READ[classID] then
			kept[id] = false
			return false
		end
	end
	local cached = C_Item and C_Item.IsItemDataCachedByID
	if cached then
		local ok, yes = pcall(cached, id)
		if ok and yes == false then
			if F.MayAsk(id) and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			F.loading = true
			return nil
		end
	end
	local lines = Lines(id)
	if not lines then return false end
	local areas, foes = {}, {}
	for i, l in ipairs(lines) do
		local t = type(l) == "table" and l.leftText
		if type(t) == "string" and not Secret(t) then
			-- (a tooltip still coming in: "Retrieving item information", or no name yet)
			if (i == 1 and t == "") or (RETRIEVING_ITEM_INFO and t == RETRIEVING_ITEM_INFO) then
				F.loading = true
				return nil
			end
			if i > 1 then BN.ReadLine(t, areas, foes) end
		end
	end
	local out = {}
	for _, a in ipairs(BN.AREAS) do if areas[a.key] then out[#out + 1] = { key = a.key, area = true } end end
	local fk = {}
	for key, shown in pairs(foes) do
		fk[#fk + 1] = key
		if not labels[key] then labels[key] = ns.UpperFirst(shown) end
	end
	table.sort(fk)
	for _, key in ipairs(fk) do out[#out + 1] = { key = key } end
	c = #out > 0 and out or false
	kept[id] = c
	return c
end

--- A row's item's bonuses (its own item, or what a recipe makes), or nil: none, or still loading.
function BN.OfRow(e)
	local id = F.ItemOf(e)
	local c = id and BN.Of(id)
	return c or nil
end

--- How a bonus is said: "Haunted", "Strongholds and Cities", "Against Undead".
function BN.Label(b)
	if b.area then return AREA_BY_KEY[b.key].label end
	return L["Against %s"]:format(labels[b.key] or ns.UpperFirst(b.key))
end
-- a label said back -> its filter's value (a group's Enter: "Against Undead" -> bonus:undead)
local valueOf = {}
--- A row's bonuses said, each once ("| group by bonus"), or nil.
function BN.Labels(e)
	local list = BN.OfRow(e)
	if not list then return nil end
	local out = {}
	for i, b in ipairs(list) do
		local t = BN.Label(b)
		valueOf[t] = b.key
		out[i] = t
	end
	return out
end
--- The bonus: value a group's label stands for, or nil.
function BN.ValueOf(label) return label and valueOf[label] end

-- bonus:<what>: an area type (by any of its words), a creature or species (singular or plural, or the start of one:
-- bonus:dem), area / creature for any of those, any for either
local ANY_AREA = { area = true, areas = true, biome = true, biomes = true, zone = true, zones = true, place = true, places = true }
local ANY_FOE = { creature = true, creatures = true, foe = true, foes = true, species = true, enemy = true, enemies = true, target = true }
local function Test(v)
	v = Lower(v):gsub("[%s_%-]", "")
	if v == "" then return nil end
	if v == "any" or v == "all" or v == "bonus" then return function() return true end end
	if ANY_AREA[v] then return function(b) return b.area end end
	if ANY_FOE[v] then return function(b) return not b.area end end
	local area = AREA_OF[v] or (AREA_BY_KEY[v] and v)
	if area then return function(b) return b.area and b.key == area end end
	local want = Stem(v)
	-- (an area type's start, bonus:mount, bonus:cav; not one a creature starts with too: bonus:und is undead)
	local foe = false
	for w in pairs(CREATURE_OF) do if w:sub(1, #v) == v then foe = true break end end
	for _, a in ipairs(foe and {} or BN.AREAS) do
		for _, w in ipairs(a.words) do
			if #v >= 3 and w:sub(1, #v) == v then
				local key = a.key
				return function(b) return b.area and b.key == key end
			end
		end
	end
	return function(b) return not b.area and b.key:sub(1, #want) == want end
end
--- A bonus: filter said: "with a bonus in Haunted areas", "with a bonus against undead".
function BN.Say(v)
	v = Lower(v):gsub("[%s_%-]", "")
	if ANY_AREA[v] then return L["with an area bonus"] end
	if ANY_FOE[v] then return L["with a bonus against creatures"] end
	local area = AREA_OF[v] or (AREA_BY_KEY[v] and v)
	if area then return L["with a bonus in %s areas"]:format(AREA_BY_KEY[area].label) end
	if v == "any" or v == "all" or v == "bonus" then return L["with a bonus"] end
	return L["with a bonus against %s"]:format(v)
end
KEYS.bonus = function(v)
	local test = Test(v)
	if not test then return nil end
	return function(e)
		local list = BN.OfRow(e)
		if not list then return false end
		for _, b in ipairs(list) do if test(b) then return true end end
		return false
	end
end
KEYS.bonuses = KEYS.bonus
KEYS.biome = function(v) return KEYS.bonus(v) end
IS.bonus = function(e) return BN.OfRow(e) ~= nil end
IS.bonuses = IS.bonus

-- the values Tab offers, the lists they judge, .filters' line
do
	local V = F.VALUES
	V.bonus = { "area", "creature" }
	for _, a in ipairs(BN.AREAS) do V.bonus[#V.bonus + 1] = a.key end
	for _, k in ipairs({ "undead", "beast", "demon", "dragonkin", "elemental", "giant", "humanoid", "troll", "ogre", "naga" }) do
		V.bonus[#V.bonus + 1] = k
	end
	V.bonuses, V.biome = V.bonus, V.bonus
	V.is[#V.is + 1] = "bonus"
	local made = F.APPLIES.q["*"]
	F.APPLIES.bonus = { ["*"] = made }
	F.APPLIES.bonuses, F.APPLIES.biome = F.APPLIES.bonus, F.APPLIES.bonus
	F.APPLIES.is.bonus = made
	local at = #F.HELP + 1
	for i, h in ipairs(F.HELP) do if h[1] == "stat:stamina" then at = i + 1 break end end
	table.insert(F.HELP, at, { "bonus:haunted", L["gear whose bonus grows in an area type (forest swamp wasteland haunted mountainous snowy desert stronghold cavern volcanic; bonus:area: any) or against a creature (bonus:undead, bonus:beast, bonus:troll; bonus:creature: any); is:bonus: either. Read from the game's own tooltip text (English); | group by bonus"] })
end

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

-- Items the game hasn't loaded (most of AtlasLoot's: @loot bonus:troll; 1.8.5, the player: "why can I not look at @loot
-- that has bonuses against trolls / biome?"; a search asked 40 at most and waited 9 s, so @loot found next to nothing):
-- queued, asked of the server a batch at a time (BN.BATCH every BN.EVERY s, not in combat), and read as they come in;
-- the search shown is run again as they do (BN.REDO s apart at most) and its footer says how many are left. What was
-- read is kept across sessions for this client build (db.bonusIndex), so the next session's search is instant.
BN.BATCH, BN.EVERY, BN.REDO, BN.GIVE_UP = 40, 0.5, 2, 30
local queue, head, queued, waiting = {}, 1, {}, {} -- (ids in order, the next one's index, queued, asked: id -> when)
local nWaiting = 0
local pumping, redoAt, redoWaiting = false, 0, false
BN.wantedText = nil -- (the prompt a bonus: filter was made for: run again as items come in while it's still typed)

F.ClearBonuses = function() kept = {} end
function BN.ForgetForTests()
	kept, labels = {}, {}
	queue, head, queued, waiting, nWaiting, pumping = {}, 1, {}, {}, 0, false
	BN.wantedText, BN.loaded = nil, nil
end

-- (kept across sessions: "<build>" and the items read as "id=" (none) or "id=haunted,f:undead:Undead", one string; a new
-- client build reads them all again: a hotfix may reword a tooltip)
local function Build()
	local v, b = _G.GetBuildInfo and GetBuildInfo()
	return tostring(v or "?") .. "." .. tostring(b or "?")
end
BN.Build = Build
--- What an item's bonuses are written as, kept: "" (none), "haunted,f:undead:Undead".
local function Pack(list)
	if not list then return "" end
	local out = {}
	for _, b in ipairs(list) do
		out[#out + 1] = b.area and b.key or ("f:" .. b.key .. ":" .. (labels[b.key] or b.key):gsub("[,:;=]", ""))
	end
	return table.concat(out, ",")
end
local function Unpack(s)
	if s == "" then return false end
	local out = {}
	for part in s:gmatch("[^,]+") do
		local key, label = part:match("^f:([^:]+):(.*)$")
		if key then
			out[#out + 1] = { key = key }
			if label ~= "" and not labels[key] then labels[key] = label end
		elseif AREA_BY_KEY[part] then
			out[#out + 1] = { key = part, area = true }
		end
	end
	return #out > 0 and out or false
end
--- The items read in an earlier session of this build, back into the cache (once, when first asked).
function BN.LoadKept()
	if BN.loaded then return end
	BN.loaded = true
	local db = ns.db
	local x = db and db.bonusIndex
	if type(x) ~= "table" or x.build ~= Build() or type(x.items) ~= "string" then return end
	for id, s in x.items:gmatch("(%d+)=([^;]*)") do
		id = tonumber(id)
		if id and kept[id] == nil then kept[id] = Unpack(s) end
	end
end
--- Write what was read for the next session (at logout).
function BN.SaveKept()
	local db = ns.db
	if not db then return end
	BN.LoadKept() -- (an earlier session's, not read this session, kept too)
	local parts = {}
	for id, c in pairs(kept) do parts[#parts + 1] = id .. "=" .. Pack(c or nil) end
	table.sort(parts)
	db.bonusIndex = #parts > 0 and { build = Build(), items = table.concat(parts, ";") } or nil
end

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
	if not BN.loaded then BN.LoadKept() end
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
			BN.Queue(id)
			F.loading = true
			return nil
		end
	end
	return BN.Read(id)
end

--- Read an item the game has: its tooltip's bonuses, kept (nil: its tooltip is still coming in).
function BN.Read(id)
	local c
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

-- the search shown, run again once items came in (not more often than BN.REDO), while its line is still typed
local function Redo()
	local UI = ns.UI
	local now = GetTime()
	if redoWaiting then return end
	if now < redoAt then
		redoWaiting = true
		C_Timer.After(redoAt - now, function() redoWaiting = false; Redo() end)
		return
	end
	redoAt = now + BN.REDO
	if not (UI and UI.RedoQuietly and UI.IsShown and UI:IsShown() and BN.wantedText and UI.edit and UI.edit:GetText() == BN.wantedText) then return end
	UI:RedoQuietly()
end
BN.Redo = Redo

--- How many items are still to be read (queued or asked of the server).
function BN.Left() return (#queue - head + 1) + nWaiting end

local Pump
--- An item the game hasn't loaded: asked of the server in the background, read once it's in.
function BN.Queue(id)
	if queued[id] or waiting[id] then return end
	queued[id] = true
	queue[#queue + 1] = id
	if not pumping then pumping = true; C_Timer.After(0, Pump) end
end

local function Done(id, c)
	if waiting[id] then waiting[id] = nil; nWaiting = nWaiting - 1 end
	if c ~= nil then kept[id] = c end
end

Pump = function()
	if InCombatLockdown and InCombatLockdown() then return C_Timer.After(5, Pump) end
	local now, n = GetTime(), 0
	-- (asked long ago and never answered: let go; asked again next time a search meets it)
	for id, at in pairs(waiting) do if now - at > BN.GIVE_UP then Done(id) end end
	local read = false
	while n < BN.BATCH and head <= #queue do
		local id = queue[head]
		head = head + 1 -- (left in place: a hole at the front would make #queue unreliable)
		queued[id] = nil
		n = n + 1
		local cached = C_Item and C_Item.IsItemDataCachedByID
		local ok, yes = true, true
		if cached then ok, yes = pcall(cached, id) end
		if ok and yes == false then
			if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			waiting[id], nWaiting = now, nWaiting + 1
		elseif kept[id] == nil then
			BN.Read(id)
			read = true
		end
	end
	if head > #queue then queue, head = {}, 1 end -- (drained: a fresh table)
	if read then Redo() end
	if head <= #queue or nWaiting > 0 then
		C_Timer.After(BN.EVERY, Pump)
	else
		pumping = false
		Redo() -- (the last ones: the footer's count goes)
	end
end
BN.Pump = function() return Pump() end -- (tests)

-- the server's answers; and what was read, kept at logout
do
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "ITEM_DATA_LOAD_RESULT")
	pcall(f.RegisterEvent, f, "PLAYER_LOGOUT")
	f:SetScript("OnEvent", function(_, event, id, ok)
		if event == "PLAYER_LOGOUT" then return pcall(BN.SaveKept) end
		if type(id) ~= "number" or not waiting[id] then return end
		if ok == false then Done(id, false) -- (the server has no such item)
		else Done(id); BN.Read(id) end
		Redo()
	end)
	BN.frame = f -- (tests)
end

--- The footer's note while items are read: "reading 1,240 items' tooltips for bonuses", or nil.
function BN.Note()
	local left = BN.Left()
	if left <= 0 or not BN.wantedText then return nil end
	return L["reading %s items' tooltips for bonuses"]:format(ns.Thousands and ns.Thousands(left) or tostring(left))
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
local function Wanted()
	local UI = ns.UI
	BN.wantedText = UI and UI.edit and UI.edit.GetText and UI.edit:GetText() or nil
end
KEYS.bonus = function(v)
	local test = Test(v)
	if not test then return nil end
	Wanted()
	return function(e)
		local list = BN.OfRow(e)
		if not list then return false end
		for _, b in ipairs(list) do if test(b) then return true end end
		return false
	end
end
KEYS.bonuses = KEYS.bonus
KEYS.biome = function(v) return KEYS.bonus(v) end
IS.bonus = function(e)
	if not BN.wantedText then Wanted() end
	return BN.OfRow(e) ~= nil
end
IS.bonuses = IS.bonus

-- A bonus said in plain words, inside a longer line ("argent dawn rewards against trolls", "reputation rewards that deal
-- 2x damage to trolls", "rewards with a bonus in mountainous areas"): the bonus: filters it says, and the words left. The
-- words around one ("deal 2x damage", "with a bonus") are how it was said, not names to look for: FILLER, dropped
-- once a bonus was said (Query.lua's Simple-mode words too).
BN.FILLER = {}
for w in ([[deal deals dealing do does double doubled triple tripled quadrupled twice 2x 3x 4x x2 x3 extra damage
	effect effects bonus bonuses area areas grow grows growing have has with in a an the that which when]]):gmatch("%S+") do BN.FILLER[w] = true end
-- (an area type's word alone that no zone's name has: "mountainous rewards"; "swamp", "forest" want "bonus" or "areas")
local ALONE = { haunted = true, snowy = true, mountainous = true, volcanic = true, cavernous = true, wasteland = true, wastelands = true }
local FOE_WORD = { against = true, vs = true, versus = true, to = true, fighting = true }
local AREA_AFTER = { bonus = true, bonuses = true, area = true, areas = true }
--- The bonus: filters a list of (lowercase) words says, and the other words (none of FILLER when one was said).
function BN.Take(words)
	local specs, seen, rest = {}, {}, {}
	local function Add(v)
		if not seen[v] then seen[v] = true; specs[#specs + 1] = "bonus:" .. v end
	end
	local i = 1
	while i <= #words do
		local w, nx = words[i], words[i + 1]
		local nxs = nx and nx:gsub("'s$", "")
		if FOE_WORD[w] and nxs and (CREATURE_OF[nxs] or (w ~= "to" and w ~= "fighting" and #nxs > 2 and nxs:find("^%a+$")
			and not NOT_CREATURE[nxs] and not BN.FILLER[nxs] and not AREA_OF[nxs])) then
			Add(Stem(nxs)); i = i + 2
		elseif AREA_OF[w] and ((nx and AREA_AFTER[nx]) or words[i - 1] == "in" or ALONE[w]) then
			Add(AREA_OF[w]); i = i + 1
		elseif w == "biome" or w == "biomes" then
			Add("area"); i = i + 1
		else
			rest[#rest + 1] = w; i = i + 1
		end
	end
	if #specs == 0 then return specs, words end
	local left = {}
	for _, w in ipairs(rest) do if not BN.FILLER[w] then left[#left + 1] = w end end
	return specs, left
end

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
	local made = {}
	for _, k in ipairs(F.APPLIES.q["*"]) do made[#made + 1] = k end
	made[#made + 1] = "reputation" -- (its rewards: "@reputation is:reward bonus:troll")
	made[#made + 1] = "itemset" -- (a set's pieces)
	F.APPLIES.bonus = { ["*"] = made }
	F.APPLIES.bonuses, F.APPLIES.biome = F.APPLIES.bonus, F.APPLIES.bonus
	F.APPLIES.is.bonus = made
	local at = #F.HELP + 1
	for i, h in ipairs(F.HELP) do if h[1] == "stat:stamina" then at = i + 1 break end end
	table.insert(F.HELP, at, { "bonus:haunted", L["gear whose bonus grows in an area type (forest swamp wasteland haunted mountainous snowy desert stronghold cavern volcanic; bonus:area: any) or against a creature (bonus:undead, bonus:beast, bonus:troll; bonus:creature: any); is:bonus: either. Read from the game's own tooltip text (English); | group by bonus"] })
end

local ns = select(2, ...)

-- Filters for NPCs and places: Questie NPCs' roles (is:vendor...), trainer:, faction:, near:, sort:nearest, PvP NPCs,
-- sells:; where a row is (in:/zone:/from:) and who holds a stored item (on:).

local F = ns.Filters
local P = F._
local KEYS, IS = P.KEYS, P.IS
local Range = F.Range
local NpcID, NpcField = P.NpcID, P.NpcField
local ClearStanding = P.ClearStanding
local Generations, Keep, Kept, Forget = P.Generations, P.Keep, P.Kept, P.Forget
local Lower = ns.Lower

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
-- Compact rows (Questie's quests, AtlasLoot's items: thousands each) get no field written onto them (a row of 8 raw
-- fields grew to 16 slots after one in:): their texts' lowercase copies are kept here by the text itself (zones and
-- details repeat: "Lv 23  Ashenvale", "Garr  Molten Core"). NPC titles and holders' names too ("Warrior Trainer": a
-- few hundred titles over thousands of NPCs, each lowercased once instead of per row per keystroke).
local lowerTexts = Generations(P.CACHE_MAX)
local function LowerText(s)
	local l = lowerTexts.new[s] or Kept(lowerTexts, s)
	if not l then l = Keep(lowerTexts, s, Lower(s)) end
	return l
end
-- what a (lowercase) trainer title teaches, worked out once per title: a few hundred titles over thousands of NPCs, on
-- every keystroke of trainer:/is:classtrainer/is:proftrainer (false: nothing; ClassOf, ProfOf)
local titleClass, titleProf = Generations(P.CACHE_MAX), Generations(P.CACHE_MAX)
F.ClearPlaces = function()
	areaNames = {}
	Forget(lowerTexts); Forget(titleClass); Forget(titleProf)
end
--- The lowercase copy of a row's text field, kept on the row (like _ltext) while the field's text is the same; a
--- compact row's from LowerText.
local function LowerField(e, field, lkey, srcKey)
	local s = e[field]
	if type(s) ~= "string" then return nil end
	if rawget(e, "_compact") then return LowerText(s) end
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
			if type(h.who) == "string" and LowerText(h.who):find(v, 1, true) then return true end
		end
	end
	return false
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
F.ClearSold = function() itemNames, soldBy, soldCount = nil, {}, 0; ClearStanding() end

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
	sub = LowerText(sub)
	if sub:find("trainer", 1, true) or sub:find("instructor", 1, true) or NpcRole(e, "TRAINER") then return sub end
end

-- PvP NPCs (0.43.5): "nearby battlemaster" listed anything with "battle" in it, of either faction
local function NpcTitle(e)
	if not NpcID(e) then return nil end
	local sub = rawget(e, "sub") or NpcField(e, "subName")
	return type(sub) == "string" and sub ~= "" and LowerText(sub) or nil
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

-- "Warrior Trainer", "Undead Mage Trainer", "Master Mage", "Grand Master Rogue", "High Priest" (whole words)
local CLASS_FINDS = {}
for i, c in ipairs(CLASSES) do CLASS_FINDS[i] = "%f[%a]" .. c .. "%f[%A]" end
local function ClassOf(sub)
	local c = Kept(titleClass, sub)
	if c == nil then
		c = false
		for i = 1, #CLASSES do
			if sub:find(CLASS_FINDS[i]) then c = CLASSES[i] break end
		end
		Keep(titleClass, sub, c)
	end
	return c or nil
end

local function ProfOf(sub)
	local p = Kept(titleProf, sub)
	if p == nil then
		p = false
		for name, words in pairs(PROFS) do
			for _, w in ipairs(words) do
				if sub:find(w, 1, true) then p = name break end
			end
			if p then break end
		end
		Keep(titleProf, sub, p)
	end
	return p or nil
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

IS.classtrainer = AnyClassTrainer
IS.proftrainer = AnyProfTrainer
IS.battlemaster = Battlemaster
IS.pvpvendor = PvpVendor
IS.pvp = function(e) return Battlemaster(e) or PvpVendor(e) end
local ROLES = { vendor = "VENDOR", trainer = "TRAINER", flightmaster = "FLIGHT_MASTER", flight = "FLIGHT_MASTER",
	innkeeper = "INNKEEPER", inn = "INNKEEPER", banker = "BANKER", bank = "BANKER", repair = "REPAIR",
	auctioneer = "AUCTIONEER", questgiver = "QUEST_GIVER", stablemaster = "STABLEMASTER" }
for word, flag in pairs(ROLES) do IS[word] = function(e) return NpcRole(e, flag) end end
IS.professiontrainer = IS.proftrainer
IS.battlemasters, IS.honorvendor, IS.pvpvendors = IS.battlemaster, IS.pvpvendor, IS.pvpvendor

local ns = select(2, ...)

-- Filters for NPCs and places: Questie NPCs' roles (is:vendor...), trainer:, faction:, near:, sort:distance, PvP NPCs,
-- sells:; where a row is (in:/zone:/from:) and who holds a stored item (on:).

local F = ns.Filters
local P = F._
local KEYS, IS = P.KEYS, P.IS
local Range = F.Range
local NpcID, NpcField = P.NpcID, P.NpcField
local ClearStanding = P.ClearStanding
local Generations, Keep, Kept, Forget = P.Generations, P.Keep, P.Kept, P.Forget
local Lower = ns.Lower
local L = ns.L

--- Does the NPC have this role (Questie's npcFlags; its numbers differ between game versions)?
local function NpcRole(e, flagName)
	if not NpcID(e) then return false end
	local roles = rawget(e, "roles") -- (a row that says its own: TrainerSpells' trainers; 0.57.1)
	if roles then return roles[flagName] == true end
	local flags = NpcField(e, "npcFlags")
	if type(flags) ~= "number" then return false end -- (before asking for the database's flag names: most rows)
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
-- (a compact row's texts lowercased once each: Core.lua's LowerText)
local LowerText = P.LowerText
-- what a (lowercase) trainer title teaches, worked out once per title: a few hundred titles over thousands of NPCs, on
-- every keystroke of trainer:/is:classtrainer/is:proftrainer (false: nothing; ClassOf, ProfOf)
local titleClass, titleProf = Generations(P.CACHE_MAX), Generations(P.CACHE_MAX)
F.ClearPlaces = function()
	areaNames = {}
	P.ForgetLowerTexts(); Forget(titleClass); Forget(titleProf)
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
	-- (your own bags' rows say "x5  Backpack", "Bag 2": in:bags is them; 0.50.7, review: only @stored rows matched it)
	if e.firstBag ~= nil and ("bags"):find(v, 1, true) then return true end
	if e.noPlace then return false end -- (a list whose detail never says a place: Achievements)
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

--- Questie's items with exactly this (lowercase) name: their ids ({} when none, or without Questie). (Chains.lua: a
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

--- The plain in: test for a place's name: a row with it in its text or where it is (Places.lua's PlaceFilter ends in it;
--- review, 0.53.6: it parsed "in:<place>", which found the place again and made a second place filter inside it).
function F.InPlaceText(v) return function(e) return Places(e, v) end end

KEYS["in"] = function(v)
	if v == "" then return nil end
	-- a place Terminal knows by name (a zone, or a town in one: in:goldshire, in:ratchet, in:org): its NPCs by where
	-- they stand, as Simple mode's "vendor goldshire" (an NPC's zone alone says Elwynn Forest, never Goldshire)
	local I = ns.Integrations
	if I and I.FindPlace and I.PlaceFilter then
		local words = {}
		for w in v:gmatch("%S+") do words[#words + 1] = w end
		local place, rest = I.FindPlace(words)
		if place and rest and #rest == 0 then
			local ok, inPlace = pcall(I.PlaceFilter, place)
			if not ok then return function(e) return Places(e, v) end end
			-- (other rows: the place filter already ends in this same Places test, by the place's own name;
			-- NPCs: their zone by name too, as before)
			return function(e) return inPlace(e) or (NpcID(e) ~= nil and Places(e, v)) end
		end
	end
	return function(e) return Places(e, v) end
end
-- (your quest log: the heading a quest is listed under, its spaces and punctuation aside: in:"thunder bluff",
-- in:thunderbluff; a quest whose text names the place isn't in it. 0.63.5, the player: Alt+` on "untrack thunder bluff
-- quests" took in quests that only mention Thunder Bluff)
do
	local InPlace = KEYS["in"]
	KEYS["in"] = function(v)
		local base = InPlace(v)
		if not base then return nil end
		-- (the place's own name when it's one Terminal knows, or a shorthand's: in:rfc, in:tb, in:sw is Stormwind, not
		-- the Swamp of Sorrows; else the words as typed. 0.63.7, review)
		local wants = {}
		local I = ns.Integrations
		local words = {}
		for w in v:gmatch("%S+") do words[#words + 1] = w end
		local place, rest
		if I and I.FindPlace then place, rest = I.FindPlace(words) end
		if place and rest and #rest == 0 and place.name then
			wants[1] = ns.Norm(place.name)
		elseif ns.Shorthand and ns.Shorthand[ns.Lower(v)] then
			for _, name in ipairs(ns.Shorthand[ns.Lower(v)]) do wants[#wants + 1] = ns.Norm(name) end
		else
			wants[1] = ns.Norm(v)
		end
		return function(e)
			if e.kind == "quests" then
				local zone = ns.Norm(tostring(e.zone or ""))
				for _, want in ipairs(wants) do
					if want ~= "" and zone:find(want, 1, true) then return true end
				end
				return false
			end
			return base(e)
		end
	end
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

--- Your class as the trainers' titles write it ("warrior", "death knight"), from the game's class token; while
--- Terminal answers someone's !t question, theirs (Core/Ask.lua's ns.Asker).
local function MyClass()
	-- (WARRIOR: the same in every language. An asker whose class isn't known has none, not yours; 0.68.5, review)
	local token
	if ns.Asker then token = ns.Asker.class else token = UnitClass and select(2, UnitClass("player")) end
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

F.ProfNamed = ProfNamed -- (Simple mode: "enchanting trainer" is trainer:enchanting, Simple.lua)

local function AnyClassTrainer(e) local sub = TrainerTitle(e); return sub and ClassOf(sub) ~= nil or false end
local function AnyProfTrainer(e) local sub = TrainerTitle(e); return sub and ProfOf(sub) ~= nil or false end

-- weapon skills by the words for them (0.53.9, the player: "dagger trainer" found no one; weapon masters' titles say
-- "Weapon Master", not what they teach): their spell ids (What's Training's); the client's own names asked of the game
F.WEAPON_SKILLS = { dagger = { 1180 }, daggers = { 1180 }, sword = { 201, 202 }, swords = { 201, 202 }, axe = { 196, 197 },
	axes = { 196, 197 }, mace = { 198, 199 }, maces = { 198, 199 }, staff = { 227 }, staves = { 227 }, polearm = { 200 },
	polearms = { 200 }, bow = { 264 }, bows = { 264 }, gun = { 266 }, guns = { 266 }, crossbow = { 5011 }, crossbows = { 5011 },
	thrown = { 2567 }, fist = { 15590 }, fists = { 15590 }, fistweapon = { 15590 }, fistweapons = { 15590 } }
F.WEAPON_SKILL_IDS = { 1180, 201, 202, 196, 197, 198, 199, 227, 200, 264, 266, 5011, 2567, 15590 }
local weaponNames -- (the client's names, lowercase -> id; made once the game has them all)
--- The weapon skills a word names (a list of spell ids), or nil: "dagger", "swords", the client's own "dolche".
function F.WeaponSkillIds(w)
	if type(w) ~= "string" or w == "" then return nil end
	w = Lower(w)
	if F.WEAPON_SKILLS[w] then return F.WEAPON_SKILLS[w] end
	if #w < 4 then return nil end
	local names = weaponNames
	if not names then
		names = {}
		local all = true
		for _, id in ipairs(F.WEAPON_SKILL_IDS) do
			local n = ns.Str(ns.Safe(C_Spell and C_Spell.GetSpellName, id)) or ns.Str((ns.Safe(_G.GetSpellInfo, id)))
			if n then names[Lower(n)] = id else all = false end
		end
		if all then weaponNames = names end
	end
	local out
	for n, id in pairs(names) do
		if n == w or n:sub(1, #w) == w then out = out or {}; out[#out + 1] = id end
	end
	if out then table.sort(out) end
	return out
end
--- A word naming a weapon skill, as trainer: takes it (Simple mode: "dagger trainer" is trainer:dagger, Simple.lua), or nil.
F.TrainerWeapon = function(w) return F.WeaponSkillIds(w) and Lower(w) or nil end

local CLASS_SET = {}
for _, c in ipairs(CLASSES) do CLASS_SET[c] = true end
F.TrainerClass = function(w) return CLASS_SET[w] and w or nil end -- (Simple mode: "mage trainer" is trainer:mage, Simple.lua)

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
	-- a weapon skill (trainer:daggers): the weapon masters who teach it to your faction (What's Training's catalog:
	-- ClassSpells.lua); without What's Training, every weapon master
	local weapon = F.WeaponSkillIds(v)
	if weapon then
		local CS = ns.ClassSpells
		local masters = CS and CS.WeaponMasters and CS.WeaponMasters(weapon)
		if masters and next(masters) then
			return function(e) local id = NpcID(e); return id ~= nil and masters[id] == true end
		end
		return function(e) local t = NpcTitle(e); return t ~= nil and t:find("weapon master", 1, true) ~= nil end
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
	-- a class or profession in the client's language (trainer:bergbau): Questie's titles are English (Simple.lua's game words)
	local said = ns.Easy and ns.Easy.GameWord and ns.Easy.GameWord(v)
	if said and said:find("^trainer:") then return KEYS.trainer(said:sub(9)) end
	-- anything else: a word of the title (pet, riding, weapon, portal, demon...)
	return function(e)
		local sub = TrainerTitle(e)
		return sub and sub:find(v, 1, true) and true or false
	end
end

-- faction: who a Questie NPC is friendly to ("A", "H" or "AH"; most monsters have nothing); a flight path, whose
-- flight master it is (Flights.lua: "AH" for a neutral one)
local FACTION = { horde = { H = true, AH = true }, h = { H = true, AH = true },
	alliance = { A = true, AH = true }, a = { A = true, AH = true },
	neutral = { AH = true }, both = { AH = true } }
KEYS.faction = function(v)
	local want = FACTION[v]
	local mine = v == "friendly" or v == "mine" or v == "me"
	if not (want or mine) then return nil end
	local w -- (yours: asked once per search, not per row; review, 0.53.6)
	return function(e)
		local f
		if NpcID(e) then f = NpcField(e, "friendlyToFaction")
		elseif e.kind == "flight" then f = e.friendlyToFaction
		else return false end
		if type(f) ~= "string" then return false end
		if not w then
			w = want
			if mine then
				local g = ns.Str(ns.Safe(_G.UnitFactionGroup, "player"))
				w = FACTION[g == "Horde" and "horde" or g == "Alliance" and "alliance" or "neutral"]
			end
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
		if not (I and I.RowYards) or not (NpcID(e) or e.wcont) then return false end
		if here == nil then here = I.Here and I.Here() or false end
		-- (Questie's NPCs, and @mailbox rows; the yards alone: RowDistance made a spot table per NPC; 0.50.7, review)
		local d = here and I.RowYards(e, here)
		return d and r(d) or false
	end
end
KEYS.within, KEYS.dist = KEYS.near, KEYS.near

-- sort:distance: not a filter (every row stays); SearchText reads it and puts Questie NPCs closest first, with how far.
-- sort:plan: your recipes that still give skill, by how many times your materials make each (Search/Questions/Plan.lua)
-- sort:best: with is:upgrade, the biggest upgrades first (F.GainOf; Simple mode's "upgrades" sorts so on its own)
-- (0.65.7, the player: "sort:distance ideally", the nearest first; sort:-distance the farthest: as said, sort:farthest)
F.SORTS = { distance = "distance", dist = "distance", nearest = "distance", near = "distance", closest = "distance",
	farthest = "-distance", furthest = "-distance", far = "-distance",
	plan = "plan", leveling = "plan", levelling = "plan", best = "best", gain = "best",
	-- (0.55.1: by what the rows have, as Simple mode's bar sorts; Bar.lua's B.SortRows)
	name = "name", alpha = "name", az = "name", level = "level", lvl = "level", ilvl = "ilvl", itemlevel = "ilvl",
	quality = "quality", q = "quality", value = "value", worth = "value", count = "count", qty = "count",
	damage = "damage", hit = "damage", biggest = "damage", line = "line", lines = "line", owner = "owner", owners = "owner" }
-- the sorts that don't turn round: the plan's, the biggest upgrades (a field's do: sort:-level; distance too, 0.65.7)
local NO_REVERSE = { plan = true, best = true }
--- A sort's field and whether it's turned round: "-level" -> "level", true; "level" -> "level", false.
function F.SortParts(id)
	if type(id) == "string" and id:sub(1, 1) == "-" then return id:sub(2), true end
	return id, false
end
--- "level" -> "level", "-level" -> "-level" (the other way round, 0.65.5), "farthest" -> "-distance", "-farthest" ->
--- "distance"; else nil.
local function SortId(v)
	local neg, name = v:match("^(%-?)(%a+)$")
	local id = name and F.SORTS[Lower(name)]
	if not id then return nil end
	local base, rev = F.SortParts(id)
	if NO_REVERSE[base] then return neg == "" and id or nil end
	if neg == "-" then rev = not rev end
	return rev and ("-" .. base) or base
end
-- Sort by more than one field (0.66.4, the player): sort:quality,-level is by quality, then on a tie by level, the
-- lowest first; as many as typed. Distance too (0.66.16, the player's sort:level,distance: the level, the nearest first
-- among equals); plan and best sort their own ways, so they stand alone.
local NOT_THEN = { plan = true, best = true }
--- "quality,-level" -> "quality,-level" (each part as SortId says it), "nearest" -> "distance"; nil when a part isn't a
--- sort, or distance, plan or best are in a list of several.
local function SortIds(v)
	if not v:find(",", 1, true) then return SortId(v) end
	local out = {}
	for part in (v .. ","):gmatch("([^,]*),") do
		local id = part ~= "" and SortId(part)
		if not id or NOT_THEN[(F.SortParts(id))] then return nil end
		out[#out + 1] = id
	end
	return #out > 0 and table.concat(out, ",") or nil
end
--- A sort's parts: "quality,-level" -> { "quality", "-level" }; nil -> {}.
function F.SortList(id)
	local out = {}
	if type(id) ~= "string" then return out end
	for part in (id .. ","):gmatch("([^,]*),") do if part ~= "" then out[#out + 1] = part end end
	return out
end
KEYS.sort = function(v)
	if not SortIds(v) then return nil end
	return function() return true end
end
--- "sort:distance" -> "nearest", "sort:plan" -> "plan", "sort:-level" -> "-level" (the other way round),
--- "sort:quality,-level" -> "quality,-level", else nil.
function F.SortOf(word)
	if type(word) ~= "string" then return nil end
	local k, v = word:match("^(%a+):([%-%a,]+)$")
	if k and Lower(k) == "sort" then return SortIds(v) end
end
KEYS.sells = function(v)
	if v == "" then return nil end
	-- sells:upgrade: a vendor whose stock holds a clear upgrade for you (0.66.12; Rewards.lua's QR.VendorUpgrades)
	if v == "upgrade" or v == "upgrades" then
		local by
		return function(e)
			local id = NpcID(e)
			if not id then return false end
			if by == nil then
				local QR = ns.QuestRewards
				local asked, _n
				if QR and QR.VendorUpgrades then by, _n, asked = QR.VendorUpgrades() end
				by = by or false
				-- (items still coming from the server: searched again once they're in, as the answer is; review)
				if asked and asked > 0 then F.loading = true end
			end
			return by and by[id] ~= nil or false
		end
	end
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
-- weapon masters, by their title (0.56.8: "weapon master" alone)
IS.weaponmaster = function(e) local t = NpcTitle(e); return t ~= nil and t:find("weapon master", 1, true) ~= nil end
IS.weaponmasters = IS.weaponmaster
IS.pvpvendor = PvpVendor
IS.pvp = function(e) return Battlemaster(e) or PvpVendor(e) end
-- (flight and flightmaster: FlightMaster below, the flight paths' own test)
local ROLES = { vendor = "VENDOR", trainer = "TRAINER",
	innkeeper = "INNKEEPER", inn = "INNKEEPER", banker = "BANKER", bank = "BANKER", repair = "REPAIR",
	auctioneer = "AUCTIONEER", questgiver = "QUEST_GIVER", stablemaster = "STABLEMASTER" }
for word, flag in pairs(ROLES) do IS[word] = function(e) return NpcRole(e, flag) end end
-- spirit healers (0.50.5, the player's ask: "nearest spirit healer"): Questie's flag for them (its names for it differ by
-- version), else the Spirit Healer himself (6491) or one called that
local SPIRIT_IDS = { [6491] = true, [13116] = true, [13117] = true } -- (the Spirit Healer; the battlegrounds' Spirit Guides)
local SPIRIT_NAME, SPIRIT_LNAME = "spirit healer", Lower(L["Spirit Healer"])
function IS.spirithealer(e)
	local id = NpcID(e)
	if not id then return false end
	if SPIRIT_IDS[id] or NpcRole(e, "SPIRIT_HEALER") or NpcRole(e, "SPIRITHEALER") or NpcRole(e, "SPIRIT_GUIDE") then return true end
	-- (the row's own name, lowercased already: Questie's database asked for every NPC's name made each search slow;
	-- 0.50.7, review)
	local n = rawget(e, "_lname") or Lower(tostring(e.name or ""))
	return n == SPIRIT_NAME or n == SPIRIT_LNAME
end
IS.spirithealers, IS.graveyard = IS.spirithealer, IS.spirithealer
-- a flight path's row stands for its flight master (Flights.lua: "nearest unlearned flight master" lists them)
local function FlightMaster(e) return e.kind == "flight" or NpcRole(e, "FLIGHT_MASTER") end
IS.flight, IS.flightmaster = FlightMaster, FlightMaster
-- flight paths: learned or not, as a flight master's map (or the world map's data) said; one not checked yet counts as
-- not learned (it may be)
IS.flightpath = function(e) return e.kind == "flight" end
-- (0.45.14) recipes too: yours are learned; the ones you don't know yet (MissingRecipes.lua) aren't, and is:learnable
-- keeps those your skill already allows
-- (0.54.6: spells too, @spell listing the ones you don't know yet: is:known keeps to your spellbook, as @spell did before)
IS.learned = function(e)
	return (e.kind == "flight" and e.learned == true) or e.kind == "recipes" or e.kind == "spells"
		or (e.kind == "classspells" and rawget(e, "known") == true)
end
IS.unlearned = function(e)
	return (e.kind == "flight" and e.learned ~= true) or e.kind == "missing" or (e.kind == "classspells" and rawget(e, "known") ~= true)
end
IS.learnable = function(e) return e.kind == "missing" and e.canLearn == true end
IS.canlearn = IS.learnable
IS.flightpaths, IS.taxi = IS.flightpath, IS.flightpath
IS.known, IS.discovered = IS.learned, IS.learned
IS.missing, IS.undiscovered, IS.unknown = IS.unlearned, IS.unlearned, IS.unlearned
IS.professiontrainer = IS.proftrainer
IS.battlemasters, IS.honorvendor, IS.pvpvendors = IS.battlemaster, IS.pvpvendor, IS.pvpvendor

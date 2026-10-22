local ns = select(2, ...)
local L = ns.L

-- Simple and Advanced mode's examples, and the ones made for the character playing (split out of Easy.lua; they stay
-- on ns.Easy: E.EXAMPLES, E.ADV_EXAMPLES, E.rand, E.PersonalExamples, E.ExamplePool, E.NextExample, E.Example).

local E = ns.Easy

local Lower = ns.Lower
local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

----------------------------------------------------------------------
-- The empty prompt's faint examples (a different one each time it opens)
----------------------------------------------------------------------

-- Each with what it needs (an addon: "Questie", "AtlasLoot", "Attune", "WhatsTraining", "Syndicator" (a bag addon for your alts);
-- "guild", "group") and where it's most use ("city": a capital, or resting in a town; "field": out in the world;
-- "instance": in a dungeon or raid; none: anywhere). One whose addon isn't there isn't offered; the ones for where you
-- are come first, the others after (0.52.1, the player's ask: "nearest trainer, mailbox" in a city, "nearest dungeon,
-- best upgrades" outside; "if no Questie, no NPC suggestions").
E.SIMPLE = {
	-- in a city
	{ "nearest mailbox", "Questie", "city" }, { "nearest innkeeper", "Questie", "city" }, { "nearest repair", "Questie", "city" },
	{ "nearest auctioneer", "Questie", "city" }, { "nearest banker", "Questie", "city" }, { "nearby battlemaster", "Questie", "city" },
	{ "nearest pvp vendor", "Questie", "city" }, { "mining trainer in org", "Questie", "city" }, { "my auctions", nil, "city" },
	{ "my mail", nil, "city" }, { "what can i train", "WhatsTraining", "city" }, { "how much is training", "WhatsTraining", "city" },
	{ "recipes i can learn now", nil, "city" }, { "recipes i'm missing", nil, "city" },
	{ "mats for thorium belt", nil, "city" }, { "what uses copper bar", nil, "city" }, { "guild blacksmith", "guild", "city" },
	{ "rested xp", nil, "city" }, { "my lockouts", nil, "city" }, { "group browser", nil, "city" },
	-- out in the world
	{ "where should i quest", nil, "field" }, { "where should i level", nil, "field" }, { "quest upgrades", "Questie", "field" },
	{ "upgrades", nil, "field" }, { "nearest dungeon", nil, "field" }, { "what dungeon should i do", nil, "field" },
	{ "where should i fish", nil, "field" }, { "where is hogger", "Questie", "field" }, { "vendor goldshire", "Questie", "field" },
	{ "nearest spirit healer", "Questie", "field" }, { "nearest unlearned flight master", nil, "field" },
	{ "quests to drop", nil, "field" }, { "stamina food", nil, "field" }, { "attack power food", nil, "field" },
	{ "what should i auction", "Auctionator", "city" },
	{ "use hearthstone", nil, "field" }, { "durability", nil, "field" }, { "quests to turn in", nil, "field" },
	{ "quests here", "Questie", "field" }, { "quests per zone", "Questie", "field" }, { "track nearby quests", nil, "field" }, { "track completed quests", nil, "field" }, { "dungeons at my level", nil, "field" },
	-- in a dungeon
	{ "who needs fortitude", "group", "instance" }, { "missing buffs", "group", "instance" }, { "who is dead", "group", "instance" },
	{ "group healers", "group", "instance" }, { "what killed me", nil, "instance" }, { "repair cost", nil, "instance" },
	-- anywhere
	{ "what should i do" }, { "what can i craft" }, { "dance" }, { "rare sword" }, { "sword or axe" }, { "rare ring not boe" }, { "weapon damage" }, { "stormwind" }, { "gold" },
	{ "shield that drops from kresh", "AtlasLoot" }, { "where to get mageweave" }, { "unlearned flight paths" },
	{ "who priest undercity" }, { "online", "guild" }, { "spells not on my bars" }, { "what's on this week" },
	{ "next darkmoon faire" }, { "my attunements", "Attune" }, { "my keys", "Attune" }, { "attunements to do", "Attune" },
	{ "what do i learn next level", "WhatsTraining" }, { "upcoming spells", "WhatsTraining" }, { "spellid fireball" }, { "healing talents" },
	{ L["tip: F1 shows every key"], tip = true },
}
-- Advanced mode's: its syntax (@kinds, key:value filters, >> chat, .commands); one whose @kind isn't there (no Questie:
-- no @npc) isn't offered (Valid, below)
E.ADVANCED = {
	{ "@npc is:vendor in:barrens", "field" }, { "@gear slot:feet ilvl:20+" }, { "hogger >> party" },
	{ "@item q:rare+ is:boe" }, { "@questie lvl:20-25 in:ashenvale", "field" }, { "@item stat:sta>=10" },
	{ "@npc trainer:class faction:friendly", "city" }, { "@recipe stat:agility" }, { "linen cloth >> guild" },
	{ "@npc sells:coarse_thread", "city" }, { "@stored linen cloth", "city" }, { "@gold" }, { "@xp rested", "city" },
	{ "@achievement is:todo" }, { "@dungeon sort:nearest", "field" }, { "@flight is:unlearned sort:nearest", "field" },
	{ "@map fish:mine", "field" }, { "thorium belt > mats > alts", "city" }, { "mats for thorium belt >>> party", "city" },
	{ "copper bar > uses", "city" }, { "@map lvl:30", "field" }, { "@dungeon lvl:25", "field" }, { "@recipe is:skillup", "city" },
	{ "@friend is:online" }, { "@guild blacksmith", "city" }, { "@spell is:unplaced" }, { "@quest is:drop", "field" },
	{ "@recipe is:unknown", "city" }, { "@recipe is:learnable", "city" }, { "@training is:learnable | sum cost", "city" },
	{ "@training is:nextlevel" }, { "@spell class:druid lvl:30" }, { "@who orc lvl:20-30" }, { "@calendar is:holiday" },
	{ "@item is:boe|q:epic" }, { "@spell is:ready", "instance" }, { "@gear slot:head|chest -is:soulbound" },
	{ "@item q:rare|epic" }, { "@npc is:repair sort:nearest", "city" }, { "@npc trainer:mining near:500", "city" },
	{ "@loot is:upgrade sort:best", "field" }, { "@questie is:upgrade sort:best", "field" }, { "@group is:dead", "instance" },
	{ "@lockout is:raid", "city" }, { "@cvar changed" }, { ".filters (every key:value)" }, { ".theme dracula" },
	{ L["tip: Up = last command, Down = recent picks"], tip = true }, { L["tip: F1 shows every key"], tip = true },
}
local function Texts(list)
	local out = {}
	for _, x in ipairs(list) do out[#out + 1] = x.tip and x[1] or ("try: " .. x[1]) end
	return out
end
-- (every one, as shown: "try: ..." and the tips)
E.EXAMPLES, E.ADV_EXAMPLES = Texts(E.SIMPLE), Texts(E.ADVANCED) -- (tests)

-- Examples made for the character playing (their class, professions, bags, level, where they are, guild): mixed in
-- with the fixed ones, every other suggestion. Worked out from lists already built (never a big list on its own),
-- again after a minute or when the level or zone changed.
local SLOT_WORDS = { "helm", "boots", "gloves", "belt", "bracers", "cloak", "ring", "chest", "legs", "shoulders" }
local PRIMARY = { WARRIOR = "str", PALADIN = "str", DEATHKNIGHT = "str", ROGUE = "agi", HUNTER = "agi",
	MAGE = "int", WARLOCK = "int", PRIEST = "int", DRUID = "int", SHAMAN = "int" }
E.rand = math.random

--- A list's rows as last built, never built again here (0.53.1, the player: a CPU spike on opening: the suggestions'
--- list, made again a minute on, rebuilt your bags, quest log and professions each time). A few minutes old is fine for
--- a suggestion; a list never built yet (or let go) gives none this time.
local function Entries(id)
	local p = ns.providers[id]
	local list = p and rawget(p, "_entries")
	return type(list) == "table" and list or {}
end
local function Pick(list)
	if #list == 0 then return nil end
	return list[E.rand(1, #list)]
end
local function Short(s, n) return type(s) == "string" and s ~= "" and #s <= (n or 28) and s or nil end

--- A working Advanced example: its @kinds known, its filters parse (made from game data, so checked here).
local function Valid(ex)
	for w in ex:gmatch("%S+") do
		if w:sub(1, 1) == "@" and not ns:ResolveProvider(w:sub(2)) then return false end
		if w:find("^[-!]?%a+:%S") and not (ns.Filters and ns.Filters.Parse(w)) then return false end
	end
	return true
end

----------------------------------------------------------------------
-- Ammo (0.64.2, the player: "a melee with a bow or gun and no arrows or bullets: try: nearest vendor sells:arrow; a
-- hunter: when the quiver or ammo pouch is low")
----------------------------------------------------------------------

local WEAPON, PROJECTILE, QUIVER = 2, 6, 11 -- (item classes: Enum.ItemClass)
-- a bow or crossbow shoots arrows, a gun bullets (Enum.ItemWeaponSubclass; Enum.ItemProjectileSubclass 2 arrow, 3 bullet)
local SHOOTS = { [2] = "arrow", [18] = "arrow", [3] = "shot" }
local PROJECTILE_KIND = { [2] = "arrow", [3] = "shot" }
local HOLDS = { [2] = "arrow", [3] = "shot" } -- (a quiver holds arrows, an ammo pouch bullets: Enum.ItemQuiverSubclass)
E.AMMO_STACK = 200 -- (a stack of arrows or bullets, when the item doesn't say)
E.AMMO_LOW_SHARE, E.AMMO_LOW_MIN = 0.25, 200 -- (a hunter's ammo is low under a quarter of the quiver, or a stack)

local function ItemClass(id)
	local get = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
	if not (get and id) then return nil end
	local ok, _, _, _, _, _, classID, subClassID = pcall(get, id)
	if not ok then return nil end
	return Num(classID), Num(subClassID)
end
local function Equipped(slot) return GetInventoryItemID and Num(Safe(GetInventoryItemID, "player", slot)) end

--- What your ranged weapon shoots ("arrow", "shot"), or nil: none worn, a wand or a thrown one, or a game with no
--- ammo (no ammo slot: nothing to buy).
function E.AmmoKind()
	-- (a client with no ammo slot errors, or answers nothing: either way, nothing to buy)
	local ok, ammoSlot = false, nil
	if GetInventorySlotInfo then ok, ammoSlot = pcall(GetInventorySlotInfo, "AmmoSlot") end
	if not (ok and type(ammoSlot) == "number") then return nil end
	for _, slot in ipairs({ 18, 16 }) do -- (the ranged slot; a client with none: the main hand)
		local classID, sub = ItemClass(Equipped(slot))
		if classID == WEAPON and SHOOTS[sub] then return SHOOTS[sub] end
	end
	return nil
end

--- How much of that ammo is in your bags, and how much your quivers and ammo pouches hold (0: none).
function E.AmmoCount(kind)
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return 0, 0 end
	local have, room = 0, 0
	for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
		local slots = Num(Safe(C.GetContainerNumSlots, bag)) or 0
		for s = 1, slots do
			local info = Safe(C.GetContainerItemInfo, bag, s)
			local id = type(info) == "table" and Num(info.itemID)
			if id then
				local classID, sub = ItemClass(id)
				if classID == PROJECTILE and PROJECTILE_KIND[sub] == kind then have = have + (Num(info.stackCount) or 1) end
			end
		end
		-- (the bag itself: a quiver or an ammo pouch, its slots each a stack)
		if bag > 0 and C.ContainerIDToInventoryID then
			local inv = Num(Safe(C.ContainerIDToInventoryID, bag))
			local classID, sub = ItemClass(inv and Equipped(inv))
			-- (only the one for this ammo: an ammo pouch is no room for arrows; review, 0.64.3)
			if classID == QUIVER and HOLDS[sub] == kind then room = room + slots * E.AMMO_STACK end
		end
	end
	return have, room
end

--- The ammo to buy ("arrow", "shot"), or nil: a hunter whose ammo is low, anyone else with a bow or gun and none.
function E.AmmoNeed(classFile)
	local kind = E.AmmoKind()
	if not kind then return nil end
	local have, room = E.AmmoCount(kind)
	if classFile == "HUNTER" then
		if have < math.max(E.AMMO_LOW_MIN, room * E.AMMO_LOW_SHARE) then return kind end
		return nil
	end
	return have == 0 and kind or nil
end

----------------------------------------------------------------------
-- Reagents (0.64.4, the player: "try: nearest reagent vendor, if level is appropriate and if it is needed: priest
-- candles if none, paladin if empty on anything, mages, druids etc."). A class's spells that use one up, each as its
-- ranks in order with the reagent of each: the highest rank you know says which one you carry. Knowing the spell is the
-- level being right; none of it in your bags is the need. (Only what's cast often enough to keep on you: not feathers,
-- fish oil, infernal stones.)
----------------------------------------------------------------------

local HOLY_CANDLE, SACRED_CANDLE, SYMBOL_OF_DIVINITY, SYMBOL_OF_KINGS = 17028, 17029, 17033, 21177
local RUNE_OF_TELEPORTATION, RUNE_OF_PORTALS, ARCANE_POWDER, ANKH, FLASH_POWDER = 17031, 17032, 17020, 17030, 5140
local function Each(ids, item) local t = {} for _, id in ipairs(ids) do t[#t + 1] = { { id, item } } end return t end
local function Join(...) local t = {} for _, l in ipairs({ ... }) do for _, x in ipairs(l) do t[#t + 1] = x end end return t end
E.REAGENT_SPELLS = {
	PRIEST = {
		{ { 21562, HOLY_CANDLE }, { 21564, SACRED_CANDLE } }, -- Prayer of Fortitude
		{ { 27681, SACRED_CANDLE } }, -- Prayer of Spirit
		{ { 27683, SACRED_CANDLE } }, -- Prayer of Shadow Protection
	},
	PALADIN = Join({ { { 19752, SYMBOL_OF_DIVINITY } } }, -- Divine Intervention
		-- the Greater Blessings: Might, Wisdom, Kings, Salvation, Light, Sanctuary
		Each({ 25782, 25916, 25894, 25918, 25898, 25895, 25890, 25899 }, SYMBOL_OF_KINGS)),
	MAGE = Join(
		Each({ 3561, 3562, 3563, 3565, 3566, 3567 }, RUNE_OF_TELEPORTATION), -- the Teleports
		Each({ 10059, 11416, 11417, 11418, 11419, 11420 }, RUNE_OF_PORTALS), -- the Portals
		{ { { 23028, ARCANE_POWDER } } }), -- Arcane Brilliance
	DRUID = {
		{ { 20484, 17034 }, { 20739, 17035 }, { 20742, 17036 }, { 20747, 17037 }, { 20748, 17038 } }, -- Rebirth: its seeds
		{ { 21849, 17021 }, { 21850, 17026 } }, -- Gift of the Wild: Wild Berries, Wild Thornroot
	},
	SHAMAN = { { { 20608, ANKH } } }, -- Reincarnation
	ROGUE = { { { 1856, FLASH_POWDER }, { 1857, FLASH_POWDER } } }, -- Vanish
}
-- reagents a reagent vendor doesn't sell: "nearest vendor sells:<it>" instead (Flash Powder: poison suppliers;
-- release review, 0.64.6)
E.REAGENT_ELSEWHERE = { [FLASH_POWDER] = true }

--- An item as a sells: value: its name, lowercase, _ for the spaces (the client's language), else its id.
function E.SellsValue(id)
	local name = C_Item and C_Item.GetItemNameByID and Str(Safe(C_Item.GetItemNameByID, id))
	if not name and GetItemInfo then name = Str(Safe(GetItemInfo, id)) end
	return name and (Lower(name):gsub("%s+", "_")) or tostring(id)
end

local function BagCount(id)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	return f and Num(Safe(f, id, false)) or nil
end

--- The reagents your class's spells want and your bags have none of: their item ids, in the class's order, or nil.
function E.ReagentNeed(classFile)
	local chains = E.REAGENT_SPELLS[classFile or ""]
	local CS = ns.ClassSpells
	if not (chains and CS and CS.Known) then return nil end
	local out, seen = {}, {}
	for _, chain in ipairs(chains) do
		local item
		for i = #chain, 1, -1 do
			if CS.Known(chain[i][1]) then item = chain[i][2] break end
		end
		if item and not seen[item] then
			seen[item] = true
			if BagCount(item) == 0 then out[#out + 1] = item end
		end
	end
	return #out > 0 and out or nil
end

--- What the examples are made from: the character (level, class), its professions and consumables, a dungeon about
--- its level, where it is, its guild.
local function Gather()
	local f = {}
	f.level = UnitLevel and Num(Safe(UnitLevel, "player"))
	local className, classFile = Safe(UnitClass, "player")
	className, f.classFile = Str(className), Str(classFile)
	f.cls = className and Lower(className)
	-- professions you have (their rows' names; not their trade spells, Smelting: "nearest smelting trainer", "smelting
	-- skillup" found nothing; 0.49.2, review), and a consumable you carry
	local profs = {}
	for _, e in ipairs(Entries("professions")) do
		local n = not e.spellID and Short(e.name and Lower(e.name), 20)
		if n then profs[#profs + 1] = n end
	end
	f.prof = Pick(profs)
	f.carry = {}
	for _, e in ipairs(Entries("consumables")) do
		local n = Short(e.name and Lower(e.name), 24)
		if n then f.carry[#f.carry + 1] = n end
	end
	-- a dungeon about your level (WoW Forever's entrances)
	local fit = {}
	local I = ns.Integrations
	local level = f.level
	for _, d in ipairs(I and I.ENTRANCES or {}) do
		if level and not d[5] and d[6] and level >= d[6] - 3 and level <= d[7] then fit[#fit + 1] = Lower(d[1]):gsub(" %(.*%)$", "") end
	end
	f.dungeon = Pick(fit)
	local zoneName = GetRealZoneText and Str(Safe(GetRealZoneText))
	f.zone = Short(zoneName and Lower(zoneName), 22)
	f.inGuild = IsInGuild and Safe(IsInGuild)
	f.ammo = E.AmmoNeed(f.classFile)
	local need = E.ReagentNeed(f.classFile)
	for _, id in ipairs(need or {}) do
		if E.REAGENT_ELSEWHERE[id] then f.sells = f.sells or E.SellsValue(id) else f.reagents = true end
	end
	-- (what's to buy, as it was: a bag change made again only when it changes; E.OnBags)
	E.buyKey = E.BuyKey(f.ammo, need)
	-- the dungeon you're in (its loot: "the deadmines upgrades")
	local inside, kind = Safe(IsInInstance)
	if inside == true and (kind == "party" or kind == "raid") then
		f.instance = Short(Str(Safe(GetInstanceInfo)) and Lower(Str(Safe(GetInstanceInfo))), 30)
	end
	return f
end

-- Advanced mode's, each kept only if it works here (its @kinds known, its filters parse)
local function AdvancedExamples(f, add)
	local level, zone, prof = f.level, f.zone, f.prof
	if f.classFile and PRIMARY[f.classFile] then add("@gear stat:" .. PRIMARY[f.classFile] .. " is:upgrade", nil, "field") end
	if prof then add("@recipe is:skillup " .. prof, nil, "city"); add("@npc trainer:" .. prof:gsub(" ", "") .. " sort:nearest", nil, "city") end
	if f.inGuild then add("@guild is:online") end
	if level then add("@questie lvl:" .. level .. "-" .. (level + 2) .. (zone and (" in:" .. zone:gsub(" ", "_")) or ""), nil, "field") end
	if f.dungeon then add("@loot " .. f.dungeon .. " is:upgrade", nil, "field") end
	if f.instance then add("@loot " .. f.instance .. " is:upgrade", nil, "instance") end
	if f.ammo then add("@npc is:vendor sells:" .. f.ammo .. " faction:friendly sort:nearest", nil, nil, true) end
	if f.reagents then add("@npc reagent is:vendor faction:friendly sort:nearest", nil, nil, true) end
	if f.sells then add("@npc is:vendor sells:" .. f.sells .. " faction:friendly sort:nearest", nil, nil, true) end
end

local function SimpleExamples(f, add)
	local prof, dungeon = f.prof, f.dungeon
	-- (out of ammo, or a hunter's running low: where to buy it, offered more often than the rest)
	if f.ammo then add("nearest vendor sells:" .. f.ammo, "Questie", nil, true) end
	-- (out of a reagent your spells use: candles, symbols, runes, seeds, an ankh)
	if f.reagents then add("nearest reagent vendor", "Questie", nil, true) end
	if f.sells then add("nearest vendor sells:" .. f.sells, "Questie", nil, true) end -- (a reagent sold elsewhere)
	if f.cls then add("nearest " .. f.cls .. " trainer", "Questie", "city") end
	if prof then add(prof .. " skillup", nil, "city"); add("nearest " .. prof .. " trainer", "Questie", "city") end
	if #f.carry > 0 then add("use " .. Pick(f.carry), nil, "field") end
	if f.level and f.level < 60 then add(Pick(SLOT_WORDS) .. " upgrades", nil, "field") end
	if dungeon then add(dungeon, nil, "field"); add(dungeon .. " upgrades", "AtlasLoot", "field") end
	if f.instance then add(f.instance .. " upgrades", "AtlasLoot", "instance") end
	if f.zone then add("vendor " .. f.zone, "Questie", "field") end
	if f.inGuild then add("online") end
	add("nearest flight master", nil, "field")
	-- (Auctionator: what your bags would bring, from the lists as last read; the amount is a note, not typed)
	local AN = ns.Auctionator
	if AN and AN.On and AN.On() then
		local _, total = AN.ToPost(false)
		if total >= AN.WORTH_POSTING then add("what should i auction (" .. L["about %s"]:format(AN.About(total)) .. ")", "Auctionator", "city") end
		local mats = 0
		for _, e in ipairs(Entries("mats")) do mats = mats + (AN.ValueOf(e) or 0) end
		if mats >= AN.WORTH_POSTING then add("ah value of my mats (" .. L["about %s"]:format(AN.About(mats)) .. ")", "Auctionator", "city") end
	end
end

--- What an example needs is here: its addon installed, your guild, your group.
local function Has(need)
	if not need then return true end
	if need == "guild" then return Safe(IsInGuild) == true end
	if need == "group" then return Safe(IsInGroup) == true end
	local I = ns.Integrations
	return not (I and I.AddonMissing and I.AddonMissing(need))
end
E.HasForExample = Has

--- The character's own examples, tagged as the fixed ones are: { text, need, at, mine = true }, those it has the
--- addon (or guild, group) for.
local function Personal(advanced)
	local out = {}
	local f = Gather()
	local function add(s, need, at, urgent)
		if s and Has(need) and (not advanced or Valid(s)) then out[#out + 1] = { s, need, at, mine = true, todo = urgent or nil } end
	end
	if advanced then AdvancedExamples(f, add) else SimpleExamples(f, add) end
	return out
end
E.PersonalTagged = Personal
--- (as before: the texts, "try: ..."; tests)
function E.PersonalExamples(advanced)
	local out = {}
	for _, x in ipairs(Personal(advanced)) do out[#out + 1] = "try: " .. x[1] end
	return out
end

----------------------------------------------------------------------
-- Where you are, for which examples come first (0.52.1, the player's ask)
----------------------------------------------------------------------

-- the capitals' maps (and their parts: a city's own sub-maps have it as their parent)
local CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true,
	[1947] = true, [1954] = true, [1955] = true }
--- "instance" (a dungeon or raid), "city" (a capital), "town" (resting: an inn elsewhere), or "field" (out in the world).
function E.Place()
	local inside, kind = Safe(IsInInstance)
	if inside == true and (kind == "party" or kind == "raid") then return "instance" end
	local M = C_Map
	local map = M and M.GetBestMapForUnit and Num(Safe(M.GetBestMapForUnit, "player"))
	for _ = 1, 3 do
		if not map then break end
		if CAPITALS[map] then return "city" end
		local info = M.GetMapInfo and Safe(M.GetMapInfo, map)
		map = type(info) == "table" and Num(info.parentMapID) or nil
	end
	if Safe(IsResting) == true then return "town" end
	return "field"
end
-- how much more often an example for where you are comes up: { [where you are] = { [where it's for] = weight } }
E.PLACE_WEIGHT = {
	city = { city = 4, field = 0.6, instance = 0.4 },
	town = { city = 2.5, field = 2, instance = 0.4 },
	field = { city = 0.6, field = 4, instance = 0.6 },
	instance = { city = 0.4, field = 0.8, instance = 5 },
}
E.MINE_WEIGHT, E.TIP_WEIGHT = 1.5, 0.5
-- (0.61.4, the player: "it should be part of the random group", only more frequent) "what should i do" when there's
-- something worth doing (Suggest.lua's SG.Pressing: lists already read only)
E.TODO_WEIGHT = 4 -- (as an example for where you are)
E.rand01 = math.random

--- The examples to offer ({ text, need, at } each; tip, mine), those for where you are first: each once, in a weighted shuffle (each one's place a draw
--- weighted by how well it fits here; Efraimidis-Spirakis), so all of them come up, the fitting ones sooner.
function E.Ordered(list, place)
	local weights = E.PLACE_WEIGHT[place] or {}
	local keyed = {}
	for i, x in ipairs(list) do
		local at = x[3] -- ({ text, need, at })
		local w = x.tip and E.TIP_WEIGHT or ((at and weights[at] or 1) * (x.mine and E.MINE_WEIGHT or 1) * (x.todo and E.TODO_WEIGHT or 1))
		local u = E.rand01()
		if type(u) ~= "number" or u <= 0 then u = 1e-6 end
		keyed[#keyed + 1] = { x = x, k = u ^ (1 / w), i = i }
	end
	table.sort(keyed, function(a, b) if a.k ~= b.k then return a.k > b.k end return a.i < b.i end)
	local out = {}
	for _, e in ipairs(keyed) do out[#out + 1] = e.x end
	return out
end

local pool = { at = 0 }
--- What the examples are offered for: which addons are here, your guild and group (a change: made again).
local function Setup()
	local t = {}
	for _, n in ipairs({ "Questie", "AtlasLoot", "Attune", "WhatsTraining", "Syndicator", "guild", "group" }) do t[#t + 1] = Has(n) and "1" or "0" end
	return table.concat(t)
end
--- The list the suggestions come from: the fixed ones and the character's own, those this setup has, those for where
--- you are first (E.Ordered); made again after a minute, or when your level, zone, place or setup changed.
local function Pool()
	local adv = not E.On()
	local now = GetTime and GetTime() or 0
	local level = UnitLevel and Num(Safe(UnitLevel, "player"))
	local zone = GetRealZoneText and Str(Safe(GetRealZoneText))
	local place, setup = E.Place(), Setup()
	if pool.list and pool.adv == adv and pool.level == level and pool.zone == zone and pool.place == place
		and pool.setup == setup and now - (pool.made or 0) < 60 then
		return pool.list
	end
	-- (asked only when the pool is made again, a minute on: not on every open; release review, 0.63.0)
	local SG = ns.Suggest
	local pressing = false
	if not adv and SG and SG.Pressing then local ok, p = pcall(SG.Pressing); pressing = ok and p or false end
	local cands = {}
	for _, x in ipairs(adv and E.ADVANCED or E.SIMPLE) do
		-- (Advanced's: the second field is where; Simple's: what it needs, then where)
		local need, at = x[2], x[3]
		if adv then need, at = nil, x[2] end
		if x.tip or (Has(need) and (not adv or Valid(x[1]:gsub(" %b()$", "")))) then
			cands[#cands + 1] = { x[1], need, at, tip = x.tip, todo = pressing and x[1] == "what should i do" or nil }
		end
	end
	local ok, mine = pcall(Personal, adv)
	for _, x in ipairs(ok and type(mine) == "table" and mine or {}) do cands[#cands + 1] = x end
	local list = {}
	for _, x in ipairs(E.Ordered(cands, place)) do list[#list + 1] = x.tip and x[1] or ("try: " .. x[1]) end
	if #list == 0 then list[1] = L["tip: F1 shows every key"] end
	pool.list, pool.adv, pool.level, pool.zone, pool.place, pool.setup, pool.made = list, adv, level, zone, place, setup, now
	pool.at = 0 -- (made again: from its first, the ones for here)
	return list
end
E.ExamplePool = Pool
--- What's to buy, as one string: the ammo, then the reagents ("arrow|17028,17033"; "|" for nothing).
function E.BuyKey(ammo, reagents)
	return (ammo or "") .. "|" .. table.concat(reagents or {}, ",")
end
--- Is what's to buy different from what the pool was made with? (The pool made again when it is: the ammo bought, its
--- suggestion goes; run out, it comes; review, 0.64.3: it stayed up to a minute. Release review, 0.64.6: not made
--- again on every bag change while one is up, which reshuffled the examples on every arrow shot.)
function E.CheckBuy()
	if E.buyKey == nil or (InCombatLockdown and InCombatLockdown()) then return false end
	local _, classFile = Safe(UnitClass, "player")
	classFile = Str(classFile)
	if E.BuyKey(E.AmmoNeed(classFile), E.ReagentNeed(classFile)) == E.buyKey then return false end
	pool.made = nil
	return true
end
--- Your bags changed (or combat ended): checked a moment later, once for a burst of changes.
local checking = false
function E.OnBags()
	if checking or E.buyKey == nil then return end
	checking = true
	local function Run() checking = false E.CheckBuy() end
	if C_Timer and C_Timer.After then C_Timer.After(1, Run) else Run() end
end
--- The pool made again on the next look (tests).
function E.ResetPool() pool.made = nil end
do
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
	pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function() E.OnBags() end)
end
-- a fresh install (nothing run from the prompt yet): the first suggestion is the tour, once (0.51.16, the player's ask)
E.TOUR_EXAMPLE = "try: .tour"
function E.NextExample()
	local db = ns.db
	pool.first = nil
	-- (spent when it's shown, E.ExampleShown: not on an open with suggestions off or with text typed; review, 0.51.25)
	if type(db) == "table" and not db.tourOffered and #(db.history or {}) == 0 then
		pool.first = E.TOUR_EXAMPLE
		return pool.first
	end
	local list = Pool()
	pool.at = pool.at % #list + 1
	return list[pool.at]
end
--- The example in the empty prompt was drawn (Completion.lua): the tour's is offered once.
function E.ExampleShown(ex)
	if ex == E.TOUR_EXAMPLE and type(ns.db) == "table" then ns.db.tourOffered = true end
end
function E.Example()
	if pool.first then return pool.first end
	local list = Pool()
	return list[(math.max(1, pool.at) - 1) % #list + 1]
end

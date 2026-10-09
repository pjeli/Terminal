local ns = select(2, ...)

-- Simple and Advanced mode's examples, and the ones made for the character playing (split out of Easy.lua; they stay
-- on ns.Easy: E.EXAMPLES, E.ADV_EXAMPLES, E.rand, E.PersonalExamples, E.ExamplePool, E.NextExample, E.Example).

local E = ns.Easy

local Lower = ns.Lower
local Safe, Str, Num = ns.Safe, ns.Str, ns.Num

----------------------------------------------------------------------
-- The empty prompt's faint examples (a different one each time it opens)
----------------------------------------------------------------------

E.EXAMPLES = {
	"try: stamina food", "try: nearest innkeeper", "try: use hearthstone", "try: dance", "try: rare sword",
	"try: where is hogger", "try: nearest repair", "try: shield that drops from kresh",
	"try: attack power food", "try: vendor goldshire", "try: mining trainer in org", "try: stormwind", "try: gold", "try: rested xp",
	"try: nearest mailbox", "try: nearest dungeon", "try: sword or axe", "try: rare ring not boe", "try: group browser",
	"try: who priest undercity", "try: weapon damage", "try: online", "try: where should i level",
	"try: what dungeon should i do", "try: where should i fish", "try: nearby battlemaster", "try: nearest pvp vendor",
	"try: what killed me", "try: mats for thorium belt", "try: what uses copper bar", "try: where to get mageweave",
	"try: nearest unlearned flight master", "try: unlearned flight paths", "try: guild blacksmith",
}
-- Advanced mode's: its syntax (@kinds, key:value filters, >> chat, .commands)
E.ADV_EXAMPLES = {
	"try: @npc is:vendor in:barrens", "try: @gear slot:feet ilvl:20+", "try: hogger >> party",
	"try: @item q:rare+ is:boe", "try: @questie lvl:20-25 in:ashenvale", "try: @item stat:sta>=10",
	"try: @npc trainer:class faction:friendly", "try: @recipe stat:agility", "try: linen cloth >> guild",
	"try: @npc sells:coarse_thread", "try: @stored linen cloth", "try: @gold", "try: @xp rested", "try: @achievement is:todo",
	"try: @dungeon sort:nearest", "try: @flight is:unlearned sort:nearest", "try: @map fish:mine", "try: thorium belt > mats > alts", "try: mats for thorium belt >>> party", "try: copper bar > uses", "try: @map lvl:30", "try: @dungeon lvl:25", "try: @recipe is:skillup", "try: @friend is:online", "try: @guild blacksmith", "try: @who orc lvl:20-30",
	"try: @item is:boe|q:epic", "try: @spell is:ready", "try: @gear slot:head|chest -is:soulbound", "try: @item q:rare|epic", "try: @npc is:repair sort:nearest", "try: @npc trainer:mining near:500", "try: @cvar changed", "try: .filters (every key:value)", "try: .theme dracula",
	"tip: Up = last command, Down = recent picks",
}
-- Examples made for the character playing (their class, professions, bags, level, where they are, guild): mixed in
-- with the fixed ones, every other suggestion. Worked out from lists already built (never a big list on its own),
-- again after a minute or when the level or zone changed.
local SLOT_WORDS = { "helm", "boots", "gloves", "belt", "bracers", "cloak", "ring", "chest", "legs", "shoulders" }
local PRIMARY = { WARRIOR = "str", PALADIN = "str", DEATHKNIGHT = "str", ROGUE = "agi", HUNTER = "agi",
	MAGE = "int", WARLOCK = "int", PRIEST = "int", DRUID = "int", SHAMAN = "int" }
E.rand = math.random

local function Entries(id)
	local p = ns.providers[id]
	if not p then return {} end
	local ok, list = pcall(ns.GetEntries, ns, p)
	return ok and type(list) == "table" and list or {}
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

--- What the examples are made from: the character (level, class), its professions and consumables, a dungeon about
--- its level, where it is, its guild.
local function Gather()
	local f = {}
	f.level = UnitLevel and Num(Safe(UnitLevel, "player"))
	local className, classFile = Safe(UnitClass, "player")
	className, f.classFile = Str(className), Str(classFile)
	f.cls = className and Lower(className)
	-- professions you have (their rows' names), and a consumable you carry
	local profs = {}
	for _, e in ipairs(Entries("professions")) do
		local n = Short(e.name and Lower(e.name), 20)
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
	return f
end

-- Advanced mode's, each kept only if it works here (its @kinds known, its filters parse)
local function AdvancedExamples(f, add, out)
	local level, zone, prof = f.level, f.zone, f.prof
	if f.classFile and PRIMARY[f.classFile] then add("@gear stat:" .. PRIMARY[f.classFile] .. " is:upgrade") end
	if prof then add("@recipe is:skillup " .. prof); add("@npc trainer:" .. prof:gsub(" ", "") .. " sort:nearest") end
	if f.inGuild then add("@guild is:online") end
	if level then add("@questie lvl:" .. level .. "-" .. (level + 2) .. (zone and (" in:" .. zone:gsub(" ", "_")) or "")) end
	if f.dungeon then add("@loot " .. f.dungeon .. " is:upgrade") end
	local kept = {}
	for _, ex in ipairs(out) do if Valid(ex:gsub("^try: ", "")) then kept[#kept + 1] = ex end end
	return kept
end

local function SimpleExamples(f, add, out)
	local prof, dungeon = f.prof, f.dungeon
	if f.cls then add("nearest " .. f.cls .. " trainer") end
	if prof then add(prof .. " skillup"); add("nearest " .. prof .. " trainer") end
	if #f.carry > 0 then add("use " .. Pick(f.carry)) end
	if f.level and f.level < 60 then add(Pick(SLOT_WORDS) .. " upgrades") end
	if dungeon then add(dungeon); add(dungeon .. " upgrades") end
	if f.zone then add("vendor " .. f.zone) end
	if f.inGuild then add("online") end
	add("nearest flight master")
	return out
end

function E.PersonalExamples(advanced)
	local out = {}
	local function add(s) if s then out[#out + 1] = "try: " .. s end end
	local f = Gather()
	if advanced then return AdvancedExamples(f, add, out) end
	return SimpleExamples(f, add, out)
end

local function Examples() return E.On() and E.EXAMPLES or E.ADV_EXAMPLES end
local pool = { at = 0 }
--- The list the suggestions come from: the character's own examples between the fixed ones (one of each in turn).
local function Pool()
	local adv = not E.On()
	local now = GetTime and GetTime() or 0
	local level = UnitLevel and Num(Safe(UnitLevel, "player"))
	local zone = GetRealZoneText and Str(Safe(GetRealZoneText))
	if pool.list and pool.adv == adv and pool.level == level and pool.zone == zone and now - (pool.made or 0) < 60 then return pool.list end
	local fixed, mine = Examples(), {}
	local ok, got = pcall(E.PersonalExamples, adv)
	if ok and type(got) == "table" then mine = got end
	local list, i, j = {}, 1, 1
	while i <= #fixed or j <= #mine do
		if j <= #mine then list[#list + 1] = mine[j]; j = j + 1 end
		if i <= #fixed then list[#list + 1] = fixed[i]; i = i + 1 end
	end
	pool.list, pool.adv, pool.level, pool.zone, pool.made = list, adv, level, zone, now
	return list
end
E.ExamplePool = Pool
function E.NextExample()
	local list = Pool()
	pool.at = pool.at % #list + 1
	return list[pool.at]
end
function E.Example()
	local list = Pool()
	return list[(math.max(1, pool.at) - 1) % #list + 1]
end

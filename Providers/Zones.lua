local ns = select(2, ...)
local L = ns.L

-- Level bands: each zone's level range (Z.LEVELS, Terminal's own list, its sources in docs/DATA_SOURCES.md) and the
-- fishing skill it needs (Z.FISHING, made by tests/gen_data.py from Mangos Zero's fishing table).
-- Used for the map rows' detail ("Lv 18-30"), `lvl:` on zones and dungeons, and three questions in plain words:
--   "where should i level" (or quest): zones for your level, quests there at your level, best fit and nearest first;
--   "what dungeon should i do": dungeons for your level (raids: "what raid should i do");
--   "where should i fish": zones your fishing skill is enough for, the best first, then the next ones to unlock.
-- A level said in the question is used instead of yours ("zones for level 35", "dungeon for 25").

local Z = {}
ns.Zones = Z

local Safe, Secret = ns.Safe, ns.Secret

-- Each zone's level range: { uiMap, min level, max level, name } (cities: no range, only fishing). The classic zones'
-- as warcraft.wiki.gg's "Zones by level (Classic)" gives them; WoW Forever's own as its pages and Blizzard's news say
-- them (docs/DATA_SOURCES.md). Shen'dralas has no published range yet: not listed until it has one.
Z.LEVELS = {
	-- Eastern Kingdoms
	{ 1416, 30, 40, "Alterac Mountains" },
	{ 1417, 30, 40, "Arathi Highlands" },
	{ 1418, 35, 45, "Badlands" },
	{ 1419, 45, 55, "Blasted Lands" },
	{ 1428, 50, 58, "Burning Steppes" },
	{ 1430, 55, 60, "Deadwind Pass" },
	{ 1426, 1, 10, "Dun Morogh" },
	{ 1431, 18, 30, "Duskwood" },
	{ 1423, 53, 60, "Eastern Plaguelands" },
	{ 1429, 1, 10, "Elwynn Forest" },
	{ 1424, 20, 35, "Hillsbrad Foothills" },
	{ 1455, nil, nil, "Ironforge" },
	{ 1432, 10, 20, "Loch Modan" },
	{ 1433, 15, 25, "Redridge Mountains" },
	{ 1427, 45, 50, "Searing Gorge" },
	{ 1421, 10, 20, "Silverpine Forest" },
	{ 1453, nil, nil, "Stormwind City" },
	{ 1434, 30, 45, "Stranglethorn Vale" },
	{ 1435, 35, 45, "Swamp of Sorrows" },
	{ 1425, 40, 50, "The Hinterlands" },
	{ 1420, 1, 10, "Tirisfal Glades" },
	{ 1458, nil, nil, "Undercity" },
	{ 1436, 10, 20, "Westfall" },
	{ 1422, 51, 58, "Western Plaguelands" },
	{ 1437, 20, 30, "Wetlands" },
	-- Kalimdor
	{ 1440, 18, 30, "Ashenvale" },
	{ 1447, 45, 55, "Azshara" },
	{ 1439, 10, 20, "Darkshore" },
	{ 1457, nil, nil, "Darnassus" },
	{ 1443, 30, 40, "Desolace" },
	{ 1411, 1, 10, "Durotar" },
	{ 1445, 35, 45, "Dustwallow Marsh" },
	{ 1448, 48, 55, "Felwood" },
	{ 1444, 40, 50, "Feralas" },
	{ 1450, nil, nil, "Moonglade" },
	{ 1412, 1, 10, "Mulgore" },
	{ 1454, nil, nil, "Orgrimmar" },
	{ 1451, 55, 60, "Silithus" },
	{ 1442, 15, 27, "Stonetalon Mountains" },
	{ 1446, 40, 50, "Tanaris" },
	{ 1438, 1, 10, "Teldrassil" },
	{ 1413, 10, 25, "The Barrens" },
	{ 1441, 25, 35, "Thousand Needles" },
	{ 1456, nil, nil, "Thunder Bluff" },
	{ 1449, 48, 55, "Un'Goro Crater" },
	{ 1452, 53, 60, "Winterspring" },
	-- WoW Forever's own
	{ 2482, 60, 60, "Hyjal" },
	{ 2521, 1, 12, "Zephras Isle" },
	{ 2548, 35, 45, "Riverglades" },
}

-- The fishing skill each zone needs, and a higher one in places (its isles, lakes, coves): { skill, in places }.
-- generated: tests/gen_data.py fishing (do not edit by hand)
Z.FISHING = {
	[1416] = { 130, nil }, -- Alterac Mountains (area 36)
	[1417] = { 130, nil }, -- Arathi Highlands (area 45)
	[1428] = { 330, nil }, -- Burning Steppes (area 46)
	[1430] = { 330, nil }, -- Deadwind Pass (area 41)
	[1426] = { 1, nil }, -- Dun Morogh (area 1)
	[1431] = { 55, nil }, -- Duskwood (area 10)
	[1423] = { 330, nil }, -- Eastern Plaguelands (area 139)
	[1429] = { 1, nil }, -- Elwynn Forest (area 12)
	[1424] = { 55, nil }, -- Hillsbrad Foothills (area 267)
	[1455] = { 1, nil }, -- Ironforge (area 1537)
	[1432] = { 1, nil }, -- Loch Modan (area 38)
	[1433] = { 55, nil }, -- Redridge Mountains (area 44)
	[1421] = { 1, nil }, -- Silverpine Forest (area 130)
	[1453] = { 1, nil }, -- Stormwind City (area 1519)
	[1434] = { 130, 205 }, -- Stranglethorn Vale (area 33)
	[1435] = { 130, nil }, -- Swamp of Sorrows (area 8)
	[1425] = { 205, nil }, -- The Hinterlands (area 47)
	[1420] = { 1, nil }, -- Tirisfal Glades (area 85)
	[1458] = { 1, nil }, -- Undercity (area 1497)
	[1436] = { 1, nil }, -- Westfall (area 40)
	[1422] = { 205, nil }, -- Western Plaguelands (area 28)
	[1437] = { 55, nil }, -- Wetlands (area 11)
	[1440] = { 55, nil }, -- Ashenvale (area 331)
	[1447] = { 205, 330 }, -- Azshara (area 16)
	[1439] = { 1, nil }, -- Darkshore (area 148)
	[1457] = { 1, nil }, -- Darnassus (area 1657)
	[1443] = { 130, nil }, -- Desolace (area 405)
	[1411] = { 1, nil }, -- Durotar (area 14)
	[1445] = { 130, nil }, -- Dustwallow Marsh (area 15)
	[1448] = { 205, nil }, -- Felwood (area 361)
	[1444] = { 205, 330 }, -- Feralas (area 357)
	[1450] = { 205, nil }, -- Moonglade (area 493)
	[1412] = { 1, nil }, -- Mulgore (area 215)
	[1454] = { 1, nil }, -- Orgrimmar (area 1637)
	[1451] = { 330, nil }, -- Silithus (area 1377)
	[1442] = { 55, nil }, -- Stonetalon Mountains (area 406)
	[1446] = { 205, nil }, -- Tanaris (area 440)
	[1438] = { 1, nil }, -- Teldrassil (area 141)
	[1413] = { 1, nil }, -- The Barrens (area 17)
	[1441] = { 130, nil }, -- Thousand Needles (area 400)
	[1456] = { 1, nil }, -- Thunder Bluff (area 1638)
	[1449] = { 205, nil }, -- Un'Goro Crater (area 490)
	[1452] = { 330, nil }, -- Winterspring (area 618)
}
-- end of generated: fishing

-- { uiMap, min level, max level, fishing skill, fishing skill in places (a higher one: pools, deeper water), name }
Z.LIST = {}
for _, z in ipairs(Z.LEVELS) do
	local f = Z.FISHING[z[1]]
	Z.LIST[#Z.LIST + 1] = { z[1], z[2], z[3], f and f[1], f and f[2], z[4] }
end

local byMap = {}
for _, z in ipairs(Z.LIST) do
	byMap[z[1]] = { ui = z[1], min = z[2], max = z[3], fish = z[4], fishHigh = z[5], name = z[6] }
end

--- A zone's record by its uiMap ({ ui, min, max, fish, fishHigh, name }), or nil.
function Z.Of(ui) return byMap[ui] end

--- "Lv 18-30" (a single level: "Lv 60"), or nil for a zone with no level range.
function Z.LevelText(z)
	if not (z and z.min) then return nil end
	return z.min == z.max and L["Lv %d"]:format(z.min) or L["Lv %d-%d"]:format(z.min, z.max)
end

local function FishText(z)
	if not (z and z.fish) then return nil end
	return z.fishHigh and L["Fishing %d (%d in places)"]:format(z.fish, z.fishHigh) or L["Fishing %d"]:format(z.fish)
end

----------------------------------------------------------------------
-- The questions
----------------------------------------------------------------------

local CUES = { should = true, best = true, good = true, recommend = true, recommended = true, suggest = true, next = true,
	which = true, what = true, zone = true, zones = true }
-- ("fishing spots", "leveling spots": a place word is a cue too, but only for fishing and levelling: "dungeon
-- locations", "quest areas" stay searches)
local PLACE_CUES = { spot = true, spots = true, hole = true, holes = true, pool = true, pools = true, location = true,
	locations = true, places = true, areas = true }
local PLACE_ASKS = { fish = true, fishing = true, level = true, leveling = true, levelling = true, lvl = true, xp = true,
	exp = true, grind = true, grinding = true }
local LEVEL_WORDS = { level = true, leveling = true, levelling = true, lvl = true, quest = true, questing = true,
	quests = true, xp = true, exp = true, grind = true, grinding = true }
local DUNGEON_WORDS = { dungeon = true, dungeons = true, instance = true, instances = true }
local RAID_WORDS = { raid = true, raids = true }
local FISH_WORDS = { fish = true, fishing = true }

-- every word a question may use (any other word makes it a search: "where to fish in feralas", "best sword")
local ASKS = {}
for w in ([[where should i can do to go what which whats wheres best good next for my me a an the am im now in at
	is are would you recommend recommended suggest zone zones place places area areas level leveling levelling lvl quest
	questing quests xp exp grind grinding dungeon dungeons instance instances raid raids fish fishing run try
	please some lv right spot spots hole holes pool pools location locations upgrade upgrades]]):gmatch("%S+") do ASKS[w] = true end

--- What a line of plain words asks, if it's one of the questions: "level", "dungeon", "raid" or "fish", and the
--- level said in it (nil: yours). nil when it isn't one.
function Z.Question(text)
	local line = ns.QuestionText(text)
	if not line then return nil end
	local t, has, level = {}, {}, nil
	for w in line:gmatch("%S+") do
		local n = tonumber(w)
		if n then
			if n >= 1 and n <= 80 and n == math.floor(n) then level = n else return nil end
		elseif not ASKS[w] then
			return nil -- (a word no question uses: a search, "where do i turn in hogger")
		end
		t[#t + 1] = w
		has[w] = true
	end
	if #t < 2 then return nil end -- ("dungeon" alone is a search, not a question)
	local function any(set) for _, w in ipairs(t) do if set[w] then return true end end return false end
	-- "where should i ...", "where to ...", "where can i ...", "where do i ..."
	local where = has.where and (has.should or has.to or has.can or has["do"])
	-- ("dungeons at my level", 0.61.0: as "for my level"; "quests at my level" stays a search)
	local at = has.at and (any(DUNGEON_WORDS) or any(RAID_WORDS)) and not (has.quest or has.quests) -- ("dungeon quests at my level": a search)
	local cue = where or any(CUES) or (has["for"] or at) and (has.my or has.me or level) or (any(PLACE_CUES) and any(PLACE_ASKS))
	if not cue then return nil end
	-- ("best dungeon for upgrades", 0.61.0: the dungeon for your level; "quest upgrades" are QuestUpgrades.lua's)
	-- (and asked which: "best dungeon for upgrades"; "dungeon upgrades for my level" stays is:upgrade's search; release
	-- review, 0.63.0)
	if (has.upgrade or has.upgrades) and not ((any(DUNGEON_WORDS) or any(RAID_WORDS)) and any(CUES)) then return nil end
	if any(FISH_WORDS) then return "fish", level end
	if any(DUNGEON_WORDS) then return "dungeon", level end
	if any(RAID_WORDS) then return "raid", level end
	if any(LEVEL_WORDS) or (where and has.go) then
		-- "where is quest x" isn't asked here: it needs a cue word, and "where" alone isn't one
		return "level", level
	end
	if (has.zone or has.zones) and (has["for"] or has.should) then return "level", level end
	return nil
end

local function PlayerLevel()
	if ns.Asker then return ns.Asker.level end -- (a !t question: the asker's level, Core/Ask.lua)
	local l = UnitLevel and Safe(UnitLevel, "player")
	return type(l) == "number" and not Secret(l) and l > 0 and l or nil
end

--- Your fishing skill, or nil when you haven't learned Fishing (or the game won't say).
function Z.FishingSkill()
	if not (GetProfessions and GetProfessionInfo) then return nil end
	local slots = { Safe(GetProfessions) }
	local function Rank(idx)
		if idx == nil or Secret(idx) then return nil end
		local _, _, rank, _, _, _, line = Safe(GetProfessionInfo, idx)
		if Secret(rank) then return nil end
		return tonumber(rank), line
	end
	local r = Rank(slots[4]) -- (the fishing slot)
	if r then return r end
	for i = 1, 8 do
		local rank, line = Rank(slots[i])
		if rank and line == 356 then return rank end
	end
	return nil
end

-- where you are, and how far a zone's middle is from there (yards, same continent only)
local function Distance(ui, here)
	local I = ns.Integrations
	if not (here and I and I.SpotXY) then return nil end
	local cont, x, y = I.SpotXY(ui, { 50, 50 })
	if not cont or cont ~= here.cont then return nil end
	local dx, dy = x - here.x, y - here.y
	return math.sqrt(dx * dx + dy * dy)
end

local function ZoneName(z)
	local I = ns.Integrations
	return (I and I.ZoneName and I.ZoneName(z.ui)) or z.name
end

-- Questie's quests at a level, per zone name (cached per level until the quest list changes): those of a level
-- from 2 below to 3 above, not done yet, for your race and class (when Questie says).
local questCounts = {}
local function RaceClassBits()
	local race = UnitRace and select(3, Safe(UnitRace, "player"))
	local class = UnitClass and select(3, Safe(UnitClass, "player"))
	return type(race) == "number" and 2 ^ (race - 1) or nil, type(class) == "number" and 2 ^ (class - 1) or nil
end
local function Allows(mask, bitv)
	if type(mask) ~= "number" or mask == 0 or not bitv or not (_G.bit and _G.bit.band) then return true end
	return _G.bit.band(mask, bitv) ~= 0
end
--- A Questie quest at your level (2 below to 3 above), not done, for your race and class: a test for its rows.
function Z.QuestFitter(level)
	local QD = ns.QuestieData
	local DB = QD and QD.DB and QD.DB()
	local raceBit, classBit = RaceClassBits()
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	return function(q)
		local lv = rawget(q, "level")
		if type(lv) ~= "number" or lv < level - 2 or lv > level + 3 then return false end
		local id = rawget(q, "key")
		if done and Safe(done, id) then return false end
		if DB and DB.QueryQuestSingle then
			return Allows(Safe(DB.QueryQuestSingle, id, "requiredRaces"), raceBit)
				and Allows(Safe(DB.QueryQuestSingle, id, "requiredClasses"), classBit)
		end
		return true
	end
end

function Z.QuestCounts(level)
	local p = ns.providers.questie
	if not (p and level) then return nil end
	local list = ns:GetEntries(p)
	if #list == 0 then return nil end
	-- (until Questie's list or your quest log is made again, a quest turned in: not every time any list is; review,
	-- 0.57.7: entriesGen counts every list's, and @quests is read again on every open)
	local qp = ns.providers.quests
	local log = qp and rawget(qp, "_entries") or false
	local c = questCounts[level]
	if c and c.list == list and c.log == log then return c.counts end
	local fits = Z.QuestFitter(level)
	local counts = {}
	for _, q in ipairs(list) do
		local zone = rawget(q, "zone")
		if zone and fits(q) then counts[zone] = (counts[zone] or 0) + 1 end
	end
	questCounts[level] = { list = list, log = log, counts = counts }
	return counts
end

-- a zone row that opens the map on it (the game's map key / macro, as @map rows do)
local function ZoneRow(z, detail, score, dist)
	local M = ns.Maps
	local p = ns.providers.maps -- (shown and remembered as the zone's own @map row: its label, its pick count)
	return {
		name = ZoneName(z), key = M.Key(z.ui), kind = "maps", mapID = z.ui, icon = "Interface\\Icons\\INV_Misc_Map_01",
		kindLabel = p and ns:KindLabel(p) or nil, freqKey = ns:FreqKey("maps", M.Key(z.ui)),
		detail = detail, _score = score, _pos = nil, _dist = dist,
		secure = M and M.SECURE, isOpen = M and M.IsOpenFor, after = M and M.ShowAfter, activate = M and M.Direct,
		secondary = M and M.PinOnly,
	}
end

local function Join(parts) return table.concat(parts, ns.DETAIL_SEP) end

local function Fit(level, lo, hi)
	if level >= lo and level <= hi then return L["right for you"], 2 end
	if level < lo then return L["a bit high for you"], 1 end
	return L["nearly outgrown"], 0
end

local function Order(a, b)
	if a._score ~= b._score then return a._score > b._score end
	if (a._dist ~= nil) ~= (b._dist ~= nil) then return a._dist ~= nil end
	if a._dist and b._dist and a._dist ~= b._dist then return a._dist < b._dist end
	return a.name < b.name
end

local function Ranked(rows)
	table.sort(rows, Order)
	-- the list's order is the answer: scores counting down, so a later sort keeps it
	ns.ScoreInOrder(rows)
	return rows
end

local function Here()
	local I = ns.Integrations
	return I and I.Here and I.Here() or nil
end

--- Zones for a level: in its range (best centred first), then up to 2 below it, nearly done; nearest first among equals.
local function LevelRows(level)
	local here, counts = Here(), Z.QuestCounts(level)
	local rows = {}
	for _, z in ipairs(Z.LIST) do
		local zz = byMap[z[1]]
		if zz.min and level >= zz.min - 2 and level <= zz.max + 2 then
			local label, tier = Fit(level, zz.min, zz.max)
			local centre = math.abs(level - (zz.min + zz.max) / 2)
			local parts = { Z.LevelText(zz) }
			local n = counts and counts[ZoneName(zz)] or counts and counts[zz.name]
			if n and n > 0 then parts[#parts + 1] = (n == 1 and L["%d quest at your level"] or L["%d quests at your level"]):format(n) end
			parts[#parts + 1] = label
			rows[#rows + 1] = ZoneRow(zz, Join(parts), tier * 1000 - centre * 10 + (n and math.min(n, 30) or 0) / 10,
				Distance(zz.ui, here))
		end
	end
	return Ranked(rows)
end

--- Dungeons (or raids) for a level: the entrance rows (@dungeon / @raid) whose range fits, best first, one per
--- instance (the nearest entrance of one with two).
local function InstanceRows(level, raids)
	local p = ns.providers[raids and "raid" or "dungeon"]
	if not p then return {} end
	local here = Here()
	local I = ns.Integrations
	local best = {}
	for _, e in ipairs(ns:GetEntries(p)) do
		local lo, hi = e.minLevel, e.level
		if type(lo) == "number" and type(hi) == "number" and level >= lo - 3 and level <= hi + 1 then
			local d = I and I.RowDistance and I.RowDistance(e, here) or nil
			local b = best[e.name]
			if not b or (d and (not b.d or d < b.d)) then best[e.name] = { e = e, d = d } end
		end
	end
	local rows = {}
	for _, b in pairs(best) do
		local e, d = b.e, b.d
		local label, tier = Fit(level, e.minLevel, e.level)
		local centre = math.abs(level - (e.minLevel + e.level) / 2)
		local lv = e.minLevel == e.level and L["Lv %d"]:format(e.level) or L["Lv %d-%d"]:format(e.minLevel, e.level)
		local parts = { lv, label }
		if e.zone then parts[#parts + 1] = e.zone end
		rows[#rows + 1] = setmetatable({ detail = Join(parts), _score = tier * 1000 - centre * 10, _dist = d },
			{ __index = e })
	end
	return Ranked(rows)
end

--- Fishing: zones your skill is enough for, the most demanding first (the best catches), then the next two to unlock.
local function FishRows(skill)
	local here = Here()
	local ok, next = {}, {}
	for _, z in ipairs(Z.LIST) do
		local zz = byMap[z[1]]
		if zz.fish then
			local parts = { FishText(zz) }
			if not skill or zz.fish <= skill then
				if zz.fishHigh and skill and zz.fishHigh > skill then parts[#parts + 1] = L["deeper spots need %d"]:format(zz.fishHigh) end
				if Z.LevelText(zz) then parts[#parts + 1] = Z.LevelText(zz) end
				ok[#ok + 1] = ZoneRow(zz, Join(parts), skill and zz.fish or -zz.fish, Distance(zz.ui, here))
			else
				parts[#parts + 1] = L["needs %d"]:format(zz.fish)
				if Z.LevelText(zz) then parts[#parts + 1] = Z.LevelText(zz) end
				next[#next + 1] = ZoneRow(zz, Join(parts), -zz.fish, Distance(zz.ui, here))
			end
		end
	end
	Ranked(ok)
	table.sort(next, Order)
	-- (the next ones to unlock: the lowest requirement first, at most two of them)
	local rows = ok
	local shown, last = 0, nil
	for _, r in ipairs(next) do
		local need = byMap[r.mapID].fish
		if shown < 2 or need == last then
			rows[#rows + 1] = r
			if need ~= last then shown = shown + 1 end
			last = need
		end
	end
	ns.ScoreInOrder(rows)
	return rows
end

--- The answer to a question (Z.Question): rows, and the footer's note ("Zones for level 23", "Your fishing: 150").
--- The question as Advanced mode writes it (Alt+`): "@map lvl:20", "@dungeon lvl:35", "@map fish:mine".
--- (0.55.7: kept as said, nil: the zones, dungeons and raids are ranked by how well they fit your level, and fishing
--- spots by the catches, which no filter does: "@map lvl:23" listed only exact fits, in another order. Search.lua's
--- ns.QuestionToAdvanced)
function Z.ToAdvanced() return nil end

function Z.Answer(kind, said)
	local level = said or PlayerLevel()
	if kind == "fish" then
		local skill = Z.FishingSkill()
		local note = skill and L["Your fishing: %d"]:format(skill) or L["You haven't learned Fishing: a fishing trainer teaches it"]
		return FishRows(skill), note
	end
	if not level then return {}, L["Your level isn't known here"] end
	if kind == "dungeon" then return InstanceRows(level, false), L["Dungeons for level %d"]:format(level) end
	if kind == "raid" then
		local rows = InstanceRows(level, true)
		return rows, (#rows == 0 and L["Raids are for level 60"] or L["Raids for level %d"]:format(level))
	end
	return LevelRows(level), L["Zones for level %d"]:format(level)
end

local ns = select(2, ...)

-- Level bands: each zone's level range and the fishing skill it needs, from Leatrix Maps' zone levels (its world map's
-- "Show zone levels" table, WoW Forever's own zones included; copied: it lives in Leatrix Maps' private namespace).
-- Used for the map rows' detail ("Lv 18-30"), `lvl:` on zones and dungeons, and three questions in plain words:
--   "where should i level" (or quest): zones for your level, quests there at your level, best fit and nearest first;
--   "what dungeon should i do": dungeons for your level (raids: "what raid should i do");
--   "where should i fish": zones your fishing skill is enough for, the best first, then the next ones to unlock.
-- A level said in the question is used instead of yours ("zones for level 35", "dungeon for 25").

local Z = {}
ns.Zones = Z

local Safe, Str, Secret = ns.Safe, ns.Str, ns.Secret

-- { uiMap, min level, max level, fishing skill, fishing skill in places (a higher one: pools, deeper water), name }
-- (cities: no level range, only fishing)
Z.LIST = {
	-- Eastern Kingdoms
	{ 1416, 30, 40, 130, nil, "Alterac Mountains" },
	{ 1417, 30, 40, 130, nil, "Arathi Highlands" },
	{ 1418, 35, 45, nil, nil, "Badlands" },
	{ 1419, 45, 55, nil, nil, "Blasted Lands" },
	{ 1428, 50, 58, 330, nil, "Burning Steppes" },
	{ 1430, 55, 60, 330, nil, "Deadwind Pass" },
	{ 1426, 1, 10, 1, nil, "Dun Morogh" },
	{ 1431, 18, 30, 55, nil, "Duskwood" },
	{ 1423, 53, 60, 330, nil, "Eastern Plaguelands" },
	{ 1429, 1, 10, 1, nil, "Elwynn Forest" },
	{ 1424, 20, 30, 55, nil, "Hillsbrad Foothills" },
	{ 1455, nil, nil, 1, nil, "Ironforge" },
	{ 1432, 10, 20, 1, nil, "Loch Modan" },
	{ 1433, 15, 25, 55, nil, "Redridge Mountains" },
	{ 1427, 43, 50, nil, nil, "Searing Gorge" },
	{ 1421, 10, 20, 1, nil, "Silverpine Forest" },
	{ 1453, nil, nil, 1, nil, "Stormwind City" },
	{ 1434, 30, 45, 130, 205, "Stranglethorn Vale" },
	{ 1435, 35, 45, 130, nil, "Swamp of Sorrows" },
	{ 1425, 40, 50, 205, nil, "The Hinterlands" },
	{ 1420, 1, 10, 1, nil, "Tirisfal Glades" },
	{ 1458, nil, nil, 1, nil, "Undercity" },
	{ 1436, 10, 20, 1, nil, "Westfall" },
	{ 1422, 51, 58, 205, nil, "Western Plaguelands" },
	{ 1437, 20, 30, 55, nil, "Wetlands" },
	-- Kalimdor
	{ 1440, 18, 30, 55, nil, "Ashenvale" },
	{ 1447, 45, 55, 205, 330, "Azshara" },
	{ 1439, 10, 20, 1, nil, "Darkshore" },
	{ 1457, nil, nil, 1, nil, "Darnassus" },
	{ 1443, 30, 40, 130, nil, "Desolace" },
	{ 1411, 1, 10, 1, nil, "Durotar" },
	{ 1445, 35, 45, 130, nil, "Dustwallow Marsh" },
	{ 1448, 48, 55, 205, nil, "Felwood" },
	{ 1444, 40, 50, 205, 330, "Feralas" },
	{ 1450, nil, nil, 205, nil, "Moonglade" },
	{ 1412, 1, 10, 1, nil, "Mulgore" },
	{ 1454, nil, nil, 1, nil, "Orgrimmar" },
	{ 1451, 55, 60, 330, nil, "Silithus" },
	{ 1442, 15, 27, 55, nil, "Stonetalon Mountains" },
	{ 1446, 40, 50, 205, nil, "Tanaris" },
	{ 1438, 1, 10, 1, nil, "Teldrassil" },
	{ 1413, 10, 25, 1, nil, "The Barrens" },
	{ 1441, 25, 35, 130, nil, "Thousand Needles" },
	{ 1456, nil, nil, 1, nil, "Thunder Bluff" },
	{ 1449, 48, 55, 205, nil, "Un'Goro Crater" },
	{ 1452, 55, 60, 330, nil, "Winterspring" },
	-- WoW Forever's own
	{ 2482, 60, 60, nil, nil, "Hyjal" },
	{ 2521, 1, 12, nil, nil, "Zephras Isle" },
	{ 2548, 35, 45, nil, nil, "Riverglades" },
	{ 2652, 35, 45, nil, nil, "Shen'dralas" },
}

local byMap = {}
for _, z in ipairs(Z.LIST) do
	byMap[z[1]] = { ui = z[1], min = z[2], max = z[3], fish = z[4], fishHigh = z[5], name = z[6] }
end

--- A zone's record by its uiMap ({ ui, min, max, fish, fishHigh, name }), or nil.
function Z.Of(ui) return byMap[ui] end

--- "Lv 18-30" (a single level: "Lv 60"), or nil for a zone with no level range.
function Z.LevelText(z)
	if not (z and z.min) then return nil end
	return z.min == z.max and ("Lv " .. z.min) or ("Lv " .. z.min .. "-" .. z.max)
end

local function FishText(z)
	if not (z and z.fish) then return nil end
	return "Fishing " .. z.fish .. (z.fishHigh and (" (" .. z.fishHigh .. " in places)") or "")
end

----------------------------------------------------------------------
-- The questions
----------------------------------------------------------------------

local CUES = { should = true, best = true, good = true, recommend = true, recommended = true, suggest = true, next = true,
	which = true, what = true, zone = true, zones = true }
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
	please some lv right]]):gmatch("%S+") do ASKS[w] = true end

--- What a line of plain words asks, if it's one of the questions: "level", "dungeon", "raid" or "fish", and the
--- level said in it (nil: yours). nil when it isn't one.
function Z.Question(text)
	if type(text) ~= "string" then return nil end
	-- Advanced syntax (@kind, key:value, >>, a|b, .command, /slash) is never a question
	if text:find("[@:>|]") or text:find("^%s*[%./!%-]") then return nil end
	local t, has, level = {}, {}, nil
	for w in ns.Lower(text):gsub("'", ""):gsub("[%p]", " "):gmatch("%S+") do
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
	local cue = where or any(CUES) or has["for"] and (has.my or has.me or level)
	if not cue then return nil end
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
function Z.QuestCounts(level)
	local p = ns.providers.questie
	if not (p and level) then return nil end
	local list = ns:GetEntries(p)
	if #list == 0 then return nil end
	local c = questCounts[level]
	if c and c.gen == ns.entriesGen and c.n == #list then return c.counts end
	local QD = ns.QuestieData
	local DB = QD and QD.DB and QD.DB()
	local raceBit, classBit = RaceClassBits()
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	local counts = {}
	for _, q in ipairs(list) do
		local lv, zone = rawget(q, "level"), rawget(q, "zone")
		if type(lv) == "number" and zone and lv >= level - 2 and lv <= level + 3 then
			local id = rawget(q, "key")
			local ok = not (done and Safe(done, id))
			if ok and DB and DB.QueryQuestSingle then
				ok = Allows(Safe(DB.QueryQuestSingle, id, "requiredRaces"), raceBit)
					and Allows(Safe(DB.QueryQuestSingle, id, "requiredClasses"), classBit)
			end
			if ok then counts[zone] = (counts[zone] or 0) + 1 end
		end
	end
	questCounts[level] = { gen = ns.entriesGen, n = #list, counts = counts }
	return counts
end

-- a zone row that opens the map on it (the game's map key / macro, as @map rows do)
local function ZoneRow(z, detail, score, dist)
	local M = ns.Maps
	return {
		name = ZoneName(z), key = "zone:" .. z.ui, kind = "maps", mapID = z.ui, icon = "Interface\\Icons\\INV_Misc_Map_01",
		detail = detail, _score = score, _pos = nil, _dist = dist, zoneAnswer = true,
		secure = M and M.SECURE, isOpen = M and M.IsOpenFor, after = M and M.ShowAfter, activate = M and M.Direct,
		secondary = M and M.PinOnly,
	}
end

local function Join(parts) return table.concat(parts, "  ·  ") end

local function Fit(level, lo, hi)
	if level >= lo and level <= hi then return "right for you", 2 end
	if level < lo then return "a bit high for you", 1 end
	return "nearly outgrown", 0
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
	for i, r in ipairs(rows) do r._score = 1e6 - i end
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
			if n and n > 0 then parts[#parts + 1] = n .. (n == 1 and " quest" or " quests") .. " at your level" end
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
		local lv = e.minLevel == e.level and ("Lv " .. e.level) or ("Lv " .. e.minLevel .. "-" .. e.level)
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
				if zz.fishHigh and skill and zz.fishHigh > skill then parts[#parts + 1] = "deeper spots need " .. zz.fishHigh end
				if Z.LevelText(zz) then parts[#parts + 1] = Z.LevelText(zz) end
				ok[#ok + 1] = ZoneRow(zz, Join(parts), skill and zz.fish or -zz.fish, Distance(zz.ui, here))
			else
				parts[#parts + 1] = "needs " .. zz.fish
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
	for i, r in ipairs(rows) do r._score = 1e6 - i end
	return rows
end

--- The answer to a question (Z.Question): rows, and the footer's note ("Zones for level 23", "Your fishing: 150").
function Z.Answer(kind, said)
	local level = said or PlayerLevel()
	if kind == "fish" then
		local skill = Z.FishingSkill()
		local note = skill and ("Your fishing: " .. skill) or "You haven't learned Fishing: a fishing trainer teaches it"
		return FishRows(skill), note
	end
	if not level then return {}, "Your level isn't known here" end
	if kind == "dungeon" then return InstanceRows(level, false), "Dungeons for level " .. level end
	if kind == "raid" then
		local rows = InstanceRows(level, true)
		return rows, (#rows == 0 and "Raids are for level 60" or ("Raids for level " .. level))
	end
	return LevelRows(level), "Zones for level " .. level
end

local ns = select(2, ...)
local L = ns.L

-- WoW Forever's Legacy (account-wide Legacy Points from challenges, spent in the Legacy Tree; rewards claimed from an
-- innkeeper) and its PvP ranks, as Blizzard's own windows read them (wow-ui-source, forever: Blizzard_LegacySystem,
-- PVPRankFrame.lua). Four lists, each only asked for (@kind, its question, Simple mode's Legacy category):
--
--   @legacy        the points earned (a row on top) and every challenge: an achievement in the Legacy categories, its
--                  name and text from GetAchievementInfo, its group the category's name (GetCategoryInfo); is:done /
--                  is:todo, cat:<group> (a class, a profession, dungeons, raids, pvp...). Enter: the Legacy window on
--                  Challenges (the achievement button the game presses, its own route); Shift+Enter: its link in chat
--   @legacyreward  the Legacy rewards: the points each needs, whether you have them, who gives them (Enter: a waypoint
--                  to him, Questie's NPC)
--   @legacyperk    the Legacy Tree's perks: ranks taken of the most, what each does (C_Traits)
--   @pvprank       your PvP rank and Rank Points, and each rank's rewards, "(reached)" up to yours
--
-- Only ids are carried (the generated block below, tests/gen_data.py legacy, docs/DATA_SOURCES.md): every name and text
-- is the game's, in the client's language, read when the list is made.

local LG = {}
ns.Legacy = LG

local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower

-- generated: tests/gen_data.py legacy (do not edit by hand)
-- from Blizzard's interface code 1.60.1 (70532) (LegacyConstantsDocumentation.lua, PVPRankFrame.lua) and the
-- client's tables (wago.tools, build 1.60.1.70532): TraitCurrencySource, Achievement, TraitTree, RenownRewards, CurrencyTypes
LG.LEGACY_FACTION = 2802 -- the Legacy reward track (its renown level: the points earned)
LG.PVP_FACTION = 2800 -- the PvP rank (its renown level: your rank, its reputation: Rank Points)
LG.POINTS_CURRENCY = 4225 -- Legacy Points, the trait currency the Legacy Tree spends
LG.TREES = { 1187, 1188, 1189 } -- the Legacy Tree's three trees: professions, adventure, progression
LG.TREE_SYSTEM = 45 -- their TraitSystemID
LG.CURRENCY = { legacyRank = 3485, pvpRank = 3473, rankPoints = 3468 }
LG.CLASS_OF = { -- a class's challenges' category (Blizzard's LEGACY_DEFAULT_CATEGORY_<CLASS>)
	[15577] = "DRUID",
	[15578] = "HUNTER",
	[15579] = "MAGE",
	[15580] = "PALADIN",
	[15581] = "PRIEST",
	[15582] = "ROGUE",
	[15583] = "SHAMAN",
	[15584] = "WARLOCK",
	[15585] = "WARRIOR",
}
LG.CLAIM = { npc = "Innkeeper Wiley", town = "Ratchet" } -- who gives the Legacy rewards (the rewards' descriptions)
-- 131 challenges: { achievement, category, Legacy Points } (some twice under two ids: the game reports one)
LG.CHALLENGES = {
	{ 61502, 15577, 1 }, -- Novice Druid (Druid)
	{ 61503, 15577, 1 }, -- Experienced Druid (Druid)
	{ 61504, 15577, 1 }, -- Master Druid (Druid)
	{ 63972, 15577, 1 }, -- Novice Druid (Druid)
	{ 63973, 15577, 1 }, -- Experienced Druid (Druid)
	{ 63974, 15577, 1 }, -- Master Druid (Druid)
	{ 61989, 15578, 1 }, -- Novice Hunter (Hunter)
	{ 61992, 15578, 1 }, -- Experienced Hunter (Hunter)
	{ 61993, 15578, 1 }, -- Master Hunter (Hunter)
	{ 63975, 15578, 1 }, -- Novice Hunter (Hunter)
	{ 63976, 15578, 1 }, -- Experienced Hunter (Hunter)
	{ 63977, 15578, 1 }, -- Master Hunter (Hunter)
	{ 61994, 15579, 1 }, -- Novice Mage (Mage)
	{ 61995, 15579, 1 }, -- Experienced Mage (Mage)
	{ 61996, 15579, 1 }, -- Master Mage (Mage)
	{ 63978, 15579, 1 }, -- Novice Mage (Mage)
	{ 63979, 15579, 1 }, -- Experienced Mage (Mage)
	{ 63980, 15579, 1 }, -- Master Mage (Mage)
	{ 61997, 15580, 1 }, -- Novice Paladin (Paladin)
	{ 61998, 15580, 1 }, -- Experienced Paladin (Paladin)
	{ 61999, 15580, 1 }, -- Master Paladin (Paladin)
	{ 63981, 15580, 1 }, -- Novice Paladin (Paladin)
	{ 63982, 15580, 1 }, -- Experienced Paladin (Paladin)
	{ 63983, 15580, 1 }, -- Master Paladin (Paladin)
	{ 62000, 15581, 1 }, -- Novice Priest (Priest)
	{ 62001, 15581, 1 }, -- Experienced Priest (Priest)
	{ 62002, 15581, 1 }, -- Master Priest (Priest)
	{ 63984, 15581, 1 }, -- Novice Priest (Priest)
	{ 63985, 15581, 1 }, -- Experienced Priest (Priest)
	{ 63986, 15581, 1 }, -- Master Priest (Priest)
	{ 62003, 15582, 1 }, -- Novice Rogue (Rogue)
	{ 62004, 15582, 1 }, -- Experienced Rogue (Rogue)
	{ 62005, 15582, 1 }, -- Master Rogue (Rogue)
	{ 63987, 15582, 1 }, -- Novice Rogue (Rogue)
	{ 63988, 15582, 1 }, -- Experienced Rogue (Rogue)
	{ 63989, 15582, 1 }, -- Master Rogue (Rogue)
	{ 62006, 15583, 1 }, -- Novice Shaman (Shaman)
	{ 62007, 15583, 1 }, -- Experienced Shaman (Shaman)
	{ 62008, 15583, 1 }, -- Master Shaman (Shaman)
	{ 63990, 15583, 1 }, -- Novice Shaman (Shaman)
	{ 63991, 15583, 1 }, -- Experienced Shaman (Shaman)
	{ 63992, 15583, 1 }, -- Master Shaman (Shaman)
	{ 62009, 15584, 1 }, -- Novice Warlock (Warlock)
	{ 62010, 15584, 1 }, -- Experienced Warlock (Warlock)
	{ 62011, 15584, 1 }, -- Master Warlock (Warlock)
	{ 63993, 15584, 1 }, -- Novice Warlock (Warlock)
	{ 63994, 15584, 1 }, -- Experienced Warlock (Warlock)
	{ 63995, 15584, 1 }, -- Master Warlock (Warlock)
	{ 61499, 15585, 1 }, -- Novice Warrior (Warrior)
	{ 61500, 15585, 1 }, -- Experienced Warrior (Warrior)
	{ 61501, 15585, 1 }, -- Master Warrior (Warrior)
	{ 63969, 15585, 1 }, -- Novice Warrior (Warrior)
	{ 63970, 15585, 1 }, -- Experienced Warrior (Warrior)
	{ 63971, 15585, 1 }, -- Master Warrior (Warrior)
	{ 62012, 15587, 1 }, -- Journeyman Alchemist (Alchemy)
	{ 62013, 15587, 1 }, -- Expert Alchemist (Alchemy)
	{ 62014, 15587, 1 }, -- Artisan Alchemist (Alchemy)
	{ 63996, 15587, 1 }, -- Journeyman Alchemist (Alchemy)
	{ 63997, 15587, 1 }, -- Expert Alchemist (Alchemy)
	{ 63998, 15587, 1 }, -- Artisan Alchemist (Alchemy)
	{ 62015, 15588, 1 }, -- Journeyman Blacksmith (Blacksmithing)
	{ 62016, 15588, 1 }, -- Expert Blacksmith (Blacksmithing)
	{ 62017, 15588, 1 }, -- Artisan Blacksmith (Blacksmithing)
	{ 63999, 15588, 1 }, -- Journeyman Blacksmith (Blacksmithing)
	{ 64000, 15588, 1 }, -- Expert Blacksmith (Blacksmithing)
	{ 64001, 15588, 1 }, -- Artisan Blacksmith (Blacksmithing)
	{ 62018, 15589, 1 }, -- Journeyman Enchanter (Enchanting)
	{ 62019, 15589, 1 }, -- Expert Enchanter (Enchanting)
	{ 62020, 15589, 1 }, -- Artisan Enchanter (Enchanting)
	{ 64002, 15589, 1 }, -- Journeyman Enchanter (Enchanting)
	{ 64003, 15589, 1 }, -- Expert Enchanter (Enchanting)
	{ 64004, 15589, 1 }, -- Artisan Enchanter (Enchanting)
	{ 62021, 15590, 1 }, -- Journeyman Engineer (Engineering)
	{ 62022, 15590, 1 }, -- Expert Engineer (Engineering)
	{ 62023, 15590, 1 }, -- Artisan Engineer (Engineering)
	{ 64005, 15590, 1 }, -- Journeyman Engineer (Engineering)
	{ 64006, 15590, 1 }, -- Expert Engineer (Engineering)
	{ 64007, 15590, 1 }, -- Artisan Engineer (Engineering)
	{ 62024, 15591, 1 }, -- Journeyman Leatherworker (Leatherworking)
	{ 62025, 15591, 1 }, -- Expert Leatherworker (Leatherworking)
	{ 62026, 15591, 1 }, -- Artisan Leatherworker (Leatherworking)
	{ 64008, 15591, 1 }, -- Journeyman Leatherworker (Leatherworking)
	{ 64009, 15591, 1 }, -- Expert Leatherworker (Leatherworking)
	{ 64010, 15591, 1 }, -- Artisan Leatherworker (Leatherworking)
	{ 62028, 15592, 1 }, -- Journeyman Tailor (Tailoring)
	{ 62029, 15592, 1 }, -- Expert Tailor (Tailoring)
	{ 62030, 15592, 1 }, -- Artisan Tailor (Tailoring)
	{ 64011, 15592, 1 }, -- Journeyman Tailor (Tailoring)
	{ 64012, 15592, 1 }, -- Expert Tailor (Tailoring)
	{ 64013, 15592, 1 }, -- Artisan Tailor (Tailoring)
	{ 62031, 15593, 1 }, -- Novice Spelunker (Dungeons)
	{ 62032, 15593, 1 }, -- Experienced Spelunker (Dungeons)
	{ 62033, 15593, 1 }, -- Master Spelunker (Dungeons)
	{ 64016, 15593, 1 }, -- Novice Spelunker (Dungeons)
	{ 64017, 15593, 1 }, -- Experienced Spelunker (Dungeons)
	{ 64018, 15593, 1 }, -- Master Spelunker (Dungeons)
	{ 684, 15594, 1 }, -- Conqueror of the Lair (Raids)
	{ 62034, 15594, 1 }, -- Conqueror of the Wilds (Raids)
	{ 62035, 15594, 1 }, -- Conqueror of the Deeps (Raids)
	{ 64019, 15594, 1 }, -- Conqueror of the Wilds (Raids)
	{ 64020, 15594, 1 }, -- Conqueror of the Deeps (Raids)
	{ 64030, 15594, 1 }, -- Conqueror of the Lair (Raids)
	{ 62054, 15596, 1 }, -- Lord Valthalak Laid to Rest (Adventure)
	{ 62382, 15596, 1 }, -- Explorer (Adventure)
	{ 64014, 15596, 1 }, -- Lord Valthalak Laid to Rest (Adventure)
	{ 64015, 15596, 1 }, -- Explorer (Adventure)
	{ 64283, 15596, 16 }, -- Played in the WoW: Forever Beta (Adventure)
	{ 62041, 15597, 1 }, -- Rank 3 (Ranks)
	{ 62042, 15597, 1 }, -- Rank 7 (Ranks)
	{ 62043, 15597, 1 }, -- Rank 10 (Ranks)
	{ 62044, 15597, 1 }, -- Rank 13 (Ranks)
	{ 62045, 15597, 1 }, -- Rank 14 (Ranks)
	{ 64021, 15597, 1 }, -- Rank 3 (Ranks)
	{ 64022, 15597, 1 }, -- Rank 7 (Ranks)
	{ 64023, 15597, 1 }, -- Rank 10 (Ranks)
	{ 64024, 15597, 1 }, -- Rank 13 (Ranks)
	{ 64025, 15597, 1 }, -- Rank 14 (Ranks)
	{ 62046, 15598, 1 }, -- Master of Alterac Valley (Reputations)
	{ 62047, 15598, 1 }, -- Master of Arathi Basin (Reputations)
	{ 62048, 15598, 1 }, -- Master of Warsong Gulch (Reputations)
	{ 62049, 15598, 1 }, -- Master of Darkspear Islands (Reputations)
	{ 64026, 15598, 1 }, -- Master of Alterac Valley (Reputations)
	{ 64027, 15598, 1 }, -- Master of Arathi Basin (Reputations)
	{ 64028, 15598, 1 }, -- Master of Warsong Gulch (Reputations)
	{ 64029, 15598, 1 }, -- Master of Darkspear Islands (Reputations)
	{ 63340, 15620, 1 }, -- Field of Honor: Week 4 (Season Journey)
	{ 63341, 15620, 1 }, -- Field of Honor: Week 7 (Season Journey)
	{ 63342, 15620, 1 }, -- Field of Honor: Week 10 (Season Journey)
	{ 64031, 15620, 1 }, -- Field of Honor: Week 4 (Season Journey)
	{ 64032, 15620, 1 }, -- Field of Honor: Week 7 (Season Journey)
	{ 64033, 15620, 1 }, -- Field of Honor: Week 10 (Season Journey)
}
LG.LEGACY_TRACK, LG.PVP_TRACK = 48, 46
-- 22 rewards: { id, track, level (points or rank), icon, item, spell, mount, player condition }
LG.REWARDS = {
	{ 1832, 46, 1, 135026, 0, 0, 0, 0 }, -- Faction Tabard Unlocked
	{ 1833, 46, 2, 133453, 0, 0, 0, 0 }, -- Insignia Trinket Unlocked
	{ 1834, 46, 3, 461814, 0, 0, 0, 0 }, -- Cloak Unlocked
	{ 1835, 46, 4, 133303, 0, 0, 0, 0 }, -- Necklace Unlocked
	{ 1836, 46, 5, 134715, 0, 0, 0, 0 }, -- Access to Combat Potions Unlocked
	{ 1837, 46, 6, 514261, 0, 0, 0, 0 }, -- Elite Faction Tabard Unlocked
	{ 1838, 46, 7, 132484, 0, 0, 0, 0 }, -- Battle Standard Unlocked
	{ 1839, 46, 8, 236972, 0, 0, 0, 0 }, -- Elite Wrist Upgrades Unlocked
	{ 2008, 46, 8, 132501, 0, 0, 0, 0 }, -- Elite Waist Upgrades Unlocked
	{ 1840, 46, 9, 795709, 0, 0, 0, 0 }, -- Elite Boot Upgrade Unlocked
	{ 1841, 46, 10, 133832, 0, 0, 0, 0 }, -- Elite Glove Upgrade Unlocked
	{ 1842, 46, 11, 132224, 0, 0, 0, 923 }, -- Faction Black War Mounts Unlocked
	{ 2009, 46, 11, 132251, 0, 0, 0, 924 }, -- Faction Black War Mounts Unlocked
	{ 1843, 46, 12, 134628, 0, 0, 0, 0 }, -- Elite Leg Upgrades Unlocked
	{ 2010, 46, 12, 135055, 0, 0, 0, 0 }, -- Elite Shoulder Upgrades Unlocked
	{ 1844, 46, 13, 132717, 0, 0, 0, 0 }, -- Elite Chest Upgrades Unlocked
	{ 2011, 46, 13, 133074, 0, 0, 0, 0 }, -- Elite Helmet Upgrades Unlocked
	{ 1845, 46, 14, 135979, 0, 0, 0, 0 }, -- Weapon Arsenal Unlocked
	{ 1856, 48, 15, 135614, 276236, 0, 0, 0 }, -- Replica Ironforge Air Rifle
	{ 1857, 48, 25, 294471, 277714, 0, 0, 0 }, -- Spectral Bear Cub
	{ 1858, 48, 40, 7941423, 277717, 0, 0, 0 }, -- Spectral Bear Tabard
	{ 1859, 48, 55, 3753812, 277718, 0, 0, 0 }, -- Reins of the Spectral Bear
}
-- end of generated: legacy

local GREY = "|cff8a8a8a"
local LEGACY_COLOR, PERK_COLOR, PVP_COLOR = "ffe0a8ff", "ffa070d0", "ffd060c0" -- (pale violet, violet, magenta)
local POINTS_ICON = "Interface\\Icons\\INV_Misc_Coin_17"
local PVP_ICON = "Interface\\Icons\\INV_BannerPVP_02"
-- the Legacy Tree's trees' names, the game's (Blizzard_LegacySystemConstants.lua's LegacyTreeData), in LG.TREES' order
local TREE_NAMES = { "LEGACY_TREE_PROFESSIONS", "LEGACY_TREE_ADVENTURE", "LEGACY_TREE_PROGRESSION" }

local function MF() local m = rawget(_G, "C_MajorFactions") return type(m) == "table" and m or nil end
local function Traits() local t = rawget(_G, "C_Traits") return type(t) == "table" and t or nil end

--- A currency's amount and name (C_CurrencyInfo), or nil.
local function Currency(id)
	local C = rawget(_G, "C_CurrencyInfo")
	local info = C and Safe(C.GetCurrencyInfo, id)
	if type(info) ~= "table" then return nil end
	return Num(info.quantity), Str(info.name)
end

--- What a track's rewards at one level are, as the game says them (C_MajorFactions.GetRenownRewardsForLevel, as the
--- Legacy window's reward track and the PvP rank pane read them; in the client's language): { [reward id] = info }, or
--- nil when the game gives none.
local function GameRewards(faction, level)
	local M = MF()
	local got = M and Safe(M.GetRenownRewardsForLevel, faction, level)
	if type(got) ~= "table" or #got == 0 then return nil end
	local out = {}
	for _, r in ipairs(got) do
		local id = type(r) == "table" and Num(r.renownRewardID)
		if id then out[id] = r end
	end
	return next(out) and out or nil
end

local ItemName, SpellName = ns.ItemName, ns.SpellName
local function MountName(id)
	if not id or id == 0 then return nil end
	local C = rawget(_G, "C_MountJournal")
	return Str(C and (Safe(C.GetMountInfoByID, id)))
end

local function Say(e) ns:Output({ "  " .. tostring(e.name) .. ((e.detail and e.detail ~= "") and ("  " .. e.detail) or "") }) end

----------------------------------------------------------------------
-- Points
----------------------------------------------------------------------

--- The Legacy Tree's config and the points it has left to spend (nil when the game gives none).
local function TreePoints()
	local T = Traits()
	if not T then return nil end
	local config = Num(Safe(T.GetConfigIDByTreeID, LG.TREES[1])) or Num(Safe(T.GetConfigIDBySystemID, LG.TREE_SYSTEM))
	if not config then return nil end
	local info = Safe(T.GetTreeCurrencyInfo, config, LG.TREES[1], false)
	local c = type(info) == "table" and info[1]
	return config, type(c) == "table" and Num(c.quantity) or nil
end

--- The Legacy Points earned as the window shows them (its reward track's renown level, Blizzard_LegacySystemUtil.lua;
--- else the Legacy rank currency; else the points of the challenges done), where they came from ("track", "currency",
--- "count"), and those left to spend in the tree. `challenges`: the rows, or a function making them (only then).
function LG.Points(challenges)
	local unspent = select(2, TreePoints())
	local M = MF()
	local n = M and Num(Safe(M.GetCurrentRenownLevel, LG.LEGACY_FACTION))
	if n and n > 0 then return n, "track", unspent end
	n = Currency(LG.CURRENCY.legacyRank)
	if n and n > 0 then return n, "currency", unspent end
	local sum = 0
	if type(challenges) == "function" then challenges = challenges() end
	for _, e in ipairs(challenges or {}) do if e.isDone then sum = sum + (e.points or 1) end end
	return sum, "count", unspent
end

----------------------------------------------------------------------
-- Challenges (@legacy)
----------------------------------------------------------------------

local AA -- Achievements.lua's row actions (its Enter's fallback, link, Shift+Enter), read when the rows are made
-- Enter: the Legacy window on Challenges by the achievement button (Forever's ToggleAchievementFrame is
-- ToggleLegacyChallenges: Blizzard_AchievementUI/Camelot), pressed by the game; nothing to press while it shows them.
-- (Not Achievements' /run line: from a /run line the Legacy window's code runs tainted, its Tree's talent panel with it
-- (Panels.lua, 0.48.4); and no clean route turns it to one challenge: ShowLegacyChallenge is Blizzard Lua.)
-- (1.3.12, review: Forever's own bindings (Bindings_Camelot.xml) have no TOGGLEACHIEVEMENT, though its name string is
-- there, so the override binding pressed nothing. There the achievement button is pressed, as Panels.lua's Legacy
-- Challenges row does; once seen not to open Challenges (Panels' db.legacyRoute false), the Legacy window's own button)
function LG.ChallengesMacro()
	if not rawget(_G, "ToggleLegacySystemUI") then return nil end -- (not WoW Forever: the achievement key)
	if ns.db and ns.db.legacyRoute == false then return "/click LegacyMicroButton" end
	return "/click AchievementMicroButton"
end
LG.SECURE = { macro = function() return LG.ChallengesMacro() end, binding = "TOGGLEACHIEVEMENT", buttons = { "AchievementMicroButton" },
	opensWindow = true }
local CHALLENGES_PAGE = 2 -- (LegacySystemFrame's page number for Challenges: Panels.lua's LEGACY_PAGES)
function LG.ChallengesShown()
	local f = rawget(_G, "LegacySystemFrame")
	return type(f) == "table" and f.IsShown and f:IsShown() and f.currentPage == CHALLENGES_PAGE or false
end
local function ChallengeOpen() return LG.ChallengesShown() end
local function Activate(e) if AA and AA.activate then AA.activate(e) end end
local function Link(e) return AA and AA.getLink and AA.getLink(e) or nil end
local function LinkInChat(e) if AA and AA.secondary then AA.secondary(e) end end

--- The first letters of a group's words ("player vs. player": pvp).
local function Initials(s)
	local out = {}
	for w in s:gmatch("[%a\128-\255]+") do out[#out + 1] = w:sub(1, 1) end
	return table.concat(out)
end
--- Does `word` (lowercase) name this group (lowercase): its start, a word's start, its initials.
function LG.GroupHas(group, word)
	if type(group) ~= "string" or type(word) ~= "string" or word == "" or group == "" then return false end
	if (" " .. group):find(" " .. word, 1, true) then return true end
	return #word >= 2 and Initials(group) == word
end

local function CategoryInfo(cat, cache)
	local c = cache[cat]
	if c == nil then
		local name, parent = Safe(rawget(_G, "GetCategoryInfo"), cat)
		c = { name = Str(name), parent = Num(parent) }
		cache[cat] = c
	end
	return c
end

--- The ids the game lists in a challenge category (as the Legacy window reads them: GetAchievementInfo(category, i)).
local function Listed(cat, into)
	local n = Num((Safe(rawget(_G, "GetCategoryNumAchievements"), cat))) or 0
	for i = 1, math.min(n, 100) do
		local id = Num((Safe(rawget(_G, "GetAchievementInfo"), cat, i)))
		if id then into[id] = true end
	end
end

local function ChallengeRow(c, info, cache)
	local id, cat, points = c[1], c[2], c[3]
	local name, completed, description, icon, mine = info[2], info[4], info[8], info[10], info[13]
	local ci = CategoryInfo(cat, cache)
	local parent = ci.parent and ci.parent > 0 and CategoryInfo(ci.parent, cache).name or nil
	-- (done as the Legacy window says: one only another character earned shows not done there, LegacySystemUtil.lua's
	-- IsChallengeVisible reads wasEarnedByMe; 1.3.12, review)
	local done = completed == true and mine ~= false
	local groups = { Lower(ci.name or ""), parent and Lower(parent) or "" }
	local class = LG.CLASS_OF[cat]
	if class then groups[#groups + 1] = Lower(class) end
	return {
		key = id, name = name, text = ns.Join(" ", Str(description), groups[1], groups[2], "legacy challenge"),
		detail = ns.Detail(ci.name, done and L["Done"] or (points > 1 and L["%s pts"]:format(points) or nil)),
		tip = Str(description), icon = Num(icon) or Str(icon) or POINTS_ICON, color = done and GREY or nil,
		isDone = done, completed = done, points = points, category = cat, group = ci.name, groups = groups, classFile = class,
		secure = LG.SECURE, isOpen = ChallengeOpen, activate = Activate, getLink = Link,
		secondary = LinkInChat, secondarySecure = AA and AA.secondarySecure, secondaryIsOpen = AA and AA.secondaryIsOpen,
		noPlace = true,
	}
end

--- One row per challenge (one carried under two ids, the same name in one category: the one the game lists, else the
--- one done, else the first), in the window's order: by category, then id.
function LG.Challenges()
	AA = ns.AchievementActions
	local listed, cache, seen, order, cats = {}, {}, {}, {}, {}
	for _, c in ipairs(LG.CHALLENGES) do
		if not cats[c[2]] then
			cats[c[2]] = true
			Listed(c[2], listed)
		end
	end
	local get = rawget(_G, "GetAchievementInfo")
	for _, c in ipairs(LG.CHALLENGES) do
		local info = { Safe(get, c[1]) }
		-- (only the achievement asked for: an id the game doesn't have answers nothing, or another one)
		if Num(info[1]) == c[1] and Str(info[2]) then
			local k = c[2] .. "\0" .. info[2]
			local score = (listed[c[1]] and 2 or 0) + ((info[4] == true and info[13] ~= false) and 1 or 0)
			local had = seen[k]
			if not had then
				seen[k] = { c = c, info = info, score = score }
				order[#order + 1] = k
			elseif score > had.score then
				had.c, had.info, had.score = c, info, score
			end
		end
	end
	local rows = {}
	for _, k in ipairs(order) do rows[#rows + 1] = ChallengeRow(seen[k].c, seen[k].info, cache) end
	return rows
end

--- The row on top: the points earned, those left to spend, how many challenges are done.
local function PointsRow(challenges)
	local earned, _, unspent = LG.Points(challenges)
	local done = 0
	for _, e in ipairs(challenges) do if e.isDone then done = done + 1 end end
	return {
		key = "points", name = L["Legacy points: %d"]:format(earned), icon = POINTS_ICON,
		detail = ns.Detail(unspent and L["%d to spend"]:format(unspent) or nil, L["%d of %d done"]:format(done, #challenges)),
		text = "legacy points", activate = Say, staysOpen = false, legacyPoints = earned,
	}
end

function LG.CollectChallenges()
	local challenges = LG.Challenges()
	local rows = { PointsRow(challenges) }
	for _, e in ipairs(challenges) do rows[#rows + 1] = e end
	ns.RankInOrder(rows)
	return rows
end

ns:RegisterProvider("legacy", {
	label = L["Legacy"],
	color = LEGACY_COLOR,
	aliases = { "legacy", "challenge", "challenges", "legacychallenge" },
	explicit = true, lazy = true,
	-- (its points row: the reward track's level and the tree's points to spend change after the challenge)
	events = { "ACHIEVEMENT_EARNED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" },
	refreshOnOpen = 60,
	collect = function() return LG.CollectChallenges() end,
})

----------------------------------------------------------------------
-- Rewards (@legacyreward) and PvP ranks (@pvprank)
----------------------------------------------------------------------

--- Who gives the Legacy rewards: Questie's NPC id (nil: Questie doesn't know him) and name (in the client's language
--- when Questie has it; else the rewards' own, English). Found by his English name whatever the client's language
--- (1.4.3: a client in another language never found him, so Enter had no waypoint).
local function ClaimNpc()
	local I = ns.Integrations
	local id = I and I.NpcIdNamedEnglish and I.NpcIdNamedEnglish(LG.CLAIM.npc)
	local row = id and I.NpcRow and I.NpcRow(id)
	return id, row and Str(row.name) or LG.CLAIM.npc
end
--- "Innkeeper Wiley, Ratchet"
function LG.ClaimText() return select(2, ClaimNpc()) .. ", " .. LG.CLAIM.town end

--- Enter on a Legacy reward: a waypoint to the innkeeper who gives it (Questie's NPC, as @npc's waypoint).
function LG.ToClaimer()
	local I = ns.Integrations
	local id, name = ClaimNpc()
	if id and I.NpcPin then I.NpcPin({ npcID = id, name = name }) return end
	ns:Print(L["Questie has no known location for %s."]:format(name))
end

--- A track's rewards: { { its row, what the game says of it (nil: nothing) } }. The game lists only those for your side;
--- without its list, one of a level's pair for the two sides is kept.
local function TrackRewards(track, faction)
	local out, byLevel, paired = {}, {}, {}
	for _, r in ipairs(LG.REWARDS) do
		if r[2] == track then
			local lvl = r[3]
			if byLevel[lvl] == nil then byLevel[lvl] = GameRewards(faction, lvl) or false end
			local said = byLevel[lvl]
			if said then
				if said[r[1]] then out[#out + 1] = { r, said[r[1]] } end
			elseif r[8] == 0 or not paired[lvl] then
				if r[8] ~= 0 then paired[lvl] = true end
				out[#out + 1] = { r, nil }
			end
		end
	end
	return out
end

-- a reward's name: the game's (a PvP rank's says what it unlocks in its description: its name is "Rank N Rewards"),
-- else its item's, mount's or spell's
local function RewardName(r, said, pvp)
	if said then
		local n
		if pvp then n = Str(said.description) or Str(said.toastDescription) else n = Str(said.name) or Str(said.toastDescription) end
		if n then return n end
	end
	return ItemName(r[5]) or MountName(r[7]) or SpellName(r[6]) -- (nothing: the row is left out, "Rank 8" twice says nothing)
end

function LG.CollectRewards()
	-- (the challenges read only when neither the track nor the currency says: 1.3.12, review)
	local earned = LG.Points(LG.Challenges)
	local rows, claim = {}, LG.ClaimText()
	for _, x in ipairs(TrackRewards(LG.LEGACY_TRACK, LG.LEGACY_FACTION)) do
		local r, said = x[1], x[2]
		local name = RewardName(r, said, false)
		if name then
			local enough = earned >= r[3]
			local tip = said and (Str(said.description) or Str(said.toastDescription)) or nil
			rows[#rows + 1] = {
				key = "r" .. r[1], name = name, points = r[3], isDone = enough,
				icon = said and Num(said.icon) or r[4], link = r[5] ~= 0 and ("item:" .. r[5]) or nil,
				detail = ns.Detail(L["%s pts"]:format(r[3]), enough and L["(reached)"] or L["need %d"]:format(r[3] - earned), claim),
				tip = tip, text = ns.Join(" ", tip and Lower(ns.Plain(tip)) or nil, "legacy reward", Lower(claim)),
				activate = LG.ToClaimer, staysOpen = false,
			}
		end
	end
	ns.RankInOrder(rows)
	return rows
end

ns:RegisterProvider("legacyreward", {
	label = L["Legacy Rewards"],
	color = LEGACY_COLOR, oneWith = "legacy", -- (part of the Legacy to the player: its colour)
	aliases = { "legacyreward", "legacyrewards" },
	explicit = true, lazy = true,
	events = { "ACHIEVEMENT_EARNED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" },
	refreshOnOpen = 60,
	collect = function() return LG.CollectRewards() end,
})

--- Your PvP rank, your Rank Points and the next rank's (C_MajorFactions.GetMajorFactionProgressionInfo, as the
--- character window's PvP pane reads them; else the rank and Rank Points currencies).
function LG.PvpRank()
	local M = MF()
	local p = M and Safe(M.GetMajorFactionProgressionInfo, LG.PVP_FACTION)
	if type(p) == "table" and Num(p.renownLevel) then
		return Num(p.renownLevel), Num(p.renownReputationEarned), Num(p.renownLevelThreshold)
	end
	local rank = M and Num(Safe(M.GetCurrentRenownLevel, LG.PVP_FACTION))
	if not rank then rank = Currency(LG.CURRENCY.pvpRank) end
	return rank, (Currency(LG.CURRENCY.rankPoints)), nil
end
--- A rank's title for you (the game's PVP_RANK_<n>_<side>, by your side and gender, as PVPRankFrame.lua reads it).
function LG.RankTitle(rank)
	if not rank or rank <= 0 then return ns.GameText("PVP_RANK_0_NAME") end
	local E = rawget(_G, "Enum")
	local first = type(E) == "table" and type(E.PvPRanks) == "table" and Num(E.PvPRanks.Rank_1)
	if not first then return nil end
	local side = Safe(rawget(_G, "UnitFactionGroup"), "player") == "Alliance" and 1 or 0
	local key = "PVP_RANK_" .. (first + rank - 1) .. "_" .. side
	return Str((Safe(rawget(_G, "GetText"), key, (Safe(rawget(_G, "UnitSex"), "player"))))) or ns.GameText(key)
end
--- "Rank 5 Knight"
function LG.RankText(rank)
	local title = LG.RankTitle(rank)
	if not rank or rank <= 0 then return title or L["Rank %d"]:format(0) end
	return L["Rank %d"]:format(rank) .. (title and (" " .. title) or "")
end

function LG.CollectPvp()
	local rank, points, nextAt = LG.PvpRank()
	local _, pointsName = Currency(LG.CURRENCY.rankPoints)
	local rows = { {
		key = "rank", name = LG.RankText(rank), icon = PVP_ICON,
		detail = points and ns.Join(" ", pointsName, (nextAt and nextAt > 0) and (points .. "/" .. nextAt) or tostring(points)) or nil,
		text = "pvp rank points mine", activate = Say, staysOpen = false, myRank = rank or 0,
	} }
	for _, x in ipairs(TrackRewards(LG.PVP_TRACK, LG.PVP_FACTION)) do
		local r, said = x[1], x[2]
		local reached = rank ~= nil and rank >= r[3]
		local name = RewardName(r, said, true)
		-- (not `level`: a rank isn't a level, and lvl: lines would list them; rank: is its filter)
		if name then rows[#rows + 1] = {
			key = "p" .. r[1], name = name, pvpRank = r[3], isDone = reached,
			icon = said and Num(said.icon) or r[4], color = (not reached) and GREY or nil,
			detail = ns.Detail(L["Rank %d"]:format(r[3]), reached and L["(reached)"] or nil),
			tip = said and Str(said.toastDescription) or nil, text = "pvp rank reward",
			activate = Say, staysOpen = false,
		} end
	end
	ns.RankInOrder(rows)
	return rows
end

ns:RegisterProvider("pvprank", {
	label = L["PvP rank"],
	color = PVP_COLOR,
	aliases = { "pvprank", "pvpranks" },
	explicit = true, lazy = true,
	-- (Rank Points: the PvP rank faction's reputation)
	events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION" },
	refreshOnOpen = 60,
	collect = function() return LG.CollectPvp() end,
})

----------------------------------------------------------------------
-- The Legacy Tree's perks (@legacyperk)
----------------------------------------------------------------------

--- One row per perk of the three trees (C_Traits: config -> tree nodes -> node -> entry -> definition -> spell), or none
--- and a trace line saying where the game gave nothing (for a player's .debug log).
function LG.CollectPerks()
	local rows, stop = {}, nil
	local T = Traits()
	local config = T and TreePoints()
	if not T then stop = "no C_Traits"
	elseif not config then
		stop = "no config (GetConfigIDByTreeID(" .. LG.TREES[1] .. "), GetConfigIDBySystemID(" .. LG.TREE_SYSTEM .. "))"
	end
	local Spell = rawget(_G, "C_Spell")
	for ti, tree in ipairs(config and LG.TREES or {}) do
		-- (each tree's own config, as Blizzard_LegacyTree.lua asks; the first's when the game gives none: 1.3.12, review)
		local cfg = Num(Safe(T.GetConfigIDByTreeID, tree)) or config
		local nodes = Safe(T.GetTreeNodes, tree)
		if type(nodes) ~= "table" or #nodes == 0 then
			stop = stop or ("no nodes in tree " .. tree)
		else
			local treeName = ns.GameText(TREE_NAMES[ti])
			for _, node in ipairs(nodes) do
				local n = Safe(T.GetNodeInfo, cfg, node)
				local entryID, max
				if type(n) == "table" then
					entryID = (type(n.activeEntry) == "table" and Num(n.activeEntry.entryID))
						or (type(n.entryIDs) == "table" and Num(n.entryIDs[1])) or nil
					max = Num(n.maxRanks)
				end
				if entryID and max and max > 0 and n.isVisible ~= false then
					local entry = Safe(T.GetEntryInfo, cfg, entryID)
					local defID = type(entry) == "table" and Num(entry.definitionID)
					local def = defID and Safe(T.GetDefinitionInfo, defID)
					local spell = type(def) == "table" and Num(def.spellID) or nil
					local name = type(def) == "table" and (Str(def.overrideName) or SpellName(spell)) or nil
					if name then
						local rank = Num(n.activeRank) or Num(n.ranksPurchased) or 0
						local desc = Str(def.overrideDescription) or (spell and Spell and Str(Safe(Spell.GetSpellDescription, spell))) or nil
						rows[#rows + 1] = {
							key = node, name = name, isDone = rank >= max, rank = rank, maxRank = max,
							icon = Num(def.overrideIcon) or (spell and Spell and Num(Safe(Spell.GetSpellTexture, spell))) or nil,
							detail = ns.Detail(treeName, rank .. "/" .. max), tip = desc,
							text = ns.Join(" ", desc and Lower(ns.Plain(desc)) or nil, treeName and Lower(treeName) or nil, "legacy perk"),
							color = rank == 0 and GREY or nil, activate = Say, staysOpen = false,
						}
					else
						stop = stop or ("node " .. tostring(node) .. ": no definition or spell name")
					end
				end
			end
		end
	end
	if #rows == 0 then ns:Trace("legacy: no perks read: " .. tostring(stop or "no visible nodes")) end
	ns.RankInOrder(rows)
	return rows
end

ns:RegisterProvider("legacyperk", {
	label = L["Legacy Tree"],
	color = PERK_COLOR,
	aliases = { "legacyperk", "perk", "perks", "legacytree" },
	explicit = true, lazy = true,
	events = { "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" },
	refreshOnOpen = 60,
	collect = function() return LG.CollectPerks() end,
})

----------------------------------------------------------------------
-- Filters: is:done / is:todo read the rows' isDone; cat:<group> is a challenge's category or its parent's
----------------------------------------------------------------------
do
	local F = ns.Filters
	local KEYS = F and F._ and F._.KEYS
	if KEYS then
		KEYS.cat = function(v)
			v = Lower((v or ""):gsub("_", " "))
			if v == "" then return nil end
			return function(e)
				if e.kind ~= "legacy" or type(e.groups) ~= "table" then return false end
				for _, g in ipairs(e.groups) do if LG.GroupHas(g, v) then return true end end
				return false
			end
		end
	end
	-- rank:11 (rank:<5, rank:8-11): a PvP rank's rewards
	if KEYS and F.Range then
		KEYS.rank = function(v)
			local r = F.Range(v)
			return r and function(e) return e.kind == "pvprank" and type(e.pvpRank) == "number" and r(e.pvpRank) or false end
		end
	end
	local A = F and F.APPLIES
	if A then
		A.cat = { ["*"] = { "legacy" } }
		A.rank = { ["*"] = { "pvprank" } }
		-- (the questions' lines end in sort:list: offered on them too)
		local SL = A.sort and A.sort.list
		if type(SL) == "table" then
			for _, id in ipairs({ "legacy", "legacyreward", "legacyperk", "pvprank" }) do
				local had = false
				for _, x in ipairs(SL) do if x == id then had = true end end
				if not had then SL[#SL + 1] = id end
			end
		end
		for _, k in ipairs({ "done", "todo" }) do
			local l = A.is and A.is[k] -- (done's and todo's are one list: added once)
			if type(l) == "table" then
				for _, id in ipairs({ "legacy", "legacyreward", "legacyperk", "pvprank" }) do
					local had = false
					for _, x in ipairs(l) do if x == id then had = true end end
					if not had then l[#l + 1] = id end
				end
			end
		end
	end
	if F and type(F.HELP) == "table" then
		F.HELP[#F.HELP + 1] = { "cat:mage", L["@legacy: WoW Forever's Legacy challenges of a group (a class, a profession, dungeons, raids, pvp...); is:todo those still to do. @legacyreward, @legacyperk: its rewards, its tree's perks; @pvprank rank:11: what PvP rank 11 unlocks"] }
	end
end

----------------------------------------------------------------------
-- The questions (Search/Questions/Questions.lua's registry, docs/QUESTIONS.md): search questions, each its list's line.
-- "legacy points", "which legacy points am i missing", "what gives legacy points for mage", "legacy rewards", "legacy
-- perks", "my pvp rank", "rank points", "what does pvp rank 11 unlock". Asked as a question, the Legacy window's own
-- row for that page (Panels.lua) comes first, and stays when nothing is found.
----------------------------------------------------------------------

local FILL = {}
for w in ([[what whats which how many much do does did i im ive am my me mine is are was were the a an of for to on in at
	have has had got can could would will there theres any all show list tell see by with from still yet so far]]):gmatch("%S+") do
	FILL[w] = true
end
local TODO = {}
for w in ("missing miss todo havent dont left remaining need needed undone unfinished incomplete"):gmatch("%S+") do TODO[w] = true end
local GIVES = { get = true, gets = true, give = true, gives = true, earn = true, gain = true } -- (with a group: those still to do)
local DONE = { done = true, completed = true, finished = true }
local STRONG = { point = true, points = true, pts = true, challenge = true, challenges = true }

local function Words(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local out = {}
	for w in t:gmatch("%S+") do out[#out + 1] = w end
	return #out > 0 and out or nil
end

local function PanelRow(tab)
	local p = ns.providers.panels
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if e.tab == tab then return e end end
	return nil
end
-- (the window's row on top; with nothing found, it and a line saying why)
local function LeadOf(tab) return function() local r = PanelRow(tab) return r and { r } or nil end end
local function NoneOf(tab, text)
	local out = {}
	local r = PanelRow(tab)
	if r then out[1] = r end
	out[#out + 1] = ns.NoteRow(text)
	return out
end
LG.NONE = L["Nothing read from the game for this yet: open the Legacy window once, then ask again."]
local TABS = { challenges = "LegacySystemFrame.LegacyChallengeTab", rewards = "LegacySystemFrame.LegacyRewardTrackTab",
	tree = "LegacySystemFrame.LegacyTreeTab" }

local CLASS_SET = {}
for _, file in pairs(LG.CLASS_OF) do CLASS_SET[file] = true end
-- the class a word names (its English file name, the client's names for it, a plural): its file name lowercase, or nil
-- (the words made once: every question reads every word of a line through it)
local classWords
local function ClassWord(w)
	if not classWords then
		classWords = {}
		local male, female = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE"), rawget(_G, "LOCALIZED_CLASS_NAMES_FEMALE")
		for file in pairs(CLASS_SET) do
			local names = { Lower(file) }
			for _, t in ipairs({ male, female }) do
				if type(t) == "table" and Str(t[file]) then names[#names + 1] = Lower(t[file]) end
			end
			for _, n in ipairs(names) do
				for _, x in ipairs({ n, n .. "s", n .. "es" }) do classWords[x] = classWords[x] or Lower(file) end
			end
		end
	end
	return classWords[w]
end
function LG.ForgetClassWords() classWords = nil end -- (tests)

--- Does this word name a challenge group (a class, or a category of the challenges listed)? Its cat: value, or nil.
local function GroupWord(w)
	if #w < 2 then return nil end
	local c = ClassWord(w)
	if c then return c end
	local one = w:gsub("s$", "")
	local p = ns.providers.legacy
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		for _, g in ipairs(type(e.groups) == "table" and e.groups or {}) do
			if LG.GroupHas(g, w) then return w end
			if #one >= 2 and LG.GroupHas(g, one) then return one end
		end
	end
	return nil
end

local LP = {}
ns.LegacyPoints = LP
--- { todo, done, cats } when the line asks about Legacy Points or challenges, else nil.
function LP.Question(text)
	local words = Words(text)
	if not words then return nil end
	-- (its two words first: a group word is looked up in the list, never for a line that isn't about the Legacy)
	local legacy, strong = false, false
	for _, w in ipairs(words) do
		if w == "legacy" then legacy = true
		elseif STRONG[w] then strong = true end
	end
	if not (legacy and strong) then return nil end
	local todo, gives, done, cats, myClass = false, false, false, {}, false
	for _, w in ipairs(words) do
		if w == "legacy" or STRONG[w] then -- (said)
		elseif TODO[w] then todo = true
		elseif DONE[w] then done = true
		elseif w == "class" then myClass = true
		elseif GIVES[w] then gives = true
		elseif not FILL[w] then
			local g = GroupWord(w)
			if not g then return nil end
			cats[#cats + 1] = g
		end
	end
	if myClass then
		local file = select(2, Safe(rawget(_G, "UnitClass"), "player"))
		if not Str(file) then return nil end
		cats[#cats + 1] = Lower(file)
	end
	-- (what gives them for a group, what's missing: the challenges still to do)
	if gives and #cats > 0 then todo = true end
	-- ("legacy challenges i havent done": still to do)
	return { todo = todo, done = done and not todo, cats = cats }
end
function LP.Line(q)
	local parts = { "@legacy" }
	if q.todo then parts[#parts + 1] = "is:todo" end
	if q.done then parts[#parts + 1] = "is:done" end
	for _, c in ipairs(q.cats or {}) do parts[#parts + 1] = "cat:" .. c end
	parts[#parts + 1] = "sort:list"
	return table.concat(parts, " ") .. " "
end
-- the points earned, and how many challenges of how many are done (the list's own rows)
local function Counts()
	local p = ns.providers.legacy
	local all, done, earned = 0, 0, 0
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if e.legacyPoints then earned = e.legacyPoints
		elseif e.isDone ~= nil then
			all = all + 1
			if e.isDone then done = done + 1 end
		end
	end
	return earned, done, all
end
function LP.Footer()
	local earned, done, all = Counts()
	return ns.Detail(L["Legacy points: %d"]:format(earned), L["%d of %d done"]:format(done, all))
end
LP.Lead = LeadOf(TABS.challenges)
function LP.None()
	local _, done, all = Counts()
	return NoneOf(TABS.challenges, all > 0 and L["%d of %d done"]:format(done, all) or LG.NONE)
end

local LR = {}
ns.LegacyRewards = LR
--- {} when the line asks for the Legacy rewards ("legacy rewards", "what can i claim with legacy points"), else nil.
function LR.Question(text)
	local words = Words(text)
	if not words then return nil end
	local legacy, strong = false, false
	for _, w in ipairs(words) do
		if w == "legacy" then legacy = true
		elseif w == "reward" or w == "rewards" or w == "unlock" or w == "unlocks" or w == "claim" then strong = true
		elseif not (FILL[w] or w == "point" or w == "points" or w == "next") then return nil end
	end
	return legacy and strong and {} or nil
end
function LR.Line() return "@legacyreward sort:list " end
function LR.Footer()
	local earned = Counts()
	return ns.Detail(L["Legacy Rewards"], L["Legacy points: %d"]:format(earned))
end
LR.Lead = LeadOf(TABS.rewards)
function LR.None() return NoneOf(TABS.rewards, LG.NONE) end

local LK = {}
ns.LegacyPerks = LK
--- {} when the line asks for the Legacy Tree's perks ("legacy perks", "my perks", "legacy talents"), else nil. (Not
--- "legacy tree" alone: that's the window's row.)
function LK.Question(text)
	local words = Words(text)
	if not words then return nil end
	local legacy, perks, talents = false, false, false
	for _, w in ipairs(words) do
		if w == "legacy" then legacy = true
		elseif w == "perk" or w == "perks" then perks = true
		elseif w == "talent" or w == "talents" then talents = true
		elseif not (FILL[w] or w == "tree") then return nil end
	end
	return (perks or (legacy and talents)) and {} or nil
end
function LK.Line() return "@legacyperk sort:list " end
function LK.Footer()
	local _, unspent = TreePoints()
	return ns.Detail(L["Legacy Tree"], unspent and L["%d to spend"]:format(unspent) or nil)
end
LK.Lead = LeadOf(TABS.tree)
function LK.None() return NoneOf(TABS.tree, LG.NONE) end

local PR = {}
ns.PvpRank = PR
--- { rank = N (what rank N unlocks: rank:N) } when the line asks about the PvP ranks ("my pvp rank", "rank points", "what does
--- pvp rank 11 unlock"), else nil.
function PR.Question(text)
	local words = Words(text)
	if not words then return nil end
	local pvp, rank, points, n = false, false, false, nil
	for _, w in ipairs(words) do
		if w == "pvp" then pvp = true
		elseif w == "rank" or w == "ranks" then rank = true
		elseif w == "point" or w == "points" then points = true
		elseif w == "rankpoints" then rank, points = true, true
		elseif tonumber(w) and not n then n = tonumber(w)
		elseif not (FILL[w] or w == "unlock" or w == "unlocks" or w == "reward" or w == "rewards" or w == "next") then return nil end
	end
	if not (rank and (pvp or points)) then return nil end
	if n and (n < 1 or n > 14 or n % 1 ~= 0) then return nil end
	return { rank = n }
end
function PR.Line(q) return "@pvprank " .. (q.rank and ("rank:" .. q.rank .. " ") or "") .. "sort:list " end
function PR.Footer() return ns.Detail(L["PvP rank"], LG.RankText((LG.PvpRank()))) end
function PR.None() return { ns.NoteRow(LG.NONE) } end

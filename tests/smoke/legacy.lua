-- WoW Forever's Legacy and PvP ranks (Providers/Legacy.lua): the generated block's shape; @legacy (challenges, one per
-- name and category, is:todo, cat:), the points, @legacyreward (Enter: a waypoint to the innkeeper), @legacyperk
-- (C_Traits), @pvprank (rank:), the questions. The game's calls are mocked here and put back at the end.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local LG = ns.Legacy
local P = ns.providers

io.write("[legacy: the generated block]\n")
do
	local ok, cats = #LG.CHALLENGES >= 100, {}
	for _, c in ipairs(LG.CHALLENGES) do
		if not (type(c[1]) == "number" and type(c[2]) == "number" and c[2] >= 15568 and c[2] <= 15626 and type(c[3]) == "number" and c[3] >= 1) then ok = false end
		cats[c[2]] = true
	end
	check(ok and cats[15579] and cats[15588] and cats[15593], "challenges: { achievement, category (15568-15626), points }: " .. #LG.CHALLENGES)
	local shaped, tracks = #LG.REWARDS > 0, {}
	for _, r in ipairs(LG.REWARDS) do
		if #r ~= 8 then shaped = false end
		for i = 1, 8 do if type(r[i]) ~= "number" then shaped = false end end
		tracks[r[2]] = (tracks[r[2]] or 0) + 1
	end
	check(shaped and tracks[LG.LEGACY_TRACK] == 4 and (tracks[LG.PVP_TRACK] or 0) >= 14, "rewards: 8 numbers each, both tracks")
	check(LG.CLASS_OF[15579] == "MAGE" and LG.LEGACY_FACTION == 2802 and LG.PVP_FACTION == 2800 and LG.POINTS_CURRENCY == 4225
		and #LG.TREES == 3 and type(LG.CLAIM.npc) == "string" and LG.CURRENCY.rankPoints == 3468,
		"the ids Blizzard's windows use, and who gives the rewards: " .. tostring(LG.CLAIM.npc))
end

-- the game, as far as these lists read it
local was = { info = _G.GetAchievementInfo, num = _G.GetCategoryNumAchievements, cat = _G.GetCategoryInfo, mf = _G.C_MajorFactions,
	traits = _G.C_Traits, cur = C_CurrencyInfo.GetCurrencyInfo, item = C_Item.GetItemNameByID, spell = C_Spell.GetSpellName,
	desc = C_Spell.GetSpellDescription, trace = ns.Trace, npcId = ns.Integrations.NpcIdNamed, npcRow = ns.Integrations.NpcRow,
	pin = ns.Integrations.NpcPin, print = ns.Print, easy = ns.db.easyMode, frame = _G.LegacySystemFrame, output = ns.Output }
local ACH = { -- id = { name, completed, description }
	[61994] = { "Novice Mage", false, "Reach Level 25 for the first time on a Mage" },
	[63978] = { "Novice Mage", true, "Reach Level 25 for the first time on a Mage" },
	[63979] = { "Experienced Mage", false, "Reach Level 45 for the first time on a Mage" },
	[62015] = { "Journeyman Blacksmith", false, "Reach 75 skill in Blacksmithing" },
	[684] = { "Conqueror of the Lair", true, "Defeat Onyxia" },
	[64283] = { "Played in the WoW: Forever Beta", false, "Played in the beta" },
}
local LISTED = { [15579] = { 63978, 63979 }, [15588] = { 62015 }, [15594] = { 684 }, [15596] = { 64283 } }
local CATS = { [15579] = { "Mage", 15568 }, [15568] = { "Classes", -1 }, [15588] = { "Blacksmithing", 15586 },
	[15586] = { "Tradeskills", -1 }, [15594] = { "Raids", -1 }, [15596] = { "Adventure", -1 } }
_G.GetAchievementInfo = function(a, i)
	local id = a
	if i then id = LISTED[a] and LISTED[a][i] end
	local x = id and ACH[id]
	if not x then return nil end
	return id, x[1], 0, x[2], 1, 1, 26, x[3], 0, 136000 + id % 1000
end
_G.GetCategoryNumAchievements = function(c) return LISTED[c] and #LISTED[c] or 0 end
_G.GetCategoryInfo = function(c) local x = CATS[c] if x then return x[1], x[2] end end
local renown, pvp = 20, { renownLevel = 11, renownReputationEarned = 1200, renownLevelThreshold = 3000 }
_G.C_MajorFactions = {
	GetCurrentRenownLevel = function(f) if f == 2802 then return renown end return 0 end,
	GetMajorFactionProgressionInfo = function(f) if f == 2800 then return pvp end end,
	GetRenownRewardsForLevel = function(f, lvl)
		if f == 2802 and lvl == 15 then return { { renownRewardID = 1856, name = "Replica Ironforge Air Rifle", description = "Join a shootout." } } end
		if f == 2802 and lvl == 25 then return { { renownRewardID = 1857, name = "Spectral Bear Cub", icon = 294471 } } end
		if f == 2800 and lvl == 11 then return { { renownRewardID = 2009, name = "Rank 11 Rewards", description = "Black War Mounts" } } end
		if f == 2800 and lvl == 1 then return { { renownRewardID = 1832, name = "Rank 1 Rewards", description = "Faction Tabard" } } end
		if f == 2800 and lvl == 12 then return { { renownRewardID = 1843, description = "Elite Leg Upgrade" }, { renownRewardID = 2010, description = "Elite Shoulder Upgrade" } } end
		return {}
	end,
}
C_CurrencyInfo.GetCurrencyInfo = function(id) if id == 3468 then return { quantity = 1200, name = "Rank Points" } end end
C_Item.GetItemNameByID = function(id) if id == 277717 then return "Spectral Bear Tabard" end end
local PERK_TREES = { [1187] = { 5001, 5002 }, [1188] = { 5003 }, [1189] = {} }
_G.C_Traits = {
	GetConfigIDByTreeID = function(t) if PERK_TREES[t] then return 900 end end,
	GetTreeCurrencyInfo = function(c, t) if c == 900 and t == 1187 then return { { traitCurrencyID = 4225, quantity = 3, spent = 17 } } end return {} end,
	GetTreeNodes = function(t) return PERK_TREES[t] end,
	GetNodeInfo = function(_, n)
		if n == 5001 then return { isVisible = true, maxRanks = 3, activeRank = 2, entryIDs = { 61 } } end
		if n == 5002 then return { isVisible = true, maxRanks = 1, activeRank = 0, activeEntry = { entryID = 62 }, entryIDs = { 62 } } end
		if n == 5003 then return { isVisible = false, maxRanks = 1, activeRank = 0, entryIDs = { 63 } } end
	end,
	GetEntryInfo = function(_, e) return { definitionID = e + 10 } end,
	GetDefinitionInfo = function(d)
		if d == 71 then return { spellID = 9001 } end
		if d == 72 then return { overrideName = "Swift Learner", overrideDescription = "Learn faster." } end
		return {}
	end,
}
C_Spell.GetSpellName = function(id) if id == 9001 then return "Herbal Insight" end return was.spell(id) end
C_Spell.GetSpellDescription = function(id) if id == 9001 then return "Find more herbs." end end
local traced = {}
ns.Trace = function(_, msg) traced[#traced + 1] = msg end
local pinned, printed = nil, {}
ns.Integrations.NpcIdNamed = function(n) if n == "innkeeper wiley" then return 6791 end end
ns.Integrations.NpcRow = function(id) if id == 6791 then return { name = "Innkeeper Wiley" } end end
ns.Integrations.NpcPin = function(e) pinned = e end
ns.Print = function(_, msg) printed[#printed + 1] = msg end
ns.Output = function() end
ns.db.easyMode = false; UI:EasyChanged()

local function Fresh() for _, id in ipairs({ "legacy", "legacyreward", "legacyperk", "pvprank" }) do P[id]._dirty = true end UI.lastScan, UI.lastExtra = nil, nil end
local function Rows(id) Fresh() return ns:GetEntries(P[id]) end
local function Names(rows)
	local t = {}
	for _, e in ipairs(rows) do if e.name and not e.noActivate and e.kind then t[#t + 1] = e.name end end
	return table.concat(t, ", ")
end
local function ByName(rows, name) for _, e in ipairs(rows) do if e.name == name then return e end end end

io.write("[legacy: challenges, points]\n")
do
	local rows = Rows("legacy")
	check(rows[1] and rows[1].name == "Legacy points: 20" and tostring(rows[1].detail):find("3 to spend", 1, true)
		and tostring(rows[1].detail):find("2 of 5 done", 1, true),
		"the points on top: the reward track's level, the tree's unspent, challenges done: " .. tostring(rows[1] and rows[1].name) .. " / " .. tostring(rows[1] and rows[1].detail))
	local mage, n = nil, 0
	for _, e in ipairs(rows) do if e.name == "Novice Mage" then mage = e n = n + 1 end end
	check(n == 1 and mage.key == 63978 and mage.isDone == true, "a challenge under two ids: one row, the one the game lists: " .. n .. " " .. tostring(mage and mage.key))
	local exp = ByName(rows, "Experienced Mage")
	check(exp and exp.isDone == false and tostring(exp.detail) == "Mage" and exp.classFile == "MAGE"
		and ByName(rows, "Journeyman Blacksmith").detail == "Blacksmithing", "its group is the category's name: " .. tostring(exp and exp.detail))
	check(tostring(ByName(rows, "Played in the WoW: Forever Beta").detail):find("16 pts", 1, true), "16 points: said")
	check(#rows == 6, "only the achievements the game has: " .. #rows)
	check(exp.secure == LG.SECURE and LG.SECURE.binding == "TOGGLEACHIEVEMENT" and exp.isOpen(exp) == false and exp.getLink
		and exp.secondary, "Enter: the achievement key (the Legacy window on Challenges); Shift+Enter: its link")
	_G.LegacySystemFrame = { IsShown = function() return true end, currentPage = 2 }
	check(exp.isOpen(exp) == true, "Challenges already shown: nothing pressed")
	_G.LegacySystemFrame = was.frame
	check(Names(UI:Search("@legacy is:todo sort:list")) == "Experienced Mage, Journeyman Blacksmith, Played in the WoW: Forever Beta",
		"@legacy is:todo: " .. Names(UI:Search("@legacy is:todo sort:list")))
	check(Names(UI:Search("@legacy is:done sort:list")) == "Novice Mage, Conqueror of the Lair", "@legacy is:done: " .. Names(UI:Search("@legacy is:done sort:list")))
	check(Names(UI:Search("@legacy cat:mage sort:list")) == "Novice Mage, Experienced Mage", "cat:mage: " .. Names(UI:Search("@legacy cat:mage sort:list")))
	check(Names(UI:Search("@legacy cat:tradeskills")) == "Journeyman Blacksmith" and Names(UI:Search("@legacy cat:blacksmith")) == "Journeyman Blacksmith",
		"cat: a parent's name, a start: " .. Names(UI:Search("@legacy cat:tradeskills")))
	check(LG.GroupHas("player vs. player", "pvp") and not LG.GroupHas("raids", "pvp"), "cat:pvp: Player vs. Player by its initials")
	-- no reward track, no currency: the points of the challenges done
	local mf = _G.C_MajorFactions
	_G.C_MajorFactions = nil
	rows = Rows("legacy")
	check(rows[1].name == "Legacy points: 2", "no track or currency: the challenges done count: " .. tostring(rows[1].name))
	_G.C_MajorFactions = mf
end

io.write("[legacy: rewards, the innkeeper]\n")
do
	local rows = Rows("legacyreward")
	check(Names(rows) == "Replica Ironforge Air Rifle, Spectral Bear Cub, Spectral Bear Tabard",
		"the game's names, else the item's; one with no name left out: " .. Names(rows))
	local rifle, cub = rows[1], rows[2]
	check(rifle.isDone == true and tostring(rifle.detail):find("15 pts", 1, true) and tostring(rifle.detail):find("(reached)", 1, true)
		and tostring(rifle.detail):find("Innkeeper Wiley, Ratchet", 1, true), "15 points, you have 20: " .. tostring(rifle.detail))
	check(cub.isDone == false and tostring(cub.detail):find("need 5", 1, true) and cub.icon == 294471, "25 points: 5 more: " .. tostring(cub.detail))
	rifle.activate(rifle)
	check(pinned and pinned.npcID == 6791 and pinned.name == "Innkeeper Wiley", "Enter: a waypoint to him (Questie's NPC)")
	ns.Integrations.NpcIdNamed = function() return nil end
	printed = {}
	LG.ToClaimer()
	check(printed[1] and printed[1]:find("Innkeeper Wiley", 1, true), "Questie doesn't know him: said: " .. tostring(printed[1]))
	ns.Integrations.NpcIdNamed = was.npcId
end

io.write("[legacy: the tree's perks]\n")
do
	local rows = Rows("legacyperk")
	local herb, swift = ByName(rows, "Herbal Insight"), ByName(rows, "Swift Learner")
	check(#rows == 2 and herb and herb.rank == 2 and herb.maxRank == 3 and tostring(herb.detail):find("2/3", 1, true) and herb.tip == "Find more herbs."
		and swift and swift.isDone == false and swift.tip == "Learn faster.", "ranks taken of the most, what each does: " .. Names(rows))
	local tr = _G.C_Traits
	_G.C_Traits = { GetConfigIDByTreeID = function() return nil end }
	traced = {}
	rows = Rows("legacyperk")
	check(#rows == 0 and traced[1] and traced[1]:find("legacy: no perks read: no config", 1, true), "nothing from the game: no rows, a trace line: " .. tostring(traced[1]))
	_G.C_Traits = tr
end

io.write("[legacy: pvp ranks]\n")
do
	local rows = Rows("pvprank")
	check(rows[1] and rows[1].name:find("Rank 11", 1, true) and rows[1].detail == "Rank Points 1200/3000", "your rank and Rank Points first: "
		.. tostring(rows[1] and rows[1].name) .. " / " .. tostring(rows[1] and rows[1].detail))
	check(Names(rows) == "Rank 11, Faction Tabard, Black War Mounts, Elite Leg Upgrade, Elite Shoulder Upgrade",
		"the game's names; your side's of a pair; none named: left out: " .. Names(rows))
	local tabard, leg = ByName(rows, "Faction Tabard"), ByName(rows, "Elite Leg Upgrade")
	check(tabard.isDone == true and tostring(tabard.detail):find("(reached)", 1, true) and leg.isDone == false, "(reached) up to your rank")
	check(Names(UI:Search("@pvprank rank:12")) == "Elite Leg Upgrade, Elite Shoulder Upgrade", "rank:12: " .. Names(UI:Search("@pvprank rank:12")))
	check(not leg.level and Names(UI:Search("@pvprank lvl:12")) == "", "a rank isn't a level")
end

io.write("[legacy: questions]\n")
do
	local Q = ns.Questions
	local function Top(line) local c = Q.Ranked(line)[1] return c and c.a.id end
	ns.db.easyMode = true; UI:EasyChanged()
	Fresh()
	local want = { ["legacy points"] = "LegacyPoints", ["which legacy points am i missing"] = "LegacyPoints",
		["what gives legacy points for mage"] = "LegacyPoints", ["legacy rewards"] = "LegacyRewards", ["legacy perks"] = "LegacyPerks",
		["my perks"] = "LegacyPerks", ["my pvp rank"] = "PvpRank", ["rank points"] = "PvpRank", ["what does pvp rank 11 unlock"] = "PvpRank" }
	for line, id in pairs(want) do check(Top(line) == id, ("\"%s\": %s's: %s"):format(line, id, tostring(Top(line)))) end
	local MINE = { LegacyPoints = true, LegacyRewards = true, LegacyPerks = true, PvpRank = true }
	local function Taken(line) for _, c in ipairs(Q.Ranked(line)) do if MINE[c.a.id] then return c.a.id end end end
	check(not Taken("legacy tree") and not Taken("legacy") and not Taken("the challenge") and not Taken("rank 3 fireball") and not Taken("pvp rank 20"),
		"\"legacy tree\" (the window's row), \"legacy\", \"the challenge\", \"rank 3 fireball\", \"pvp rank 20\": not these questions")
	local adv = {
		["legacy points"] = "@legacy sort:list ", ["which legacy points am i missing"] = "@legacy is:todo sort:list ",
		["what gives legacy points for mage"] = "@legacy is:todo cat:mage sort:list ", ["legacy challenges done"] = "@legacy is:done sort:list ", ["legacy challenges i havent done"] = "@legacy is:todo sort:list ",
		["blacksmithing legacy points"] = "@legacy cat:blacksmithing sort:list ", ["legacy rewards"] = "@legacyreward sort:list ",
		["legacy perks"] = "@legacyperk sort:list ", ["my pvp rank"] = "@pvprank sort:list ",
		["what does pvp rank 11 unlock"] = "@pvprank rank:11 sort:list " }
	for line, a in pairs(adv) do
		local got = ns.QueryToAdvanced(line)
		check(got == a, ("Alt+` \"%s\": %s"):format(line, tostring(got)))
	end
	local function Ask(line) Fresh() local rows, note = Q.Answer(line) return Names(rows), note end
	local got, note = Ask("legacy points")
	check(got:find("^Legacy points: 20, Novice Mage") and note == "Legacy points: 20  ·  2 of 5 done", "\"legacy points\": " .. got .. " / " .. tostring(note))
	got = Ask("which legacy points am i missing")
	check(got == "Experienced Mage, Journeyman Blacksmith, Played in the WoW: Forever Beta", "\"which legacy points am i missing\": " .. got)
	got = Ask("what gives legacy points for mage")
	check(got == "Experienced Mage", "\"what gives legacy points for mage\": " .. got)
	got = Ask("legacy rewards")
	check(got == "Replica Ironforge Air Rifle, Spectral Bear Cub, Spectral Bear Tabard", "\"legacy rewards\": " .. got)
	got = Ask("legacy perks")
	check(got == "Herbal Insight, Swift Learner", "\"legacy perks\": " .. got)
	got, note = Ask("my pvp rank")
	check(got:find("^Rank 11") and tostring(note):find("Rank 11", 1, true), "\"my pvp rank\": " .. got .. " / " .. tostring(note))
	got = Ask("what does pvp rank 11 unlock")
	check(got == "Black War Mounts", "\"what does pvp rank 11 unlock\": " .. got)
	-- the Legacy window's row for that page on top (Panels.lua's); with nothing found, it stays
	local ge = ns.GetEntries
	local row = { name = "Legacy Rewards", tab = "LegacySystemFrame.LegacyRewardTrackTab", key = "lr" }
	ns.GetEntries = function(self, p) if p == P.panels then return { row } end return ge(self, p) end
	local lead = ns.LegacyRewards.Lead()
	local none = ns.LegacyRewards.None()
	ns.GetEntries = ge
	check(lead and lead[1] == row and none[1] == row and none[2] and none[2].noActivate, "the window's row first, and with nothing found")
	ns.db.easyMode = false; UI:EasyChanged()
end

_G.GetAchievementInfo, _G.GetCategoryNumAchievements, _G.GetCategoryInfo, _G.C_MajorFactions, _G.C_Traits = was.info, was.num, was.cat, was.mf, was.traits
C_CurrencyInfo.GetCurrencyInfo, C_Item.GetItemNameByID, C_Spell.GetSpellName, C_Spell.GetSpellDescription = was.cur, was.item, was.spell, was.desc
ns.Trace, ns.Integrations.NpcIdNamed, ns.Integrations.NpcRow, ns.Integrations.NpcPin, ns.Print, ns.Output = was.trace, was.npcId, was.npcRow, was.pin, was.print, was.output
_G.LegacySystemFrame = was.frame
ns.db.easyMode = was.easy; UI:EasyChanged()
Fresh()

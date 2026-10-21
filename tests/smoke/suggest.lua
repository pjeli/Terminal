-- (0.61.0, the player's ask) "what should i do": things worth doing now, from what Terminal knows of your character
-- (Suggest.lua); the top few on Simple mode's empty prompt. "quests to turn in", "quests here" and "class trainer" /
-- "weapon trainer" asked in plain words, each with its Advanced syntax.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local L = ns.L
io.write("[suggest: what should i do, and its try: in the empty prompt]\n")
local SG, TI, QH = ns.Suggest, ns.TurnIn, ns.QuestsHere
check(SG and TI and QH, "Suggest.lua loaded")

local function Is(f, s) local ok, q = pcall(f, s) return ok and q ~= nil end
-- the questions
for _, s in ipairs({ "what should i do", "What should I do now?", "what now", "suggestions", "im bored", "so what should i do please" }) do
	check(Is(SG.Question, s), "asks for things to do: " .. s)
end
check(not Is(SG.Question, "what should i do in deadmines") and not Is(SG.Question, "@npc what now") and not Is(SG.Question, "suggest -x"),
	"only those words; Advanced syntax is never a question")
for _, s in ipairs({ "quests to turn in", "turn in quests", "complete quests", "which quests are ready", "quests ready to turn in", "hand in quests" }) do
	check(Is(TI.Question, s), "ready to turn in: " .. s)
end
check(not Is(TI.Question, "quests") and not Is(TI.Question, "done quest chains in zangarmarsh") and not Is(TI.Question, "turn in"),
	"not every quest line")
check(Is(QH.Question, "quests here") and Is(QH.Question, "quests in this zone") and not Is(QH.Question, "quests here kobold"), "quests here")

-- every one has its Advanced syntax (a question that stays as typed answers in Advanced mode too)
check(ns.QuestionToAdvanced("quests to turn in") == "@questlog is:complete ", "turn in as Advanced: " .. tostring(ns.QuestionToAdvanced("quests to turn in")))
-- (review: "done quests", "completed quests", "finished quest" stay the quests you've done, is:done, as before)
for _, s in ipairs({ "done quests", "completed quests", "finished quest", "quest done" }) do
	check(not Is(TI.Question, s), "the done quests' words: " .. s)
end
check(ns.Zones.Question("quests at my level") == nil, "\"quests at my level\": a search, not where to level")
do
	local save = { lvl = _G.UnitLevel, zone = _G.GetRealZoneText }
	_G.UnitLevel = function() return 22 end
	_G.GetRealZoneText = function() return "The Barrens" end
	check(QH.ToAdvanced() == '@questie lvl:20-25 in:"the barrens" ', "quests here as Advanced: " .. tostring(QH.ToAdvanced()))
	_G.UnitLevel, _G.GetRealZoneText = save.lvl, save.zone
end
check(ns.QuestionToAdvanced("what should i do") == "what should i do ", "what should i do stays as typed (answered in Advanced too)")
local E = ns.Easy
local function Adv(s) return (E.ToAdvanced(s) or ""):gsub("%s+$", "") end
check(Adv("nearest class trainer"):find("trainer:class", 1, true) and not Adv("nearest class trainer"):find(" class ", 1, true),
	"\"class trainer\": your class's, not the word class: " .. Adv("nearest class trainer"))
check(Adv("my trainer"):find("trainer:class", 1, true), "\"my trainer\": " .. Adv("my trainer"))
check(Adv("nearest weapon trainer"):find("is:weaponmaster", 1, true) and not Adv("nearest weapon trainer"):find(" weapon", 1, true),
	"\"weapon trainer\": the weapon masters: " .. Adv("nearest weapon trainer"))
check(Adv("weapon master"):find("is:weaponmaster", 1, true), "\"weapon master\": " .. Adv("weapon master"))
check(Adv("mining trainer"):find("trainer:mining", 1, true), "a profession's still its own: " .. Adv("mining trainer"))
-- (the player: "nearest fist weapons trainer" found none on the continent, "near fists trainer" Sayoc) the weapon, the
-- profession named: theirs, "my" / "weapons" / "class" set aside, no word left to look for in names
for line, want in pairs({ ["nearest fist weapons trainer"] = "@npc trainer:fist faction:friendly sort:nearest",
	["nearest fist weapon trainer"] = "@npc trainer:fist faction:friendly sort:nearest",
	["sword weapon trainer"] = "@npc trainer:sword faction:friendly sort:nearest",
	["nearest my tailoring trainer"] = "@npc trainer:tailoring faction:friendly sort:nearest",
	["my weapon trainer"] = "@npc is:weaponmaster faction:friendly sort:nearest",
	["class trainer"] = "@npc trainer:class faction:friendly sort:nearest" }) do
	check(Adv(line) == want, ("%q: %s"):format(line, Adv(line)))
end
check(Adv("dagger trainer"):find("trainer:dagger", 1, true) or Adv("dagger trainer"):find("trainer:", 1, true),
	"a weapon by name still its masters: " .. Adv("dagger trainer"))

-- the suggestions, from a character in need of everything
local save = { du = ns.Durability.Total, CC = _G.C_Container, CI = _G.C_Item, prof = ns.Professions.PlayerProfessions,
	ts = ns.TrainerSpells and ns.TrainerSpells.NextRank, get = ns.GetEntries, prov = {}, lvl = _G.UnitLevel, class = _G.UnitClass,
	theme = ns.Theme.Get }
for _, id in ipairs({ "training", "quests", "attune" }) do save.prov[id] = ns.providers[id] end
ns.Durability.Total = function() return 12345, 3, 18 end
local bag = { { quality = 0, stackCount = 2, itemID = 1 }, { quality = 0, stackCount = 1, itemID = 2 }, { quality = 2, stackCount = 1, itemID = 3 } }
_G.C_Container = setmetatable({
	GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
	GetContainerNumFreeSlots = function(b) return b == 0 and 13 or 0 end,
	GetContainerItemInfo = function(b, s) return b == 0 and bag[s] or nil end,
}, { __index = save.CC })
_G.C_Item = setmetatable({ GetItemInfo = function(id) return "x", nil, 0, 1, 1, "", "", 1, "", "", id == 1 and 25 or 10 end }, { __index = save.CI })
ns.providers.training = { _entries = { { name = "Frostbolt", state = "now", cost = 100 }, { name = "Blink", state = "now", cost = 200 },
	{ name = "Swords", state = "now", weapon = true }, { name = "Arcane Brilliance", state = "later" } } }
ns.providers.quests = { _entries = { { name = "The Fargodeep Mine", complete = true }, { name = "Kobold Candles" } } }
ns.providers.attune = nil
ns.GetEntries = function(self, p) return rawget(p, "collect") and save.get(self, p) or p._entries end
ns.Professions.PlayerProfessions = function() return { { name = "Tailoring", rank = 75, maxRank = 75 }, { name = "Herbalism", rank = 1, maxRank = 150 },
	{ name = "Mining", rank = 20, maxRank = 150 }, { name = "Cooking", rank = 5, maxRank = 75 } } end
if ns.TrainerSpells then ns.TrainerSpells.NextRank = function() return nil end end
_G.UnitLevel = function() return 10 end
_G.UnitClass = function() return "Mage", "MAGE" end
SG.Forget()

local rows = SG.Rows(true, 20)
local by = {}
for i, r in ipairs(rows) do by[r.suggestId] = r; r._at = i end
check(by.repair and (by.repair.searchText == "durability" or by.repair.searchText == "nearest repair") and by.repair.detail:find("18%", 1, true), "low gear: repair, its lowest piece")
check(by.junk and by.junk.detail:find("3 grey items", 1, true), "grey items: sell them (" .. tostring(by.junk and by.junk.detail) .. ")")
check(by.train and by.train.detail:find("2 spells", 1, true), "spells to learn now (not the later one)")
check(by.weapon and by.weapon.detail:find("Swords", 1, true), "a weapon skill to learn")
check(by["rank:tailoring"], "a profession at its cap: its next rank")
check(not by["rank:mining"], "(not one under its cap)")
do
	local lv = _G.UnitLevel
	_G.UnitLevel = function() return 8 end
	SG.Forget()
	local hit = false
	for _, r in ipairs(SG.Rows(true, 20)) do if r.suggestId == "rank:tailoring" then hit = true end end
	check(not hit, "Journeyman asks level 10: not at 8")
	_G.UnitLevel = lv
	SG.Forget()
end
check(by["level:cooking"] and not by["level:mining"] and not by["level:herbalism"], "the profession furthest from its cap (herbalism's gathered: no plan)")
check(by.turnin and by.turnin.name:find("1", 1, true) and by.turnin.searchText == "quests to turn in", "a quest to turn in")
check(by.repair._at == 1, "a worn piece at 18% first")
-- a class quest of your level (Attune): yours, not another class's (Attune tracks none of those for you)
do
	local AT = ns.Attune
	local saveRec, saveMine = AT.RecOf, AT.Mine
	local recs = { mine = { group = "class", minLevel = 10 }, other = { group = "class", minLevel = 8 }, later = { group = "class", minLevel = 30 } }
	AT.RecOf = function(e) return recs[e.id] end
	AT.Mine = function(rec) if rec == recs.other then return nil end return 20 end
	ns.providers.attune = { _entries = { { name = "Warrior's Quest", id = "other" }, { name = "Mage's Quest", id = "mine" }, { name = "Later Quest", id = "later" } } }
	SG.Forget()
	local cq
	for _, r in ipairs(SG.Rows(true, 20)) do if r.suggestId == "classquest" then cq = r end end
	check(cq and cq.name:find("Mage's Quest", 1, true) and cq.detail:find("20%", 1, true) and cq.searchText == "steps for mage's quest",
		"your class quest for your level: " .. tostring(cq and cq.name))
	AT.RecOf, AT.Mine = saveRec, saveMine
	ns.providers.attune = nil
	SG.Forget()
end
for _, r in ipairs(rows) do
	check(r.kind == "suggestion" and r.raw and r.staysOpen and type(r.activate) == "function" and r.searchText ~= "", "a row that searches: " .. r.suggestId)
	-- what it searches is understood: a question, or a search with results' syntax
	local adv = ns.QueryToAdvanced(r.searchText)
	check(adv and adv ~= "", "its search writes as Advanced: " .. r.searchText .. " -> " .. tostring(adv))
end
check(by.train.searchText == "what can i train" or by.train.searchText == "nearest mage trainer", "train: " .. by.train.searchText)
check(Is(ns.Plan.Question or function() end, by["level:cooking"].searchText) or by["level:cooking"].searchText == "cooking plan", "level: its plan")
-- asked: rows and a note
local got, note = SG.Answer()
check(#got >= 5 and #got <= SG.MAX and note:find("Things to do", 1, true), "\"what should i do\" answers with rows")
-- every one done: a note says so
ns.Durability.Total = function() return 0, 0, 100 end
bag = {}
ns.providers.training._entries, ns.providers.quests._entries = {}, {}
ns.Professions.PlayerProfessions = function() return {} end
SG.Forget()
got = SG.Answer()
check(#got == 1 and got[1].kind ~= "suggestion", "nothing pressing: a note, not an empty list")

-- nothing pressing: the empty prompt's example isn't "what should i do"
local E = ns.Easy
local wasEasy = ns.db.easyMode
ns.db.easyMode = true; UI:EasyChanged()
check(not SG.Pressing(), "nothing pressing")
for _ = 1, 3 do
	UI:Open(""); T.FlushAll()
	check(UI:SuggestionText() ~= "what should i do", "nothing pressing: not offered: " .. tostring(UI:SuggestionText()))
	UI:Hide(); T.FlushAll()
end

-- (the player: "i actually prefer an empty bar on key press... let's make 'what should i do' be a 'try:' suggestion")
-- something worth doing: the empty prompt stays empty; "try: what should i do" is among its examples, weighted up (0.61.4,
-- the player: every other open was "too obvious", "it should be part of the random group")
ns.Durability.Total = function() return 500, 1, 5 end
-- (opening reads no list: your worn pieces' wear as the game says, a quest's readiness as the game says now)
local saveDur, saveQL = _G.GetInventoryItemDurability, _G.C_QuestLog
_G.GetInventoryItemDurability = function(slot) if slot == 5 then return 5, 100 end if slot == 7 then return 70, 70 end end
local ready = { [101] = true }
_G.C_QuestLog = setmetatable({ GetLogIndexForQuestID = function(id) return ready[id] ~= nil and 1 or nil end,
	ReadyForTurnIn = function(id) return ready[id] == true end }, { __index = saveQL })
ns.providers.quests._entries = { { name = "A", complete = true, questID = 101 } }
ns.providers.quests._dirty = true -- (made again on every open: the last one read is what's there)
ns.providers.training._entries = { { name = "Frostbolt", state = "now" } }
SG.Forget()
local built = false
ns.GetEntries = function(self, p) built = true return rawget(p, "collect") and save.get(self, p) or p._entries end
-- (a round of the examples: each once, "what should i do" among them, not every other open)
local n = #E.ExamplePool()
local offered, seen = 0, {}
for _ = 1, n do
	SG.Forget()
	UI:Open(""); T.FlushAll()
	check(#UI.Results() == 0, "the empty prompt stays empty: " .. #UI.Results())
	local ex = UI:SuggestionText()
	if ex == "what should i do" then offered = offered + 1 end
	UI:Hide(); T.FlushAll()
end
check(n > 10 and offered == 1, "\"try: what should i do\" once in a round of " .. n .. " examples: " .. offered)
-- weighted up: sooner in the shuffle than an example for anywhere (E.Ordered: a weighted shuffle)
do
	local seed = 7
	local rand = E.rand01
	E.rand01 = function() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
	local function AvgAt(todo)
		local sum = 0
		for _ = 1, 400 do
			local list = { { "what should i do", todo = todo } }
			for i = 1, 30 do list[#list + 1] = { "anywhere " .. i } end
			for i, x in ipairs(E.Ordered(list, "field")) do if x[1] == "what should i do" then sum = sum + i end end
		end
		return sum / 400
	end
	local plain, up = AvgAt(nil), AvgAt(true)
	check(up < plain / 2, ("weighted up: about %.1f of 31 (plain %.1f)"):format(up, plain))
	E.rand01 = rand
end
check(not built, "opening builds no list")
ns.GetEntries = function(self, p) return rawget(p, "collect") and save.get(self, p) or p._entries end
-- what it reads: the worn piece, the quest still ready, not a list out of date
local rows = SG.Rows(false, 20)
local by2 = {}
for _, r in ipairs(rows) do by2[r.suggestId] = r end
check(by2.repair and by2.repair.detail:find("5%", 1, true) and by2.turnin and by2.train, "from lists already read: repair, turn in, train")
ready[101] = nil -- (turned in since)
ns.providers.training._dirty = true -- (a spell learned since)
SG.Forget()
by2 = {}
for _, r in ipairs(SG.Rows(false, 20)) do by2[r.suggestId] = r end
check(not by2.turnin and not by2.train, "turned in since, a list out of date: not taken")
ns.providers.training._dirty = nil
-- Advanced: its own examples
ns.db.easyMode = false; UI:EasyChanged()
ready[101] = true
for _ = 1, 3 do
	SG.Forget()
	UI:Open(""); T.FlushAll()
	check(UI:SuggestionText() ~= "what should i do", "Advanced: its own examples")
	UI:Hide(); T.FlushAll()
end
ns.db.easyMode = wasEasy; UI:EasyChanged()
_G.GetInventoryItemDurability, _G.C_QuestLog = saveDur, saveQL
ns.providers.quests._dirty = nil

ns.Durability.Total, _G.C_Container, _G.C_Item, ns.Professions.PlayerProfessions = save.du, save.CC, save.CI, save.prof
if ns.TrainerSpells then ns.TrainerSpells.NextRank = save.ts end
ns.GetEntries, _G.UnitLevel, _G.UnitClass = save.get, save.lvl, save.class
for _, id in ipairs({ "training", "quests", "attune" }) do ns.providers[id] = save.prov[id] end -- (nil ones too)
SG.Forget()

-- the questions the audit found asked in plain words but searched as words
io.write("[suggest: plain questions with their Advanced syntax]\n")
check(ns.QuestionToAdvanced("low durability") == "@durability ", "\"low durability\": " .. tostring((ns.QuestionToAdvanced("low durability"))))
check(ns.Zones.Question("dungeons at my level") == "dungeon" and ns.Zones.Question("best dungeon for upgrades") == "dungeon",
	"\"dungeons at my level\", \"best dungeon for upgrades\": the dungeon for your level")
check(ns.Zones.Question("best quest upgrades") == nil, "\"best quest upgrades\": not a zone question")
do
	local CC = ns.CanCraft
	check(Is(CC.Question, "what can i craft") and Is(CC.Question, "craftable") and Is(CC.Question, "what can i cook"),
		"what can i craft / craftable / what can i cook")
	check(not Is(CC.Question, "craft") and not Is(CC.Question, "make") and not Is(CC.Question, "what can i craft kobold")
		and not Is(CC.Question, "cook") and not Is(CC.Question, "make leather"),
		"\"craft\", \"cook\" alone, words of a search, a profession's first letters: not it")
	check(ns.QuestionToAdvanced("what can i craft") == "@recipe is:craftable ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("what can i craft")))
	check(ns.QuestionToAdvanced("what can i cook") == "@recipe is:craftable cooking ", "cook: " .. tostring(ns.QuestionToAdvanced("what can i cook")))
	local saveR, saveG, saveC = ns.providers.recipes, ns.GetEntries, C_Item.GetItemCount
	ns.providers.recipes = { _entries = {
		{ name = "Linen Bandage", recipeID = 1, profName = "First Aid", reagents = { { 2589, 1 } } },
		{ name = "Spiced Wolf Meat", recipeID = 2, profName = "Cooking", reagents = { { 2672, 1 } } },
		{ name = "Bolt of Linen Cloth", recipeID = 3, profName = "Tailoring", reagents = { { 2589, 2 } } },
		{ name = "Heavy Linen Gloves", recipeID = 4, profName = "Tailoring", reagents = { { 2996, 2 } } } } }
	ns.GetEntries = function(self, p) return rawget(p, "collect") and save.get(self, p) or p._entries end
	C_Item.GetItemCount = function(id) return id == 2589 and 2 or 0 end
	local rows = CC.Answer({ profs = {} })
	local names = {}
	for i, e in ipairs(rows) do names[i] = e.name end
	check(table.concat(names, ",") == "Bolt of Linen Cloth,Linen Bandage", "the ones you have every reagent for: " .. table.concat(names, ","))
	rows = CC.Answer({ profs = { "cooking" } })
	check(#rows == 1 and rows[1].kind ~= "recipes" and rows[1].recipeID == nil, "none for cooking: a note")
	ns.providers.recipes, ns.GetEntries, C_Item.GetItemCount = saveR, saveG, saveC
end

-- (review) the weapon row's word, as Simple mode's trainers take it: the client's "Two-Handed Swords" is sword
do
	local NAMES = { [1180] = "Daggers", [201] = "One-Handed Swords", [202] = "Two-Handed Swords", [196] = "One-Handed Axes",
		[197] = "Two-Handed Axes", [198] = "One-Handed Maces", [199] = "Two-Handed Maces", [227] = "Staves", [200] = "Polearms",
		[264] = "Bows", [266] = "Guns", [5011] = "Crossbows", [2567] = "Thrown", [15590] = "Fist Weapons" }
	local saveName = C_Spell.GetSpellName
	C_Spell.GetSpellName = function(id) return NAMES[id] end
	check(SG.WeaponWord("Two-Handed Swords") == "sword" and SG.WeaponWord("Fist Weapons") == "fist" and SG.WeaponWord("Daggers") == "dagger"
		and SG.WeaponWord("Staves") == "staff", "Two-Handed Swords: sword; Fist Weapons: fist; Staves: staff: " .. tostring(SG.WeaponWord("Staves")))
	check(SG.WeaponWord("Riding") == nil, "not a weapon: none")
	C_Spell.GetSpellName = saveName
end

-- (review) bags nearly full: a herb bag's free slots aren't room for loot
do
	local saveCC, saveDU, saveProf = _G.C_Container, ns.Durability.Total, ns.Professions.PlayerProfessions
	_G.C_Container = setmetatable({
		GetContainerNumSlots = function(b) return (b == 0 or b == 1) and 16 or 0 end,
		GetContainerNumFreeSlots = function(b) if b == 0 then return 1, 0 elseif b == 1 then return 16, 32 end return 0, 0 end,
		GetContainerItemInfo = function(b, s) if b == 0 and s == 1 then return { quality = 0, stackCount = 1, itemID = 1 } end end,
	}, { __index = saveCC })
	ns.Durability.Total = function() return 0, 0, 100 end
	ns.Professions.PlayerProfessions = function() return {} end
	SG.Forget()
	local junk
	for _, r in ipairs(SG.Rows(true, 20)) do if r.suggestId == "junk" then junk = r end end
	check(junk and junk.detail:find("1 bag slot free", 1, true), "one grey item, one slot free (the herb bag's not counted): " .. tostring(junk and junk.detail))
	_G.C_Container, ns.Durability.Total, ns.Professions.PlayerProfessions = saveCC, saveDU, saveProf
	SG.Forget()
end

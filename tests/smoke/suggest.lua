-- (0.61.0, the player's ask) "what should i do": things worth doing now, from what Terminal knows of your character
-- (Suggest.lua); the top few on Simple mode's empty prompt. "quests to turn in", "quests here" and "class trainer" /
-- "weapon trainer" asked in plain words, each with its Advanced syntax.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local L = ns.L
io.write("[suggest: what should i do, the empty prompt's things to do]\n")
local SG, TI, QH = ns.Suggest, ns.TurnIn, ns.QuestsHere
check(SG and TI and QH, "Suggest.lua loaded")

local function Is(f, s) local ok, q = pcall(f, s) return ok and q ~= nil end
-- the questions
for _, s in ipairs({ "what should i do", "What should I do now?", "what now", "suggestions", "im bored", "so what should i do please" }) do
	check(Is(SG.Question, s), "asks for things to do: " .. s)
end
check(not Is(SG.Question, "what should i do in deadmines") and not Is(SG.Question, "@npc what now") and not Is(SG.Question, "suggest -x"),
	"only those words; Advanced syntax is never a question")
for _, s in ipairs({ "quests to turn in", "turn in quests", "completed quests", "which quests are ready", "quests ready to turn in", "finished quests" }) do
	check(Is(TI.Question, s), "ready to turn in: " .. s)
end
check(not Is(TI.Question, "quests") and not Is(TI.Question, "done quest chains in zangarmarsh") and not Is(TI.Question, "turn in"),
	"not every quest line")
check(Is(QH.Question, "quests here") and Is(QH.Question, "quests in this zone") and not Is(QH.Question, "quests here kobold"), "quests here")

-- every one has its Advanced syntax (a question that stays as typed answers in Advanced mode too)
check(ns.QuestionToAdvanced("quests to turn in") == "@questlog is:complete ", "turn in as Advanced: " .. tostring(ns.QuestionToAdvanced("quests to turn in")))
check(ns.QuestionToAdvanced("completed quests") == "@questlog is:complete ", "completed quests as Advanced, not the done panel: " .. tostring(ns.QuestionToAdvanced("completed quests")))
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
ns.GetEntries = function(self, p) return p._entries end
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

-- the empty prompt: Simple mode lists the top few; Advanced stays bare; the setting turns them off
ns.Durability.Total = function() return 500, 1, 5 end
bag = { { quality = 0, stackCount = 5, itemID = 1 } }
ns.providers.quests._entries = { { name = "A", complete = true } }
ns.providers.training._entries = { { name = "Frostbolt", state = "now" } }
ns.Professions.PlayerProfessions = function() return { { name = "Tailoring", rank = 75, maxRank = 75 }, { name = "Cooking", rank = 1, maxRank = 75 } } end
SG.Forget()
local wasEasy, wasTodo = ns.db.easyMode, ns.Theme.Get().todo
ns.Theme.Set("todo", "on", true)
ns.db.easyMode = true; UI:EasyChanged()
UI:Open(""); T.FlushAll()
local res = UI.Results()
local n = 0
for _, r in ipairs(res) do if r.kind == "suggestion" then n = n + 1 end end
check(n >= 1 and n <= SG.EMPTY_MAX and #res == n, "Simple's empty prompt: at most " .. SG.EMPTY_MAX .. " things to do (" .. n .. " of " .. #res .. ")")
check(res[1] and res[1].suggestId == "repair", "the most pressing first")
UI:Hide(); T.FlushAll()
check(UI.answerNote == L["Things to do"], "under its note: " .. tostring(UI.answerNote))
check(UI:SuggestionText() ~= nil, "the faint \"try: ...\" example still in the prompt above them")
-- Down goes through them (Up: the lines you ran)
UI:Down()
check(UI.sel == 2 and UI.edit:GetText() == "", "Down: the next thing to do, nothing recalled")
UI:Hide(); T.FlushAll()
ns.Theme.Set("todo", "off", true)
SG.Forget()
UI:Open(""); T.FlushAll()
check(#UI.Results() == 0, "the setting off: the empty prompt bare")
UI:Hide(); T.FlushAll()
ns.Theme.Set("todo", "on", true)
ns.db.easyMode = false; UI:EasyChanged()
UI:Open(""); T.FlushAll()
check(#UI.Results() == 0, "Advanced's empty prompt stays bare")
UI:Hide(); T.FlushAll()
-- the empty prompt reads no list it hasn't read: nothing built to open the terminal
ns.db.easyMode = true; UI:EasyChanged()
local built = false
ns.GetEntries = function(self, p) built = true return p._entries end
SG.Forget()
UI:Open(""); T.FlushAll()
check(not built, "the empty prompt builds no list")
UI:Hide(); T.FlushAll()
ns.db.easyMode = wasEasy; UI:EasyChanged()
ns.Theme.Set("todo", wasTodo == false and "off" or "on", true)

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
	check(not Is(CC.Question, "craft") and not Is(CC.Question, "make") and not Is(CC.Question, "what can i craft kobold"),
		"\"craft\" alone, words of a search: not it")
	check(ns.QuestionToAdvanced("what can i craft") == "@recipe is:craftable ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("what can i craft")))
	check(ns.QuestionToAdvanced("what can i cook") == "@recipe is:craftable cooking ", "cook: " .. tostring(ns.QuestionToAdvanced("what can i cook")))
	local saveR, saveG, saveC = ns.providers.recipes, ns.GetEntries, C_Item.GetItemCount
	ns.providers.recipes = { _entries = {
		{ name = "Linen Bandage", recipeID = 1, profName = "First Aid", reagents = { { 2589, 1 } } },
		{ name = "Spiced Wolf Meat", recipeID = 2, profName = "Cooking", reagents = { { 2672, 1 } } },
		{ name = "Bolt of Linen Cloth", recipeID = 3, profName = "Tailoring", reagents = { { 2589, 2 } } },
		{ name = "Heavy Linen Gloves", recipeID = 4, profName = "Tailoring", reagents = { { 2996, 2 } } } } }
	ns.GetEntries = function(self, p) return p._entries end
	C_Item.GetItemCount = function(id) return id == 2589 and 2 or 0 end
	local rows = CC.Answer({ profs = {} })
	local names = {}
	for i, e in ipairs(rows) do names[i] = e.name end
	check(table.concat(names, ",") == "Bolt of Linen Cloth,Linen Bandage", "the ones you have every reagent for: " .. table.concat(names, ","))
	rows = CC.Answer({ profs = { "cooking" } })
	check(#rows == 1 and rows[1].kind ~= "recipes" and rows[1].recipeID == nil, "none for cooking: a note")
	ns.providers.recipes, ns.GetEntries, C_Item.GetItemCount = saveR, saveG, saveC
end

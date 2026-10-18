-- TrainerSpells (0.57.1, the author's ask; Providers/Integrations/TrainerSpells.lua): its WoW Forever tables read while it's
-- installed. Its trainers as @npc without Questie ("nearest mage trainer"), its weapon masters ("polearm trainer"),
-- @training without What's Training, every class's spells, the recipes a trainer teaches among @recipe is:unknown's
-- ("what can i train in tailoring"), @profession's next rank; and a table not in the shape expected said once in chat
-- with what's unavailable (I.Failed), as for the other integrations.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, TS, CS, F = ns.Integrations, ns.TrainerSpells, ns.ClassSpells, ns.Filters

io.write("[trainerspells: its tables, checked and read]\n")
do
	local G = { "TrainerSpellsBuiltin", "TrainerSpellsClassTrainers", "TrainerSpellsProfessionTrainers", "TrainerSpellsPetTrainers",
		"TrainerSpellsPortalTrainers", "TrainerSpellsBuiltin_Profession", "TrainerSpellsWeaponSkills" }
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, wt = rawget(_G, "WT_API"), race = _G.UnitRace,
		faction = _G.UnitFactionGroup, known = rawget(_G, "IsPlayerSpell"), name = C_Spell.GetSpellName, profs = ns.Professions.PlayerProfessions,
		here = I.Here, dist = I.RowDistance, failed = I.failed, on = TS.on, easy = ns.db.easyMode, class = _G.UnitClass, globals = {},
		level = _G.UnitLevel, sub = C_Spell.GetSpellSubtext, store = ns.Professions.Store }
	for _, g in ipairs(G) do save.globals[g] = rawget(_G, g) end
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Said(s) for _, m in ipairs(said) do if m:find(s, 1, true) then return m end end end
	local ok, err = pcall(function()
		-- its WoW Forever build's tables (data/forever, TrainerSpells_Camelot.toc), a few of each
		_G.TrainerSpellsBuiltin = {
			DRUID = { [10] = { [99] = { cost = 300, rank = 1 } }, [18] = { [1735] = { cost = 900, rank = 2 } }, [20] = { [768] = { cost = 2000, rank = 1 } },
				[24] = { [9005] = { cost = 2500, rank = 2 } } }, -- (Pounce rank 2: its first a quest's)
			PRIEST = { [10] = { [2652] = { cost = 15, rank = 1, race = "Scourge" }, [2006] = { cost = 15, rank = 1 } } },
			WARRIOR = { [1] = { [201] = { cost = 10 } } }, -- (a weapon skill: not a class spell)
		}
		-- (its masters' zoneID an area, its zones table the map of each)
		_G.TrainerSpellsWeaponSkills = { order = { 201, 200, 227 },
			trainers = { [11867] = { zoneID = 1519, x = 63.9, y = 69.1, names = { enUS = "Woo Ping" } },
				[11870] = { zoneID = 1497, x = 57.3, y = 32.8, names = { enUS = "Archibald" } },
				[11865] = { zoneID = 1537, x = 61.2, y = 89.5, names = { enUS = "Buliwyf Stonehand" } } },
			zones = { [1519] = { uiMapID = 1453 }, [1497] = { uiMapID = 1458 }, [1537] = { uiMapID = 1455 } },
			skills = {
				[201] = { cost = 1000, classes = { WARRIOR = true }, trainers = { Alliance = { 11867 }, Horde = { 11870 } } },
				[200] = { cost = 10000, level = 20, classes = { WARRIOR = true, DRUID = true }, trainers = { Alliance = { 11867 }, Horde = { 11870 } } },
				[227] = { cost = 1000, classes = { DRUID = true }, trainers = { Alliance = { 11865 }, Horde = {} } },
			} }
		_G.TrainerSpellsClassTrainers = { MAGE = { { npcID = 9001, faction = "A", names = { enUS = "Ann Arcane" },
			locations = { { areaID = 1519, uiMapID = 1453, x = 50, y = 50 } } } } }
		_G.TrainerSpellsProfessionTrainers = {
			Tailoring = { { npcID = 9002, faction = "A", names = { enUS = "Tom Thread" }, tags = { enUS = "Journeyman Tailor" },
				locations = { { uiMapID = 1453, x = 40, y = 40 } } } },
			Herbalism = { { npcID = 9003, faction = "H", names = { enUS = "Hilda Herb" }, tags = { enUS = "Herbalist" },
				locations = { { uiMapID = 1454, x = 40, y = 40 } } } },
		}
		_G.TrainerSpellsPetTrainers = { HUNTER = { { npcID = 9005, faction = "A", names = { enUS = "Pete Pet" },
			locations = { { uiMapID = 1453, x = 30, y = 30 } } } } }
		_G.TrainerSpellsPortalTrainers = { MAGE = { { npcID = 9004, faction = "A", names = { enUS = "Paula Portal" },
			locations = { { uiMapID = 1453, x = 60, y = 60 } } } } }
		_G.TrainerSpellsBuiltin_Profession = { Tailoring = { [1] = { [2393] = { cost = 25 } }, [50] = { [3915] = { cost = 100 }, [3909] = { cost = 500 } },
			[100] = { [2964] = { cost = 500 } }, [125] = { [3910] = { cost = 5000 } } } } -- (3909, 3910: its ranks, "Tailoring")
		_G.WT_API = nil
		_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
		C_Spell.GetSpellName = function(id)
			return ({ [2393] = "Bolt of Linen Cloth", [3915] = "Brown Linen Shirt", [2964] = "Bolt of Silk Cloth", [99] = "Demoralizing Roar",
				[768] = "Cat Form", [2652] = "Touch of Weakness", [2006] = "Resurrection", [1735] = "Demoralizing Roar", [9005] = "Pounce",
				[200] = "Polearms", [201] = "One-Handed Swords", [227] = "Staves", [3909] = "Tailoring", [3910] = "Tailoring" })[id] or save.name(id)
		end
		C_Spell.GetSpellSubtext = function(id) return ({ [3909] = "Journeyman", [3910] = "Expert", [99] = "Rank 1", [1735] = "Rank 2" })[id] end
		-- no Questie: TrainerSpells' trainers are @npc
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "npc" and id ~= "questie" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		ns:AliasesChanged()
		I.failed, TS.on = {}, nil
		TS.Forget()
		I._.SetupTrainerSpells()
		local npc = ns.providers.npc
		check(npc and npc.trainersOnly and not ns.providers.proftraining, "without Questie: its trainers are @npc; no list of its own for professions")
		local tp = ns.providers.training
		check(tp and tp.fromTrainerSpells, "without What's Training: @training is TrainerSpells'")
		check(#said == 0, "its tables as expected: nothing said: " .. tostring(said[1]))
		local rows = TS.TrainerRows()
		local by = {}
		for _, e in ipairs(rows) do by[e.npcID] = e end
		check(#rows == 8 and by[9001].sub == "Mage Trainer" and by[9002].sub == "Journeyman Tailor" and by[9004].sub == "Portal Trainer"
			and by[9005].sub == "Pet Trainer" and by[11867].sub == "Weapon Master", "class, profession, pet and portal trainers, weapon masters, each its title: " .. #rows)
		check(by[11870].ui == 1458 and by[11870].px == 57.3, "a weapon master's area: its map (Undercity's): " .. tostring(by[11870].ui))
		-- the filters read their own title, faction and role (Questie isn't there to ask)
		local function Is(spec, e) local f = F.Parse(spec) return f and f(e) and true or false end
		check(Is("trainer:mage", by[9001]) and not Is("trainer:mage", by[9002]) and Is("trainer:tailoring", by[9002])
			and Is("trainer:herbalism", by[9003]) and Is("trainer:portal", by[9004]) and Is("trainer:pet", by[9005]),
			"trainer: finds each, the Herbalist (no \"trainer\" in the title) too")
		check(Is("faction:friendly", by[9001]) and not Is("faction:friendly", by[9003]), "faction:friendly: an Alliance character's, not the Horde's")
		local res = UI:Search("@npc trainer:mage")
		check(res[1] and res[1].name == "Ann Arcane", "@npc trainer:mage: " .. tostring(res[1] and res[1].name))
		-- "nearest mage trainer" in Simple mode: by how far each is
		I.Here = function() return { cont = 1, x = 0, y = 0 } end
		I.RowDistance = function(e) local d = ({ [9001] = 120, [9004] = 40 })[e.npcID] return d, d and { cont = 1, x = d, y = 0 } end
		ns.db.easyMode = true; UI:EasyChanged()
		UI:Open("nearest mage trainer"); FlushAll()
		local r = UI.Results()
		check(r[1] and r[1].name == "Ann Arcane" and (r[1].detail or ""):find("120", 1, true), "nearest mage trainer, without Questie: " .. tostring(r[1] and r[1].name))
		UI:Hide(); FlushAll()
		-- (0.57.1, the player: "polearm trainer" listed every weapon master; TrainerSpells says who teaches it)
		check(Is("trainer:polearm", by[11867]) and not Is("trainer:polearm", by[11865]) and not Is("trainer:polearm", by[11870]),
			"trainer:polearm: the Alliance's master of it, not another weapon master, not the Horde's")
		local set = CS.WeaponMasters({ 200 })
		check(set and set[11867] and not set[11870] and not set[11865], "its weapon masters for polearms, your faction's")
		I.RowDistance = function(e) local d = ({ [11867] = 300, [11865] = 100 })[e.npcID] return d, d and { cont = 1, x = d, y = 0 } end
		for _, q in ipairs({ "polearm trainer", "polearms trainer", "nearest polearm trainer" }) do
			UI:Open(q); FlushAll()
			r = UI.Results()
			check(r[1] and r[1].name == "Woo Ping" and not (r[2] and r[2].kind == "npc"), q .. ": Woo Ping alone (not the nearer Buliwyf): " .. tostring(r[1] and r[1].name))
			UI:Hide(); FlushAll()
		end
		_G.UnitFactionGroup = function() return "Horde", "Horde" end
		set = CS.WeaponMasters({ 200 })
		check(set and set[11870] and not set[11867], "a Horde character's: Archibald")
		_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
		UI:Open("nearest innkeeper"); FlushAll()
		r = UI.Results()
		check(r[1] and r[1].noActivate and r[1].name:find("Questie", 1, true), "nearest innkeeper: it knows only trainers, Questie for the rest: " .. tostring(r[1] and r[1].name))
		UI:Hide(); FlushAll()
		check(I.AddonMissing("Questie"), "Questie still missing for every other NPC (the footer says to install it)")

		-- class spells without What's Training
		CS.Forget(); CS.ForgetRows()
		local data = CS.Data()
		local druid = {}
		for _, x in ipairs(data.DRUID or {}) do druid[x[1]] = x[2] end
		check(druid[99] == 10 and druid[768] == 20, "a druid's spells and their levels, from TrainerSpells")
		local warrior = data.WARRIOR or {}
		check(#warrior == 0, "a weapon skill isn't a class spell: " .. #warrior)
		check(not I.AddonMissing("WhatsTrainingCatalog"), "class spells there: What's Training not said missing for them")
		_G.UnitClass = function() return "Priest", "PRIEST" end
		_G.UnitRace = function() return "Human", "Human", 1 end
		local names = {}
		for _, s in ipairs(CS.Spells("PRIEST", true)) do names[s.name] = true end
		check(names["Resurrection"] and not names["Touch of Weakness"], "a race's own spell: not a human's")
		_G.UnitRace = function() return "Undead", "Scourge", 5 end
		names = {}
		for _, s in ipairs(CS.Spells("PRIEST", true)) do names[s.name] = true end
		check(names["Touch of Weakness"], "an undead priest's: Touch of Weakness")

		-- @training without What's Training: your class's spells and weapon skills still to learn
		_G.UnitClass = function() return "Druid", "DRUID" end
		_G.UnitRace = function() return "Night Elf", "NightElf", 4 end
		_G.UnitLevel = function() return 19 end
		_G.IsPlayerSpell = function(id) return id == 227 end -- (Staves known)
		tp._dirty = true
		local tr = ns:GetEntries(tp)
		local st = {}
		for _, e in ipairs(tr) do st[e.spellName .. (e.rank and (" " .. e.rank) or "")] = e end
		check(st["Demoralizing Roar Rank 1"] and st["Demoralizing Roar Rank 1"].state == "now" and st["Demoralizing Roar Rank 2"].state == "needsrank"
			and st["Cat Form"].state == "nextlevel" and st["Pounce Rank 2"].state == "later" and st["Polearms"].state == "nextlevel"
			and st["Polearms"].weapon and not st["Staves"], "learn now, an earlier rank first, next level, later; a weapon skill; one you know left out: " .. #tr)
		local v1, v2 = ns.Easy.Verbs(tr[1])
		check(v1 == ns.L["who teaches it"] and v2 == ns.L["link in chat"], "its footer: Enter who teaches it, Shift+Enter link in chat (not What's Training): " .. tostring(v1))
		check(tr[1].spellName == "Demoralizing Roar" and tr[1].state == "now" and tr[1].kind == "training" and tr[1].cost == 300,
			"learn now first, with its cost: " .. tostring(tr[1].name))
		-- (0.57.2, the player's level 30 warrior: Battle Shout Rank 1 to learn) a rank a later one replaced is known; the
		-- spellbook asked too, not only IsPlayerSpell
		local sbWas = C_SpellBook.IsSpellInSpellBook
		_G.IsPlayerSpell = function(id) return id == 227 or id == 1735 end
		C_SpellBook.IsSpellInSpellBook = function(id) return id == 768 end
		tp._dirty = true
		local names2 = {}
		for _, e in ipairs(ns:GetEntries(tp)) do names2[e.name] = true end
		check(not names2["Demoralizing Roar (Rank 1)"] and not names2["Demoralizing Roar (Rank 2)"] and not names2["Cat Form"] and names2["Polearms"],
			"Rank 2 known: Rank 1 isn't to learn (the spellbook replaced it); one in the spellbook isn't either")
		C_SpellBook.IsSpellInSpellBook = sbWas
		_G.IsPlayerSpell = function(id) return id == 227 end
		_G.UnitLevel = function() return 24 end
		tp._dirty = true
		tr = ns:GetEntries(tp)
		local pounce
		for _, e in ipairs(tr) do if e.spellName == "Pounce" then pounce = e end end
		check(pounce and pounce.state == "needsrank", "a later rank whose first no trainer teaches (a quest's): needs that first")
		_G.UnitLevel = function() return 19 end
		tp._dirty = true
		local known = ns.Pipes.LISTS.trainingknown()
		check(known[1] and known[1].spellName == "Staves" and known[1].state == "known", "a weapon skill you know: kept for \"staves > learn\"")
		local Q = ns.WhatsTraining.Q
		local tq = Q.Question("what can i train")
		local trows = tq and Q.Answer(tq)
		check(trows and trows[1] and trows[1].spellName == "Demoralizing Roar" and not trows[2], "\"what can i train\": what you can learn now")
		UI:Open("where to learn polearms"); FlushAll()
		r = UI.Results()
		local woo = false
		for _, e in ipairs(r) do if e.name == "Woo Ping" then woo = true end end
		check(woo, "where to learn polearms: its weapon master, as TrainerSpells lists him")
		UI:Hide(); FlushAll()
		local lines0 = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines0:find(ns.L["@training (without What's Training)"], 1, true), ".integrations: @training from TrainerSpells")

		-- profession training: the recipes a trainer teaches, among the recipes you don't know (@recipe is:unknown)
		ns.Professions.PlayerProfessions = function() return { { name = "Tailoring", rank = 60, maxRank = 75, skillLine = 197 } } end
		ns.Professions.Store = function() return {} end -- (no profession window opened yet)
		_G.IsPlayerSpell = function(id) return id == 2393 end
		ns.providers.missing._dirty = true
		local mr = ns:GetEntries(ns.providers.missing)
		local byName = {}
		for _, e in ipairs(mr) do byName[e.name] = e end
		check(byName["Brown Linen Shirt"] and byName["Brown Linen Shirt"].canLearn and byName["Brown Linen Shirt"].cost == 100
			and byName["Bolt of Silk Cloth"] and not byName["Bolt of Silk Cloth"].canLearn and not byName["Tailoring"] and not byName["Bolt of Linen Cloth"],
			"recipes you don't know: a trainer's, before the window was opened; not its ranks, not one you know: " .. #mr)
		local PT = ns.ProfTraining
		local q = PT.Question("what can i train in tailoring")
		check(q and q.profs and q.profs[1] == "Tailoring" and q.state == "now", "\"what can i train in tailoring\": its question")
		local ans, note = PT.Answer(q)
		check(#ans == 1 and ans[1].name == "Brown Linen Shirt" and ans[1].kind == "missing", "...what you can learn now: " .. tostring(ans[1] and ans[1].name))
		check(note:find("Journeyman", 1, true) and note:find("50", 1, true), "...and the next rank in the footer: " .. tostring(note))
		check(#PT.Answer(PT.Question("tailoring training")) == 2, "\"tailoring training\": all of it")
		check(PT.Question("what can i train") == nil and PT.Question("nearest tailoring trainer") == nil
			and PT.Question("tailoring recipes i can learn") == nil, "your class's training, a trainer's place, recipes: other questions")
		check(PT.ToAdvanced(PT.Question("how much is tailoring training")) == "@recipe is:learnable tailoring trainer | sum cost ",
			"Alt+`: " .. PT.ToAdvanced(PT.Question("how much is tailoring training")))
		ns.db.easyMode = false; UI:EasyChanged()
		local adv = UI:Search("@recipe is:learnable tailoring trainer")
		check(adv[1] and adv[1].name == "Brown Linen Shirt", "...which finds it: " .. tostring(adv[1] and adv[1].name))
		ns.db.easyMode = true; UI:EasyChanged()
		UI:Open("what can i train in tailoring"); FlushAll()
		local r2 = UI.Results()
		check(r2[1] and r2[1].name == "Brown Linen Shirt" and r2[1].kind == "missing" and not r2[2],
			"typed in Simple mode: the answer: " .. tostring(r2[1] and r2[1].name))
		UI:Hide(); FlushAll()
		local t = ns.MissingRecipes.TrainerFor("Brown Linen Shirt", 3915)
		check(t and t.cost == 100 and t.rank == 50 and t.from == "TrainerSpells", "a recipe's trainer cost before its window was opened")
		-- @profession: its next rank at a trainer
		ns.providers.professions._dirty = true
		local prow
		for _, e in ipairs(ns:GetEntries(ns.providers.professions)) do if e.name == "Tailoring" then prow = e end end
		check(prow and prow.detail:find("Journeyman", 1, true) and prow.canLearn and prow.cost == 500,
			"@profession Tailoring: its next rank, Journeyman, learnable now: " .. tostring(prow and prow.detail))
		ns.db.easyMode = false; UI:EasyChanged()
		-- Expert known: Journeyman too (Expert replaced it); a cap of 225 has Expert whatever the spellbook says
		_G.IsPlayerSpell = function(id) return id == 2393 or id == 3910 end
		check(TS.NextRank({ name = "Tailoring", rank = 130, maxRank = 225, skillLine = 197 }) == nil, "Expert known: no next rank here")
		_G.IsPlayerSpell = function(id) return id == 2393 end
		check(TS.NextRank({ name = "Tailoring", rank = 130, maxRank = 225, skillLine = 197 }) == nil, "a 225 cap: Expert known")
		local pl = UI:Search("@profession is:learnable")
		local tail = false
		for _, e in ipairs(pl) do if e.kind == "professions" and e.name == "Tailoring" then tail = true end end
		check(tail, "@profession is:learnable: a rank to learn at a trainer")

		-- not in the shape expected: said once, with what's unavailable; the rest still used
		said = {}
		I.failed = {}
		TS.Forget()
		_G.TrainerSpellsBuiltin_Profession = "moved"
		_G.TrainerSpellsBuiltin = { DRUID = "renamed" }
		_G.TrainerSpellsWeaponSkills = { skills = "moved" }
		check(TS.ProfData() == nil and TS.ClassData() == nil and TS.WeaponData() == nil and TS.TrainerRows() ~= nil,
			"the changed tables left out, the trainers still read")
		check(Said(ns.L["Its weapon masters are unavailable."]), "weapon masters: said unavailable")
		local m1 = Said(ns.L["Its profession training is unavailable."])
		local m2 = Said(ns.L["Class spells from it are unavailable."])
		check(m1 and m1:find("TrainerSpells", 1, true) and m2, "each said in chat, with what's unavailable: " .. tostring(m1))
		local n = #said
		TS.Forget(); TS.ProfData()
		check(#said == n, "said once a session")
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find("TrainerSpells:", 1, true) and lines:find(ns.L["Not as expected:"], 1, true), ".integrations says so: " .. lines)
		-- an integration that fails to start: said too
		said = {}
		local setupWas = I._.SetupTrainerSpells
		I._.SetupTrainerSpells = function() error("boom") end
		local otherWas = { I._.SetupAtlasLoot, I._.SetupQuestie, I._.SetupAttune, I._.SetupWhatsTraining }
		I._.SetupAtlasLoot, I._.SetupQuestie, I._.SetupAttune, I._.SetupWhatsTraining = nil, nil, nil, nil
		I.Setup()
		I._.SetupTrainerSpells = setupWas
		I._.SetupAtlasLoot, I._.SetupQuestie, I._.SetupAttune, I._.SetupWhatsTraining = otherWas[1], otherWas[2], otherWas[3], otherWas[4]
		check(Said(ns.L["Its profession training, trainers and class spells are unavailable."]), "failing to start: said, with what's unavailable")
		-- Questie's database without the calls Terminal reads: @npc said unavailable, not an empty list
		said = {}
		local QD = ns.QuestieData
		local dbWas, readyWas = QD.DB, QD.Ready
		QD.DB, QD.Ready = function() return { QueryNPCSingle = "gone" } end, function() return true end
		local npcState = I.npc
		local listWas, busyWas = npcState.list, npcState.busy
		npcState.list, npcState.busy = nil, nil
		I._.IndexNPCs()
		QD.DB, QD.Ready = dbWas, readyWas
		npcState.list, npcState.busy = listWas, busyWas
		check(Said(ns.L["@npc is unavailable."]) and Said("Questie"), "Questie's database changed: @npc said unavailable: " .. tostring(said[1]))
	end)
	for _, g in ipairs(G) do _G[g] = save.globals[g] end
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, _G.WT_API, _G.UnitRace, _G.UnitFactionGroup, _G.IsPlayerSpell = save.print, save.wt, save.race, save.faction, save.known
	C_Spell.GetSpellName, ns.Professions.PlayerProfessions, I.Here, I.RowDistance = save.name, save.profs, save.here, save.dist
	I.failed, TS.on, _G.UnitClass = save.failed, save.on, save.class
	_G.UnitLevel, C_Spell.GetSpellSubtext, ns.Professions.Store = save.level, save.sub, save.store
	ns.db.easyMode = save.easy; UI:EasyChanged()
	TS.Forget(); CS.Forget(); CS.ForgetRows()
	UI:Hide(); FlushAll()
	if not ok then check(false, "trainerspells: " .. tostring(err)) end
end

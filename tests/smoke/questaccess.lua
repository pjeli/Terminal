-- Can you take a quest, by QuestieDB's quest fields (Search/Questions/QuestAccess.lua): prerequisites (any one / every
-- one), exclusive quests, a level cap, breadcrumbs, a spell, a reputation cap, a parent quest, a quest after it done.
-- Z.QuestFitter and is:cantake leave out what fails; "why can't i take <quest>" says why; "<quest> > unlocks" and
-- "what does <quest> unlock" go forward. A mocked LibQuestieDB, as questiedb.lua and rewards.lua do.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, QD, QR, QA = ns.Integrations, ns.QuestieData, ns.QuestRewards, ns.QuestAccess

local function drop(id)
	ns.providers[id] = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end
local function Entity(rows)
	local ids = {}
	for id in pairs(rows) do ids[#ids + 1] = id end
	table.sort(ids)
	return { Get = function(id, field) return rows[id] and rows[id][field] end, GetAllIds = function() return ids end }
end
local function Fresh()
	I.npc.on, I.npc.list, I.npc.names, I.npc.busy = false, nil, nil, false
	I.qdb.list, I.qdb.names, I.qdb.busy = nil, nil, false
	drop("npc"); drop("questie")
	QD.ResetForTests()
	ns.Filters.ClearCache()
	QR.Forget(); QR.ForgetRequires(); QR.ForgetFaction()
	if QA then QA.Forget() end
	if ns.Pipes.ClearSteps then ns.Pipes.ClearSteps() end
end
local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[quest access: can you take it, why not, what it unlocks]\n")
do
	local Q = C_QuestLog
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
		level = _G.UnitLevel, spell = rawget(_G, "IsPlayerSpell"), rep = _G.C_Reputation, done = Q.IsQuestFlaggedCompleted,
		log = Q.GetLogIndexForQuestID, easy = ns.db.easyMode }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.UnitLevel = function() return 11 end
	local done, inLog, known, stand = { [100] = true, [105] = true, [108] = true, [111] = true }, {}, {}, 3500
	Q.IsQuestFlaggedCompleted = function(id) return done[id] == true end
	Q.GetLogIndexForQuestID = function(id) return inLog[id] end
	_G.IsPlayerSpell = function(id) return known[id] == true end
	_G.C_Reputation = { GetFactionDataByID = function(fid) if fid == 72 then return { name = "Stormwind", currentStanding = stand } end end }
	local Z = 12
	_G.LibQuestieDB = {
		Quest = Entity({
			[100] = { name = "The Missing Diplomat", questLevel = 10, zoneOrSort = Z },
			[101] = { name = "The Missing Diplomat, Part Two", questLevel = 11, zoneOrSort = Z, preQuestSingle = { 100 } },
			[102] = { name = "Seeking the Blade", questLevel = 12, zoneOrSort = Z, preQuestGroup = { 101, 103 } },
			[103] = { name = "An Errand", questLevel = 11, zoneOrSort = Z },
			[104] = { name = "Path of Steel", questLevel = 11, zoneOrSort = Z, exclusiveTo = { 105 } },
			[105] = { name = "Path of Fire", questLevel = 11, zoneOrSort = Z, exclusiveTo = { 104 } },
			[106] = { name = "Young Recruit", questLevel = 10, zoneOrSort = Z, requiredMaxLevel = 10 },
			[107] = { name = "Report to Goldshire", questLevel = 11, zoneOrSort = Z, breadcrumbForQuestId = 108 },
			[108] = { name = "Kobold Candles", questLevel = 11, zoneOrSort = Z, breadcrumbs = { 107 } },
			[109] = { name = "A Warrior's Lesson", questLevel = 11, zoneOrSort = Z, requiredSpell = 100 },
			[110] = { name = "Old Chain One", questLevel = 11, zoneOrSort = Z, nextQuestInChain = 111, childQuests = { 113 } },
			[111] = { name = "Old Chain Two", questLevel = 12, zoneOrSort = Z },
			[112] = { name = "Gnoll Troubles", questLevel = 11, zoneOrSort = Z, requiredMaxRep = { 72, 3000 } },
			[113] = { name = "Inner Errand", questLevel = 11, zoneOrSort = Z, parentQuest = 114 },
			[114] = { name = "Outer Errand", questLevel = 11, zoneOrSort = Z },
		}),
		Npc = Entity({ [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } }, npcFlags = 2 } }),
		Item = Entity({ [9004] = { name = "Linen Cloth", vendors = { 240 } } }),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	local ok, err = pcall(function()
		Fresh()
		I.Setup(); FlushAll()
		local list = ns:GetEntries(ns.providers.questie)
		check(#list == 15, "[quest access] the quests indexed: " .. #list)
		local function Row(id) for _, e in ipairs(list) do if rawget(e, "key") == id then return e end end end

		-- the test itself, field by field
		local function Can(id) return QA.CanTake(id) end
		check(Can(101) and Can(103) and Can(114), "[quest access] nothing in the way: a single prerequisite done, none at all")
		check(not Can(102), "[quest access] preQuestGroup: every one must be done (Part Two and An Errand aren't)")
		check(not Can(104) and Can(105) == true, "[quest access] exclusiveTo: Path of Fire done, Path of Steel can't be taken")
		check(not Can(106) and QA.CanTake(106, 10), "[quest access] requiredMaxLevel 10: not at 11, fine at 10")
		check(not Can(107), "[quest access] a breadcrumb to a quest done leads nowhere")
		check(not Can(109), "[quest access] requiredSpell: not learned")
		check(not Can(110), "[quest access] nextQuestInChain done: you're past it")
		check(not Can(112), "[quest access] requiredMaxRep: Friendly already (3500 of 3000)")
		check(not Can(113), "[quest access] parentQuest not in your log")
		known[100], stand, inLog[114] = true, 2000, 1
		check(Can(109) and Can(112) and Can(113), "[quest access] spell learned, under the reputation cap, the parent in your log: yes")
		known[100], stand, inLog[114] = nil, 3500, nil
		-- a group's prerequisite counts as done when one of its own exclusiveTo is: 102 needs 101 and 103
		done[101], done[103] = true, true
		check(Can(102), "[quest access] every one of the group done: yes")
		done[101], done[103] = nil, nil
		inLog[108] = 1
		check(not Can(107), "[quest access] a breadcrumb whose quest is in your log: no")
		inLog[108] = nil

		-- the quests for your level: only those you can take (Z.QuestFitter: where to quest, the zones' counts)
		local fits = ns.Zones.QuestFitter(11)
		local took = {}
		for _, e in ipairs(list) do if fits(e) then took[#took + 1] = rawget(e, "key") end end
		table.sort(took)
		check(table.concat(took, ",") == "101,103,114", "[quest access] quests for your level: those you can pick up: " .. table.concat(took, ","))
		-- is:cantake ("quests here")
		ns.db.easyMode = false
		UI.lastScan = nil
		local res = UI:Search("@questie is:cantake -is:done")
		local got = {}
		for _, e in ipairs(res) do got[#got + 1] = rawget(e, "key") end
		table.sort(got)
		check(table.concat(got, ",") == "101,103,114", "[quest access] is:cantake: " .. table.concat(got, ","))
		check(tostring(ns.FIELD_DETAIL.cantake(Row(102))):find("Needs The Missing Diplomat, Part Two first", 1, true),
			"[quest access] sort:cantake's detail says what stops you: " .. tostring(ns.FIELD_DETAIL.cantake(Row(102))))

		-- "why can't i take <quest>"
		local function Why(line)
			local top = ns.Questions.Ranked(line)[1]
			if not (top and top.a.id == "QuestAccess") then return nil, top and top.a.id end
			local rows = QA.Answer(top.q)
			return rows
		end
		local rows, other = Why("why can't i take seeking the blade?")
		check(rows and Names(rows) == "Needs The Missing Diplomat, Part Two first | Needs An Errand first",
			"[quest access] why can't i take seeking the blade: each prerequisite missing: " .. (rows and Names(rows) or tostring(other)))
		check(rows and rows[1].qid == 101 and tostring(rows[1].detail):find("The Missing Diplomat, Part Two", 1, true),
			"[quest access] ...the row is the quest it names")
		rows = Why("can i take path of steel")
		check(rows and Names(rows) == "You took Path of Fire: it's one or the other", "[quest access] can i take path of steel: " .. (rows and Names(rows) or "-"))
		rows = Why("why isnt young recruit offered")
		check(rows and Names(rows) == "Only up to level 10", "[quest access] why isnt young recruit offered: " .. (rows and Names(rows) or "-"))
		rows = Why("why is report to goldshire not offered")
		check(rows and Names(rows) == "A breadcrumb to Kobold Candles, which you've taken", "[quest access] a breadcrumb: " .. (rows and Names(rows) or "-"))
		rows = Why("why cant i take a warriors lesson")
		check(rows and Names(rows) == "Needs Charge learned", "[quest access] a spell: " .. (rows and Names(rows) or "-"))
		rows = Why("why cant i take old chain one")
		check(rows and Names(rows) == "You took Old Chain Two, which comes after it", "[quest access] past it: " .. (rows and Names(rows) or "-"))
		rows = Why("can i take the missing diplomat")
		check(rows and Names(rows) == "Done", "[quest access] done: " .. (rows and Names(rows) or "-"))
		rows = Why("can i take an errand")
		check(rows and Names(rows) == "Nothing stops you: you can take it" and rows[1].qid == 103, "[quest access] nothing stops you: " .. (rows and Names(rows) or "-"))
		check(QA.Question("can i take nothing like this") == nil and QA.Question("why cant i fly") == nil and QA.Question("can i craft") == nil,
			"[quest access] no quest named: not this question")
		-- (1.3.13, review) someone's !t question: your quests aren't theirs, so not answered as if they were
		ns.Asker = { level = 11, class = "MAGE" }
		check(QA.Question("can i take the missing diplomat") == nil, "[quest access] a !t question: not answered with your quests")
		ns.Asker = nil
		-- a quest with none of the fields: said at once, your level not even asked
		local ul, asks = _G.UnitLevel, 0
		_G.UnitLevel = function(...) asks = asks + 1 return ul(...) end
		local fine = QA.CanTake(103)
		_G.UnitLevel = ul
		check(fine == true and asks == 0, "[quest access] nothing to judge: true, nothing asked: " .. asks)
		-- (Enter and the tooltip are the quest's own: its name in the Wowhead line, not the reason's)
		do
			local shown
			local was = ns.ShowText
			ns.ShowText = function(_, title) shown = title end
			rows = Why("why cant i take seeking the blade")
			rows[1].activate(rows[1])
			ns.ShowText = was
			check(tostring(shown):find("Part Two", 1, true) and not tostring(shown):find("Needs", 1, true), "[quest access] Enter: the quest's own: " .. tostring(shown))
		end

		-- what a quest unlocks: the quests whose prerequisites name it, the next in its chain, its child quests, where a
		-- breadcrumb leads
		local function Ids(t) local o = {} for i, u in ipairs(t) do o[i] = u.id end return table.concat(o, ",") end
		check(Ids(QA.Unlocks(100)) == "101" and Ids(QA.Unlocks(101)) == "102" and Ids(QA.Unlocks(103)) == "102",
			"[quest access] unlocks: by prerequisites: " .. Ids(QA.Unlocks(100)) .. " / " .. Ids(QA.Unlocks(101)))
		check(Ids(QA.Unlocks(110)) == "111,113" and Ids(QA.Unlocks(107)) == "108", "[quest access] unlocks: next in chain, child quests, a breadcrumb's quest: "
			.. Ids(QA.Unlocks(110)) .. " / " .. Ids(QA.Unlocks(107)))
		local P = ns.Pipes
		check(P.Canonical("what does the missing diplomat unlock") == "missing diplomat > unlocks"
			and P.Canonical("what comes after old chain one") == "old chain one > unlocks" and P.Canonical("next quest after old chain one") == "old chain one > unlocks"
			and P.Canonical("what does nothing like this unlock") == nil, "[quest access] the words: " .. tostring(P.Canonical("what does the missing diplomat unlock")))
		UI.lastScan = nil
		res = UI:Search("@questie the missing diplomat, part two > unlocks")
		check(Names(res) == "Seeking the Blade" and tostring(res[1].detail):find("needs it", 1, true),
			"[quest access] part two > unlocks: Seeking the Blade, which needs it: " .. Names(res) .. " / " .. tostring(res[1] and res[1].detail))
		UI.lastScan = nil
		res = UI:Search("@questie old chain one > unlocks")
		check(Names(res) == "Old Chain Two | Inner Errand" and tostring(res[1].detail):find("next in its chain", 1, true)
			and tostring(res[1].detail):find("done", 1, true), "[quest access] old chain one > unlocks: " .. Names(res))
		ns.db.easyMode = true
		UI:Hide(); FlushAll()
		UI:Open("what does old chain one unlock"); FlushAll()
		res = UI.Results()
		check(res[1] and res[1].name == "Old Chain Two", "[quest access] Simple mode: what does old chain one unlock: " .. Names(res))
		UI:Hide(); FlushAll()
	end)
	check(ok, "[quest access] ran: " .. tostring(err))
	ns.db.easyMode = save.easy
	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
	_G.UnitRace, _G.UnitClass, _G.UnitLevel, _G.IsPlayerSpell, _G.C_Reputation = save.race, save.class, save.level, save.spell, save.rep
	Q.IsQuestFlaggedCompleted, Q.GetLogIndexForQuestID = save.done, save.log
end

io.write("[quest access: one rule for every place that asks (1.6.3)]\n")
do
	-- (1.6.3, the mismatch hunt) "can i take", is:cantake / sort:cantake, the quests for your level (Z.QuestFitter) and
	-- quest upgrades each judged with part of the rules: one QR.CanTakeAll now. And OneForAll's prerequisites, which only
	-- "> chain" read, count for "can i take" and "> unlocks" too.
	local Q = C_QuestLog
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
		level = _G.UnitLevel, fac = _G.UnitFactionGroup, rep = _G.C_Reputation, done = Q.IsQuestFlaggedCompleted,
		log = Q.GetLogIndexForQuestID, easy = ns.db.easyMode, OA = rawget(_G, "OneForAll") }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.UnitLevel = function() return 11 end
	_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
	local done = {}
	Q.IsQuestFlaggedCompleted = function(id) return done[id] == true end
	Q.GetLogIndexForQuestID = function() return nil end
	_G.C_Reputation = { GetFactionDataByID = function(fid)
		if fid == 72 then return { name = "Stormwind", currentStanding = 3500 } end
		if fid == 47 then return { name = "Ironforge", currentStanding = 9500 } end
	end }
	local Z, SP = 12, { [12] = { { 40, 60 } } }
	_G.LibQuestieDB = {
		Quest = Entity({
			[200] = { name = "Grunt's Errand", questLevel = 11, zoneOrSort = Z, startedBy = { { 250 } } }, -- (only a Horde NPC gives it)
			[201] = { name = "Veteran's Task", questLevel = 11, zoneOrSort = Z, requiredLevel = 20, startedBy = { { 240 } } },
			[202] = { name = "Honored Errand", questLevel = 11, zoneOrSort = Z, requiredMinRep = { 72, 9000 }, startedBy = { { 240 } } },
			[203] = { name = "Plain Errand", questLevel = 11, zoneOrSort = Z, startedBy = { { 240 } } },
			[204] = { name = "Deep Errand", questLevel = 11, zoneOrSort = Z, startedBy = { { 240 } } },
			[205] = { name = "The Lead In", questLevel = 11, zoneOrSort = Z, startedBy = { { 240 } } },
			[206] = { name = "Two Givers", questLevel = 11, zoneOrSort = Z, startedBy = { { 250, 240 } } }, -- (the Horde's listed first)
			-- (release review) a three-step OneForAll chain: only its last step unlocks the quest
			[207] = { name = "Step One", questLevel = 11, zoneOrSort = Z, startedBy = { { 240 } } },
			[208] = { name = "Step Two", questLevel = 11, zoneOrSort = Z, startedBy = { { 240 } } },
			[209] = { name = "The Final Step", questLevel = 11, zoneOrSort = Z, startedBy = { { 240 } } },
			-- (release review) quests needing the Ironforge standing you have: one above your level
			[210] = { name = "A Veteran's Honor", questLevel = 11, zoneOrSort = Z, requiredLevel = 20, requiredMinRep = { 47, 9000 }, startedBy = { { 240 } } },
			[211] = { name = "B Simple Honor", questLevel = 11, zoneOrSort = Z, requiredMinRep = { 47, 9000 }, startedBy = { { 240 } } },
		}),
		Npc = Entity({ [240] = { name = "Marshal Dughan", friendlyToFaction = "A", spawns = SP, npcFlags = 2 },
			[250] = { name = "Grunt Logash", friendlyToFaction = "H", spawns = SP, npcFlags = 2 } }),
		Item = Entity({}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	-- (OneForAll: Deep Errand needs The Lead In, which QuestieDB doesn't say)
	_G.OneForAll = { QUEST_PREREQ_CHAINS = { [204] = { { id = 205 }, { id = 204 } }, [209] = { { id = 207 }, { id = 208 }, { id = 209 } } } }
	local K = ns.OneForAll and ns.OneForAll.Attunements
	local ok, err = pcall(function()
		Fresh()
		if K then K.Forget() end
		I.Setup(); FlushAll()
		local list = ns:GetEntries(ns.providers.questie)
		local function Keys(rows) local t = {} for _, e in ipairs(rows) do t[#t + 1] = rawget(e, "key") end table.sort(t) return table.concat(t, ",") end
		-- one rule
		check(not QR.CanTakeAll(200) and not QR.CanTakeAll(201) and not QR.CanTakeAll(202) and QR.CanTakeAll(203) and not QR.CanTakeAll(204)
			and QR.CanTakeAll(205), "[can take] the other side's giver, level 20, Honored, OneForAll's prerequisite: no; the plain one: yes")
		-- every place agrees
		local fits = ns.Zones.QuestFitter(11)
		local took = {}
		for _, e in ipairs(list) do if fits(e) then took[#took + 1] = e end end
		check(Keys(took) == "203,205,206,207,208,211", "[can take] quests for your level (quests near me, the zones' counts): " .. Keys(took))
		ns.db.easyMode = false
		UI.lastScan = nil
		check(Keys(UI:Search("@questie is:cantake")) == "203,205,206,207,208,211", "[can take] is:cantake: " .. Keys(UI:Search("@questie is:cantake")))
		-- (1.6.8, the mismatch hunt) its giver for distance, Shift+Enter and the map: one of yours, not the first listed
		if ns.Pipes.ForgetFriendly then ns.Pipes.ForgetFriendly() end
		check(I.QuestGiver(206) == 240, "[giver] two givers, the other side's listed first: yours: " .. tostring(I.QuestGiver(206)))
		local vet
		for _, e in ipairs(list) do if rawget(e, "key") == 201 then vet = e end end
		check(tostring(ns.FIELD_DETAIL.cantake(vet)):find(ns.L["Requires level %d"]:format(20), 1, true),
			"[can take] sort:cantake's detail says the level, as can i take does: " .. tostring(ns.FIELD_DETAIL.cantake(vet)))
		-- OneForAll's prerequisite: said, and counted going forward
		check(not QA.CanTake(204) and QA.Reasons(204)[1] and QA.Say(QA.Reasons(204)[1]):find("The Lead In", 1, true),
			"[can take] OneForAll's prerequisite: why not, named: " .. tostring(QA.Reasons(204)[1] and QA.Say(QA.Reasons(204)[1])))
		local un = {}
		for _, u in ipairs(QA.Unlocks(205)) do un[#un + 1] = u.id end
		check(table.concat(un, ",") == "204", "[can take] the lead in > unlocks: Deep Errand: " .. table.concat(un, ","))
		local function UnlockIds(id) local t = {} for _, u in ipairs(QA.Unlocks(id)) do t[#t + 1] = u.id end return table.concat(t, ",") end
		check(UnlockIds(207) == "" and UnlockIds(208) == "209",
			"[unlocks] a three-step chain: step one unlocks not the last quest, step two does: " .. UnlockIds(207) .. " / " .. UnlockIds(208))
		-- quests needing a standing you have: those you can take first, by the one rule (not above your level)
		local rows = ns.QuestNeeds.Answer({ what = "rep", fids = { [47] = true }, need = 1 })
		check(rows[1] and rawget(rows[1], "key") == nil and rows[1].key == 211 and rows[2] and rows[2].key == 210,
			"[standing] the one you can take first, the one above your level after: " .. tostring(rows[1] and rows[1].key))
		done[205] = true
		QA.Forget()
		check(QA.CanTake(204) and QR.CanTakeAll(204), "[can take] its prerequisite done: yes")
	end)
	check(ok, "[can take] ran: " .. tostring(err))
	ns.db.easyMode = save.easy
	_G.OneForAll = save.OA
	if K then K.Forget() end
	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
	_G.UnitRace, _G.UnitClass, _G.UnitLevel, _G.UnitFactionGroup, _G.C_Reputation = save.race, save.class, save.level, save.fac, save.rep
	Q.IsQuestFlaggedCompleted, Q.GetLogIndexForQuestID = save.done, save.log
	if ns.Pipes.ForgetFriendly then ns.Pipes.ForgetFriendly() end -- (the stubbed side not kept for later files: review)
end

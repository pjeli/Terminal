-- Quests by their reward, and the quests before one (Rewards.lua, 0.49.16, the player's ask: "outlaw saber quest" listed
-- the Baron Aquanis quest, not the one rewarding the Outlaw Sabre). Questie's data: items name the quests rewarding them
-- (questRewards); quests name the ones before them (preQuestGroup: all; preQuestSingle: any one, the one you can take).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, QD, QR = ns.Integrations, ns.QuestieData, ns.QuestRewards

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
	QR.Forget()
	if ns.Pipes.ClearSteps then ns.Pipes.ClearSteps() end
end
local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[rewards: quests by their reward, and the quests before one]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
		easy = ns.db.easyMode }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.LibQuestieDB = {
		Quest = Entity({
			[100] = { name = "The Missing Diplomat", questLevel = 20, zoneOrSort = 12 },
			[101] = { name = "The Missing Diplomat, Part Two", questLevel = 21, zoneOrSort = 12, preQuestSingle = { 100 } },
			[105] = { name = "An Errand", questLevel = 22, zoneOrSort = 12, preQuestSingle = { 106, 107 } },
			[106] = { name = "A Horde Errand", questLevel = 22, zoneOrSort = 12, requiredRaces = 2 + 16 + 32 + 128 },
			[107] = { name = "An Alliance Errand", questLevel = 22, zoneOrSort = 12, requiredRaces = 1 + 4 + 8 + 64 },
			[102] = { name = "Seeking the Blade", questLevel = 24, zoneOrSort = 12, preQuestGroup = { 101, 105 } },
			[103] = { name = "Seeking the Blade (Horde)", questLevel = 24, zoneOrSort = 12, preQuestSingle = { 106 },
				requiredRaces = 2 + 16 + 32 + 128 },
			[300] = { name = "Blade of the Sea", questLevel = 30, zoneOrSort = 12 },
			[301] = { name = "A Bear's Errand", questLevel = 10, zoneOrSort = 12 },
			[200] = { name = "Baron Aquanis", questLevel = 24, zoneOrSort = 12,
				objectivesText = { "Bring the strange water globe to Je'neu Sancrea." } },
		}),
		Npc = Entity({ [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } }, npcFlags = 2 } }),
		Item = Entity({
			[9001] = { name = "Outlaw Sabre", questRewards = { 102, 103 } },
			[9005] = { name = "Bear Shawl", questRewards = { 301 } },
			[9006] = { name = "Bone Ring", questRewards = { 301 } },
			[9007] = { name = "Glowing Wand", questRewards = { 301 } },
			[9008] = { name = "Gray Kodo Cloak", questRewards = { 301 } },
			[9009] = { name = "Sea Blade", questRewards = { 300 } },
			[9010] = { name = "Agamaggan's Clutch", questRewards = { 300 } },
			[9002] = { name = "Strike of the Hydra", questRewards = { 200 } },
			[9003] = { name = "Diplomat Ring", questRewards = { 101 } },
			[9004] = { name = "Linen Cloth", vendors = { 240 } },
		}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	Fresh()
	I.Setup(); FlushAll()
	check(I.qdb.list and #I.qdb.list == 10, "the quests indexed: " .. tostring(I.qdb.list and #I.qdb.list))

	-- the items some quest rewards: by name, part of it, a close spelling
	check(#QR.Index() == 9, "the items quests reward (not the cloth), read in the background: " .. #QR.Index())
	local q = QR.Question("outlaw saber quest")
	check(q and q.items[1].name == "Outlaw Sabre", "\"outlaw saber quest\": the Outlaw Sabre (a close spelling)")
	for _, s in ipairs({ "quest for outlaw sabre", "which quest rewards the outlaw sabre?", "outlaw sabre quest reward", "sabre quest" }) do
		local qq = QR.Question(s)
		check(qq and qq.items[1].name == "Outlaw Sabre", s .. ": the Outlaw Sabre")
	end
	check(QR.Question("linen cloth quest") == nil and QR.Question("outlaw sabre") == nil and QR.Question("@questie sabre") == nil
		and QR.Question("missing diplomat quest") == nil, "no quest reward named, no quest word, Advanced syntax, a quest called that: a search")
	-- (review, 0.49.17) a question's little words aren't an item's; words are typed at a name's word's start; a close
	-- spelling only with two words or more; a quest named with the words, its little words aside, stays a search
	for _, s in ipairs({ "quests near me", "quests in my zone", "low quests", "gray quests", "grey quests", "blade of the sea quest",
		"saber quest" }) do
		check(QR.Question(s) == nil, s .. ": a search, not a reward: " .. tostring(QR.Question(s) and QR.Question(s).items[1].name))
	end
	q = QR.Question("what's the quest for outlaw sabre?")
	check(q and q.items[1].name == "Outlaw Sabre", "what's the quest for outlaw sabre: apostrophes and marks left out")

	-- Simple mode: the quest rewarding it, not the one whose words are close
	ns.db.easyMode = true
	UI:Hide(); FlushAll()
	UI:Open("outlaw saber quest"); FlushAll()
	local res = UI.Results()
	-- (the Horde's quest rewards it too: a human is shown the one they can take; review, 0.49.17)
	check(res[1] and res[1].name == "Seeking the Blade" and res[1].detail:find("^Rewards Outlaw Sabre") and #res == 1,
		"outlaw saber quest: the quest rewarding it: " .. Names(res) .. " / " .. tostring(res[1] and res[1].detail))
	check(tostring(UI.status:GetText()):find("Quests that reward Outlaw Sabre", 1, true), "the footer says so: " .. tostring(UI.status:GetText()))
	check(ns.Easy.ToAdvanced("outlaw saber quest") == "@questie reward:outlaw_sabre ", "Alt+`: " .. ns.Easy.ToAdvanced("outlaw saber quest"))
	UI:Hide(); FlushAll()

	-- (0.50.7, review) a name with an apostrophe: Alt+` writes it as reward: matches it, apostrophes left out
	check(ns.Easy.ToAdvanced("agamaggans clutch quest") == "@questie reward:agamaggans_clutch ",
		"Alt+`, an apostrophe: " .. ns.Easy.ToAdvanced("agamaggans clutch quest"))
	-- (review, 0.57.7) a word still being typed isn't looked for as a close spelling (a pass over every item per letter);
	-- once it's typed (a space after it, or another word) it is
	QR.ForgetClose()
	check(QR.Question("quest outlaw sabe") == nil and QR.Question("quest outlaw saber") == nil, "a word still being typed: no close spelling looked for")
	local q2 = QR.Question("quest outlaw saber ")
	check(q2 and q2.items[1] and q2.items[1].name == "Outlaw Sabre", "typed, a space after it: Outlaw Sabre by its close spelling")
	local exact = QR.Items({ "agamaggan's", "clutch" }, true)
	check(exact[1] and exact[1].name == "Agamaggan's Clutch", "reward:agamaggan's_clutch finds it")
	-- (0.50.7, review) asked while the index is still being read: the search waits for it, not an empty answer kept
	QR.Forget()
	ns.Filters.loading, ns.Pipes.loading = nil, nil
	local none = QR.Items({ "outlaw" })
	check(#none == 0 and ns.Filters.loading == true and ns.Pipes.loading == true, "still being read: nothing yet, and the search asks again")
	FlushAll()
	ns.Filters.loading, ns.Pipes.loading = nil, nil
	check(QR.Items({ "outlaw" })[1].name == "Outlaw Sabre", "then it's in")

	-- (0.50.7, review) an NPC's fallback with nothing to press: pinned, the map not opened from Terminal's code
	do
		local twm, pr, shown, ui = _G.ToggleWorldMap, ns.Print, WorldMapFrame.shown, QD.UiMapOfArea
		QD.UiMapOfArea = function(a) return a == 12 and 1429 or nil end
		local opened, said = 0, {}
		_G.ToggleWorldMap = function() opened = opened + 1 end
		ns.Print = function(_, msg) said[#said + 1] = tostring(msg) end
		WorldMapFrame.shown = false
		I._.OpenNpcDirect({ npcID = 240, name = "Marshal Dughan" })
		FlushAll()
		_G.ToggleWorldMap, ns.Print, WorldMapFrame.shown, QD.UiMapOfArea = twm, pr, shown, ui
		local text = table.concat(said, " / ")
		check(opened == 0 and text:find(ns.L["World Map"], 1, true), "an NPC's fallback: not opened from here, said where: " .. opened .. " " .. text)
	end

	-- Advanced mode: reward:<item>
	ns.db.easyMode = false
	res = UI:Search("@questie reward:outlaw_sabre")
	check(#res == 1 and res[1].name == "Seeking the Blade", "@questie reward:outlaw_sabre: " .. Names(res))
	res = UI:Search("@questie reward:saber")
	check(#res == 1 and res[1].name == "Seeking the Blade", "reward:saber (a close spelling, part of the name): " .. Names(res))
	res = UI:Search("@questie reward:hydra")
	check(#res == 1 and res[1].name == "Baron Aquanis", "reward:hydra: " .. Names(res))
	res = UI:Search("@questie reward:linen_cloth")
	check(#res == 0, "no quest rewards it: nothing: " .. Names(res))

	-- the chain: the quests before it, first to last (every one of a group; of "any one", the one a human can take)
	local chain = QR.Chain(102)
	check(table.concat(chain, ",") == "100,101,107,105,102", "the chain, first to last: " .. table.concat(chain, ","))
	res = UI:Search("@questie seeking the blade > chain")
	check(Names(res) == "The Missing Diplomat | The Missing Diplomat, Part Two | An Alliance Errand | An Errand | Seeking the Blade",
		"@questie seeking the blade > chain: in order: " .. Names(res))
	check(res[1].detail:find("^step 1 of 4") and res[5].detail:find("^the quest itself"), "each says its step: " .. tostring(res[1].detail))
	res = UI:Search("@questie reward:outlaw_sabre > chain")
	check(#res == 5 and res[5].name == "Seeking the Blade", "from the reward: its chain: " .. Names(res))
	res = UI:Search("seeking the blade > chain")
	check(#res == 5, "no @questie: chain starts from Questie's quests: " .. Names(res))
	res = UI:Search("outlaw sabre > chain")
	check(#res == 5 and res[5].name == "Seeking the Blade", "an item's name: the chain of the quest rewarding it (yours): " .. Names(res))
	res = UI:Search("prereq for seeking the blade")
	check(#res == 5, "prereq for (one prereq): the chain: " .. Names(res))
	check(ns.Easy.ToAdvanced("gray quests"):find("^@quest "), "Alt+` asks the questions in the search's order: gray quests: "
		.. ns.Easy.ToAdvanced("gray quests"))
	res = UI:Search("the missing diplomat > chain")
	check(res[1] and res[1].noActivate, "a quest nothing comes before: said so: " .. Names(res))

	-- Simple mode's words
	ns.db.easyMode = true
	for _, s in ipairs({ "quest chain for seeking the blade", "quest chain for outlaw sabre", "seeking the blade quest chain" }) do
		UI:Hide(); FlushAll()
		UI:Open(s); FlushAll()
		res = UI.Results()
		check(#res == 5 and res[5].name == "Seeking the Blade", s .. ": " .. Names(res))
	end
	UI:Hide(); FlushAll()

	ns.db.easyMode = save.easy
	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
	_G.UnitRace, _G.UnitClass = save.race, save.class
	I.Setup(); FlushAll()
end

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
			[200] = { name = "Baron Aquanis", questLevel = 24, zoneOrSort = 12,
				objectivesText = { "Bring the strange water globe to Je'neu Sancrea." } },
		}),
		Npc = Entity({ [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } }, npcFlags = 2 } }),
		Item = Entity({
			[9001] = { name = "Outlaw Sabre", questRewards = { 102 } },
			[9002] = { name = "Strike of the Hydra", questRewards = { 200 } },
			[9003] = { name = "Diplomat Ring", questRewards = { 101 } },
			[9004] = { name = "Linen Cloth", vendors = { 240 } },
		}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	Fresh()
	I.Setup(); FlushAll()
	check(I.qdb.list and #I.qdb.list == 7, "the quests indexed: " .. tostring(I.qdb.list and #I.qdb.list))

	-- the items some quest rewards: by name, part of it, a close spelling
	check(#QR.Index() == 3, "the items quests reward (not the cloth): " .. #QR.Index())
	local q = QR.Question("outlaw saber quest")
	check(q and q.items[1].name == "Outlaw Sabre", "\"outlaw saber quest\": the Outlaw Sabre (a close spelling)")
	for _, s in ipairs({ "quest for outlaw sabre", "which quest rewards the outlaw sabre?", "outlaw sabre quest reward", "sabre quest" }) do
		local qq = QR.Question(s)
		check(qq and qq.items[1].name == "Outlaw Sabre", s .. ": the Outlaw Sabre")
	end
	check(QR.Question("linen cloth quest") == nil and QR.Question("outlaw sabre") == nil and QR.Question("@questie sabre") == nil
		and QR.Question("missing diplomat quest") == nil, "no quest reward named, no quest word, Advanced syntax, a quest called that: a search")

	-- Simple mode: the quest rewarding it, not the one whose words are close
	ns.db.easyMode = true
	UI:Hide(); FlushAll()
	UI:Open("outlaw saber quest"); FlushAll()
	local res = UI.Results()
	check(res[1] and res[1].name == "Seeking the Blade" and res[1].detail:find("^Rewards Outlaw Sabre") and #res == 1,
		"outlaw saber quest: the quest rewarding it: " .. Names(res) .. " / " .. tostring(res[1] and res[1].detail))
	check(tostring(UI.status:GetText()):find("Quests that reward Outlaw Sabre", 1, true), "the footer says so: " .. tostring(UI.status:GetText()))
	check(ns.Easy.ToAdvanced("outlaw saber quest") == "@questie reward:outlaw_sabre ", "Alt+`: " .. ns.Easy.ToAdvanced("outlaw saber quest"))
	UI:Hide(); FlushAll()

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
	check(#res == 5 and res[5].name == "Seeking the Blade", "an item's name: the chain of the quest rewarding it: " .. Names(res))
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

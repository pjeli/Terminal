-- (0.65.3, the player's ask: "quests that reward bags"; there are some notable ones) the quests whose reward is a bag (a
-- quiver, an ammo pouch) that you can still take, the most slots first; @questie reward:bag in Advanced.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, QD, QR, F = ns.Integrations, ns.QuestieData, ns.QuestRewards, ns.Filters

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
	F.ClearCache()
	QR.Forget()
	QR.ForgetSlots()
end
local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[questbags: quests that reward bags]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
		easy = ns.db.easyMode, inst = C_Item.GetItemInfoInstant, done = C_QuestLog.IsQuestFlaggedCompleted,
		cached = C_Item.IsItemDataCachedByID, ti = rawget(_G, "C_TooltipInfo") }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
	_G.LibQuestieDB = {
		Quest = Entity({
			[600] = { name = "The Tailor's Errand", questLevel = 12, requiredLevel = 8, zoneOrSort = 12 },
			[601] = { name = "Pouch for a Farmer", questLevel = 5, requiredLevel = 1, zoneOrSort = 12 },
			[602] = { name = "Old Sack Run", questLevel = 6, requiredLevel = 1, zoneOrSort = 12 },
			[603] = { name = "Horde Satchel", questLevel = 10, requiredLevel = 5, zoneOrSort = 12, requiredRaces = 2 + 16 + 32 + 128 },
			[604] = { name = "Herbalist's Favor", questLevel = 15, requiredLevel = 10, zoneOrSort = 12 },
			[605] = { name = "The Fletcher", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
			[606] = { name = "A Sword for You", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
		}),
		Npc = Entity({}),
		Item = Entity({
			[7001] = { name = "Tailor's Satchel", questRewards = { 600 } },
			[7002] = { name = "Small Brown Pouch", questRewards = { 601 } },
			[7003] = { name = "Old Sack", questRewards = { 602 } },
			[7004] = { name = "Horde Satchel", questRewards = { 603 } },
			[7005] = { name = "Herb Pouch", questRewards = { 604 } },
			[7006] = { name = "Light Quiver", questRewards = { 605 } },
			[7007] = { name = "Bagged Sword", questRewards = { 606 } },
		}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	-- class, subclass, its subclass's name, its slots
	local ITEMS = { [7001] = { 1, 0, "Bag", 12 }, [7002] = { 1, 0, "Bag", 6 }, [7003] = { 1, 0, "Bag", 8 }, [7004] = { 1, 0, "Bag", 14 },
		[7005] = { 1, 2, "Herb Bag", 12 }, [7006] = { 11, 2, "Quiver", 8 }, [7007] = { 2, 7, "One-Handed Swords" } }
	C_Item.GetItemInfoInstant = function(id)
		local t = ITEMS[id]
		if not t then return nil end
		return id, "x", t[3], "", 1, t[1], t[2]
	end
	local loaded = { [7001] = true, [7002] = true, [7004] = true, [7005] = true, [7006] = true }
	C_Item.IsItemDataCachedByID = function(id) return loaded[id] == true end
	_G.C_TooltipInfo = { GetItemByID = function(id)
		local t = ITEMS[id]
		if not (t and t[4] and loaded[id]) then return { lines = {} } end
		return { lines = { { leftText = ITEMS[id] and "Name" }, { leftText = ("%d Slot %s"):format(t[4], t[3]) } } }
	end }
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 602 end
	Fresh()
	I.Setup(); FlushAll()
	check(QR.Index() and #QR.Index() == 7, "the rewards indexed")

	-- the question
	for _, s in ipairs({ "quests that reward bags", "bag quests", "which quests give a bag", "quests with bags",
		"quest bags", "biggest bag quests", "quests that reward pouches" }) do
		local q = QR.BagQuestion(s)
		check(q and q.kind == "bag", s .. ": quests rewarding bags")
	end
	check((QR.BagQuestion("quivers from quests") or {}).kind == "quiver", "quivers from quests: quivers")
	check((QR.BagQuestion("quests that reward ammo pouches") or {}).kind == "ammo", "ammo pouches: ammo pouches")
	for _, s in ipairs({ "bags", "my bags", "bag", "quests", "outlaw sabre quest", "bag of marbles quest", "bag slots" }) do
		check(not QR.BagQuestion(s), s .. ": not that question")
	end

	-- the answer: the most slots first; done, another race's and not-a-bag left out; a trade's bag said so
	ns.db.easyMode = true
	UI:Hide(); FlushAll()
	UI:Open("quests that reward bags"); FlushAll()
	local res = UI.Results()
	check(Names(res) == "The Tailor's Errand | Herbalist's Favor | Pouch for a Farmer",
		"the bags you can still get, the most slots first (then the lowest level): " .. Names(res))
	check(res[1] and res[1].detail:find("Rewards Tailor's Satchel", 1, true) and res[1].detail:find("12 slots", 1, true),
		"each says which bag and its slots: " .. tostring(res[1] and res[1].detail))
	check(res[2] and res[2].detail:find("Herb Bag", 1, true) and not res[1].detail:find("  Bag", 1, true),
		"a trade's bag says which; a plain one doesn't: " .. tostring(res[2] and res[2].detail))
	check(tostring(UI.status:GetText()):find(ns.L["%d done already, not listed"]:format(1), 1, true),
		"the footer: how many you've done: " .. tostring(UI.status:GetText()))
	check(ns.QuestionToAdvanced("quests that reward bags") == "quests that reward bags ", "Alt+`: the line as said")
	UI:Hide(); FlushAll()
	-- a bag the game hasn't sent yet: listed without its slots (asked for), after those with them
	loaded[7001] = nil
	QR.ForgetSlots()
	UI:Open("bag quests"); FlushAll()
	res = UI.Results()
	check(Names(res) == "Herbalist's Favor | Pouch for a Farmer | The Tailor's Errand" and not res[3].detail:find("slots", 1, true),
		"its slots not known yet: last, no slots said: " .. Names(res))
	UI:Hide(); FlushAll()
	loaded[7001] = true
	-- quivers
	UI:Open("quivers from quests"); FlushAll()
	check(Names(UI.Results()) == "The Fletcher", "quivers from quests: " .. Names(UI.Results()))
	UI:Hide(); FlushAll()

	-- Advanced: @questie reward:bag (every quest whose reward is one, by the item's class: not the Bagged Sword's)
	ns.db.easyMode = false; UI:EasyChanged()
	UI.lastScan = nil
	local adv = {}
	for _, e in ipairs(UI:Search("@questie reward:bag")) do adv[#adv + 1] = e.name end
	table.sort(adv)
	adv = table.concat(adv, " | ")
	check(adv:find("Pouch for a Farmer", 1, true) and adv:find("Herbalist's Favor", 1, true) and not adv:find("A Sword for You", 1, true)
		and not adv:find("The Fletcher", 1, true), "@questie reward:bag: the bags' quests, not the Bagged Sword's: " .. adv)

	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
	_G.UnitRace, _G.UnitClass = save.race, save.class
	C_Item.GetItemInfoInstant, C_QuestLog.IsQuestFlaggedCompleted, C_Item.IsItemDataCachedByID = save.inst, save.done, save.cached
	_G.C_TooltipInfo = save.ti
	ns.db.easyMode = save.easy; UI:EasyChanged()
	Fresh()
	I.Setup(); FlushAll()
	UI.lastScan = nil
end

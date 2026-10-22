-- 0.65.x review (0.65.10): quests that reward bags — Simple and Advanced agree with a bag and a quiver offered, on ties and on bags
-- whose slots aren't known yet (asked for in Advanced too, no tooltip read per keystroke).
-- review of 0.65.3/0.65.4 bag quests: Simple vs Advanced, reward:pouch, tooltip scans
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, QD, QR, F = ns.Integrations, ns.QuestieData, ns.QuestRewards, ns.Filters
local function say(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end io.write("  >> " .. table.concat(t, " ") .. "\n") end

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
	if QR.ForgetSlots then QR.ForgetSlots() end
	if QR.ForgetFaction then QR.ForgetFaction() end
end
local function Names(rows)
	local t = {}
	for _, e in ipairs(rows) do if ns.Bar.Real(e) then t[#t + 1] = tostring(e.name) end end
	return table.concat(t, " | ")
end

local tipCalls = 0
local function Setup(quests, items, ITEMS, loaded)
	_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Hunter", "HUNTER", 3 end
	_G.LibQuestieDB = {
		Quest = Entity(quests), Npc = Entity({}), Item = Entity(items),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	C_Item.GetItemInfoInstant = function(id)
		local t = ITEMS[id]
		if not t then return nil end
		return id, "x", t[3], "", 1, t[1], t[2]
	end
	C_Item.IsItemDataCachedByID = function(id) return loaded[id] == true end
	_G.C_TooltipInfo = { GetItemByID = function(id)
		tipCalls = tipCalls + 1
		local t = ITEMS[id]
		if not (t and t[4] and loaded[id]) then return { lines = {} } end
		return { lines = { { leftText = "Name" }, { leftText = ("%d Slot %s"):format(t[4], t[3]) } } }
	end }
	C_QuestLog.IsQuestFlaggedCompleted = function() return false end
	Fresh()
	I.Setup(); FlushAll()
end

local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
	easy = ns.db.easyMode, inst = C_Item.GetItemInfoInstant, done = C_QuestLog.IsQuestFlaggedCompleted,
	cached = C_Item.IsItemDataCachedByID, ti = rawget(_G, "C_TooltipInfo"), faction = _G.UnitFactionGroup }

local function Adv(line)
	ns.db.easyMode = false
	for _, p in pairs(ns.providers) do p._dirty = true end
	UI.lastScan = nil
	local r = UI:Search(line)
	ns.db.easyMode = true
	return r
end
local function Simple(q)
	ns.db.easyMode = true
	for _, p in pairs(ns.providers) do p._dirty = true end
	UI.lastScan = nil
	return UI:Search(q)
end

io.write("[R1: a quest rewarding a bag AND a quiver]\n")
do
	Setup({
		[700] = { name = "Bag Or Quiver", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
		[701] = { name = "Ten Slot Bag Quest", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
	}, {
		[7100] = { name = "Small Satchel", questRewards = { 700 } },
		[7101] = { name = "Big Quiver", questRewards = { 700 } },
		[7102] = { name = "Ten Bag", questRewards = { 701 } },
	}, { [7100] = { 1, 0, "Bag", 6 }, [7101] = { 11, 2, "Quiver", 14 }, [7102] = { 1, 0, "Bag", 10 } },
	{ [7100] = true, [7101] = true, [7102] = true })
	local s = Names(Simple("quests that reward bags"))
	local line = ns.QuestionToAdvanced("quests that reward bags")
	local a = Names(Adv(line))
	say("simple:", s); say("advanced (" .. line .. "):", a)
	check(s == a, "R1 Simple and Advanced same order for a quest offering a bag and a quiver: " .. s .. " // " .. a)
	local same, why = T.SameAsAdvanced("quests that reward bags")
	check(same, "R1 SameAsAdvanced: " .. tostring(why))
	local d = QR.BagDetail(setmetatable({ kind = "questie", qid = 700, detail = "" }, {}))
	check(d and d:find("Small Satchel", 1, true), "R1 Advanced detail for reward:bag names the bag, not the quiver: " .. tostring(d))
end

io.write("[R2: equal slots, equal level: tie order]\n")
do
	Setup({
		[710] = { name = "Zeta Errand", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
		[711] = { name = "Alpha Errand", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
	}, {
		[7110] = { name = "Bag Z", questRewards = { 710 } },
		[7111] = { name = "Bag A", questRewards = { 711 } },
	}, { [7110] = { 1, 0, "Bag", 8 }, [7111] = { 1, 0, "Bag", 8 } }, { [7110] = true, [7111] = true })
	local same, why = T.SameAsAdvanced("quests that reward bags")
	check(same, "R2 SameAsAdvanced with a tie: " .. tostring(why))
end

io.write("[R3: two bags whose slots aren't known yet]\n")
do
	Setup({
		[720] = { name = "Aaa High", questLevel = 20, requiredLevel = 15, zoneOrSort = 12 },
		[721] = { name = "Zzz Low", questLevel = 5, requiredLevel = 1, zoneOrSort = 12 },
		[722] = { name = "Known Bag", questLevel = 9, requiredLevel = 1, zoneOrSort = 12 },
	}, {
		[7120] = { name = "Bag One", questRewards = { 720 } },
		[7121] = { name = "Bag Two", questRewards = { 721 } },
		[7122] = { name = "Bag Three", questRewards = { 722 } },
	}, { [7120] = { 1, 0, "Bag", 8 }, [7121] = { 1, 0, "Bag", 8 }, [7122] = { 1, 0, "Bag", 6 } }, { [7122] = true })
	local same, why = T.SameAsAdvanced("quests that reward bags")
	check(same, "R3 SameAsAdvanced with unknown slots: " .. tostring(why))
	-- Advanced alone asks nothing of the server for them (no F.loading, no RequestLoadItemDataByID)
	local asked = 0
	local req = C_Item.RequestLoadItemDataByID
	C_Item.RequestLoadItemDataByID = function() asked = asked + 1 end
	Adv("@questie reward:bag -is:done sort:slots ")
	local advAsked, advLoading = asked, F.loading
	asked = 0
	Simple("quests that reward bags")
	say("advanced asked:", advAsked, "loading:", advLoading, " simple asked:", asked, "loading:", F.loading)
	check(advAsked > 0 or advLoading, "R3b Advanced reward:bag sort:slots asks for the bags' data as Simple does")
	C_Item.RequestLoadItemDataByID = req
end

io.write("[R5: reward:pouch / pouch quest: ammo pouches and items called pouch]\n")
do
	Setup({
		[730] = { name = "Shot Pouch Quest", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
		[731] = { name = "Ammo Run", questLevel = 10, requiredLevel = 5, zoneOrSort = 12 },
	}, {
		[7130] = { name = "Small Shot Pouch", questRewards = { 730 } },
		[7131] = { name = "Pouch of Bullets", questRewards = { 731 } },
	}, { [7130] = { 11, 3, "Ammo Pouch", 8 }, [7131] = { 15, 0, "Junk" } }, { [7130] = true, [7131] = true })
	local a = Names(Adv("@questie reward:pouch "))
	say("@questie reward:pouch ->", a)
	check(a:find("Shot Pouch Quest", 1, true), "R5 reward:pouch finds the quest rewarding Small Shot Pouch: " .. a)
	local b = Names(Adv("@questie reward:small_shot_pouch "))
	say("@questie reward:small_shot_pouch ->", b)
	local s = Names(Simple("pouch quest"))
	say("Simple 'pouch quest' ->", s)
	check(s:find("Shot Pouch Quest", 1, true), "R5 'pouch quest' lists the Small Shot Pouch's quest: " .. s)
end

io.write("[R7: tooltip scans per keystroke in Advanced]\n")
do
	local quests, items, ITEMS = {}, {}, {}
	for i = 1, 100 do
		quests[800 + i] = { name = "Bag Quest " .. i, questLevel = 10, requiredLevel = 5, zoneOrSort = 12 }
		items[8000 + i] = { name = "Some Bag " .. i, questRewards = { 800 + i } }
		ITEMS[8000 + i] = { 1, 0, "Bag", 6 + (i % 10) }
	end
	Setup(quests, items, ITEMS, {}) -- none loaded yet (fresh login; or items the client never has)
	tipCalls = 0
	Adv("@questie reward:bag ")
	local one = tipCalls
	tipCalls = 0
	for _, l in ipairs({ "@questie reward:bag b", "@questie reward:bag ba", "@questie reward:bag bag", "@questie reward:bag bag " }) do Adv(l) end
	say("tooltip scans: first search", one, "; next 4 keystrokes", tipCalls)
	check(tipCalls == 0, "R7 typing on after reward:bag rescans no tooltips (membership needs no slots): " .. tipCalls .. " scans in 4 keystrokes")
	tipCalls = 0
	Adv("@questie bag sort:slots ")
	say("tooltip scans for @questie bag sort:slots:", tipCalls)
end

_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
_G.UnitRace, _G.UnitClass = save.race, save.class
C_Item.GetItemInfoInstant, C_QuestLog.IsQuestFlaggedCompleted, C_Item.IsItemDataCachedByID = save.inst, save.done, save.cached
_G.C_TooltipInfo, _G.UnitFactionGroup = save.ti, save.faction
ns.db.easyMode = save.easy; UI:EasyChanged()
Fresh()
I.Setup(); FlushAll()
UI.lastScan = nil

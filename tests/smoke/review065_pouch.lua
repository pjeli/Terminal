-- 0.65.x review (0.65.10): reward:pouch and "pouch quest" are the items named so again, not every bag.
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

_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
_G.UnitRace, _G.UnitClass = save.race, save.class
C_Item.GetItemInfoInstant, C_QuestLog.IsQuestFlaggedCompleted, C_Item.IsItemDataCachedByID = save.inst, save.done, save.cached
_G.C_TooltipInfo, _G.UnitFactionGroup = save.ti, save.faction
ns.db.easyMode = save.easy; UI:EasyChanged()
Fresh()
I.Setup(); FlushAll()
UI.lastScan = nil

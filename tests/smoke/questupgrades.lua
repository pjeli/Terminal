-- (0.51.15, the player's ask) upgrades from quests: "quest upgrades" lists the quests near your level you can still take
-- whose reward is an upgrade for you, the biggest first, with what it rewards and how far its giver is; @questie
-- is:upgrade judges a quest by its rewards.
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
end
local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[questupgrades: quests whose reward is an upgrade]\n")
do
	local save = { Q = _G.Questie, L = _G.QuestieLoader, Lib = _G.LibQuestieDB, race = _G.UnitRace, class = _G.UnitClass,
		easy = ns.db.easyMode, info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel,
		inv = _G.GetInventoryItemLink, can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo,
		inst = C_Item.GetItemInfoInstant, invId = _G.GetInventoryItemID, done = C_QuestLog.IsQuestFlaggedCompleted,
		here = I.Here, dist = I.NpcDistance, head = _G.INVTYPE_HEAD, str = _G.ITEM_MOD_STRENGTH_SHORT }
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.LibQuestieDB = {
		Quest = Entity({
			[500] = { name = "Wolf Trouble", questLevel = 20, requiredLevel = 16, zoneOrSort = 12, startedBy = { { 240 } } },
			[501] = { name = "Weak Hat", questLevel = 21, requiredLevel = 16, zoneOrSort = 12, startedBy = { { 240 } } },
			[502] = { name = "Old Errand", questLevel = 8, requiredLevel = 4, zoneOrSort = 12 },
			[503] = { name = "Finished Errand", questLevel = 20, requiredLevel = 16, zoneOrSort = 12 },
			[504] = { name = "Horde Errand", questLevel = 20, requiredLevel = 16, zoneOrSort = 12, requiredRaces = 2 + 16 + 32 + 128 },
			[505] = { name = "Boot Camp", questLevel = 22, requiredLevel = 18, zoneOrSort = 12, startedBy = { { 240 } } },
		}),
		Npc = Entity({ [240] = { name = "Marshal Dughan", spawns = { [12] = { { 42.1, 65.9 } } }, npcFlags = 2 } }),
		Item = Entity({
			[9501] = { name = "Helm of the Wolf", questRewards = { 500 } },
			[9502] = { name = "Cap of Weakness", questRewards = { 501 } },
			[9503] = { name = "Old Great Helm", questRewards = { 502 } },
			[9504] = { name = "Finished Helm", questRewards = { 503 } },
			[9505] = { name = "Horde Helm", questRewards = { 504 } },
			[9506] = { name = "Camp Boots", questRewards = { 505 } },
		}),
		flavor = { name = "Forever", rules = "Classic" },
		Enum = { byExpansion = { Classic = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, TRAINER = 16 } } } },
	}
	local ITEMS = {
		[9500] = { "Worn Helm", "|Hitem:9500|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9501] = { "Helm of the Wolf", "|Hitem:9501|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9502] = { "Cap of Weakness", "|Hitem:9502|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9503] = { "Old Great Helm", "|Hitem:9503|h", 2, 10, 5, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9504] = { "Finished Helm", "|Hitem:9504|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9505] = { "Horde Helm", "|Hitem:9505|h", 2, 22, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[9506] = { "Camp Boots", "|Hitem:9506|h", 2, 22, 18, "Armor", "Mail", 1, "INVTYPE_FEET" },
	}
	local STATS = { [9500] = { ITEM_MOD_STRENGTH_SHORT = 3 }, [9501] = { ITEM_MOD_STRENGTH_SHORT = 8 },
		[9502] = { ITEM_MOD_STRENGTH_SHORT = 2 }, [9503] = { ITEM_MOD_STRENGTH_SHORT = 9 }, [9504] = { ITEM_MOD_STRENGTH_SHORT = 10 },
		[9505] = { ITEM_MOD_STRENGTH_SHORT = 11 }, [9506] = { ITEM_MOD_STRENGTH_SHORT = 4 } }
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemStats = function(link) return STATS[idOf(link)] end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	_G.UnitLevel = function() return 20 end
	C_PlayerInfo.CanUseItem = function() return true end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9500|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 9500 end end
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 503 end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) if id == 240 then return 42, { cont = 1, x = 30, y = 30 } end end
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT = "Head", "Strength"
	Fresh()
	I.Setup(); FlushAll()
	check(QR.Index() and #QR.Index() == 6, "the rewards indexed")

	-- the question
	for _, s in ipairs({ "quest upgrades", "upgrade quests", "quests with upgrades", "upgrades from quests", "Quest rewards that are upgrades" }) do
		check(QR.UpgradeQuestion(s), s .. ": asks for upgrades from quests")
	end
	for _, s in ipairs({ "upgrades", "helm upgrades", "quests", "quest for the helm of doom upgrades" }) do
		check(not QR.UpgradeQuestion(s), s .. ": not that question")
	end
	-- Simple mode: the quests, biggest first; the too-low, done and other faction's left out, and the one that isn't
	ns.db.easyMode = true
	UI:Hide(); FlushAll()
	UI:Open("quest upgrades"); FlushAll()
	local res = UI.Results()
	check(Names(res) == "Wolf Trouble | Boot Camp", "quest upgrades: the quests whose reward is an upgrade, biggest first: " .. Names(res))
	check(res[1] and res[1].detail == "42 yd  Rewards Helm of the Wolf" and res[1]._dist == 42 and res[1].wcont == 1,
		"...what it rewards, and how far its giver is (the arrow's place): " .. tostring(res[1] and res[1].detail))
	local why = {}
	for _, l in ipairs(T.UpgradeWhy(res[1]) or {}) do why[#why + 1] = l.text end
	why = table.concat(why, " | ")
	check(why == "Helm of the Wolf | Over what you wear (slot: head): | +5 Strength", "the tooltip says why: " .. why)
	check(tostring(UI.status:GetText()):find(ns.L["Quests whose reward is an upgrade for you"], 1, true), "the footer says what they are")
	-- (0.52.3) its tooltip: which reward is the upgrade, and the game's comparison of that reward
	local compared = {}
	local realTC = _G.C_TooltipComparison
	_G.C_TooltipComparison = { GetItemComparisonInfo = function(item) compared[#compared + 1] = item.hyperlink end,
		GetItemComparisonDelta = function() return {} end }
	UI.sel = 1
	local TT = _G.TerminalTooltip
	local said, realAdd = {}, TT.AddLine
	TT.AddLine = function(self, s, ...) said[#said + 1] = tostring(s) return realAdd(self, s, ...) end
	TT.entry = nil -- (drawn again: shown already as the list came up)
	UI:UpdateTooltip()
	TT.AddLine = realAdd
	_G.C_TooltipComparison = realTC
	said = table.concat(said, " | ")
	check(said:find("Helm of the Wolf", 1, true) and not said:find("upgrade for you", 1, true),
		"the quest's tooltip names the reward compared, no \"an upgrade\" line: " .. said)
	check(compared[1] == "|Hitem:9501|h", "a quest's tooltip: the game compares its reward: " .. tostring(compared[1]))
	check(ns.Easy.ToAdvanced("quest upgrades") == "@questie is:upgrade sort:best ", "Alt+`: " .. ns.Easy.ToAdvanced("quest upgrades"))
	UI:Hide(); FlushAll()
	-- Advanced: is:upgrade judges a quest by its rewards
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Open("@questie is:upgrade sort:best"); FlushAll()
	res = UI.Results()
	-- (no level, faction or done check in Advanced: is:todo, lvl: are there for that)
	check(Names(res) == "Horde Errand | Finished Errand | Wolf Trouble | Boot Camp",
		"@questie is:upgrade sort:best: by their rewards, biggest first: " .. Names(res))
	UI:Hide(); FlushAll()

	Fresh()
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = save.Q, save.L, save.Lib
	_G.UnitRace, _G.UnitClass, ns.db.easyMode = save.race, save.class, save.easy
	UI:EasyChanged()
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, C_Item.GetItemInfoInstant = save.can, save.det, save.inst
	_G.GetInventoryItemID, C_QuestLog.IsQuestFlaggedCompleted = save.invId, save.done
	I.Here, I.NpcDistance = save.here, save.dist
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT = save.head, save.str
	I.Setup(); FlushAll()
end

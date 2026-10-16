-- (review, 0.53.6) small fixes in the lists: a macro's #show line, .history's "|", the Quick Keybind row's text
local T = ...
local ns, check = T.ns, T.check

io.write("[review: macros, history, keybinds]\n")
do -- a macro starting with #show (any case): its first command is the detail
	local real = _G.GetMacroInfo
	_G.GetMacroInfo = function(i) if i == 1 then return "Hearth", 1, "#Show Hearthstone\n/use Hearthstone" end return real(i) end
	ns.providers.macros._dirty = true
	local hearth
	for _, e in ipairs(ns:GetEntries(ns.providers.macros)) do if e.name == "Hearth" then hearth = e end end
	_G.GetMacroInfo = real
	ns.providers.macros._dirty = true
	check(hearth and tostring(hearth.detail):find("/use Hearthstone", 1, true) and not tostring(hearth.detail):find("#Show", 1, true),
		"#Show: the macro's first command is said, not the directive: " .. tostring(hearth and hearth.detail))
end
do -- .history: a "|" typed ("linen|wool") said as "||" in chat
	local h = ns.db.history
	ns.db.history = { "linen|wool" }
	local out = ns:FindCommand("history").run("")
	ns.db.history = h
	check(out[2] and out[2]:find("linen||wool", 1, true), ".history escapes |: " .. tostring(out[2]))
end
do -- Quick Keybind Mode's row points at the button by the button's own text
	local a, b = _G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE = "Quick Keybind", "Quick Keybind Mode"
	ns.providers.keybinds._dirty = true
	local row = ns:GetEntries(ns.providers.keybinds)[1]
	_G.SETTINGS_QUICK_KEYBIND_BUTTON, _G.QUICK_KEYBIND_MODE = a, b
	ns.providers.keybinds._dirty = true
	check(row and row.rowText == "Quick Keybind" and row.name == "Quick Keybind Mode",
		"its row is the mode's name, pointing at the button's text: " .. tostring(row and row.rowText))
end
do -- @xp: read again on opening only once a minute has passed (alts' rested fills slowly)
	T.check(ns.providers.experience.refreshOnOpen == 60, "@xp's refresh on open: at most once a minute")
end
do -- in: on achievements: their detail (progress, points) isn't worked out per row: it never says a place
	local real, asked = _G.GetAchievementInfo, 0
	_G.GetAchievementInfo = function(...) asked = asked + 1 if real then return real(...) end end
	ns.providers.achievements._dirty = true
	local list = ns:GetEntries(ns.providers.achievements)
	asked = 0
	local f = ns.Filters.Parse("in:barrens")
	for _, e in ipairs(list) do ns.Filters.Pass(e, { f }) end
	_G.GetAchievementInfo = real
	ns.providers.achievements._dirty = true
	T.check(#list > 0 and asked == 0, ("in: over %d achievements: none read from the game for it (%d)"):format(#list, asked))
end
do -- @gear made again when a skill is learned (Plate Mail at a trainer: what you can use changes, no bag event)
	local p = ns.providers.gear
	ns:GetEntries(p)
	p._dirty = false
	T.ef.scripts.OnEvent(T.ef, "SKILL_LINES_CHANGED")
	T.FlushAll()
	T.check(p._dirty == true, "SKILL_LINES_CHANGED: @gear to be made again")
end
do -- an Item row's Enter opens your bags on where the item is now, not where it was when the list was made
	local B = ns.Bags
	local save = { open = B.Open, ids = B.BagIDs, n = C_Container.GetContainerNumSlots, info = C_Container.GetContainerItemInfo }
	local opened
	B.Open = function(bags) opened = bags return nil end
	B.BagIDs = function() return { 0, 1, 2 } end
	C_Container.GetContainerNumSlots = function() return 4 end
	C_Container.GetContainerItemInfo = function(bag, slot) if bag == 2 and slot == 3 then return { itemID = 4242 } end end
	B.Show({ itemID = 4242, name = "Moved Thing", locs = { { 1, 1 } } })
	B.Open, B.BagIDs, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = save.open, save.ids, save.n, save.info
	T.check(opened and opened[1] == 2 and #opened == 1, "the item moved to bag 2: bag 2 opened, not bag 1: " .. tostring(opened and opened[1]))
end
do -- the items list made again (a bag changed): Questie isn't asked again what each item starts, nor each quest's needs
	local QD = ns.QuestieData
	local real = QD.DB
	local asked = { item = 0, quest = 0 }
	local fake = {
		QueryItemSingle = function() asked.item = asked.item + 1 return nil end,
		QueryQuestSingle = function() asked.quest = asked.quest + 1 return nil end,
	}
	QD.DB = function() return fake end
	ns.providers.items._dirty = true
	ns:GetEntries(ns.providers.items)
	local first = { item = asked.item, quest = asked.quest }
	asked.item, asked.quest = 0, 0
	ns.providers.items._dirty = true
	ns:GetEntries(ns.providers.items)
	QD.DB = real
	ns.providers.items._dirty = true
	T.check(first.item > 0 and asked.item == 0 and asked.quest == 0,
		("made again: Questie asked nothing again (items %d then %d, quests %d then %d)"):format(first.item, asked.item, first.quest, asked.quest))
end
do -- an item the client's own data says isn't equipment ("" slot): no GetItemInfo asked to make sure
	local inst, info = C_Item.GetItemInfoInstant, C_Item.GetItemInfo
	local asked = 0
	C_Item.GetItemInfoInstant = function(id) return 4243, "Trade Goods", "Cloth", "" end
	C_Item.GetItemInfo = function(...) asked = asked + 1 return info(...) end
	local loc = ns.ItemGear.EquipLoc({ itemID = 4243 })
	C_Item.GetItemInfoInstant, C_Item.GetItemInfo = inst, info
	T.check(loc == nil and asked == 0, "not equipment by the instant answer: GetItemInfo not asked: " .. asked)
end
do -- a damaged piece's repair cost asked once while it stays as worn (the list is made again after every loot)
	local DU = ns.Durability
	local TI = _G.C_TooltipInfo
	local asked = 0
	_G.C_TooltipInfo = { GetInventoryItem = function() asked = asked + 1 return { repairCost = 1234 } end }
	local a = DU.CostOf("|Hitem:777|h", 40, 100, 5)
	local b = DU.CostOf("|Hitem:777|h", 40, 100, 5)
	local c = DU.CostOf("|Hitem:777|h", 30, 100, 5) -- (worn more: asked again)
	_G.C_TooltipInfo = TI
	T.check(a == 1234 and b == 1234 and c == 1234 and asked == 2, "the cost asked once per wear: " .. asked)
end
do -- Baganator's bag windows: looked for again (at most once a second) while none shows, so a view made later is found
	local Roots = ns.Bags._BaganatorRoots
	local t = 1000
	local realTime = _G.GetTime
	_G.GetTime = function() return t end
	Roots(true) -- (none yet)
	local f = { GetChildren = function() end, IsShown = function() return true end }
	_G.Baganator_CategoryViewBackpackViewFrameelvui = f
	local soon = Roots()
	t = t + 1.5
	local later = Roots()
	_G.Baganator_CategoryViewBackpackViewFrameelvui = nil
	Roots(true)
	_G.GetTime = realTime
	T.check(#soon == 0 and later[1] == f, "a view made later: found once a second has passed")
end

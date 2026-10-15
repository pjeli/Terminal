-- (0.51.14, the player's ask) the best upgrades first: "upgrades" (and sort:best) orders them by how much each beats
-- what you wear, and the tooltip says why ("+6 Strength over current (slot: head)").
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F = ns.Filters

io.write("[bestfirst: the biggest upgrades first, the tooltip saying why]\n")
do
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel, inv = _G.GetInventoryItemLink,
		can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo, class = _G.UnitClass, inst = C_Item.GetItemInfoInstant,
		invId = _G.GetInventoryItemID, providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode,
		head = _G.INVTYPE_HEAD, str = _G.ITEM_MOD_STRENGTH_SHORT, sta = _G.ITEM_MOD_STAMINA_SHORT }
	local ITEMS = {
		[70] = { "Worn Helm", "|Hitem:70|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[71] = { "Alpha Helm", "|Hitem:71|h", 2, 21, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[72] = { "Beta Helm", "|Hitem:72|h", 2, 21, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[73] = { "Gamma Helm", "|Hitem:73|h", 2, 21, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
	}
	local STATS = { [70] = { ITEM_MOD_STRENGTH_SHORT = 3 }, [71] = { ITEM_MOD_STRENGTH_SHORT = 6 },
		[72] = { ITEM_MOD_STRENGTH_SHORT = 9 }, [73] = { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 2 } }
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemStats = function(link) return STATS[idOf(link)] end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	C_PlayerInfo.CanUseItem = function() return true end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:70|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 70 end end
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT = "Head", "Strength", "Stamina"
	F.ClearCache()
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
		return { { name = "Alpha Helm", itemID = 71, key = 71, link = "item:71" }, { name = "Beta Helm", itemID = 72, key = 72, link = "item:72" },
			{ name = "Gamma Helm", itemID = 73, key = 73, link = "item:73" } }
	end })
	local function Names(res)
		local t = {}
		for _, e in ipairs(res) do if e.itemID then t[#t + 1] = e.name end end
		return table.concat(t, ", ")
	end
	-- Simple mode: "upgrades" (the only category with them: opened for you), the biggest first
	ns.Easy.Set(true)
	UI.lastScan, UI.lastOverview, UI.category = nil, nil, nil
	UI:Open("upgrades")
	FlushAll()
	check(Names(UI.Results()) == "Beta Helm, Alpha Helm, Gamma Helm",
		"upgrades: the biggest first (+6 Str, +3 Str, +1 Str +2 Sta), not by name: " .. Names(UI.Results()))
	-- the tooltip says why
	UI:UpdateTooltip() -- (the terminal's own tooltip made)
	local TT = _G.TerminalTooltip
	local lines, real = {}, TT.AddLine
	TT.AddLine = function(self, s, ...) lines[#lines + 1] = tostring(s) if real then return real(self, s, ...) end end
	for i, e in ipairs(UI.Results()) do if e.name == "Gamma Helm" then UI.sel = i end end
	UI:UpdateTooltip()
	TT.AddLine = real
	local tip = table.concat(lines, "\n")
	check(tip:find("+2 Stamina, +1 Strength over current (slot: head)", 1, true), "the tooltip says why: " .. tip:gsub("\n", " | "))
	UI:Hide(); FlushAll()
	-- Advanced: is:upgrade as it was (by name), sort:best the biggest first
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Open("@loot is:upgrade")
	FlushAll()
	check(Names(UI.Results()) == "Alpha Helm, Beta Helm, Gamma Helm", "@loot is:upgrade: as before: " .. Names(UI.Results()))
	UI:Open("@loot is:upgrade sort:best")
	FlushAll()
	check(Names(UI.Results()) == "Beta Helm, Alpha Helm, Gamma Helm", "@loot is:upgrade sort:best: the biggest first: " .. Names(UI.Results()))
	-- another search after: no "why" on its rows
	UI:Open("@loot helm")
	FlushAll()
	check(F.UpgradeWhy(UI.Results()[1]) == nil, "a search that doesn't weigh upgrades: its tooltips say nothing of them")
	UI:Hide(); FlushAll()

	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview, UI.category = nil, nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID = save.invId
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT = save.head, save.str, save.sta
	F.ClearCache()
	UI:Hide(); FlushAll()
end

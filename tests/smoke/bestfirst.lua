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
		head = _G.INVTYPE_HEAD, str = _G.ITEM_MOD_STRENGTH_SHORT, sta = _G.ITEM_MOD_STAMINA_SHORT, agi = _G.ITEM_MOD_AGILITY_SHORT,
		weapon = _G.INVTYPE_WEAPON, dw = _G.CanDualWield, dps = _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT }
	local ITEMS = {
		[70] = { "Worn Helm", "|Hitem:70|h", 2, 20, 15, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[71] = { "Alpha Helm", "|Hitem:71|h", 2, 21, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[72] = { "Beta Helm", "|Hitem:72|h", 2, 21, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
		[73] = { "Gamma Helm", "|Hitem:73|h", 2, 21, 16, "Armor", "Mail", 1, "INVTYPE_HEAD" },
	}
	local STATS = { [70] = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_AGILITY_SHORT = 2 }, [71] = { ITEM_MOD_STRENGTH_SHORT = 6 },
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
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT, _G.ITEM_MOD_AGILITY_SHORT = "Head", "Strength", "Stamina", "Agility"
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
	TT.AddLine = function(self, s, r, g, b, ...)
		local colour = (r == 0.25 and g == 1) and "green" or (r == 1 and g == 0.3) and "red" or "other"
		lines[#lines + 1] = tostring(s) .. "=" .. colour
		if real then return real(self, s, r, g, b, ...) end
	end
	for i, e in ipairs(UI.Results()) do if e.name == "Gamma Helm" then UI.sel = i end end
	UI:UpdateTooltip()
	TT.AddLine = real
	local tip = table.concat(lines, "\n")
	-- (0.51.17, the player: gains green, losses red, a line each, gains first)
	check(tip:find("Over what you wear (slot: head):=other\n+2 Stamina=green\n+1 Strength=green\n-2 Agility=red", 1, true),
		"the tooltip says why, a line each, gains (green) then losses (red): " .. tip:gsub("\n", " | "))
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

	-- (0.51.17, the player: a mace weighed against main hand and shield together) a one-hander against the main hand only
	-- when the off hand holds a shield
	ITEMS[80] = { "Old Mace", "|Hitem:80|h", 2, 20, 15, "Weapon", "One-Handed Maces", 1, "INVTYPE_WEAPON" }
	ITEMS[81] = { "Tower Shield", "|Hitem:81|h", 2, 20, 15, "Armor", "Shields", 1, "INVTYPE_SHIELD" }
	ITEMS[82] = { "Better Mace", "|Hitem:82|h", 2, 21, 16, "Weapon", "One-Handed Maces", 1, "INVTYPE_WEAPON" }
	ITEMS[83] = { "Lesser Mace", "|Hitem:83|h", 2, 21, 16, "Weapon", "One-Handed Maces", 1, "INVTYPE_WEAPON" }
	STATS[80] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 2 }
	STATS[81] = { RESISTANCE0_NAME = 600, ITEM_MOD_STAMINA_SHORT = 3 }
	STATS[82] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12, ITEM_MOD_STRENGTH_SHORT = 3 }
	STATS[83] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9, ITEM_MOD_STRENGTH_SHORT = 2 }
	_G.GetInventoryItemLink = function(_, slot)
		if slot == 16 then return "|Hitem:80|h[Old Mace]|h" elseif slot == 17 then return "|Hitem:81|h[" .. ITEMS[81][1] .. "]|h" end
	end
	_G.GetInventoryItemID = function(_, slot) if slot == 16 then return 80 elseif slot == 17 then return 81 end end
	_G.CanDualWield = function() return true end
	_G.INVTYPE_WEAPON, _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "One-Hand", "Damage Per Second"
	F.ClearCache()
	local fit = F.GearFit()
	local better, lesser = { itemID = 82, kind = "loot" }, { itemID = 83, kind = "loot" }
	check(fit(better) and not fit(lesser), "with a shield: against the main hand (a weaker mace than yours isn't one, though it beats the shield)")
	local why = F.UpgradeWhy(better)
	local text = {}
	for _, l in ipairs(why or {}) do text[#text + 1] = l.text end
	text = table.concat(text, " | ")
	check(not text:find("600", 1, true) and text:find("+1 Strength", 1, true), "...its why says nothing of the shield's armor: " .. text)
	-- dual wielding: the weaker weapon of the two
	ITEMS[81] = { "Off Mace", "|Hitem:81|h", 2, 20, 15, "Weapon", "One-Handed Maces", 1, "INVTYPE_WEAPON" }
	STATS[81] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8, ITEM_MOD_STRENGTH_SHORT = 1 }
	F.ClearCache()
	fit = F.GearFit()
	check(fit({ itemID = 83, kind = "loot" }), "dual wielding: a mace better than your off-hand one is one")
	-- (0.51.19, the player's ask) dual wielding: why against each hand it beats; one it doesn't beat isn't said
	local function WhyText(e)
		local t = {}
		for _, l in ipairs(F.UpgradeWhy(e) or {}) do t[#t + 1] = l.text end
		return table.concat(t, " | ")
	end
	local mid, best = { itemID = 83, kind = "loot" }, { itemID = 82, kind = "loot" }
	fit(mid); fit(best)
	check(WhyText(mid) == "Over Off Mace: | +1 Damage Per Second | +1 Strength",
		"better than the off hand only: against it alone: " .. WhyText(mid))
	check(WhyText(best) == "Over Off Mace: | +4 Damage Per Second | +2 Strength | Over Old Mace: | +2 Damage Per Second | +1 Strength",
		"better than both: against each, the bigger gain first: " .. WhyText(best))

	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastOverview, UI.category = nil, nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID = save.invId
	_G.INVTYPE_HEAD, _G.ITEM_MOD_STRENGTH_SHORT, _G.ITEM_MOD_STAMINA_SHORT, _G.ITEM_MOD_AGILITY_SHORT = save.head, save.str, save.sta, save.agi
	_G.INVTYPE_WEAPON, _G.CanDualWield, _G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = save.weapon, save.dw, save.dps
	F.ClearCache()
	UI:Hide(); FlushAll()
end

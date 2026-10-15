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
	check(Names(UI.Results()) == "Beta Helm, Alpha Helm",
		"upgrades: the biggest first (+6 Str, +3 Str -2 Agi), not by name: " .. Names(UI.Results()))
	-- (0.52.7, the player: "pretty clear upgrades; only slight trade-offs") +1 Str +2 Sta for -2 Agi gives up more than
	-- half of what it gains (a warrior's weights): not one
	check(not Names(UI.Results()):find("Gamma", 1, true), "a big trade-off (Gamma Helm) isn't an upgrade")
	-- (0.52.3, 0.52.5: the player's asks) the tooltip says it's an upgrade, and the game's comparison is in it: what
	-- the game would compare with, named, and its stat changes as it words them (no tooltips of the game's beside it)
	UI:UpdateTooltip() -- (the terminal's own tooltip made)
	local TT = _G.TerminalTooltip
	local asked, deltaFor = {}, {}
	local realTC = _G.C_TooltipComparison
	local WORN = { hyperlink = "|Hitem:70|h[Worn Helm]|h" }
	_G.C_TooltipComparison = {
		GetItemComparisonInfo = function(item) asked[#asked + 1] = item.hyperlink return { method = 0, item = WORN, additionalItems = {} } end,
		GetItemComparisonDelta = function(item, worn) deltaFor[#deltaFor + 1] = worn.hyperlink return { "+2 Stamina", "+1 Strength", "-2 Agility" } end,
		CompareItem = function() error("the game's tooltips aren't asked for") end,
	}
	local realName = C_Item.GetItemNameByID
	C_Item.GetItemNameByID = function(k) if tostring(k):find("item:70", 1, true) then return "Worn Helm" end end
	local lines, real = {}, TT.AddLine
	TT.AddLine = function(self, s, r, g, b, ...)
		local colour = (r == 0.25 and g == 1) and "green" or (r == 1 and g == 1 and b == 1) and "white" or (r == 1 and g == 0.82) and "gold" or "other"
		lines[#lines + 1] = tostring(s) .. "=" .. colour
		if real then return real(self, s, r, g, b, ...) end
	end
	for i, e in ipairs(UI.Results()) do if e.name == "Alpha Helm" then UI.sel = i end end
	TT.entry = nil
	UI:UpdateTooltip()
	local tip = table.concat(lines, "\n")
	check(asked[1] == "item:71" and deltaFor[1] == WORN.hyperlink, "the game says what to compare the item with, and the changes: "
		.. tostring(asked[1]) .. " / " .. tostring(deltaFor[1]))
	check(not tip:find("=green", 1, true) and tip:find(ns.L["Over %s:"]:format("Worn Helm") .. "=gold", 1, true)
		and tip:find("+2 Stamina=white\n+1 Strength=white\n-2 Agility=white", 1, true),
		"in the tooltip: over what (named), the game's lines; no \"an upgrade\" line (the list is of upgrades): " .. tip:gsub("\n", " | "))
	-- two it could replace (rings, trinkets): a part for each
	local OTHER = { hyperlink = "|Hitem:74|h[Other]|h" }
	_G.C_TooltipComparison.GetItemComparisonInfo = function() return { method = 0, item = WORN, additionalItems = { OTHER } } end
	deltaFor, lines = {}, {}
	TT.entry = nil
	UI:UpdateTooltip()
	check(deltaFor[1] == WORN.hyperlink and deltaFor[2] == OTHER.hyperlink, "two pieces it could replace: compared with each")
	-- (0.52.8, the player: "sometimes not showing the delta") a row whose verdict a background search dropped (judged
	-- again meanwhile) is still compared while it's on screen; nothing worn there: said so
	_G.C_TooltipComparison.GetItemComparisonInfo = function(item) asked[#asked + 1] = item.hyperlink return { method = 0, item = WORN, additionalItems = {} } end
	local selRow = UI.Results()[UI.sel]
	F.SetGain(selRow, nil)
	asked = {}
	TT.entry = nil
	UI:UpdateTooltip()
	check(asked[1] == "item:71", "its verdict dropped by a background search: compared all the same: " .. tostring(asked[1]))
	_G.C_TooltipComparison.GetItemComparisonInfo = function() return nil end
	lines = {}
	TT.entry = nil
	UI:UpdateTooltip()
	check(table.concat(lines, "|"):find(ns.L["Nothing worn there to compare with"], 1, true), "nothing worn in its slot: said so")
	_G.C_TooltipComparison.GetItemComparisonInfo = function(item) asked[#asked + 1] = item.hyperlink return { method = 0, item = WORN, additionalItems = {} } end
	-- in combat too (nothing kept from addons)
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	deltaFor = {}
	TT.entry = nil
	UI:UpdateTooltip()
	_G.InCombatLockdown = realCombat
	check(#deltaFor > 0, "in combat: compared all the same")
	_G.C_TooltipComparison.GetItemComparisonInfo = function(item) asked[#asked + 1] = item.hyperlink return { method = 0, item = WORN, additionalItems = {} } end
	-- the item not loaded yet: said, waited for, then compared once it's in (not Terminal's own numbers meanwhile)
	local realCached = C_Item.IsItemDataCachedByID
	local loaded = false
	C_Item.IsItemDataCachedByID = function(id) if id == 71 then return loaded end return true end
	asked, lines = {}, {}
	TT.entry = nil
	UI:UpdateTooltip()
	tip = table.concat(lines, "\n")
	check(#asked == 0 and tip:find(ns.L["Comparing once the game has the item..."], 1, true), "not loaded: said so, no comparison yet")
	loaded = true
	local waiter = UI.tipWaiter
	waiter:GetScript("OnEvent")(waiter, "GET_ITEM_INFO_RECEIVED", 71, true)
	check(asked[1] == "item:71", "...loaded: the tooltip drawn again, compared: " .. tostring(asked[1]))
	C_Item.IsItemDataCachedByID = realCached
	TT.AddLine = real
	UI:Hide(); FlushAll()
	-- a search that doesn't weigh upgrades: no comparison on its rows
	UI:Open("@loot helm")
	FlushAll()
	asked = {}
	TT.entry = nil
	UI:UpdateTooltip()
	check(#asked == 0, "rows not weighed as upgrades: no comparison")
	C_Item.GetItemNameByID = realName
	_G.C_TooltipComparison = realTC
	UI:Hide(); FlushAll()
	-- Advanced: is:upgrade as it was (by name), sort:best the biggest first
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Open("@loot is:upgrade")
	FlushAll()
	check(Names(UI.Results()) == "Alpha Helm, Beta Helm", "@loot is:upgrade: as before: " .. Names(UI.Results()))
	UI:Open("@loot is:upgrade sort:best")
	FlushAll()
	check(Names(UI.Results()) == "Beta Helm, Alpha Helm", "@loot is:upgrade sort:best: the biggest first: " .. Names(UI.Results()))
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

	-- (review, 0.51.25) a two-hander worn: a one-hander is weighed against it once, not as two weapons
	ITEMS[84] = { "Big Axe", "|Hitem:84|h", 2, 20, 15, "Weapon", "Two-Handed Axes", 1, "INVTYPE_2HWEAPON" }
	STATS[84] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9, ITEM_MOD_STRENGTH_SHORT = 1 }
	_G.GetInventoryItemLink = function(_, slot) if slot == 16 then return "|Hitem:84|h[Big Axe]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 16 then return 84 end end
	F.ClearCache()
	fit = F.GearFit()
	local over2h = { itemID = 82, kind = "loot" }
	check(fit(over2h) and WhyText(over2h) == "Over what you wear (slot: one-hand): | +3 Damage Per Second | +2 Strength",
		"over a two-hander: once, not twice: " .. WhyText(over2h))
	-- (review, 0.51.25) a gain from an earlier search isn't another's: sort:best without is:upgrade orders nothing by it
	local e = { itemID = 82, kind = "loot" }
	fit(e)
	check(F.GainOf(e) ~= nil, "weighed: a gain")
	_G.GetInventoryItemLink = function(_, slot) if slot == 16 or slot == 17 then return "|Hitem:82|h[Better Mace]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 16 or slot == 17 then return 82 end end
	F.ClearCache()
	check(not F.GearFit()(e) and F.GainOf(e) == nil, "weighed again, no upgrade now: its old gain gone")
	-- (review, 0.51.25) an empty slot's piece with no stats to weigh goes after real upgrades, not above them
	_G.INVTYPE_TRINKET = _G.INVTYPE_TRINKET or "Trinket"
	ITEMS[85] = { "Shiny Trinket", "|Hitem:85|h", 2, 21, 16, "Armor", "Miscellaneous", 1, "INVTYPE_TRINKET" }
	STATS[85] = {}
	F.ClearCache()
	local tr, helm = { itemID = 85, kind = "loot" }, { itemID = 71, kind = "loot" }
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:70|h[Worn Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 70 end end
	fit = F.GearFit()
	check(fit(tr) and fit(helm) and F.GainOf(tr).gain < F.GainOf(helm).gain,
		"an empty trinket slot's statless trinket below a real upgrade: " .. tostring(F.GainOf(tr) and F.GainOf(tr).gain))

	-- (0.52.7, the player: "items I already have equipped" in the list) a ring you wear isn't an upgrade, though it beats
	-- your other ring; a better ring is
	_G.INVTYPE_FINGER = _G.INVTYPE_FINGER or "Finger"
	ITEMS[90] = { "Good Ring", "|Hitem:90|h", 2, 20, 15, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" }
	ITEMS[91] = { "Weak Ring", "|Hitem:91|h", 2, 20, 15, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" }
	ITEMS[92] = { "Great Ring", "|Hitem:92|h", 2, 21, 16, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER" }
	STATS[90], STATS[91], STATS[92] = { ITEM_MOD_STRENGTH_SHORT = 6 }, { ITEM_MOD_STRENGTH_SHORT = 1 }, { ITEM_MOD_STRENGTH_SHORT = 8 }
	_G.GetInventoryItemLink = function(_, slot)
		if slot == 11 then return "|Hitem:90|h[Good Ring]|h" elseif slot == 12 then return "|Hitem:91|h[Weak Ring]|h" end
	end
	_G.GetInventoryItemID = function(_, slot) if slot == 11 then return 90 elseif slot == 12 then return 91 end end
	F.ClearCache()
	fit = F.GearFit()
	check(not fit({ itemID = 90, kind = "loot" }) and fit({ itemID = 92, kind = "loot" }),
		"the ring you wear: not an upgrade (though it beats your other one); a better ring is")
	-- (0.52.7) a clear upgrade: slight trade-offs at most, and enough of a gain
	local W = F.WEIGHTS.WARRIOR
	check(F.ClearGain({ str = 6 }, { str = 3, agi = 2 }, W), "+3 Str for -2 Agi: an upgrade (gives up less than half)")
	check(not F.ClearGain({ str = 4, sta = 2 }, { str = 3, agi = 2 }, W), "+1 Str +2 Sta for -2 Agi: not (gives up most of it)")
	check(not F.ClearGain({ str = 20.5 }, { str = 20 }, W), "+0.5 Str on 20: too little to be one")
	check(not F.ClearGain({ str = 3 }, { str = 3 }, W), "the same: not one")

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

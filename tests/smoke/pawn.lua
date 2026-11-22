-- Pawn's scales judge is:upgrade (1.7.3, a player on CurseForge: "It'd be nice if item upgrade searches could use the
-- current Pawn scales automatically when Pawn is installed, instead of having to export and paste to transfer the
-- weights"). A stand-in for Pawn's functions for other addons (PawnIsReady, PawnGetAllScalesEx, PawnGetAllStatValues).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F, L = ns.Filters, ns.L

io.write("[pawn: the scales Pawn shows judge is:upgrade]\n")
do
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel, inv = _G.GetInventoryItemLink,
		can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo, class = _G.UnitClass, inst = C_Item.GetItemInfoInstant,
		invId = _G.GetInventoryItemID, providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode,
		roles = ns.db.upgradeRoles, custom = ns.db.upgradeCustom, points = ns.Talents.Points,
		ready = rawget(_G, "PawnIsReady"), all = rawget(_G, "PawnGetAllScalesEx"), values = rawget(_G, "PawnGetAllStatValues") }
	ns.Talents.Points = function() return {} end
	local ITEMS = {
		[80] = { "Feral Helm", "|Hitem:80|h", 2, 20, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[81] = { "Healer Helm", "|Hitem:81|h", 2, 20, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[82] = { "Cat Helm", "|Hitem:82|h", 2, 20, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
	}
	local STATS = { [80] = { ITEM_MOD_AGILITY_SHORT = 6 }, [81] = { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 5 },
		[82] = { ITEM_MOD_AGILITY_SHORT = 9 } }
	local idOf = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
	C_Item.GetItemInfo = function(id) local t = ITEMS[idOf(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemStats = function(link) return STATS[idOf(link)] end
	C_Item.GetDetailedItemLevelInfo = function(link) local t = ITEMS[idOf(link)] return t and t[4] end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[idOf(id)] return idOf(id), t and t[6], t and t[7], t and t[9] end
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Druid", "DRUID", 11 end
	C_PlayerInfo.CanUseItem = function() return true end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:80|h[Feral Helm]|h" end end
	_G.GetInventoryItemID = function(_, slot) if slot == 1 then return 80 end end
	F.ClearCache()
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function()
		return { { name = "Healer Helm", itemID = 81, key = 81, link = "item:81" }, { name = "Cat Helm", itemID = 82, key = 82, link = "item:82" } }
	end })
	ns.db.easyMode = false
	ns.db.upgradeRoles, ns.db.upgradeCustom = nil, nil
	local function Upgrades()
		F.ForgetPawn(); F.ClearFit()
		local t = {}
		for _, e in ipairs(UI:Search("@loot is:upgrade")) do if e.itemID then t[#t + 1] = e.name end end
		table.sort(t)
		return table.concat(t, ", ")
	end
	local weights = ns:FindCommand("weights")
	local integrations = ns:FindCommand("integrations")
	local function Integrations() return table.concat(integrations.run("", ns), "\n") end

	-- no Pawn: as before (a druid's levelling tree)
	_G.PawnIsReady, _G.PawnGetAllScalesEx, _G.PawnGetAllStatValues = nil, nil, nil
	check(Upgrades() == "Cat Helm" and not Integrations():find("Pawn:", 1, true), "no Pawn: Terminal's own weights, no Pawn line: " .. Upgrades())

	-- Pawn with a healer's scale shown (and a cat's not shown)
	local ready = true
	local SCALES = {
		{ Name = "\"Pawn\":Healer", LocalizedName = "Healer", IsVisible = true },
		{ Name = "Kitty", LocalizedName = "Kitty", IsVisible = false },
	}
	local VALUES = { ["\"Pawn\":Healer"] = { Intellect = 1, Spirit = 0.8, Stamina = 0.2, IsCloth = 1, ExpertiseRating = 0.3 },
		Kitty = { Agility = 1, Strength = 0.5 } }
	_G.PawnIsReady = function() return ready end
	_G.PawnGetAllScalesEx = function() return SCALES end
	_G.PawnGetAllStatValues = function(name) return VALUES[name] end
	local scales = (function() F.ForgetPawn() return F.PawnScales() end)()
	check(scales and #scales == 1 and scales[1].name == "Healer" and scales[1].w.int == 1 and scales[1].w.spi == 0.8
		and scales[1].ignored[1] == "ExpertiseRating" and #scales[1].ignored == 1,
		"Pawn's shown scale read: its name, its weights in Terminal's stats, a stat not weighed said (IsCloth isn't a stat)")
	check(Upgrades() == "Healer Helm", "Pawn's Healer scale judges: the Healer Helm, not the Cat Helm: " .. Upgrades())
	local set = F.MyWeightSets()[1]
	check(set[2] == F.PawnRole("Healer"), "its role: Pawn \"Healer\" (the tooltip's \"An upgrade for\")")
	check(Integrations():find(L["found: its scales shown in tooltips judge is:upgrade (%s)"]:format('"Healer"'), 1, true),
		".integrations: Pawn found, its scale named: " .. Integrations())
	local lines = table.concat(weights.run("", ns), "\n")
	check(lines:find(F.PawnRole("Healer") .. " " .. L["(now: from Pawn)"], 1, true) and not lines:find(L["(now: your class's levelling tree)"], 1, true),
		".weights: Pawn's scale is the one now, not the levelling tree: " .. lines)

	-- both shown: an upgrade for either
	SCALES[2].IsVisible = true
	check(Upgrades() == "Cat Helm, Healer Helm", "two scales shown: an upgrade for either: " .. Upgrades())

	-- the same weights read again: the same table (the verdicts kept are keyed by it)
	F.ForgetPawn()
	local a = F.PawnScales()
	F.ForgetPawn()
	local b = F.PawnScales()
	check(a ~= b and a[1].w ~= nil, "(read twice from scratch: new tables)")
	local keepWas = F.PAWN_EVERY
	F.PAWN_EVERY = -1 -- (read every time)
	local c1 = F.PawnScales()
	local c2 = F.PawnScales()
	check(c1 == c2, "read again, the same weights: the same table")
	F.PAWN_EVERY = keepWas

	-- a tree picked in .weights wins; .weights pawn goes back to Pawn's
	weights.run("feral", ns)
	SCALES[2].IsVisible = false
	check(F.MyRoles()[1] == "feral" and Upgrades() == "Cat Helm", "feral picked in .weights: Pawn's scale not used: " .. Upgrades())
	check(Integrations():find(L["found, not used: you picked %s in .weights (.weights pawn uses its scales again)"]:format(F.ROLE_SAY.feral), 1, true),
		".integrations says it's not used, and how to use it")
	lines = table.concat(weights.run("pawn", ns), "\n")
	check(F.MyRoles() == nil and lines:find(L["Upgrades: judged by your Pawn scales again."], 1, true) and Upgrades() == "Healer Helm",
		".weights pawn: Pawn's scales again, nothing to paste: " .. lines)

	-- Pawn still loading, or no scale shown: Terminal's own
	ready = false
	check(Upgrades() == "Cat Helm" and Integrations():find(L["found, still loading"], 1, true), "Pawn not ready: Terminal's own weights")
	ready = true
	SCALES[1].IsVisible = false
	check(Upgrades() == "Cat Helm" and Integrations():find(L["found, no scale shown in its tooltips for this character: is:upgrade uses Terminal's own weights"], 1, true),
		"no scale shown: Terminal's own weights")
	-- OneForAll's gear value steps aside while Pawn's scales judge
	SCALES[1].IsVisible = true
	F.ForgetPawn()
	check(F.PawnJudges() ~= nil, "Pawn's scales judge (none picked)")
	local G = ns.OneForAllGear
	if G and G.Judge then check(G.Judge() == nil, "OneForAll's gear value not used while Pawn's scales judge") end
	-- a pasted Pawn string is read as before
	local w, name = F.ParsePawn('( Pawn: v1: "Bear": Stamina=1, Armor=0.1, Agility=0.5 )')
	check(w and name == "Bear" and w.sta == 1 and w.agi == 0.5, "a pasted Pawn string: read as before")

	_G.PawnIsReady, _G.PawnGetAllScalesEx, _G.PawnGetAllStatValues = save.ready, save.all, save.values
	F.ForgetPawn()
	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID, ns.providers, ns.providerOrder, ns.db.easyMode = save.invId, save.providers, save.order, save.easy
	ns.db.upgradeRoles, ns.db.upgradeCustom, ns.Talents.Points = save.roles, save.custom, save.points
	F.ClearCache()
end

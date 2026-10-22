-- Upgrades by role (0.54.1, a player's ask: "How does the addon score upgrades? Can I control it? On a druid I care about
-- both feral and resto gear"): .weights shows how they're judged and picks roles; a clear upgrade for any role picked
-- counts, and its tooltip says which.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local F, L = ns.Filters, ns.L

io.write("[upgraderoles: .weights, upgrades for the roles you pick]\n")
do
	local save = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, level = _G.UnitLevel, inv = _G.GetInventoryItemLink,
		can = C_PlayerInfo.CanUseItem, det = C_Item.GetDetailedItemLevelInfo, class = _G.UnitClass, inst = C_Item.GetItemInfoInstant,
		invId = _G.GetInventoryItemID, providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode,
		roles = ns.db.upgradeRoles, custom = ns.db.upgradeCustom }
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
	ns.db.upgradeRoles = nil
	local function Upgrades()
		local t = {}
		for _, e in ipairs(UI:Search("@loot is:upgrade")) do if e.itemID then t[#t + 1] = e.name end end
		table.sort(t)
		return table.concat(t, ", ")
	end
	local weights = ns:FindCommand("weights")
	check(F._MyName() ~= nil, "(a character to keep the roles for)")

	-- all-round (none picked): a druid's own weights; the healer helm gives up too much agility to be a clear upgrade
	check(F.MyRoles() == nil and Upgrades() == "Cat Helm", "all-round: the Cat Helm only: " .. Upgrades())
	local lines = table.concat(weights.run("", ns), "\n")
	check(lines:find(L["(now: your class's levelling tree)"], 1, true) and lines:find(F.ROLE_SAY.feral, 1, true) and lines:find(F.ROLE_SAY.restoration, 1, true)
		and lines:find("agi ", 1, true), ".weights: how it's judged, the class's roles and their weights: " .. lines)

	-- (0.65.9, the player: "only let .weights define one role") two roles: said, nothing picked
	lines = table.concat(weights.run("resto feral", ns), "\n")
	check(F.MyRoles() == nil and lines:find(L["One role at a time: .weights %s. Yours: %s"]:sub(1, 10), 1, true), "resto feral: one at a time: " .. lines)
	-- one: the healer
	lines = table.concat(weights.run("resto", ns), "\n")
	local roles = F.MyRoles()
	check(roles and #roles == 1 and roles[1] == "restoration" and lines:find(L["Upgrades: judged for %s."]:format(F.ROLE_SAY.restoration), 1, true), "resto: the healer: " .. lines)
	local healer
	for _, e in ipairs(UI:Search("@loot is:upgrade")) do if e.name == "Healer Helm" then healer = e end end
	check(F.GainOf(healer) and F.GainOf(healer).role == "restoration", "the healer helm: an upgrade as a healer")
	-- (0.65.9, the player: "a gentle footer reminder to set .weights if they don't like the results of upgrade searching")
	UI:Open("@loot is:upgrade"); FlushAll()
	local foot = tostring(UI.status:GetText())
	check(foot:find(L["Not what you'd pick? .weights sets how upgrades are judged"], 1, true), "an upgrade search's footer: .weights: " .. foot)
	UI:SetQuery("@loot helm"); FlushAll()
	foot = tostring(UI.status:GetText())
	check(not foot:find(".weights", 1, true), "another search's: not: " .. foot)
	UI:Hide(); FlushAll()
	-- the tooltip says the role
	UI:Open("@loot is:upgrade"); FlushAll()
	UI:UpdateTooltip()
	local TT = _G.TerminalTooltip
	local said, add = {}, TT.AddLine
	TT.AddLine = function(self, s, ...) said[#said + 1] = tostring(s) return add(self, s, ...) end
	for i, e in ipairs(UI.Results()) do if e.name == "Healer Helm" then UI.sel = i end end
	TT.entry, TT.noneFor = nil, nil
	TT:Hide()
	UI:UpdateTooltip()
	TT.AddLine = add
	check(table.concat(said, "\n"):find(L["An upgrade for: %s"]:format(F.ROLE_SAY.restoration), 1, true), "the tooltip: for which role: " .. table.concat(said, " / "))
	UI:Hide(); FlushAll()

	-- healer alone: the cat helm's agility counts for nothing
	weights.run("healer", ns)
	check(Upgrades() == "Healer Helm", "healer alone: " .. Upgrades())
	-- not a druid's role: said, nothing changed
	lines = table.concat(weights.run("fury", ns), "\n")
	check(lines:find(L["Not a role of your class: %s. Yours: %s"]:sub(1, 12), 1, true) and F.MyRoles()[1] == "restoration", "fury: not a druid's: " .. lines)
	-- kept per character
	check(type(ns.db.upgradeRoles) == "table" and ns.db.upgradeRoles[F._MyName()][1] == "restoration", "kept for this character")
	weights.run("all", ns)
	check(F.MyRoles() == nil and Upgrades() == "Cat Helm", "all: all-round again")

	-- (0.65.8, the player: "let's add custom weights; and support for the Pawn scale strings") your own weights: a role of
	-- their own, picked when set; weighed scaled (the most wanted 1), said as typed
	ns.db.upgradeCustom = nil
	lines = table.concat(weights.run("set int=2 spi 2", ns), "\n")
	roles = F.MyRoles()
	check(roles and #roles == 1 and roles[1] == "custom" and lines:find("int 2", 1, true), ".weights set int=2 spi 2: your own, picked: " .. lines)
	check(Upgrades() == "Healer Helm", "judged by them: the Healer Helm (agility counts for nothing): " .. Upgrades())
	check(F.MyWeightSets()[1][1].int == 1 and F.CustomWeights().w.int == 2, "weighed scaled (int 1), kept as typed (int 2)")
	check(type(ns.db.upgradeCustom) == "table" and ns.db.upgradeCustom[F._MyName()], "kept for this character")
	lines = table.concat(weights.run("set int=2 luck=5", ns), "\n")
	check(lines:find("luck=5", 1, true) and lines:find("spellcrit", 1, true) and F.CustomWeights().w.spi == 2,
		"a word that isn't a stat: said, with the stats to use; nothing changed: " .. lines)
	-- a Pawn scale string: its stats, its name; what Terminal doesn't weigh (sockets) said, the class and the like skipped
	local PAWN = '( Pawn: v1: "Kitty": Class=Druid, Agility=2, Strength=1.5, HitRating=1, RedSocket=10, MeleeDps=3, RangedDps=1 )'
	local w, name, ignored = F.ParsePawn(PAWN)
	check(w and w.agi == 2 and w.str == 1.5 and w.hit == 1 and w.dps == 3 and name == "Kitty" and #ignored == 1 and ignored[1] == "RedSocket",
		"a Pawn scale read: agi 2, str 1.5, hit 1, dps 3 (the more of melee and ranged); RedSocket not weighed here")
	check(F.ParsePawn("Agility=2") == nil and F.ParsePawn('( Pawn: v1: "x": Class=Druid )') == nil, "not one, or no stat in it: nil")
	lines = table.concat(weights.run("pawn " .. PAWN, ns), "\n")
	check(F.MyRoles()[1] == "custom" and F.CustomWeights().name == "Kitty" and lines:find('"Kitty"', 1, true) and lines:find("RedSocket", 1, true),
		".weights pawn <string>: taken, named, its sockets said: " .. lines)
	check(Upgrades() == "Cat Helm", "judged by the Pawn scale: the Cat Helm: " .. Upgrades())
	weights.run('( Pawn: v1: "Wise": Intellect=3 )', ns)
	check(F.CustomWeights().name == "Wise" and Upgrades() == "Healer Helm", "a Pawn scale string typed alone after .weights: taken too")
	-- .weights pawn alone: a window to paste it in (Pawn's strings are often longer than the prompt takes)
	local O = ns.Options
	local opened
	local real = O.PasteDialog
	O.PasteDialog = function(...) opened = real(...) return opened end
	lines = table.concat(weights.run("pawn", ns), "\n")
	O.PasteDialog = real
	check(opened and opened:IsShown(), ".weights pawn: the paste window opens: " .. lines)
	if opened then
		opened.box:SetText(PAWN)
		opened.Apply()
		check(F.CustomWeights().name == "Kitty" and tostring(opened.status:GetText()):find("Kitty", 1, true), "pasted and applied: " .. tostring(opened.status:GetText()))
		opened:Hide()
		-- (the style's import still a style's)
		local d = O.ImportDialog()
		check(d.onApply == ns.Theme.Import and d.title:GetText() == L["Import a Terminal style"], "Options' Import style: still the style's")
		d:Hide()
	end
	-- a class role picked: yours kept, not used; .weights custom picks them again; forgotten: all-round again
	weights.run("feral", ns)
	check(F.MyRoles()[1] == "feral" and F.CustomWeights() and Upgrades() == "Cat Helm", "feral: yours kept, feral's used: " .. Upgrades())
	weights.run("custom", ns)
	check(F.MyRoles()[1] == "custom" and Upgrades() == "Cat Helm", ".weights custom: yours again (Kitty): " .. Upgrades())
	lines = table.concat(weights.run("clear", ns), "\n")
	check(F.CustomWeights() == nil and F.MyRoles() == nil, ".weights clear: forgotten, all-round again: " .. lines)
	-- (several kept from before 0.65.9: the first that's still yours)
	ns.db.upgradeRoles[F._MyName()] = { "custom", "feral", "healer" }
	roles = F.MyRoles()
	check(roles and #roles == 1 and roles[1] == "feral", "several roles kept from before: the first still yours, alone: " .. tostring(roles and table.concat(roles, ",")))
	check(table.concat(weights.run("custom", ns), "\n"):find(L["Not a role of your class: %s. Yours: %s"]:sub(1, 12), 1, true), "custom with none set: not a role")
	weights.run("all", ns)

	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID, ns.providers, ns.providerOrder, ns.db.easyMode = save.invId, save.providers, save.order, save.easy
	ns.db.upgradeRoles, ns.db.upgradeCustom = save.roles, save.custom
	F.ClearCache()
end

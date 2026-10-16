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
		roles = ns.db.upgradeRoles }
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
	check(lines:find(L["All-round (now): %s"]:sub(1, 8), 1, true) and lines:find(F.ROLE_SAY.feral, 1, true) and lines:find(F.ROLE_SAY.healer, 1, true)
		and lines:find("agi ", 1, true), ".weights: how it's judged, the class's roles and their weights: " .. lines)

	-- feral and healer: either counts
	lines = table.concat(weights.run("resto feral", ns), "\n")
	local roles = F.MyRoles()
	check(roles and roles[1] == "healer" and roles[2] == "feral", "resto feral: healer and feral picked: " .. lines)
	check(Upgrades() == "Cat Helm, Healer Helm", "for either role: both helms: " .. Upgrades())
	local healer
	for _, e in ipairs(UI:Search("@loot is:upgrade")) do if e.name == "Healer Helm" then healer = e end end
	check(F.GainOf(healer) and F.GainOf(healer).role == "healer", "the healer helm: an upgrade as a healer")
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
	check(table.concat(said, "\n"):find(L["An upgrade for: %s"]:format(F.ROLE_SAY.healer), 1, true), "the tooltip: for which role: " .. table.concat(said, " / "))
	UI:Hide(); FlushAll()

	-- healer alone: the cat helm's agility counts for nothing
	weights.run("healer", ns)
	check(Upgrades() == "Healer Helm", "healer alone: " .. Upgrades())
	-- not a druid's role: said, nothing changed
	lines = table.concat(weights.run("tank", ns), "\n")
	check(lines:find(L["Not a role of your class: %s. Yours: %s"]:sub(1, 12), 1, true) and F.MyRoles()[1] == "healer", "tank: not a druid's: " .. lines)
	-- kept per character
	check(type(ns.db.upgradeRoles) == "table" and ns.db.upgradeRoles[F._MyName()][1] == "healer", "kept for this character")
	weights.run("all", ns)
	check(F.MyRoles() == nil and Upgrades() == "Cat Helm", "all: all-round again")

	C_Item.GetItemInfo, C_Item.GetItemStats, _G.UnitLevel, _G.GetInventoryItemLink = save.info, save.stats, save.level, save.inv
	C_PlayerInfo.CanUseItem, C_Item.GetDetailedItemLevelInfo, _G.UnitClass, C_Item.GetItemInfoInstant = save.can, save.det, save.class, save.inst
	_G.GetInventoryItemID, ns.providers, ns.providerOrder, ns.db.easyMode = save.invId, save.providers, save.order, save.easy
	ns.db.upgradeRoles = save.roles
	F.ClearCache()
end

-- Durability (Durability.lua, 0.50.3, the player's ask): @durability lists what wears down, lowest first, with what
-- repairing each costs (the game's figure: the item's tooltip data, repairCost) and the whole bill on top; Simple mode's
-- "durability", "repair cost", "what needs repair", "broken gear"; dura:, is:broken, is:damaged; Shift+Enter walks to
-- the nearest repair vendor.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local DU, P = ns.Durability, ns.providers.durability

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[durability: wear and repair costs]\n")
do
	local save = { dur = _G.GetInventoryItemDurability, info = _G.GetInventorySlotInfo, link = _G.GetInventoryItemLink,
		tex = _G.GetInventoryItemTexture, TI = _G.C_TooltipInfo, cd = C_Container.GetContainerItemDurability,
		ci = C_Container.GetContainerItemInfo, ns_ = C_Container.GetContainerNumSlots, easy = ns.db.easyMode,
		canRepair = _G.CanMerchantRepair, allCost = _G.GetRepairAllCost, vendor = ns.db.repairVendor, guid = _G.UnitGUID }
	_G.UnitGUID = function() return "Player-1-ME" end
	check(P and ns:ResolveProvider("durability") == P and ns:ResolveProvider("dura") == P, "@durability, @dura")
	local SLOT = { HeadSlot = 1, ChestSlot = 5, LegsSlot = 7, FeetSlot = 8, MainHandSlot = 16, Finger0Slot = 11 }
	local worn = {
		[1] = { "Fancy Helm", 40, 50, 1200 }, [5] = { "Tough Chest", 100, 100, 0 }, [7] = { "Leaky Legs", 0, 75, 5025 },
		[8] = { "Old Boots", 9, 45, 830 }, [16] = { "Rusty Sword", 70, 90, 400 }, [11] = { "A Ring", nil, nil, 0 },
	}
	_G.GetInventorySlotInfo = function(n) return SLOT[n] or 99 end
	_G.GetInventoryItemLink = function(_, s) local w = worn[s] return w and ("|cffffffff|Hitem:" .. (900 + s) .. "|h[" .. w[1] .. "]|h|r") end
	_G.GetInventoryItemTexture = function() return "Interface\\Icons\\INV_Helmet_01" end
	_G.GetInventoryItemDurability = function(s) local w = worn[s] if w and w[2] then return w[2], w[3] end end
	local costAsked = 0
	_G.C_TooltipInfo = {
		GetInventoryItem = function(_, s) costAsked = costAsked + 1 local w = worn[s] return w and { repairCost = w[4] } end,
		GetBagItem = function(b, s) if b == 0 and s == 1 then return { repairCost = 300 } end end,
	}
	C_Container.GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end
	C_Container.GetContainerItemDurability = function(b, s)
		if b == 0 and s == 1 then return 10, 40 end
		if b == 0 and s == 2 then return 30, 30 end -- (not damaged: not listed)
	end
	C_Container.GetContainerItemInfo = function(b, s)
		if b == 0 and s == 1 then return { itemID = 777, hyperlink = "|cffffffff|Hitem:777|h[Spare Shield]|h|r", quality = 1, iconFileID = 1 } end
		if b == 0 and s == 2 then return { itemID = 778, hyperlink = "|cffffffff|Hitem:778|h[Fine Gloves]|h|r", quality = 1, iconFileID = 1 } end
	end
	ns.db.easyMode = false
	P._dirty = true
	local res = UI:Search("@durability")
	-- the whole bill on top, then the lowest first; a ring (no durability) and an undamaged bag piece left out
	check(Names(res) == "Repair all: 77s 55c | Leaky Legs | Old Boots | Spare Shield | Rusty Sword | Fancy Helm | Tough Chest",
		"the bill, then lowest first: " .. Names(res))
	check(costAsked == 4, "the repair cost asked only of damaged pieces: " .. costAsked)
	local legs, total = res[2], res[1]
	check(legs.detail:find("broken", 1, true) and legs.detail:find("Legs", 1, true) and legs.detail:find("50s 25c", 1, true)
		and not legs.detail:find("|T", 1, true) and not legs.detail:find("0 / 75", 1, true), "a broken piece, short: " .. legs.detail)
	check(not total.name:find("|T", 1, true), "the bill's name: coins as text (a row draws no icons): " .. total.name)
	check(total.detail:find("5 pieces damaged", 1, true) and total.detail:find("lowest: Legs", 1, true), "the total's detail: " .. total.detail)
	check(res[4].detail:find("25%", 1, true) and res[4].detail:find("in your bags", 1, true), "a bag piece: " .. res[4].detail)
	-- what Enter and Shift+Enter do
	local function V(e) return table.concat({ ns.Easy.Verbs(e) }, "/") end
	check(V(legs) == "show on character/nearest repair" and V(res[4]) == "show in bags/nearest repair" and V(total) == "show in chat/nearest repair",
		"verbs: " .. V(legs) .. ", " .. V(res[4]) .. ", " .. V(total))
	check(legs.secure and legs.slotName == "LegsSlot", "a worn piece opens the character window on its slot")
	check(DU.ShareText(total) == "Repair all: 77s 55c, 5 pieces damaged, lowest: Legs 0%", "the bill for chat: " .. DU.ShareText(total))
	check(DU.ShareText(legs):find("Leaky Legs", 1, true) and DU.ShareText(legs):find("broken, 0/75, repair 50s 25c", 1, true),
		"a piece for chat: " .. DU.ShareText(legs))
	-- Shift+Enter: the nearest repair vendor
	UI:Open("@durability"); FlushAll()
	legs.secondary(legs); FlushAll()
	check(UI.edit:GetText() == "@npc is:repair sort:nearest", "Shift+Enter: the nearest repair vendor: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	-- (0.50.3, the player's screenshot) a name the client hasn't loaded ("[]" in the link): asked for, the list made again
	-- once it's in, not "Item #905"
	local nameByID, asked = C_Item.GetItemNameByID, {}
	local loadData = C_Item.RequestLoadItemDataByID
	C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
	local known = false
	C_Item.GetItemNameByID = function(id) if id == 905 and known then return "Tough Chest" end end
	local link = _G.GetInventoryItemLink
	_G.GetInventoryItemLink = function(u, sl) if sl == 5 then return "|cffffffff|Hitem:905::::::::60:::::::::|h[]|h|r" end return link(u, sl) end
	P._dirty = true
	res = UI:Search("@durability")
	local chest
	for _, e in ipairs(res) do if e.dura and e.dura.slotId == 5 then chest = e end end
	check(chest and chest.name == "Item #905" and asked[1] == 905, "not loaded yet: asked for: " .. tostring(chest and chest.name))
	known = true
	DU.nameFrame:GetScript("OnEvent")(DU.nameFrame, "GET_ITEM_INFO_RECEIVED", 905, true)
	FlushAll()
	res = UI:Search("@durability")
	chest = nil
	for _, e in ipairs(res) do if e.dura and e.dura.slotId == 5 then chest = e end end
	check(chest and chest.name == "Tough Chest", "its name once it's in: " .. tostring(chest and chest.name))
	C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID, _G.GetInventoryItemLink = nameByID, loadData, link
	P._dirty = true
	res = UI:Search("@durability")
	-- a search not naming it: the bill and the damaged pieces, not the ones at full
	local plainRows = P.plain(P, ns:GetEntries(P))
	check(#plainRows == 6 and not Names(plainRows):find("Tough Chest", 1, true), "plain searches: the bill and the damaged: " .. Names(plainRows))
	-- filters
	res = UI:Search("@durability is:broken")
	check(Names(res) == "Leaky Legs", "is:broken: " .. Names(res))
	res = UI:Search("@durability dura:<30")
	check(Names(res) == "Leaky Legs | Old Boots | Spare Shield", "dura:<30: " .. Names(res))
	res = UI:Search("@durability is:damaged")
	check(#res == 5 and not Names(res):find("Tough Chest", 1, true), "is:damaged: " .. Names(res))
	-- .durability
	local lines = ns:FindCommand("durability").run("")
	check(lines[1] == ns.L["Durability:"] and lines[2]:find("^Repair all: 77s 55c") and #lines == 8, ".durability: " .. table.concat(lines, " / "))

	-- (0.50.3, the player's screenshot: 3s 43c listed, the vendor asked 3s 9c) a repair vendor's reputation discount: its
	-- total exact while it's open, and taken off every figure after
	_G.CanMerchantRepair = function() return true end
	_G.GetRepairAllCost = function() return 6980, true end -- (7755 less 10%)
	DU.OnEvent("MERCHANT_SHOW")
	res = UI:Search("@durability")
	check(res[1].cost == 6980 and res[1].detail:find("10% off", 1, true), "at the vendor: its figure to the copper, 10% off said: " .. tostring(res[1].cost) .. " " .. res[1].detail)
	check(res[2].name == "Leaky Legs" and res[2].cost == 4523, "each piece with the discount: " .. tostring(res[2].cost))
	DU.OnEvent("MERCHANT_CLOSED")
	P._dirty = true
	res = UI:Search("@durability")
	local sum = 0
	for i = 2, #res do sum = sum + (res[i].cost or 0) end
	check(res[1].cost == sum and math.abs(sum - 6980) <= 3, "away from it: the pieces' discounted figures added up: " .. tostring(res[1].cost))
	_G.CanMerchantRepair, _G.GetRepairAllCost = save.canRepair, save.allCost
	ns.db.repairVendor = nil
	P._dirty = true
	res = UI:Search("@durability")
	-- Simple mode's questions; "repair" alone and "nearest repair" stay the vendors'
	ns.db.easyMode = true
	for _, s in ipairs({ "durability", "repair cost", "how much to repair", "what needs repair", "my repair bill", "broken gear" }) do
		check(DU.Question(s) ~= nil, s .. ": the durability question")
	end
	for _, s in ipairs({ "repair", "nearest repair", "repair nearby", "broken tooth", "damaged", "@durability",
		-- (review, 0.50.3) items and other searches: a search
		"durability frame", "durability addon", "repair bot cost", "price of repair bot", "i need a repair bot", "who needs repair",
		"armor kit broken", "item level of broken gear", "broken armory", "geared broken" }) do
		check(DU.Question(s) == nil, s .. ": not the durability question")
	end
	UI:Hide(); FlushAll()
	UI:Open("what needs repair"); FlushAll()
	res = UI.Results()
	check(#res == 6 and res[1].duraKind == "total" and tostring(UI.status:GetText()):find("repair all: 77", 1, true),
		"what needs repair: the bill, then the damaged pieces: " .. Names(res) .. " / " .. tostring(UI.status:GetText()))
	UI:Hide(); FlushAll()
	UI:Open("broken gear"); FlushAll()
	check(Names(UI.Results()) == "Leaky Legs", "broken gear: " .. Names(UI.Results()))
	check(ns.Easy.ToAdvanced("broken gear") == "@durability is:broken ", "Alt+`: " .. ns.Easy.ToAdvanced("broken gear"))
	UI:Hide(); FlushAll()
	UI:Open("durability"); FlushAll()
	UI.results[2].secondary(UI.results[2]); FlushAll()
	check(UI.edit:GetText() == "nearest repair", "Simple mode's Shift+Enter: nearest repair: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()

	-- nothing damaged: said so
	for _, w in pairs(worn) do if w[2] then w[2] = w[3] end end
	C_Container.GetContainerItemDurability = function() return nil end
	P._dirty = true
	UI:Open("what needs repair"); FlushAll()
	check(UI.Results()[1] and UI.Results()[1].noActivate and UI.Results()[1].name == ns.L["Nothing to repair"], "nothing damaged: said so: " .. Names(UI.Results()))
	UI:Hide(); FlushAll()
	UI:Open("durability"); FlushAll()
	check(UI.Results()[1].name == ns.L["Nothing to repair"] and UI.Results()[1].detail == ns.L["everything at full durability"],
		"all repaired: no 'lowest: 100%': " .. tostring(UI.Results()[1].detail))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false

	-- a client without the items' figures: the last repair vendor's total
	worn[7][2] = 10
	_G.C_TooltipInfo = nil
	_G.CanMerchantRepair = function() return true end
	_G.GetRepairAllCost = function() return 4321, true end
	ns.db.repairVendor = nil
	DU.OnMerchant()
	local me = UnitGUID("player")
	check(ns.db.repairVendor and ns.db.repairVendor[me] and ns.db.repairVendor[me].cost == 4321, "a repair vendor's total kept, for this character")
	P._dirty = true
	res = UI:Search("@durability")
	check(res[1].name == "Repair all: about 43s 21c", "no figures here: about the vendor's total: " .. tostring(res[1].name))
	-- (review, 0.50.3) another character's vendor total isn't yours; Repair All at the vendor: 0, no figure
	local guid = _G.UnitGUID
	_G.UnitGUID = function() return "Player-1-ALT" end
	P._dirty = true
	res = UI:Search("@durability")
	check(res[1].name == ns.L["Repair all"], "an alt: no figure of yours: " .. tostring(res[1].name))
	_G.UnitGUID = guid
	DU.OnEvent("MERCHANT_SHOW")
	_G.GetRepairAllCost = function() return 0, false end
	DU.OnEvent("UPDATE_INVENTORY_DURABILITY")
	DU.OnEvent("MERCHANT_CLOSED")
	check(ns.db.repairVendor[me].cost == 0, "repaired at the vendor: its total read again: 0")
	P._dirty = true
	res = UI:Search("@durability")
	check(res[1].name == ns.L["Repair all"], "then no stale figure: " .. tostring(res[1].name))

	_G.GetInventoryItemDurability, _G.GetInventorySlotInfo, _G.GetInventoryItemLink, _G.GetInventoryItemTexture = save.dur, save.info, save.link, save.tex
	_G.C_TooltipInfo, C_Container.GetContainerItemDurability, C_Container.GetContainerItemInfo = save.TI, save.cd, save.ci
	C_Container.GetContainerNumSlots, ns.db.easyMode = save.ns_, save.easy
	_G.CanMerchantRepair, _G.GetRepairAllCost, ns.db.repairVendor, _G.UnitGUID = save.canRepair, save.allCost, save.vendor, save.guid
	P._dirty = true
end

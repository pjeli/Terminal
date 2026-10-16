local ns = select(2, ...)
local L = ns.L

-- Durability (@durability, @dura, @repaircost; Simple mode: "durability", "repair cost", "what needs repair", "broken
-- gear", under Character; 0.50.3, the player's ask): every piece you wear that wears down, and the damaged ones in your
-- bags, lowest first, each with its durability and what repairing it costs; a row on top with the whole bill.
--
-- What a repair costs is the game's own figure, the one a repair vendor's tooltip shows (the item's tooltip data,
-- repairCost), before any discount your reputation with the vendor's faction gives. A client that doesn't give it to
-- addons gets the last repair vendor's "repair all" total instead (GetRepairAllCost, read when you open one).
--
--   Enter        a worn piece: the character window, pointing at its slot; one in your bags: your bags on it; the total:
--                every row in chat (only you see it)
--   Shift+Enter  the nearest repair vendor ("nearest repair": Questie's NPCs)

local DU = {}
ns.Durability = DU

local Safe, Num, Str = ns.Safe, ns.Num, ns.Str

-- the slots that wear down (rings, trinkets, neck, back, shirt and tabard don't: their max is 0 or none)
DU.SLOTS = { "HeadSlot", "ShoulderSlot", "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
	"MainHandSlot", "SecondaryHandSlot", "RangedSlot", "BackSlot", "NeckSlot", "Finger0Slot", "Finger1Slot",
	"Trinket0Slot", "Trinket1Slot" }
DU.LOW, DU.WORN = 20, 50 -- (%: red at or below LOW, yellow at or below WORN)

local Money = ns.Money

-- the game's figure for repairing an item: its tooltip data's repairCost (the retail tooltip API), else what a hidden
-- tooltip's SetInventoryItem / SetBagItem gives (the classic one), else nil
local scan
local function ScanTip()
	if scan == nil then
		local ok, t = pcall(CreateFrame, "GameTooltip", "TerminalRepairScanTip", nil, "GameTooltipTemplate")
		scan = ok and t or false
		if scan and scan.SetOwner then pcall(scan.SetOwner, scan, UIParent, "ANCHOR_NONE") end
	end
	return scan or nil
end
local function Cost(slot, bag, bagSlot)
	local TI = C_TooltipInfo
	if TI then
		local data
		if bag then data = TI.GetBagItem and Safe(TI.GetBagItem, bag, bagSlot)
		else data = TI.GetInventoryItem and Safe(TI.GetInventoryItem, "player", slot) end
		-- (asked only of a damaged piece: data without a figure means this client doesn't give it, not "free"; the hidden
		-- tooltip isn't tried then: on this API it goes through every addon's tooltip hooks and gives no figure either)
		local c = type(data) == "table" and Num(data.repairCost)
		return c and c > 0 and c or nil
	end
	local t = ScanTip()
	if not t then return nil end
	local ok, _, _, cost
	if bag then
		if not t.SetBagItem then return nil end
		ok, _, cost = pcall(t.SetBagItem, t, bag, bagSlot) -- (classic: hasCooldown, repairCost)
	else
		if not t.SetInventoryItem then return nil end
		ok, _, _, cost = pcall(t.SetInventoryItem, t, "player", slot) -- (classic: hasItem, hasCooldown, repairCost)
	end
	cost = ok and Num(cost)
	return cost and cost > 0 and cost or nil
end
DU.Cost = Cost

-- (a piece's repair cost, kept by what it depends on: the item and how worn it is. The list is made again after every
-- loot (BAG_UPDATE_DELAYED), and each made asked the tooltip API for every damaged piece; review, 0.53.6)
local costs, costCount = {}, 0
local function CostOf(link, cur, max, slot, bag, bagSlot)
	local key = tostring(link) .. ":" .. cur .. ":" .. max
	local c = costs[key]
	if c == nil then
		c = Cost(slot, bag, bagSlot) or false
		if costCount >= 200 then costs, costCount = {}, 0 end -- (a few pieces at a time: never grows for long)
		costs[key], costCount = c, costCount + 1
	end
	return c or nil
end
DU.CostOf = CostOf -- (tests)

-- Names the client hasn't loaded yet (a link reads "[]" until then: 0.50.3, the player's screenshot showed "Item #270003"):
-- asked for, and the list made again once they're in, or after 10 s (Util.lua's ns.NameWait; review, 0.53.6: this copy
-- never gave up, a name that never came kept the events listened to all session)
local nameWait = ns.NameWait("durability")
DU.nameFrame = nameWait.frame -- (tests)

local function ItemName(link, id)
	return nameWait.Name(id, link) or (id and L["Item #%d"]:format(id)) or "?"
end

--- What wears down, now: { { name, link, itemID, icon, quality, cur, max, pct, cost, slotId, slotName, slotText, bag,
--- bagSlot } }: every worn piece with durability, and the damaged ones in your bags.
function DU.Read()
	local out = {}
	local dur = _G.GetInventoryItemDurability
	if dur then
		for _, slotName in ipairs(DU.SLOTS) do
			local okS, slotId = pcall(GetInventorySlotInfo, slotName)
			if okS and type(slotId) == "number" then
				local cur, max = Safe(dur, slotId)
				cur, max = Num(cur), Num(max)
				local link = Str(Safe(GetInventoryItemLink, "player", slotId))
				if cur and max and max > 0 and link then
					local id = tonumber(link:match("item:(%d+)")) or (C_Item and C_Item.GetItemInfoInstant and Safe(C_Item.GetItemInfoInstant, link))
					local equipLoc = C_Item and C_Item.GetItemInfoInstant and select(4, Safe(C_Item.GetItemInfoInstant, link))
					local quality = C_Item and C_Item.GetItemInfo and select(3, Safe(C_Item.GetItemInfo, link))
					out[#out + 1] = { name = ItemName(link, id), link = link, itemID = id, quality = quality,
						icon = Safe(GetInventoryItemTexture, "player", slotId), cur = cur, max = max,
						cost = (cur < max) and CostOf(link, cur, max, slotId) or nil, slotId = slotId, slotName = slotName,
						slotText = (Str(equipLoc) and Str(_G[equipLoc])) or (ns.SlotText and ns.SlotText(slotId)) or slotName:gsub("Slot", "") }
				end
			end
		end
	end
	local C = C_Container
	if C and C.GetContainerItemDurability and C.GetContainerNumSlots then
		for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
			for s = 1, Num(Safe(C.GetContainerNumSlots, bag)) or 0 do
				local cur, max = Safe(C.GetContainerItemDurability, bag, s)
				cur, max = Num(cur), Num(max)
				if cur and max and max > 0 and cur < max then
					local info = C.GetContainerItemInfo and Safe(C.GetContainerItemInfo, bag, s)
					if type(info) == "table" and info.itemID then
						out[#out + 1] = { name = ItemName(info.hyperlink, info.itemID), link = info.hyperlink, itemID = info.itemID,
							quality = info.quality, icon = info.iconFileID, cur = cur, max = max,
							cost = CostOf(info.hyperlink or info.itemID, cur, max, nil, bag, s),
							bag = bag, bagSlot = s }
					end
				end
			end
		end
	end
	-- (nothing to repair costs nothing; a damaged piece without the game's figure stays nil: not known)
	for _, d in ipairs(out) do
		d.pct = math.floor(100 * d.cur / d.max) -- (down: a damaged piece never reads 100%)
		if d.cur >= d.max then d.cost = 0 end
		d.rawCost = d.cost -- (the game's figure; d.cost: what you'd pay, the last vendor's discount taken off: DU.Collect)
	end
	return out
end

-- the last repair vendor's word for everything (when the items' own figures aren't there): { cost, at }
-- (per character, by GUID: TerminalDB is the account's, and an alt's bill isn't yours)
local MyKey = ns.PlayerGUID
local atVendor = false -- (a repair vendor's window is open: its figure is the bill)
local function Vendor()
	local key = MyKey()
	local t = ns.db and type(ns.db.repairVendor) == "table" and ns.db.repairVendor
	local v = t and key and t[key]
	return type(v) == "table" and v or nil
end

local function PctHex(pct)
	if pct <= DU.LOW then return "|cffff4040" end
	if pct <= DU.WORN then return "|cffffd040" end
	return "|cff40ff40"
end
DU.PctHex = PctHex

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local list -- (the last collect's rows)
local NEAREST = "nearest repair"

-- Shift+Enter: the nearest repair vendor (the search Simple mode's "nearest repair" is, Advanced's @npc is:repair)
local function NearestRepair(e)
	local UI = ns.UI
	local text = (ns.Easy and ns.Easy.On and ns.Easy.On()) and NEAREST or "@npc is:repair sort:nearest"
	UI:WalkTo(text, e)
end

local function Line(e)
	if e.duraKind == "total" then return e.plainDetail end
	return "  " .. (e.link or e.name) .. ":  " .. e.plainDetail
end
--- Every row, for chat (.durability).
function DU.Lines()
	local out = {}
	for _, e in ipairs(list or {}) do out[#out + 1] = Line(e) end
	return out
end
local function PrintAll() ns:Output(DU.Lines()) end

local function ShareText(e)
	if e.duraKind == "total" then return e.plainDetail end
	return (e.link or e.name) .. ": " .. e.plainDetail
end
DU.ShareText = ShareText

local function Tooltip(e, t)
	local d = e.dura
	local shown = false
	if d and d.slotId and t.SetInventoryItem then shown = pcall(t.SetInventoryItem, t, "player", d.slotId)
	elseif d and d.bag and t.SetBagItem then shown = pcall(t.SetBagItem, t, d.bag, d.bagSlot) end
	if not shown then t:SetText(e.name, 1, 0.82, 0) end
	if e.duraKind == "total" then
		for _, r in ipairs(list or {}) do
			if r.duraKind ~= "total" then t:AddDoubleLine(r.name, r.plainDetail, 1, 1, 1, 0.8, 0.8, 0.8) end
		end
	end
	t:AddLine(" ")
	if e.cost and e.cost > 0 then
		t:AddDoubleLine(L["Repair cost"], Money(e.cost), 1, 1, 1, 1, 1, 1)
		local ratio = DU.Ratio()
		if ratio then
			t:AddLine(L["With the last repair vendor's discount (%d%%: your reputation with its faction); another vendor's may differ."]:format(
				math.floor((1 - ratio) * 100 + 0.5)), 0.6, 0.6, 0.6, true)
		else
			t:AddLine(L["Before any discount your reputation with the vendor's faction gives."], 0.6, 0.6, 0.6, true)
		end
	elseif e.costUnknown then
		local v = Vendor()
		if v and e.duraKind == "total" then
			t:AddDoubleLine(L["Last repair vendor"], Money(v.cost) .. "  " .. L["(%s ago)"]:format(ns.Ago((_G.time and _G.time() or 0) - (v.at or 0))),
				1, 1, 1, 1, 1, 1)
		else
			t:AddLine(L["The game doesn't say what repairing it costs here: a repair vendor shows it."], 0.6, 0.6, 0.6, true)
		end
	end
	t:AddLine(e.duraKind == "total" and L["Enter: every piece in chat    Shift+Enter: the nearest repair vendor"]
		or (e.dura and e.dura.bag and L["Enter: show in bags    Shift+Enter: the nearest repair vendor"])
		or L["Enter: show on character    Shift+Enter: the nearest repair vendor"], 0.6, 0.6, 0.6, true)
end

local ITEM = ns.ItemGear and ns.ItemGear.WORN or {}

local function Row(d)
	local e = {
		key = d.slotId and ("slot" .. d.slotId) or ("bag" .. d.bag .. "-" .. d.bagSlot), name = d.name, link = d.link,
		itemID = d.itemID, icon = d.icon, color = ns.QualityHex and ns.QualityHex(d.quality) or nil, dura = d,
		duraPct = d.pct, duraCur = d.cur, duraMax = d.max, cost = d.cost, costUnknown = d.cost == nil and d.cur < d.max or nil,
		slotId = d.slotId, slotName = d.slotName, tooltip = Tooltip, shareLink = ShareText,
		secondary = NearestRepair, secondaryStaysOpen = true,
	}
	if d.slotId then
		e.activate, e.secure, e.isOpen, e.after = ITEM.activate, ITEM.secure, ITEM.isOpen, ITEM.after
	else
		e.activate = function(r) if not (ns.Bags and ns.Bags.ShowItem(r.itemID, r.link, r.name)) then ns:Print(L["You don't carry %s."]:format(tostring(r.name))) end end
	end
	local where = d.slotText or L["in your bags"]
	local state = d.cur == 0 and L["broken"] or (d.pct .. "%")
	local plainCost = (d.cost and d.cost > 0) and L["repair %s"]:format(Money(d.cost, true)) or nil
	-- (short, the row's width is the list's: the points are in the tooltip, the game's own; 0.50.3, the player's screenshot:
	-- "repair..." cut off. Coins as text: a row draws no icons in its words)
	e.detail = ns.Detail(PctHex(d.pct) .. state .. "|r", where, (d.cost and d.cost > 0) and Money(d.cost, true) or nil)
	e.plainDetail = table.concat({ state, ("%d/%d"):format(d.cur, d.max), plainCost }, ", ")
	e.text = table.concat({ "durability repair", ns.Lower(where), d.cur == 0 and "broken" or "", d.cur < d.max and "damaged" or "",
		d.bag and "bag bags" or "equipped worn" }, " ")
	return e
end

local function TotalRow(rows)
	local cost, unknown, damaged, lowest = 0, false, 0, nil
	for _, e in ipairs(rows) do
		if e.cost then cost = cost + e.cost elseif e.costUnknown then unknown = true end
		if e.duraCur < e.duraMax then damaged = damaged + 1 end
		if e.dura.slotId and (not lowest or e.duraPct < lowest.duraPct) then lowest = e end
	end
	local v = Vendor()
	local ratio = DU.Ratio()
	-- (a repair vendor open: what it asks, to the copper)
	if atVendor and not unknown and v and v.cost > 0 then cost = v.cost end
	local name, plain
	if damaged == 0 then
		name = L["Nothing to repair"]
	elseif unknown then
		v = v and v.cost > 0 and v or nil -- (repaired since: no figure)
		name = v and L["Repair all: about %s"]:format(Money(v.cost, true)) or L["Repair all"]
		plain = name
	else
		-- (coins as text: a row's name draws no icons, "3|TInterface\MoneyFrame..." showed; 0.50.3, the player's screenshot)
		name = L["Repair all: %s"]:format(Money(cost, true))
		plain = name
	end
	local e = {
		key = "total", name = name, duraKind = "total", icon = "Interface\\Icons\\Trade_BlackSmithing",
		cost = (not unknown and damaged > 0) and cost or nil, costUnknown = unknown or nil, duraPct = lowest and lowest.duraPct or 100,
		duraCur = damaged > 0 and 0 or 1, duraMax = 1, dura = {},
		tooltip = Tooltip, shareLink = ShareText, activate = PrintAll, secondary = NearestRepair, secondaryStaysOpen = true,
		text = "durability repair all total bill cost",
	}
	local parts = {}
	if damaged > 0 then
		parts[#parts + 1] = (damaged == 1 and L["%d piece damaged"] or L["%d pieces damaged"]):format(damaged)
		if ratio and not unknown then parts[#parts + 1] = L["%d%% off (the last vendor's)"]:format(math.floor((1 - ratio) * 100 + 0.5)) end
		if lowest then parts[#parts + 1] = L["lowest: %s %s"]:format(lowest.dura.slotText or lowest.name, PctHex(lowest.duraPct) .. lowest.duraPct .. "%|r") end
	else
		parts[#parts + 1] = L["everything at full durability"]
	end
	e.detail = ns.Detail(unpack(parts))
	e.plainDetail = (plain and (plain .. ", ") or "") .. ns.Plain(table.concat(parts, ", "))
	if damaged == 0 then e.plainDetail = ns.Plain(table.concat(parts, ", ")) end
	return e
end

--- The last repair vendor's discount for you: what it asks of the game's figure (0.9: 10% off), or nil for none.
function DU.Ratio()
	local v = Vendor()
	local r = v and tonumber(v.ratio)
	return r and r < 0.995 and r or nil
end

function DU.Collect()
	local rows = {}
	local ratio = DU.Ratio()
	for _, d in ipairs(DU.Read()) do
		if ratio and d.rawCost and d.rawCost > 0 then d.cost, d.ratio = math.floor(d.rawCost * ratio + 0.5), ratio end
		rows[#rows + 1] = Row(d)
	end
	-- the lowest first; worn before bags among equals
	table.sort(rows, function(a, b)
		if a.duraPct ~= b.duraPct then return a.duraPct < b.duraPct end
		if (a.dura.bag ~= nil) ~= (b.dura.bag ~= nil) then return a.dura.bag == nil end
		return a.name < b.name
	end)
	if #rows > 0 then table.insert(rows, 1, TotalRow(rows)) end
	ns.RankInOrder(rows)
	list = rows
	return rows
end

--- The whole bill now: copper (nil when the game doesn't say), pieces damaged, the lowest worn piece's percent.
function DU.Total()
	if not list then DU.Collect() end
	local t = list and list[1]
	if not t or t.duraKind ~= "total" then return 0, 0, 100 end
	local damaged = 0
	for _, e in ipairs(list) do if e.duraKind ~= "total" and e.duraCur < e.duraMax then damaged = damaged + 1 end end
	return t.cost, damaged, t.duraPct
end

ns:RegisterProvider("durability", {
	label = L["Durability"],
	color = "ffb0a090", -- (worn leather)
	aliases = { "durability", "dura", "repaircost" },
	events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED" },
	guard = 1,
	-- (a search not naming it: the bill and what's damaged, not every piece at full next to its @gear row)
	plain = function(_, rows)
		local out = {}
		for _, e in ipairs(rows) do
			if (e.duraKind == "total" and e.cost) or (e.duraKind ~= "total" and e.duraCur < e.duraMax) then out[#out + 1] = e end
		end
		return out
	end,
	collect = function() return DU.Collect() end,
})

-- a repair vendor open: its "repair all" total kept for this character (what a client without the items' own figures
-- shows), read again as durability changes while it's open (0 after Repair All)
local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY" }) do pcall(ev.RegisterEvent, ev, e) end
function DU.OnMerchant()
	local key = MyKey()
	if not (ns.db and key and _G.CanMerchantRepair and Safe(_G.CanMerchantRepair)) then return end
	local cost = Num(Safe(_G.GetRepairAllCost))
	if not cost then return end
	if type(ns.db.repairVendor) ~= "table" or ns.db.repairVendor.cost then ns.db.repairVendor = {} end -- (0.50.3's first shape)
	-- what it asks against the game's own figures: the discount your reputation with its faction gives (0.50.3, the player:
	-- 3s 43c listed, the vendor asked 3s 9c: 10% off at honored). Kept until the next vendor says otherwise; a vendor
	-- with nothing to repair says nothing about it.
	local before = ns.db.repairVendor[key]
	local ratio = type(before) == "table" and before.ratio or nil
	local sum, known = 0, true
	for _, d in ipairs(DU.Read()) do
		if d.cur < d.max then
			if d.rawCost then sum = sum + d.rawCost else known = false end
		end
	end
	if known and sum > 0 and cost > 0 then
		local r = cost / sum
		if r >= 0.5 and r <= 1.001 then ratio = math.min(1, r) end
	end
	ns.db.repairVendor[key] = { cost = cost, at = _G.time and _G.time() or 0, ratio = ratio }
	ns:Changed("durability")
end
function DU.OnEvent(event)
	if event == "MERCHANT_SHOW" then atVendor = true; DU.OnMerchant()
	elseif event == "MERCHANT_CLOSED" then atVendor = false
	elseif atVendor then DU.OnMerchant() end
end
ev:SetScript("OnEvent", function(_, event) DU.OnEvent(event) end)
DU.frame = ev -- (tests)

----------------------------------------------------------------------
-- The question: "durability", "my durability", "repair cost", "repair bill", "how much to repair", "what needs repair",
-- "broken gear", "damaged items"
----------------------------------------------------------------------

local FILL = {}
for w in ([[my me i is are do does did what whats which how much many the a an of to for on all show list check see it its
	will would gear items item equipment armor armour stuff things need needs needed]]):gmatch("%a+") do FILL[w] = true end
local COST = { cost = true, costs = true, bill = true, price = true, much = true, pay = true }
local THINGS = { gear = true, item = true, items = true, equipment = true, armor = true, armour = true, stuff = true }

--- The question: { broken, damaged, words } or nil when the line isn't asking about durability. "repair" alone, "nearest
--- repair", "repair nearby" are the repair vendors' (an NPC's role), not this.
function DU.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local q = { words = {} }
	local strong, repair, cost, needs, state, things = false, false, false, false, false, false
	for w in t:gmatch("%S+") do
		if w == "bot" or w == "bots" or w == "kit" or w == "kits" then return nil end -- (Field Repair Bot, Armor Kit: items)
		if THINGS[w] then things = true end
		if w == "durability" or w == "dura" then strong = true
		elseif w == "repair" or w == "repairs" or w == "repairing" or w == "repaired" then repair = true
		elseif COST[w] then cost = true
		elseif w == "need" or w == "needs" or w == "needed" then needs = true
		elseif w == "broken" then q.broken, state = true, true
		elseif w == "damaged" then q.damaged, state = true, true
		elseif not FILL[w] then q.words[#q.words + 1] = w end
	end
	-- ("broken" alone, "broken bottle": a search; "broken gear", "damaged items": this)
	if not (strong or (repair and (cost or needs)) or (state and things)) then return nil end
	if repair and needs then q.damaged = true end
	-- (words naming none of your pieces: not this question; "durability frame", "who needs repair")
	if #q.words > 0 and #DU.Match(q) == 0 then return nil end
	return q
end

DU.NOTE = L["Durability"]

local NoteRow = ns.NoteRow

--- The rows the question keeps.
function DU.Match(q)
	local p = ns.providers.durability
	local all = p and ns:GetEntries(p) or {}
	local rows = {}
	for _, e in ipairs(all) do
		local ok = true
		if e.duraKind == "total" then ok = not q.broken and #q.words == 0
		else
			if q.broken and e.duraCur > 0 then ok = false end
			if q.damaged and e.duraCur >= e.duraMax then ok = false end
			local hay = ns.Lower(e.name) .. " " .. (e._ltext or "")
			for _, w in ipairs(q.words) do if ok and not hay:find(w, 1, true) then ok = false end end
		end
		if ok then rows[#rows + 1] = e end
	end
	return rows
end

function DU.Answer(q)
	q = q or {}
	local rows = DU.Match(q)
	ns.ScoreInOrder(rows)
	local cost, damaged = DU.Total()
	local note = DU.NOTE .. ns.DETAIL_SEP .. ((damaged == 0 and L["nothing to repair"])
		or (cost and L["repair all: %s"]:format(Money(cost))) or L["%d to repair"]:format(damaged))
	local items = 0
	for _, e in ipairs(rows) do if e.duraKind ~= "total" then items = items + 1 end end
	if items == 0 then
		local p = ns.providers.durability
		local any = p and #ns:GetEntries(p) > 0
		return { NoteRow((not any and L["Nothing wears down"]) or (q.broken and L["Nothing is broken"]) or L["Nothing to repair"]) }, note
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@durability is:broken legs".
function DU.ToAdvanced(q)
	local parts = { "@durability" }
	if q.broken then parts[#parts + 1] = "is:broken" elseif q.damaged then parts[#parts + 1] = "is:damaged" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

ns:RegisterCommand("durability", {
	desc = L["Your gear's durability and what repairing it costs"],
	aliases = { "dura", "repaircost" },
	run = function()
		DU.Collect()
		local lines = DU.Lines()
		if #lines == 0 then return { L["Nothing wears down"] } end
		table.insert(lines, 1, L["Durability:"])
		return lines
	end,
})

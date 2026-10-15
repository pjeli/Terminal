local ns = select(2, ...)

-- The selected row's tooltip (TerminalTooltip) beside the terminal: the entry's own drawing, its link or its tip
-- text; an item or spell the client hasn't loaded yet is drawn again once its data comes. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local L = ns.L

-- The terminal's own tooltip. GameTooltip would also pop up the game's "Equipped"
-- comparison tooltips for gear, and those land on top of the terminal (an upgrade's comparison is in this one:
-- Compare, below).
local tip
local function Tip()
	if not tip then
		tip = CreateFrame("GameTooltip", "TerminalTooltip", UIParent, "GameTooltipTemplate")
		tip.supportsItemComparison = false -- a finder shows the thing, not "if you replace this..."
		tip:SetFrameStrata("TOOLTIP")
		if ns.Zen then ns.Zen.Made(tip) end -- (made while .zen has the interface faded: kept up, Zen.lua)
	end
	return tip
end

-- the game's comparison tooltips: the tooltip's own list, else the global pair
local SHOPPING = { "ShoppingTooltip1", "ShoppingTooltip2" }
local function Shopping(t, i)
	local own = t.shoppingTooltips
	return own and own[i] or _G[SHOPPING[i]]
end
local function HideComparisons(t)
	for i = 1, 2 do
		local s = Shopping(t, i)
		if s and s.Hide then s:Hide() end
	end
end

-- An upgrade's comparison (0.52.3, the player's ask: "use the in-game comparison logic rather than our own"; 0.52.5:
-- in Terminal's own tooltip, not the game's "Equipped" tooltips beside it): what the game would compare the item with
-- (C_TooltipComparison.GetItemComparisonInfo: the piece you wear there; both rings, both trinkets; both hands for a
-- two-hander) and its stat changes as the game words them (GetItemComparisonDelta: "+5 Strength", "-4 Agility"), a
-- part for each piece, named. Whether it's an upgrade at all stays Terminal's (Upgrades.lua: your class's stats
-- weighed). Neither call is kept from addons, in combat or out, and nothing of the game's interface is shown.
local function ItemName(item)
	local key = item.guid or item.hyperlink
	local ok, name = pcall(C_Item.GetItemNameByID, key)
	if not ok or type(name) ~= "string" or ns.Secret(name) or name == "" then return nil end
	local okQ, q = pcall(C_Item.GetItemQualityByID, key)
	local hex = okQ and type(q) == "number" and ns.QualityHex and ns.QualityHex(q)
	return hex and ("|c" .. hex:gsub("^|c", "") .. name .. "|r") or name
end
--- The game's comparison of the item with what you wear, added to the tooltip (true), or nothing to add (false: the
--- calls missing, the item not one the game compares, nothing worn there).
local function Compare(t, link)
	local TC = C_TooltipComparison
	if not (TC and TC.GetItemComparisonInfo and TC.GetItemComparisonDelta) or type(link) ~= "string" then return false end
	local item = { hyperlink = link }
	local ok, info = pcall(TC.GetItemComparisonInfo, item)
	if not ok then return false end
	if type(info) ~= "table" or type(info.item) ~= "table" then return false, "nothing" end -- (nothing worn there)
	local M = Enum and Enum.TooltipComparisonMethod or {}
	local method = info.method or M.Single or 0
	local single = method == (M.Single or 0)
	local paired = method == (M.WithBagMainHandItem or 2) or method == (M.WithBagOffHandItem or 3)
	local more = type(info.additionalItems) == "table" and info.additionalItems[1] or nil
	-- (one piece; or two to choose from, each its own part: the rings; or a pair taken together: both hands)
	local pieces = { info.item }
	if single and more then pieces[2] = more end
	local any = false
	for _, worn in ipairs(pieces) do
		local okD, lines = pcall(TC.GetItemComparisonDelta, item, worn, (not single) and more or nil, paired)
		if okD and type(lines) == "table" and #lines > 0 then
			local name = ItemName(worn)
			local head = (not single and method == (M.WithBothHands or 1) and _G.ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION)
				or (name and L["Over %s:"]:format(name)) or _G.ITEM_DELTA_DESCRIPTION or "?"
			t:AddLine(" ")
			t:AddLine(head, 1, 0.82, 0, true)
			for _, l in ipairs(lines) do
				if type(l) == "string" and not ns.Secret(l) then t:AddLine(l, 1, 1, 1, true) end
			end
			any = true
		end
	end
	return any
end
UI._CompareTip = Compare -- (tests)

--- Is the item something worn (gear: its slot type, by the client's own item data)?
local function Wearable(id)
	id = tonumber(id)
	if not (id and C_Item and C_Item.GetItemInfoInstant) then return false end
	local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, id)
	return ok and type(loc) == "string" and loc ~= "" and loc ~= "INVTYPE_NON_EQUIP" and loc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

--- An item's link as the game names it, else "item:<id>" (the game takes either).
local function ItemLink(id)
	local ok, _, link = pcall(C_Item.GetItemInfo, id)
	return ok and type(link) == "string" and not ns.Secret(link) and link or ("item:" .. id)
end

-- Match the terminal: same background and border (light themes keep the game's dark tooltip,
-- since item text is drawn for a dark background).
local function StyleTip(t)
	local th = Theme.Get()
	local r, g, b, a = 0.06, 0.06, 0.1, 0.95
	local br, bg, bb = Theme.RGB(th.border)
	if not Theme.IsLight() then
		r, g, b = Theme.RGB(th.bg)
		a = math.max(0.92, th.bgAlpha)
	end
	local nine = t.NineSlice
	if type(nine) == "table" and nine.SetCenterColor then
		pcall(nine.SetCenterColor, nine, r, g, b, a)
		pcall(nine.SetBorderColor, nine, br, bg, bb, 1)
	elseif t.SetBackdropColor then
		pcall(t.SetBackdropColor, t, r, g, b, a)
		pcall(t.SetBackdropBorderColor, t, br, bg, bb, 1)
	end
end

--- Is there room for the tooltip right of the terminal? (Errors while the frame isn't placed yet: PlaceTip's pcall.)
local function RoomRight()
	local frame = UI.frame
	local scale = frame:GetEffectiveScale()
	local right = frame:GetRight() * scale
	local screen = UIParent:GetRight() * UIParent:GetEffectiveScale()
	return screen - right > 330 * UIParent:GetEffectiveScale()
end

-- Beside the terminal, on whichever side has room.
local function PlaceTip(t)
	local frame = UI.frame
	t:ClearAllPoints()
	local ok, roomRight = pcall(RoomRight)
	if ok and roomRight == false then
		t:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, 0)
	else
		t:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
	end
end

function UI:UpdateTooltip()
	local frame = UI.frame
	local t = Tip()
	local e = UI:IsShown() and UI.results[UI.sel] or nil
	-- the row menu is up: no tooltip (both sit beside the terminal, on top of each other)
	if UI:MenuShown() then e = nil end
	-- the same row still selected and its tooltip still up: nothing to redraw (only kept beside the
	-- terminal, which may have been dragged)
	if e and t.entry == e and t:IsShown() then PlaceTip(t) return end
	t:Hide()
	HideComparisons(t)
	t.entry = nil
	UI.StopTipWait(t) -- (another row, or none: the last one's item isn't waited on)
	if not e or e.noActivate then return end
	-- entries may supply a link directly, or a function that builds it only when selected
	local link = e.link
	if not link and e.getLink then
		local ok, l = pcall(e.getLink, e)
		link = ok and l or nil
	end
	-- never a profession ("trade") link: showing one opens that profession's window, as clicking it does
	if type(link) == "string" and link:find("|Htrade:", 1, true) then link = nil end
	UI.PrefetchTips() -- (the spells of the rows on screen asked for now: their tooltips are ready when you get to them)
	if not (link or e.tip or e.tooltip) then
		-- (0.46.15, the player: right after a /reload no talent showed a tooltip at all until the terminal was opened
		-- again: a spell the client hasn't loaded gives no link yet) asked for, and drawn once it's in
		UI.WaitForTipData(t, e, nil)
		return
	end
	t:SetOwner(frame, "ANCHOR_NONE")
	PlaceTip(t)
	local shown = false
	if e.tooltip then -- the entry draws its own (stored items: who has how many)
		shown = pcall(e.tooltip, e, t)
	end
	if link and not shown then
		shown = pcall(t.SetHyperlink, t, link)
	end
	if not shown and e.tip then
		t:SetText(e.name, 1, 1, 1)
		t:AddLine(e.tip, 0.8, 0.8, 0.8, true)
		shown = true
	end
	if shown then
		-- an upgrade the search weighed (0.51.14): said so, and the game's comparison beside it (Compare, above); a
		-- quest's: the reward that is one, compared. The item not loaded yet: waited for, then drawn again with it.
		local F = ns.Filters
		local cmpID, rewardName
		if F and F.UpgradeItem then cmpID, rewardName = F.UpgradeItem(e) end -- (both: "a and f()" keeps only the first)
		-- (a row of a search that weighed upgrades whose verdict a background search has since dropped (it judged the
		-- same row again: the item let go meanwhile, or found otherwise), still on screen till F5: compared all the
		-- same; 0.52.8, the player: "sometimes not showing the delta")
		if not cmpID and F and F.fitMade and not e.slotId and Wearable(e.itemID) then cmpID = tonumber(e.itemID) end
		local cmpLink
		if cmpID then
			cmpLink = (rewardName and ItemLink(cmpID)) or (type(link) == "string" and link:find("item:", 1, true) and link) or ItemLink(cmpID)
			-- (no "an upgrade" line: the list is of upgrades already; 0.52.6, the player. A quest: which reward it is)
			if rewardName then
				t:AddLine(" ")
				t:AddLine(ItemName({ hyperlink = cmpLink }) or rewardName, 1, 0.82, 0, true)
			end
			if not UI.ItemReady(cmpID) then
				if not rewardName then t:AddLine(" ") end
				t:AddLine(L["Comparing once the game has the item..."], 0.6, 0.6, 0.6, true)
			else
				local done, why = Compare(t, cmpLink)
				-- (nothing worn in its slot: the game has nothing to compare with; said, not left blank)
				if not done and why == "nothing" then
					t:AddLine(" ")
					t:AddLine(L["Nothing worn there to compare with"], 0.6, 0.6, 0.6, true)
				end
			end
		end
		t.entry = e
		t:Show()
		HideComparisons(t)
		StyleTip(t)
		UI.WaitForTipData(t, e, link, cmpID)
	end
end

-- An item the client hasn't loaded yet shows "Retrieving item information" and the tooltip never redraws itself (it
-- stayed so until you moved away and back). Its data arriving (GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT for that
-- id) redraws it; the server may drop an ask, so it's asked again every TIP_RETRY s, TIP_TRIES times. An item the
-- server says it doesn't have isn't asked for again for TIP_FAILED s (it answered at once, and every answer redrew
-- and asked again: an ask a few times a second while the row stayed selected).
-- A spell is the same (0.46.15, the player: another class's talent showed only "Improved Frostbolt  Passive" until
-- you moved away and back): its data or its text not in yet (C_Spell.IsSpellDataCached false, or an empty
-- C_Spell.GetSpellDescription) is asked for (RequestLoadSpellData) and the tooltip drawn again once it is
-- (SPELL_DATA_LOAD_RESULT / SPELL_TEXT_UPDATE for that spell, or the same retries).
UI.TIP_RETRY, UI.TIP_TRIES, UI.TIP_FAILED = 0.6, 8, 60
do
	local waiter, waitGen, listening = nil, 0, nil
	local failed, failedN = {}, 0 -- "kind:id" -> when the server said it has no such item or spell
	-- (these events fire for everything in the game: heard only while a tooltip waits on one, and only its kind's)
	local EVENTS = {
		item = { "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" },
		spell = { "SPELL_DATA_LOAD_RESULT", "SPELL_TEXT_UPDATE" },
	}
	local KIND_OF = {}
	for kind, list in pairs(EVENTS) do for _, ev in ipairs(list) do KIND_OF[ev] = kind end end
	local function Listen(kind) -- (nil: none)
		if not waiter or listening == kind then return end
		if listening then for _, ev in ipairs(EVENTS[listening]) do pcall(waiter.UnregisterEvent, waiter, ev) end end
		listening = kind
		if kind then for _, ev in ipairs(EVENTS[kind]) do pcall(waiter.RegisterEvent, waiter, ev) end end
	end
	--- What the tooltip shows that may still be loading: "item", id or "spell", id; nil for anything else. No link at
	--- all (a spell the client hasn't loaded gives none): the row's own spell.
	local function DataOfTip(e, link)
		local id = tonumber(e.itemID)
		if not id and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
		if id then return "item", id end
		if type(link) == "string" then
			id = tonumber(link:match("spell:(%d+)"))
			if id then return "spell", id end
		elseif link == nil then
			id = tonumber(e.spellID)
			if id then return "spell", id end
		end
	end
	local function ItemCached(id)
		local f = C_Item and C_Item.IsItemDataCachedByID
		if not f then return true end -- (no way to tell: nothing to wait for)
		local ok, yes = pcall(f, id)
		return not ok or yes ~= false
	end
	local function SpellLoaded(id)
		local S = C_Spell
		if not S then return true end
		if S.IsSpellDataCached then
			local ok, yes = pcall(S.IsSpellDataCached, id)
			if ok and yes == false then return false end
		end
		if S.GetSpellDescription then
			local ok, d = pcall(S.GetSpellDescription, id)
			if ok and not ns.Secret(d) and d == "" then return false end -- (its text: asked for along with its data)
		end
		return true
	end
	local function Loaded(kind, id) if kind == "spell" then return SpellLoaded(id) end return ItemCached(id) end
	local function Ask(kind, id)
		if kind == "spell" then
			if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
		elseif C_Item and C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, id)
		end
	end
	--- The tooltip drawn again for `e`: shown for it, or waited for with nothing to show yet (no link), while it's the
	--- row selected.
	local function Redraw(t, e)
		if not e then return false end
		if not (t.entry == e and t:IsShown()) and not (UI:IsShown() and UI.results[UI.sel] == e) then return false end
		t.entry = nil -- (the "same row, nothing to redraw" shortcut must not skip it)
		UI:UpdateTooltip()
		return true
	end
	local function Now() return GetTime and GetTime() or 0 end
	--- No tooltip waits on anything any more (the tooltip hidden): nothing heard.
	function UI.StopTipWait(t)
		if t then t.waitID, t.waitKind, t.waitFor = nil, nil, nil end
		Listen(nil)
	end

	local function OnEvent(_, event, got, ok)
		local tip = Tip()
		local kind = KIND_OF[event]
		local e = tip.waitFor
		if not (kind and got and tip.waitKind == kind and tip.waitID == got and e) then return end
		if ok == false then -- (the server has no such item or spell: nothing more to wait for)
			if failedN > 500 then failed, failedN = {}, 0 end
			local k = kind .. ":" .. got
			if not failed[k] then failedN = failedN + 1 end
			failed[k] = Now()
			UI.StopTipWait(tip)
			return
		end
		if not Loaded(kind, got) then return end -- (not in yet: the timer keeps watching)
		UI.StopTipWait(tip)
		Redraw(tip, e)
	end

	--- (the item an upgrade's comparison needs: loaded?)
	function UI.ItemReady(id) return ItemCached(id) end

	function UI.WaitForTipData(t, e, link, compareID)
		waitGen = waitGen + 1
		UI.StopTipWait(t)
		local kind, id = DataOfTip(e, link)
		-- (the row's own loaded, the item its comparison needs not: that one waited for; 0.52.3)
		if (not id or Loaded(kind, id)) and compareID and not ItemCached(compareID) then kind, id = "item", compareID end
		if not id or Loaded(kind, id) then return end
		if failed[kind .. ":" .. id] and Now() - failed[kind .. ":" .. id] < UI.TIP_FAILED then return end
		t.waitID, t.waitKind, t.waitFor = id, kind, e
		if not waiter then
			waiter = CreateFrame("Frame")
			UI.tipWaiter = waiter -- (tests)
			waiter:SetScript("OnEvent", OnEvent)
		end
		Listen(kind)
		Ask(kind, id)
		local gen, tries = waitGen, 0
		local function Again()
			if gen ~= waitGen or t.waitID ~= id then return end
			tries = tries + 1
			if Loaded(kind, id) then UI.StopTipWait(t) Redraw(t, e) return end
			if tries >= UI.TIP_TRIES then return end
			Ask(kind, id)
			C_Timer.After(UI.TIP_RETRY, Again)
		end
		C_Timer.After(UI.TIP_RETRY, Again)
	end
end

-- The rows on screen with a spell (spells, talents, other classes' too): each spell the client hasn't loaded is asked
-- for once, so its tooltip (link and text) is there by the time the row is selected.
UI.PREFETCH_MAX = 2000 -- spells asked for, remembered (then forgotten and asked again if still not loaded)
do
	local asked, n = {}, 0
	function UI.PrefetchTips()
		local S = C_Spell
		if not (S and S.IsSpellDataCached and S.RequestLoadSpellData) then return 0 end
		local rows = UI.results or {}
		local from = (UI.offset or 0) + 1
		local to = math.min(#rows, from + ((UI.layout and UI.layout.ROWS) or 10) - 1)
		local sent = 0
		for i = from, to do
			local e = rows[i]
			local id = type(e) == "table" and tonumber(e.spellID)
			if id and not asked[id] then
				if n >= UI.PREFETCH_MAX then asked, n = {}, 0 end
				asked[id], n = true, n + 1
				local ok, cached = pcall(S.IsSpellDataCached, id)
				if ok and cached == false then
					pcall(S.RequestLoadSpellData, id)
					sent = sent + 1
				end
			end
		end
		return sent
	end
end

--- The tooltip put away with the terminal (Hide, the frame's OnHide): hidden, nothing kept as shown.
function UI:HideTooltip()
	if tip then tip:Hide(); tip.entry = nil; HideComparisons(tip) end
	UI.StopTipWait(tip)
end

--- The tooltip drawn again the next time it's asked for (ApplyTheme: its colours changed).
function UI:ForgetTooltip()
	if tip then tip.entry = nil end
end

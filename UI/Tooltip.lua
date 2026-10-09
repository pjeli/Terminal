local ns = select(2, ...)

-- The selected row's tooltip (TerminalTooltip) beside the terminal: the entry's own drawing, its link or its tip
-- text; an item the client hasn't loaded yet is drawn again once its data comes. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme

-- The terminal's own tooltip. GameTooltip would also pop up the game's "Equipped"
-- comparison tooltips for gear, and those land on top of the terminal.
local tip
local function Tip()
	if not tip then
		tip = CreateFrame("GameTooltip", "TerminalTooltip", UIParent, "GameTooltipTemplate")
		tip.supportsItemComparison = false -- a finder shows the thing, not "if you replace this..."
		tip:SetFrameStrata("TOOLTIP")
	end
	return tip
end

-- the game's comparison tooltips: the tooltip's own list, else the global pair
local SHOPPING = { "ShoppingTooltip1", "ShoppingTooltip2" }
local function HideComparisons(t)
	local own = t.shoppingTooltips
	for i = 1, 2 do
		local s = own and own[i] or _G[SHOPPING[i]]
		if s and s.Hide then s:Hide() end
	end
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
	t.entry = nil
	if not e or e.noActivate then return end
	-- entries may supply a link directly, or a function that builds it only when selected
	local link = e.link
	if not link and e.getLink then
		local ok, l = pcall(e.getLink, e)
		link = ok and l or nil
	end
	-- never a profession ("trade") link: showing one opens that profession's window, as clicking it does
	if type(link) == "string" and link:find("|Htrade:", 1, true) then link = nil end
	if not (link or e.tip or e.tooltip) then return end
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
		t.entry = e
		t:Show()
		HideComparisons(t)
		StyleTip(t)
		UI.WaitForTipItem(t, e, link)
	end
end

-- An item the client hasn't loaded yet shows "Retrieving item information" and the tooltip never redraws itself (it
-- stayed so until you moved away and back). Its data arriving (GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT for that
-- id) redraws it; the server may drop an ask, so it's asked again every TIP_RETRY s, TIP_TRIES times. An item the
-- server says it doesn't have isn't asked for again for TIP_FAILED s (it answered at once, and every answer redrew
-- and asked again: an ask a few times a second while the row stayed selected).
UI.TIP_RETRY, UI.TIP_TRIES, UI.TIP_FAILED = 0.6, 8, 60
do
	local waiter, waitGen = nil, 0
	local failed, failedN = {}, 0 -- item id -> when the server said it has no such item
	local function ItemOfTip(e, link)
		local id = tonumber(e.itemID)
		if not id and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
		return id
	end
	local function Cached(id)
		local f = C_Item and C_Item.IsItemDataCachedByID
		if not f then return true end -- (no way to tell: nothing to wait for)
		local ok, yes = pcall(f, id)
		return not ok or yes ~= false
	end
	local function Redraw(t, e)
		if t.entry ~= e or not t:IsShown() then return false end
		t.entry = nil -- (the "same row, nothing to redraw" shortcut must not skip it)
		UI:UpdateTooltip()
		return true
	end
	local function Now() return GetTime and GetTime() or 0 end
	function UI.WaitForTipItem(t, e, link)
		waitGen = waitGen + 1
		t.waitID = nil
		local id = ItemOfTip(e, link)
		if not id or Cached(id) then return end
		if failed[id] and Now() - failed[id] < UI.TIP_FAILED then return end
		t.waitID = id
		if not waiter then
			waiter = CreateFrame("Frame")
			UI.tipWaiter = waiter -- (tests)
			pcall(waiter.RegisterEvent, waiter, "GET_ITEM_INFO_RECEIVED")
			pcall(waiter.RegisterEvent, waiter, "ITEM_DATA_LOAD_RESULT")
			waiter:SetScript("OnEvent", function(_, _, got, ok)
				local tip = Tip()
				if not (got and tip.waitID == got and tip.entry) then return end
				if ok == false then -- (the server has no such item: nothing more to wait for)
					if failedN > 500 then failed, failedN = {}, 0 end
					if not failed[got] then failedN = failedN + 1 end
					failed[got] = Now()
					tip.waitID = nil
					return
				end
				if not Cached(got) then return end -- (not in yet: the timer keeps watching)
				tip.waitID = nil
				Redraw(tip, tip.entry)
			end)
		end
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		local gen, tries = waitGen, 0
		local function Again()
			if gen ~= waitGen or t.waitID ~= id then return end
			tries = tries + 1
			if Cached(id) then t.waitID = nil Redraw(t, e) return end
			if tries >= UI.TIP_TRIES then return end
			if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			C_Timer.After(UI.TIP_RETRY, Again)
		end
		C_Timer.After(UI.TIP_RETRY, Again)
	end
end

--- The tooltip put away with the terminal (Hide, the frame's OnHide): hidden, nothing kept as shown.
function UI:HideTooltip()
	if tip then tip:Hide(); tip.entry = nil end
end

--- The tooltip drawn again the next time it's asked for (ApplyTheme: its colours changed).
function UI:ForgetTooltip()
	if tip then tip.entry = nil end
end

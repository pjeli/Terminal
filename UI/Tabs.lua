local ns = select(2, ...)
local L = ns.L

-- Tabs (0.53.5, the player's ask: several lists open at once, a shopping list, your route, upgrades; each
-- one a standing view, not a one-off search). Ctrl+T opens one, Ctrl+1-4 (or Ctrl+Tab / Ctrl+Shift+Tab) switch,
-- Ctrl+Shift+W closes one; a click on a tab switches, a right-click closes it. The strip shows over the prompt while
-- there are two or more.
--
-- A tab is what the prompt had (UI:SaveState's text, cursor, mode for this run, category, selected row), kept in
-- db.tabs so it's there after a /reload. The one shown keeps itself up to date: a list it shows that changes is
-- searched again in the background and, once the new rows are sure (Results.lua's Hold), they go up by themselves
-- (no F5). A tab you're not looking at isn't searched (no cost): it's searched afresh when you switch to it, and its
-- label gets a dot when a list it showed changed since. Opening the terminal brings back the tab you were on.

local UI, Theme = ns.UI, ns.Theme
local T = {}
ns.Tabs = T
T.MAX = 4

local run = setmetatable({}, { __mode = "k" }) -- tab -> { kinds = set, any = bool, at = Stamp() } (not saved)
local changed = {} -- provider id -> Stamp() when it last changed
local stamp = 0
local function Stamp() stamp = stamp + 1 return stamp end -- (in order, never two alike: a change and a look in one frame too)

local function DB()
	local db = ns.db
	if not db then return nil end
	local t = db.tabs
	if type(t) ~= "table" then
		t = { list = {}, cur = 1 }
		db.tabs = t
	end
	if type(t.list) ~= "table" then t.list = {} end
	local n = #t.list
	local cur = tonumber(t.cur) or 1
	t.cur = math.max(1, math.min(cur, math.max(1, n)))
	return t
end

function T.List() local t = DB() return t and t.list or {} end
--- Are there tabs (two or more: one alone is the plain prompt)?
function T.On() return #T.List() >= 2 end
function T.Cur() local t = DB() return t and t.cur or 1 end

--- A list changed (Core.lua's WarmLater, through ns.OnDirty): a tab not shown that had its rows gets a dot.
function T.Dirty(p)
	if p and p.id then changed[p.id] = Stamp() end
end

--- Has a list this tab showed changed since it was last looked at?
function T.Changed(tab)
	local r = tab and run[tab]
	if not r then return false end
	for id, at in pairs(changed) do
		if at > r.at and (r.any or r.kinds[id]) then return true end
	end
	return false
end

--- The prompt as it is now, as a tab (what's saved: text, cursor, the mode for this run, category, the selected row's
--- kind, key and name), and what it showed (not saved: the lists its rows came from).
local function Snapshot()
	local s = UI:SaveState()
	local tab = { text = s.text or "", cursor = s.cursor, category = s.category }
	if type(s.temp) == "table" then tab.temp = { from = s.temp.from, category = s.temp.category } end
	if s.tempSimple then tab.tempSimple = true end
	local sel = s.sel
	if type(sel) == "table" and type(sel.name) == "string" and (type(sel.key) == "string" or type(sel.key) == "number") then
		tab.sel = { kind = sel.kind, key = sel.key, name = sel.name }
	end
	local n, kinds, any = 0, {}, false
	for _, e in ipairs(UI.results) do
		if not (e.noActivate or e.lead) then
			n = n + 1
			local k = e.kind
			if type(k) == "string" and ns.providers[k] then kinds[k] = true else any = true end -- (a sum's rows: any list)
		end
	end
	tab.n = n
	run[tab] = { kinds = kinds, any = any, at = Stamp() }
	return tab
end

--- The tab shown kept as it is now (switching away, closing the terminal). Not pure fuzzy finding's (a run of its own,
--- over the tab: the tab stays as it was), nor the tour's.
function T.SaveCurrent()
	if not T.On() or not UI.edit then return end
	if UI.fzf or (ns.Tour and ns.Tour.Active and ns.Tour.Active()) then return end
	local t = DB()
	t.list[t.cur] = Snapshot()
end

--- The mode a tab was in for its run (Alt+`'s Advanced, fuzzy finding's Simple) over the mode you're in for good: only
--- what differs from it (switched for good since: nothing to bring back), as a quick reopen does.
local function SetMode(tab)
	local E = ns.Easy
	if not E then return end
	local simple = not (ns.db and ns.db.easyMode == false)
	E.temp, E.tempSimple = simple and tab.temp or nil, (not simple) and tab.tempSimple or nil
end

--- The prompt set to a tab, the terminal open (a switch): searched afresh, its row selected again.
local function Load(tab)
	tab = tab or {}
	UI:EndFuzzy()
	UI:Disarm()
	UI:HideRowMenu()
	SetMode(tab)
	UI.Forget(UI, true)
	UI.blockedSyntax, UI.sendTo, UI.action = nil, nil, nil
	UI.walks, UI.histIdx, UI.showRecent, UI.recalled = {}, nil, nil, nil
	UI.category, UI.categoryAuto = tab.category, nil
	UI.popTarget = tab.sel
	UI.refreshText = nil -- (another tab: not the same search again, whatever its text)
	local text = type(tab.text) == "string" and tab.text or ""
	UI:SetOrResearch(text)
	UI.cursor = math.max(0, math.min(type(tab.cursor) == "number" and tab.cursor or #text, #text))
	UI:UpdateCaret()
	UI:SetStatus()
	UI:UpdateGhost()
	run[tab] = run[tab] or { kinds = {}, any = false, at = Stamp() }
	run[tab].at = Stamp() -- (looked at: no dot)
end

--- Opening the terminal with tabs: the one you were on (UI:Open, when it opens with no text of its own). Its text, with
--- its mode set; UI:Open calls T.AfterOpen once it's open.
function T.ForOpen()
	if not T.On() then return nil end
	local tab = T.List()[T.Cur()] or {}
	SetMode(tab)
	return tab
end

function T.AfterOpen(tab)
	if tab.category then UI:SetCategory(tab.category) end
	if tab.sel then
		UI.popTarget = tab.sel
		UI:SelectPopTarget(not UI.searchJob)
		UI:Render()
	end
	local text = UI.edit:GetText()
	UI.cursor = math.max(0, math.min(type(tab.cursor) == "number" and tab.cursor or #text, #text))
	UI:UpdateCaret()
	if run[tab] then run[tab].at = Stamp() end
	T.Layout()
end

--- Says something in the chat window, once: "4 tabs at most" and the like.
local function Say(msg) ns:Print(msg) end

--- Ctrl+T: a new tab, empty, in the mode you're in for good; the prompt as it was is the tab before it.
function T.New()
	local t = DB()
	if not t or not UI:IsShown() then return false end
	if #t.list >= T.MAX then
		Say(L["%d tabs at most: Ctrl+Shift+W closes one"]:format(T.MAX))
		return false
	end
	if #t.list == 0 then t.list[1], t.cur = {}, 1 end -- (the prompt as it was: tab 1)
	t.list[t.cur] = Snapshot()
	local tab = { text = "" }
	t.list[#t.list + 1] = tab
	t.cur = #t.list
	ns:Trace(("tabs: tab %d opened"):format(t.cur))
	Load(tab)
	T.Layout()
	return true
end

--- Ctrl+1-4, a click: tab `i`. False when there's no such tab.
function T.Switch(i)
	local t = DB()
	if not (t and T.On() and UI:IsShown()) then return false end
	if type(i) ~= "number" or not t.list[i] then return false end
	if i == t.cur then return true end
	t.list[t.cur] = Snapshot()
	t.cur = i
	ns:Trace(("tabs: tab %d"):format(i))
	Load(t.list[i])
	T.Layout()
	return true
end

--- Ctrl+Tab / Ctrl+Shift+Tab: the next / previous tab, round.
function T.Step(dir)
	if not T.On() then return false end
	local n = #T.List()
	return T.Switch((T.Cur() - 1 + dir) % n + 1)
end

--- Ctrl+Shift+W, a right-click: tab `i` (the one shown, by default) closed. One left: no tabs, the plain prompt.
function T.Close(i)
	local t = DB()
	if not (t and T.On()) then return false end
	i = i or t.cur
	if not t.list[i] then return false end
	local shown = i == t.cur
	if shown then t.list[t.cur] = Snapshot() end -- (the others' numbers move; the one shown, as it is)
	table.remove(t.list, i)
	if i < t.cur or (shown and t.cur > #t.list) then t.cur = t.cur - 1 end
	t.cur = math.max(1, math.min(t.cur, #t.list))
	ns:Trace(("tabs: tab %d closed"):format(i))
	local tab = t.list[t.cur]
	if #t.list < 2 then t.list, t.cur = {}, 1 end -- (one left: the plain prompt, as it was)
	if shown and UI:IsShown() then Load(tab) end
	T.Layout()
	return true
end

----------------------------------------------------------------------
-- The strip: a label per tab over the prompt ("1  linen cloth  12"), the one shown in the text colour with the accent
-- under it, the others dim; a dot after one whose lists changed since you looked.
----------------------------------------------------------------------

local strip

local function Build()
	if strip or not UI.frame then return strip end
	strip = CreateFrame("Frame", nil, UI.frame)
	strip.buttons = {}
	for i = 1, T.MAX do
		local b = CreateFrame("Button", nil, strip)
		b.text = b:CreateFontString(nil, "OVERLAY")
		b.text:SetFontObject(Theme.fonts.small)
		b.text:SetPoint("LEFT", 8, 1)
		b.text:SetPoint("RIGHT", -6, 1)
		b.text:SetJustifyH("LEFT")
		b.text:SetWordWrap(false)
		b.line = b:CreateTexture(nil, "ARTWORK")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 4, 0)
		b.line:SetPoint("BOTTOMRIGHT", -4, 0)
		if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
		b:SetScript("OnClick", function(_, button)
			if UI.closing then return end
			if button == "RightButton" then T.Close(i) else T.Switch(i) end
		end)
		b:Hide()
		strip.buttons[i] = b
	end
	T.strip = strip
	return strip
end

--- How tall the strip is (0: hidden), for the header (List.lua's HeaderH, UI.lua's prompt).
function T.Height()
	if not T.On() then return 0 end
	return math.max(18, (Theme.Get().fontSize or 14) + 8)
end

--- What a tab's label says: its number, its text (or "new tab"), how many it listed.
local function Label(i, tab, shown)
	local t = Theme.Get()
	local text = shown and UI.edit:GetText() or tab.text
	text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
	local n = shown and nil or tab.n
	if shown then
		n = 0
		for _, e in ipairs(UI.results) do if not (e.noActivate or e.lead) then n = n + 1 end end
	end
	local name = text ~= "" and text:gsub("|", "||") or L["new tab"]
	local out = "|cff" .. t.dim .. i .. "|r  " .. (shown and "|cff" .. t.text or "|cff" .. t.dim) .. name .. "|r"
	if type(n) == "number" and n > 0 and text ~= "" then out = out .. "  |cff" .. t.dim .. n .. "|r" end
	if not shown and T.Changed(tab) then out = out .. " |cff" .. t.accent .. "•|r" end
	return out
end

--- The strip drawn for the tabs as they are (and the header made room for it, or given back).
function T.Layout()
	if not UI.frame then return end
	local h = T.Height()
	if h ~= (UI.tabsH or 0) then
		UI.tabsH = h
		UI:ApplyTheme() -- (the prompt moves down under the strip, or back up)
	end
	T.Draw()
end

function T.Draw()
	local s = Build()
	if not s then return end
	local on = T.On()
	s:SetShown(on)
	if not on then return end
	local t = Theme.Get()
	local classic = t.frame == "classic"
	local pin = classic and 5 or 2
	local h = T.Height()
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", pin + 4, -pin)
	s:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -pin - 4, -pin)
	s:SetHeight(h)
	local list, cur = T.List(), T.Cur()
	local w = ((t.width or 600) - 2 * (pin + 4)) / math.max(1, #list)
	local ar, ag, ab = Theme.RGB(t.accent)
	for i, b in ipairs(s.buttons) do
		local tab = list[i]
		if tab then
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", s, "TOPLEFT", (i - 1) * w, 0)
			b:SetSize(w, h)
			local label = Theme.FixColors(Label(i, tab, i == cur))
			if b.label ~= label then b.label = label; b.text:SetText(label) end
			b.line:SetColorTexture(ar, ag, ab, i == cur and 0.9 or 0)
			b:Show()
		else
			b:Hide()
		end
	end
end

----------------------------------------------------------------------
-- Keys (Keys.lua): Ctrl+T, Ctrl+1-4, Ctrl+Tab, Ctrl+Shift+W. True when the key was a tab's.
----------------------------------------------------------------------
function T.Key(key, shift)
	if key == "T" then T.New() return true end
	local n = type(key) == "string" and tonumber(key:match("^([1-9])$"))
	if n then
		if n <= T.MAX then T.Switch(n) end
		return true
	end
	if key == "TAB" and T.On() then T.Step(shift and -1 or 1) return true end
	if key == "W" and shift and T.On() then T.Close() return true end
	return false
end

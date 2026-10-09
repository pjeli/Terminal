local T = ...
-- The window split into files (UI.lua, Prompt, Completion, List, Tooltip, Motion, Activate, Keys, RowMenu, Results,
-- Modes): what they reach each other through, and the frame's OnHide before anything but the frame exists
local ns, UI, check = T.ns, T.UI, T.check

do -- the helpers and constants one UI file gives the others (captured at load, or read by UI.lua's frame scripts)
	UI:Open(""); T.FlushAll()
	for _, name in ipairs({ "EasyOn", "Wake", "Style", "PrevPos", "NextPos", "Forget", "PlaceRow", "HideNav", "CursorStyle",
		"SecureView", "ClickFor", "FinishClicked", "KeysDown", "LegacyDown", "StopRepeat", "ListKey", "TickKey",
		"HideTooltip", "ForgetTooltip", "ForgetCompletion", "Results", "Selected" }) do
		check(type(UI[name]) == "function", "UI." .. name .. " is there for the other UI files")
	end
	for _, name in ipairs({ "MAX_ROWS", "FOOTER_H", "BUSY_DOTS", "TAB_LATE", "SLICE_MS", "SLICE_CHECK" }) do
		check(type(UI[name]) == "number", "UI." .. name .. " is published")
	end
	check(type(UI.ONCE_LABEL) == "string", "UI.ONCE_LABEL is published")
	local L = UI.layout
	check(type(L) == "table" and type(L.ROWS) == "number" and type(L.ROW_H) == "number" and type(L.HEADER_H) == "number"
		and type(L.LINE_H) == "number", "the layout numbers are one table, UI.layout")
	check(UI.frame == _G.TerminalFrame and UI.measure and UI.divider and UI.selEdge and UI.footLine and UI.edit and UI.caret
		and UI.hit and UI.busy and UI.ghost and UI.selBar and UI.promptBg and UI.status and UI.hints, "the widgets are published on UI")
	check(type(UI.rows) == "table" and #UI.rows == UI.MAX_ROWS and UI.motion and UI._repeat, "the row frames, the motion loop, the key repeat")
	check(UI.Results() == UI.results and UI.Selected() == UI.sel, "UI.Results() and UI.Selected() give the fields")
	UI:Hide(); T.FlushAll()
end

do -- the frame's OnHide when only the frame exists (in the game, BuildFrame's frame:Hide() fires it on the first open)
	UI:Open(""); UI:Hide(); T.FlushAll()
	local F = _G.TerminalFrame
	local names = { "edit", "caret", "caretChar", "hit", "busy", "syntax", "selText", "ghost", "selBar", "selEdge", "divider",
		"promptBg", "measure", "footLine", "status", "hints", "promptFS" }
	local saved = {}
	for _, n in ipairs(names) do saved[n] = UI[n]; UI[n] = nil end
	local ok, err = pcall(F.scripts.OnHide, F)
	for _, n in ipairs(names) do UI[n] = saved[n] end
	check(ok, "OnHide runs with only the frame made: " .. tostring(err))
	T.FlushAll()
	-- Easy's Alt+` for this run and fuzzy finding end in it too, whichever file holds them
	UI:Open(""); T.FlushAll()
	UI:FuzzyOnce(); T.FlushAll()
	check(UI.fzf, "fuzzy finding on")
	for _, n in ipairs(names) do saved[n] = UI[n] end
	UI.caret, UI.caretChar, UI.hit = nil, nil, nil
	ok, err = pcall(F.scripts.OnHide, F)
	UI.caret, UI.caretChar, UI.hit = saved.caret, saved.caretChar, saved.hit
	check(ok and not UI.fzf, "OnHide ends fuzzy finding: " .. tostring(err))
	UI:Hide(); T.FlushAll()
end

do -- the layout numbers follow the theme in every file: none keeps a copy taken at load
	local Th = ns.Theme
	local rowsWas = Th.Get().rows
	Th.Set("rows", 4)
	check(UI.layout.ROWS == 4, "rows 4: the layout says 4: " .. tostring(UI.layout.ROWS))
	UI:Open("@panel"); T.FlushAll()
	local shown = 0
	for _, r in ipairs(UI.rows) do if r:IsShown() then shown = shown + 1 end end
	check(#UI.Results() > 8 and shown == 4, "Render draws four rows: " .. shown .. " of " .. #UI.Results())
	T.key("PAGEDOWN")
	check(UI.Selected() == 5 and UI.offset == 1, "PageDown moves a page of four: " .. UI.Selected() .. " / " .. UI.offset)
	UI:Scroll(-1)
	check(UI.offset == 4 and UI.Selected() > UI.offset and UI.Selected() <= UI.offset + 4,
		"the wheel scrolls three and keeps the selection on screen: " .. UI.offset .. " / " .. UI.Selected())
	UI:Hide(); T.FlushAll()
	Th.Set("rows", rowsWas)
	check(UI.layout.ROWS == rowsWas, "and back")
end

do -- ">>> party": the rows to send are grouped once per list (CollapseGroup), not again on every status update
	local SH = ns.Share
	local wasEasy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("@panel >>> party"); T.FlushAll()
	local total = #SH.GroupRows(UI.groupList or {})
	local foot = UI.status:GetText() or ""
	check(total > 2 and foot:find("Enter sends all " .. total .. " to party", 1, true), "footer: how many go where: " .. foot)
	local calls, base, pre, prefetched = 0, SH.GroupRows, SH.Prefetch, nil
	SH.GroupRows = function(...) calls = calls + 1 return base(...) end
	SH.Prefetch = function(rows, grouped) prefetched = { rows = rows, grouped = grouped } return pre(rows, grouped) end
	for _ = 1, 5 do UI:SetStatus() end
	UI:SelectionChanged()
	check(calls == 0, "status updates group nothing again: " .. calls .. " GroupRows calls")
	check(prefetched and prefetched.grouped and #prefetched.rows == total, "Prefetch gets the grouped rows, said grouped")
	check((UI.status:GetText() or "") == foot, "the footer says the same: " .. tostring(UI.status:GetText()))
	-- typing on: the new list is grouped once, as it's collapsed
	calls = 0
	UI:SetQuery("@panel >>> party ", 17); T.FlushAll()
	check(calls == 1, "the next list: grouped once: " .. calls)
	-- a pick list after the channel (no grouped list): the footer still counts what's shown
	SH.GroupRows, SH.Prefetch = base, pre
	UI:SetQuery("@panel >>> party q:", 19); T.FlushAll()
	check(UI.groupList == nil and UI.groupRows == nil, "a pick list: nothing grouped kept")
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = wasEasy; UI:EasyChanged()
end

do -- Share.Prefetch: an item asked for isn't asked again for a minute, and the ids asked long ago aren't all kept
	local SH = ns.Share
	local saved = { cached = C_Item.IsItemDataCachedByID, req = C_Item.RequestLoadItemDataByID, time = _G.GetTime }
	local now, asks = 5000, {}
	_G.GetTime = function() return now end
	C_Item.IsItemDataCachedByID = function() return false end
	C_Item.RequestLoadItemDataByID = function(id) asks[#asks + 1] = id end
	local function Items(from, n)
		local rows = {}
		for i = 1, n do local id = from + i; rows[i] = { kind = "item", key = id, itemID = id, name = "Item " .. id } end
		return rows
	end
	-- a list of 100 unloaded items every 12 seconds for 10 minutes: 5000 different ids
	for round = 1, 50 do
		SH.Prefetch(Items(900000 + round * 1000, 100))
		now = now + 12
	end
	check(#asks == 5000, "every item asked for once: " .. #asks)
	local kept = SH.AskedCount and SH.AskedCount() or 1e9
	check(kept < 1500, "the ids asked over a minute ago aren't all kept: " .. kept)
	-- forgetting them changes nothing: asked under a minute ago, not again; over a minute ago, asked again
	asks = {}
	check(SH.Prefetch(Items(900000 + 50 * 1000, 100)) == 0 and #asks == 0, "asked 12 s ago: not asked again")
	check(SH.Prefetch(Items(900000 + 1 * 1000, 100)) == 100, "asked 10 minutes ago: asked again")
	C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, _G.GetTime = saved.cached, saved.req, saved.time
end

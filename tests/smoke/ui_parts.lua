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

do -- the frame's OnHide when only the frame exists (BuildFrame's first frame:Hide() fired it on the first open; since
	-- 0.44.10 the frame is hidden before its scripts are set, but the handler stays safe that early)
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

do -- every result sent while the search still goes on over frames: finished first (all of them go), or, when that would
	-- take long, nothing sent yet (0.44.16; only its first frame's rows went)
	local SH = ns.Share
	local wasEasy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	local big = {}
	for i = 1, 3000 do big[i] = { key = i, name = ("Pebble %04d%s"):format(i, i % 150 == 0 and " glint" or "") } end
	ns:RegisterProvider("bigsend", { label = "Big", aliases = { "bigsend" }, explicit = true, collect = function() return big end })
	ns:GetEntries(ns.providers.bigsend)
	local realClock, ms = _G.debugprofilestop, 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end -- every look at the clock: 1 ms
	local realSend, got = SH.SendAll, nil
	SH.SendAll = function(list) got = #SH.GroupRows(list) return got end
	local budget = UI.SEND_FINISH_MS
	UI.SEND_FINISH_MS = 1e9
	UI:Open("@bigsend glint >>> party")
	local early = #SH.GroupRows(UI.groupList or {})
	check(UI.searchJob and early < 20, "(the search still going: " .. early .. " so far)")
	T.key("ENTER")
	check(got == 20 and not UI:IsShown(), ">>> while the search still goes on: finished first, all 20 go: " .. tostring(got))
	T.FlushAll()
	-- the row menu's "All N": counted and sent from the whole search too
	UI:Open("@bigsend glint")
	check(UI.searchJob ~= nil, "(the search still going)")
	UI:ShowRowMenu(1)
	local menu = _G.TerminalRowMenu
	local all
	for _, b in ipairs(menu.lines or {}) do
		local it = b:IsShown() and b.item
		if it and (it.label or ""):find("^All ") then all = all or it end
	end
	check(all and all.label:find("^All 20 to "), "the menu's All line counts every result: " .. tostring(all and all.label))
	got = nil
	if all and all.run then all.run() end
	-- (say, yell: one line the game presses, with every result counted: Share.PressLine, 0.45.16)
	local line = all and all.chatTo and all.chatTo.all and SH.ChatLine(nil, all.chatTo)
	check(got == 20 or (line and line:find("^/s ") and line:find("Pebble 1800 glint %+8 more$")), "and sends every one: " .. tostring(got or line))
	UI:HideRowMenu(); UI:Hide(); T.FlushAll()
	-- too long to finish now: nothing sent, it says to press again
	UI.SEND_FINISH_MS = 0
	got = nil
	local printed, pr = {}, ns.Print
	ns.Print = function(_, m) printed[#printed + 1] = m end
	UI:Open("@bigsend glint >>> party")
	T.key("ENTER")
	check(got == nil and printed[1] == UI.STILL_SEARCHING and UI:IsShown(), "too long to finish now: nothing sent, says so: " .. tostring(printed[1]))
	ns.Print = pr
	UI:Hide(); T.FlushAll()
	UI.SEND_FINISH_MS, SH.SendAll, _G.debugprofilestop = budget, realSend, realClock
	ns.providers.bigsend = nil
	for i, id in ipairs(ns.providerOrder) do if id == "bigsend" then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()
	ns.db.easyMode = wasEasy; UI:EasyChanged()
end

do -- a click on a wrapped prompt's second line puts the cursor there (0.44.16: GetCursorPosition's y was dropped by an
	-- `and`, so every click landed on the first line)
	local mx, my = 0, 0
	local savedPos = _G.GetCursorPosition
	_G.GetCursorPosition = function() return mx, my end
	UI:Open("")
	UI:SetQuery(("word "):rep(30)) -- (150 letters: wraps)
	local edit = UI.edit
	local sv = { left = rawget(edit, "GetLeft"), scale = rawget(edit, "GetEffectiveScale"), center = rawget(edit, "GetCenter") }
	edit.GetLeft = function() return 100 end
	edit.GetEffectiveScale = function() return 1 end
	edit.GetCenter = function() return 300, 500 end
	local lines = UI:PromptLines()
	check(#lines >= 2, "(the prompt wraps: " .. #lines .. " lines)")
	mx, my = 100 + 7 * 3, 500 - UI.layout.LINE_H -- (a line down, three letters in)
	local H = UI.hit
	H.scripts.OnMouseDown(H, "LeftButton"); H.scripts.OnMouseUp(H, "LeftButton")
	check(lines[2] and UI.cursor >= lines[2][1] - 1 and UI.cursor <= lines[2][2], "a click on the second line puts the cursor on it: "
		.. tostring(UI.cursor) .. " (line 2: " .. tostring(lines[2] and lines[2][1]) .. "-" .. tostring(lines[2] and lines[2][2]) .. ")")
	rawset(edit, "GetLeft", sv.left); rawset(edit, "GetEffectiveScale", sv.scale); rawset(edit, "GetCenter", sv.center)
	_G.GetCursorPosition = savedPos
	UI:Hide(); T.FlushAll()
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

-- (0.45.18, the player's screenshot) a row saying how far: the distance in a column of its own after the arrow's slot,
-- the same place on every row; the arrow sits there; rows without one as before
io.write("[the distance column, the arrow beside it]\n")
do
	local I = ns.Integrations
	local was = { here = I.Here, dist = I.NpcDistance, facing = I.Facing, bearing = I.Bearing, rowDist = I.RowDistance }
	I.RowDistance = function() return 480, { cont = 1, x = 480, y = 0 } end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	local D = { [9001] = 133, [9002] = 2221, [9003] = 50 }
	I.NpcDistance = function(id) local d = D[id] return d, d and { cont = 1, x = d, y = 0 } or nil end
	I.Facing = function() return 0 end
	I.Bearing = function() return 0.5 end
	local list = {
		setmetatable({ detail = "133 yd  Teaches it  ·  Expert Blacksmith", _dist = 133 }, { __index = { kind = "npc", key = 9001, name = "Traugh" } }),
		setmetatable({ detail = "2221 yd  Teaches it", _dist = 2221 }, { __index = { kind = "npc", key = 9002, name = "Dwukk" } }),
		{ kind = "npc", key = 9003, name = "Plain", detail = "Banker" },
		setmetatable({ detail = "Lv 18-30  ·  fits", _dist = 500 }, { __index = { kind = "dungeon", key = 1, name = "Zone", wcont = 1, wx = 0, wy = 0 } }),
	}
	UI:Open("zzqqxxyy"); T.FlushAll()
	UI.results, UI.sel, UI.offset = list, 1, 0
	UI:Render(); UI:SelectionChanged()
	local r1, r2, r3, r4 = UI.rows[1], UI.rows[2], UI.rows[3], UI.rows[4]
	check(r1.dist:IsShown() and r1.dist:GetText() == "133 yd" and r1.detail:GetText() == "Teaches it  ·  Expert Blacksmith"
		and r2.dist:GetText() == "2221 yd" and r2.detail:GetText() == "Teaches it", "how far, in its column; what it is after it: " .. tostring(r1.dist:GetText()))
	check(r1.dist.lastPoint and r2.dist.lastPoint and r1.dist.lastPoint[4] == r2.dist.lastPoint[4] and r1.dist.lastPoint[2] == r1.kind,
		"every row's distance in the same column")
	check(not r3.dist:IsShown() and r3.detail:GetText() == "Banker" and not r4.dist:IsShown() and r4.detail:GetText() == "Lv 18-30  ·  fits",
		"rows that don't say how far (a zone answer's distance is only its order): as before")
	check(UI.navArrow and UI.navArrow:IsShown() and UI.navArrow.lastPoint and UI.navArrow.lastPoint[2] == r1.dist, "the arrow: in the slot before the distance")
	UI.sel = 2; UI:SelectionChanged()
	check(UI.navArrow.lastPoint[2] == r2.dist, "the next row's arrow: the same place")
	-- walking: the distance keeps up, in its column
	D[9002] = 2000
	UI.sel = 1; UI:SelectionChanged(); UI.sel = 2; UI:SelectionChanged()
	check(r2.dist:GetText() == "2000 yd" and list[2].detail == "2000 yd  Teaches it" and r2.detail:GetText() == "Teaches it", "walking: the distance keeps up: " .. tostring(r2.dist:GetText()))
	-- a row that doesn't say how far: the arrow just left of its text, never further than its room
	UI.sel = 3; UI:SelectionChanged()
	check(UI.navArrow.lastPoint and UI.navArrow.lastPoint[2] == r3.detail, "a plain NPC row: the arrow by its text")
	-- a dungeon in "what dungeon should i do": its distance is its order, its detail its levels: kept as it is
	UI.sel = 4; UI:SelectionChanged()
	check(UI.navArrow:IsShown() and list[4].detail == "Lv 18-30  ·  fits" and r4.detail:GetText() == "Lv 18-30  ·  fits",
		"a row whose distance is only its order: its detail isn't rewritten as you walk: " .. tostring(list[4].detail))
	local L = UI.layout
	list[3].detail = string.rep("long title ", 30)
	UI:Render(); UI.sel = 2; UI:SelectionChanged(); UI.sel = 3; UI:SelectionChanged()
	check(UI.navArrow.lastPoint[4] == -(r3.detail:GetWidth() + 4), "a text cut off: the arrow at the start of what shows, not past it: " .. tostring(UI.navArrow.lastPoint[4]))
	check(r1.label.lastPoint and r1.label.lastPoint[2] == r1.kind and r1.label.lastPoint[4] == -(16 + L.DETAIL_W),
		"the name ends where the detail's room begins (never under a distance)")
	UI:Hide(); T.FlushAll()
	I.Here, I.NpcDistance, I.Facing, I.Bearing, I.RowDistance = was.here, was.dist, was.facing, was.bearing, was.rowDist
end

-- (0.45.19, the player) the game's own keys for things that don't touch Terminal stay the game's while it's open:
-- Ctrl+R (the frame rate), Ctrl+S (sound), Ctrl+M (music), Alt+Enter (windowed)...; Terminal's own chords stay its own
io.write("[the game's keys that stay the game's]\n")
do
	local F = UI.frame
	local was = { action = _G.GetBindingAction, ctrl = _G.IsControlKeyDown, alt = _G.IsAltKeyDown }
	local B = { ["CTRL-R"] = "TOGGLEFPS", ["CTRL-S"] = "TOGGLESOUND", ["CTRL-M"] = "TOGGLEMUSIC", ["ALT-ENTER"] = "TOGGLEWINDOWED",
		["CTRL-F"] = "TARGETFOCUS", ["CTRL-A"] = "TOGGLEFPS", ["R"] = "TOGGLEFPS", ["CTRL-ENTER"] = "TOGGLEFPS" }
	_G.GetBindingAction = function(c) return B[c] or "" end
	UI:Open(""); T.FlushAll()
	_G.IsControlKeyDown = function() return true end
	T.key("R")
	check(F.propagate == true and T.query() == "", "Ctrl+R: the game's (the frame rate), nothing typed")
	T.key("S"); local s1 = F.propagate
	T.key("M"); local m1 = F.propagate
	check(s1 == true and m1 == true, "Ctrl+S, Ctrl+M: sound, music")
	T.key("F")
	check(F.propagate == false, "Ctrl+F bound to something that acts (targeting): Terminal keeps it")
	T.key("A")
	check(F.propagate == false, "Ctrl+A: Terminal's own (select all), whatever the game binds it to")
	_G.IsControlKeyDown = was.ctrl
	T.key("R", "r")
	check(T.query() == "r" and F.propagate == false, "a plain R types, even bound to something that would pass")
	_G.IsAltKeyDown = function() return true end
	local shownWas = UI:IsShown()
	T.key("ENTER")
	check(F.propagate == true and shownWas and UI:IsShown(), "Alt+Enter: the game's windowed toggle, no result run")
	_G.IsAltKeyDown = was.alt
	_G.IsControlKeyDown = function() return true end
	check(UI.GameKey("ENTER") == false, "Ctrl+Enter: Terminal's own (stays open)")
	_G.IsControlKeyDown = was.ctrl
	_G.GetBindingAction = was.action
	UI:Hide(); T.FlushAll()
end

-- (0.45.19, the player) dragging the terminal: it snaps to a grid, its middle onto the screen's; lines show the
-- middles while dragging (the one it sits on lit); Shift: no snapping
io.write("[dragging the terminal: grid and middles]\n")
do
	local l, t, onX, onY = UI.SnapPosition(595, 457, 400, 100, 1600, 900, false)
	check(l == 600 and t == 450 and onX and onY, "near the middles: exactly on them: " .. l .. "," .. t)
	l, t, onX, onY = UI.SnapPosition(103, 700, 400, 100, 1600, 900, false)
	check(l == 96 and t == 706 and not onX and not onY, "elsewhere: on the grid (its lines run through the middles): " .. l .. "," .. t)
	l, t = UI.SnapPosition(103, 700, 400, 100, 1600, 900, true)
	check(l == 103 and t == 700, "Shift: where it was dragged")
	l, t = UI.SnapPosition(-50, 2000, 400, 100, 1600, 900, false)
	check(l == 0 and t == 900, "kept on the screen: " .. l .. "," .. t)

	local F = UI.frame
	local was = { point = ns.db.point, cur = _G.GetCursorPosition, left = F.GetLeft, top = F.GetTop, fs = F.GetEffectiveScale,
		us = UIParent.GetEffectiveScale, uw = UIParent.w, uh = UIParent.h, w = F.w, h = F.h, shift = _G.IsShiftKeyDown }
	local px, py = 200, 550
	_G.GetCursorPosition = function() return px, py end
	F.GetLeft, F.GetTop = function() return 100 end, function() return 600 end
	F.GetEffectiveScale, UIParent.GetEffectiveScale = function() return 1 end, function() return 1 end
	UIParent.w, UIParent.h = 1600, 900
	UI:Open(""); T.FlushAll()
	F.w, F.h = 400, 100
	F.scripts.OnDragStart(F)
	local g = UI.guides
	check(g and g:IsShown() and g.midX and g.midY, "dragging: the lines show")
	px, py = 705, 553 -- (its middle 5 short of the screen's)
	UI:DragTick()
	check(F.lastPoint and F.lastPoint[4] == 600 and F.lastPoint[5] == 610 and g.midX.alpha == 1 and g.midY.alpha ~= 1,
		"its middle onto the screen's (that line lit), its top on the grid: " .. tostring(F.lastPoint and F.lastPoint[4]) .. "," .. tostring(F.lastPoint and F.lastPoint[5]))
	_G.IsShiftKeyDown = function() return true end
	px, py = 711, 553
	UI:DragTick()
	check(F.lastPoint[4] == 611 and F.lastPoint[5] == 603 and g.midX.alpha ~= 1, "Shift held: no snapping: " .. tostring(F.lastPoint[4]))
	_G.IsShiftKeyDown = was.shift
	px, py = 705, 553
	F.scripts.OnDragStop(F)
	check(not g:IsShown() and ns.db.point and ns.db.point[1] == "TOPLEFT" and ns.db.point[3] == 600 and ns.db.point[4] == 610,
		"let go: the lines go, the snapped place is kept")
	-- closed while dragged: the lines go
	F.scripts.OnDragStart(F)
	UI:Hide(); T.FlushAll()
	if F.scripts.OnHide then F.scripts.OnHide(F) end
	check(not g:IsShown() and UI.drag == nil, "closed while dragged: the lines go")
	ns.db.point, _G.GetCursorPosition, F.GetLeft, F.GetTop, F.GetEffectiveScale = was.point, was.cur, was.left, was.top, was.fs
	UIParent.GetEffectiveScale, UIParent.w, UIParent.h, F.w, F.h = was.us, was.uw, was.uh, was.w, was.h
end

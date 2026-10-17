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
	UI:SetQuery("@item >>> party q:", 18); T.FlushAll() -- (q: judges items: "@panel q:" offers nothing since 0.47.7)
	check(UI.Results()[1] and UI.Results()[1].syntaxRow, "the pick list shows")
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
	UI:ShowRowMenu(1, false, true) -- (the send button's menu: its All lines, 0.55.12)
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
	check(ns.Zen.Kept(g), "the lines keep their own alpha: .zen's fade leaves them up (0.46.11)")
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
	-- (0.50.7, review) another screen size: the same frame, its lines re-placed (a new frame each time piled up)
	local lines = #g.lines
	UIParent.w, UIParent.h = 1920, 1080
	UI:Open(""); T.FlushAll()
	F.scripts.OnDragStart(F)
	check(UI.guides == g and g.key:find("1920", 1, true), "a new screen size: the same guides frame, re-laid: " .. tostring(UI.guides == g))
	UIParent.w, UIParent.h = 1600, 900
	F.scripts.OnDragStop(F)
	F.scripts.OnDragStart(F)
	local shown = 0
	for _, t in ipairs(g.lines) do if t:IsShown() then shown = shown + 1 end end
	check(#g.lines >= lines and shown == lines, "back to the smaller screen: its lines, the rest hidden: " .. shown .. "/" .. lines)
	F.scripts.OnDragStop(F)
	UI:Hide(); T.FlushAll()
	ns.db.point, _G.GetCursorPosition, F.GetLeft, F.GetTop, F.GetEffectiveScale = was.point, was.cur, was.left, was.top, was.fs
	UIParent.GetEffectiveScale, UIParent.w, UIParent.h, F.w, F.h = was.us, was.uw, was.uh, was.w, was.h
end

do -- combat (0.46.14, the player's ask): open as a fight starts, the terminal goes at once (.zen: the interface back at
	-- once) and comes back as it was once the fight is over; opened by hand during the fight: as it was, nothing later
	local S, Zen, P = ns.Secure, ns.Zen, _G.UIParent
	local icl, focusWas, alphaWas = _G.InCombatLockdown, _G.GetCurrentKeyBoardFocus, P:GetAlpha()
	local fighting, focus = false, nil
	_G.InCombatLockdown = function() return fighting end
	_G.GetCurrentKeyBoardFocus = function() return focus end
	local F = UI.frame
	local function Fight() fighting = true; S.OnCombat() end
	local function Over() fighting = false; S.OnRegen() end
	UI:Open("e"); T.FlushAll()
	check(#UI.results >= 2, "(a search with rows to pick from: " .. #UI.results .. ")")
	UI:Move(1)
	local picked = UI.results[UI.sel]
	UI.cursor = 0; UI:UpdateCaret()
	Fight()
	check(not UI:IsShown() and not F:IsShown() and not UI.closing and F.kb == false and UI.combatState,
		"a fight starts: the terminal gone at once (no closing animation), the keyboard let go, what it showed kept")
	T.FlushAll()
	check(not UI:IsShown(), "it stays closed while the fight goes on")
	Over(); T.FlushAll()
	check(UI:IsShown() and T.query() == "e" and UI.cursor == 0 and UI.results[UI.sel] == picked and UI.keys == true
		and UI.combatState == nil, "the fight is over: back as it was (text, cursor, the row picked), reading keys")
	UI:Hide(); T.FlushAll()
	-- closed when the fight starts: nothing comes back
	Fight(); Over(); T.FlushAll()
	check(not UI:IsShown(), "closed as the fight started: it stays closed")
	-- Down's recent picks on the empty prompt come back too (UI:SaveState, also F1's)
	UI:Open(""); UI.showRecent = true; UI:Research(); T.FlushAll()
	Fight(); Over(); T.FlushAll()
	check(UI:IsShown() and UI.showRecent == true, "the recent picks Down brought up come back")
	UI:Hide(); T.FlushAll()
	UI:Open("e"); UI.recalled = "e"; T.FlushAll() -- (Simple mode's last search, brought back by Down: Up puts it away)
	Fight(); Over(); T.FlushAll()
	check(UI:IsShown() and UI.recalled == "e", "the search Down brought back is still Down's (Up puts it away)")
	UI:Hide(); T.FlushAll()
	-- opened by hand during the fight (`): as it was; nothing comes back later
	UI:Open("e"); T.FlushAll()
	Fight()
	UI:Toggle(); T.FlushAll()
	check(UI:IsShown() and T.query() == "e" and UI.combatState == nil and UI.keys == false,
		"` during the fight: back as it was (the game's text box: combat)")
	UI:Hide(); T.FlushAll()
	Over(); T.FlushAll()
	check(not UI:IsShown(), "closed again during the fight: it stays closed after")
	-- opened another way during the fight (Alt+`, a link): afresh, and nothing comes back later
	UI:Open("e"); T.FlushAll()
	Fight()
	UI:Open("hearth"); UI:Hide(); T.FlushAll()
	Over(); T.FlushAll()
	check(not UI:IsShown() and UI.combatState == nil, "opened another way during the fight: the kept state is dropped")
	-- the chat box being typed in as the fight ends: back once it lets go; a new fight meanwhile keeps it
	UI:Open("e"); T.FlushAll()
	Fight()
	local chat = CreateFrame("EditBox")
	focus = chat
	Over(); T.Flush()
	check(not UI:IsShown() and UI.combatState, "over, the chat box being typed in: not yet")
	Fight() -- (fighting again; the terminal isn't open, nothing to keep anew)
	focus = nil
	T.Flush(); T.Flush()
	check(not UI:IsShown() and UI.combatState, "a new fight before it came back: still waiting, for that one's end")
	Over(); T.FlushAll()
	check(UI:IsShown() and T.query() == "e", "that fight over, the keyboard free: back")
	UI:Hide(); T.FlushAll()
	UI:Open("e"); T.FlushAll()
	Fight()
	focus = chat
	Over()
	focus = nil
	T.Flush(); T.Flush()
	check(UI:IsShown() and T.query() == "e", "the chat box let go: back")
	UI:Hide(); T.FlushAll()
	UI:Open("e"); T.FlushAll()
	Fight()
	focus = chat
	Over(); T.FlushAll()
	check(not UI:IsShown() and UI.combatState == nil, "the chat box kept the keyboard: given up, the terminal stays closed")
	-- one of Terminal's apps opened meanwhile (in the terminal's place): it stays
	UI:Open("e"); T.FlushAll()
	Fight()
	focus = chat
	Over()
	local apps, appShown = ns.Panel.Registered(), true
	apps[#apps + 1] = { IsShown = function() return appShown end, Close = function() appShown = false end }
	focus = nil
	T.Flush(); T.Flush()
	check(not UI:IsShown() and UI.combatState == nil, "an app opened before it came back: the terminal stays closed")
	table.remove(apps)
	-- .zen: the interface back at once as the fight starts, faded again when the terminal comes back
	local animWas = ns.Theme.Animation
	ns.Theme.Animation = function() return nil end -- (fades at once: the alpha tells the steps apart)
	P:SetAlpha(0.9)
	ns.db.zen = true
	UI:Open("e"); T.FlushAll()
	check(Zen.active and P:GetAlpha() == 0, "(.zen: faded)")
	ns.Theme.Animation = animWas
	Fight()
	check(not UI:IsShown() and not Zen.active and math.abs(P:GetAlpha() - 0.9) < 1e-9, ".zen: the fight starts, the interface is back at once")
	F.scripts.OnHide(F); T.FlushAll() -- (the game fires OnHide)
	check(not Zen.active and math.abs(P:GetAlpha() - 0.9) < 1e-9, ".zen: and stays back during the fight")
	Over()
	check(UI:IsShown() and Zen.active, ".zen: the terminal back after the fight, the interface fading again")
	UI:HideNow(); F.scripts.OnHide(F); T.FlushAll()
	Zen.Leave(true)
	ns.db.zen = nil
	P:SetAlpha(alphaWas)
	_G.InCombatLockdown, _G.GetCurrentKeyBoardFocus = icl, focusWas
end


io.write("[review 0.48.6: the window's state]\n")
do
	local SH = ns.Share
	local wasEasy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	local function Drop(id)
		ns.providers[id] = nil
		for i, x in ipairs(ns.providerOrder) do if x == id then table.remove(ns.providerOrder, i) break end end
		ns:AliasesChanged()
	end
	-- (the mock's rows have no position: the catcher lies over a row only where it can say where the row is)
	for _, r in ipairs(UI.rows) do
		r.GetLeft, r.GetBottom, r.GetEffectiveScale = function() return 100 end, function() return 300 end, function() return 1 end
	end
	-- ">> party": hovering rows works out no chat line (an NPC's line sets its map pin to link it); the click does
	local OWN = { macro = "/targetexact Orc Innkeeper" }
	local npcs = { { key = 1, npcID = 1, name = "Orc Innkeeper One", secure = OWN, isOpen = ns.Never },
		{ key = 2, npcID = 2, name = "Orc Innkeeper Two" }, { key = 3, npcID = 3, name = "Orc Innkeeper Three" } }
	ns:RegisterProvider("zzrev", { label = "Rev", aliases = { "zzrev" }, explicit = true, collect = function() return npcs end })
	local I = ns.Integrations
	local basePin, pins = I.NpcPinLink, 0
	I.NpcPinLink = function() pins = pins + 1; return "[pin]" end
	UI:Open("@zzrev orc >> party"); T.FlushAll()
	UI.rows[1].scripts.OnEnter(UI.rows[1])
	UI.rows[2].scripts.OnEnter(UI.rows[2])
	local c = UI.catcher
	check(pins == 0 and c and c.attrs.macrotext1 == "", ">> party: hovering two rows sets no pin: " .. pins)
	c.scripts.PreClick(c, "LeftButton")
	check(pins == 1 and (c.attrs.macrotext1 or ""):find("^/p "), "the click works its line out (one pin): " .. tostring(c.attrs.macrotext1))
	-- the row menu's first lines are the row's own action, not the send
	pins = 0
	UI:ShowRowMenu(1)
	local first = _G.TerminalRowMenu.lines[1]
	local own
	for _, b in ipairs(_G.TerminalRowMenu.lines) do
		if b:IsShown() and b.attrs and b.attrs.macrotext1 == OWN.macro then own = true end
	end
	check(pins == 0 and not ((first.attrs and first.attrs.macrotext1) or ""):find("/p ", 1, true) and own,
		">> party: the menu's first line is the row's own action, nothing worked out to send: " .. tostring(first.attrs and first.attrs.macrotext1))
	UI:HideRowMenu(); UI:Hide(); T.FlushAll()
	I.NpcPinLink = basePin
	Drop("zzrev")
	-- a click finishes as Enter does: a press that asks for more stays open; Ctrl on a no-window press keeps it open
	local never = ns.Never
	local rows2 = { { key = "a", name = "Ask zz", secure = { macro = "/who zz" }, isOpen = never, staysOpen = true, kind = "who" },
		{ key = "b", name = "Toy zz", secure = { macro = "/use item:1" }, isOpen = never } }
	ns:RegisterProvider("zzrev2", { label = "Rev2", aliases = { "zzrev2" }, explicit = true, collect = function() return rows2 end })
	local function ClickRow(name, ctrl)
		UI:Open("@zzrev2 zz"); T.FlushAll()
		local at
		for i, r in ipairs(UI.Results()) do if r.name == name then at = i end end
		UI.rows[at].scripts.OnEnter(UI.rows[at])
		local cc = UI.catcher
		local function go() cc.scripts.PostClick(cc, "LeftButton") end
		if ctrl then T.withCtrl(go) else go() end
		local shown = UI:IsShown()
		UI:Hide(); T.FlushAll()
		return shown, cc
	end
	check(ClickRow("Ask zz") == true, "a click on a row that asks for more (@who's): the terminal stays open")
	local shownToy, cc = ClickRow("Toy zz", true)
	check(shownToy == true and cc.attrs["ctrl-macrotext1"] == "/use item:1", "Ctrl+click on a no-window press: stays open; ctrl- set")
	check(ClickRow("Toy zz") == false, "a plain click on it: closes")
	Drop("zzrev2")
	-- the footer's notes (gold) are made readable on a light theme whatever else it says
	do
		local light = ns.Theme.IsLight
		ns.Theme.IsLight = function() return true end
		UI.flightNote, UI.mode = "zz note", "search"
		UI.results = { { name = "x", key = 1 } }
		UI:SetStatus()
		local txt = UI.status.text or ""
		UI.flightNote = nil
		ns.Theme.IsLight = light
		check(txt:find("zz note", 1, true) and not txt:find("|cffffd200zz note", 1, true), "a light theme: the footer's note made readable: " .. txt)
		UI.results = {}
	end
	-- the same text searched again (a list finished loading): the selection stays; the menu's "Write" writes its own row
	local loading = true
	local many = {}
	for i = 1, 8 do many[i] = { key = i, name = "Pebble " .. i } end
	ns:RegisterProvider("zzrev3", { label = "Rev3", aliases = { "zzrev3" }, explicit = true, collect = function() return many end,
		busy = function() return loading and "loading pebbles" or nil end })
	UI:Open("@zzrev3 pebble"); T.FlushAll()
	UI:UpdateBusy()
	UI:Move(4)
	local before = UI.Results()[UI.sel]
	loading = false
	UI:UpdateBusy(); T.FlushAll()
	check(UI.Results()[UI.sel] == before or (UI.Results()[UI.sel] and before and UI.Results()[UI.sel].name == before.name),
		"a list finished loading: the selected row stays selected: " .. tostring(UI.Results()[UI.sel] and UI.Results()[UI.sel].name))
	UI:Move(-10); UI:Move(2)
	local menuOn = UI.Results()[UI.sel]
	UI:ShowRowMenu(UI.sel)
	local write
	for _, b in ipairs(_G.TerminalRowMenu.lines) do if b:IsShown() and b.item and b.item.label == ns.L["Write into the prompt"] then write = b end end
	UI:Move(2) -- (the selection moves under the open menu)
	if write then write.scripts.PostClick(write) end
	check(menuOn and T.query():find(menuOn.name, 1, true), "the menu's Write: its own row: " .. T.query())
	UI:HideRowMenu(); UI:Hide(); T.FlushAll()
	-- (0.50.7, review) a row to select again, left from a search stopped by closing: not jumped to on the next open
	UI:Open("@zzrev3 pebble"); T.FlushAll()
	UI.popTarget = UI.Results()[5]
	UI:Hide(); T.FlushAll()
	UI:Open("@zzrev3 pebble"); T.FlushAll()
	check(UI.sel == 1, "opened again: the top row selected, not one from before: " .. UI.sel)
	UI:Hide(); T.FlushAll()
	-- (0.50.7, review) the list rebuilt under the open menu (new tables, the same rows): still its own row
	UI:Open("@zzrev3 pebble"); T.FlushAll()
	UI:Move(-10); UI:Move(2)
	menuOn = UI.Results()[UI.sel]
	UI:ShowRowMenu(UI.sel)
	write = nil
	for _, b in ipairs(_G.TerminalRowMenu.lines) do if b:IsShown() and b.item and b.item.label == ns.L["Write into the prompt"] then write = b end end
	local rebuilt = {}
	for i = #UI.results, 1, -1 do
		local r = {}
		for k, v in pairs(UI.results[i]) do r[k] = v end
		rebuilt[#rebuilt + 1] = r
	end
	UI.results = rebuilt
	if write then write.scripts.PostClick(write) end
	check(menuOn and T.query():find(menuOn.name .. " ", 1, true), "rebuilt under the menu: Write still writes its own row: " .. T.query())
	UI:HideRowMenu(); UI:Hide(); T.FlushAll()
	-- the mouse wheel moving the selection off an armed row disarms it, as the arrows do
	local lots = {}
	for i = 1, 40 do lots[i] = { key = i, name = "Gravel " .. i } end
	ns:RegisterProvider("zzrev5", { label = "Rev5", aliases = { "zzrev5" }, explicit = true, collect = function() return lots end })
	UI:Open("@zzrev5 gravel"); T.FlushAll()
	UI.armedEntry = UI.Results()[1]; ns.Secure.armed = "MACRO"
	UI:Scroll(-3)
	check(UI.sel > 1 and UI.armedEntry == nil, "the wheel moved the selection: disarmed: " .. UI.sel)
	UI:Hide(); T.FlushAll()
	Drop("zzrev5")
	-- fuzzy finding's way back (F1, a fight) in the game's frame (GetTime the same all frame): the row comes back
	ns:RegisterProvider("zzrev4", { label = "Rev4", aliases = { "zzrev4" }, collect = function() return many end })
	UI:FuzzyOnce("pebble"); T.FlushAll()
	UI:Move(3)
	local fzBefore = UI.Results()[UI.sel]
	local st = UI:SaveState()
	UI:HideNow(); T.FlushAll()
	local realTime = _G.GetTime
	local frozen = realTime()
	_G.GetTime = function() return frozen end
	UI:RestoreState(st)
	_G.GetTime = realTime
	T.FlushAll()
	check(fzBefore and UI.Results()[UI.sel] and UI.Results()[UI.sel].name == fzBefore.name,
		"fuzzy finding restored: its row selected again: " .. tostring(UI.Results()[UI.sel] and UI.Results()[UI.sel].name))
	UI:HideNow(); T.FlushAll()
	Drop("zzrev3"); Drop("zzrev4")
	-- ">>> say" while the search still goes on: finished first, every result in the line; an armed row's search goes on
	local big = {}
	for i = 1, 3000 do big[i] = { key = i, name = ("Stone %04d%s"):format(i, i % 150 == 0 and " glint" or "") } end
	ns:RegisterProvider("zzbig", { label = "Big", aliases = { "zzbig" }, explicit = true, collect = function() return big end })
	local realClock, ms = _G.debugprofilestop, 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	UI:Open("@zzbig glint >>> say")
	local going = UI.searchJob ~= nil
	local finishWas = UI.SEND_FINISH_MS
	UI.SEND_FINISH_MS = 1e9 -- (the counting clock: give it all the "time" it needs)
	T.key("ENTER")
	UI.SEND_FINISH_MS = finishWas
	local proxy = _G.TerminalMacroProxy
	local line = proxy and proxy.attrs and proxy.attrs.macrotext or ""
	local n = 0
	for _ in line:gmatch("glint") do n = n + 1 end
	local more = tonumber(line:match("%+(%d+)")) or 0 -- (one line of 255 characters: the rest counted, "+7 more")
	check(going and n + more == 20 and n > 2, ">>> say mid-search: finished first, all 20 in the line or counted: " .. n .. " + " .. more)
	UI:Disarm(); UI:Hide(); T.FlushAll()
	UI:Open("@zzbig glint")
	going = UI.searchJob ~= nil
	UI.armedEntry = UI.Results()[1]; ns.Secure.armed = "MACRO"
	T.FlushAll()
	_G.debugprofilestop = realClock
	check(going and #UI.Results() == 20, "a row armed while the search goes on: it still finishes: " .. #UI.Results())
	UI:Disarm(); UI:Hide(); T.FlushAll()
	Drop("zzbig")
	-- ">> party": the hints say Enter sends it (not the row's own verb); the armed line too; ">> drop": Terminal asks
	ns:RegisterProvider("zzrev6", { label = "Rev6", aliases = { "zzrev6" }, explicit = true, collect = function() return many end })
	UI:Open("@zzrev6 pebble >> party"); T.FlushAll()
	local hints = UI.hints:GetText() or ""
	check(hints:find(ns.L["send it to %s"]:format(UI.sendTo.label), 1, true) and not hints:find("open", 1, true),
		">> party: the hints say Enter sends it: " .. hints)
	local sv = UI.SecureView(UI.Results()[1], false)
	UI.armedEntry = sv; UI:SetStatus()
	check((UI.status:GetText() or ""):find(ns.L["send it to %s"]:format(UI.sendTo.label), 1, true), "armed: \"Press Enter to send it to ...\": " .. tostring(UI.status:GetText()))
	UI.armedEntry = nil
	UI:SetQuery("@zzrev6 pebble >> drop")
	check((UI.status:GetText() or ""):find("Terminal asks first", 1, true), ">> drop: Terminal asks first: " .. tostring(UI.status:GetText()))
	-- the footer's colours fixed for light themes always (the flight and recipe notes' gold included)
	local fixed = 0
	local fixWas = ns.Theme.FixColors
	ns.Theme.FixColors = function(x) fixed = fixed + 1 return fixWas(x) end
	UI:SetQuery("@zzrev6 pebble"); UI:SetStatus()
	ns.Theme.FixColors = fixWas
	check(fixed > 0, "a plain footer goes through FixColors too")
	UI:Hide(); T.FlushAll()
	Drop("zzrev6")
	-- a Mac's Cmd+V: Ctrl+V's (the paste), never a typed "v" and the plain box for the session
	local metaWas = _G.IsMetaKeyDown
	_G.IsMetaKeyDown = function() return true end
	local checkedWas = UI.charChecked
	UI.charChecked = nil
	UI:Open(""); T.FlushAll()
	T.key("V")
	_G.IsMetaKeyDown = metaWas
	T.FlushAll()
	check(not UI.noChar and not T.query():find("v", 1, true), "Cmd+V first: no stray \"v\", key capture kept: " .. T.query())
	UI.charChecked = checkedWas
	UI:Hide(); T.FlushAll()
	-- the slim copy bar where the terminal sits, at its scale
	local t = ns.Theme.Get()
	local scaleWas, pointWas = t.scale, ns.db.point
	t.scale, ns.db.point = 1.3, { "TOPLEFT", "TOPLEFT", 200, -150 }
	ns:ShowText("Link", "https://example.org/x", { compact = true })
	local bar = _G.TerminalLinkFrame
	check(bar and bar.scale == 1.3, "the copy bar takes the terminal's scale: " .. tostring(bar and bar.scale))
	if bar then bar:Hide() end
	t.scale, ns.db.point = scaleWas, pointWas
	for _, r in ipairs(UI.rows) do r.GetLeft, r.GetBottom, r.GetEffectiveScale = nil, nil, nil end
	ns.db.easyMode = wasEasy; UI:EasyChanged()
end

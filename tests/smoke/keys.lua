local T = ...
-- The keys (0.45.20): the keys window (F1, .keybinds) and the keys made alike in every mode
local ns, UI, check, key, query, withCtrl = T.ns, T.UI, T.check, T.key, T.query, T.withCtrl
local K = ns.KeysWindow
local E = ns.Easy

local function withShift(fn) local s = _G.IsShiftKeyDown; _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = s end
local function Find(rows, k) for _, r in ipairs(rows) do if r.key == k then return r end end end
local function WKey(k) local f = K.frame; f.scripts.OnKeyDown(f, k) end

io.write("[keys window: one list, three modes]\n")
do
	for _, m in ipairs(K.MODES) do
		local rows = K.Rows(m)
		check(rows[1] and rows[1].title, m .. ": starts with a section title")
		local empty = false
		for i, r in ipairs(rows) do
			if r.title and (not rows[i + 1] or rows[i + 1].title) then empty = true end
		end
		check(not empty, m .. ": no section without keys")
		for _, k in ipairs({ "Enter", "Shift+Enter", "Up / Down", "Tab", "Shift+Tab", "F1", "` or Esc", "Ctrl+Home / End", "Ctrl+W", "Ctrl+U" }) do
			check(Find(rows, k), m .. " lists " .. k)
		end
	end
	local s, a, f = K.Rows("simple"), K.Rows("advanced"), K.Rows("fuzzy")
	check(Find(s, "Shift+Right").text:find("menu", 1, true) and Find(a, "Shift+Right").text:find("write the result", 1, true)
		and Find(f, "Shift+Right").text:find("its name", 1, true), "Shift+Right: Simple's menu, Advanced's write it, fuzzy finding's name")
	check(Find(f, "Enter").text:find("Simple mode", 1, true) and Find(f, "Shift+Enter").text:find("Advanced", 1, true),
		"fuzzy finding: Enter to Simple, Shift+Enter to Advanced")
	check(not Find(f, "Shift+Left") and not Find(f, "Ctrl+Enter") and not Find(f, "."), "fuzzy finding: no back, no Ctrl+Enter, no commands")
	check(not Find(s, "@kind") and not Find(s, ">> party") and Find(a, "@kind") and Find(a, ">> party"), "Advanced's syntax only in Advanced")
	check(not Find(a, "Alt+`") and Find(s, "Alt+`") and Find(f, "Alt+`"), "Alt+`: Simple's and fuzzy finding's (Advanced: it closes, as `)")
	-- highlighted: a mode's own way only
	check(not Find(s, "Up / Down").own and not Find(a, "Up / Down").own and not Find(f, "Up / Down").own, "keys alike everywhere aren't highlighted")
	check(Find(f, "Enter").own and not Find(s, "Enter").own and not Find(a, "Enter").own, "fuzzy finding's Enter is its own; the others' aren't")
	check(Find(a, "@kind").own and Find(s, "Shift+Left").own and not Find(a, "Shift+Left").own, "a line for one mode, or a mode's own text, is highlighted")
	-- every line is for some mode; F1 is the key the terminal reads
	for _, line in ipairs(K.LINES) do
		if not K.IsTitle(line) then
			local any = false
			for _, m in ipairs(K.MODES) do if K.TextFor(line, m) then any = true end end
			check(any, "\"" .. tostring(line[1]) .. "\" is shown in some mode")
		end
	end
	check(Find(s, UI.HELP_KEY) ~= nil, "the window lists the key the terminal opens it with")
end

io.write("[keys window: F1 opens it on the mode in use; Esc brings the terminal back as it was]\n")
do
	local was = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); T.FlushAll()
	UI:SetQuery("a"); T.FlushAll()
	local n = #UI.Results()
	check(n >= 2, "(several results for a: " .. n .. ")")
	UI:Move(1)
	local picked = UI.Results()[UI.Selected()]
	K.flipAt = nil
	key("F1")
	check(K.IsShown() and not UI:IsShown() and K.Mode() == "advanced", "Advanced: F1 opens the keys on Advanced's tab: " .. tostring(K.Mode()))
	check(K.frame.propagate == nil or true, "(opened)")
	local scroll, content, pool, tabs, footer, legend = K.Parts()
	check(K.shown and K.shown > 10 and pool[1].row and pool[1].row.title, "its rows are drawn, a section title first")
	check((legend:GetText() or ""):find("Advanced's own", 1, true), "the legend names the tab's mode: " .. tostring(legend:GetText()))
	check((footer:GetText() or ""):find("Esc / F1", 1, true), "the footer says Esc / F1 go back")
	-- tabs: Tab / Shift+Tab, Left / Right, 1-3, a click
	WKey("TAB"); check(K.Mode() == "fuzzy" and K.frame.propagate == false, "Tab: the next tab (kept, not the game's)")
	WKey("TAB"); check(K.Mode() == "simple", "round to the first")
	withShift(function() WKey("TAB") end); check(K.Mode() == "fuzzy", "Shift+Tab: the previous")
	WKey("LEFT"); check(K.Mode() == "advanced", "Left: the previous")
	WKey("RIGHT"); check(K.Mode() == "fuzzy", "Right: the next")
	WKey("1"); check(K.Mode() == "simple", "1: Simple")
	tabs[2].scripts.OnClick(tabs[2]); check(K.Mode() == "advanced", "a click on a tab shows it")
	-- scrolling
	scroll.h = 100
	K.ScrollTo(0)
	WKey("DOWN"); check(K.Offset() == 36, "Down scrolls: " .. K.Offset())
	WKey("END"); check(K.Offset() == content.h - 100 and K.Offset() > 36, "End: the bottom")
	WKey("DOWN"); check(K.Offset() == content.h - 100, "not past it")
	WKey("HOME"); check(K.Offset() == 0, "Home: the top")
	K.frame.scripts.OnMouseWheel(K.frame, -1); check(K.Offset() == 36, "the wheel scrolls")
	WKey("3"); check(K.Offset() == 0, "another tab starts at its top")
	WKey("W"); check(K.frame.propagate == true and K.IsShown(), "other keys go on to the game")
	-- Esc: back to the terminal as it was
	WKey("ESCAPE")
	check(not K.IsShown() and UI:IsShown() and query() == "a", "Esc: back to the terminal, the search as it was: " .. query())
	check(not E.On() and not UI.fzf, "in Advanced mode")
	check(UI.Results()[UI.Selected()] and UI.Results()[UI.Selected()].name == picked.name, "the row picked selected again")
	-- F1's own repeats right after: not a second press (Esc and Shift+Left always count)
	key("F1"); check(not K.IsShown() and UI:IsShown(), "F1 held: its repeats don't flip the window back")
	K.flipAt = nil
	key("F1"); check(K.IsShown(), "F1 again opens it")
	K.flipAt = nil
	WKey("F1"); check(not K.IsShown() and UI:IsShown() and query() == "a", "F1 in it goes back too")
	-- Shift+Left: back, and its held key doesn't go back a step in the terminal as well
	K.flipAt = nil
	key("F1")
	withShift(function() WKey("LEFT") end)
	check(not K.IsShown() and UI:IsShown() and UI.backHeld ~= nil, "Shift+Left: back, the held key marked")
	UI.backHeld = nil
	-- ` closes everything
	K.flipAt = nil
	key("F1"); WKey("`")
	check(not K.IsShown() and not UI:IsShown(), "` closes it (and the terminal stays closed)")
	ns.db.easyMode = was; UI:EasyChanged()
end

do -- the mode of this run comes back: Alt+`'s Advanced, fuzzy finding, Simple mode's category
	local was = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); T.FlushAll()
	UI:SetQuery("hearthstone"); T.FlushAll()
	UI:AdvancedOnce(); T.FlushAll()
	local adv = query()
	K.flipAt = nil
	key("F1")
	check(K.IsShown() and K.Mode() == "advanced", "Alt+`'s Advanced run: the Advanced tab")
	WKey("ESCAPE"); T.FlushAll()
	check(UI:IsShown() and E.temp ~= nil and not E.On() and query() == adv, "back in Advanced for this run, the text as it was: " .. query())
	UI:Hide(); T.FlushAll()
	check(E.temp == nil and E.On(), "(Simple again once closed)")
	-- fuzzy finding
	UI:FuzzyOnce("hearth"); T.FlushAll()
	K.flipAt = nil
	key("F1")
	check(K.IsShown() and K.Mode() == "fuzzy", "fuzzy finding: its tab")
	WKey("ESCAPE"); T.FlushAll()
	check(UI:IsShown() and UI.fzf and query() == "hearth", "back in fuzzy finding: " .. query())
	UI:Hide(); T.FlushAll()
	-- Simple mode, a category picked
	UI:Open(""); T.FlushAll()
	UI:SetQuery("hearth"); T.FlushAll()
	UI:SetCategory("bags"); T.FlushAll()
	K.flipAt = nil
	key("F1")
	check(K.IsShown() and K.Mode() == "simple", "Simple mode: its tab")
	WKey("ESCAPE"); T.FlushAll()
	check(UI:IsShown() and UI.category == "bags" and not UI.categoryAuto and query() == "hearth", "back in the category picked (not just opened for you): " .. tostring(UI.category))
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = was; UI:EasyChanged()
end

do -- .keybinds, the real text box's F1, combat, and an update's new file not loaded yet
	local c = ns.commands.keybinds
	check(c and ns:FindCommand("keys") == c and ns:FindCommand("shortcuts") == c and ns:FindCommand("hotkeys") == c, ".keybinds, .keys, .shortcuts, .hotkeys")
	c.run("fu")
	check(K.IsShown() and K.Mode() == "fuzzy", ".keybinds fu: fuzzy finding's tab")
	K.Close()
	c.run("")
	check(K.IsShown() and K.Mode() == K.ModeNow(), ".keybinds: the tab of the mode in use")
	WKey("ESCAPE"); T.FlushAll()
	check(UI:IsShown() and query() == "", "Esc after .keybinds: the terminal, an empty prompt")
	-- the game's own text box (after Ctrl+C, in combat) has F1 too
	UI:EnterEdit()
	K.flipAt = nil
	UI.edit.scripts.OnKeyDown(UI.edit, "F1")
	check(K.IsShown(), "F1 in the game's text box opens it too")
	K.Close()
	-- combat: refused, saying why; combat starting closes it
	local basePrint, printed = ns.Print, {}
	ns.Print = function(_, m) printed[#printed + 1] = m end
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(K.Open("simple") == false and not K.IsShown() and tostring(printed[1]):find("combat", 1, true), "not in combat: " .. tostring(printed[1]))
	_G.InCombatLockdown = realCombat
	K.Open("simple")
	K.frame.scripts.OnEvent(K.frame, "PLAYER_REGEN_DISABLED")
	check(not K.IsShown() and tostring(printed[2]):find("closed: combat started", 1, true), "combat starting closes it: " .. tostring(printed[2]))
	-- a /reload after the update: the new file isn't loaded, F1 says to restart
	printed = {}
	ns.KeysWindow = nil
	check(UI:KeysWindow() == false and tostring(printed[1]):find("restart the game", 1, true), "without the file: F1 says to restart: " .. tostring(printed[1]))
	ns.KeysWindow = K
	ns.Print = basePrint
	-- F1 is Terminal's even when the game binds it to a key that otherwise goes on (Ctrl+R's kind)
	local realGBA = _G.GetBindingAction
	_G.GetBindingAction = function() return "TOGGLEFPS" end
	check(UI.GameKey("F1") == false, "F1 never goes on to the game")
	_G.GetBindingAction = realGBA
	UI:Hide(); T.FlushAll()
	-- opening another panel closes it
	K.Open("simple"); ns.Changelog.Open()
	check(not K.IsShown() and ns.Changelog.IsShown(), "another panel opening closes it")
	ns.Changelog.Close()
end

io.write("[keys alike in every mode]\n")
do
	UI:Open(""); T.FlushAll()
	-- Ctrl+Home / Ctrl+End: the first / last result (Home and End alone stay the prompt's)
	UI:SetQuery("a"); T.FlushAll()
	local n = #UI.Results()
	withCtrl(function() key("END") end)
	check(n >= 2 and UI.Selected() == n, "Ctrl+End: the last result (" .. UI.Selected() .. " of " .. n .. ")")
	check(UI.cursor == 1, "(the caret stays)")
	withCtrl(function() key("HOME") end)
	check(UI.Selected() == 1, "Ctrl+Home: the first")
	-- Ctrl+Delete: up to the next word; Ctrl+W: the word before; Ctrl+U: everything before the cursor
	UI:SetQuery("hearth stone cloth", 7)
	withCtrl(function() key("DELETE") end)
	check(query() == "hearth cloth" and UI.cursor == 7, "Ctrl+Delete: the word right of the cursor and its spaces: '" .. query() .. "'")
	UI:SetQuery("hearth stone cloth", 12)
	withCtrl(function() key("W") end)
	check(query() == "hearth  cloth" and UI.cursor == 7, "Ctrl+W: the word before the cursor: '" .. query() .. "'")
	UI:SetQuery("hearth stone", 6)
	withCtrl(function() key("U") end)
	check(query() == " stone" and UI.cursor == 0, "Ctrl+U: what's before the cursor: '" .. query() .. "'")
	UI:SetQuery("hearth stone")
	withCtrl(function() key("U") end)
	check(query() == "", "Ctrl+U at the end: the whole line")
	UI:SetQuery("hearth stone", 12); UI.anchor = 2; UI.cursor = 9
	withCtrl(function() key("W") end)
	check(query() == "heone", "Ctrl+W over a selection: the selection: '" .. query() .. "'")
	-- the game's own text box: the same
	UI:SetQuery("hearth stone")
	UI:EnterEdit()
	withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "W") end)
	check(query() == "hearth ", "the text box: Ctrl+W: '" .. query() .. "'")
	UI:SetQuery("a"); T.FlushAll()
	withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "END") end)
	check(UI.Selected() == #UI.Results(), "the text box: Ctrl+End")
	UI:Hide(); T.FlushAll()
	-- a key that types nothing (F5, Insert) before anything was typed: not taken for a client that can't capture keys
	local cc, nc = UI.charChecked, UI.noChar
	UI.charChecked, UI.noChar = nil, nil
	UI:Open(""); T.FlushAll()
	key("F5"); key("INSERT"); T.FlushAll()
	check(not UI.noChar and UI.keys, "F5 / Insert first: the drawn prompt stays")
	UI.charChecked, UI.noChar = cc, nc
	UI:Hide(); T.FlushAll()
	check(UI.KeyTypes("A") and UI.KeyTypes("SPACE") and UI.KeyTypes("NUMPAD1") and UI.KeyTypes("\195\150")
		and not UI.KeyTypes("F5") and not UI.KeyTypes("INSERT") and not UI.KeyTypes("CAPSLOCK"), "which keys type")
end

do -- Tab, one rule: complete, else the next result; Shift+Tab the previous (Advanced; Simple: easy.lua; the pick list:
	-- search.lua)
	local was = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); T.FlushAll()
	UI:SetQuery("a"); T.FlushAll()
	local n = #UI.Results()
	local realAccept = UI.AcceptCompletion
	UI.AcceptCompletion = function() return false end
	key("TAB")
	check(n >= 2 and UI.Selected() == 2, "Advanced: Tab with nothing to complete: the next result")
	withShift(function() key("TAB") end)
	check(UI.Selected() == 1, "Shift+Tab: the previous")
	UI.AcceptCompletion = realAccept
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = was; UI:EasyChanged()
end

do -- the footer names F1 in every mode; the pick list's Shift+Tab is "previous" (back is Shift+Left's word)
	local th = ns.Theme.Get()
	local w = th.width
	th.width = 1600
	local was = ns.db.easyMode
	for _, simple in ipairs({ true, false }) do
		ns.db.easyMode = simple; UI:EasyChanged()
		UI:Open(""); T.FlushAll()
		UI:SetQuery("hearth"); T.FlushAll()
		UI.hintsRoom = nil; UI:FitHints()
		check((UI.hints:GetText() or ""):find("F1|r keys", 1, true), (simple and "Simple" or "Advanced") .. ": the footer says F1 keys: " .. tostring(UI.hints:GetText()))
		UI:Hide(); T.FlushAll()
	end
	UI:FuzzyOnce("hearth"); T.FlushAll()
	UI.hintsRoom = nil; UI:FitHints()
	check((UI.hints:GetText() or ""):find("F1|r keys", 1, true), "fuzzy finding: the footer says F1 keys")
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); T.FlushAll()
	UI:SetQuery("@"); T.FlushAll()
	UI.hintsRoom = nil; UI:FitHints()
	local h = UI.hints:GetText() or ""
	check(h:find("Shift+Tab|r previous", 1, true) and not h:find("Shift+Tab|r back", 1, true), "the pick list: Shift+Tab previous: " .. h)
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = was; UI:EasyChanged()
	th.width = w
end

do -- right-click in fuzzy finding: its first lines do what its Enter and Shift+Enter do (nothing is run)
	local was = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	UI:FuzzyOnce("hearth"); T.FlushAll()
	local e = UI.Results()[1]
	check(e ~= nil, "(fuzzy finding lists something)")
	if e then
		UI:ShowRowMenu(1)
		local l1, l2 = _G.TerminalRowMenuLine1, _G.TerminalRowMenuLine2
		check(l1.fs:GetText() == "To Simple mode" and l2.fs:GetText() == "To Advanced mode",
			"the menu's first lines: " .. tostring(l1.fs:GetText()) .. " / " .. tostring(l2.fs:GetText()))
		UI:MenuPicked(l2)
		check(not UI.fzf and UI:IsShown() and not E.On() and query():find(ns.Plain(e.name), 1, true), "To Advanced mode: as Shift+Enter: " .. query())
	end
	UI:Hide(); T.FlushAll()
	ns.db.easyMode = was; UI:EasyChanged()
end

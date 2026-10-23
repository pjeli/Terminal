local ns = select(2, ...)
local L = ns.L

-- The keyboard: out of combat the terminal reads keys itself (the drawn prompt's editing keys, held keys repeated,
-- Tab, the toggle key), so Enter on a result that opens a game window goes on to the game's binding in the same press.
-- Split out of UI.lua.

local UI = ns.UI
local LY = UI.layout
local EasyOn, PrevPos, NextPos, SecureView, TAB_LATE = UI.EasyOn, UI.PrevPos, UI.NextPos, UI.SecureView, UI.TAB_LATE

----------------------------------------------------------------------
-- Keyboard
--
-- Out of combat the terminal frame reads keystrokes itself (OnKeyDown + OnChar) instead
-- of the text box. That lets Enter on a Blizzard window be passed on to the game, where
-- it lands on the secure button: one press opens the window. In combat (when addons may
-- not change keyboard propagation), or on a client that doesn't send typed characters to
-- frames, the ordinary text box takes over.
----------------------------------------------------------------------

-- keys that go straight to the game while the terminal reads the keyboard
local PASS_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true, LWIN = true, RWIN = true, PRINTSCREEN = true,
}

-- (0.45.19, the player: Ctrl+S should still toggle sound, Ctrl+M music...) the game's own actions that don't touch what
-- Terminal does: a key chord bound to one of these still goes to the game while the terminal is open. Not targeting,
-- casting, moving, windows, or anything that hides the UI. (Ctrl+R, the frame rate, was one until 0.63.6: it's the
-- history search's now, the terminal's own; .atop's window still passes it on.)
UI.PASS_ACTIONS = {
	TOGGLEFPS = true, TOGGLESOUND = true, TOGGLEMUSIC = true, TOGGLEAMBIENCE = true, MASTERVOLUMEUP = true,
	MASTERVOLUMEDOWN = true, SCREENSHOT = true, TOGGLEGRAPHICSSETTINGS = true, TOGGLESELFHIGHLIGHT = true,
	TOGGLEWINDOWED = true, TOGGLE_VOICE_SELF_MUTE = true, TOGGLE_VOICE_SELF_DEAFEN = true, TEXT_TO_SPEECH_STOP = true,
	MINIMAPZOOMIN = true, MINIMAPZOOMOUT = true,
}
-- keys Terminal uses with Ctrl or Alt: always Terminal's (select all, the clipboard, the list's Ctrl+N/J/P/K, Ctrl+U/W,
-- words, Alt+`; Ctrl+Enter and Shift+Enter are its own too; F1 the keys window and F5 new results, whatever the game
-- binds to them)
local OWN_CHORD_KEYS = { A = true, C = true, V = true, N = true, J = true, P = true, K = true, U = true, W = true,
	Z = true, Y = true, -- (undo, redo: 0.66.1)
	T = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, -- (tabs: Ctrl+T, Ctrl+1-4; Tabs.lua)
	["`"] = true, LEFT = true, RIGHT = true, UP = true, DOWN = true, HOME = true, END = true, BACKSPACE = true,
	DELETE = true, TAB = true, ESCAPE = true, PAGEUP = true, PAGEDOWN = true, SPACE = true, F1 = true, F5 = true }
UI.HELP_KEY = "F1" -- (Apps/KeysWindow.lua: every key, per mode; .keybinds too)

--- The key with the modifiers held, as the game names a binding ("CTRL-SPACE"), and the modifiers: alt, ctrl, shift, meta.
local function Chord(key)
	local alt = IsAltKeyDown and IsAltKeyDown() or false
	local ctrl = IsControlKeyDown and IsControlKeyDown() or false
	local shift = IsShiftKeyDown and IsShiftKeyDown() or false
	local meta = IsMetaKeyDown and IsMetaKeyDown() or false
	return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. (meta and "META-" or "") .. key,
		alt, ctrl, shift, meta
end

--- Is this key press the game's (a chord with Ctrl, Alt or Meta, or a function key, bound to one of PASS_ACTIONS and
--- not one of Terminal's own)? Also the action it's bound to.
function UI.GameKey(key)
	if type(key) ~= "string" or OWN_CHORD_KEYS[key] or ns.IsTickKey(key) or not GetBindingAction then return false end
	local chord, alt, ctrl, shift, meta = Chord(key)
	if (key == "ENTER" or key == "NUMPADENTER") and (ctrl or shift) then return false end
	if not (alt or ctrl or meta) and not key:match("^F%d+$") then return false end -- (a plain key types)
	local ok, action = pcall(GetBindingAction, chord)
	if ok and type(action) == "string" and UI.PASS_ACTIONS[action] then return true, action end
	return false
end

function UI:EnterKeys()
	local frame, edit = UI.frame, UI.edit
	if not frame or self.noChar or InCombatLockdown() then return false end
	if self.clipHint then self.clipHint = nil; self:SetStatus() end
	self.keys = true
	self.anchor = nil
	-- (the game's text box's caret, where it was moved there: the drawn prompt's own follows only text changes; 0.63.7,
	-- review: back from combat the caret jumped to the end)
	if edit.HasFocus and edit:HasFocus() and edit.GetCursorPosition then
		local p = edit:GetCursorPosition()
		if type(p) == "number" then self.cursor = p end
	end
	self.cursor = math.min(self.cursor or 0, #edit:GetText())
	edit:ClearFocus()
	frame:EnableKeyboard(true)
	frame:SetPropagateKeyboardInput(false)
	self:UpdateCaret()
	return true
end

function UI:EnterEdit()
	local frame, edit = UI.frame, UI.edit
	if not frame then return end
	if self._repeat then self._repeat.key = nil; self._repeat:Hide() end
	self.keys = false
	frame:EnableKeyboard(false)
	local lo, hi = self:SelRange()
	self.anchor = nil
	edit:SetFocus()
	edit:SetCursorPosition(self.cursor or #edit:GetText())
	if lo and edit.HighlightText then edit:HighlightText(lo, hi) end -- the selection carries over
	self:UpdateCaret()
end

local function WordLeft(s, c) -- start of the word left of c
	local i = c
	while i > 0 and s:sub(i, i):match("%s") do i = i - 1 end
	while i > 0 and not s:sub(i, i):match("%s") do i = i - 1 end
	return i
end

local function WordRight(s, c) -- end of the word right of c
	local n, i = #s, c
	while i < n and s:sub(i + 1, i + 1):match("%s") do i = i + 1 end
	while i < n and not s:sub(i + 1, i + 1):match("%s") do i = i + 1 end
	return i
end

local function NextWord(s, c) -- where the next word starts after c (the rest of this word, then its spaces)
	local n, i = #s, c
	while i < n and not s:sub(i + 1, i + 1):match("%s") do i = i + 1 end
	while i < n and s:sub(i + 1, i + 1):match("%s") do i = i + 1 end
	return i
end

--- Move the caret. With shift the selection grows from where it began; without, it's dropped.
local function MoveCaret(to, shift)
	if shift then
		if not UI.anchor then UI.anchor = UI.cursor end
	else
		UI.anchor = nil
	end
	UI.cursor = to
	UI:UpdateCaret()
end

--- Does this key type a character (a letter, a digit, Space, the number pad, a letter of another alphabet)? A function
--- key, Insert or Caps Lock types nothing: no OnChar follows them.
local function Types(key)
	return type(key) == "string" and (#key == 1 or key == "SPACE" or key:find("^NUMPAD") ~= nil or key:find("[\128-\255]") ~= nil)
end
UI.KeyTypes = Types -- (tests)

-- Terminal's own binding commands (Bindings.xml) and what each runs
local OWN_ACTIONS = { TERMINAL_TOGGLE = "Toggle", TERMINAL_FUZZY = "FuzzyOnce", TERMINAL_ADVANCED_ONCE = "AdvancedOnce" }

--- (0.49.2, review: ".bind CTRL-SPACE" opened the terminal, and Ctrl+Space then did nothing in it: the terminal holds the
--- keyboard, so the game's binding never fires) The key chord is bound to one of Terminal's own commands: which one, else
--- nil. Not ` or another key the terminal's bound to alone (TickKey's: Tab+` and Alt+` too), not Enter (running a
--- result), not a plain key that types (it types). Alt with a key whose chord has no binding: the key without Alt (the
--- game hands it that binding too), so Alt+Ctrl+Space is Alt+` when Ctrl+Space is the terminal's (0.65.1).
function UI.OwnBinding(key)
	if type(key) ~= "string" or ns.IsTickKey(key) or key == "ENTER" or key == "NUMPADENTER" or not GetBindingAction then return nil end
	local chord, alt, ctrl, _, meta = Chord(key)
	if not (alt or ctrl or meta) and Types(key) then return nil end
	local ok, action = pcall(GetBindingAction, chord)
	-- (only the terminal's key: Alt+ it is Alt+`; and never a key that types with Ctrl and Alt, which is AltGr typing
	-- on many layouts: AltGr+Q types @; 0.65.1 review)
	if alt and ok and (action == nil or action == "") and not (ctrl and (#key == 1 or key:find("[\128-\255]"))) then
		local ok2, a2 = pcall(GetBindingAction, (chord:gsub("ALT%-", "", 1)))
		if ok2 and a2 == "TERMINAL_TOGGLE" then action = a2 end
	end
	if ok and type(action) == "string" and OWN_ACTIONS[action] then return action end
	return nil
end

--- A key that types the same character at once on every keyboard: a plain letter or digit, Space. (A dead key, ´ ` ^ ~ ¨,
--- types nothing until the next key; a symbol key may be one on another layout, the number pad types nothing with Num
--- Lock off.)
local function SureChar(key)
	return key == "SPACE" or (type(key) == "string" and key:match("^%w$") ~= nil)
end

local function CheckChar(key)
	local edit = UI.edit
	-- OnChar should follow this key; if it never does, this client can't do key capture. (Only a key that types: a
	-- function key pressed before anything was typed switched to the plain text box for good. And only one that surely
	-- types at once (0.49.2, review): a dead key first in a session (´ then e for é) switched to it for the session.)
	if UI.charChecked or not SureChar(key) then return end
	UI.pendingChar = key
	C_Timer.After(0, function()
		local k = UI.pendingChar
		if not k then return end
		UI.pendingChar = nil
		UI.noChar = true
		local ch = (k == "SPACE" and " ") or (#k == 1 and k:lower()) or ""
		local q, c = edit:GetText(), UI.cursor
		UI:SetQuery(q:sub(1, c) .. ch .. q:sub(c + 1), c + #ch)
		UI:EnterEdit()
		ns:Print(L["This client doesn't pass typed text to addon frames, so the plain search box is used (windows that need a secure click will take Enter twice)."])
	end)
end

----------------------------------------------------------------------
-- Holding a key. Frames are told about a key press once, so held Backspace, Delete and
-- the arrow keys are repeated here: after a short delay, then steadily, until key-up.
----------------------------------------------------------------------

local EditKey -- defined below
local REPEAT_KEYS = { BACKSPACE = true, DELETE = true, LEFT = true, RIGHT = true, UP = true, DOWN = true }
local REPEAT_DELAY, REPEAT_RATE = 0.4, 0.045
UI.BACK_HOLD = 2 -- (s: a Shift+Left that went back, if its key-up is never heard)
local rep = CreateFrame("Frame")
rep:Hide()
UI._repeat = rep

local function StopRepeat()
	rep.key = nil
	rep:Hide()
end

local function StartRepeat(key, ctrl, shift)
	rep.key, rep.ctrl, rep.shift, rep.wait = key, ctrl, shift, REPEAT_DELAY
	rep:Show()
end

rep:SetScript("OnUpdate", function(self, elapsed)
	if not self.key then return end
	self.wait = self.wait - elapsed
	if self.wait > 0 then return end
	-- stop if the key was let go without us hearing it, or the terminal moved on
	if not (UI.keys and UI:IsShown()) or (IsKeyDown and not IsKeyDown(self.key)) then
		StopRepeat()
		return
	end
	self.wait = REPEAT_RATE
	EditKey(self.key, self.ctrl, self.shift)
end)

local function KeysDown(self, key)
	local edit = UI.edit
	UI.swallowChar = nil -- (a character to drop comes right after its own key, before the next one: Bar.lua)
	if InCombatLockdown() then
		UI:EnterEdit()
		return
	end
	if PASS_KEYS[key] then
		self:SetPropagateKeyboardInput(true)
		return
	end
	-- (0.49.2, review) a key bound to one of Terminal's own commands (".bind CTRL-SPACE", the fuzzy-finding key): run here,
	-- as the game's binding would, before Terminal's own chords (Ctrl+Space's) take it; never passed on (it would open
	-- the terminal again)
	local own = UI.OwnBinding(key)
	if own then
		self:SetPropagateKeyboardInput(false)
		ns:Trace(("key %s: Terminal's %s"):format(key, own))
		-- (the terminal's own key, bound with a modifier: what ` does in it, Tab+ and Alt+ too; 0.65.1)
		if own == "TERMINAL_TOGGLE" then UI.TickKey() else UI[OWN_ACTIONS[own]](UI) end
		return
	end
	-- (0.55.13, the player) Alt+F, Alt+S, Alt+G: the bar's Filter, Sort and Group menus, to pick from with the keys; and
	-- a bar menu open from the keys takes them (Bar.lua). Before the game's keys: the bar is showing, they're its
	local B = ns.Bar
	if B and B.MenuKey(self, key) then return end
	if B and IsAltKeyDown and IsAltKeyDown() and not IsControlKeyDown() and B.ALT_KEYS[key] and B.KeyOpen(B.ALT_KEYS[key]) then
		self:SetPropagateKeyboardInput(false)
		B.SwallowAltChar(key) -- (the character the client types for it after the key: not typed)
		return
	end
	-- (Ctrl+R: the history search, the terminal's own (ListKey); not passed on to the game's frame rate. 0.63.6, the player)
	local ctrlR = key == "R" and IsControlKeyDown and IsControlKeyDown() and not (IsAltKeyDown and IsAltKeyDown())
	local game, action = UI.GameKey(key)
	if game and not ctrlR then
		-- the game's own key for something that doesn't touch Terminal (Ctrl+S, sound): it goes on to it
		ns:Trace(("key %s: the game's %s"):format(key, tostring(action)))
		self:SetPropagateKeyboardInput(true)
		return
	end
	if key == "TAB" then
		UI.tabHeld = GetTime()
		-- Tab still held from the press that opened the terminal (its repeats): not a Tab of its own. Unless the client
		-- tells Tab is down now (IsKeyDown, a plain true): then its "not held" as the toggle key opened the terminal was
		-- true too, and this is a Tab of its own (0.49.2, review: ` then Tab within a second was swallowed, and its
		-- key-up turned to fuzzy finding)
		-- (Ctrl+Tab never is: the next tab; review, 0.53.6)
		if UI.openedByToggle and GetTime() - UI.openedByToggle < TAB_LATE and not UI:TabToldDown() and not IsControlKeyDown() then
			self:SetPropagateKeyboardInput(false)
			return
		end
	end
	UI.openedByToggle = nil -- (a key typed: too late to read the opening press as Tab+`)
	local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
	if UI:MenuKey(self, key) then return end
	UI:HideRowMenu()
	-- .tour: Enter goes on, Shift+Left back, Esc ends it (Tour.lua)
	if ns.Tour and ns.Tour.Key(key, shift) then
		self:SetPropagateKeyboardInput(false)
		return
	end
	if (key == "ENTER" or key == "NUMPADENTER") and UI.histSearch then
		-- Ctrl+R: the line picked goes in the prompt and is searched (UI/Modes.lua)
		self:SetPropagateKeyboardInput(false)
		UI:HistoryAccept(UI.results[UI.sel])
		return
	end
	if (key == "ENTER" or key == "NUMPADENTER") and UI.fzf then
		-- pure fuzzy finding: the result goes over to Simple mode (Enter) or Advanced (Shift+Enter), nothing is run
		self:SetPropagateKeyboardInput(false)
		UI:FuzzyPop(UI.results[UI.sel], shift)
		return
	end
	if key == "ENTER" or key == "NUMPADENTER" then
		-- (">>> say": the one line the game presses holds every result, so a search still going is finished first, as
		-- ">>> party" and the menu's "All N" lines do; review, 0.48.6: only the first frame's rows went)
		local to = UI.sendTo
		if to and to.all and to.cmd and ns.Share.Restricted(to) and not UI:FinishSearch(UI.SEND_FINISH_MS) then
			self:SetPropagateKeyboardInput(false)
			ns:Print(UI.STILL_SEARCHING)
			return
		end
		-- something armed for this Enter (Shift+Enter or a click in the game's text box, a click on a row with no click
		-- route, a line of the mouse menu) on the row still selected: Enter presses that, as the footer says. Else it's
		-- stale, and Enter works its press out afresh. (0.49.2, review: it always worked it out again, from Shift held
		-- now and without the menu's own line: the armed "link in chat" ran the plain open, the menu's Open sent it)
		local sel, armed = UI.results[UI.sel], UI.armedEntry
		if armed and not (sel and UI.SameRow(sel, armed)) then
			UI:Disarm()
			armed = nil
		end
		local se = armed or SecureView(sel, shift)
		UI.holdOpen = UI.HoldFor(se, ctrl) -- (Ctrl+Enter: stays open after a press that opens no window)
		if se and UI:ArmForPress(se) then
			-- (a press that asks for more, @who's "Ask the server", isn't a line to run again: as Activate and a click)
			if not se.staysOpen then ns:RecordHistory(edit:GetText()) end
			self:SetPropagateKeyboardInput(true) -- this same press reaches the game's binding
			UI:FinishSoon(se)
			return
		end
		self:SetPropagateKeyboardInput(false)
		UI:Activate(nil, { keepOpen = ctrl, secondary = shift or (armed ~= nil and rawget(armed, "isShift") == true) })
		return
	end
	self:SetPropagateKeyboardInput(false)

	if key == "LEFT" and UI.backHeld then
		-- (the press that went back, still held: this client's own repeats of it go nowhere)
		if GetTime() - UI.backHeld < UI.BACK_HOLD then return end
		UI.backHeld = nil
	end
	if REPEAT_KEYS[key] then
		if rep.key == key then
			-- a second key-down without a key-up: this client repeats held keys itself
			UI.nativeRepeat = true
			StopRepeat()
		elseif not UI.nativeRepeat then
			StartRepeat(key, ctrl, shift)
		end
	end
	EditKey(key, ctrl, shift)
end

--- Where the cursor is: Terminal's own while it draws the prompt, else the game's text box's.
local function Cursor(text)
	local edit = UI.edit
	local c = UI.keys and UI.cursor or (edit.GetCursorPosition and edit:GetCursorPosition())
	return UI.ClampCursor(c, text)
end
--- The caret now, in the drawn prompt or the game's text box (UI.cursor is stale in the box: it follows text changes
--- only; review, 0.53.6: a tab, F1 and combat kept an old caret).
function UI.CursorNow() return Cursor(UI.edit and UI.edit:GetText() or "") end

--- The keys Terminal does alike in the drawn prompt and the real text box (combat, the clipboard): F1 the keys window,
--- F5 the new results a background search held (nothing held: nothing happens), PageUp/Down a page, Ctrl+Home/End the
--- first/last result, Ctrl+N/J and Ctrl+P/K a row, Ctrl+U deletes what's before the cursor and Ctrl+W the word before it
--- (as a shell does). True when the key was one of them.
local function ListKey(key, ctrl)
	if key == UI.HELP_KEY then UI:KeysWindow()
	elseif key == UI.UPDATE_KEY then UI:ShowNewResults()
	elseif key == "PAGEUP" then UI:Move(-LY.ROWS)
	elseif key == "PAGEDOWN" then UI:Move(LY.ROWS)
	elseif not ctrl then return false
	elseif key == "HOME" then UI:Move(-#UI.results)
	elseif key == "END" then UI:Move(#UI.results)
	elseif key == "R" then UI:HistoryKey() -- (a shell's Ctrl+R: the history searched; again: an older one)
	elseif key == "N" or key == "J" then UI:Move(1)
	elseif key == "P" or key == "K" then UI:Move(-1)
	elseif key == "U" or key == "W" then
		local text = UI.edit:GetText()
		local c = Cursor(text)
		local lo = UI.keys and UI:SelRange()
		if lo then
			local _, hi = UI:SelRange()
			UI:SetQuery(text:sub(1, lo) .. text:sub(hi + 1), lo) -- (over a selection: the selection, as Backspace)
		else
			local before = key == "U" and "" or text:sub(1, c):gsub("[^%s]*%s*$", "") -- (W: the word left, its spaces)
			UI:SetQuery(before .. text:sub(c + 1), #before)
			if not UI.keys and UI.edit.SetCursorPosition then UI.edit:SetCursorPosition(#before) end
		end
	else return false end
	return true
end

--- Backspace or Delete over a selection: the selection goes. True when there was one.
local function DeleteSelection(text)
	local lo, hi = UI:SelRange()
	if not lo then return false end
	UI:SetQuery(text:sub(1, lo) .. text:sub(hi + 1), lo)
	return true
end

--- The toggle key (`) while the terminal is open, in the drawn prompt and the game's own text box alike: Tab+` = pure
--- fuzzy finding (in it already: closes), Alt+` = Advanced for this run, else it closes.
local function TickKey(key)
	UI:TraceTick()
	if UI:TabDown() then
		UI:FuzzyOnce()
	elseif IsAltKeyDown and IsAltKeyDown() and not ns.IsAltBoundKey(key) then -- (Alt+Q bound: it closes)
		UI:AdvancedOnce()
	else
		UI:Hide()
	end
end

-- (a block: the key helpers are EditKey's own)
do
	--- Right: a selection collapses to its right end; at the end of the prompt it takes the suggestion, and with Shift
	--- (nothing to select there) Simple mode opens the row menu, Advanced writes the result into the prompt; else the
	--- caret moves (a word with Ctrl, selecting with Shift).
	local function RightKey(text, c, ctrl, shift)
		local lo, hi = UI:SelRange()
		if lo and not shift then
			MoveCaret(hi, false)
		elseif not shift and not ctrl and c >= #text and UI:AcceptCompletion() then
			return -- at the end: take the suggestion
		elseif shift and not ctrl and c >= #text and EasyOn() and not UI.fzf and not UI:SuggestionText() and UI.results[UI.sel] then
			UI:ShowRowMenu(UI.sel, true) -- Simple mode: what can be done with it (the result's text would be Advanced syntax)
			return
		elseif shift and not ctrl and c >= #text and UI:FillFromResult() then
			return -- at the end (nothing to select): the selected result into the prompt, "@npc Thrall"
		else
			MoveCaret(ctrl and WordRight(text, c) or NextPos(text, c), shift)
		end
	end

	--- Tab, one rule in every mode (0.45.20): it completes, like a shell (the faint text after the cursor; Simple mode's
	--- category row: picks it), and with nothing to complete goes to the next result; Shift+Tab the previous one. The
	--- pick list ("@", "q:") goes round. Back is Shift+Left's (Simple mode's Tab in a category no longer goes back to
	--- all of them). The game's own text box (combat, the clipboard) runs it too (UI.TabKey).
	local function TabKey(shift)
		if UI.fzf or UI.histSearch then
			UI:Move(shift and -1 or 1) -- (pure fuzzy finding, Ctrl+R: nothing to complete)
		elseif UI:StepSyntax(shift and -1 or 1) then
			return -- (the pick list ("@", "q:"): Tab / Shift+Tab only move through it, Enter writes the one picked)
		elseif shift then
			UI:Move(-1)
		elseif UI:AcceptCompletion() then
			return
		elseif EasyOn() and UI.mode == "search" and UI:EasyTab() then
			return -- (a category row: picked)
		else
			UI:Move(1)
		end
	end
	UI.TabKey = TabKey

	--- Ctrl+V / Ctrl+C in the drawn prompt: the clipboard is only reachable from the game's own text box, and this press
	--- is spent getting there: the next Ctrl+V / Ctrl+C does it (the prompt and footer say so).
	local function ClipKey(key)
		UI.clipHint = key
		UI:EnterEdit()
		UI:SetStatus()
		-- temporary: gone with the paste/copy, or after a few seconds whatever happens
		local token = {}
		UI.clipToken = token
		C_Timer.After(5, function()
			if UI.clipToken == token and UI.clipHint then
				UI.clipHint = nil
				UI:SetStatus(); UI:UpdateGhost()
			end
		end)
	end

	--- What a key does to the query (also run again for held keys).
	EditKey = function(key, ctrl, shift)
		local edit = UI.edit
		local text, c = edit:GetText(), UI.cursor
		if ns.IsTickKey(key) then
			TickKey(key)
		elseif key == "ESCAPE" then
			UI:Dismiss()
		elseif (key == "BACKSPACE" or key == "DELETE") and DeleteSelection(text) then
			return
		elseif key == "BACKSPACE" then
			if ctrl then
				local before = text:sub(1, c):gsub("[^%s]*%s*$", "") -- the word left of the caret (and spaces after it)
				UI:SetQuery(before .. text:sub(c + 1), #before)
			elseif c > 0 then
				local p = PrevPos(text, c)
				UI:SetQuery(text:sub(1, p) .. text:sub(c + 1), p)
			end
		elseif key == "DELETE" then
			-- (Ctrl: up to the next word, the word right of the caret and the spaces after it, as Ctrl+Backspace takes the
			-- one left of it)
			if c < #text then UI:SetQuery(text:sub(1, c) .. text:sub((ctrl and NextWord(text, c) or NextPos(text, c)) + 1), c) end
		elseif key == "LEFT" and shift and not ctrl and UI:GoBack() then
			-- Shift+Left goes back (0.45.17, the player: the one key for it): the search a step left, a category picked;
			-- the held key does nothing more until let go. Nothing to go back to: it selects, as before
			StopRepeat()
			UI.backHeld = GetTime()
		elseif key == "LEFT" then
			local lo = UI:SelRange()
			if lo and not shift then
				MoveCaret(lo, false) -- a selection collapses to its left end
			else
				MoveCaret(ctrl and WordLeft(text, c) or PrevPos(text, c), shift)
			end
		elseif key == "RIGHT" then
			RightKey(text, c, ctrl, shift)
		elseif ctrl and (key == "HOME" or key == "END") then
			ListKey(key, ctrl) -- (the first / last result; Home and End alone are the prompt's)
		elseif key == "HOME" then
			MoveCaret(0, shift)
		elseif key == "END" then
			MoveCaret(#text, shift)
		elseif key == "UP" then
			UI:Up()
		elseif key == "DOWN" then
			UI:Down()
		elseif ctrl and not IsAltKeyDown() and ns.Tabs and ns.Tabs.Key(key, shift) then
			return -- (tabs: Ctrl+T, Ctrl+1-4, Ctrl+Tab, Ctrl+Shift+W; Tabs.lua)
		elseif key == "TAB" then
			TabKey(shift)
		elseif ListKey(key, ctrl and not IsAltKeyDown()) then
			return
		elseif (ctrl and not IsAltKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown()) then
			-- (Ctrl with Alt is AltGr, typing: Polish ą ć ń, Czech and Hungarian @ |; Terminal has no Ctrl+Alt keys. 0.49.2,
			-- review: AltGr+A selected all, AltGr+C opened the clipboard box, AltGr+W deleted a word)
			-- (a Mac's Cmd is Ctrl here: Cmd+A, Cmd+C, Cmd+V; review, 0.48.6: Cmd+V as the first key typed a stray "v" and,
			-- no typed character following it, switched to the plain text box for the session)
			if key == "A" then
				UI.anchor = 0; UI.cursor = #text; UI:UpdateCaret() -- select all
			elseif key == "V" or key == "C" then
				ClipKey(key)
			elseif key == "Z" then
				UI:UndoEdit(shift and 1 or -1) -- (undo; Ctrl+Shift+Z redoes, as Ctrl+Y does: 0.66.1)
			elseif key == "Y" then
				UI:UndoEdit(1)
			end
		elseif not IsAltKeyDown() then
			CheckChar(key)
		end
	end
end

-- Two-step fallback when key capture isn't available: Enter is armed, wait for it.
local function LegacyDown(self, key)
	if InCombatLockdown() then
		UI:Disarm()
		UI:EnterEdit()
		return
	end
	if key == "ENTER" or key == "NUMPADENTER" or key == "ESCAPE" or PASS_KEYS[key] then
		self:SetPropagateKeyboardInput(true)
		if (key == "ENTER" or key == "NUMPADENTER") and UI.armedEntry then UI:FinishSoon(UI.armedEntry) end
	else
		self:SetPropagateKeyboardInput(false)
		UI:Disarm()
		UI:EnterEdit()
		UI:Render()
	end
end

function UI:OnChar(text)
	local edit = UI.edit
	self.pendingChar = nil
	self.charChecked = true
	if not self.keys or not self:IsShown() then return end
	-- the ` of Alt+` (its OnChar follows the key that switched to Advanced): not typed
	if ns.IsTickKey(text) and self.swallowTick and GetTime() - self.swallowTick < 0.5 then
		self.swallowTick = nil
		return
	end
	-- the character a key the bar took types after it (Alt+F's on a Mac, Space picking a line): not typed (Bar.lua)
	local sw = self.swallowChar
	if sw then
		self.swallowChar = nil
		local want = (sw.ch and text == sw.ch) or (sw.letter and (ns.Lower(text) == sw.letter or text:byte(1) > 127))
		if GetTime() - sw.at < 0.5 and want then return end
	end
	local q, c = edit:GetText(), self.cursor
	local lo, hi = self:SelRange()
	if lo then q, c = q:sub(1, lo) .. q:sub(hi + 1), lo end -- typing replaces the selection
	self:SetQuery(q:sub(1, c) .. text .. q:sub(c + 1), c + #text)
end

-- (UI.lua's frame scripts and LetGo call these)
UI.KeysDown, UI.LegacyDown, UI.StopRepeat, UI.ListKey, UI.TickKey = KeysDown, LegacyDown, StopRepeat, ListKey, TickKey

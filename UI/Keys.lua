local ns = select(2, ...)

-- The keyboard: out of combat the terminal reads keys itself (the drawn prompt's editing keys, held keys repeated,
-- Tab, the toggle key), so Enter on a result that opens a game window goes on to the game's binding in the same press.
-- Split out of UI.lua.

local UI = ns.UI
local L = UI.layout
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

function UI:EnterKeys()
	local frame, edit = UI.frame, UI.edit
	if not frame or self.noChar or InCombatLockdown() then return false end
	if self.clipHint then self.clipHint = nil; self:SetStatus() end
	self.keys = true
	self.anchor = nil
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

local function CheckChar(key)
	local edit = UI.edit
	-- OnChar should follow this key; if it never does, this client can't do key capture
	if UI.charChecked then return end
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
		ns:Print("This client doesn't pass typed text to addon frames, so the plain search box is used (windows that need a secure click will take Enter twice).")
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
	if InCombatLockdown() then
		UI:EnterEdit()
		return
	end
	if PASS_KEYS[key] then
		self:SetPropagateKeyboardInput(true)
		return
	end
	if key == "TAB" then
		UI.tabHeld = GetTime()
		-- Tab still held from the press that opened the terminal (its repeats): not a Tab of its own
		if UI.openedByToggle and GetTime() - UI.openedByToggle < TAB_LATE then
			self:SetPropagateKeyboardInput(false)
			return
		end
	end
	UI.openedByToggle = nil -- (a key typed: too late to read the opening press as Tab+`)
	local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
	if UI:MenuKey(self, key) then return end
	UI:HideRowMenu()
	if (key == "ENTER" or key == "NUMPADENTER") and UI.fzf then
		-- pure fuzzy finding: the result goes over to Simple mode (Enter) or Advanced (Shift+Enter), nothing is run
		self:SetPropagateKeyboardInput(false)
		UI:FuzzyPop(UI.results[UI.sel], shift)
		return
	end
	if key == "ENTER" or key == "NUMPADENTER" then
		local se = SecureView(UI.results[UI.sel], shift)
		UI.holdOpen = UI.HoldFor(se, ctrl) -- (Ctrl+Enter: stays open after a press that opens no window)
		if se and UI:ArmForPress(se) then
			ns:RecordHistory(edit:GetText())
			self:SetPropagateKeyboardInput(true) -- this same press reaches the game's binding
			UI:FinishSoon(se)
			return
		end
		self:SetPropagateKeyboardInput(false)
		UI:Activate(nil, { keepOpen = ctrl, secondary = shift })
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

--- The keys that walk the list, the same in the drawn prompt and the real text box: PageUp/Down a
--- page, Ctrl+N/J and Ctrl+P/K a row, Ctrl+U clears the query. True when the key was one of them.
local function ListKey(key, ctrl)
	if key == "PAGEUP" then UI:Move(-L.ROWS)
	elseif key == "PAGEDOWN" then UI:Move(L.ROWS)
	elseif not ctrl then return false
	elseif key == "N" or key == "J" then UI:Move(1)
	elseif key == "P" or key == "K" then UI:Move(-1)
	elseif key == "U" then UI:SetQuery("", 0)
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
local function TickKey()
	UI:TraceTick()
	if UI:TabDown() then
		UI:FuzzyOnce()
	elseif IsAltKeyDown and IsAltKeyDown() then
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

	--- Tab (Shift+Tab: back). The game's own text box (combat, the clipboard) runs it too (UI.TabKey).
	local function TabKey(shift)
		if UI.fzf then
			UI:Move(shift and -1 or 1) -- (pure fuzzy finding: Tab goes through the list too)
		elseif EasyOn() and UI.mode == "search" then
			-- easy mode: back to the categories (or pick one), unless there is typed syntax to complete
			if not UI:AcceptCompletion() then UI:EasyTab() end
		-- Tab completes, like a shell; with nothing (more) to complete it moves down the list
		-- the pick list ("@", "q:"): Tab / Shift+Tab only move through it (Enter writes the one picked)
		elseif UI:StepSyntax(shift and -1 or 1) then
			return
		elseif shift then
			UI:Move(-1)
		elseif not UI:AcceptCompletion() then UI:Move(1) end
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
		if key == "`" then
			TickKey()
		elseif key == "ESCAPE" then
			UI:Hide()
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
			if c < #text then UI:SetQuery(text:sub(1, c) .. text:sub(NextPos(text, c) + 1), c) end
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
		elseif key == "HOME" then
			MoveCaret(0, shift)
		elseif key == "END" then
			MoveCaret(#text, shift)
		elseif key == "UP" then
			UI:Up()
		elseif key == "DOWN" then
			UI:Down()
		elseif key == "TAB" then
			TabKey(shift)
		elseif ListKey(key, ctrl) then
			return
		elseif ctrl then
			if key == "A" then
				UI.anchor = 0; UI.cursor = #text; UI:UpdateCaret() -- select all
			elseif key == "V" or key == "C" then
				ClipKey(key)
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
	if text == "`" and self.swallowTick and GetTime() - self.swallowTick < 0.5 then
		self.swallowTick = nil
		return
	end
	local q, c = edit:GetText(), self.cursor
	local lo, hi = self:SelRange()
	if lo then q, c = q:sub(1, lo) .. q:sub(hi + 1), lo end -- typing replaces the selection
	self:SetQuery(q:sub(1, c) .. text .. q:sub(c + 1), c + #text)
end

-- (UI.lua's frame scripts and LetGo call these)
UI.KeysDown, UI.LegacyDown, UI.StopRepeat, UI.ListKey, UI.TickKey = KeysDown, LegacyDown, StopRepeat, ListKey, TickKey

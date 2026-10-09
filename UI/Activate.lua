local ns = select(2, ...)

-- Running a result (Enter, a click, Shift+Enter). A window Blizzard owns is opened by the game's own press: Enter armed
-- on a secure button, or the click catcher laid over the hovered row; Terminal's code then only points at the result.
-- Split out of UI.lua.

local UI = ns.UI
local rows = UI.rows
local catcher -- TerminalClickCatcher, made the first time a row needs it (see "Mouse clicks" below)

----------------------------------------------------------------------
-- Secure opening (see Secure.lua for why)
----------------------------------------------------------------------

--- Entries' `after` steps click and point at Blizzard frames, which are protected in combat.
local function RunAfter(e)
	if InCombatLockdown() then
		ns:Trace("combat: skipped after-step for " .. tostring(e.name))
		return
	end
	local ok, err = pcall(e.after, e)
	if not ok then ns:Trace("after-step error for " .. tostring(e.name) .. ": " .. tostring(err)) end
end

--- The entry's after-step (pointing at the result), `d` seconds from now: the window the press opened is up by then.
local function AfterSoon(e, d)
	if e.after then C_Timer.After(d, function() RunAfter(e) end) end
end

--- A click (the catcher, a menu line) on which the game ran the result's macro: finish as after Enter. `se`: the view
--- whose after-step runs (a Shift+click: the secondary's).
--- Ctrl+Enter keeps the terminal open, for a press the game makes too when it opens no window (a use, a cast, a toy,
--- an emote, a chat line: nothing has to be open first, its isOpen is ns.Never or none); a window's press closes it
--- as before (a window it opens would close it anyway: it's in UISpecialFrames). A press that's always made though
--- it opens a window (the achievement window, a journal, an options page: isOpen ns.Never too) says so in its spec
--- (`opensWindow`): it closes as every window's press does.
local function HoldFor(se, ctrl)
	if not (ctrl and se) then return nil end
	if type(se.secure) == "table" and se.secure.opensWindow then return nil end
	local o = se.isOpen
	return (not o or o == ns.Never) or nil
end
UI.HoldFor = HoldFor

local function FinishClicked(e, se)
	local edit = UI.edit
	ns:Bump(e.freqKey)
	ns:RecordHistory(edit:GetText())
	UI:Hide()
	AfterSoon(se, 0.1)
end
UI.FinishClicked = FinishClicked

function UI:Disarm()
	local frame = UI.frame
	self.holdOpen = nil
	if self.armedEntry or ns.Secure.armed or self.legacyArm then
		-- kept a moment: the press may still come back (see Secure.lua's PostClick)
		if self.armedEntry then self.lastArmedEntry, self.lastArmedAt = self.armedEntry, GetTime() end
		self.armedEntry = nil
		ns.Secure.Disarm()
		if self.legacyArm then
			self.legacyArm = false
			if frame and not self.keys then frame:EnableKeyboard(false) end
		end
		self:SetStatus()
	end
end

--- Called from Activate (Enter in the plain box, or a mouse click) for entries with `secure`.
--- Returns true if it took over: the window was already open, or Enter is now armed.
function UI:TryArmSecure(e)
	local frame, edit = UI.frame, UI.edit
	local S = ns.Secure
	local target = S.Resolve(e.secure, e)
	if not target then ns:Trace("secure: no binding/button for " .. e.name) return false end
	if e.isOpen and e.isOpen(e) then -- nothing to click, just point at the thing
		ns:Trace("secure: window already open, highlighting " .. e.name)
		self:Hide()
		ns:Bump(e.freqKey)
		AfterSoon(e, 0.05)
		return true
	end
	if InCombatLockdown() or not S.Arm(target) then ns:Trace("secure: could not arm for " .. e.name .. " (combat or no proxy)") return false end
	ns:Trace("secure: armed Enter -> " .. tostring(target.binding or target.button or target.spell) .. " for " .. e.name)
	ns:Bump(e.freqKey)
	self.armedEntry = e
	if not self.keys and not self:EnterKeys() then
		-- this client can't read keys for us: listen only for the next Enter
		edit:ClearFocus()
		frame:EnableKeyboard(true)
		self.legacyArm = true
	end
	self:SetStatus()
	return true
end

--- Enter pressed while the terminal reads the keyboard: bind Enter to the secure button
--- so this same keypress, passed on to the game, opens the window.
function UI:ArmForPress(e)
	local edit = UI.edit
	local S = ns.Secure
	local target = S.Resolve(e.secure, e)
	if not target or (e.isOpen and e.isOpen(e)) then return false end
	if not S.Arm(target) then ns:Trace("secure: arm failed on key press for " .. e.name) return false end
	ns:Trace("secure: key press armed -> " .. tostring(target.binding or target.button or target.spell) .. " for " .. e.name)
	-- (a text box holding the keyboard gets the press instead of the binding: say whose, for .debug log)
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if focus and focus ~= edit then
		local ok, name = pcall(function() return focus:GetName() or (focus.GetDebugName and focus:GetDebugName()) end)
		ns:Trace("secure: the keyboard is held by " .. tostring(ok and name or "a text box") .. ": the press may go there")
	end
	if self.armedEntry ~= e then ns:Bump(e.freqKey) end
	self.armedEntry = e
	self:SetStatus()
	return true
end

--- With a keybinding command, the window opens on this very key press; give the game a
--- moment, then close the terminal and point at the result. (A proxy button reports back through PostClick
--- instead: the macro proxy acts on key down, the click proxies Secure.Proxy makes on key release.)
function UI:FinishSoon(e)
	if ns.Secure.mode ~= "binding" then return end
	self.pendingAfter = e
	C_Timer.After(0.15, function()
		if self.pendingAfter ~= e then return end
		self.pendingAfter = nil
		if self.armedEntry == e then
			self:FinishSecure()
		elseif not UI:IsShown() then
			-- the window that just opened closed the terminal first: still point at the result
			ns.Secure.Disarm()
			AfterSoon(e, 0.1)
		end
	end)
end

function UI:FinishSecure()
	local hold = self.holdOpen -- (read before Disarm clears it)
	local e = self.armedEntry
	-- the press came back after the terminal had closed (the window it opened closed it): still that entry
	if not e and self.lastArmedEntry and self.lastArmedAt and GetTime() - self.lastArmedAt < ns.Secure.LATE then
		e = self.lastArmedEntry
	end
	-- finishing now: Disarm mustn't keep it as a press still to come back (its after-step would run twice)
	self.armedEntry, self.lastArmedEntry = nil, nil
	self:Disarm()
	if not e then return end
	ns:Trace("secure: finished, highlighting " .. e.name)
	-- (a press that asks for more, @who's: the answer comes into the list; Ctrl+Enter on one that opens no window)
	if not e.staysOpen and not hold then self:Hide() end
	AfterSoon(e, 0.1)
end

ns.Secure.onClicked = function() UI:FinishSecure() end

function UI:OnCombat()
	self:Disarm()
	if self.keys then self:EnterEdit() end -- keyboard propagation can't be changed in combat
end

function UI:OnRegen()
	if self:IsShown() and not self.keys and not self.noChar then self:EnterKeys() end
end

-- ">> channel": the chat line the game presses for the selected result
local function SendMacro(v) return ns.Share.Macro(v, UI.sendTo) end
local SEND_SPEC = { macro = SendMacro }
local NeverOpen = ns.Never -- (a chat line: always pressed)
local function SentAfter(v) ns:Trace("share: the game sent " .. tostring(v.name) .. " to " .. tostring(UI.sendTo and UI.sendTo.label)) end

--- The entry to open through the game's own key for this press, or nil. Shift+Enter uses the
--- entry's secondary action; one that opens a window itself (secondarySecure) is armed like
--- Enter is, with its own isOpen/after (e.g. an equipment set: the character window's sets).
local function SecureView(e, shift)
	if not e then return nil end
	-- ">> party": the selected result goes to the channel (the game presses the chat line), Enter or Shift+Enter
	if UI.sendTo then
		-- (no channel yet, or not one: nothing is pressed; Activate says what's missing)
		-- (">>> party": Terminal sends every result itself in Activate, a press the game doesn't take)
		if not UI.sendTo.cmd or UI.sendTo.all or e.noActivate or e.raw or e.completion then return nil end
		return setmetatable({ secure = SEND_SPEC, isOpen = NeverOpen, after = SentAfter }, { __index = e })
	end
	if shift and e.secondary then
		if not e.secondarySecure then return nil end
		-- (false, not nil: a missing one would fall back to the row's own Enter steps through __index; an NPC's
		-- Shift+Enter targeted it and then ran Enter's after-step too, which pinned it on the map)
		return setmetatable({
			secure = e.secondarySecure, isOpen = e.secondaryIsOpen or false, after = e.secondaryAfter or false,
			staysOpen = e.secondaryStaysOpen, -- (nil: the row's own; a chain's row stays open on Enter, not Shift+Enter)
			isShift = true, -- (the footer's "Press Enter to <Shift+Enter's verb>")
		}, { __index = e })
	end
	return e.secure and e or nil
end
UI.SecureView = SecureView

----------------------------------------------------------------------
-- Mouse clicks on results that open game windows
--
-- Enter opens such a window through the game's own key (see Secure.lua), but a mouse click
-- can't press a keybinding. So while the pointer is over such a result, a secure button
-- (TerminalClickCatcher) lies over its row, set to run that result's /click lines or spell
-- cast on a left click: the game presses them itself (nothing runs tainted), and Terminal
-- then closes and points at the result, as after Enter. Shift+click runs the secondary the
-- same way. Results with no such route (or whose window is already open) and plain actions
-- go on to the row's usual Activate. In combat the catcher hides itself (a secure state
-- driver), as windows can't be opened then anyway.
----------------------------------------------------------------------


--- The macro a click on this result runs (nil: none), and the entry view it opens. `quiet`: worked
--- out for the pointer resting on a row, not for a press: the macro's steps aren't traced.
local function ClickFor(e, shift, quiet)
	local se = SecureView(e, shift)
	if not se then return nil end
	if se.isOpen and se.isOpen(se) then return nil end -- already open: Activate only points at it
	return ns.Secure.ClickMacro(se.secure, se, quiet), se
end
UI.ClickFor = ClickFor

local function Catcher()
	if catcher or InCombatLockdown() then return catcher end
	local ok, c = pcall(CreateFrame, "Button", "TerminalClickCatcher", UIParent,
		"SecureActionButtonTemplate, SecureHandlerStateTemplate")
	if not ok or not c then return nil end
	c:Hide()
	c:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (right: the row's menu; no secure action on it)
	c:SetAttribute("useOnKeyDown", false)
	c:EnableMouseWheel(true)
	c:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(delta) end)
	c:SetScript("OnLeave", function() UI:HideCatcher() end)
	c:HookScript("PostClick", function(_, button) UI:CatcherClicked(button) end)
	if RegisterStateDriver then
		c:SetAttribute("_onstate-combat", [[ if newstate == "1" then self:Hide() end ]])
		pcall(RegisterStateDriver, c, "combat", "[combat] 1; 0")
	end
	catcher = c
	UI.catcher = c
	return c
end

function UI:HideCatcher()
	if not catcher then return end
	if catcher:IsShown() and not InCombatLockdown() then catcher:Hide() end
	catcher.entry = nil
end

--- Lay the catcher over row `row` (its frame), scaled to UIParent's coordinates.
local function AnchorCatcher(c, row)
	local frame = UI.frame
	local left, bottom, w, h = row:GetLeft(), row:GetBottom(), row:GetWidth(), row:GetHeight()
	if not (type(left) == "number" and type(bottom) == "number" and type(w) == "number" and type(h) == "number") then
		return false
	end
	local rs, us = row:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local s = (type(rs) == "number" and type(us) == "number" and us > 0) and rs / us or 1
	c:ClearAllPoints()
	c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
	c:SetSize(w * s, h * s)
	c:SetFrameStrata(frame:GetFrameStrata())
	local level = frame:GetFrameLevel()
	c:SetFrameLevel((type(level) == "number" and level or 1) + 20)
	return true
end

--- The pointer is over row i: if its result opens a window, lay the catcher over the row.
function UI:PlaceCatcher(i)
	local frame = UI.frame
	if InCombatLockdown() or self.closing or not frame or not frame:IsShown() then return end
	if self.fzf then self:HideCatcher() return end -- (a click hands the result over; nothing is opened)
	local row, e = rows[i], UI.results[UI.offset + i]
	-- the same result on the same row (the list redrawn under a resting pointer): its macros
	-- stand, the catcher only follows the row
	if catcher and e and catcher.entry == e and catcher.row == i and catcher:IsShown() then
		if not AnchorCatcher(catcher, row) then self:HideCatcher() end
		return
	end
	local plain = e and ClickFor(e, false, true)
	local shifted = e and ClickFor(e, true, true)
	if not (plain or shifted) then self:HideCatcher() return end
	local c = Catcher()
	if not c then return end
	if not AnchorCatcher(c, row) then self:HideCatcher() return end
	c:SetAttribute("type1", plain and "macro" or "")
	c:SetAttribute("macrotext1", plain)
	-- shift: its own action, or none at all (so a shift-click never runs the plain one)
	c:SetAttribute("shift-type1", shifted and "macro" or "")
	c:SetAttribute("shift-macrotext1", shifted)
	c.row, c.entry, c.plain, c.shifted = i, e, plain, shifted
	c:Show()
end

--- After a click on the catcher: if the game ran a macro, finish as after Enter; otherwise
--- the result's usual action.
function UI:CatcherClicked(button)
	local c = catcher
	local e = c and c.entry
	if not e or self.closing then return end
	local idx = UI.offset + c.row
	if button == "RightButton" then -- the row's menu (the catcher has no right-button action)
		if UI.results[idx] == e then UI.sel = idx; self:ShowRowMenu(idx) end
		return
	end
	self:HideCatcher()
	if UI.results[idx] ~= e then return end
	UI.sel = idx
	local kind, text
	if SecureButton_GetModifiedAttribute then
		kind = SecureButton_GetModifiedAttribute(c, "type", button or "LeftButton")
		text = SecureButton_GetModifiedAttribute(c, "macrotext", button or "LeftButton")
	else
		if IsShiftKeyDown() then text = c.shifted else text = c.plain end
		kind = text and "macro" or nil
	end
	if kind == "macro" and type(text) == "string" and text ~= "" then
		local se = SecureView(e, text ~= c.plain) or e
		ns:Trace("click: the game ran " .. text:gsub("\n", " | ") .. " for " .. tostring(e.name))
		C_Timer.After(0.3, function()
			local cf = _G.CharacterFrame
			if cf and cf.IsShown and cf:IsShown() then
				ns:Trace("click: character window now on " .. tostring(cf.activeSubframe))
			end
		end)
		FinishClicked(e, se)
	else
		ns:Trace("click: no window macro for " .. tostring(e.name) .. ", running its usual action")
		self:Activate(idx, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
	end
end

----------------------------------------------------------------------
-- Activation
----------------------------------------------------------------------

--- What a ">>" / ">>>" with no channel yet, or a word that isn't one, says (arrows: ">>" or ">>>").
local function NoChannel(to, arrows)
	local them = arrows == ">>>" and "them" or "it"
	ns:Print(to.bad and ("No channel called " .. to.bad .. ": " .. arrows .. " party, guild, raid, say, yell, officer, instance, whisper <name>, or a number")
		or ("Say where to send " .. them .. ": " .. arrows .. " party, guild, raid, say, yell, officer, instance, whisper <name>"))
end

UI.STILL_SEARCHING = "Still searching: press it again in a moment, to send every result."
--- ">>> channel": every result at once, sent by Terminal inside this press (Share.SendAll); a search still going is
--- finished first (else only its first frame's rows would go), or, when that would take long, nothing is sent yet.
local function SendEveryResult(self, to)
	if not to.cmd then return NoChannel(to, ">>>") end
	if not self:FinishSearch(UI.SEND_FINISH_MS) then ns:Print(UI.STILL_SEARCHING) return end
	local n, why = ns.Share.SendAll(self.groupList or UI.results, to, to.query)
	if not n then ns:Print(why) return end
	ns:RecordHistory(UI.edit:GetText())
	self:Hide()
end

--- ">> channel": the selected result is sent, never opened or run: the game presses the chat line (armed here).
local function SendSelected(self, e, to, secondary)
	if not to.cmd then return NoChannel(to, ">>") end
	local se = SecureView(e, secondary)
	if se and self:TryArmSecure(se) then ns:RecordHistory(UI.edit:GetText()) return end
	ns:Print(InCombatLockdown() and "In combat: can't send it now." or ("Couldn't send " .. tostring(e.name) .. "."))
end

function UI:Activate(idx, opts)
	local edit = UI.edit
	opts = opts or {}
	local e = UI.results[idx or UI.sel]
	if not e or e.noActivate then return end
	if self.fzf then return self:FuzzyPop(e, opts.secondary) end -- (a click: as Enter / Shift+Enter)
	-- ">>> channel": every result at once, sent by Terminal inside this press (a macro runs 255 characters at most)
	local to = self.sendTo
	if to and to.all and not e.completion then return SendEveryResult(self, to) end
	-- Opening or clicking Blizzard's windows is protected in combat: do nothing rather than
	-- have the game block us. (Shift+Enter actions that don't touch windows still work.)
	if InCombatLockdown() and (e.noCombat or e.secure) and not (opts.secondary and e.secondary and not e.noCombatSecondary) then
		ns:Trace("combat: ignored Enter on " .. tostring(e.name))
		-- (what the key would have done: "use", "show in spellbook", "run"... not always "open")
		local enter, shift
		if ns.Easy then enter, shift = ns.Easy.Verbs(e) end
		local verb = (opts.secondary and shift) or enter or "open"
		ns:Print(("%s: can't %s in combat."):format(tostring(e.name), verb))
		return
	end
	-- ">> channel": never opened or run, only sent (by the game's press, armed below)
	if to and not e.completion then return SendSelected(self, e, to, opts.secondary) end
	-- (a row that only fills the prompt in, "Search Questie for this", is a step, not something run)
	if not e.staysOpen then ns:RecordHistory(edit:GetText()) end
	-- windows Blizzard owns are opened by a secure click, never from our own code
	local se = SecureView(e, opts.secondary)
	self.holdOpen = HoldFor(se, opts.keepOpen)
	if se and self:TryArmSecure(se) then return end
	self.holdOpen = nil
	local args = self.args
	local isCmd = e.kind == "cmd"
	local stays = e.staysOpen
	if opts.secondary and e.secondary and e.secondaryStaysOpen ~= nil then stays = e.secondaryStaysOpen end
	if not opts.keepOpen and not stays then self:Hide() end
	ns:Bump(e.freqKey)
	local fn = (opts.secondary and e.secondary) or e.activate
	ns:Trace(("DIRECT (addon code) %s: %s [%s]"):format(opts.secondary and "secondary" or "activate", tostring(e.name), tostring(e.kind)))
	if not fn then return end
	local ok, ret = pcall(fn, e, args, self)
	if not ok then
		ns:Print("Error: " .. tostring(ret))
		return
	end
	-- a command's answer goes to the chat window, not into the results
	if isCmd and type(ret) == "table" then ns:Output(ret) end
end

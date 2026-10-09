local ns = select(2, ...)
local Fuzzy = ns.Fuzzy
local Theme = ns.Theme

local UI = {}
ns.UI = UI

local FOOTER_H = 26 -- one line: the result count on the left, key hints on the right
UI.FOOTER_H = FOOTER_H
local ONCE_LABEL = "Advanced, this time" -- (Alt+`: this run is Advanced, Simple again once it closes)
UI.ONCE_LABEL = ONCE_LABEL
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
UI.EasyOn = EasyOn
local MAX_ROWS = 20
UI.MAX_ROWS = MAX_ROWS
local SLICE_MS = 6 -- a search's share of one frame; a longer one goes on in the next frames
local SLICE_CHECK = 64 -- rows scored between looks at the clock
UI.SLICE_CHECK = SLICE_CHECK
UI.SLICE_MS = SLICE_MS

-- layout, recomputed from the theme (only ApplyTheme writes it; read through L when needed, never copied at load)
UI.layout = { ROWS = 10, ROW_H = 26, HEADER_H = 50, LINE_H = 19 }
local L = UI.layout

local TAB_LATE = 1.0 -- (opened by the toggle key this long ago, nothing typed since: Tab let go = it was Tab+`)
UI.TAB_LATE = TAB_LATE
local BUSY_DOTS = 8 -- the loading spinner's dots (BuildPromptParts makes them, SpinBusy turns them)
UI.BUSY_DOTS = BUSY_DOTS

local frame, edit, status, hints, promptFS, caret, measure, divider, promptBg, ghost, selBar, selEdge, footLine, selText, caretFrame, caretChar, hit, busy, syntax
local rows = {}
UI.rows = rows
local motion = CreateFrame("Frame") -- drives every animation (Motion.lua)
-- motion timings come from the animation style (Theme.ANIMATIONS)
local function Style() return Theme.Animation() or Theme.ANIMATIONS.smooth end
motion:Hide()
UI.motion = motion
-- something starts moving: the loop runs every frame again (resting, it only blinks the cursor)
local function Wake()
	UI.blinkOnly = false
	motion:Show()
end
UI.Style, UI.Wake = Style, Wake
UI.results = {}
function UI.Results() return UI.results end
UI.sel, UI.offset = 1, 0
function UI.Selected() return UI.sel end
UI.args = nil
UI.keys = false   -- true while the terminal reads keystrokes itself (Keys.lua)
UI.noChar = false -- set if this client never sends typed characters to frames
UI.cursor = 0     -- byte position of the caret in the query

--- The last search forgotten: nothing to narrow from, no completion kept for its rows. `looks`: the footer's key
--- hints are measured and the prompt's colours drawn again too (another mode).
local function Forget(self, looks)
	self.lastScan, self.lastOverview = nil, nil
	self:ForgetCompletion()
	if looks then self.hintsRoom, self.syntaxKey = nil, nil end
end
UI.Forget = Forget

local function IsCont(b) return b and b >= 0x80 and b < 0xC0 end

local function PrevPos(s, c) -- caret position one UTF-8 character to the left of c
	if c <= 0 then return 0 end
	local i = c
	while i > 1 and IsCont(s:byte(i)) do i = i - 1 end
	return i - 1
end

local function NextPos(s, c) -- one character to the right
	if c >= #s then return #s end
	local i = c + 1
	while i < #s and IsCont(s:byte(i + 1)) do i = i + 1 end
	return i
end
UI.PrevPos, UI.NextPos = PrevPos, NextPos

function UI:Animated() return Theme.Animation() ~= nil end

----------------------------------------------------------------------
-- Frame construction
----------------------------------------------------------------------

--- Let go of the keyboard (the next key already reaches the game) and put the drawn prompt's cursor away.
local function LetGo()
	UI.keys = false
	UI.StopRepeat()
	frame:EnableKeyboard(false)
	if caret then caret:Hide(); caretChar:Hide() end
	if hit then hit:Hide() end
	UI.dragging = false
end

-- (a block: Build's parts are its own)
local Build
do
	--- The terminal's frame: dragged by its body, keys read while the prompt is drawn, closed with Esc.
	local function BuildFrame()
		frame = CreateFrame("Frame", "TerminalFrame", UIParent, "BackdropTemplate")
		UI.frame = frame
		-- (hidden before its scripts are set: this first hide isn't a close. Its OnHide ended Alt+`'s one run, so the
		-- first Alt+` after a /reload opened in Simple mode)
		frame:Hide()
		frame:SetFrameStrata("DIALOG")
		frame:SetClampedToScreen(true)
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})
		frame:SetMovable(true)
		if frame.SetClipsChildren then frame:SetClipsChildren(true) end -- rows are cut off as it shrinks
		frame:EnableMouse(true)
		frame:EnableMouseWheel(true)
		frame:EnableKeyboard(false)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			-- saved by its top-left corner, so the terminal grows and shrinks downward
			local left, top = self:GetLeft(), self:GetTop()
			if left and top then
				ns.db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
			else
				local p, _, rp, x, y = self:GetPoint()
				ns.db.point = { p, rp, x, y }
			end
		end)
		frame:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(delta) end)
		frame:SetScript("OnHide", function(self)
			UI:EndAdvancedOnce()
			UI:EndFuzzy()
			UI.openedByToggle, UI.tabHeld = nil, nil
			UI:MotionReset()
			UI:HideTooltip()
			UI:Disarm()
			LetGo()
			-- closed by the game (a window it opened, Esc): the click catcher and the row menu go too, a frame later (a
			-- click on either may be what's closing it, and its PostClick still needs its entry to finish)
			C_Timer.After(0, function()
				if not UI:IsShown() then
					UI:HideCatcher()
					UI:HideRowMenu()
				end
			end)
		end)
		frame:SetScript("OnKeyDown", function(self, key)
			if UI.keys then return UI.KeysDown(self, key) end
			if UI.legacyArm then return UI.LegacyDown(self, key) end
			if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
		end)
		frame:SetScript("OnChar", function(_, text) UI:OnChar(text) end)
		frame:SetScript("OnKeyUp", function(_, key)
			if UI._repeat.key == key then UI.StopRepeat() end
			if key == "TAB" then UI:TabReleased() end
		end)

		local pt = ns.db.point
		if pt then
			frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
		else
			frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
		end
		tinsert(UISpecialFrames, "TerminalFrame")
	end

	--- The query's text changed (typed, pasted or set): searched again, the caret placed (`self`: the edit box).
	local function EditTextChanged(self)
		-- the key that opened the terminal (` or ~) must not end up typed into the box
		local t = self:GetText()
		if t:find("^[`~]") then
			local stripped = t:gsub("^[`~]+", "")
			UI.cursor = math.max(0, (UI.cursor or 0) - (#t - #stripped))
			self:SetText(stripped)
			return
		end
		if not UI._histSet and t ~= UI.histText then UI.histIdx = nil end
		if not UI.keys then
			local cp = self:GetCursorPosition()
			if type(cp) == "number" then UI.cursor = cp end
			-- typed or pasted into the real text box (Ctrl+V hands over to it: the clipboard is only
			-- there): back to Terminal's own prompt next frame, coloured, Enter opening in one press
			-- (only text changes: Ctrl+C or a selection to copy keeps the real box)
			if not UI.backToKeys and UI:IsShown() and not InCombatLockdown() and not UI.noChar then
				UI.backToKeys = true
				C_Timer.After(0, function()
					UI.backToKeys = nil
					if UI:IsShown() and not UI.keys and not InCombatLockdown() then
						local p = edit:GetCursorPosition()
						if type(p) == "number" then UI.cursor = p end
						UI:EnterKeys()
					end
				end)
			end
		end
		UI.cursor = math.min(UI.cursor or #t, #t)
		-- the game can report a change without one (the box resized, say): searching again
		-- then restarted a search spread over frames forever, and reset the scroll each time
		if t ~= UI.searchedText then UI:Refresh() end
		UI:UpdateCaret()
	end

	--- The prompt's label and the game's own text box (clipboard, combat; a click into it hands over to it).
	local function BuildEdit()
		promptFS = frame:CreateFontString(nil, "OVERLAY")
		promptFS:SetFontObject(Theme.fonts.input)
		UI.promptFS = promptFS

		edit = CreateFrame("EditBox", nil, frame)
		edit:SetFontObject(Theme.fonts.input)
		edit:SetAutoFocus(false)
		edit:SetAltArrowKeyMode(false)
		edit:SetMaxLetters(256)
		UI.edit = edit
		edit:SetScript("OnTextChanged", EditTextChanged)
		edit:SetScript("OnEditFocusGained", function()
			-- clicked into the box: plain text editing (clipboard, selection) until reopened
			if UI.keys then
				UI.keys = false
				UI.anchor = nil
				frame:EnableKeyboard(false)
				UI:UpdateCaret()
			end
		end)
		edit:SetScript("OnEnterPressed", function()
			UI:Activate(nil, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
		end)
		edit:SetScript("OnEscapePressed", function() UI:Hide() end)
		edit:SetScript("OnArrowPressed", function(_, key)
			if key == "UP" then UI:Up() elseif key == "DOWN" then UI:Down() end
		end)
		-- (Tab here does what it does in the drawn prompt: Simple mode's categories, Advanced's pick lists, completion)
		edit:SetScript("OnTabPressed", function() UI.TabKey(IsShiftKeyDown()) end)
		edit:SetScript("OnKeyUp", function(_, key) if key == "TAB" then UI.tabHeld = nil end end)
		edit:SetScript("OnKeyDown", function(_, key)
			-- the reminder after Ctrl+V / Ctrl+C goes with the next key (the paste or copy itself)
			if UI.clipHint and key ~= "LCTRL" and key ~= "RCTRL" then
				UI.clipHint = nil
				C_Timer.After(0, function() UI:SetStatus(); UI:UpdateGhost() end)
			end
			if key == "TAB" then UI.tabHeld = GetTime() end
			if key == "`" then
				UI.TickKey() -- (bindings don't fire while the box has focus, so the toggle key closes it here)
			else
				UI.ListKey(key, IsControlKeyDown())
			end
		end)
	end

	--- The text measurer, the cursor's frame above the text box, the click area over the prompt. Gives the box's
	--- frame level (the spinner goes above it).
	local function BuildCaretParts()
		measure = frame:CreateFontString(nil, "OVERLAY")
		measure:SetFontObject(Theme.fonts.input)
		measure:SetAlpha(0)
		UI.measure = measure

		-- the cursor lives in a frame above the text box, so a box cursor can cover the letter under it
		-- (which is then drawn again on top, in a colour that reads on the box)
		caretFrame = CreateFrame("Frame", nil, frame)
		caretFrame:SetAllPoints(edit)
		local lvl = edit:GetFrameLevel()
		caretFrame:SetFrameLevel((type(lvl) == "number" and lvl or 1) + 2)
		-- clicks and drags on the prompt move Terminal's own cursor (the real text box stays for Ctrl+C/V)
		hit = CreateFrame("Frame", nil, frame)
		hit:SetAllPoints(edit)
		hit:SetFrameLevel((type(lvl) == "number" and lvl or 1) + 1)
		hit:EnableMouse(true)
		hit:Hide()
		hit:SetScript("OnMouseDown", function(_, button) if button == nil or button == "LeftButton" then UI:PressPrompt() end end)
		hit:SetScript("OnMouseUp", function() UI:ReleasePrompt() end)
		UI.hit = hit
		return lvl
	end

	--- The spinner at the end of the prompt.
	local function BuildBusy(lvl)
		-- a ring of dots at the end of the prompt while something is still loading; mouse-over says what
		busy = CreateFrame("Frame", nil, frame)
		busy:SetSize(22, 22)
		busy:SetFrameLevel((type(lvl) == "number" and lvl or 1) + 3)
		busy:EnableMouse(true)
		busy:Hide()
		busy.dots = {}
		for i = 1, BUSY_DOTS do
			local d = busy:CreateTexture(nil, "OVERLAY")
			local a = (i - 1) / BUSY_DOTS * 2 * math.pi
			d:SetSize(4, 4)
			d:SetPoint("CENTER", busy, "CENTER", math.cos(a) * 7, math.sin(a) * 7)
			busy.dots[i] = d
		end
		busy:SetScript("OnUpdate", function(self, elapsed) UI:SpinBusy(elapsed) end)
		busy:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
			GameTooltip:SetText("Still loading", 1, 1, 1)
			for _, l in ipairs(self.lines or {}) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8, true) end
			GameTooltip:Show()
		end)
		busy:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		UI.busy = busy
	end

	--- The cursor and its letter, the coloured copy of the text, the selection, the faint suggestion.
	local function BuildPromptText()
		caret = caretFrame:CreateTexture(nil, "ARTWORK")
		caret:SetWidth(2)
		caret:Hide()
		caretChar = caretFrame:CreateFontString(nil, "OVERLAY")
		caretChar:SetFontObject(Theme.fonts.input)
		caretChar:SetJustifyH("LEFT")
		caretChar:SetWordWrap(false)
		caretChar:Hide()
		UI.caret = caret
		UI.caretChar = caretChar
		-- what's typed, coloured by what it is (UI:Highlighted), over the text box's own text (made
		-- invisible while this shows). It lives in the click frame, which shows only while the prompt is
		-- drawn by Terminal: above the box's text and the selection band, below the cursor.
		syntax = hit:CreateFontString(nil, "ARTWORK")
		syntax:SetFontObject(Theme.fonts.input)
		syntax:SetJustifyH("LEFT")
		syntax:SetWordWrap(false)
		syntax:SetPoint("LEFT", edit, "LEFT", 0, 0)
		syntax:Hide()
		UI.syntax = syntax
		-- the selected part of the query, behind the (child frame's) text
		selText = frame:CreateTexture(nil, "BORDER", nil, 1)
		selText:Hide()
		UI.selText = selText

		-- the rest of the suggested completion, faint, right after what's typed (Tab takes it)
		ghost = frame:CreateFontString(nil, "OVERLAY")
		ghost:SetFontObject(Theme.fonts.input)
		ghost:SetJustifyH("LEFT")
		ghost:SetWordWrap(false)
		ghost:Hide()
		UI.ghost = ghost
	end

	--- The selection band, the divider, the prompt's background.
	local function BuildListParts()
		-- the selected row: a soft band with a bright edge that glides between rows
		selBar = frame:CreateTexture(nil, "BORDER", nil, 2)
		selEdge = frame:CreateTexture(nil, "ARTWORK")
		selEdge:SetWidth(2)
		selBar:Hide(); selEdge:Hide()
		UI.selBar = selBar
		UI.selEdge = selEdge

		divider = frame:CreateTexture(nil, "ARTWORK")
		divider:SetHeight(1)
		UI.divider = divider
		-- the prompt's own background, behind the query box (Theme promptBg)
		promptBg = frame:CreateTexture(nil, "BORDER")
		UI.promptBg = promptBg
	end

	--- What Terminal draws over and around the prompt: the cursor, the click area, the spinner, the coloured
	--- copy of the text, the selection, the faint suggestion, the selection band, the divider, the prompt's background.
	local function BuildPromptParts()
		local lvl = BuildCaretParts()
		BuildBusy(lvl)
		BuildPromptText()
		BuildListParts()
	end

	--- The result rows.
	local function BuildRows()
		for i = 1, MAX_ROWS do
			local b = CreateFrame("Button", nil, frame)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetPoint("LEFT", 6, 0)
			b.kind = b:CreateFontString(nil, "OVERLAY")
			b.kind:SetFontObject(Theme.fonts.small)
			b.kind:SetPoint("RIGHT", -8, 0)
			b.kind:SetWidth(80)
			b.kind:SetJustifyH("RIGHT")
			b.detail = b:CreateFontString(nil, "OVERLAY")
			b.detail:SetFontObject(Theme.fonts.small)
			b.detail:SetPoint("RIGHT", b.kind, "LEFT", -8, 0)
			b.detail:SetJustifyH("RIGHT")
			b.detail:SetWordWrap(false)
			b.label = b:CreateFontString(nil, "OVERLAY")
			b.label:SetFontObject(Theme.fonts.row)
			b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
			b.label:SetPoint("RIGHT", b.detail, "LEFT", -8, 0)
			b.label:SetJustifyH("LEFT")
			b.label:SetWordWrap(false)
			if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
			b:SetScript("OnClick", function(_, button)
				if UI.closing then return end -- fading out: already done
				UI.sel = UI.offset + i
				if button == "RightButton" then return UI:ShowRowMenu(UI.sel) end
				UI:Activate(UI.sel, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
			end)
			b:SetScript("OnEnter", function()
				if UI.closing then return end
				if UI.results[UI.offset + i] and UI.sel ~= UI.offset + i then
					if UI.armedEntry then UI:Disarm() end
					UI.sel = UI.offset + i
					UI:SelectionChanged()
				end
				UI:PlaceCatcher(i)
			end)
			b:Hide()
			rows[i] = b
		end
	end

	--- The footer: a faint rule, the result count on the left, key hints on the right, both centred on one line.
	local function BuildFooter()
		footLine = frame:CreateTexture(nil, "ARTWORK")
		footLine:SetHeight(1)
		UI.footLine = footLine
		status = frame:CreateFontString(nil, "OVERLAY")
		status:SetFontObject(Theme.fonts.small)
		status:SetJustifyH("LEFT")
		status:SetWordWrap(false)
		UI.status = status
		hints = frame:CreateFontString(nil, "OVERLAY")
		hints:SetFontObject(Theme.fonts.small)
		hints:SetJustifyH("RIGHT")
		hints:SetWordWrap(false)
		UI.hints = hints
	end

	Build = function()
		if frame then return end
		BuildFrame()
		BuildEdit()
		BuildPromptParts()
		BuildRows()
		BuildFooter()
		UI:ApplyTheme()
	end
end

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------

--- The layout numbers, from the theme (every file reads them through UI.layout).
local function ApplyLayout(t)
	L.ROWS = math.max(1, math.min(MAX_ROWS, t.rows))
	L.ROW_H = math.max(22, t.fontSize + 12)
	L.HEADER_H = math.max(50, t.fontSize + 36)
	L.LINE_H = t.fontSize + 6
	UI.linesKey = nil -- (fonts changed: the prompt's lines are measured again)
end

--- The footer's line, the result count and the key hints, placed for the font size.
local function ApplyFooterLayout(t)
	-- footer: always one line (hints that don't fit are left out, see FitHints)
	local footerH = math.max(FOOTER_H, t.fontSize + 12)
	UI.footerH = footerH
	local classicInset = t.frame == "classic" and 5 or 1
	footLine:ClearAllPoints()
	footLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", classicInset + 6, footerH)
	footLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -classicInset - 6, footerH)
	status:ClearAllPoints()
	status:SetPoint("LEFT", frame, "BOTTOMLEFT", 14, footerH / 2)
	hints:ClearAllPoints()
	hints:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -14, footerH / 2)
end

--- The frame's border and colours, the divider, the prompt's background, the fuzzy-finding glow.
local function ApplyFrameStyle(t)
	-- the frame: the game's own tooltip border (tinted, e.g. bronze) or a thin flat line
	local classic = t.frame == "classic"
	if frame._frameStyle ~= t.frame then
		frame._frameStyle = t.frame
		frame:SetBackdrop(classic and {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		} or {
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})
	end
	local r, g, b = Theme.RGB(t.bg)
	frame:SetBackdropColor(r, g, b, t.bgAlpha)
	r, g, b = Theme.RGB(t.border)
	frame:SetBackdropBorderColor(r, g, b, 1)
	divider:SetColorTexture(r, g, b, 1)
	local pr, pg, pb = Theme.RGB(t.promptBg or t.bg)
	promptBg:SetColorTexture(pr, pg, pb, t.bgAlpha)
	if UI.fzf then UI:ShowGlow(true) else UI:ColorGlow() end -- (a glow style or colour changed while it shows)
end

--- The prompt's label and the query box after it, the spinner, the typed text's colours.
local function ApplyPromptTheme(t)
	-- prompt, then the query box right after it
	local mid = -(L.HEADER_H - 4) / 2
	promptFS:SetText("|cff" .. t.prompt .. t.promptText:gsub("|", "||") .. "|r")
	promptFS:ClearAllPoints()
	promptFS:SetPoint("LEFT", frame, "TOPLEFT", 14, mid)
	local pw = promptFS:GetStringWidth() or 10
	UI.editLeft, UI.editMid = 14 + pw + 8, mid
	UI:PlaceEdit()
	edit:SetHeight(t.fontSize + 14)
	busy:ClearAllPoints()
	busy:SetPoint("RIGHT", frame, "TOPRIGHT", -12, mid)
	for _, d in ipairs(busy.dots) do d:SetColorTexture(Theme.RGB(t.accent)) end
	local tr, tg, tb = Theme.RGB(t.text)
	edit:SetTextColor(tr, tg, tb)
	UI.syntaxKey, UI.syntaxOn = nil, nil -- (colours changed: drawn again)
	UI:UpdateSyntax()
end

--- The caret, the selection in the prompt, the selection band, the faint suggestion.
local function ApplyCaretTheme(self, t)
	local ar, ag, ab = Theme.RGB(t.accent)
	caret:SetColorTexture(ar, ag, ab, 1)
	caret:SetHeight(t.fontSize + 5)
	UI.onAccent = Theme.OnColor(t.accent, t.bg)
	if UI.keys then UI:UpdateCaret() end
	selText:SetColorTexture(ar, ag, ab, 0.38)
	for _, band in ipairs(UI.selBands) do band:SetColorTexture(ar, ag, ab, 0.38) end
	selBar:SetColorTexture(ar, ag, ab, 0.16)
	selEdge:SetColorTexture(ar, ag, ab, 0.9)
	local gr, gg, gb = Theme.RGB(t.dim)
	ghost:SetTextColor(gr, gg, gb, 0.75)
	self.selY = nil -- re-place the selection band for the new layout
end

--- The rows (sizes, colours, places), the footer's colours and key hints.
local function ApplyRowsTheme(self, t)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	for i = 1, MAX_ROWS do
		local row = rows[i]
		row:SetHeight(L.ROW_H)
		row.slide = nil
		row.icon:SetSize(L.ROW_H - 6, L.ROW_H - 6)
		row.detail:SetWidth(math.floor(t.width * 0.3))
		row.label:SetTextColor(tr, tg, tb)
		row.detail:SetTextColor(dr, dg, db)
		if i > L.ROWS then row:Hide() end
	end
	self:LayoutHeader() -- (the divider, the prompt's background, the rows' places, the click area)
	status:SetTextColor(dr, dg, db)
	hints:SetTextColor(dr, dg, db)
	local lr, lg, lb = Theme.RGB(t.border)
	footLine:SetColorTexture(lr, lg, lb, 0.35)
	self.hintsRoom = nil -- fonts and colours may have changed: measure the hints again
	self:FitHints()
end

function UI:ApplyTheme()
	if not frame then return end
	local t = Theme.Get()
	Theme.ApplyFonts()

	ApplyLayout(t)
	ApplyFooterLayout(t)
	frame:SetWidth(t.width)
	self.snapNext = true -- a new layout: no growing into it
	self:FitHeight()
	frame:SetScale(t.scale)

	ApplyFrameStyle(t)
	ApplyPromptTheme(t)
	ApplyCaretTheme(self, t)
	ApplyRowsTheme(self, t)

	Fuzzy.matchColor = "|cff" .. t.match
	UI.offset = math.max(0, math.min(UI.offset, #UI.results - L.ROWS))
	self:ForgetTooltip() -- (its colours changed too: drawn again)
	self:Render()
	self.snapNext = false
	self:UpdateCaret()
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

--- Open (closing counts as closed: the fade-out is only for the eye).
function UI:IsShown() return frame and frame:IsShown() and not self.closing or false end

function UI:Hide()
	self:HideRowMenu()
	self:HideCatcher() -- (also when the game closed the terminal first: no catcher left over an empty spot)
	UI.HideNav()
	self.clipHint = nil -- (the Ctrl+V / Ctrl+C reminder doesn't outlive the terminal)
	if not frame or not frame:IsShown() or self.closing then return end
	self:Disarm()
	self:HideTooltip()
	edit:ClearFocus()
	-- the search to bring back with Down on the next open (only a search: not a .command or /slash)
	local typed = edit:GetText()
	if typed:find("%S") and self.mode == "search" and not self.fzf then
		self.lastQuery = typed
		self.lastCategory = not self.categoryAuto and self.category or nil
	end
	self:EndAdvancedOnce()
	self:EndFuzzy()
	self.openedByToggle, self.tabHeld = nil, nil -- (closed, Tab's key-up isn't seen: it isn't trusted as held after)
	self.histIdx = nil
	Forget(self) -- (rows kept only for the next keystroke)
	-- let go of the keyboard at once, so the next key already reaches the game
	LetGo()
	if busy and busy:IsShown() then busy:Hide() end
	ghost:Hide()
	if self:Animated() then
		self:StartClose()
	else
		frame:Hide()
	end
end

--- Gone at once, without the closing animation (something else takes its place: .atop).
function UI:HideNow()
	self:Hide()
	if frame and frame:IsShown() then
		self.phase, self.closing = nil, false
		frame:Hide()
		self:MotionReset()
	end
end

function UI:Open(text)
	Build()
	self:Disarm()
	self.histIdx = nil
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		-- (a number: only when the list is older than that many seconds; the loot and combat logs' "5 min ago")
		local r = p.refreshOnOpen
		if r == true or (type(r) == "number" and GetTime() - (p._collectedAt or -1e9) >= r) then p._dirty = true end
	end
	ns.Highlight:Clear()
	local reopening = self.closing
	self.closing = false
	self.category, self.categoryAuto = nil, nil -- (each time it opens: no category yet, nothing listed)
	if ns.Easy then ns.Easy.NextExample() end -- (another example in the empty prompt each time)
	self.showRecent, self.recalled = nil, nil
	-- the last search's rows are gone before the frame shows: it opened at their height and only
	-- then collapsed to the bare prompt, seen for a moment on every reopen (and reopened while
	-- still fading out, the fading rows go at once too)
	UI.results, UI.sel, UI.offset = {}, 1, 0
	self.searchJob, self.mode, self.sendTo = nil, "search", nil
	self.snapNext = true
	self:FitHeight(text or "")
	frame:Show()
	self:StartOpen(reopening)
	self.snapNext = true -- opens at the right size; it grows and shrinks from there
	self.opening = true -- (the rows still come in with the style)
	-- SetText searches (OnTextChanged) only if the text changed, and the game may report that
	-- change a frame later (by then not snapping: the glide was the flash): search now unless it
	-- already happened (a second search in the same frame would be queued for the next one)
	local want = text or ""
	local before = self.refreshCount
	if edit:GetText() ~= want then edit:SetText(want) end
	if self.refreshCount == before then self:Research() end
	self.cursor = #edit:GetText()
	self.snapNext, self.opening = false, false
	if not self:EnterKeys() then
		-- plain text box: focus next frame so the opening keypress isn't typed into it
		C_Timer.After(0, function()
			if UI:IsShown() and not UI.keys then edit:SetFocus() end
		end)
	end
	self:UpdateCaret()
end

function UI:Toggle()
	if self:IsShown() then return self:Hide() end
	-- Tab+` (the game sees the toggle key; Tab held): opens in pure fuzzy finding
	if self:TabDown() then return self:FuzzyOnce() end
	self:Open()
	self.openedByToggle = GetTime() -- (Tab let go just after, nothing typed: it was Tab+`, TabReleased)
end

local ns = select(2, ...)
local L = ns.L

-- The prompt Terminal draws over the game's text box out of combat: the query set and measured, wrapped onto more
-- lines when long, the caret and the selection, mouse clicks and drags on it, the loading spinner at its end, and the
-- colours of what's typed. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local LY = UI.layout
local EasyOn, Wake, NextPos, BUSY_DOTS = UI.EasyOn, UI.Wake, UI.NextPos, UI.BUSY_DOTS

local MAX_LINES = 8 -- a long prompt wraps onto more lines (the header grows down)

----------------------------------------------------------------------
-- Undo in the prompt (0.66.1, the player): Ctrl+Z undoes the last edit to what's typed, Ctrl+Y (or Ctrl+Shift+Z) redoes
-- it. A run of typed letters is one edit (a word at a time, as editors do: a space starts the next), as is a run of
-- Backspaces; Ctrl+W, Ctrl+U, Ctrl+Backspace, a paste, a completion, Alt+` writing the line out are each one. Kept while
-- the terminal is open, for the prompt it shows (a new run or another tab starts afresh).
----------------------------------------------------------------------
UI.UNDO_MAX = 100 -- edits kept to undo
UI.UNDO_RUN = 1.5 -- seconds between keys that still make one run of typing
local undo = { back = {}, fwd = {} }

--- Nothing to undo or redo (the terminal opened, another tab).
function UI:ResetUndo()
	undo.back, undo.fwd, undo.run, undo.runAt, undo.runPos = {}, {}, nil, nil, nil
	undo.seen = UI.edit and UI.edit:GetText() or nil
end

--- How `new` differs from `old`: "type" (one character typed), "erase" (one taken away), or nil (more); whether it
--- starts a new run all the same (a space after a word); where in the line it was, and where the caret is after it.
local function EditKind(old, new)
	local dn = #new - #old
	if dn > 0 and dn <= 4 then
		-- (one character, UTF-8: up to 4 bytes; typed where the caret was)
		local c = UI.cursor or #old
		if new:sub(1, c) == old:sub(1, c) and new:sub(c + 1 + dn) == old:sub(c + 1) then
			local ch = new:sub(c + 1, c + dn)
			-- (a space after a word starts the next run: undone, the word stays)
			if dn == 1 and ch == " " then return "type", c > 0 and old:sub(c, c) ~= " ", c, c + dn end
			if dn == 1 or ch:find("^[\192-\247][\128-\191]+$") then return "type", nil, c, c + dn end
		end
	elseif dn < 0 and dn >= -4 then
		-- (one character taken away: Backspace or Delete, not Ctrl+W's word)
		local p = 0
		while p < #new and new:byte(p + 1) == old:byte(p + 1) do p = p + 1 end
		if p > 0 and old:byte(p) >= 192 and old:byte(p) <= 247 then p = p - 1 end -- (a multi-byte character's start)
		if new:sub(p + 1) == old:sub(p + 1 - dn) then
			local ch = old:sub(p + 1, p - dn)
			if #ch == 1 or ch:find("^[\192-\247][\128-\191]+$") then return "erase", nil, p, p end
		end
	end
end

--- The prompt about to change from `old` (caret `cursor`) to `new`: kept to undo, unless it continues a run of typing or
--- erasing.
local function Remember(old, cursor, new)
	local kind, breaks, at, after = EditKind(old, new)
	local now = GetTime()
	undo.fwd = {} -- (a new edit: what was undone can't come back)
	-- (and where the run left off: typing somewhere else, after Home, is an edit of its own; review. Erasing goes on at
	-- the caret, Delete, or a character before it, Backspace)
	local here = undo.runPos and at and (at == undo.runPos or (kind == "erase" and at < undo.runPos and at >= undo.runPos - 4))
	if kind and not breaks and here and undo.run == kind and undo.runAt and now - undo.runAt <= UI.UNDO_RUN then
		undo.runAt, undo.runPos = now, after
		return
	end
	undo.run, undo.runAt, undo.runPos = kind, now, after
	local back = undo.back
	back[#back + 1] = { text = old, cursor = cursor }
	if #back > UI.UNDO_MAX then table.remove(back, 1) end
end

--- The game's own text box changed (a paste: Ctrl+V hands over to it; typing in combat): kept to undo as an edit, as
--- the drawn prompt's are (SetQuery's own changes were seen already).
function UI:NoteBoxText(text)
	if self.undoing or type(text) ~= "string" then return end
	local old = undo.seen
	undo.seen = text
	if old and old ~= text then Remember(old, math.min(self.cursor or #old, #old), text) end
end

--- Ctrl+Z (dir -1) / Ctrl+Y (dir 1): the prompt as it was before the last edit, or again after it. False when there's
--- nothing to undo or redo.
function UI:UndoEdit(dir)
	local from, to = undo.back, undo.fwd
	if dir > 0 then from, to = undo.fwd, undo.back end
	local s = table.remove(from)
	if not s then return false end
	to[#to + 1] = { text = UI.edit:GetText(), cursor = self.cursor }
	undo.run, undo.runAt, undo.runPos = nil, nil, nil -- (typing after an undo is an edit of its own)
	self.undoing = true
	self:SetQuery(s.text, s.cursor)
	self.undoing = nil
	return true
end

--- How many edits can be undone and redone (the tests).
function UI:UndoDepth() return #undo.back, #undo.fwd end

function UI:SetQuery(text, cursor)
	local edit = UI.edit
	if not self.undoing and edit:GetText() ~= text then Remember(edit:GetText(), self.cursor or #edit:GetText(), text) end
	undo.seen = text -- (the box's change this makes: not an edit of its own, NoteBoxText)
	self.anchor = nil -- typing, completing or clearing drops any selection
	self.typedAt = GetTime()
	self.cursor = math.max(0, math.min(cursor or #text, #text))
	if edit:GetText() ~= text then
		edit:SetText(text) -- OnTextChanged -> Refresh, UpdateCaret
	else
		self:UpdateCaret()
	end
end

-- the text cursor: a line or a box (the character under it is redrawn in a colour that reads
-- on the box), steady or blinking
local CURSORS = {
	["blinking-line"] = { box = false, blink = true },
	["solid-line"] = { box = false, blink = false },
	["blinking-box"] = { box = true, blink = true },
	["solid-box"] = { box = true, blink = false },
}
local function CursorStyle() return CURSORS[Theme.Get().cursor] or CURSORS["blinking-line"] end
UI.CursorStyle = CursorStyle

--- The selected part of the query as byte positions (lo, hi), or nil. The drawn prompt keeps
--- its own selection: `anchor` is where it started, the caret is where it ends.
function UI:SelRange()
	local edit = UI.edit
	local a, c = self.anchor, self.cursor
	if not (a and c) or a == c or not edit then return nil end
	local n = #edit:GetText()
	a, c = math.min(a, n), math.min(c, n)
	if a == c then return nil end
	if a < c then return a, c end
	return c, a
end

local function Width(str)
	local measure = UI.measure
	measure:SetText((str:gsub("|", "||")))
	return measure:GetStringWidth() or 0
end

local function LineRoom() return (UI.edit:GetWidth() or 400) - 2 end

--- The prompt's lines: { first byte, last byte } each. Text wider than the box wraps (only while
--- Terminal draws the prompt; the real text box scrolls its one line): after the last space that
--- fits, or inside a word too long for a line. Cached for the text and the box's width.
function UI:PromptLines()
	local edit = UI.edit
	local text = ns.MaskSecret(edit:GetText() or "")
	local room = LineRoom()
	local key = text .. "\0" .. room .. "\0" .. tostring(self.keys)
	if self.linesKey == key and self.lines then return self.lines end
	self.linesKey = key
	local lines = {}
	if not self.keys or text == "" or Width(text) <= room then
		lines[1] = { 1, #text }
	else
		local ends = {} -- where each character ends (bytes), for a binary search per line
		local p = 0
		while p < #text do p = NextPos(text, p); ends[#ends + 1] = p end
		local first, ci = 1, 1 -- the line's first byte, and the index in `ends` of its first character
		while first <= #text do
			if #lines == MAX_LINES - 1 then lines[#lines + 1] = { first, #text } break end
			local lo, hi, fit = ci, #ends, ci -- the most characters from ci that fit (at least one)
			while lo <= hi do
				local mid = math.floor((lo + hi) / 2)
				if Width(text:sub(first, ends[mid])) <= room then fit, lo = mid, mid + 1 else hi = mid - 1 end
			end
			local e = ends[fit]
			if e < #text then
				if text:sub(e + 1, e + 1) == " " then
					e = e + 1 -- (the space after the last word that fits stays on this line)
				else
					local k = e
					while k > first and text:sub(k, k) ~= " " do k = k - 1 end
					if k > first then e = k end -- after the last space; a word too long for a line is split
				end
			end
			lines[#lines + 1] = { first, e }
			first = e + 1
			while ci <= #ends and ends[ci] < first do ci = ci + 1 end
		end
	end
	self.lines = lines
	return lines
end

--- Where the caret goes after `pos` bytes: x along its line, y down from the first line, the line.
function UI:PromptXY(pos)
	local edit = UI.edit
	local text = ns.MaskSecret(edit:GetText() or "")
	local lines = self:PromptLines()
	local i = 1
	for k = 2, #lines do
		if lines[k][1] - 1 <= pos then i = k else break end
	end
	local first = lines[i][1]
	local x = pos >= first and Width(text:sub(first, pos)) or 0
	return math.min(x, LineRoom()), -(i - 1) * LY.LINE_H, i
end

local selBands = {} -- the selection on lines after its first (selText is the first)
local function SelBand(k)
	local frame = UI.frame
	local band = selBands[k]
	if not band then
		band = frame:CreateTexture(nil, "BORDER", nil, 1)
		local ar, ag, ab = Theme.RGB(Theme.Get().accent)
		band:SetColorTexture(ar, ag, ab, 0.38)
		selBands[k] = band
	end
	return band
end
UI.selBands = selBands

--- The selection band(s), from where the selection started to the (gliding) caret.
function UI:PlaceTextSel()
	local edit, selText = UI.edit, UI.selText
	if not selText then return end
	for _, band in ipairs(selBands) do band:Hide() end
	local lo, hi = self:SelRange()
	if not (self.keys and self:IsShown() and self.anchorX and lo) then
		selText:Hide()
		return
	end
	local h = Theme.Get().fontSize + 5
	local x1, y1, i1 = self:PromptXY(lo)
	local x2, _, i2 = self:PromptXY(hi)
	if i1 == i2 then
		x1, x2 = self.anchorX, self.caretX or self.caretTo or 0 -- (one line: its caret end glides)
		if x1 > x2 then x1, x2 = x2, x1 end
		selText:ClearAllPoints()
		selText:SetPoint("LEFT", edit, "LEFT", x1, y1)
		selText:SetSize(math.max(1, x2 - x1), h)
		selText:Show()
		return
	end
	local text, lines = ns.MaskSecret(edit:GetText() or ""), self.lines
	for i = i1, i2 do
		local band = i == i1 and selText or SelBand(i - i1)
		local from = i == i1 and x1 or 0
		local to = i == i2 and x2 or math.min(Width(text:sub(lines[i][1], lines[i][2])), LineRoom())
		band:ClearAllPoints()
		band:SetPoint("LEFT", edit, "LEFT", from, -(i - 1) * LY.LINE_H)
		band:SetSize(math.max(3, to - from), h)
		band:Show()
	end
end

function UI:UpdateCaret()
	local edit, caret, caretChar, hit, selText, measure = UI.edit, UI.caret, UI.caretChar, UI.hit, UI.selText, UI.measure
	if not caret then return end
	if hit then hit:SetShown(self.keys and self:IsShown() and true or false) end
	if not (self.keys and self:IsShown()) then
		self.dragging = false
		caret:Hide()
		caretChar:Hide()
		if selText then selText:Hide() end
		for _, band in ipairs(selBands) do band:Hide() end
		self:SetPromptExtra(0) -- (the real text box: one scrolling line)
		self:UpdateGhost()
		self:UpdateSyntax()
		return
	end
	local text = ns.MaskSecret(edit:GetText() or "")
	self:SetPromptExtra((#self:PromptLines() - 1) * LY.LINE_H)
	local x, y = self:PromptXY(self.cursor)
	if y ~= self.caretY then self.caretX = nil end -- (to another line: no gliding across)
	self.caretTo, self.caretY = x, y
	self.anchorX = self:SelRange() and (self:PromptXY(self.anchor)) or nil
	local st = CursorStyle()
	-- a box covers the character at the caret (or the first letter of the suggestion at the
	-- end); that character is drawn again on top, in a colour that reads on the box
	local ch, dimmed
	if st.box then
		if self.cursor < #text then
			ch = text:sub(self.cursor + 1, NextPos(text, self.cursor))
		else
			local add = self:Suggestion()
			if add then ch, dimmed = add:sub(1, NextPos(add, 0)), true end
		end
		measure:SetText(((ch and ch ~= "" and ch or "0"):gsub("|", "||")))
		self.caretW = math.max(6, math.min(measure:GetStringWidth() or 8, 40))
		local r, g, b = Theme.RGB(self.onAccent or "000000")
		caretChar:SetText(ch and ((ch:gsub("|", "||"))) or "")
		caretChar:SetTextColor(r, g, b, dimmed and 0.8 or 1)
	end
	self.caretCh = st.box and ch or nil
	caret:SetWidth(st.box and self.caretW or 2)
	self.typedAt = GetTime() -- a moving caret stays solid; it blinks again once idle
	if not (self:Animated() and caret:IsShown() and self.caretX) then
		self.caretX = self.caretTo
	end
	self:PlaceCaret()
	caret:Show()
	caret:SetAlpha(1)
	caretChar:SetAlpha(1)
	self:PlaceTextSel()
	if self:Animated() or st.blink then Wake() end
	self:UpdateGhost()
	self:UpdateSyntax()
end

--- Put the cursor (and, for a box, its character) at the caret's current x.
function UI:PlaceCaret()
	local edit, caret, caretChar = UI.edit, UI.caret, UI.caretChar
	local x, y = self.caretX or self.caretTo or 0, self.caretY or 0
	self.caretPlaced = x
	caret:ClearAllPoints()
	caret:SetPoint("LEFT", edit, "LEFT", x, y)
	if self.caretCh and self.caretCh ~= "" and CursorStyle().box then
		caretChar:ClearAllPoints()
		caretChar:SetPoint("LEFT", edit, "LEFT", x, y)
		caretChar:Show()
	else
		caretChar:Hide()
	end
end

--- Where the mouse is along the prompt text, in the text's own units.
local function PromptX()
	local edit = UI.edit
	local cx = GetCursorPosition and GetCursorPosition()
	local scale, left = edit:GetEffectiveScale(), edit:GetLeft()
	if type(cx) ~= "number" or type(left) ~= "number" or type(scale) ~= "number" or scale == 0 then return 0 end
	return cx / scale - left
end

--- Where the mouse is down from the first line's middle, in the text's own units.
local function PromptY()
	local edit = UI.edit
	local cy
	if GetCursorPosition then cy = select(2, GetCursorPosition()) end -- (not `x and f()`: that keeps one value, the x)
	local scale = edit:GetEffectiveScale()
	local _, mid = edit:GetCenter()
	if type(cy) ~= "number" or type(mid) ~= "number" or type(scale) ~= "number" or scale == 0 then return 0 end
	return mid - cy / scale
end

--- The caret position (in bytes) nearest to the mouse: its line, then along it.
local function IndexAt(x, down)
	local edit = UI.edit
	local text = ns.MaskSecret(edit:GetText() or "")
	local lines = UI:PromptLines()
	local i = math.max(1, math.min(#lines, 1 + math.floor((down or 0) / LY.LINE_H + 0.5)))
	local first, last = lines[i][1], lines[i][2]
	local best, bestD, pos = first - 1, math.abs(x), first - 1
	while pos < last do
		pos = NextPos(text, pos)
		local w = Width(text:sub(first, pos))
		local d = math.abs(x - w)
		if d < bestD then best, bestD = pos, d end
		if w >= x then break end
	end
	-- the end of a wrapped line is the next line's start: stay on this one, before its space
	if i < #lines and best == last and text:sub(last, last) == " " then best = last - 1 end
	-- (a password's *s are a * a byte: a click between two of one letter's goes before the letter, never inside it,
	-- where typing would split it and the key made from it wouldn't match a friend's. Review, 0.58.16)
	local real = edit:GetText() or ""
	while best > 0 and best < #real do
		local b = real:byte(best + 1)
		if not b or b < 128 or b >= 192 then break end
		best = best - 1
	end
	return best
end
UI.PromptIndexAt = IndexAt -- (the tests)

--- Mouse down on the prompt: the cursor goes there (shift extends the selection); dragging
--- selects. The prompt stays Terminal's own, so the chosen cursor style stays too.
function UI:PressPrompt()
	local edit, hit = UI.edit, UI.hit
	if not (self.keys and edit) then return end
	local idx = IndexAt(PromptX(), PromptY())
	if IsShiftKeyDown() then
		self.anchor = self.anchor or self.cursor
	else
		self.anchor = idx
	end
	self.cursor = idx
	self.dragging = true
	if hit then hit:SetScript("OnUpdate", function() UI:DragPrompt() end) end -- only while dragging
	self:UpdateCaret()
end

function UI:DragPrompt()
	local hit = UI.hit
	if not (self.dragging and self.keys) then -- the drag ended some other way (closed, focus): stop watching
		if hit then hit:SetScript("OnUpdate", nil) end
		return
	end
	local idx = IndexAt(PromptX(), PromptY())
	if idx ~= self.cursor then
		self.cursor = idx
		self:UpdateCaret()
	end
end

function UI:ReleasePrompt()
	local hit = UI.hit
	self.dragging = false
	if hit then hit:SetScript("OnUpdate", nil) end
	if self.anchor == self.cursor then self.anchor = nil end
	self:UpdateCaret()
end

----------------------------------------------------------------------
-- Still loading: providers say so with `busy` (Syndicator scanning, AtlasLoot or Questie being
-- indexed, item names on their way); a spinner at the end of the prompt shows it.
----------------------------------------------------------------------

--- What is still loading, one line per provider that says so.
function UI:BusyLines()
	local out, who = {}, {}
	-- (a background search: the list shown is the whole last one, not a best-so-far; review, 0.51.25)
	if self.searchJob and not self.searchJob.quiet then out[1] = L["Searching... (the best matches so far are shown)"] end
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if p.busy then
			local ok, msg = pcall(p.busy, p)
			if ok and type(msg) == "string" and msg ~= "" then
				out[#out + 1] = msg
				who[id] = true
			end
		end
	end
	return out, who
end

--- The query box: room for the spinner is always kept at its end (resizing it as the spinner
--- came and went made the game report the text as changed).
function UI:PlaceEdit()
	local frame, edit = UI.frame, UI.edit
	if not (edit and self.editLeft) then return end
	edit:ClearAllPoints()
	edit:SetPoint("LEFT", frame, "TOPLEFT", self.editLeft, self.editMid)
	edit:SetPoint("RIGHT", frame, "TOPRIGHT", -38 - (self.badgeRoom or 0), self.editMid)
end

----------------------------------------------------------------------
-- Badges: small icons at the end of the prompt, left of the spinner, each with a tooltip (0.58.6: Terminal: Share's
-- connection, the player's "a little wifi icon at the very end of the Terminal prompt box"). Another addon adds one:
--   Terminal.UI.AddBadge({ id = "x", draw = function(f) ... end, shown = function() return true end,
--       refresh = function(f) ... end, tooltip = function(t) t:SetText(...) end })
-- draw(f) once on its 22x22 frame; shown() whether it shows now; refresh(f) each time they're placed (its colours);
-- tooltip(t) fills its pop-out on mouse-over. fade = seconds: then it fades to a faint mark, back on mouse-over or
-- UI.WakeBadge(id) (0.58.9, the player: "fade to low opacity after some seconds and re-appear on mouse-over").
-- UI:PlaceBadges() when what they show changed.
----------------------------------------------------------------------

UI.badges = {}
local BADGE_W = 22
local FADED = 0.2 -- (a faded badge's opacity)

function UI.AddBadge(def)
	for i, d in ipairs(UI.badges) do
		if d.id == def.id then table.remove(UI.badges, i) break end
	end
	UI.badges[#UI.badges + 1] = def
	if UI.frame then UI:PlaceBadges() end
end

-- A badge's pop-out: a tooltip of Terminal's own (the game's GameTooltip is anyone's: another addon's or the game's
-- own redraw took it over, and .zen fades it), out to the right of the badge, drawn again every second while it's up
-- (what it says changes: a friend connects, their items come in). Hover shows it; a click keeps it up until the next.
local badgeTip
local function BadgeTip()
	if not badgeTip then
		badgeTip = CreateFrame("GameTooltip", "TerminalBadgeTip", UIParent, "GameTooltipTemplate")
		badgeTip:SetFrameStrata("TOOLTIP")
		if ns.Zen and ns.Zen.Made then ns.Zen.Made(badgeTip) end
	end
	return badgeTip
end
UI.BadgeTip = BadgeTip

-- (0.58.10, the player's screenshot: the pop-out and the selected row's tooltip on top of each other) The pop-out takes
-- the row tooltip's place beside the terminal (UI.PlaceTip), and the row's waits until it's put away (UI.badgeTipUp).
--- A badge's per-frame work (its pop-out drawn again, its fading) started again, when it isn't running.
local function Tick(f)
	if f.tick and not f.ticking then
		f.ticking = true
		f:SetScript("OnUpdate", f.tick)
	end
end

local function DrawTip(f, def)
	local t = BadgeTip()
	if not (t and def.tooltip) then return end
	if not UI.badgeTipUp then
		UI.badgeTipUp = true
		UI:UpdateTooltip() -- (the row's put away)
	end
	t:SetOwner(UI.frame or f, "ANCHOR_NONE")
	if UI.PlaceTip and UI.frame then UI.PlaceTip(t) else t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "BOTTOMRIGHT", 4, -4) end
	local ok, err = pcall(def.tooltip, t)
	if not ok then ns:Trace("badge " .. tostring(def.id) .. ": " .. tostring(err)) end
	t:Show()
	f.tipUp, f.tipAt = true, GetTime()
	Tick(f)
end

--- The pop-out put away: the selected row's tooltip back.
local function HideTip(f)
	if badgeTip then badgeTip:Hide() end
	f.tipUp = nil
	if UI.badgeTipUp then
		UI.badgeTipUp = nil
		if UI.ForgetTooltip then UI:ForgetTooltip() end
		UI:UpdateTooltip()
	end
end

local function MakeBadge(def)
	local f = CreateFrame("Frame", nil, UI.frame)
	f:SetSize(BADGE_W, BADGE_W)
	local lvl = UI.edit and UI.edit:GetFrameLevel()
	f:SetFrameLevel((type(lvl) == "number" and lvl or 1) + 10) -- (over the prompt's own parts)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self)
		self.over = true
		self:SetAlpha(1)
		Tick(self)
		DrawTip(self, def)
	end)
	f:SetScript("OnLeave", function(self)
		self.over = nil
		self.fadeAt = def.fade and (GetTime() + def.fade) or nil
		if self.pinned then return end
		if self.tipUp then HideTip(self) end
	end)
	f:SetScript("OnMouseUp", function(self)
		self.pinned = not self.pinned
		if self.pinned then DrawTip(self, def) else HideTip(self) end
	end)
	f.tick = function(self, elapsed)
		if self.tipUp and GetTime() - (self.tipAt or 0) >= 1 then DrawTip(self, def) end
		-- (faded after `fade` seconds, over half a second; never while pointed at or its pop-out kept up)
		local a = (self.GetAlpha and self:GetAlpha()) or 1
		if type(a) ~= "number" then a = 1 end
		if self.fadeAt and not (self.over or self.pinned) and GetTime() >= self.fadeAt and a > FADED then
			a = math.max(FADED, a - (elapsed or 0) * 1.6)
			self:SetAlpha(a)
		end
		-- (nothing left to do: faded, or no fading, and no pop-out up. Not run every frame for good; woken by a
		-- point, a wake, a pop-out. Review, 0.58.16)
		if not (self.tipUp or self.over or self.pinned) and (not self.fadeAt or a <= FADED) then
			self:SetScript("OnUpdate", nil)
			self.ticking = nil
		end
	end
	Tick(f)
	f:SetScript("OnHide", function(self)
		if self.tipUp then HideTip(self) end
		self.pinned = nil
	end)
	if def.draw then pcall(def.draw, f) end
	f.fadeAt = def.fade and (GetTime() + def.fade) or nil
	def.frame = f
	return f
end

--- A badge seen again at full strength (something it says changed), fading again after its seconds.
function UI.WakeBadge(id)
	for _, def in ipairs(UI.badges) do
		local f = def.frame
		if def.id == id and f then
			f:SetAlpha(1)
			f.fadeAt = def.fade and (GetTime() + def.fade) or nil
			Tick(f)
		end
	end
end

--- The badges shown placed right to left after the spinner, the prompt's box made narrower by them.
function UI:PlaceBadges()
	local frame = UI.frame
	if not (frame and self.editMid) then return end
	-- (the spinner's spot when it's not there, a little in from the frame's edge; 0.58.9, the player: placed better)
	local x = -14 - ((UI.busy and UI.busy:IsShown()) and (BADGE_W + 2) or 0)
	local room = 0
	-- (none while something's typed: the prompt is the text's; 0.58.13, the player: "disappear if the user starts typing
	-- or has text in the prompt box". EditTextChanged places them again when the box empties or fills)
	local typed = UI.edit ~= nil and (UI.edit:GetText() or "") ~= ""
	self.badgesTyped = typed
	for _, def in ipairs(UI.badges) do
		local ok, on = pcall(def.shown)
		on = ok and on and not typed and true or false
		local f = def.frame or (on and MakeBadge(def)) or nil
		if f then
			f:SetShown(on)
			if on then
				f:ClearAllPoints()
				f:SetPoint("RIGHT", frame, "TOPRIGHT", x, self.editMid)
				if def.refresh then pcall(def.refresh, f) end
				-- (the pop-out up: drawn again with what's new)
				if f.tipUp then DrawTip(f, def) end
				x, room = x - (BADGE_W + 2), room + BADGE_W + 2
			end
		end
	end
	-- (the spinner's place is kept in -38 already: only the badges' room is more)
	if room ~= (self.badgeRoom or 0) then
		self.badgeRoom = room
		self:PlaceEdit()
		self.linesKey = nil -- (the box's width changed: the prompt's lines made again)
	end
end

--- Show or hide the spinner. When loading ends, the results are searched again so what just
--- arrived shows up.
function UI:UpdateBusy()
	local busy = UI.busy
	if not busy then return end
	local lines, who = {}, {}
	if self:IsShown() then lines, who = self:BusyLines() end
	-- a provider that just finished loading is collected again: what it had before was partial
	local finished = false
	for id in pairs(busy.who or {}) do
		if not who[id] and ns.providers[id] then
			ns.providers[id]._dirty = true
			finished = true
		end
	end
	busy.who = who
	local was = busy:IsShown()
	-- (a new table only when what's loading changed: its tooltip is drawn again then, not twice a second; review, 0.57.7)
	local said = table.concat(lines, "\n")
	if said ~= busy.said then busy.said, busy.lines = said, lines end
	busy:SetShown(#lines > 0)
	if was ~= busy:IsShown() then self:PlaceBadges() end -- (the badges move over for the spinner)
	if was ~= busy:IsShown() or finished then self:SetStatus() end
	if finished and self:IsShown() and not self.inBusyRefresh then
		ns:Trace("busy: loading finished, searching again")
		self.inBusyRefresh = true
		self:QuietRedo() -- (in the background: what it finds waits for F5 when a list is shown; 0.51.12)
		self.inBusyRefresh = false
	end
end

function UI:SpinBusy(elapsed)
	local busy = UI.busy
	busy.t = (busy.t or 0) + (elapsed or 0)
	busy.check = (busy.check or 0) + (elapsed or 0)
	local head = math.floor(busy.t * 10) % BUSY_DOTS -- one step every 0.1 s
	if head ~= busy.head then -- (redrawn only when the leading dot moves)
		busy.head = head
		for i, d in ipairs(busy.dots) do
			local behind = (head - (i - 1)) % BUSY_DOTS -- 0 = the leading dot
			d:SetAlpha(1 - behind / BUSY_DOTS * 0.85)
		end
	end
	if busy.check >= 0.5 then
		busy.check = 0
		local before = busy.lines
		self:UpdateBusy()
		if busy.lines ~= before and busy:IsShown() and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(busy) then
			busy:GetScript("OnEnter")(busy)
		end
	end
end

----------------------------------------------------------------------
-- Prompt colours: what's typed, coloured by what Terminal makes of it
----------------------------------------------------------------------

local function Hex(c)
	if type(c) ~= "string" then return nil end
	c = c:gsub("^|c", "")
	if #c == 8 then c = c:sub(3) end
	return #c == 6 and c or nil
end

local function Paint(hex, s)
	if s == "" then return "" end
	return "|cff" .. hex .. (s:gsub("|", "||")) .. "|r"
end

--- The colour of the channel word after a ">>": a channel (or the start of one's name being typed: pending) in the
--- filter colour, the start of another word still being typed plain, anything else bad.
local function ChannelColor(word, typing, filt, base, bad)
	local to = ns.Share.Channel(word)
	-- (">> csv", ">>> text": copying is a place to send too; review, 0.53.6)
	return (to.cmd or to.pending or to.drop or to.quests or to.copy) and filt or ((typing and ns.Share.IsStart(word)) and base or bad)
end

-- Which words parse as filters, remembered (review, 0.48.6: every keystroke parsed every filter word again just to
-- colour it; "is:upgrade" / "upgrades" read every worn item each time). Only whether it parses is kept, never the
-- filter, and the mode is part of the key (Simple mode's words are its own); at most WORDS_KEPT, then begun again.
local WORDS_KEPT = 300
local parsed, nParsed = {}, 0
local function Remembered(kind, w, ask)
	local k = kind .. (EasyOn() and "s" or "a") .. w
	local v = parsed[k]
	if v == nil then
		if nParsed >= WORDS_KEPT then parsed, nParsed = {}, 0 end
		v = ask(w) and true or false
		parsed[k], nParsed = v, nParsed + 1
	end
	return v
end
local function Parses(w) return Remembered("p", w, ns.Filters.Parse) end
local function IsWord(w) return Remembered("w", w, ns.Easy.Word) end

--- What the typed text is made of: { first byte, last byte, colour } pieces covering it. @kinds in
--- their own colour (unknown ones in red), filters (lvl:20, is:todo; a filter key with a value it
--- doesn't take in red), the .command and the /slash command at the start, plain words in the text
--- colour. plain: everything in the text colour (the colours turned off, a wrapped prompt).
function UI:SyntaxSegments(text, plain)
	local t = Theme.Get()
	local base, bad, filt = t.text, Theme.SYNTAX.bad, Theme.SYNTAX.filter
	if plain or self.fzf or self.histSearch then return { { 1, #text, base } } end
	local first = text:sub(1, 1)
	if first == "." or first == "/" then
		local head = text:match("^(%S*)")
		local color = t.prompt
		if first == "." then color = (#head == 1 or ns:FindCommand(head:sub(2))) and t.accent or bad end
		return { { 1, #head, color }, { #head + 1, #text, base } }
	end
	local out, F, pos = {}, ns.Filters, 1
	local afterSend = false -- (the channel word right after a ">>")
	local steps = false -- (after a "|" standing alone: "| sum value", "| zone:..."; its words are steps, not filters)
	while pos <= #text do
		local sp = text:match("^%s+", pos)
		if sp then
			out[#out + 1] = { pos, pos + #sp - 1, base }
			pos = pos + #sp
		else
			local word = text:match("^%S+", pos)
			-- (a quote opened in it: the word runs to where it closes, spaces and all, as the search reads it: in:"elwynn
			-- forest" is one filter; 0.53.1, the player: q:"Rare" showed as a bad filter)
			local _, quotes = word:gsub('"', "")
			if quotes % 2 == 1 then
				local close = text:find('"', pos + #word, true)
				local stop = close and ((text:find("%s", close) or #text + 1) - 1) or #text
				word = text:sub(pos, stop)
			end
			local color = base
			if word == "|" and ns.Aggregate then
				color, steps = t.accent, true
			elseif steps and ns.Aggregate and word:sub(1, 2) ~= ">>" then
				-- (a step's field:value: a field it knows in the filters' colour; release review: quality:"Rare", which Enter
				-- on a group writes, showed as a bad filter)
				local key = word:match("^(%a+):")
				if key then color = ns.Aggregate.FieldOf(key) and filt or bad end
			elseif (word == ">>" or word == ">>>") and ns.Share then
				color = t.accent
				afterSend = true
			elseif ns.Share and #word > 2 and word:sub(1, 2) == ">>" then
				-- ">>party", ">>>party": the arrows in the accent, the channel judged as after a ">>"
				local arrows = word:sub(3, 3) == ">" and 3 or 2
				out[#out + 1] = { pos, pos + arrows - 1, t.accent }
				pos = pos + arrows
				word = word:sub(arrows + 1)
				color = ChannelColor(word, pos + #word > #text, filt, base, bad)
			elseif afterSend then
				afterSend = false
				color = ChannelColor(word, pos + #word > #text, filt, base, bad)
			elseif word:sub(1, 1) == "@" then
				local p = #word > 1 and ns:ResolveProvider(word:sub(2))
				color = p and (Hex(p.color) or t.accent) or (#word == 1 and t.accent or bad)
			else
				local key, value = word:match("^(%a+):(.*)$")
				-- (0.49.2, review: "-малое", "-épée" are "not" too, as the search reads them: a letter of any language)
				if F and (word:find("[|&]") or word:find("^[-!][%a\128-\255]")) then
					-- "-is:boe", "q:rare|epic", "sword|axe": a filter once it parses (still being typed: plain)
					local typing = pos + #word > #text
					color = Parses(word) and filt or ((typing or not key) and base or bad)
				elseif key and F and F.IsKey(key) then
					color = (value == "" or Parses(word)) and filt or bad
				elseif not key and ns.Easy and IsWord(word) then
					color = filt -- (easy mode: "rare", "ready", "vendor")
				end
			end
			out[#out + 1] = { pos, pos + #word - 1, color }
			pos = pos + #word
		end
	end
	return out
end


--- Bytes from..to of the text, painted by the pieces that cover them.
local function PaintRange(text, segs, from, to)
	local out = {}
	for _, sg in ipairs(segs) do
		local a, b = math.max(sg[1], from), math.min(sg[2], to)
		if a <= b then out[#out + 1] = Paint(sg[3], text:sub(a, b)) end
	end
	return table.concat(out)
end

--- The typed text with colour codes (see SyntaxSegments). Spaces are kept as typed. (tests)
function UI:Highlighted(text)
	return PaintRange(text, self:SyntaxSegments(text), 1, #text)
end

local syntaxLines = {} -- one per line of the prompt (the first is `syntax`)
local function SyntaxLine(i)
	local edit, hit, syntax = UI.edit, UI.hit, UI.syntax
	if i == 1 then return syntax end
	local fs = syntaxLines[i]
	if not fs then
		fs = hit:CreateFontString(nil, "ARTWORK")
		fs:SetFontObject(Theme.fonts.input)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		syntaxLines[i] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", edit, "LEFT", 0, -(i - 1) * LY.LINE_H)
	return fs
end

--- The coloured copy over the prompt, a line per line of it, while Terminal draws the prompt.
--- Shown with the colours on, and always once the prompt wraps (the box can't show more lines);
--- the box's own text hides under it.
function UI:UpdateSyntax()
	local edit, syntax = UI.edit, UI.syntax
	if not (syntax and edit) then return end
	local text = ns.MaskSecret(edit:GetText() or "")
	local lines = self:PromptLines()
	local colours = Theme.Get().syntax
	-- (a secret being typed, ".share join raid <code>": the copy shows it as *s, so it's always on; the box's own text, in
	-- the game's typing mode (combat), is the game's password box: all *s. 0.58.6, the player: streams)
	local secret = ns.SecretLine(text)
	-- (what's applied, not only whether it's a password line: leaving Terminal's own keys with the line as it is, a
	-- click into the box or Ctrl+C, turns the box's password mode on. Review, 0.58.16: it stayed off, the password
	-- in clear)
	local want = (secret and not self.keys) and true or false
	if edit.SetPassword and edit.secretShown ~= want then edit.secretShown = want; pcall(edit.SetPassword, edit, want) end
	local on = self.keys and self:IsShown() and text ~= "" and (colours or #lines > 1 or secret) and true or false
	if on then
		local key = (self.linesKey or text) .. "\0" .. tostring(colours)
		if self.syntaxKey ~= key then
			self.syntaxKey = key
			local segs = self:SyntaxSegments(text, not colours)
			for i, l in ipairs(lines) do
				local fs = SyntaxLine(i)
				fs:SetText(Theme.FixColors(PaintRange(text, segs, l[1], l[2])))
				fs:Show()
			end
			for i = #lines + 1, MAX_LINES do if syntaxLines[i] then syntaxLines[i]:Hide() end end
		end
	else
		for i = 2, MAX_LINES do if syntaxLines[i] then syntaxLines[i]:Hide() end end
		self.syntaxKey = nil
	end
	if on ~= self.syntaxOn then
		self.syntaxOn = on
		syntax:SetShown(on)
		local tr, tg, tb = Theme.RGB(Theme.Get().text)
		edit:SetTextColor(tr, tg, tb, on and 0 or 1) -- (the box's own text hides under the copy)
	end
end

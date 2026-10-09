local ns = select(2, ...)

-- The prompt Terminal draws over the game's text box out of combat: the query set and measured, wrapped onto more
-- lines when long, the caret and the selection, mouse clicks and drags on it, the loading spinner at its end, and the
-- colours of what's typed. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local L = UI.layout
local EasyOn, Wake, NextPos, BUSY_DOTS = UI.EasyOn, UI.Wake, UI.NextPos, UI.BUSY_DOTS

local MAX_LINES = 8 -- a long prompt wraps onto more lines (the header grows down)

function UI:SetQuery(text, cursor)
	local edit = UI.edit
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
	local text = edit:GetText() or ""
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
	local text = edit:GetText() or ""
	local lines = self:PromptLines()
	local i = 1
	for k = 2, #lines do
		if lines[k][1] - 1 <= pos then i = k else break end
	end
	local first = lines[i][1]
	local x = pos >= first and Width(text:sub(first, pos)) or 0
	return math.min(x, LineRoom()), -(i - 1) * L.LINE_H, i
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
	local text, lines = edit:GetText(), self.lines
	for i = i1, i2 do
		local band = i == i1 and selText or SelBand(i - i1)
		local from = i == i1 and x1 or 0
		local to = i == i2 and x2 or math.min(Width(text:sub(lines[i][1], lines[i][2])), LineRoom())
		band:ClearAllPoints()
		band:SetPoint("LEFT", edit, "LEFT", from, -(i - 1) * L.LINE_H)
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
	local text = edit:GetText()
	self:SetPromptExtra((#self:PromptLines() - 1) * L.LINE_H)
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
	local text = edit:GetText()
	local lines = UI:PromptLines()
	local i = math.max(1, math.min(#lines, 1 + math.floor((down or 0) / L.LINE_H + 0.5)))
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
	return best
end

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
	if self.searchJob then out[1] = "Searching... (the best matches so far are shown)" end
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
	edit:SetPoint("RIGHT", frame, "TOPRIGHT", -38, self.editMid)
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
	busy.lines = lines
	busy:SetShown(#lines > 0)
	if was ~= busy:IsShown() or finished then self:SetStatus() end
	if finished and self:IsShown() and not self.inBusyRefresh then
		ns:Trace("busy: loading finished, searching again")
		self.inBusyRefresh = true
		self:Refresh()
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
		self:UpdateBusy()
		if busy:IsShown() and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(busy) then busy:GetScript("OnEnter")(busy) end
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
	return (to.cmd or to.pending or to.drop) and filt or ((typing and ns.Share.IsStart(word)) and base or bad)
end

--- What the typed text is made of: { first byte, last byte, colour } pieces covering it. @kinds in
--- their own colour (unknown ones in red), filters (lvl:20, is:todo; a filter key with a value it
--- doesn't take in red), the .command and the /slash command at the start, plain words in the text
--- colour. plain: everything in the text colour (the colours turned off, a wrapped prompt).
function UI:SyntaxSegments(text, plain)
	local t = Theme.Get()
	local base, bad, filt = t.text, Theme.SYNTAX.bad, Theme.SYNTAX.filter
	if plain or self.fzf then return { { 1, #text, base } } end
	local first = text:sub(1, 1)
	if first == "." or first == "/" then
		local head = text:match("^(%S*)")
		local color = t.prompt
		if first == "." then color = (#head == 1 or ns:FindCommand(head:sub(2))) and t.accent or bad end
		return { { 1, #head, color }, { #head + 1, #text, base } }
	end
	local out, F, pos = {}, ns.Filters, 1
	local afterSend = false -- (the channel word right after a ">>")
	while pos <= #text do
		local sp = text:match("^%s+", pos)
		if sp then
			out[#out + 1] = { pos, pos + #sp - 1, base }
			pos = pos + #sp
		else
			local word = text:match("^%S+", pos)
			local color = base
			if EasyOn() and ns.Easy.IsAdvancedWord(word) then
				color = bad -- (Simple mode: Advanced syntax isn't taken)
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
				if F and (word:find("[|&]") or word:find("^[-!]%a")) then
					-- "-is:boe", "q:rare|epic", "sword|axe": a filter once it parses (still being typed: plain)
					local typing = pos + #word > #text
					color = F.Parse(word) and filt or ((typing or not key) and base or bad)
				elseif key and F and F.IsKey(key) then
					color = (value == "" or F.Parse(word)) and filt or bad
				elseif not key and ns.Easy and ns.Easy.Word(word) then
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

--- The typed text with colour codes (see SyntaxSegments). Spaces are kept as typed.
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
	fs:SetPoint("LEFT", edit, "LEFT", 0, -(i - 1) * L.LINE_H)
	return fs
end

--- The coloured copy over the prompt, a line per line of it, while Terminal draws the prompt.
--- Shown with the colours on, and always once the prompt wraps (the box can't show more lines);
--- the box's own text hides under it.
function UI:UpdateSyntax()
	local edit, syntax = UI.edit, UI.syntax
	if not (syntax and edit) then return end
	local text = edit:GetText() or ""
	local lines = self:PromptLines()
	local colours = Theme.Get().syntax
	local on = self.keys and self:IsShown() and text ~= "" and (colours or #lines > 1) and true or false
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

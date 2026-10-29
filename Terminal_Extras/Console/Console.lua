-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- .console (branch console-dev): a terminal of its own over the whole screen. Up to four panes, tiled (grid, tall,
-- wide, mono), each a shell (Shell.lua) over Terminal's lists as files (FS.lua). An app a pane starts (.snake, .wowamp,
-- .atop...) opens in that pane and keeps going beside the others. ` steps out (games pause: their frames hide), .console
-- comes back to everything as it was. Zen is always on here, whatever .zen says.
--
-- Typing goes to a real EditBox per pane (the clipboard works), its text drawn over in colour; an app's pane gives the
-- keyboard to the app, the console keeping its own keys (Ctrl+..., `) by wrapping the app's OnKeyDown while it's
-- docked. A pane's command runs in a coroutine, BUDGET_MS a frame shared by the running ones.

local Panel, Theme, SH, FS = ns.Panel, ns.Theme, ns.Shell, ns.ConsoleFS
local Paint = SH.Paint

local C = {}
ns.Console = C

C.MAX = 4
C.LAYOUTS = { "tile", "grid", "tall", "wide", "mono" }
C.MAX_LINES = 2000 -- (a pane's scrollback)
C.BUDGET_MS = 8 -- (a frame's time for the running commands, all panes together)
C.POLL = 0.1 -- (s: apps opened or closed looked for this often)
C.GAP, C.PAD, C.TITLE_H, C.STATUS_H = 6, 8, 18, 20
C.TAB_AGAIN = 3 -- (s: a second Tab lists many choices)
C.MANY = 60 -- (more choices than this: Tab again to list them)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame, status, statusRight
local panes = {}
local focus
local layout, zoomed = "tile", false
local nextPid = 1
local docked = {} -- app -> its pane
local launcher -- the pane whose command opened the last app
local measure

local function RGB(hex) return Theme.RGB(hex) end
local PAL = { bg = "0b0d12", pane = "10131a", edge = "232836", title = "161a23", caret = "7dcfff" }

C.FONT_MIN, C.FONT_MAX = 8, 32

--- Every pane's text size unless it has its own: the console's (db.console.fontSize: .console font, font -a), else
--- Terminal's.
function C.DefaultFontSize()
	local db = ns.db
	local n = db and type(db.console) == "table" and tonumber(db.console.fontSize)
	return n or Theme.Get().fontSize or 13
end
--- A pane's text size: its own (font N in it, Ctrl+= / Ctrl+-; this session), else the default.
function C.FontSize(p) return p and p.fontSize or C.DefaultFontSize() end
local function Font(p) return Theme.FontAt(C.FontSize(p)) end
-- (titles and the status bar keep Terminal's size: their bars are a fixed height)
local function Chrome() return Theme.FontAt(math.min(14, Theme.Get().fontSize or 13)) end
local function LineH(p) return C.FontSize(p) + 5 end

----------------------------------------------------------------------
-- Panes
----------------------------------------------------------------------

local function History()
	local d = SH.Data()
	if not d then return {} end
	d.history = type(d.history) == "table" and d.history or {}
	local h = d.history
	for i = #h, 1, -1 do if SH.Secret(h[i]) then table.remove(h, i) end end -- (a password kept before they were left out)
	return h
end

local function IndexOf(p)
	for i, q in ipairs(panes) do if q == p then return i end end
	return nil
end

local function PaneOf(sh)
	for _, p in ipairs(panes) do if p.sh == sh then return p end end
	return nil
end

local function AppName(rec)
	local name = rec and rec.frame and rec.frame.GetName and rec.frame:GetName()
	name = tostring(name or "app"):gsub("^Terminal", "")
	return ns.Lower(name)
end

--- What a pane shows in its title and in ps: its app, its command, or the shell.
local function What(p)
	if p.app then return AppName(p.app) end
	if p.job then return p.jobText or "tsh" end
	return "tsh"
end

local function Trim(p)
	if #p.lines > C.MAX_LINES + 200 then
		local keep, from = {}, #p.lines - C.MAX_LINES + 1
		for i = from, #p.lines do keep[#keep + 1] = p.lines[i] end
		p.lines = keep
	end
end

local function Print(p, line)
	p.lines[#p.lines + 1] = tostring(line or "")
	if p.since then p.since = p.since + 1 end -- (lines the command now running printed: C.Wipe takes them back)
	if p.offset > 0 then p.offset = p.offset + 1 end
	Trim(p)
	p.dirty = true
end
C.Print = Print

local function PromptText(p)
	local pg = p.pager
	if pg then
		if pg.mode == "search" then return Paint("yellow", pg.dir < 0 and "?" or "/") end
		local n = #pg.lines
		local last = math.min(n, pg.top + (pg.rows or 1) - 1)
		return Paint("cyan", SH.Literal(pg.title)) .. Paint("dim", ("  %d-%d/%d  "):format(n == 0 and 0 or pg.top, last, n))
			.. Paint(pg.note and "orange" or "dim", SH.Literal(pg.note or L["q quits  / searches  n next  Space a page"])) .. " "
	end
	local is = p.isearch
	if is then return Paint("yellow", is.failed and "(failed reverse-i-search)" or "(reverse-i-search)") .. Paint("dim", "`") end
	return SH.PromptLine(p.sh)
end
C.PromptText = PromptText

local NewPane -- (below: the ui hooks make panes)

local ui = {}
function ui.Split(sh) return C.Split(PaneOf(sh)) ~= nil end
function ui.ClosePane(sh) local p = PaneOf(sh) if p then p.closeAfter = true end end
function ui.Layout(mode)
	if mode == nil or mode == "" then
		return true, layout
	end
	for _, m in ipairs(C.LAYOUTS) do
		if m == mode then layout = m; zoomed = false; C.Layout() return true, m end
	end
	return false
end
function ui.Panes()
	local out = {}
	for i, p in ipairs(panes) do out[#out + 1] = { id = p.id, index = i, what = What(p) } end
	return out
end
function ui.Kill(pid, from)
	for _, p in ipairs(panes) do
		if p.id == pid then
			if p.app then C.CloseApp(p) return true end
			if p.job and p.sh ~= from then p.sh.cancelled = true return true end
			return p.sh == from
		end
	end
	return false
end
--- The text size of the pane `sh` runs in, or (no sh, or -a / --all first) every pane's default: nothing asks; a
--- number sets it, "+" / "-" a step, "reset" (a pane: the default again; the default: Terminal's). The size and
--- whether it was the default; or nil and why.
function ui.Font(args, sh)
	args = type(args) == "table" and args or { args }
	local i, all = 1, sh == nil
	local first = args[1] and tostring(args[1]):lower()
	if first == "-a" or first == "--all" or first == "all" then all, i = true, 2 end
	local p = not all and PaneOf(sh) or nil
	if not p then all = true end
	local a = args[i] and tostring(args[i]):lower() or ""
	local target = not all and p or nil
	if a == "" then return C.FontSize(target), all end
	if a == "reset" or a == "default" then return C.SetFontSize(nil, target), all end
	if a == "+" then return C.SetFontSize(C.FontSize(target) + 1, target), all end
	if a == "-" then return C.SetFontSize(C.FontSize(target) - 1, target), all end
	local n = tonumber(a)
	if not n then return nil, L["a size from %d to %d, + or -, or reset"]:format(C.FONT_MIN, C.FONT_MAX) end
	return C.SetFontSize(n, target), all
end
function ui.Pager(sh, lines, title)
	local p = PaneOf(sh)
	if not p then return false end
	C.Pager(p, lines, { title = title })
	return true
end
function ui.Matrix(sh)
	local p = PaneOf(sh)
	if p then C.Matrix(p) end
end
function ui.Wipe(sh) C.Wipe(PaneOf(sh)) end
function ui.Launched(sh) launcher = PaneOf(sh) or launcher; C.PollApps() end
function ui.Theme(map) C.ApplyTheme(map) end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Row(p, i)
	local r = p.rows[i]
	if r then return r end
	r = p.sheet:CreateFontString(nil, "OVERLAY")
	r:SetFontObject(Font(p))
	r:SetJustifyH("LEFT")
	r:SetJustifyV("MIDDLE")
	if r.SetWordWrap then r:SetWordWrap(false) end
	if r.SetNonSpaceWrap then r:SetNonSpaceWrap(false) end
	r:SetTextColor(RGB(SH.C.text))
	p.rows[i] = r
	return r
end

local widths, widthCount = {}, 0 -- size -> text -> px (the column stops measure every cell shown on each redraw)
--- The width of text in a pane's font.
local function Width(text, p)
	local size = C.FontSize(p)
	local bySize = widths[size]
	if not bySize then bySize = {} widths[size] = bySize end
	local w = bySize[text]
	if w then return w end
	if not measure then
		measure = frame:CreateFontString(nil, "OVERLAY")
		measure:Hide()
	end
	measure:SetFontObject(Font(p))
	measure:SetText(text)
	w = measure:GetStringWidth() or 0
	if widthCount > 4000 then widths, widthCount = { [size] = {} }, 0 bySize = widths[size] end
	bySize[text], widthCount = w, widthCount + 1
	return w
end
C.Width = Width

local function ApplyFont(p)
	local f = Font(p)
	for _, r in ipairs(p.rows) do
		r:SetFontObject(f)
		for _, c in ipairs(r.cells or {}) do c:SetFontObject(f) end
		for _, c in ipairs(r.mono or {}) do c:SetFontObject(f) end
		if r.rest then r.rest:SetFontObject(f) end
	end
	p.prompt:SetFontObject(f)
	p.edit:SetFontObject(f)
	p.overlay:SetFontObject(f)
	p.dirty = true
end

--- Sets a text size (nil: back to the default). With a pane, that pane's (this session); without, the default every
--- pane takes, kept between sessions (the panes' own sizes let go, so all show it now). The size it is now.
function C.SetFontSize(n, p)
	if n ~= nil then n = math.max(C.FONT_MIN, math.min(C.FONT_MAX, math.floor(tonumber(n) or C.FontSize(p)))) end
	if p then
		p.fontSize = n
		ApplyFont(p)
		return C.FontSize(p)
	end
	local db = ns.db
	if not db then return C.DefaultFontSize() end
	db.console = type(db.console) == "table" and db.console or {}
	db.console.fontSize = n
	for _, q in ipairs(panes) do
		q.fontSize = nil
		ApplyFont(q)
	end
	C.Status()
	return C.DefaultFontSize()
end

C.PROMPT_ROOM = 10 -- (characters of room the input line keeps for typing: a prompt taking more is shortened)

--- The input line's prompt, shortened in a narrow pane (0.68.13, the player's screenshot: user@host ran on over the
--- next pane): as set, else where you are and the prompt's end, else its end alone.
function C.InputPrompt(p, room)
	local text = PromptText(p)
	if p.pager or p.isearch then return text end
	local want = room - C.PROMPT_ROOM * Width("0", p)
	for _, spec in ipairs({ "dir", "char" }) do
		if Width(text, p) <= want then break end
		text = SH.PromptLine(p.sh, spec)
	end
	return text
end

--- The input line: the prompt, the box after it, its text in colour over it and the block caret.
function C.UpdateInput(p)
	local lh = LineH(p)
	local room = math.max(0, (p.body:GetWidth() or 0) - 8)
	p.prompt:SetText(C.InputPrompt(p, room))
	p.prompt:SetWidth(math.max(1, room)) -- (still too long, a pager's line: the game ends it at the pane's edge)
	local pw = math.min(p.prompt:GetStringWidth() or 0, room)
	p.edit:ClearAllPoints()
	p.edit:SetPoint("TOPLEFT", p.prompt, "TOPLEFT", pw, 0)
	p.edit:SetPoint("RIGHT", p.body, "RIGHT", -4, 0)
	p.edit:SetHeight(lh)
	local text = p.edit:GetText() or ""
	local pos = p.edit.GetCursorPosition and p.edit:GetCursorPosition() or #text
	local secret = not p.pager and not p.isearch and SH.Secret(text)
	local shown = secret and SH.Masked(text) or text -- (the password as *s: the box's own text is never drawn then)
	local painted = (p.pager or p.isearch) and SH.Literal(text) or SH.Highlight(p.sh, shown)
	p.overlay:SetText(painted)
	local room = (p.edit:GetWidth() or 0) - 8
	local fits = (p.overlay:GetStringWidth() or 0) <= room or room <= 0
	p.suggestion = nil
	if p.isearch then
		p.overlay:SetText(painted .. Paint("dim", "': ") .. (p.isearch.line and SH.Highlight(p.sh, p.isearch.line, true) or ""))
	elseif fits and not secret and not p.pager and not p.job and pos >= #text then
		p.suggestion = SH.Suggest(p.sh, text)
		if p.suggestion then p.overlay:SetText(painted .. Paint("dim", SH.Literal(p.suggestion))) end
	end
	if p == focus then
		local hint = not p.pager and not p.isearch and SH.UsageHint(text, pos) or nil
		if hint ~= C.usageNote then C.usageNote = hint; C.Status() end
	end
	local tr, tg, tb = RGB(SH.C.text)
	if fits or p.isearch or secret then
		p.edit:SetTextColor(tr, tg, tb, 0)
		p.overlay:Show()
		local x = Width(SH.Literal(shown:sub(1, pos)), p)
		local under = shown:sub(pos + 1, pos + 1)
		local w = math.max(6, under ~= "" and under ~= " " and Width(SH.Literal(under), p) or Width("n", p))
		p.caret:ClearAllPoints()
		p.caret:SetPoint("TOPLEFT", p.edit, "TOPLEFT", x, -1)
		p.caret:SetSize(w, lh - 2)
		p.caret:SetShown(p == focus and not p.app and p.edit:HasFocus())
	else
		p.edit:SetTextColor(tr, tg, tb, 1)
		p.overlay:Hide()
		p.caret:Hide()
	end
end

C.CELL_GAP = 14 -- (px between lined-up columns)

--- A line's tab-parted cells (ls -l), or nil for a plain line.
local function Cells(line)
	if not line:find("\t", 1, true) then return nil end
	line = line:gsub("|Htsh:.-|h|h", "")
	local cells = {}
	for c in (line .. "\t"):gmatch("(.-)\t") do cells[#cells + 1] = c end
	return cells
end
C.Cells = Cells

--- Where each column starts (px) for the lines shown: every column as wide as its widest cell among them.
local function Stops(p, lines, from, to)
	local widths = {}
	for idx = from, to do
		local cells = lines[idx] and Cells(lines[idx])
		if cells then
			for j = 1, #cells - 1 do
				local w = Width(cells[j], p)
				if not widths[j] or w > widths[j] then widths[j] = w end
			end
		end
	end
	local stops, x = { 0 }, 0
	for j = 1, #widths do
		x = x + widths[j] + C.CELL_GAP
		stops[j + 1] = x
	end
	return stops
end

C.MONO_GAP = 12 -- (px between an art line's fixed-width part and the rest)

--- The room a pane's lines have (px), as SideOf counts it.
local function Room(p) return math.max(0, (p.body:GetWidth() or 0) - 8) end

--- text with its first px cut off, whole characters only: what's left (its colours kept; a link's wrapping dropped:
--- C.LinkAt reads the lines, not the rows) and how far right of the cut it starts (less than a character).
local function CutLeft(p, text, px)
	local chars, colors, color, i, n = {}, {}, nil, 1, #text
	while i <= n do
		local two = text:sub(i, i + 1)
		local code = text:match("^|c%x%x%x%x%x%x%x%x", i)
		if code then color, i = code, i + 10
		elseif two == "|r" then color, i = nil, i + 2
		elseif two == "|H" then i = (text:find("|h", i + 2, true) or n - 1) + 2
		elseif two == "|h" then i = i + 2
		else
			local ch = two == "||" and "||" or text:match("^[%z\1-\127\194-\244][\128-\191]*", i) or text:sub(i, i)
			local k = #chars + 1
			chars[k], colors[k] = ch, color
			i = i + #ch
		end
	end
	-- (the fewest characters as wide as px)
	local lo, hi = 0, #chars
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if Width(table.concat(chars, "", 1, mid), p) >= px then hi = mid else lo = mid + 1 end
	end
	local out, cur = {}, nil
	for j = lo + 1, #chars do
		if colors[j] ~= cur then out[#out + 1] = colors[j] or "|r"; cur = colors[j] end
		out[#out + 1] = chars[j]
	end
	if cur then out[#out + 1] = "|r" end
	return table.concat(out), Width(table.concat(chars, "", 1, lo), p) - px
end
C.CutLeft = CutLeft

--- One piece of a line (a row, a cell, an art line's rest) drawn x px right of the sheet's left edge and y down, cut to
--- the pane: nothing past either edge is drawn. (0.68.13: neither SetClipsChildren nor the ScrollFrame cut text in the
--- game, and lines ran on over the next pane, seen twice.)
local function Fit(p, fs, text, x, y)
	local room = Room(p)
	if text == "" or x >= room or x + Width(text, p) <= 0 then
		fs:SetText("")
		fs:Hide()
		return
	end
	if x < 0 then text, x = CutLeft(p, text, -x) end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", p.sheet, "TOPLEFT", x, y)
	fs:SetWidth(math.max(1, room - x)) -- (the game ends a line that doesn't fit at this width)
	fs:SetText(text)
	fs:Show()
end

--- An art line (SH.Mono) x px right of the sheet's left edge: its first part a character a slot, every slot one width
--- (a monospace font's way: none of the game's fonts is one), the rest of the line after the slots. Spaces take a slot
--- and draw nothing; a slot not wholly in the pane isn't drawn.
local function SetMono(p, r, line, x, y)
	local bytes, cols, rest = line:match("^|Htshm:(%d+):(%d+)|h|h(.*)$")
	bytes, cols = tonumber(bytes) or 0, tonumber(cols) or 0
	local art = rest:sub(1, bytes)
	rest = rest:sub(bytes + 1)
	local cw = Width("0", p)
	local h = LineH(p)
	local room = Room(p)
	r.mono = r.mono or {}
	local used, col, color, i = 0, 0, nil, 1
	while i <= #art do
		local code = art:match("^|c(%x%x%x%x%x%x%x%x)", i)
		if code then color, i = code, i + 10
		elseif art:sub(i, i + 1) == "|r" then color, i = nil, i + 2
		else
			local ch
			if art:sub(i, i + 1) == "||" then ch = "||"
			else ch = art:match("^[%z\1-\127\194-\244][\128-\191]*", i) or art:sub(i, i) end
			i = i + #ch
			local sx = x + col * cw
			if ch ~= " " and sx >= 0 and sx + cw <= room then
				used = used + 1
				local fs = r.mono[used]
				if not fs then
					fs = p.sheet:CreateFontString(nil, "OVERLAY")
					fs:SetFontObject(Font(p))
					fs:SetJustifyH("CENTER")
					fs:SetTextColor(RGB(SH.C.text))
					r.mono[used] = fs
				end
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", p.sheet, "TOPLEFT", sx, y)
				fs:SetSize(cw, h)
				fs:SetText(color and ("|c" .. color .. ch .. "|r") or ch)
				fs:Show()
			end
			col = col + 1
		end
	end
	for j = used + 1, #r.mono do r.mono[j]:Hide() end
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", p.sheet, "TOPLEFT", 0, y)
	r:SetText("")
	for _, c in ipairs(r.cells or {}) do c:Hide() end
	if not r.rest then
		r.rest = p.sheet:CreateFontString(nil, "OVERLAY")
		r.rest:SetFontObject(Font(p))
		r.rest:SetJustifyH("LEFT")
		if r.rest.SetWordWrap then r.rest:SetWordWrap(false) end
		r.rest:SetTextColor(RGB(SH.C.text))
	end
	r.rest:SetHeight(h)
	Fit(p, r.rest, rest, x + math.max(cols, col) * cw + C.MONO_GAP, y)
end

--- A row's own pieces hidden (its cells, an art line's slots and rest), and with `all` the row too.
local function HideParts(r, all)
	if all then r:Hide() end
	for _, c in ipairs(r.cells or {}) do c:Hide() end
	for _, c in ipairs(r.mono or {}) do c:Hide() end
	if r.rest then r.rest:Hide() end
end
C.HideParts = HideParts

--- A row's text, x px right of the sheet's left edge (slid sideways) and y down: plain, or its cells at the stops (the
--- last one takes the rest of the line), or an art line; cut to the pane (Fit).
local function SetRow(p, r, line, stops, x, y)
	if line:find("^|Htshm:") then return SetMono(p, r, line, x, y) end
	HideParts(r)
	line = line:gsub("|Htsh:.-|h|h", "") -- (an ls -l line's own columns: for the pipes, never drawn)
	local cells = Cells(line)
	r.cells = r.cells or {}
	if not cells then
		Fit(p, r, line, x, y)
		for _, c in ipairs(r.cells) do c:Hide() end
		return
	end
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", p.sheet, "TOPLEFT", 0, y)
	r:SetText("")
	for j, text in ipairs(cells) do
		local c = r.cells[j]
		if not c then
			c = p.sheet:CreateFontString(nil, "OVERLAY")
			c:SetFontObject(Font(p))
			c:SetJustifyH("LEFT")
			if c.SetWordWrap then c:SetWordWrap(false) end
			c:SetTextColor(RGB(SH.C.text))
			r.cells[j] = c
		end
		c:SetHeight(r:GetHeight() or LineH(p))
		Fit(p, c, text, x + (stops[j] or 0), y)
	end
	for j = #cells + 1, #r.cells do r.cells[j]:Hide() end
end

--- How wide a line is drawn (px): its text, its last column's end, an art line's slots and the rest after them.
local function LineWidth(p, line, stops)
	local bytes, cols, rest = line:match("^|Htshm:(%d+):(%d+)|h|h(.*)$")
	if bytes then return (tonumber(cols) or 0) * Width("0", p) + C.MONO_GAP + Width(rest:sub((tonumber(bytes) or 0) + 1), p) end
	line = line:gsub("|Htsh:.-|h|h", "")
	local cells = Cells(line)
	if not cells then return Width(line, p) end
	return (stops[#cells] or 0) + Width(cells[#cells], p)
end

--- The sideways scroll for lines first..last (px): p.hx, no further than the widest of them needs; and that most.
local function SideOf(p, lines, first, last, stops)
	local wide = 0
	for idx = first, last do
		if lines[idx] then wide = math.max(wide, LineWidth(p, lines[idx], stops)) end
	end
	local most = math.max(0, math.ceil(wide - ((p.body:GetWidth() or 0) - 8)))
	return math.min(p.hx or 0, most), most, wide
end

--- The pager's lines: a page from `top`, what's searched for marked; the prompt line its state.
local function DrawPager(p)
	local pg = p.pager
	local lh = LineH(p)
	local rows = math.max(1, math.floor(((p.body:GetHeight() or 0) - 4) / lh) - 1)
	pg.rows = rows
	pg.top = math.max(1, math.min(pg.top, math.max(1, #pg.lines - rows + 1)))
	local last = math.min(#pg.lines, pg.top + rows - 1)
	local stops = Stops(p, pg.lines, pg.top, last)
	local hx, most, wide = SideOf(p, pg.lines, pg.top, last, stops)
	p.view = { lines = pg.lines, first = pg.top, count = math.max(0, last - pg.top + 1), stops = stops, hx = hx, most = most, wide = wide }
	local match = pg.search and pg.search ~= "" and SH.Matcher(pg.search)
	for i = 1, math.max(rows, #p.rows) do
		local idx = pg.top + i - 1
		if i <= rows and idx <= last then
			local r = Row(p, i)
			r:SetHeight(lh)
			local line = pg.lines[idx]
			local s, e = nil, nil
			if match then s, e = match(FS.Strip(line)) end
			SetRow(p, r, s and SH.Mark(line, s, e) or line, stops, -hx, -2 - (i - 1) * lh)
			r:Show()
		elseif p.rows[i] then
			HideParts(p.rows[i], true)
		end
	end
	p.prompt:ClearAllPoints()
	p.prompt:SetPoint("TOPLEFT", p.body, "TOPLEFT", 4, -2 - rows * lh)
	p.prompt:SetHeight(lh)
	p.prompt:Show()
	p.edit:Show()
	C.UpdateInput(p)
	C.DrawSelection(p)
	C.Title(p)
end

----------------------------------------------------------------------
-- matrix (an easter egg): green rain down the pane, as cmatrix; any key stops it
----------------------------------------------------------------------

C.MATRIX_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*+=<>?:;{}[]"
C.MATRIX_FPS = 20
C.MATRIX_SHADES = { "ffffff", "b9ffb0", "5dff5a", "23d12b", "13a51d", "0b7a14", "06520d", "033307" }

local function MatrixChar()
	local i = math.random(#C.MATRIX_CHARS)
	return C.MATRIX_CHARS:sub(i, i)
end

local function MatrixDrop(m, rows)
	return { head = -math.random(0, rows), speed = 6 + math.random() * 18, len = math.random(4, math.max(5, math.floor(rows * 0.8))) }
end

--- The rain: one column of text per column of letters (a FontString each, its lines the rows), drawn from each
--- column's drop: its head white, its trail greener and darker behind it.
local function DrawMatrix(p)
	local m = p.matrix
	local lh = LineH(p)
	local cw = math.max(6, Width("M", p))
	local cols = math.max(1, math.floor(((p.body:GetWidth() or 0) - 8) / cw))
	local rows = math.max(1, math.floor(((p.body:GetHeight() or 0) - 4) / lh))
	if m.cols ~= cols or m.rows ~= rows then
		m.cols, m.rows, m.drops, m.chars = cols, rows, {}, {}
		for c = 1, cols do
			m.drops[c] = MatrixDrop(m, rows)
			local ch = {}
			for r = 1, rows do ch[r] = MatrixChar() end
			m.chars[c] = ch
		end
	end
	for i = 1, #p.rows do HideParts(p.rows[i], true) end
	p.prompt:Hide()
	p.overlay:Hide()
	p.caret:Hide()
	p.mcols = p.mcols or {}
	local shades = C.MATRIX_SHADES
	for c = 1, cols do
		local fs = p.mcols[c]
		if not fs then
			fs = p.body:CreateFontString(nil, "OVERLAY")
			fs:SetJustifyH("CENTER")
			fs:SetJustifyV("TOP")
			p.mcols[c] = fs
		end
		fs:SetFontObject(Font(p))
		if fs.SetSpacing then fs:SetSpacing(lh - C.FontSize(p)) end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", p.body, "TOPLEFT", 4 + (c - 1) * cw, -2)
		fs:SetWidth(cw)
		local d, ch = m.drops[c], m.chars[c]
		local out = {}
		for r = 1, rows do
			local behind = d.head - r -- (0: the head; up to len: its trail)
			if behind >= 0 and behind < 1 then
				out[r] = "|cff" .. shades[1] .. ch[r] .. "|r"
			elseif behind >= 1 and behind < d.len then
				local k = 2 + math.floor((behind - 1) / d.len * (#shades - 1))
				out[r] = "|cff" .. shades[math.min(#shades, k)] .. ch[r] .. "|r"
			else
				out[r] = " "
			end
		end
		fs:SetText(table.concat(out, "\n"))
		fs:Show()
	end
	for c = cols + 1, #p.mcols do p.mcols[c]:Hide() end
	C.Title(p)
end

--- A frame of the rain: drops fall, letters flicker; drawn MATRIX_FPS times a second.
local function MatrixStep(p, elapsed)
	local m = p.matrix
	m.t = (m.t or 0) + elapsed
	if m.t < 1 / C.MATRIX_FPS then return end
	local dt = m.t
	m.t = 0
	if m.drops then
		for c, d in ipairs(m.drops) do
			d.head = d.head + d.speed * dt
			if d.head - d.len > m.rows then m.drops[c] = MatrixDrop(m, m.rows) end
			if math.random() < 0.3 then
				local ch = m.chars[c]
				ch[math.random(#ch)] = MatrixChar()
			end
		end
	end
	p.dirty = true
end
C.MatrixStep = MatrixStep

function C.Matrix(p)
	p.matrix = { t = 0 }
	p.edit:SetText("")
	p.dirty = true
end

function C.StopMatrix(p)
	p.matrix = nil
	for _, fs in ipairs(p.mcols or {}) do fs:Hide() end
	p.edit:SetText("")
	p.dirty = true
end

--- A pane's scrollback and input line, from the top down; once full, the newest lines at the bottom.
function C.Draw(p)
	if p.matrix then p.dirty = false return DrawMatrix(p) end
	if p.pager then p.dirty = false return DrawPager(p) end
	p.dirty = false
	local lh = LineH(p)
	local h = p.body:GetHeight() or 0
	local rows = math.max(1, math.floor((h - 4) / lh))
	local input = not p.app
	local outRows = rows - (input and 1 or 0)
	local n = #p.lines
	p.offset = math.max(0, math.min(p.offset, math.max(0, n - outRows)))
	local last = n - p.offset
	local first = math.max(1, last - outRows + 1)
	local stops = Stops(p, p.lines, first, last)
	local hx, most, wide = SideOf(p, p.lines, first, last, stops)
	p.view = { lines = p.lines, first = first, count = math.max(0, last - first + 1), stops = stops, hx = hx, most = most, wide = wide }
	local shown = 0
	for i = 1, math.max(outRows, #p.rows) do
		local idx = first + i - 1
		if i <= outRows and idx <= last and idx >= 1 then
			local r = Row(p, i)
			r:SetHeight(lh)
			SetRow(p, r, p.lines[idx], stops, -hx, -2 - (i - 1) * lh)
			r:Show()
			shown = i
		elseif p.rows[i] then
			HideParts(p.rows[i], true)
		end
	end
	p.prompt:ClearAllPoints()
	p.prompt:SetPoint("TOPLEFT", p.body, "TOPLEFT", 4, -2 - shown * lh)
	p.prompt:SetHeight(lh)
	p.prompt:SetShown(input and not p.job)
	p.edit:SetShown(input)
	if input then C.UpdateInput(p) end
	if p.job then p.caret:Hide() end
	C.DrawSelection(p)
	C.Title(p)
end

function C.Title(p)
	local i = IndexOf(p) or 0
	local mine = p == focus
	local badge = mine and Paint("cyan", " " .. i .. " ") or Paint("dim", " " .. i .. " ")
	p.title:SetText(badge .. " " .. Paint(mine and "text" or "dim", SH.Literal(FS.Pretty(p.sh.cwd))))
	local right = ""
	if p.app then right = Paint("magenta", AppName(p.app))
	elseif p.job then right = Paint("yellow", SH.Literal(ns.Cut and ns.Cut(p.jobText or "", 40) or (p.jobText or "")))
	end
	if p.offset > 0 then right = Paint("orange", "[+" .. p.offset .. "] ") .. right end
	local v = p.view
	if v and (v.most or 0) > 0 and not p.matrix then
		local cw = math.max(1, Width("0", p))
		right = Paint("orange", ("[col %d/%d] "):format(math.floor((v.hx or 0) / cw) + 1, math.ceil((v.wide or 0) / cw))) .. right
	end
	p.titleRight:SetText(right)
	local er, eg, eb = RGB(mine and (PAL.focus or Theme.Get().accent) or PAL.edge)
	p.frame:SetBackdropBorderColor(er, eg, eb, 1)
end

function C.Status()
	if not status then return end
	local parts = { Paint("green", "[" .. FS.Host() .. "]") }
	for i, p in ipairs(panes) do
		local s = i .. ":" .. (What(p):match("%S+") or "tsh")
		parts[#parts + 1] = p == focus and Paint("cyan", s .. "*") or Paint("dim", s)
	end
	parts[#parts + 1] = Paint("dim", "  " .. layout .. (zoomed and " (zoom)" or ""))
	if C.prefix then parts[#parts + 1] = Paint("yellow", "  ^B") end
	status:SetText(table.concat(parts, "  "))
	local note = C.SelectionNote() or C.hoverNote
	statusRight:SetText((note and Paint("yellow", note) or C.usageNote
		or Paint("dim", L["` step out   Ctrl+B then c pane, x close, o next   help   drag to copy"])) .. "   " .. Paint("text", date and date("%H:%M") or ""))
end

----------------------------------------------------------------------
-- Tiling
----------------------------------------------------------------------

--- Each pane's rectangle { x, y, w, h } (from the area's top left) for n panes in a layout.
function C.Rects(n, mode, w, h, gap, focusIdx)
	local r = {}
	local function R(x, y, rw, rh) return { x = x, y = y, w = rw, h = rh } end
	if n == 0 then return r end
	if mode == "mono" then
		for i = 1, n do r[i] = (i == (focusIdx or 1)) and R(0, 0, w, h) or false end
		return r
	end
	if n == 1 then r[1] = R(0, 0, w, h) return r end
	local half, halfH = (w - gap) / 2, (h - gap) / 2
	if mode == "wide" then
		r[1] = R(0, 0, w, halfH)
		local cw = (w - gap * (n - 2)) / (n - 1)
		for i = 2, n do r[i] = R((i - 2) * (cw + gap), halfH + gap, cw, halfH) end
		return r
	end
	if mode == "tall" or (mode == "grid" and n == 3) then
		r[1] = R(0, 0, half, h)
		local ch = (h - gap * (n - 2)) / (n - 1)
		for i = 2, n do r[i] = R(half + gap, (i - 2) * (ch + gap), half, ch) end
		return r
	end
	-- grid: 2 side by side, 4 as two rows of two
	if n == 2 then r[1], r[2] = R(0, 0, half, h), R(half + gap, 0, half, h) return r end
	r[1], r[2] = R(0, 0, half, halfH), R(half + gap, 0, half, halfH)
	r[3], r[4] = R(0, halfH + gap, half, halfH), R(half + gap, halfH + gap, half, halfH)
	return r
end

----------------------------------------------------------------------
-- Tiling as a tree (the "tile" layout, the default: i3's and bspwm's way). A split halves the pane it's made from (side by
-- side when that pane is wider than tall, else one above the other) and leaves the others where they are; closing a
-- pane gives its room to the one it was split with. A node is { pane = p }, or { dir = "v" (side by side) | "h"
-- (stacked), ratio (the first part's share), a, b }. The gaps between panes can be dragged to move a split, a double
-- click evens it. grid, tall, wide and mono still lay the panes out their own way (C.Rects); the tree is kept for tile.
----------------------------------------------------------------------

C.RATIO_MIN, C.RATIO_MAX = 0.12, 0.88 -- (how far a split can be dragged)
C.GRAB = 4 -- (px either side of a gap that still grabs it)
C.DOUBLE = 0.35 -- (s: two clicks on a gap this close even it)
local tree
function C.Tree() return tree end -- (tests)

local function FindLeaf(node, p)
	if not node then return nil end
	if node.pane then return node.pane == p and node or nil end
	return FindLeaf(node.a, p) or FindLeaf(node.b, p)
end

local function Leaves(node, out)
	out = out or {}
	if not node then return out end
	if node.pane then out[#out + 1] = node.pane return out end
	Leaves(node.a, out)
	Leaves(node.b, out)
	return out
end

--- The tree's rectangles: pane -> { x, y, w, h }; and its splits, each { node, x, y, w, h (the gap), from, len (the
--- room split, along its direction) }.
function C.TreeRects(node, x, y, w, h, gap, rects, splits)
	rects, splits = rects or {}, splits or {}
	if not node then return rects, splits end
	if node.pane then
		rects[node.pane] = { x = x, y = y, w = w, h = h }
		return rects, splits
	end
	if node.dir == "v" then
		local aw = math.floor((w - gap) * node.ratio + 0.5)
		C.TreeRects(node.a, x, y, aw, h, gap, rects, splits)
		C.TreeRects(node.b, x + aw + gap, y, w - aw - gap, h, gap, rects, splits)
		splits[#splits + 1] = { node = node, x = x + aw, y = y, w = gap, h = h, from = x, len = w - gap }
	else
		local ah = math.floor((h - gap) * node.ratio + 0.5)
		C.TreeRects(node.a, x, y, w, ah, gap, rects, splits)
		C.TreeRects(node.b, x, y + ah + gap, w, h - ah - gap, gap, rects, splits)
		splits[#splits + 1] = { node = node, x = x, y = y + ah, w = w, h = gap, from = y, len = h - gap }
	end
	return rects, splits
end

local function Area()
	local W, H = frame and frame:GetWidth() or 0, frame and frame:GetHeight() or 0
	return W - C.PAD * 2, H - C.PAD * 2 - C.STATUS_H
end

--- `p` into the tree: the pane it was split from halved (none: beside everything there is).
function C.TreeAdd(p, from)
	if not tree then tree = { pane = p } return end
	local leaf = from and FindLeaf(tree, from)
	local w, h = Area()
	local rect
	if leaf then
		rect = (C.TreeRects(tree, 0, 0, w, h, C.GAP))[from]
	else
		leaf, rect = tree, { w = w, h = h }
	end
	local dir = (rect and rect.h > rect.w) and "h" or "v"
	local old = { pane = leaf.pane, dir = leaf.dir, ratio = leaf.ratio, a = leaf.a, b = leaf.b }
	leaf.pane, leaf.dir, leaf.ratio, leaf.a, leaf.b = nil, dir, 0.5, old, { pane = p }
end

--- `p` out of the tree: the pane it was split with takes its room.
function C.TreeRemove(p)
	if not tree then return end
	if tree.pane == p then tree = nil return end
	local function Walk(node)
		if not node or node.pane then return false end
		for _, side in ipairs({ "a", "b" }) do
			local child = node[side]
			if child.pane == p then
				local other = side == "a" and node.b or node.a
				node.pane, node.dir, node.ratio, node.a, node.b = other.pane, other.dir, other.ratio, other.a, other.b
				return true
			end
			if Walk(child) then return true end
		end
		return false
	end
	Walk(tree)
end

--- The tree made again when it doesn't hold exactly the panes there are (each split from the one before it).
local function TreeCheck()
	local have, n = {}, 0
	for _, q in ipairs(Leaves(tree)) do have[q] = true; n = n + 1 end
	local ok = n == #panes
	for _, q in ipairs(panes) do if not have[q] then ok = false end end
	if ok then return end
	tree = nil
	for i, q in ipairs(panes) do C.TreeAdd(q, panes[i - 1]) end
end
C.TreeCheck = TreeCheck

--- The tree as saved: a pane is its place in the list, a split { d, r, a, b }.
function C.TreeSave(node)
	if not node then return nil end
	if node.pane then return IndexOf(node.pane) end
	return { d = node.dir, r = node.ratio, a = C.TreeSave(node.a), b = C.TreeSave(node.b) }
end

--- A saved tree back over the panes there are (anything it doesn't fit: made again).
function C.TreeLoad(saved)
	local function Load(t)
		if type(t) == "number" then return panes[t] and { pane = panes[t] } or nil end
		if type(t) ~= "table" or (t.d ~= "v" and t.d ~= "h") then return nil end
		local a, b = Load(t.a), Load(t.b)
		if not (a and b) then return nil end
		local r = math.max(C.RATIO_MIN, math.min(C.RATIO_MAX, tonumber(t.r) or 0.5))
		return { dir = t.d, ratio = r, a = a, b = b }
	end
	tree = Load(saved)
	TreeCheck()
end

--- The two panes' places swapped in the tree (Ctrl+Enter's promote, in tile).
local function TreeSwap(p, q)
	local a, b = FindLeaf(tree, p), FindLeaf(tree, q)
	if a and b then a.pane, b.pane = q, p end
end

-- dragging a gap
local drag, lastDown
local divider

--- The mouse over the console's tiling area: x, y from its top left.
local function AreaCursor()
	local x, y = GetCursorPosition()
	local sc = tonumber(frame:GetEffectiveScale()) or 1
	local left, top = tonumber(frame:GetLeft()) or 0, tonumber(frame:GetTop()) or 0
	return (tonumber(x) or 0) / sc - left - C.PAD, top - (tonumber(y) or 0) / sc - C.PAD
end

--- The split whose gap is at x, y (area coordinates), or nil. Only in tile, not zoomed.
function C.SplitAt(x, y)
	if layout ~= "tile" or zoomed then return nil end
	for _, sp in ipairs(C.splits or {}) do
		local g = C.GRAB
		if x >= sp.x - g and x <= sp.x + sp.w + g and y >= sp.y - g and y <= sp.y + sp.h + g then return sp end
	end
	return nil
end

--- A gap's split moved to x, y (area coordinates).
function C.DragTo(sp, x, y)
	local at = sp.node.dir == "v" and x or y
	local r = (at - sp.from - C.GAP / 2) / math.max(1, sp.len)
	sp.node.ratio = math.max(C.RATIO_MIN, math.min(C.RATIO_MAX, r))
	C.Layout(true)
end

--- The mouse pressed on the console (not on a pane): a gap grabbed; a second press on it soon after evens it.
function C.GapDown()
	if not GetCursorPosition then return end
	local x, y = AreaCursor()
	local sp = C.SplitAt(x, y)
	if not sp then return end
	local now = GetTime()
	if lastDown and lastDown.node == sp.node and now - lastDown.t < C.DOUBLE then
		sp.node.ratio = 0.5
		lastDown, drag = nil, nil
		C.Layout(true)
		return
	end
	lastDown = { node = sp.node, t = now }
	drag = sp
end

function C.GapUp() drag = nil end

--- A frame while a gap is held: the split follows the mouse; let go, it stays.
function C.GapTick()
	if not drag then return end
	if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then drag = nil return end
	if not GetCursorPosition then return end
	local x, y = AreaCursor()
	C.DragTo(drag, x, y)
	-- (the split's gap moved: the one held now is its new place)
	for _, sp in ipairs(C.splits or {}) do if sp.node == drag.node then drag = sp end end
end

--- The gap under the mouse lit (in tile), so it's seen it can be dragged.
function C.GapHover()
	if not (frame and GetCursorPosition) then return end
	local sp = drag or (frame.IsMouseOver and frame:IsMouseOver() == true and C.SplitAt(AreaCursor()))
	if not sp then
		if divider and divider:IsShown() then divider:Hide() end
		return
	end
	if not divider then
		divider = frame:CreateTexture(nil, "OVERLAY")
		divider:SetTexture(WHITE)
		local r, g, b = RGB(PAL.caret)
		divider:SetVertexColor(r, g, b, 0.6)
	end
	-- (placed again only when the gap under the mouse is another or moved: this runs every frame)
	if divider.x ~= sp.x or divider.y ~= sp.y or divider.w ~= sp.w or divider.h ~= sp.h then
		divider.x, divider.y, divider.w, divider.h = sp.x, sp.y, sp.w, sp.h
		divider:ClearAllPoints()
		divider:SetPoint("TOPLEFT", frame, "TOPLEFT", C.PAD + sp.x, -C.PAD - sp.y)
		divider:SetSize(math.max(1, sp.w), math.max(1, sp.h))
	end
	if not divider:IsShown() then divider:Show() end
end

C.GLIDE = 0.2 -- (s: a pane gliding to its new place when the tiling changes)
local gliding = false

local function Place(p, x, y, w, h)
	p.frame:ClearAllPoints()
	p.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", C.PAD + x, -C.PAD - y)
	p.frame:SetSize(math.max(1, w), math.max(1, h))
	p.shownRect = { x = x, y = y, w = w, h = h }
end

local function Same(a, b)
	return math.abs(a.x - b.x) < 0.5 and math.abs(a.y - b.y) < 0.5 and math.abs(a.w - b.w) < 0.5 and math.abs(a.h - b.h) < 0.5
end

--- Tiles the panes. They glide from where they were to where they go (a new pane out of the one it was split from,
--- fading in), unless `snap` (opening, the screen resized) or animations are off.
function C.Layout(snap)
	if not frame then return end
	local W, H = frame:GetWidth() or 0, frame:GetHeight() or 0
	local areaW, areaH = W - C.PAD * 2, H - C.PAD * 2 - C.STATUS_H
	local mode = zoomed and "mono" or layout
	local rects
	C.splits = nil
	if mode == "tile" then
		TreeCheck()
		local byPane, splits = C.TreeRects(tree, 0, 0, areaW, areaH, C.GAP)
		rects, C.splits = {}, splits
		for i, q in ipairs(panes) do rects[i] = byPane[q] or false end
	else
		rects = C.Rects(#panes, mode, areaW, areaH, C.GAP, IndexOf(focus))
	end
	local animate = not snap and frame:IsShown() and Theme.Animation() ~= nil
	for i, p in ipairs(panes) do
		local rc = rects[i]
		if rc then
			p.rect = rc
			local from = p.shownRect or p.spawn
			p.spawn = nil
			if animate and from and not Same(from, rc) then
				p.glide = { from = from, t = 0 }
				gliding = true
				Place(p, from.x, from.y, from.w, from.h)
				if p.fadeIn then p.frame:SetAlpha(0) end
			else
				p.glide, p.fadeIn = nil, nil
				Place(p, rc.x, rc.y, rc.w, rc.h)
				p.frame:SetAlpha(1)
			end
			p.frame:Show()
		else
			p.frame:Hide()
			p.rect, p.shownRect, p.glide = nil, nil, nil
		end
		if p.app then C.PlaceApp(p) end
		p.dirty = true
	end
	C.Status()
end

--- A frame of the glide: eased out (fast, then settling).
local function Glide(elapsed)
	if not gliding then return end
	gliding = false
	for _, p in ipairs(panes) do
		local g, rc = p.glide, p.rect
		if g and rc then
			g.t = math.min(1, g.t + elapsed / C.GLIDE)
			local e = 1 - (1 - g.t) ^ 3
			local a = g.from
			Place(p, a.x + (rc.x - a.x) * e, a.y + (rc.y - a.y) * e, a.w + (rc.w - a.w) * e, a.h + (rc.h - a.h) * e)
			if p.fadeIn then p.frame:SetAlpha(e) end
			if p.app then C.PlaceApp(p) end
			p.dirty = true
			if g.t >= 1 then p.glide, p.fadeIn = nil, nil; p.frame:SetAlpha(1) else gliding = true end
		end
	end
end
C.Glide = Glide

----------------------------------------------------------------------
-- Focus and keys
----------------------------------------------------------------------

local function Keyboard(rec, on)
	if rec and rec.frame and rec.frame.EnableKeyboard then pcall(rec.frame.EnableKeyboard, rec.frame, on) end
end

function C.Focus(p)
	if not p then return end
	local old = focus
	focus = p
	for _, q in ipairs(panes) do
		if q.app then Keyboard(q.app, q == p and frame:IsShown()) end
	end
	if p.app then
		p.edit:ClearFocus()
	elseif frame:IsShown() then
		p.edit:SetFocus()
	end
	if zoomed and old ~= p then C.Layout() end
	for _, q in ipairs(panes) do q.dirty = true end
	C.Status()
end

function C.Cycle(step)
	local i = IndexOf(focus) or 1
	local n = #panes
	if n == 0 then return end
	C.Focus(panes[((i - 1 + step) % n) + 1])
end

--- The pane next to the focused one that way (by their centres).
function C.Toward(dir)
	if not (focus and focus.rect) then return end
	local a = focus.rect
	local ax, ay = a.x + a.w / 2, a.y + a.h / 2
	local best, bestD
	for _, p in ipairs(panes) do
		local b = p.rect
		if p ~= focus and b then
			local bx, by = b.x + b.w / 2, b.y + b.h / 2
			local dx, dy = bx - ax, by - ay
			local ok = (dir == "LEFT" and dx < -1) or (dir == "RIGHT" and dx > 1) or (dir == "UP" and dy < -1) or (dir == "DOWN" and dy > 1)
			if ok then
				local d = dx * dx + dy * dy
				if not bestD or d < bestD then best, bestD = p, d end
			end
		end
	end
	if best then C.Focus(best) end
end

--- The focused pane to the first place (the big one in tall, wide and grid with three).
function C.Promote()
	local i = IndexOf(focus)
	if not i or i == 1 then return end
	if layout == "tile" then TreeSwap(focus, panes[1]) end
	table.remove(panes, i)
	table.insert(panes, 1, focus)
	C.Layout()
end

function C.NextLayout()
	local i = 1
	for k, m in ipairs(C.LAYOUTS) do if m == layout then i = k end end
	layout = C.LAYOUTS[i % #C.LAYOUTS + 1]
	zoomed = false
	C.Layout()
	Print(focus, Paint("dim", L["layout: "]) .. Paint("cyan", layout))
end

C.SIDE_CHARS = 8 -- (characters a notch of Shift+wheel slides the lines)

--- Slides a pane's lines sideways by px (more: further right along the long lines), as far as the widest shown needs.
function C.Side(p, px)
	local v = p.view
	p.hx = math.max(0, math.min(v and v.most or 0, (v and v.hx or 0) + px))
	p.dirty = true
end

--- Half the pane's width (px): what Left/Right slide the lines by (as less -S does).
function C.HalfWidth(p) return math.max(1, math.floor(((p.body:GetWidth() or 0) - 8) / 2)) end

function C.Scroll(p, lines)
	if p.pager then
		p.pager.top = math.max(1, p.pager.top - lines)
		p.dirty = true
		return
	end
	p.offset = math.max(0, p.offset + lines)
	p.dirty = true
end

----------------------------------------------------------------------
-- The pager (less, Ctrl+R): lines kept whole (not the scrollback's 2000), read a page at a time, searched
----------------------------------------------------------------------

--- Opens lines in a pane's pager. opts: title, atEnd (start at the last page), search (the search line open), dir
--- (-1: searching back, as ?).
function C.Pager(p, lines, opts)
	opts = opts or {}
	p.pager = { lines = lines or {}, top = 1, title = opts.title or "less", mode = opts.search and "search" or "keys",
		dir = opts.dir or 1 }
	if opts.atEnd then p.pager.top = math.max(1, #p.pager.lines) end
	p.edit:SetText("")
	p.dirty = true
	C.Status()
end

function C.ClosePager(p)
	p.pager, p.hx = nil, 0
	p.edit:SetText("")
	p.dirty = true
	C.Status()
end

--- The next line (dir 1) or one before (dir -1) from the top's that has what's searched for; the page moves there.
function C.PagerFind(p, dir)
	local pg = p.pager
	if not (pg and pg.search and pg.search ~= "") then return false end
	local match = SH.Matcher(pg.search)
	local i = pg.top + dir
	while i >= 1 and i <= #pg.lines do
		if match(FS.Strip(pg.lines[i])) then
			pg.top, pg.note = i, nil
			p.dirty = true
			return true
		end
		i = i + dir
	end
	pg.note = L["Pattern not found"]
	p.dirty = true
	return false
end

--- One of less's keys (a character typed, or a key's name). True when it was one.
function C.PagerKey(p, k)
	local pg = p.pager
	local page = math.max(1, (pg.rows or 10) - 1)
	pg.note = nil
	if k == "q" or k == "Q" or k == "ESCAPE" then C.ClosePager(p) return true
	elseif k == " " or k == "f" or k == "PAGEDOWN" then pg.top = pg.top + page
	elseif k == "b" or k == "PAGEUP" then pg.top = math.max(1, pg.top - page)
	elseif k == "j" or k == "DOWN" or k == "ENTER" then pg.top = pg.top + 1
	elseif k == "k" or k == "UP" then pg.top = math.max(1, pg.top - 1)
	elseif k == "LEFT" then C.Side(p, -C.HalfWidth(p))
	elseif k == "RIGHT" then C.Side(p, C.HalfWidth(p))
	elseif k == "g" or k == "<" or k == "HOME" then pg.top = 1
	elseif k == "G" or k == ">" or k == "END" then pg.top = #pg.lines
	elseif k == "/" or k == "?" then pg.mode, pg.dir = "search", k == "?" and -1 or 1
	elseif k == "n" then C.PagerFind(p, pg.dir)
	elseif k == "N" then C.PagerFind(p, -pg.dir)
	else return false end
	p.dirty = true
	return true
end

--- What's typed in the search line is searched for (Enter); from the page's top, the way it was asked.
function C.PagerSearch(p)
	local pg = p.pager
	local text = p.edit:GetText() or ""
	pg.mode = "keys"
	p.edit:SetText("")
	if text ~= "" then pg.search = text end
	-- (the first look includes the top line itself)
	pg.top = pg.top - pg.dir
	if not C.PagerFind(p, pg.dir) then pg.top = pg.top + pg.dir end
	p.dirty = true
end

-- Ctrl+B, then a key (tmux's way): the window keys a browser keeps for itself (Ctrl+N, Ctrl+W, Ctrl+Tab on
-- uiforever.com) work there too. The key after it types nothing (each box's text, as the key left it, put back a frame later).
C.PREFIX_KEYS = {
	C = "split", ["5"] = "split", ["'"] = "split", N = "next", O = "next", P = "prev", X = "close", Z = "zoom",
	SPACE = "layout", ENTER = "promote", ["["] = "scrollback", LEFT = "LEFT", RIGHT = "RIGHT", UP = "UP", DOWN = "DOWN",
	["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["="] = "bigger", ["-"] = "smaller", ["0"] = "font",
}
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
C.prefix = false

local function KeepTexts()
	local keep = {}
	for _, q in ipairs(panes) do keep[q] = { q.edit:GetText() or "", q.edit.GetCursorPosition and q.edit:GetCursorPosition() or 0 } end
	C_Timer.After(0, function()
		for q, k in pairs(keep) do
			if (q.edit:GetText() or "") ~= k[1] then
				q.edit:SetText(k[1])
				if q.edit.SetCursorPosition then q.edit:SetCursorPosition(k[2]) end
			end
		end
	end)
end

--- The key after Ctrl+B. True: it was the prefix's (any key ends it: Esc and unknown keys do nothing).
local function PrefixKey(p, key)
	if MODIFIERS[key] then return true end
	C.prefix = false
	local what = C.PREFIX_KEYS[key]
	if what == "split" then C.Split(p)
	elseif what == "next" then C.Cycle(1)
	elseif what == "prev" then C.Cycle(-1)
	elseif what == "close" then C.ClosePane(p)
	elseif what == "zoom" then zoomed = not zoomed; C.Layout()
	elseif what == "layout" then C.NextLayout()
	elseif what == "promote" then C.Promote()
	elseif what == "scrollback" then
		local copy = {}
		for i, l in ipairs(p.lines) do copy[i] = l end
		C.Pager(p, copy, { title = L["scrollback"], atEnd = true })
	elseif what == "bigger" then C.SetFontSize(C.FontSize(p) + 1, p)
	elseif what == "smaller" then C.SetFontSize(C.FontSize(p) - 1, p)
	elseif what == "font" then C.SetFontSize(nil, p)
	elseif type(what) == "number" then if panes[what] then C.Focus(panes[what]) end
	elseif what then C.Toward(what) end
	-- (after the key's work: a pane it opened has the keyboard, and the letter lands there next)
	KeepTexts()
	C.Status()
	return true
end

--- The console's own keys, wherever the keyboard is (a pane's box or a docked app). True when it was one.
function C.WindowKey(p, key)
	if ns.IsTickKey(key) then C.prefix = false C.Leave() return true end
	if C.prefix then return PrefixKey(p, key) end
	if not IsControlKeyDown() then return false end
	if key == "B" then C.prefix = true C.Status() return true end
	if key == "N" or key == "T" then C.Split(p)
	elseif key == "W" then C.ClosePane(p)
	elseif key == "TAB" then C.Cycle(IsShiftKeyDown() and -1 or 1)
	elseif key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN" then C.Toward(key)
	elseif key:match("^[1-4]$") then if panes[tonumber(key)] then C.Focus(panes[tonumber(key)]) end
	elseif key == "Z" then zoomed = not zoomed; C.Layout()
	elseif key == "SPACE" then C.NextLayout()
	elseif key == "ENTER" then C.Promote()
	elseif key == "=" or key == "+" or key == "NUMPADPLUS" then C.SetFontSize(C.FontSize(p) + 1, p)
	elseif key == "-" or key == "NUMPADMINUS" then C.SetFontSize(C.FontSize(p) - 1, p)
	elseif key == "0" or key == "NUMPAD0" then C.SetFontSize(nil, p)
	else return false end
	return true
end

local PAGER_NAMED = { PAGEUP = true, PAGEDOWN = true, UP = true, DOWN = true, HOME = true, END = true, LEFT = true, RIGHT = true }

function C.KeyDown(p, key)
	if C.WindowKey(p, key) then return end
	if p.matrix then
		if not MODIFIERS[key] then C.StopMatrix(p) end
		return
	end
	local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
	if p.pager then
		if p.pager.mode == "keys" and PAGER_NAMED[key] then C.PagerKey(p, key) end
		return
	end
	if p.isearch then return C.SearchKey(p, key, ctrl) end
	if ctrl and key == "R" and not p.job then return C.SearchStart(p) end
	if (key == "RIGHT" or key == "END") and not ctrl and not shift and p.suggestion then
		local text = p.edit:GetText() or ""
		local rest = p.suggestion
		if key == "RIGHT" and IsAltKeyDown and IsAltKeyDown() then rest = rest:match("^%s*[^%s/]+/?") or rest end
		p.edit:SetText(text .. rest)
		p.edit:SetCursorPosition(#text + #rest)
		return
	end
	local h = p.sh.history
	-- (Left/Right with nothing typed: the lines slide sideways, there being no cursor to move)
	if (key == "LEFT" or key == "RIGHT") and not ctrl and not shift and not p.job and (p.edit:GetText() or "") == ""
		and p.view and (p.view.most or 0) > 0 then
		C.Side(p, key == "LEFT" and -C.HalfWidth(p) or C.HalfWidth(p))
		return
	end
	if ctrl and key == "C" then
		if p.job then p.sh.cancelled = true
		elseif (p.edit:GetText() or "") ~= "" then
			Print(p, PromptText(p) .. SH.Highlight(p.sh, SH.Masked(p.edit:GetText()), true) .. Paint("dim", "^C"))
			p.edit:SetText("")
		end
	elseif ctrl and key == "L" then p.lines = {}; p.offset, p.hx = 0, 0; p.dirty = true
	elseif ctrl and key == "U" then p.edit:SetText("")
	elseif ctrl and key == "D" then if (p.edit:GetText() or "") == "" and not p.job then C.ClosePane(p) end
	elseif key == "PAGEUP" then C.Scroll(p, C.PageOf(p))
	elseif key == "PAGEDOWN" then C.Scroll(p, -C.PageOf(p))
	elseif shift and key == "UP" then C.Scroll(p, 1)
	elseif shift and key == "DOWN" then C.Scroll(p, -1)
	elseif ctrl and key == "HOME" then C.Scroll(p, #p.lines)
	elseif ctrl and key == "END" then C.Scroll(p, -#p.lines)
	elseif key == "UP" and not p.job then
		if #h == 0 then return end
		if not p.histIdx then p.draft = p.edit:GetText(); p.histIdx = #h + 1 end
		p.histIdx = math.max(1, p.histIdx - 1)
		p.edit:SetText(h[p.histIdx] or "")
		p.edit:SetCursorPosition(#(h[p.histIdx] or ""))
	elseif key == "DOWN" and not p.job then
		if not p.histIdx then return end
		p.histIdx = p.histIdx + 1
		local text = h[p.histIdx]
		if not text then text = p.draft or ""; p.histIdx = nil end
		p.edit:SetText(text)
		p.edit:SetCursorPosition(#text)
	end
end

----------------------------------------------------------------------
-- Ctrl+R: the history searched as you type (bash's reverse-i-search). The box holds what's searched for, the prompt
-- says so, the line found shows faint after it. Ctrl+R again: an older one. Enter runs it; Right, Left, Home, End, Tab,
-- Up or Down put it in the box to edit; Esc, Ctrl+G or Ctrl+C let go (the line as it was before).
----------------------------------------------------------------------

function C.SearchStart(p)
	local text = p.edit:GetText() or ""
	p.histIdx = nil
	p.isearch = { draft = text }
	C.SearchUpdate(p) -- (what was typed is searched for at once)
end

--- What's searched for changed: the newest line holding it.
function C.SearchUpdate(p)
	local is = p.isearch
	if not is then return end
	local q = p.edit:GetText() or ""
	local idx, line = SH.HistorySearch(p.sh, q)
	if idx then is.idx, is.line, is.failed = idx, line, false
	else is.failed = q ~= "" end
	if q == "" then is.idx, is.line = nil, nil end
	C.UpdateInput(p)
end

--- Ctrl+R again: an older line holding it (not the same text twice).
function C.SearchOlder(p)
	local is = p.isearch
	local q = p.edit:GetText() or ""
	local idx, line = is.idx, is.line
	repeat idx, line = SH.HistorySearch(p.sh, q, idx) until not idx or line ~= is.line
	if idx then is.idx, is.line, is.failed = idx, line, false else is.failed = q ~= "" end
	C.UpdateInput(p)
end

--- Out of the search: the line found in the box (`take`), else the line as it was.
function C.SearchEnd(p, take)
	local is = p.isearch
	if not is then return end
	p.isearch = nil
	local text = take and is.line or is.draft or ""
	p.edit:SetText(text)
	p.edit:SetCursorPosition(#text)
	C.UpdateInput(p)
end

local SEARCH_TAKES = { LEFT = true, RIGHT = true, HOME = true, END = true, UP = true, DOWN = true }

function C.SearchKey(p, key, ctrl)
	if ctrl and key == "R" then C.SearchOlder(p)
	elseif ctrl and (key == "G" or key == "C") then C.SearchEnd(p, false)
	elseif SEARCH_TAKES[key] then C.SearchEnd(p, true)
	end
end

function C.PageOf(p)
	return math.max(1, math.floor(((p.body:GetHeight() or 0) - 4) / LineH(p)) - 2)
end

----------------------------------------------------------------------
-- Running
----------------------------------------------------------------------

local function Done(p)
	p.job, p.jobText = nil, nil
	p.sh.yieldable = false
	p.dirty = true
	if p.closeAfter then p.closeAfter = nil; C.ClosePane(p) end
	C.Status()
end

local function Step(p, deadline)
	p.sh.yieldable = true
	p.sh.deadline = deadline
	local ok, err = coroutine.resume(p.job)
	if not ok then
		if err == SH.CANCEL then Print(p, Paint("dim", "^C")); p.sh.status = 130
		else Print(p, Paint("red", "tsh: " .. SH.Literal(tostring(err)))) end
	end
	if coroutine.status(p.job) == "dead" then Done(p) end
end

--- Runs a line in a pane (what Enter does).
function C.Run(p, text)
	p.offset, p.hx = 0, 0
	p.histIdx, p.draft, p.isearch = nil, nil, nil
	p.since = 0
	Print(p, PromptText(p) .. SH.Highlight(p.sh, SH.Masked(text), true))
	if text:match("^%s*$") then return end
	p.sh.cancelled = false
	p.jobText = SH.Masked(text)
	p.job = coroutine.create(function() return SH.Run(p.sh, text) end)
	launcher = p
	Step(p, (debugprofilestop and debugprofilestop() or 0) + C.BUDGET_MS)
end

function C.Enter(p)
	if p.matrix then C.StopMatrix(p) return end
	if p.pager then
		if p.pager.mode == "search" then C.PagerSearch(p) else C.PagerKey(p, "ENTER") end
		return
	end
	if p.job then return end
	if p.isearch then C.SearchEnd(p, true) end
	local text = p.edit:GetText() or ""
	p.edit:SetText("")
	C.Run(p, text)
end

function C.Complete(p)
	if p.isearch then C.SearchEnd(p, true) return end
	if p.job then return end
	local text = p.edit:GetText() or ""
	local cur = p.edit.GetCursorPosition and p.edit:GetCursorPosition() or #text
	local new, pos, choices = SH.Complete(p.sh, text, cur)
	if choices and #choices > 0 then
		if #choices > C.MANY and not (p.tabAt and GetTime() - p.tabAt < C.TAB_AGAIN) then
			p.tabAt = GetTime()
			Print(p, Paint("dim", L["Display all %d possibilities? (Tab again)"]:format(#choices)))
			return
		end
		p.tabAt = nil
		Print(p, PromptText(p) .. SH.Highlight(p.sh, SH.Masked(text), true))
		C.Columns(p, choices)
		return
	end
	if new ~= text then
		p.edit:SetText(new)
		p.edit:SetCursorPosition(pos)
	end
end

--- Names packed into lines as wide as the pane.
function C.Columns(p, names)
	local room = math.max(100, (p.body:GetWidth() or 400) - 12)
	local sep = "   "
	local line, w = {}, 0
	local sepW = Width(sep, p)
	for i, n in ipairs(names) do
		if i > 500 then Print(p, Paint("dim", L["... and %d more"]:format(#names - 500))) break end
		local lit = SH.Literal(n)
		local nw = Width(lit, p)
		if #line > 0 and w + sepW + nw > room then
			Print(p, table.concat(line, sep))
			line, w = {}, 0
		end
		line[#line + 1] = lit
		w = w + (#line > 1 and sepW or 0) + nw
	end
	if #line > 0 then Print(p, table.concat(line, sep)) end
end

----------------------------------------------------------------------
-- Apps in panes
----------------------------------------------------------------------

--- An app's frame: Panel registers each app and its frame in the same order.
local function FrameOf(app)
	local apps, frames = Panel.Registered(), Panel.Frames()
	for i, a in ipairs(apps) do if a == app then return frames[i] end end
	return nil
end

function C.PlaceApp(p)
	local rec = p.app
	if not rec then return end
	local f = rec.frame
	if not p.rect or not frame:IsShown() then rec.hidden = true; f:Hide() return end -- (zoomed past, or stepped out)
	rec.hidden = nil
	if not f:IsShown() and not rec.closed then f:Show() end
	local fw, fh = f:GetWidth() or 0, f:GetHeight() or 0
	local bw, bh = (p.body:GetWidth() or 0) - 8, (p.body:GetHeight() or 0) - 8
	if fw <= 0 or fh <= 0 or bw <= 0 or bh <= 0 then return end
	local base = (frame:GetEffectiveScale() or 1) / ((UIParent and UIParent:GetEffectiveScale()) or 1)
	local s = math.max(0.35, math.min(1.4, math.min(bw / fw, bh / fh) * base))
	f:SetScale(s)
	f:ClearAllPoints()
	f:SetPoint("CENTER", p.body, "CENTER", 0, 0)
end

--- Puts an app that just opened into a pane: the one whose command opened it, else a free one, else a new one.
function C.Dock(app, p)
	local f = FrameOf(app)
	if not f then return end
	if not p or p.app then
		p = nil
		for _, q in ipairs(panes) do if not q.app and not q.job then p = q break end end
		if not p and #panes < C.MAX then p = C.Split(focus, true) end
		if not p then
			app.Close()
			Print(focus, Paint("red", L["no room: four panes, each busy (Ctrl+W closes one)"]))
			return
		end
	end
	local rec = { app = app, frame = f, keyDown = f:GetScript("OnKeyDown"), strata = f:GetFrameStrata(), close = app.Close }
	app.Close = function(...)
		rec.closed = true
		return rec.close(...)
	end
	f:SetScript("OnKeyDown", function(self, key)
		local pane = docked[app]
		-- (the console's keys only while it shows: opened from Terminal meanwhile, the app is the app's own)
		if pane and C.IsShown() and C.WindowKey(pane, key) then
			Panel.Propagate(self, true)
			return
		end
		if rec.keyDown then rec.keyDown(self, key) end
	end)
	f:SetFrameStrata("FULLSCREEN")
	p.app = rec
	docked[app] = p
	C.PlaceApp(p)
	C.Focus(p)
	p.dirty = true
	C.Status()
end

--- An app's pane is a shell again (the app closed): its keys and place as they were.
function C.Undock(app, quiet)
	local p = docked[app]
	if not p then return end
	local rec = p.app
	docked[app] = nil
	p.app = nil
	if rec then
		app.Close = rec.close
		local f = rec.frame
		f:SetScript("OnKeyDown", rec.keyDown)
		pcall(f.SetFrameStrata, f, rec.strata or "DIALOG")
		pcall(f.EnableKeyboard, f, true)
		if not quiet then Print(p, Paint("dim", L["[%s exited]"]:format(AppName(rec)))) end
	end
	p.dirty = true
	if p == focus and frame and frame:IsShown() then p.edit:SetFocus() end
	C.Status()
end

function C.CloseApp(p)
	if not p.app then return end
	local app = p.app.app
	pcall(app.Close)
	C.Undock(app, true)
end

--- Apps that opened since (docked into the pane that ran the command) and docked apps that closed.
function C.PollApps()
	if not frame or not frame:IsShown() then return end
	for _, app in ipairs(Panel.Registered()) do
		if app ~= C and not docked[app] and type(app.IsShown) == "function" and app.IsShown() then
			C.Dock(app, launcher or focus)
		end
	end
	for app, p in pairs(docked) do
		local rec = p.app
		if rec and (rec.closed or (not rec.hidden and not app.IsShown())) then C.Undock(app) end
	end
end

-- Panel.Opening (an app opening) leaves the console and the apps in it alone while it shows.
function Panel.Keeps(other)
	return frame ~= nil and frame:IsShown() and (other == C or docked[other] ~= nil)
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

local function FontString(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
	fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end

NewPane = function()
	local p = { id = nextPid, lines = {}, rows = {}, offset = 0 }
	nextPid = nextPid + 1
	p.sh = SH.Session({
		history = History(),
		print = function(line) Print(p, line) end,
		clear = function() p.lines = {}; p.offset = 0; p.dirty = true end,
		ui = ui,
	})
	local f = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Panel.Flat(f)
	f:SetBackdropColor(RGB(PAL.pane))
	f:EnableMouse(true)
	f:SetScript("OnMouseDown", function(_, button)
		C.Focus(p)
		if button == "LeftButton" then C.SelectStart(p) end -- (a drag selects text to copy)
	end)
	f:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then C.SelectEnd(p) end end)
	if f.EnableMouseWheel then f:EnableMouseWheel(true) end
	f:SetScript("OnMouseWheel", function(_, delta)
		if IsShiftKeyDown and IsShiftKeyDown() then C.Side(p, -(delta or 0) * C.SIDE_CHARS * Width("0", p))
		else C.Scroll(p, (delta or 0) * 3) end
	end)
	p.frame = f

	local bar = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	bar:SetTexture(WHITE)
	bar:SetVertexColor(RGB(PAL.title))
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(C.TITLE_H)
	p.bar = bar
	p.title = FontString(f, Chrome())
	p.title:SetPoint("LEFT", bar, "LEFT", 4, 0)
	p.titleRight = FontString(f, Chrome())
	p.titleRight:SetJustifyH("RIGHT")
	p.titleRight:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", 4, -C.TITLE_H - 3)
	body:SetPoint("BOTTOMRIGHT", -4, 4)
	if body.SetClipsChildren then body:SetClipsChildren(true) end
	body:EnableMouse(false)
	p.body = body
	-- (the lines are drawn on a sheet inside the body's padding, and C.Side slides them along it. Each piece is cut to
	-- the sheet's edges by Fit: neither SetClipsChildren on a plain frame nor this ScrollFrame cut text in the game,
	-- lines ran on over the next pane, seen twice. The ScrollFrame stays for what clipping it does.)
	local clip = CreateFrame("ScrollFrame", nil, body)
	clip:SetPoint("TOPLEFT", 4, 0)
	clip:SetPoint("BOTTOMRIGHT", -4, 0)
	clip:EnableMouse(false)
	p.sheet = CreateFrame("Frame", nil, clip)
	p.sheet:SetSize(1, 1)
	p.sheet:EnableMouse(false)
	if clip.SetScrollChild then clip:SetScrollChild(p.sheet) end
	-- (a scroll child has no anchors: sized to the clip's room whenever that changes)
	clip:SetScript("OnSizeChanged", function(_, w, h) p.sheet:SetSize(math.max(1, w or 1), math.max(1, h or 1)) end)
	p.clip = clip

	p.prompt = FontString(body, Font(p))
	local eb = CreateFrame("EditBox", nil, body)
	eb:SetAutoFocus(false)
	eb:SetFontObject(Font(p))
	if eb.SetTextInsets then eb:SetTextInsets(0, 0, 0, 0) end
	eb:SetMaxLetters(1000)
	eb:SetScript("OnEnterPressed", function() C.Enter(p) end)
	eb:SetScript("OnTabPressed", function() C.Complete(p) end)
	eb:SetScript("OnEscapePressed", function(self)
		if p.matrix then C.StopMatrix(p) return end
		if p.pager then
			if p.pager.mode == "search" then p.pager.mode = "keys"; self:SetText(""); p.dirty = true
			else C.ClosePager(p) end
			return
		end
		if p.isearch then C.SearchEnd(p, false) return end
		if (self:GetText() or "") ~= "" then self:SetText("") else C.Leave() end
	end)
	eb:SetScript("OnKeyDown", function(_, key) C.KeyDown(p, key) end)
	eb:SetScript("OnTextChanged", function(self)
		local t = self:GetText() or ""
		if t:find("`", 1, true) then -- (the key that steps out is never typed)
			local pos = self:GetCursorPosition()
			self:SetText((t:gsub("`", "")))
			self:SetCursorPosition(math.max(0, pos - 1))
			return
		end
		if p.matrix and t ~= "" then self:SetText("") C.StopMatrix(p) return end -- (a key typed stops the rain)
		-- (the pager reads typed keys as its own: q, Space, b, j, k, g, G, /, ?, n, N; the box stays empty)
		if p.pager and p.pager.mode == "keys" and t ~= "" then
			self:SetText("")
			for ch in t:gmatch(".") do if p.pager then C.PagerKey(p, ch) end end
			return
		end
		if p.histIdx and t ~= (p.sh.history[p.histIdx] or "") then p.histIdx = nil end
		if p.isearch then C.SearchUpdate(p) return end
		C.UpdateInput(p)
	end)
	eb:SetScript("OnCursorChanged", function() if p.overlay then C.UpdateInput(p) end end)
	eb:SetScript("OnEditFocusGained", function() if focus ~= p then C.Focus(p) end C.UpdateInput(p) end)
	eb:SetScript("OnEditFocusLost", function() p.caret:Hide() end)
	p.edit = eb
	p.overlay = FontString(body, Font(p))
	p.overlay:SetPoint("LEFT", eb, "LEFT", 0, 0)
	p.caret = body:CreateTexture(nil, "ARTWORK")
	p.caret:SetTexture(WHITE)
	local cr, cg, cb = RGB(PAL.caret)
	p.caret:SetVertexColor(cr, cg, cb, 0.55)
	p.caret:Hide()
	return p
end

local function Fit()
	local W = UIParent and UIParent:GetWidth() or 1200
	local H = UIParent and UIParent:GetHeight() or 800
	frame:SetSize(math.floor(W * 0.94), math.floor(H * 0.9))
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	C.fitW, C.fitH = W, H
end

local sincePoll, sinceClock, blink = 0, 0, 0
----------------------------------------------------------------------
-- Selecting with the mouse: drag over a pane's lines and the text is put, selected, into a box of its own that takes
-- the keyboard, so Ctrl+C copies it (an addon can't write the clipboard: only a real box and the player's Ctrl+C can).
-- Any other key goes on to the pane as usual and lets the selection go.
----------------------------------------------------------------------

C.SEL_COLOR = "33467c"
C.CELL_JOIN = "  " -- (between an ls -l line's columns, copied)
C.COPIED_FOR = 3 -- (s: "copied" said in the status line)

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

--- A drawn line's parts as plain text (its columns, or itself whole), each a list of its characters.
local function Parts(line)
	line = line:gsub("|Htsh:.-|h|h", "")
	local out = {}
	for j, c in ipairs(Cells(line) or { line }) do
		local chars = {}
		for ch in FS.Strip(c):gmatch(CHAR) do chars[#chars + 1] = ch end
		out[j] = chars
	end
	return out
end

local function Prefix(chars, k) return table.concat(chars, "", 1, k) end

local function Before(a, b)
	if a.idx ~= b.idx then return a.idx < b.idx end
	if a.j ~= b.j then return a.j < b.j end
	return a.k < b.k
end

--- The place under x, y (px from the body's top left): { idx = the line, j = its part, k = characters before }.
local function PosAt(p, x, y)
	local v = p.view
	if not v or v.count < 1 then return nil end
	local i = math.max(1, math.min(v.count, math.floor((y - 2) / LineH(p)) + 1))
	local idx = v.first + i - 1
	local parts = Parts(v.lines[idx] or "")
	x = x - 4 + (v.hx or 0)
	local j = 1
	for n = 2, #parts do if x >= (v.stops[n] or math.huge) then j = n end end
	local chars = parts[j]
	local rel = x - (#parts > 1 and (v.stops[j] or 0) or 0)
	local k, before = #chars, 0
	for n = 1, #chars do
		local w = Width(SH.Literal(Prefix(chars, n)), p)
		if rel < (before + w) / 2 then k = n - 1 break end
		before = w
	end
	return { idx = idx, j = j, k = k }
end

--- Where a place is drawn on its row (px from the body's left).
local function XOf(p, parts, j, k)
	local base = #parts > 1 and (p.view.stops[j] or 0) or 0
	return 4 - (p.view.hx or 0) + base + (k > 0 and Width(SH.Literal(Prefix(parts[j], k)), p) or 0)
end

--- The selection's two ends in order, or nil.
local function Ends(s)
	if not (s and s.b) then return nil end
	if Before(s.b, s.a) then return s.b, s.a end
	return s.a, s.b
end

--- The selected text: each line's parts joined by C.CELL_JOIN, cut at the two ends, the lines by "\n".
function C.SelectedText(p)
	local a, b = Ends(p.sel)
	if not a then return nil end
	local join = {}
	for ch in C.CELL_JOIN:gmatch(CHAR) do join[#join + 1] = ch end
	local out = {}
	for idx = a.idx, b.idx do
		local parts = Parts(p.sel.lines[idx] or "")
		local chars, startOf = {}, {}
		for j, part in ipairs(parts) do
			if j > 1 then for _, ch in ipairs(join) do chars[#chars + 1] = ch end end
			startOf[j] = #chars
			for _, ch in ipairs(part) do chars[#chars + 1] = ch end
		end
		local from = idx == a.idx and startOf[a.j] + a.k + 1 or 1
		local to = idx == b.idx and startOf[b.j] + b.k or #chars
		out[#out + 1] = from <= to and table.concat(chars, "", from, to) or ""
	end
	return table.concat(out, "\n")
end

--- The selection's bands behind the lines shown.
function C.DrawSelection(p)
	p.bands = p.bands or {}
	local v, used = p.view, 0
	local a, b = Ends(p.sel)
	if a and v and p.sel.lines == v.lines then
		local lh = LineH(p)
		local r, g, bl = RGB(C.SEL_COLOR)
		for i = 1, v.count do
			local idx = v.first + i - 1
			if idx >= a.idx and idx <= b.idx then
				local parts = Parts(v.lines[idx] or "")
				local x1 = idx == a.idx and XOf(p, parts, a.j, a.k) or XOf(p, parts, 1, 0)
				local x2 = idx == b.idx and XOf(p, parts, b.j, b.k) or (XOf(p, parts, #parts, #parts[#parts]) + Width("n", p))
				x1, x2 = math.max(4, x1), math.min((p.body:GetWidth() or 0) - 4, x2) -- (a band's part slid out of sight)
				if x2 > x1 then
					used = used + 1
					local t = p.bands[used]
					if not t then
						t = p.body:CreateTexture(nil, "ARTWORK")
						t:SetTexture(WHITE)
						p.bands[used] = t
					end
					t:SetVertexColor(r, g, bl, 0.9)
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", p.body, "TOPLEFT", x1, -2 - (i - 1) * lh)
					t:SetSize(x2 - x1, lh)
					t:Show()
				end
			end
		end
	end
	for i = used + 1, #p.bands do p.bands[i]:Hide() end
end

--- The mouse over a pane's body: x, y from its top left.
local function Cursor(p)
	local x, y = GetCursorPosition()
	local sc = tonumber(p.body:GetEffectiveScale()) or 1
	local left, top = tonumber(p.body:GetLeft()) or 0, tonumber(p.body:GetTop()) or 0
	return (tonumber(x) or 0) / sc - left, top - (tonumber(y) or 0) / sc
end

local copyBox
--- The box the selection is put in (the keyboard's while a selection is ready): see C.CopyKey.
local function CopyBox()
	if copyBox then return copyBox end
	local b = CreateFrame("EditBox", nil, frame)
	b:SetMultiLine(true)
	b:SetAutoFocus(false)
	b:SetFontObject(Chrome())
	b:SetSize(1, 1)
	b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	b:SetAlpha(0)
	b:SetScript("OnKeyDown", function(self, key) C.CopyKey(self.pane, key) end)
	-- (a letter typed goes to the pane's line, as if the selection weren't there)
	b:SetScript("OnChar", function(self, ch)
		local p = self.pane
		if p and ch ~= "`" and ch ~= "\n" and ch ~= "\r" and p.edit.Insert then p.edit:Insert(ch) end
	end)
	b:SetScript("OnEscapePressed", function(self) C.SelectClear(self.pane, true) end)
	b:SetScript("OnEditFocusLost", function(self) if self.pane then C.SelectClear(self.pane) end end)
	copyBox = b
	return b
end
C.CopyBox = function() return copyBox end

--- What the status line says about the selection, or nil.
function C.SelectionNote()
	local n = C.selNote
	if n and n.untilT and (GetTime() or 0) > n.untilT then C.selNote = nil return nil end
	return n and n.text
end

function C.SelectStart(p)
	if p.app or p.matrix or not p.view then return end
	C.SelectClear(p)
	local pos = PosAt(p, Cursor(p))
	if pos then p.sel = { a = pos, lines = p.view.lines, dragging = true } end
end

function C.SelectMove(p)
	local s = p.sel
	if not (s and s.dragging and p.view and s.lines == p.view.lines) then return end
	local pos = PosAt(p, Cursor(p))
	if pos and not (s.b and pos.idx == s.b.idx and pos.j == s.b.j and pos.k == s.b.k) then
		s.b = pos
		C.DrawSelection(p)
	end
end

--- The drag ends: the text into the copy box, selected and holding the keyboard; nothing selected (a click), let go.
function C.SelectEnd(p)
	local s = p.sel
	if not (s and s.dragging) then return end
	C.SelectMove(p)
	s.dragging = false
	local text = C.SelectedText(p)
	if not text or text == "" then
		C.SelectClear(p)
		C.OpenLink(p, C.LinkAt(p, Cursor(p)), IsShiftKeyDown and IsShiftKeyDown())
		return
	end
	local box = CopyBox()
	box.pane = p
	box:Show()
	box:SetText(text)
	box:SetFocus()
	box:HighlightText()
	local _, lines = text:gsub("\n", "")
	C.selNote = { text = (lines == 0 and L["selected: Ctrl+C copies it"] or L["%d lines selected: Ctrl+C copies them"]:format(lines + 1)) }
	C.Status()
end

--- Lets the selection go (the pane's box takes the keyboard back with `refocus`).
function C.SelectClear(p, refocus)
	if not p then return end
	p.sel = nil
	C.DrawSelection(p)
	if copyBox and copyBox.pane == p then
		copyBox.pane = nil
		copyBox:SetText("")
		copyBox:ClearFocus()
		copyBox:Hide()
	end
	if C.selNote and not C.selNote.untilT then C.selNote = nil end
	if refocus and focus == p and C.IsShown() and not p.app then p.edit:SetFocus() end
	C.Status()
end

--- A key while a selection is ready. Ctrl+C: the box copies it (the game does that), then it's let go. Any other key:
--- the selection let go and the key the pane's, a moment later (a letter goes to the pane's line through OnChar).
function C.CopyKey(p, key)
	if not p or MODIFIERS[key] then return end
	if IsControlKeyDown() and key == "C" then
		C_Timer.After(0, function()
			C.SelectClear(p, true)
			C.selNote = { text = L["copied"], untilT = (GetTime() or 0) + C.COPIED_FOR }
			C.Status()
		end)
		return
	end
	C_Timer.After(0, function()
		C.SelectClear(p, true)
		if key == "ENTER" then C.Enter(p) else C.KeyDown(p, key) end
	end)
end

----------------------------------------------------------------------
-- Clicking what a command printed: a path the shell linked (SH.Link: ls, find, locate, grep's file names, search's rows)
-- opens it, a folder with cd and ls, a file with cat; Shift+click pins it; a suggestion's "→ search" runs that search.
-- Each runs in the pane as if typed (the line and its history), so what happened is there to read. Hovering one says
-- in the status line what a click does.
----------------------------------------------------------------------

--- The links in a drawn line's part (its text as the console gets it): { from, to (characters, as Parts counts them),
--- kind ("p" a path, "s" a search), target }.
local function LinksIn(raw)
	local out, n, i, open = {}, 0, 1, nil
	while i <= #raw do
		local c = raw:sub(i, i)
		local nx = raw:sub(i + 1, i + 1)
		if c ~= "|" then
			local ch = raw:match("^[%z\1-\127\194-\244][\128-\191]*", i) or c
			n, i = n + 1, i + #ch
		elseif nx == "|" then n, i = n + 1, i + 2
		elseif nx == "c" and raw:match("^|c%x%x%x%x%x%x%x%x", i) then i = i + 10
		elseif nx == "r" then i = i + 2
		elseif nx == "H" then
			local kind, target, after = raw:match("^|Htsh([ps]):(.-)|h()", i)
			if kind then
				open, i = { from = n + 1, kind = kind, target = target }, after
			else
				local _, e = raw:find("|h", i + 2, true)
				i = (e or #raw) + 1
			end
		elseif nx == "h" then
			if open then open.to = n; out[#out + 1] = open; open = nil end
			i = i + 2
		elseif nx == "T" or nx == "A" then
			local _, e = raw:find(nx == "T" and "|t" or "|a", i + 2, true)
			i = (e or #raw) + 1
		else n, i = n + 1, i + 1 end
	end
	return out
end
C.LinksIn = LinksIn

--- The link under x, y (px from the pane body's top left), or nil: only on its text, not the room after a line.
function C.LinkAt(p, x, y)
	local pos = PosAt(p, x, y)
	if not pos then return nil end
	local line = (p.view.lines[pos.idx] or ""):gsub("|Htsh:.-|h|h", "")
	local parts = Parts(line)
	local chars = parts[pos.j] or {}
	if x > XOf(p, parts, pos.j, #chars) + 2 then return nil end
	local rawPart = (Cells(line) or { line })[pos.j] or ""
	for _, l in ipairs(LinksIn(rawPart)) do
		if l.to and pos.k >= l.from - 1 and pos.k <= l.to then return l end
	end
	return nil
end

local function Quoted(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

--- What a click on a link runs (a folder: cd and ls; a file: cat; Shift: pin; a search link: search), or nil.
function C.LinkLine(link, shift)
	if not link then return nil end
	if link.kind == "s" then return "search " .. link.target end
	local node = FS.Resolve("/", link.target)
	if not node then return nil end
	if shift then return "pin " .. Quoted(link.target) end
	if node.kind == "file" then return "cat " .. Quoted(link.target) end
	return "cd " .. Quoted(link.target) .. " && ls"
end

--- A click on a link: what it stands for, run in the pane as if typed. True when something ran.
function C.OpenLink(p, link, shift)
	if not link or p.job or p.app or p.pager or p.matrix then return false end
	local line = C.LinkLine(link, shift)
	if not line then return false end
	C.Run(p, line)
	return true
end

--- What the status line says about the link under the mouse, or nil.
function C.LinkHint(link)
	if not link then return nil end
	if link.kind == "s" then return L["click: search %s"]:format(link.target) end
	local node = FS.Resolve("/", link.target)
	if not node then return nil end
	local name = link.target:match("[^/]+$") or link.target
	if node.kind == "file" then return L["click: cat %s   Shift+click: pin it"]:format(name) end
	return L["click: open %s"]:format(link.target)
end

local hoverX, hoverY
--- The link under the mouse, said in the status line (worked out only when the mouse moved).
function C.Hover()
	if not GetCursorPosition then return end
	local x, y = GetCursorPosition()
	if x == hoverX and y == hoverY then return end
	hoverX, hoverY = x, y
	local hint
	for _, p in ipairs(panes) do
		if p.view and not p.app and not (p.sel and p.sel.dragging) and p.body.IsMouseOver and p.body:IsMouseOver() == true then
			hint = C.LinkHint(C.LinkAt(p, Cursor(p)))
			break
		end
	end
	if hint ~= C.hoverNote then C.hoverNote = hint; C.Status() end
end

local function Tick(_, elapsed)
	elapsed = tonumber(elapsed) or 0
	-- the terminal opened over the console (its key, with no box of ours holding the keyboard): step out
	if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then C.Leave() return end
	local W, H = UIParent and UIParent:GetWidth(), UIParent and UIParent:GetHeight()
	if W and (C.fitW ~= W or C.fitH ~= H) then Fit(); C.Layout(true) end -- (numbers compared: no string made a frame)
	Glide(elapsed)
	for _, p in ipairs(panes) do if p.matrix and p.rect then MatrixStep(p, elapsed) end end
	local running = 0
	for _, p in ipairs(panes) do if p.job then running = running + 1 end end
	if running > 0 then
		local now = debugprofilestop and debugprofilestop() or 0
		local share = C.BUDGET_MS / running
		local list = {} -- (a command may close its pane: exit)
		for i, p in ipairs(panes) do list[i] = p end
		for _, p in ipairs(list) do
			if p.job then
				now = debugprofilestop and debugprofilestop() or now
				Step(p, now + share)
			end
		end
	end
	sincePoll = sincePoll + elapsed
	if sincePoll >= C.POLL then sincePoll = 0; C.PollApps() end
	for i = #panes, 1, -1 do
		local p = panes[i]
		if p and p.closeAfter and not p.job then p.closeAfter = nil; C.ClosePane(p) end
	end
	for _, p in ipairs(panes) do if p.dirty and p.rect then C.Draw(p) end end
	C.Hover()
	C.GapTick()
	C.GapHover()
	for _, p in ipairs(panes) do
		if p.sel and p.sel.dragging then
			C.SelectMove(p)
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then C.SelectEnd(p) end
		end
	end
	sinceClock = sinceClock + elapsed
	if sinceClock >= 1 then sinceClock = 0; C.Status() end
	-- the block caret breathes
	blink = blink + elapsed
	if focus and focus.caret and focus.caret:IsShown() then
		focus.caret:SetAlpha(0.35 + 0.35 * (1 + math.cos(blink * 4)) / 2)
	end
end

--- The scheme (SH.palette, theme) on the console's own parts; `map` (old colour -> new) recolours every pane's lines.
function C.ApplyTheme(map)
	local th = SH.palette or SH.ThemeOf("tokyonight")
	for _, k in ipairs({ "bg", "pane", "edge", "title", "caret" }) do PAL[k] = th[k] or PAL[k] end
	PAL.focus = th.focus
	C.SEL_COLOR = th.sel or C.SEL_COLOR
	if frame then
		local r, g, b = RGB(PAL.bg)
		frame:SetBackdropColor(r, g, b, 0.97)
		frame:SetBackdropBorderColor(RGB(PAL.edge))
	end
	local cr, cg, cb = RGB(PAL.caret)
	for _, p in ipairs(panes) do
		p.frame:SetBackdropColor(RGB(PAL.pane))
		if p.bar then p.bar:SetVertexColor(RGB(PAL.title)) end
		p.caret:SetVertexColor(cr, cg, cb, 0.55)
		if map then
			for i, l in ipairs(p.lines) do p.lines[i] = SH.Recolor(l, map) end
			if p.pager then for i, l in ipairs(p.pager.lines) do p.pager.lines[i] = SH.Recolor(l, map) end end
		end
		p.dirty = true
	end
	C.Status()
end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalConsole", C)
	frame:EnableKeyboard(false)
	Panel.Flat(frame)
	local r, g, b = RGB(PAL.bg)
	frame:SetBackdropColor(r, g, b, 0.97)
	frame:SetBackdropBorderColor(RGB(PAL.edge))
	frame:SetScript("OnUpdate", Tick)
	frame:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then C.GapDown() end end)
	frame:SetScript("OnMouseUp", function() C.GapUp() end)
	status = FontString(frame, Chrome())
	status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", C.PAD + 2, 5)
	statusRight = FontString(frame, Chrome())
	statusRight:SetJustifyH("RIGHT")
	statusRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -C.PAD - 2, 5)
	C.frame = frame
end

----------------------------------------------------------------------
-- Opening, stepping out, coming back
----------------------------------------------------------------------

function C.IsShown() return frame ~= nil and frame:IsShown() end
function C.Panes() return panes end
function C.Focused() return focus end
function C.DockedIn(app) return docked[app] end

--- A new pane after `from` (a shell where `from` was: same place). The pane, or nil with four already.
function C.Split(from, quiet)
	if #panes >= C.MAX then
		if from and not quiet then Print(from, Paint("red", L["four panes is the most (Ctrl+W closes one)"])) end
		return nil
	end
	local p = NewPane()
	if from then p.sh.cwd, p.sh.prevCwd = from.sh.cwd, from.sh.cwd end
	p.spawn = from and from.shownRect
	p.fadeIn = true
	local at = from and IndexOf(from)
	table.insert(panes, at and at + 1 or #panes + 1, p)
	C.TreeAdd(p, from)
	zoomed = false
	C.Layout()
	if not quiet then C.Focus(p) end
	return p
end

function C.ClosePane(p)
	local i = IndexOf(p)
	if not i then return end
	if p.job then p.sh.cancelled = true; p.job = nil end
	if p.app then C.CloseApp(p) end
	p.edit:ClearFocus()
	p.frame:Hide()
	table.remove(panes, i)
	C.TreeRemove(p)
	if launcher == p then launcher = nil end
	if #panes == 0 then
		focus = nil
		C.Close("exit")
		return
	end
	if focus == p then focus = panes[math.min(i, #panes)] end
	C.Layout()
	C.Focus(focus)
end

--- Steps out: the console and its apps hide (games pause), the interface comes back; .console brings it all back.
function C.Leave()
	if not C.IsShown() then return end
	for _, p in ipairs(panes) do
		p.edit:ClearFocus()
		if p.app then p.app.hidden = true; p.app.frame:Hide() end
	end
	frame:Hide()
	if ns.Zen then
		ns.Zen.Force(false)
		ns.Zen.Closed()
	end
end

--- Closed by combat (Panel's) or by the last exit: as stepping out; the last exit forgets the panes.
function C.Close(why)
	local shown = C.IsShown()
	C.Leave()
	if why == "combat" and shown then ns:Print(L["Console paused for combat: .console brings it back."]) end
	if why == "exit" then
		for app in pairs(docked) do C.Undock(app, true) end
		panes, focus, launcher, tree = {}, nil, nil, nil
		C.SaveSession() -- (none left: nothing to bring back after a /reload)
	end
end

function C.Reset()
	for _, p in ipairs(panes) do
		if p.app then C.CloseApp(p) end
		p.frame:Hide()
	end
	panes, focus, launcher, zoomed, tree = {}, nil, nil, false, nil
	C.SaveSession()
end

----------------------------------------------------------------------
-- Through a /reload: the panes as they were (each one's place, its text size, its last lines), the layout and which pane
-- had the keyboard, kept in the cache file (SH.Data().session) when the interface goes (PLAYER_LOGOUT: a /reload sends it too) and put
-- back the next time the console opens. Apps and commands running then aren't kept: their panes come back as shells.
-- The last pane closed (exit) and .console reset forget it.
----------------------------------------------------------------------

C.SAVE_LINES = 150 -- (lines kept per pane)

local function ConsoleDb() return SH.Data() end

--- Keeps the panes as they are now (none: forgets what was kept).
function C.SaveSession()
	local cdb = ConsoleDb()
	if not cdb then return end
	if #panes == 0 then cdb.session = nil return end
	local s = { layout = layout, zoomed = zoomed or nil, focus = IndexOf(focus) or 1, panes = {}, tree = C.TreeSave(tree) }
	for i, p in ipairs(panes) do
		local lines = {}
		for j = math.max(1, #p.lines - C.SAVE_LINES + 1), #p.lines do lines[#lines + 1] = p.lines[j] end
		s.panes[i] = { cwd = p.sh.cwd, prev = p.sh.prevCwd, font = p.fontSize, lines = lines }
	end
	cdb.session = s
end

--- The panes kept before the /reload, back (each saying so under its lines). True when there were any.
function C.RestoreSession()
	local cdb = ConsoleDb()
	local s = cdb and cdb.session
	if type(s) ~= "table" or type(s.panes) ~= "table" or #s.panes == 0 then return false end
	for i, sp in ipairs(s.panes) do
		if i > C.MAX then break end
		local p = type(sp) == "table" and C.Split(nil, true)
		if p then
			if type(sp.cwd) == "string" and sp.cwd:sub(1, 1) == "/" then p.sh.cwd = sp.cwd end
			if type(sp.prev) == "string" and sp.prev:sub(1, 1) == "/" then p.sh.prevCwd = sp.prev end
			if tonumber(sp.font) then C.SetFontSize(tonumber(sp.font), p) end
			for _, l in ipairs(type(sp.lines) == "table" and sp.lines or {}) do
				if type(l) == "string" then p.lines[#p.lines + 1] = l end
			end
			Print(p, Paint("dim", L["-- restored after a reload --"]))
		end
	end
	for _, m in ipairs(C.LAYOUTS) do if m == s.layout then layout = m end end
	zoomed = s.zoomed == true
	C.TreeLoad(s.tree)
	focus = panes[tonumber(s.focus) or 1] or panes[1]
	return #panes > 0
end

local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:SetScript("OnEvent", function() pcall(C.SaveSession) end)
C.saver = saver -- (tests)

function C.Open()
	if not Panel.CanOpen(L["The console takes the keyboard, which the game doesn't allow in combat."]) then return false end
	if SH.theme ~= SH.ThemeName() or not SH.palette then SH.SetTheme(SH.ThemeName()) end
	Build()
	C.ApplyTheme()
	Panel.Opening(C)
	Fit()
	frame:Show()
	if ns.Zen then
		ns.Zen.Force(true)
		ns.Zen.Opened()
	end
	if #panes == 0 and not C.RestoreSession() then
		local p = C.Split(nil, true)
		for _, l in ipairs(FS.Motd()) do Print(p, l) end
		focus = p
	end
	-- the apps that were here, back as they were (one opened elsewhere meanwhile, or closed, leaves its pane)
	for app, p in pairs(docked) do
		local rec = p.app
		local _, rel = rec.frame:GetPoint(1)
		if rec.closed or rel ~= p.body then C.Undock(app) end
	end
	C.Layout(true)
	for _, p in ipairs(panes) do if p.app then C.PlaceApp(p) end end
	C.Focus(focus or panes[1])
	return true
end

C.BLACK_HOLD, C.BLACK_FADE = 1, 0.5 -- (s: the screen black, then coming back)
local black

--- sudo rm -rf / (an easter egg): the screen black for a moment, the console stepped out of, then the interface
--- fading back in as it was. Nothing is touched, and the pane that ran it looks as if it never had: what the command
--- printed (its prompt line too) and its history line taken back; .console comes back to everything else as it was.
function C.Wipe(p)
	if not black then
		black = CreateFrame("Frame", "TerminalConsoleBlack", UIParent)
		black:SetFrameStrata("TOOLTIP")
		black:SetAllPoints(UIParent)
		if black.SetIgnoreParentAlpha then pcall(black.SetIgnoreParentAlpha, black, true) end
		black:EnableMouse(true)
		local t = black:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints(black)
		t:SetColorTexture(0, 0, 0, 1)
		C.black = black
	end
	black:SetScript("OnUpdate", nil)
	black:SetAlpha(1)
	black:Show()
	if p then
		for _ = 1, math.min(p.since or 0, #p.lines) do p.lines[#p.lines] = nil end
		p.offset, p.dirty = 0, true
		local h = p.sh.history
		if h[#h] and h[#h]:find("rm", 1, true) then h[#h] = nil end
	end
	C.Leave()
	C_Timer.After(C.BLACK_HOLD, function()
		local left = C.BLACK_FADE
		black:SetScript("OnUpdate", function(self, elapsed)
			left = left - (tonumber(elapsed) or 0)
			if left <= 0 then
				self:SetScript("OnUpdate", nil)
				self:Hide()
				return
			end
			self:SetAlpha(left / C.BLACK_FADE)
		end)
	end)
end

function C.Toggle()
	if C.IsShown() then C.Leave() else C.Open() end
end

ns:RegisterCommand("console", {
	desc = L["A console over everything Terminal knows: lists as directories, rows as files, ls, cd, cat, grep, pipes; up to four panes (` steps out, .console comes back; .console reset starts again)"],
	aliases = { "tty", "tsh" },
	complete = function() return { { "reset", L["close every pane and start again"] }, { "font", L["the console's text size: a number, + or -, or reset"] } } end,
	run = function(args)
		local a = strtrim(args or ""):lower()
		local size = a:match("^font%s*(.*)$")
		if size then
			local now, why = ui.Font({ size })
			if not now then return { why } end
			if C.IsShown() then return nil end
			return { L["Console text size: %d, every pane (.console font reset: Terminal's)"]:format(now) }
		end
		if a == "reset" then C.Reset() end
		C.Open()
	end,
})

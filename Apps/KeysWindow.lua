local ns = select(2, ...)

-- .keybinds (F1 in the terminal): every key Terminal uses, in a small scrollable window where the terminal sits, one
-- tab per mode: Simple, Advanced and Fuzzy finding (it opens on the one in use). The keys are one set for all three
-- (K.LINES): where a mode does a key its own way it says so, and that key is drawn in the accent colour. Esc, F1 or
-- Shift+Left go back to the terminal as it was (UI:SaveState / RestoreState); ` closes. Up/Down, PgUp/PgDn, Home/End
-- and the wheel scroll; Tab / Shift+Tab, Left/Right or 1-3 change the tab (a click on one too). Only its own keys are
-- kept (the Panel pattern): not in combat.

local K = {}
ns.KeysWindow = K

local UI, Theme, Panel = ns.UI, ns.Theme, ns.Panel
local Text, Hex = Panel.Text, Panel.Hex

K.MODES = { "simple", "advanced", "fuzzy" }
K.LABELS = { simple = "Simple", advanced = "Advanced", fuzzy = "Fuzzy finding" }
local LETTER = { simple = "s", advanced = "a", fuzzy = "f" }

-- One list for the three modes, so they stay alike. { key, text } is the same in every mode; `s`, `a`, `f` give a
-- mode's own text (that mode does it its own way: drawn in the accent colour); `only = "sa"` names the modes a line is
-- for (a line for one mode alone is that mode's own too). { "Title" } alone starts a section.
K.LINES = {
	{ "Search" },
	{ "type", s = "what you're after, in plain words: stamina food, nearest innkeeper, mats for thorium belt",
		a = "words, @kinds, filters and chains: @npc is:vendor in:barrens, thorium belt > mats",
		f = "a name's letters in order, over every list at once" },
	{ "Up / Down", "the previous / next result" },
	{ "Tab", "complete the faint text after the cursor; nothing to complete: the next result",
		s = "pick the selected category (or complete the faint text); else the next result",
		a = "complete the faint text (@kinds, filters, commands); in a pick list the next one; else the next result",
		f = "the next result" },
	{ "Shift+Tab", "the previous result", a = "the previous result (in a pick list, the previous one)" },
	{ "PgUp / PgDn", "a page up / down" },
	{ "Ctrl+Home / End", "the first / last result" },
	{ "Ctrl+N / Ctrl+P", "the next / previous result (Ctrl+J / Ctrl+K too)" },
	{ "mouse wheel", "scroll the results; pointing at a row selects it" },

	{ "Act on the selected result" },
	{ "Enter", "do what the footer says: open, use, cast, set a waypoint...",
		f = "take it to Simple mode, selected there: nothing is run" },
	{ "Shift+Enter", "its other action (the footer says which)", f = "take it to Advanced mode, as @kind name" },
	{ "Ctrl+Enter", "act and keep Terminal open (a window it opens still closes it)", only = "sa" },
	{ "click", "as Enter; with Shift or Ctrl, as Shift+Enter or Ctrl+Enter", f = "as Enter; Shift+click as Shift+Enter" },
	{ "right-click", "everything it can do: open, use, link it, send it (or all of them) to chat" },
	{ "Shift+Right", s = "at the end of the prompt: that menu from the keyboard (Up/Down, Enter)",
		a = "at the end of the prompt: write the result into it, to build on (@npc Thrall)",
		f = "at the end of the prompt: write its name into it" },

	{ "Get around" },
	{ "Shift+Left", "back to the list you came from, your pick selected again", only = "sa",
		s = "back: to the list you came from (your pick selected again), or from a category to all of them" },
	{ "Up", "on an empty prompt: lines you ran before, older with each press", only = "sa" },
	{ "Down", only = "sa", s = "on an empty prompt: your last search back (Up puts it away)",
		a = "on an empty prompt: your recent picks (Up puts them away)" },

	{ "Edit the prompt" },
	{ "Left / Right", "move the cursor (Ctrl: a word at a time)" },
	{ "Home / End", "the start / end of the prompt" },
	{ "Shift+move", "select as the cursor moves (Shift+Left goes back first, where it can); Ctrl+A selects it all" },
	{ "Right", "at the end of the prompt: take the faint text; Shift+Right on an empty one types the example", only = "sa" },
	{ "Backspace / Del", "delete a letter (Ctrl: a word)" },
	{ "Ctrl+W", "delete the word before the cursor" },
	{ "Ctrl+U", "delete everything before the cursor (at the end: the whole line)" },
	{ "Ctrl+C / Ctrl+V", "copy / paste (the first press gets the text box ready: press again)" },

	{ "Modes and the window" },
	{ "` or Esc", "close", s = "close (Down brings the search back next time)" },
	{ "Alt+`", only = "sf", s = "this search in Advanced mode, this one time", f = "the same words in Advanced mode" },
	{ "Tab+`", "fuzzy finding over every list (hold Tab, press `)", f = "close" },
	{ "F1", "this list (also .keybinds)" },
	{ "drag", "move Terminal: it snaps to a grid, the screen's middles lit (Shift: freely)" },
	{ "Ctrl+R, Ctrl+S...", "the game's own keys for the frame rate, sound, music, volume and screenshots still work" },

	{ "What you type" },
	{ "use, nearest...", "start with what to do: use hearthstone, nearest innkeeper, where is hogger", only = "s" },
	{ "or / not", "sword or axe, rare ring not boe", only = "s" },
	{ "@kind", "one list: @npc, @item, @recipe (type @ to pick one)", only = "a" },
	{ "key:value", "a filter: lvl:20-30 q:rare+ is:boe sort:nearest (.filters lists them)", only = "a" },
	{ "-x  a|b", "not / or: -is:soulbound, sword|axe, q:rare|epic", only = "a" },
	{ "a > mats", "a chain: thorium belt > mats > alts (.chains)", only = "a" },
	{ ">> party", "send the selected result to chat; >>> party sends them all", only = "a" },
	{ ".", "a Terminal command: .help, .options, .theme (Tab completes)", only = "sa" },
	{ "/", "a slash command or emote: /dance, /who", only = "sa" },
	{ "3*45g", "a sum, gold too", only = "sa" },
	{ "anything", "every letter is searched: nothing is syntax here", only = "f" },
}

--- A line's text in `mode`, or nil when the line isn't for that mode.
function K.TextFor(line, mode)
	local l = LETTER[mode]
	if not l or (line.only and not line.only:find(l, 1, true)) then return nil end
	local own = line[l]
	if type(own) == "string" then return own end
	return line[2]
end

--- Does `mode` do this key its own way (its own text, or a line for that mode alone)?
function K.Own(line, mode)
	local l = LETTER[mode]
	if not K.TextFor(line, mode) then return false end
	return type(line[l]) == "string" or (line.only ~= nil and #line.only == 1)
end

--- Is this line a section's title ({ "Search" }: nothing but a name)?
function K.IsTitle(line)
	return line[2] == nil and line.s == nil and line.a == nil and line.f == nil and line.only == nil
end

--- The rows `mode` shows: { title = ... } for a section with something in it, { key, text, own } for each key.
function K.Rows(mode)
	local out, title = {}, nil
	for _, line in ipairs(K.LINES) do
		if K.IsTitle(line) then
			title = line[1]
		else
			local text = K.TextFor(line, mode)
			if text then
				if title then out[#out + 1] = { title = title }; title = nil end
				out[#out + 1] = { key = line[1], text = text, own = K.Own(line, mode) }
			end
		end
	end
	return out
end

--- The mode in use: fuzzy finding, Simple (for good, or this run from fuzzy finding), else Advanced.
function K.ModeNow()
	if UI.fzf then return "fuzzy" end
	if ns.Easy and ns.Easy.On() then return "simple" end
	return "advanced"
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local W_MIN, H = 540, 440
local STEP = 36 -- pixels a line of scrolling moves
local GAP, SECTION_GAP, KEY_PAD = 4, 12, 16
K.FLIP_WAIT = 0.3 -- (s: F1 held, the client's own repeats don't flip back and forth)

local frame, title, modeText, legend, box, scroll, content, thumb, footer, measure
local tabs = {}
local pool = {} -- { key = FontString, text = FontString } per row shown
local offset, mode, back = 0, "simple", nil

local function MaxOffset()
	if not (content and scroll) then return 0 end
	return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
end

--- Scroll to `to` pixels from the top (kept inside the list), the thumb following.
function K.ScrollTo(to)
	offset = math.max(0, math.min(MaxOffset(), to or 0))
	if scroll then scroll:SetVerticalScroll(offset) end
	if thumb and scroll then
		local viewH, max = scroll:GetHeight() or 1, MaxOffset()
		local h = math.max(16, viewH * viewH / math.max(1, viewH + max))
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -4 - (max > 0 and (viewH - h) * offset / max or 0))
		thumb:SetShown(max > 0)
	end
end
function K.Offset() return offset end
function K.Mode() return mode end

local function Height(fs, least)
	local h = fs:GetStringHeight()
	return math.max(least, type(h) == "number" and h or 0)
end

local function Pair(i)
	local p = pool[i]
	if p then return p end
	p = { key = Text(content, 12), text = Text(content, 12) }
	p.text:SetWordWrap(true)
	p.text:SetJustifyV("TOP")
	p.key:SetJustifyV("TOP")
	pool[i] = p
	return p
end

--- The tab buttons: the shown one in the accent colour, underlined; the others dimmed.
local function DrawTabs(t)
	local acc, dim = Hex(t.accent), Hex(t.dim)
	local x = 12
	for i, m in ipairs(K.MODES) do
		local b = tabs[i]
		local label = ("%d %s"):format(i, K.LABELS[m])
		b.fs:SetText(Theme.FixColors(("|cff%s%s|r"):format(m == mode and acc or dim, label)))
		local w = (b.fs:GetStringWidth() or 60) + 14
		b:SetSize(w, 20)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -30)
		b.line:SetColorTexture(Theme.RGB(t.accent))
		b.line:SetShown(m == mode)
		x = x + w + 6
	end
end

--- The rows of the tab shown, in two columns: keys (the text colour, a mode's own in the accent colour), and what they
--- do (dimmed, wrapping), under the section titles.
local function Fill(t, width)
	local rows = K.Rows(mode)
	local keyW = 0
	for _, r in ipairs(rows) do
		if r.key then
			measure:SetText(r.key)
			keyW = math.max(keyW, measure:GetStringWidth() or 0)
		end
	end
	keyW = math.min(math.floor(width * 0.4), keyW + KEY_PAD)
	local acc, txt, dim = Hex(t.accent), Hex(t.text), Hex(t.dim)
	local y, n = 0, 0
	for i, r in ipairs(rows) do
		n = n + 1
		local p = Pair(n)
		p.key:ClearAllPoints(); p.text:ClearAllPoints()
		if r.title then
			if i > 1 then y = y + SECTION_GAP end
			p.key:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			p.key:SetWidth(width)
			p.key:SetText(Theme.FixColors(("|cff%s%s|r"):format(acc, r.title)))
			p.text:SetText("")
			p.text:Hide()
			p.key:Show()
			y = y + Height(p.key, 14) + GAP
		else
			p.key:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
			p.key:SetWidth(keyW - 8)
			p.key:SetText(Theme.FixColors(("|cff%s%s|r"):format(r.own and acc or txt, (r.key:gsub("|", "||")))))
			p.text:SetPoint("TOPLEFT", content, "TOPLEFT", keyW, -y)
			p.text:SetWidth(width - keyW)
			p.text:SetText(Theme.FixColors(("|cff%s%s|r"):format(dim, (r.text:gsub("|", "||")))))
			p.key:Show(); p.text:Show()
			y = y + math.max(Height(p.key, 14), Height(p.text, 14)) + GAP
		end
		p.row = r
	end
	for i = n + 1, #pool do pool[i].key:Hide(); pool[i].text:Hide(); pool[i].row = nil end
	content:SetWidth(width)
	content:SetHeight(math.max(1, y))
	K.shown = n
end

local function Layout()
	local t = Theme.Get()
	local W = math.max(W_MIN, t.width or 640)
	Panel.Layout(frame, W, H)
	local br, bg, bb = Theme.RGB(t.border)
	box:SetBackdropBorderColor(br, bg, bb, 1)
	local ar, ag, ab = Theme.RGB(t.accent)
	thumb:SetColorTexture(ar, ag, ab, 0.8)
	local dr, dg, db = Theme.RGB(t.dim)
	modeText:SetTextColor(dr, dg, db)
	legend:SetTextColor(dr, dg, db)
	title:SetText(Theme.FixColors(("|cff%skeys|r"):format(Hex(t.accent))))
	modeText:SetText("you're in " .. K.LABELS[K.ModeNow()] .. (K.ModeNow() == "fuzzy" and "" or " mode"))
	legend:SetText(Theme.FixColors(("Keys in |cff%sthis colour|r are %s's own; the rest work the same in every mode they're in.")
		:format(Hex(t.accent), K.LABELS[mode])))
	-- the footer in the terminal's key-hint style: the key in the text colour, its meaning dimmed
	local key = "|cff" .. Hex(t.text)
	local parts = {}
	for _, h in ipairs(K.FOOTER) do parts[#parts + 1] = key .. h[1] .. "|r " .. h[2] end
	footer:SetText(Theme.FixColors(table.concat(parts, "     ")))
	footer:SetTextColor(dr, dg, db)
	DrawTabs(t)
	Fill(t, W - 20 - 24)
end

K.FOOTER = { { "Tab", "mode" }, { "Up/Down", "scroll" }, { "Esc / F1", "back to the prompt" }, { "`", "close" } }

--- Show `m`'s tab ("simple", "advanced", "fuzzy"), from its top.
function K.Show(m)
	if not LETTER[m] then return end
	mode = m
	if frame and frame:IsShown() then
		Layout()
		K.ScrollTo(0)
	end
end

--- The next (dir 1) or previous (-1) tab, round.
function K.Step(dir)
	for i, m in ipairs(K.MODES) do
		if m == mode then return K.Show(K.MODES[(i - 1 + dir) % #K.MODES + 1]) end
	end
end

local function Shifted() return IsShiftKeyDown and IsShiftKeyDown() or false end

local KEYS = {
	UP = function() K.ScrollTo(offset - STEP) end,
	DOWN = function() K.ScrollTo(offset + STEP) end,
	PAGEUP = function() K.ScrollTo(offset - (scroll:GetHeight() or 200) + STEP) end,
	PAGEDOWN = function() K.ScrollTo(offset + (scroll:GetHeight() or 200) - STEP) end,
	HOME = function() K.ScrollTo(0) end,
	END = function() K.ScrollTo(MaxOffset()) end,
	TAB = function() K.Step(Shifted() and -1 or 1) end,
	LEFT = function() if Shifted() then K.Back(true) else K.Step(-1) end end, -- (Shift+Left: back, as in the terminal)
	RIGHT = function() K.Step(1) end,
	["1"] = function() K.Show("simple") end,
	["2"] = function() K.Show("advanced") end,
	["3"] = function() K.Show("fuzzy") end,
	ESCAPE = function() K.Back() end,
	F1 = function() if not K.TooSoon() then K.Back() end end,
	["`"] = function() K.Close() end,
}

--- Its keys are kept; any other key goes on to the game.
function K.KeyDown(self, key)
	local fn = KEYS[key]
	if fn then fn() end
	Panel.Propagate(self, fn)
end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalKeysWindow", K)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnKeyDown", function(self, key) K.KeyDown(self, key) end)
	frame:SetScript("OnMouseWheel", function(_, delta) K.ScrollTo(offset - delta * STEP) end)

	title, modeText = Panel.Header(frame)
	for i, m in ipairs(K.MODES) do
		local b = CreateFrame("Button", nil, frame)
		b.fs = Text(b, 12, "CENTER")
		b.fs:SetPoint("CENTER", 0, 1)
		b.line = b:CreateTexture(nil, "ARTWORK")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 4, 0)
		b.line:SetPoint("BOTTOMRIGHT", -4, 0)
		b:SetScript("OnClick", function() K.Show(m) end)
		tabs[i] = b
	end
	legend = Text(frame, 11)
	legend:SetPoint("TOPLEFT", 12, -56)
	legend:SetPoint("RIGHT", frame, "RIGHT", -12, 0)

	box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 10, -74)
	box:SetPoint("BOTTOMRIGHT", -10, 30)
	box:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

	scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", -14, 8)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	measure = Text(content, 12)
	measure:SetAlpha(0)

	thumb = box:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(1, 1, 1, 1)
	thumb:SetWidth(3)

	footer = Panel.Footer(frame, 10)
	K.frame = frame
end

function K.IsShown() return Panel.Shown(frame) end
function K.Parts() return scroll, content, pool, tabs, footer, legend end -- (tests)

--- Opens on `m`'s tab (nil: the mode in use). `from`: the terminal as it was (UI:SaveState) to go back to; nil: an empty
--- prompt. The terminal goes while it shows (Panel.Opening).
function K.Open(m, from)
	if not Panel.CanOpen("The keys window takes the arrow keys while open, which the game doesn't allow in combat.") then return false end
	K.flipAt = GetTime()
	mode = LETTER[m] and m or K.ModeNow()
	back = from
	Build()
	Panel.Opening(K) -- (straight in, where the terminal was: it and the other panels go)
	frame:Show()
	Layout()
	K.ScrollTo(0)
	return true
end

function K.Close(why)
	back = nil
	return Panel.Close(frame, why, "The keys window")
end

--- F1 pressed a moment after it opened or closed the window: the held key's own repeats, not a press (they'd flip it
--- back and forth). Esc and Shift+Left always count.
function K.TooSoon() return K.flipAt ~= nil and GetTime() - K.flipAt < K.FLIP_WAIT end

--- Esc, F1, Shift+Left: back to the terminal as it was when F1 was pressed (`held`: by Shift+Left, whose repeats
--- mustn't go back a step in the terminal too).
function K.Back(held)
	local was = back
	if not K.Close() then return false end
	K.flipAt = GetTime()
	UI:RestoreState(was)
	if held then UI.backHeld = GetTime() end
	return true
end

ns:RegisterCommand("keybinds", {
	desc = "Every key Terminal uses, for each mode (F1 in the terminal; Esc goes back)",
	aliases = { "keys", "shortcuts", "hotkeys" },
	complete = function() return { { "simple", "Simple mode's keys" }, { "advanced", "Advanced mode's" }, { "fuzzy", "fuzzy finding's" } } end,
	run = function(args)
		local want = strtrim(args or ""):lower()
		local m
		for _, x in ipairs(K.MODES) do
			if want ~= "" and x:sub(1, #want) == want then m = x end
		end
		K.Open(m)
	end,
})

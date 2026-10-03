local ns = select(2, ...)
local Fuzzy = ns.Fuzzy
local Theme = ns.Theme

local UI = {}
ns.UI = UI

local FOOTER_H = 24 -- one line of footer; a second line is added when the hints don't fit
local HINTS = "Enter open  |  Shift+Enter more  |  / slash  . cmd  @kind  = calc"
local MAX_ROWS = 20
local MAX_RESULTS = 100
local TEXT_SCORE = 1.0 -- score given to a match found in an entry's secondary text
local QUESTION_MARK = 134400
local HINT = "|cffffd200"

-- layout, recomputed from the theme
local ROWS, ROW_H, HEADER_H = 10, 26, 50

-- keys that go straight to the game while the terminal reads the keyboard
local PASS_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true, PRINTSCREEN = true,
}

local frame, edit, status, hints, promptFS, caret, measure, divider, promptBg
local rows = {}
local results = {}
local sel, offset = 1, 0
UI.args = nil
UI.keys = false   -- true while the terminal reads keystrokes itself (see "Keyboard")
UI.noChar = false -- set if this client never sends typed characters to frames
UI.cursor = 0     -- byte position of the caret in the query

----------------------------------------------------------------------
-- Scoring
----------------------------------------------------------------------

local function FreqBonus(e)
	local f = ns.db and ns.db.freq[e.freqKey or ""]
	return f and math.min(f, 20) * 0.05 or 0
end

local function ScoreEntry(e, tokens)
	local total, set = 0, {}
	for _, tk in ipairs(tokens) do
		local best, pos = Fuzzy.match(tk, e.name, e._lname)
		if e.text then
			if not e._ltext then e._ltext = e.text:lower() end
			if e._ltext:find(tk, 1, true) and (not best or best < TEXT_SCORE) then
				best, pos = TEXT_SCORE, nil
			end
		end
		if not best then return nil end
		total = total + best
		if pos then
			for _, i in ipairs(pos) do set[i] = true end
		end
	end
	e._pos = set
	return total
end

local function SortAndTrim(list)
	table.sort(list, function(a, b)
		if a._score ~= b._score then return a._score > b._score end
		local an, bn = a._lname or "", b._lname or ""
		if an ~= bn then return an < bn end
		return tostring(a.key) < tostring(b.key)
	end)
	for i = #list, MAX_RESULTS + 1, -1 do list[i] = nil end
	return list
end

local function PseudoEntries(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = { name = line, raw = true, icon = false, noActivate = true, kindLabel = "", detail = "" }
	end
	return out
end

----------------------------------------------------------------------
-- Searching
----------------------------------------------------------------------

function UI:CommandEntries()
	local list = {}
	for _, name in ipairs(ns.commandOrder) do
		local c = ns.commands[name]
		list[#list + 1] = {
			kind = "cmd",
			kindLabel = "|cff33ff99cmd|r",
			name = name,
			_lname = name,
			key = name,
			icon = "Interface\\Icons\\INV_Misc_Note_01",
			detail = c.desc,
			text = table.concat(c.aliases, " "),
			freqKey = "cmd:" .. name,
			activate = function(_, args) return c.run(args or "", ns) end,
		}
	end
	return list
end

--- Used by "/" and "." modes: first word picks the entry, the rest is its arguments.
function UI:WordSearch(entries, text)
	local word, rest = text:match("^%s*(%S*)%s*(.*)$")
	self.args = rest
	local tokens
	if word ~= "" and word ~= "/" then tokens = { word:lower() } end
	local out = {}
	for _, e in ipairs(entries) do
		if not tokens then
			e._score, e._pos = 0, {}
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s then
				e._score = s + FreqBonus(e)
				out[#out + 1] = e
			end
		end
	end
	return SortAndTrim(out)
end

--- The empty terminal: what you picked last, newest first, then your all-time favourites.
function UI:FrequentEntries()
	local out = {}
	local rank = {}
	for i, key in ipairs(ns.db.recent or {}) do rank[key] = i end
	-- providers named by recent picks are read even if they're heavy (map, options, loot)
	local want = {}
	for key in pairs(rank) do want[key:match("^([^:]+):") or ""] = true end
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if (not p.explicit and not p.lazy) or want[id] then
			for _, e in ipairs(ns:GetEntries(p)) do
				local r = rank[e.freqKey]
				local f = ns.db.freq[e.freqKey]
				if r then
					e._score, e._pos = 10000 - r, {}
					out[#out + 1] = e
				elseif f and f > 0 and not p.explicit and not p.lazy then
					e._score, e._pos = f, {}
					out[#out + 1] = e
				end
			end
		end
	end
	if #out == 0 then
		return PseudoEntries({
			"Type to fuzzy-search items, quests (by text), spells, recipes, camp objects...",
			"Start with  /  for slash commands,  .  for terminal commands (try .help)",
			"Add  @questlog  /  @item  /  @recipe  to search a single kind (@questie: every quest, with Questie)",
			"Type a sum like  3*45g  or  12.5% of 800  for the calculator",
			"Change the look with  .theme  and  .set , or  .options",
		})
	end
	return SortAndTrim(out)
end

function UI:Search(text)
	-- arithmetic: the answer is the top result (see Calc.lua)
	local calc = ns.Calc and ns.Calc.Entry(text)
	if calc then
		local res = self:SearchText(text)
		table.insert(res, 1, calc)
		return res
	end
	return self:SearchText(text)
end

function UI:SearchText(text)
	self.linkedGuess = {}
	self.linked = {} -- quest entry -> the item that brought it along (drawn with an arrow)
	local kinds, tokens = nil, {}
	for w in text:gmatch("%S+") do
		if w:sub(1, 1) == "@" then
			local p = ns:ResolveProvider(w:sub(2))
			if p then
				kinds = kinds or {}
				kinds[p.id] = true
			end
		else
			tokens[#tokens + 1] = w:lower()
		end
	end
	local empty = #tokens == 0
	if empty and not kinds then return self:FrequentEntries() end

	local out = {}
	local present = {}
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		local included
		if kinds then included = kinds[id] else included = not p.explicit end
		if included then
			for _, e in ipairs(ns:GetEntries(p)) do
				if empty then
					e._score, e._pos = FreqBonus(e), {}
					out[#out + 1] = e
				else
					local s = ScoreEntry(e, tokens)
					if s then
						e._score = s + FreqBonus(e)
						out[#out + 1] = e
						present[e] = true
					end
				end
			end
		end
	end
	-- a quest item brings its quest along, right below it ("Intact Limbs" -> its quest)
	if not empty and (not kinds or kinds.quests) and ns.providers.quests then
		local linked, from = {}, {}
		self.guessed = {}
		for _, e in ipairs(out) do
			if e.questID and e.kind ~= "quests" then
				local best = linked[e.questID]
				if not best or e._score > best then linked[e.questID] = e._score; from[e.questID] = e end
			end
		end
		-- items with no sure quest: the likeliest quests, offered as "maybe"
		for _, e in ipairs(out) do
			if e.guessIDs and e.kind ~= "quests" and not e.questID then
				for _, id in ipairs(e.guessIDs) do
					if not linked[id] then
						linked[id] = e._score; from[id] = e; self.guessed[id] = true
					end
				end
			end
		end
		if next(linked) then
			for _, q in ipairs(ns:GetEntries(ns.providers.quests)) do
				local s = linked[q.questID]
				if s then
					if not present[q] then
						q._pos = {}
						out[#out + 1] = q
					end
					-- directly under its item when the item itself was searched for by name; an item
					-- that only matched through its quest's text stays below the quest
					local it = from[q.questID]
					if not present[q] or (it._pos and next(it._pos)) then
						q._score = s - 0.001
						self.linked[q] = it
						self.linkedGuess = self.linkedGuess or {}
						self.linkedGuess[q] = self.guessed[q.questID] or nil
					end
				end
			end
		end
	end
	return SortAndTrim(out)
end

function UI:Refresh()
	if not frame then return end
	if self.armedEntry then self:Disarm() end -- the query changed: whatever was armed is stale
	self.pendingAfter = nil
	self.args = nil
	self.mode = "search"
	local text = edit:GetText():gsub("^%s+", "")
	local first = text:sub(1, 1)
	if first == "." then
		self.mode = "cmd"
		results = self:WordSearch(self:CommandEntries(), text:sub(2))
	elseif first == "/" then
		self.mode = "slash"
		local p = ns.providers.slash
		results = p and self:WordSearch(ns:GetEntries(p), text) or {}
	else
		results = self:Search(text)
	end
	sel, offset = 1, 0
	self:Render()
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

-- The terminal's own tooltip. GameTooltip would also pop up the game's "Equipped"
-- comparison tooltips for gear, and those land on top of the terminal.
local tip
local function Tip()
	if not tip then
		tip = CreateFrame("GameTooltip", "TerminalTooltip", UIParent, "GameTooltipTemplate")
		tip.supportsItemComparison = false -- a finder shows the thing, not "if you replace this..."
		tip:SetFrameStrata("TOOLTIP")
	end
	return tip
end

local function HideComparisons(t)
	for _, s in ipairs(t.shoppingTooltips or {}) do
		if s and s.Hide then s:Hide() end
	end
	for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
		local s = _G[name]
		if s and s.GetOwner and s:GetOwner() == t then s:Hide() end
	end
end

-- Match the terminal: same background and border (light themes keep the game's dark tooltip,
-- since item text is drawn for a dark background).
local function StyleTip(t)
	local th = Theme.Get()
	local r, g, b, a = 0.06, 0.06, 0.1, 0.95
	local br, bg, bb = Theme.RGB(th.border)
	if not Theme.IsLight() then
		r, g, b = Theme.RGB(th.bg)
		a = math.max(0.92, th.bgAlpha)
	end
	local nine = t.NineSlice
	if type(nine) == "table" and nine.SetCenterColor then
		pcall(nine.SetCenterColor, nine, r, g, b, a)
		pcall(nine.SetBorderColor, nine, br, bg, bb, 1)
	elseif t.SetBackdropColor then
		pcall(t.SetBackdropColor, t, r, g, b, a)
		pcall(t.SetBackdropBorderColor, t, br, bg, bb, 1)
	end
end

-- Beside the terminal, on whichever side has room.
local function PlaceTip(t)
	t:ClearAllPoints()
	local ok, roomRight = pcall(function()
		local scale = frame:GetEffectiveScale()
		local right = frame:GetRight() * scale
		local screen = UIParent:GetRight() * UIParent:GetEffectiveScale()
		return screen - right > 330 * UIParent:GetEffectiveScale()
	end)
	if ok and roomRight == false then
		t:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, 0)
	else
		t:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
	end
end

function UI:UpdateTooltip()
	local t = Tip()
	t:Hide()
	if not (frame and frame:IsShown()) then return end
	local e = results[sel]
	if not e or e.noActivate then return end
	-- entries may supply a link directly, or a function that builds it only when selected
	local link = e.link
	if not link and e.getLink then
		local ok, l = pcall(e.getLink, e)
		link = ok and l or nil
	end
	if not (link or e.tip) then return end
	t:SetOwner(frame, "ANCHOR_NONE")
	PlaceTip(t)
	local shown = false
	if link then
		shown = pcall(t.SetHyperlink, t, link)
	end
	if not shown and e.tip then
		t:SetText(e.name, 1, 1, 1)
		t:AddLine(e.tip, 0.8, 0.8, 0.8, true)
		shown = true
	end
	if shown then
		t:Show()
		HideComparisons(t)
		StyleTip(t)
	end
end

local MODE_LABEL = { cmd = "commands", slash = "slash commands" }

function UI:SetStatus()
	if not status then return end
	if self.armedEntry then
		status:SetText(Theme.FixColors(HINT .. "Press Enter to open|r  " .. self.armedEntry.name))
		if hints then hints:Hide() end -- the armed line gets the whole footer
		return
	end
	if hints then hints:SetShown(Theme.Get().hints and true or false) end
	local count = #results
	local quiet = count > 0 and results[1].noActivate
	local mode = MODE_LABEL[self.mode or ""] -- plain searching needs no label
	local text = quiet and "" or (count .. " result" .. (count == 1 and "" or "s"))
	if mode then text = text .. (text ~= "" and "  |  " or "") .. mode end
	status:SetText(text)
end

local ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12|t "

function UI:Render()
	if not frame then return end
	local t = Theme.Get()
	local ar, ag, ab = Theme.RGB(t.accent)
	local light = Theme.IsLight()
	for i = 1, MAX_ROWS do
		local r = rows[i]
		local idx = offset + i
		local e = (i <= ROWS) and results[idx] or nil
		if e then
			r:Show()
			if e.raw then
				r.label:SetText(Theme.FixColors(e.name))
			else
				local base = e.color
				if light and base == "|cffffffff" then base = nil end -- white item names vanish on light themes
				r.label:SetText(Theme.FixColors(Fuzzy.Colorize(e.name, e._pos, base)))
			end
			if e.icon == false then
				r.icon:Hide()
			else
				r.icon:Show()
				r.icon:SetTexture(e.icon or QUESTION_MARK)
			end
			local from = self.linked and self.linked[e]
			if from and not e.raw then
				r.label:SetText(ARROW .. r.label:GetText())
				r.detail:SetText((self.linkedGuess and self.linkedGuess[e] and "maybe needs " or "needs ") .. from.name)
			else
				r.detail:SetText(e.detail or "")
			end
			r.kind:SetText(Theme.FixColors(e.kindLabel or ""))
			r.bg:SetColorTexture(ar, ag, ab, idx == sel and 0.18 or 0)
		else
			r:Hide()
		end
	end
	self:SetStatus()
	self:UpdateTooltip()
end

function UI:Move(delta)
	local n = #results
	if n == 0 then return end
	if self.armedEntry then self:Disarm() end
	sel = math.max(1, math.min(n, sel + delta))
	if sel <= offset then offset = sel - 1 end
	if sel > offset + ROWS then offset = sel - ROWS end
	self:Render()
end

function UI:Scroll(delta)
	local maxOffset = math.max(0, #results - ROWS)
	offset = math.max(0, math.min(maxOffset, offset - delta * 3))
	sel = math.max(offset + 1, math.min(offset + ROWS, sel))
	self:Render()
end

----------------------------------------------------------------------
-- Secure opening (see Secure.lua for why)
----------------------------------------------------------------------

--- Entries' `after` steps click and point at Blizzard frames, which are protected in combat.
local function RunAfter(e)
	if InCombatLockdown() then
		ns:Trace("combat: skipped after-step for " .. tostring(e.name))
		return
	end
	pcall(e.after, e)
end

function UI:Disarm()
	if self.armedEntry or ns.Secure.armed or self.legacyArm then
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
	local S = ns.Secure
	local target = S.Resolve(e.secure)
	if not target then ns:Trace("secure: no binding/button for " .. e.name) return false end
	if e.isOpen and e.isOpen() then -- nothing to click, just point at the thing
		ns:Trace("secure: window already open, highlighting " .. e.name)
		self:Hide()
		ns:Bump(e.freqKey)
		if e.after then C_Timer.After(0.05, function() RunAfter(e) end) end
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
	local S = ns.Secure
	local target = S.Resolve(e.secure)
	if not target or (e.isOpen and e.isOpen()) then return false end
	if not S.Arm(target) then ns:Trace("secure: arm failed on key press for " .. e.name) return false end
	ns:Trace("secure: key press armed -> " .. tostring(target.binding or target.button or target.spell) .. " for " .. e.name)
	if self.armedEntry ~= e then ns:Bump(e.freqKey) end
	self.armedEntry = e
	self:SetStatus()
	return true
end

--- With a keybinding command, the window opens on this very key press; give the game a
--- moment, then close the terminal and point at the result. (A proxy button acts on key
--- release and reports back through PostClick instead.)
function UI:FinishSoon(e)
	if ns.Secure.mode ~= "binding" then return end
	self.pendingAfter = e
	C_Timer.After(0.15, function()
		if self.pendingAfter ~= e then return end
		self.pendingAfter = nil
		if self.armedEntry == e then
			self:FinishSecure()
		elseif not (frame and frame:IsShown()) then
			-- the window that just opened closed the terminal first: still point at the result
			ns.Secure.Disarm()
			if e.after then C_Timer.After(0.1, function() RunAfter(e) end) end
		end
	end)
end

function UI:FinishSecure()
	local e = self.armedEntry
	self:Disarm()
	if not e then return end
	ns:Trace("secure: finished, highlighting " .. e.name)
	self:Hide()
	if e.after then C_Timer.After(0.1, function() RunAfter(e) end) end
end

ns.Secure.onClicked = function() UI:FinishSecure() end

function UI:OnCombat()
	self:Disarm()
	if self.keys then self:EnterEdit() end -- keyboard propagation can't be changed in combat
end

function UI:OnRegen()
	if frame and frame:IsShown() and not self.keys and not self.noChar then self:EnterKeys() end
end

----------------------------------------------------------------------
-- Keyboard
--
-- Out of combat the terminal frame reads keystrokes itself (OnKeyDown + OnChar) instead
-- of the text box. That lets Enter on a Blizzard window be passed on to the game, where
-- it lands on the secure button: one press opens the window. In combat (when addons may
-- not change keyboard propagation), or on a client that doesn't send typed characters to
-- frames, the ordinary text box takes over.
----------------------------------------------------------------------

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

function UI:SetQuery(text, cursor)
	self.cursor = math.max(0, math.min(cursor or #text, #text))
	if edit:GetText() ~= text then edit:SetText(text) end -- OnTextChanged -> Refresh
	self:UpdateCaret()
end

function UI:UpdateCaret()
	if not caret then return end
	if not (self.keys and frame:IsShown()) then
		caret:Hide()
		return
	end
	local text = edit:GetText()
	measure:SetText((text:sub(1, self.cursor):gsub("|", "||")))
	local w = measure:GetStringWidth() or 0
	local maxW = (edit:GetWidth() or 400) - 2
	caret:ClearAllPoints()
	caret:SetPoint("LEFT", edit, "LEFT", math.min(w, maxW), 0)
	caret:Show()
end

function UI:EnterKeys()
	if not frame or self.noChar or InCombatLockdown() then return false end
	self.keys = true
	self.cursor = math.min(self.cursor or 0, #edit:GetText())
	edit:ClearFocus()
	frame:EnableKeyboard(true)
	frame:SetPropagateKeyboardInput(false)
	self:UpdateCaret()
	return true
end

function UI:EnterEdit()
	if not frame then return end
	if self._repeat then self._repeat.key = nil; self._repeat:Hide() end
	self.keys = false
	frame:EnableKeyboard(false)
	edit:SetFocus()
	edit:SetCursorPosition(self.cursor or #edit:GetText())
	self:UpdateCaret()
end

local function CheckChar(key)
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
		ns:Print("this client doesn't pass typed text to addon frames, so the plain search box is used (windows that need a secure click will take Enter twice).")
	end)
end

----------------------------------------------------------------------
-- Holding a key. Frames are told about a key press once, so held Backspace, Delete and
-- the arrow keys are repeated here: after a short delay, then steadily, until key-up.
----------------------------------------------------------------------

local EditKey -- defined below
local REPEAT_KEYS = { BACKSPACE = true, DELETE = true, LEFT = true, RIGHT = true, UP = true, DOWN = true }
local REPEAT_DELAY, REPEAT_RATE = 0.4, 0.045
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
	if not (UI.keys and frame and frame:IsShown()) or (IsKeyDown and not IsKeyDown(self.key)) then
		StopRepeat()
		return
	end
	self.wait = REPEAT_RATE
	EditKey(self.key, self.ctrl, self.shift)
end)

--- The entry to open through the game's own key for this press, or nil. Shift+Enter uses the
--- entry's secondary action; one that opens a window itself (secondarySecure) is armed like
--- Enter is, with its own isOpen/after (e.g. an equipment set: the character window's sets).
local function SecureView(e, shift)
	if not e then return nil end
	if shift and e.secondary then
		if not e.secondarySecure then return nil end
		return setmetatable({
			secure = e.secondarySecure, isOpen = e.secondaryIsOpen, after = e.secondaryAfter,
		}, { __index = e })
	end
	return e.secure and e or nil
end
UI.SecureView = SecureView

local function KeysDown(self, key)
	if InCombatLockdown() then
		UI:EnterEdit()
		return
	end
	if PASS_KEYS[key] then
		self:SetPropagateKeyboardInput(true)
		return
	end
	local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
	if key == "ENTER" or key == "NUMPADENTER" then
		local se = SecureView(results[sel], shift)
		if se and UI:ArmForPress(se) then
			self:SetPropagateKeyboardInput(true) -- this same press reaches the game's binding
			UI:FinishSoon(se)
			return
		end
		self:SetPropagateKeyboardInput(false)
		UI:Activate(nil, { keepOpen = ctrl, secondary = shift })
		return
	end
	self:SetPropagateKeyboardInput(false)

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

--- What a key does to the query (also run again for held keys).
EditKey = function(key, ctrl, shift)
	local text, c = edit:GetText(), UI.cursor
	if key == "ESCAPE" or key == "`" then
		UI:Hide()
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
	elseif key == "LEFT" then
		UI.cursor = PrevPos(text, c); UI:UpdateCaret()
	elseif key == "RIGHT" then
		UI.cursor = NextPos(text, c); UI:UpdateCaret()
	elseif key == "HOME" then
		UI.cursor = 0; UI:UpdateCaret()
	elseif key == "END" then
		UI.cursor = #text; UI:UpdateCaret()
	elseif key == "UP" then
		UI:Move(-1)
	elseif key == "DOWN" then
		UI:Move(1)
	elseif key == "TAB" then
		UI:Move(shift and -1 or 1)
	elseif key == "PAGEUP" then
		UI:Move(-ROWS)
	elseif key == "PAGEDOWN" then
		UI:Move(ROWS)
	elseif ctrl then
		if key == "N" or key == "J" then UI:Move(1)
		elseif key == "P" or key == "K" then UI:Move(-1)
		elseif key == "U" then UI:SetQuery("", 0)
		elseif key == "V" or key == "A" or key == "C" then
			UI:EnterEdit() -- clipboard and selection need the real text box
		end
	elseif not IsAltKeyDown() then
		CheckChar(key)
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
	self.pendingChar = nil
	self.charChecked = true
	if not self.keys or not frame:IsShown() then return end
	local q, c = edit:GetText(), self.cursor
	self:SetQuery(q:sub(1, c) .. text .. q:sub(c + 1), c + #text)
end

----------------------------------------------------------------------
-- Activation
----------------------------------------------------------------------

function UI:Activate(idx, opts)
	opts = opts or {}
	local e = results[idx or sel]
	if not e or e.noActivate then return end
	-- Opening or clicking Blizzard's windows is protected in combat: do nothing rather than
	-- have the game block us. (Shift+Enter actions that don't touch windows still work.)
	if InCombatLockdown() and (e.noCombat or e.secure) and not (opts.secondary and e.secondary and not e.noCombatSecondary) then
		ns:Trace("combat: ignored Enter on " .. tostring(e.name))
		ns:Print("In combat: can't open " .. tostring(e.name) .. " now.")
		return
	end
	-- windows Blizzard owns are opened by a secure click, never from our own code
	local se = SecureView(e, opts.secondary)
	if se and self:TryArmSecure(se) then return end
	local args = self.args
	local isCmd = e.kind == "cmd"
	if not opts.keepOpen then self:Hide() end
	ns:Bump(e.freqKey)
	local fn = (opts.secondary and e.secondary) or e.activate
	ns:Trace(("DIRECT (addon code) %s: %s [%s]"):format(opts.secondary and "secondary" or "activate", tostring(e.name), tostring(e.kind)))
	if not fn then return end
	local ok, ret = pcall(fn, e, args, self)
	if not ok then
		ns:Print("error: " .. tostring(ret))
		return
	end
	-- a command's answer goes to the chat window, not into the results
	if isCmd and type(ret) == "table" then ns:Output(ret) end
end

----------------------------------------------------------------------
-- Frame construction
----------------------------------------------------------------------

local function Build()
	if frame then return end

	frame = CreateFrame("Frame", "TerminalFrame", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:EnableKeyboard(false)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		ns.db.point = { p, rp, x, y }
	end)
	frame:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(delta) end)
	frame:SetScript("OnHide", function(self)
		if tip then tip:Hide() end
		UI:Disarm()
		UI.keys = false
		StopRepeat()
		self:EnableKeyboard(false)
		if caret then caret:Hide() end
	end)
	frame:SetScript("OnKeyDown", function(self, key)
		if UI.keys then return KeysDown(self, key) end
		if UI.legacyArm then return LegacyDown(self, key) end
		if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
	end)
	frame:SetScript("OnChar", function(_, text) UI:OnChar(text) end)
	frame:SetScript("OnKeyUp", function(_, key)
		if rep.key == key then StopRepeat() end
	end)
	frame:Hide()

	local pt = ns.db.point
	if pt then
		frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
	tinsert(UISpecialFrames, "TerminalFrame")

	promptFS = frame:CreateFontString(nil, "OVERLAY")
	promptFS:SetFontObject(Theme.fonts.input)
	UI.promptFS = promptFS

	edit = CreateFrame("EditBox", nil, frame)
	edit:SetFontObject(Theme.fonts.input)
	edit:SetAutoFocus(false)
	edit:SetAltArrowKeyMode(false)
	edit:SetMaxLetters(256)
	UI.edit = edit
	edit:SetScript("OnTextChanged", function(self)
		-- the key that opened the terminal (` or ~) must not end up typed into the box
		local t = self:GetText()
		if t:find("^[`~]") then
			local stripped = t:gsub("^[`~]+", "")
			UI.cursor = math.max(0, (UI.cursor or 0) - (#t - #stripped))
			self:SetText(stripped)
			return
		end
		if not UI.keys then
			local cp = self:GetCursorPosition()
			if type(cp) == "number" then UI.cursor = cp end
		end
		UI.cursor = math.min(UI.cursor or #t, #t)
		UI:Refresh()
		UI:UpdateCaret()
	end)
	edit:SetScript("OnEditFocusGained", function()
		-- clicked into the box: plain text editing (clipboard, selection) until reopened
		if UI.keys then
			UI.keys = false
			frame:EnableKeyboard(false)
			UI:UpdateCaret()
		end
	end)
	edit:SetScript("OnEnterPressed", function()
		UI:Activate(nil, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
	end)
	edit:SetScript("OnEscapePressed", function() UI:Hide() end)
	edit:SetScript("OnArrowPressed", function(_, key)
		if key == "UP" then UI:Move(-1) elseif key == "DOWN" then UI:Move(1) end
	end)
	edit:SetScript("OnTabPressed", function() UI:Move(IsShiftKeyDown() and -1 or 1) end)
	edit:SetScript("OnKeyDown", function(_, key)
		if key == "`" then
			-- bindings don't fire while the box has focus, so the toggle key closes it here
			UI:Hide()
		elseif key == "PAGEUP" then
			UI:Move(-ROWS)
		elseif key == "PAGEDOWN" then
			UI:Move(ROWS)
		elseif IsControlKeyDown() then
			if key == "N" or key == "J" then UI:Move(1)
			elseif key == "P" or key == "K" then UI:Move(-1)
			elseif key == "U" then edit:SetText("") end
		end
	end)

	measure = frame:CreateFontString(nil, "OVERLAY")
	measure:SetFontObject(Theme.fonts.input)
	measure:SetAlpha(0)

	caret = frame:CreateTexture(nil, "OVERLAY")
	caret:SetWidth(2)
	caret:Hide()
	local blink = caret:CreateAnimationGroup()
	blink:SetLooping("BOUNCE")
	local fade = blink:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.1)
	fade:SetDuration(0.5)
	blink:Play()

	divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	-- the prompt's own background, behind the query box (Theme promptBg)
	promptBg = frame:CreateTexture(nil, "BORDER")
	UI.promptBg = promptBg

	for i = 1, MAX_ROWS do
		local b = CreateFrame("Button", nil, frame)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
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
		b:SetScript("OnClick", function()
			sel = offset + i
			UI:Activate(sel, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
		end)
		b:SetScript("OnEnter", function()
			if results[offset + i] and sel ~= offset + i then
				if UI.armedEntry then UI:Disarm() end
				sel = offset + i
				UI:Render()
			end
		end)
		b:Hide()
		rows[i] = b
	end

	status = frame:CreateFontString(nil, "OVERLAY")
	status:SetFontObject(Theme.fonts.small)
	status:SetPoint("BOTTOMLEFT", 12, 7)
	hints = frame:CreateFontString(nil, "OVERLAY")
	hints:SetFontObject(Theme.fonts.small)
	hints:SetPoint("BOTTOMRIGHT", -12, 7)
	hints:SetText(HINTS)
	hints:SetJustifyH("RIGHT")
	hints:SetWordWrap(true)

	UI:ApplyTheme()
end

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------

function UI:ApplyTheme()
	if not frame then return end
	local t = Theme.Get()
	Theme.ApplyFonts()

	ROWS = math.max(1, math.min(MAX_ROWS, t.rows))
	ROW_H = math.max(22, t.fontSize + 12)
	HEADER_H = math.max(50, t.fontSize + 36)
	-- footer: the key hints sit right of the result count; on a narrow terminal they wrap
	-- onto a second line instead of running into it
	local footerH = FOOTER_H
	if t.hints then
		local saved = status:GetText()
		status:SetText("000 results  |  commands")
		local reserve = (status:GetStringWidth() or 0) + 20
		status:SetText(saved or "")
		hints:SetText(HINTS)
		local avail = t.width - 24 - reserve
		local full = hints:GetStringWidth() or 0
		if full > avail then
			hints:SetWidth(math.max(120, avail))
			footerH = FOOTER_H + math.max(10, t.fontSize - 2) + 2
		else
			hints:SetWidth(full + 4)
		end
	end
	UI.footerH = footerH
	frame:SetSize(t.width, HEADER_H + ROWS * ROW_H + footerH)
	frame:SetScale(t.scale)

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
	divider:ClearAllPoints()
	local inset = classic and 5 or 1
	divider:SetPoint("TOPLEFT", inset, -(HEADER_H - 4))
	divider:SetPoint("TOPRIGHT", -inset, -(HEADER_H - 4))
	local pin = classic and 4 or 1
	promptBg:ClearAllPoints()
	promptBg:SetPoint("TOPLEFT", pin, -pin)
	promptBg:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -pin, -(HEADER_H - 4))
	local pr, pg, pb = Theme.RGB(t.promptBg or t.bg)
	promptBg:SetColorTexture(pr, pg, pb, t.bgAlpha)

	-- prompt, then the query box right after it
	local mid = -(HEADER_H - 4) / 2
	promptFS:SetText("|cff" .. t.prompt .. t.promptText:gsub("|", "||") .. "|r")
	promptFS:ClearAllPoints()
	promptFS:SetPoint("LEFT", frame, "TOPLEFT", 14, mid)
	local pw = promptFS:GetStringWidth() or 10
	edit:ClearAllPoints()
	edit:SetPoint("LEFT", frame, "TOPLEFT", 14 + pw + 8, mid)
	edit:SetPoint("RIGHT", frame, "TOPRIGHT", -14, mid)
	edit:SetHeight(t.fontSize + 14)
	local tr, tg, tb = Theme.RGB(t.text)
	edit:SetTextColor(tr, tg, tb)

	local ar, ag, ab = Theme.RGB(t.accent)
	caret:SetColorTexture(ar, ag, ab, 1)
	caret:SetHeight(t.fontSize + 5)

	local dr, dg, db = Theme.RGB(t.dim)
	for i = 1, MAX_ROWS do
		local row = rows[i]
		local y = -HEADER_H - (i - 1) * ROW_H
		row:ClearAllPoints()
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 6, y)
		row:SetPoint("TOPRIGHT", -6, y)
		row.icon:SetSize(ROW_H - 6, ROW_H - 6)
		row.detail:SetWidth(math.floor(t.width * 0.3))
		row.label:SetTextColor(tr, tg, tb)
		row.detail:SetTextColor(dr, dg, db)
		if i > ROWS then row:Hide() end
	end
	status:SetTextColor(dr, dg, db)
	hints:SetTextColor(dr, dg, db)
	hints:SetShown(t.hints and true or false)

	Fuzzy.matchColor = "|cff" .. t.match
	offset = math.max(0, math.min(offset, #results - ROWS))
	self:Render()
	self:UpdateCaret()
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

function UI:IsShown() return frame and frame:IsShown() end

function UI:Hide()
	if not frame then return end
	self:Disarm()
	if tip then tip:Hide() end
	edit:ClearFocus()
	frame:Hide()
end

function UI:Open(text)
	Build()
	self:Disarm()
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if p.refreshOnOpen then p._dirty = true end
	end
	ns.Highlight:Clear()
	frame:Show()
	self.cursor = #(text or "")
	edit:SetText(text or "")
	self.cursor = #edit:GetText()
	self:Refresh()
	if not self:EnterKeys() then
		-- plain text box: focus next frame so the opening keypress isn't typed into it
		C_Timer.After(0, function()
			if frame:IsShown() and not UI.keys then edit:SetFocus() end
		end)
	end
	self:UpdateCaret()
end

function UI:Toggle()
	if self:IsShown() then self:Hide() else self:Open() end
end

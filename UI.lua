local ns = select(2, ...)
local Fuzzy = ns.Fuzzy
local Theme = ns.Theme

local UI = {}
ns.UI = UI

local FOOTER_H = 26 -- one line: the result count on the left, key hints on the right
-- key hints, most useful first: on a narrow terminal the last ones are left out, never wrapped
local HINTS = {
	{ "Enter", "open" }, { "Tab", "complete" }, { "Shift+Enter", "more" },
	{ "@", "kind" }, { "/", "slash" }, { ".", "command" }, { "=", "calc" },
}
local MAX_ROWS = 20
local MAX_RESULTS = 100
local SLICE_MS = 6 -- a search's share of one frame; a longer one goes on in the next frames
local SLICE_CHECK = 64 -- rows scored between looks at the clock
UI.SLICE_MS = SLICE_MS
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

local frame, edit, status, hints, promptFS, caret, measure, divider, promptBg, ghost, selBar, selEdge, footLine, selText, caretFrame, caretChar, hit, busy, catcher
local PlaceRow -- (Motion)
local rows = {}
UI.rows = rows
local motion = CreateFrame("Frame") -- drives every animation (see "Motion")
-- motion timings come from the animation style (Theme.ANIMATIONS)
local function Style() return Theme.Animation() or Theme.ANIMATIONS.smooth end
motion:Hide()
UI.motion = motion
-- something starts moving: the loop runs every frame again (resting, it only blinks the cursor)
local function Wake()
	UI.blinkOnly = false
	motion:Show()
end
local results = {}
function UI.Results() return results end
local sel, offset = 1, 0
function UI.Selected() return sel end
UI.args = nil
UI.keys = false   -- true while the terminal reads keystrokes itself (see "Keyboard")
UI.noChar = false -- set if this client never sends typed characters to frames
UI.cursor = 0     -- byte position of the caret in the query

----------------------------------------------------------------------
-- Scoring
----------------------------------------------------------------------

local function FreqBonus(e)
	local freq = ns.db and ns.db.freq
	if not freq then return 0 end
	-- compact rows build their key on every read: only for kinds that were ever picked
	local k = rawget(e, "freqKey")
	if not k then
		if not ns:FreqKind(e.kind) then return 0 end
		k = e.freqKey
	end
	local f = k and freq[k]
	return f and math.min(f, 20) * 0.05 or 0
end

--- The entry's score for these tokens, or nil. Allocation-free: matched letters (for the
--- highlight) are worked out later, only for the rows on screen (see Positions).
local function ScoreEntry(e, tokens)
	local total, nameHit = 0, false
	-- rawget: compact rows (tens of thousands of NPCs) would go through __index twice per row
	local ltext = rawget(e, "_ltext")
	if not ltext then
		local text = rawget(e, "text")
		if text then ltext = ns.Lower(text); e._ltext = ltext end
	end
	for i = 1, #tokens do
		local tk = tokens[i]
		local best = Fuzzy.score(tk, e.name, e._lname)
		if best then
			nameHit = true
		end
		if ltext and (not best or best < TEXT_SCORE) and ltext:find(tk, 1, true) then
			best = TEXT_SCORE
		end
		if not best then return nil end
		total = total + best
	end
	e._pos, e._nameHit = nil, nameHit
	return total
end

--- The matched letters of the entry's name for these tokens (a set of byte positions).
local function Positions(e, tokens)
	local set = {}
	if not (e._nameHit and tokens) then return set end
	for _, tk in ipairs(tokens) do
		local _, pos = Fuzzy.match(tk, e.name, e._lname)
		if pos then
			for _, i in ipairs(pos) do set[i] = true end
		end
	end
	return set
end

local function Better(a, b)
	if a._score ~= b._score then return a._score > b._score end
	local an, bn = a._lname or "", b._lname or ""
	if an ~= bn then return an < bn end
	return tostring(a.key) < tostring(b.key)
end

--- The best MAX_RESULTS of the list, in order. With thousands of matches, a small heap keeps
--- only the best so far instead of sorting them all.
local function SortAndTrim(list)
	local n = #list
	if n > MAX_RESULTS * 2 then
		local heap, size = {}, 0 -- worst of the kept ones on top
		local function up(i)
			while i > 1 do
				local p = math.floor(i / 2)
				if Better(heap[p], heap[i]) then heap[p], heap[i] = heap[i], heap[p]; i = p else break end
			end
		end
		local function down(i)
			while true do
				local l, r, w = i * 2, i * 2 + 1, i
				if l <= size and Better(heap[w], heap[l]) then w = l end
				if r <= size and Better(heap[w], heap[r]) then w = r end
				if w == i then return end
				heap[w], heap[i] = heap[i], heap[w]
				i = w
			end
		end
		for k = 1, n do
			local e = list[k]
			if size < MAX_RESULTS then
				size = size + 1
				heap[size] = e
				up(size)
			elseif Better(e, heap[1]) then
				heap[1] = e
				down(1)
			end
		end
		for k = n, 1, -1 do list[k] = nil end
		for k = 1, size do list[k] = heap[k] end
	end
	table.sort(list, Better)
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

local function RunCmd(e, args) return e.cmd.run(args or "", ns) end
local cmdList, cmdCount -- the command rows, made again only when commands are added

function UI:CommandEntries()
	if cmdList and cmdCount == #ns.commandOrder then return cmdList end
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
			cmd = c,
			activate = RunCmd,
		}
	end
	cmdList, cmdCount = list, #ns.commandOrder
	return list
end

local function RunArg(e) return e.cmd.run(e.argLine, ns) end

--- The arguments a command takes, as rows, while you type them: ".theme " lists the themes,
--- ".set cursor " the cursor styles. A command's `complete(args)` gives them, as strings or
--- { value, detail }. Each row runs the command with that argument (Enter, a click, or Tab and
--- the arrows to pick one). With nothing typed yet, the command itself comes first, so Enter
--- still runs it as typed. Nil when the command takes no listed arguments, or none match.
function UI:ArgEntries(text)
	local word, rest = text:match("^%s*(%S+)%s(.*)$")
	local c = word and ns:FindCommand(word)
	if not (c and c.complete) then return nil end
	local ok, list = pcall(c.complete, rest)
	if not ok or type(list) ~= "table" then return nil end
	local before, argWord = rest:match("^(.-)(%S*)$")
	local lw = ns.Lower(argWord)
	local out = {}
	for i, cand in ipairs(list) do
		local val, detail = cand, nil
		if type(cand) == "table" then val, detail = cand[1], cand[2] end
		local lv = type(val) == "string" and ns.Lower(val)
		local at = lv and (lw == "" and 1 or lv:find(lw, 1, true))
		if at then
			out[#out + 1] = {
				kind = "cmd", kindLabel = "|cff33ff99." .. c.name .. "|r", icon = "Interface\\Icons\\INV_Misc_Note_01",
				name = val, _lname = lv, key = c.name .. " " .. val, freqKey = "cmd:" .. c.name,
				detail = detail or "", cmd = c, argLine = before .. val, activate = RunArg, _nameHit = true,
				_score = (at == 1 and 1000 or 500) - i, -- starts with what's typed first, then in the list's order
			}
		end
	end
	if #out == 0 then return nil end
	if lw == "" then
		for _, e in ipairs(self:CommandEntries()) do
			if e.name == c.name then
				e._score, e._pos = 2000, {}
				table.insert(out, 1, e)
				break
			end
		end
	end
	self.args = rest
	self.posTokens = lw ~= "" and { lw } or nil
	table.sort(out, function(a, b) return a._score > b._score end)
	return out
end

--- Used by "/" and "." modes: first word picks the entry, the rest is its arguments.
function UI:WordSearch(entries, text)
	local word, rest = text:match("^%s*(%S*)%s*(.*)$")
	self.args = rest
	local tokens
	if word ~= "" and word ~= "/" then tokens = { ns.Lower(word) } end
	self.posTokens = tokens
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
			tokens[#tokens + 1] = ns.Lower(w)
		end
	end
	local empty = #tokens == 0
	self.posTokens = tokens
	if empty and not kinds then self.lastScan = nil return self:FrequentEntries() end

	local out = {}
	local included = {}
	local fresh = true -- every list read is already built (nothing to re-collect)
	local sig = {}
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		local inc
		if kinds then inc = kinds[id] else inc = not p.explicit end
		if inc then
			included[#included + 1] = p
			sig[#sig + 1] = id
			if p._dirty or not p._entries then fresh = false end
		end
	end
	sig = table.concat(sig, ",")
	-- typing one more letter can only narrow the matches: score just the last ones again
	local last = self.lastScan
	local candidates
	if not empty and fresh and last and last.sig == sig and last.gen == ns.entriesGen and #last.tokens == #tokens then
		candidates = last.matches
		for i = 1, #tokens do
			local a, b = last.tokens[i], tokens[i]
			if i < #tokens and a ~= b then candidates = nil break end
			if i == #tokens and b:sub(1, #a) ~= a then candidates = nil break end
		end
	end
	local function consider(e)
		if empty then
			e._score, e._pos = FreqBonus(e), {}
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s then
				e._score = s + FreqBonus(e)
				out[#out + 1] = e
			end
		end
	end
	self.lastSearchNarrowed = candidates and true or false
	-- run by UI:RunSearch: past this frame's share, hand back what matched so far and go on
	-- in the next frame (tens of thousands of NPCs or quests no longer hitch one frame)
	local slicing = self.sliceUntil ~= nil and coroutine.running() ~= nil
	local function overBudget() return slicing and debugprofilestop() > self.sliceUntil end
	if candidates then
		for i = 1, #candidates do
			consider(candidates[i])
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = ns:GetEntries(p)
			if overBudget() then coroutine.yield(out) end -- (reading the list may have taken the share)
			for i = 1, #list do
				consider(list[i])
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	if not empty then
		local matches = {}
		for i = 1, #out do matches[i] = out[i] end
		self.lastScan = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = matches }
	end
	-- a quest item brings its quest along, right below it ("Intact Limbs" -> its quest)
	if not empty and (not kinds or kinds.quests) and ns.providers.quests then
		local linked, from, guessed = {}, {}, {}
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
						linked[id] = e._score; from[id] = e; guessed[id] = true
					end
				end
			end
		end
		if next(linked) then
			local present = {} -- quests already among the results
			for _, e in ipairs(out) do if e.kind == "quests" then present[e] = true end end
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
					if not present[q] or it._nameHit then
						q._score = s - 0.001
						self.linked[q] = it
						self.linkedGuess[q] = guessed[q.questID] or nil
					end
				end
			end
		end
	end
	local res = SortAndTrim(out)
	-- nothing here has what was typed in its name, but a list only searched with @kind does
	-- (Questie's quests, NPCs): a row on top offers it (Tab or Enter adds the @kind)
	if not kinds and not empty then
		local hints, at = self:BigListHint(text, tokens, res, overBudget)
		for i, hint in ipairs(hints or {}) do table.insert(res, math.min((at or 1) + i - 1, #res + 1), hint) end
	end
	return res
end

-- the lists offered by that row, in order: big databases only searched with @kind
local HINT_KINDS = { "stored", "questie", "npc" }

local function NameHasAll(e, tokens)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	for i = 1, #tokens do
		if not ln:find(tokens[i], 1, true) then return false end
	end
	return true
end

local function HintActivate(e) UI:SetQuery(e.completion, #e.completion) end

--- The "Search <list> for this" row, or nil. Only when no result has every typed word in its
--- name and an @kind list has a match: by name (a plain substring look) in the huge lists, or a
--- full match (hintFull: @stored, by item and holder). Spread over frames like the search.
function UI:BigListHint(text, tokens, res, overBudget)
	local typed = 0
	for i = 1, #tokens do typed = typed + #tokens[i] end
	if typed < 3 then return nil end
	-- your own results already have it: only a list marked hintSecond (@stored: the same item on
	-- an alt or in a bank) is still offered, as the second row, under what you carry
	local mine = false
	for _, e in ipairs(res) do
		if NameHasAll(e, tokens) then mine = true break end
	end
	local hints = {} -- one row per list that has it (a name can be a quest and an NPC both)
	for _, id in ipairs(HINT_KINDS) do
		local p = ns.providers[id]
		if p and p.explicit and (not mine or p.hintSecond) then
			local list = ns:GetEntries(p)
			local first, count = nil, 0
			for i = 1, #list do
				local e = list[i]
				if (p.hintFull and ScoreEntry(e, tokens)) or (not p.hintFull and NameHasAll(e, tokens)) then
					count = count + 1
					first = first or e
					if count >= 100 then break end
				end
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(res) end
			end
			if first then
				local kind = "@" .. (p.aliases and p.aliases[1] or id)
				local query = text:gsub("^%s+", "")
				hints[#hints + 1] = {
					name = ("Search %s for this"):format(p.hintLabel or p.label), kindLabel = "|cff33ff99Tab|r",
					detail = first.name .. (count > 1 and ("  +%s more"):format(count >= 100 and "99" or count - 1) or ""),
					icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
					completion = kind .. " " .. query, staysOpen = true, activate = HintActivate,
					_score = math.huge, _pos = {},
				}
			end
		end
	end
	if #hints > 0 then return hints, mine and 2 or 1 end
end

--- A search spread over frames: up to SLICE_MS of it now. Gives the results to show, and
--- whether they're final; if not, the best matches found so far (sorted once, on a copy) show
--- now and the search goes on quietly in the next frames (see ContinueSearch).
function UI:RunSearch(text)
	self.searchJob = nil
	if not (debugprofilestop and coroutine) then return self:Search(text), true end
	local job = { co = coroutine.create(function() return self:Search(text) end), ms = 0 }
	job.step = function() self:ContinueSearch(job) end
	local res, done = self:StepSearch(job)
	if done then return res, true end
	-- not finished: the best of what matched so far (on a copy: the search goes on filling it),
	-- under the calculator's answer when there is one (Search adds it only at the end)
	local t0 = debugprofilestop()
	local copy = {}
	for i = 1, #res do copy[i] = res[i] end
	copy = SortAndTrim(copy)
	local calc = ns.Calc and ns.Calc.Entry(text)
	if calc then table.insert(copy, 1, calc) end
	job.ms = job.ms + (debugprofilestop() - t0)
	return copy, false
end

function UI:StepSearch(job)
	local t0 = debugprofilestop()
	self.sliceUntil = t0 + SLICE_MS
	local ok, res = coroutine.resume(job.co)
	self.sliceUntil = nil
	job.ms = job.ms + (debugprofilestop() - t0)
	job.slices = (job.slices or 0) + 1
	if not ok then
		self.searchJob = nil
		ns:Print("search error: " .. tostring(res))
		return {}, true
	end
	if coroutine.status(job.co) == "dead" then
		self.searchJob = nil
		return res or {}, true
	end
	self.searchJob = job
	return res, false -- the matches so far (still being filled)
end

--- The next frame's share of the search. Once done, the full results replace the early ones;
--- the selected result stays selected if it's still there.
function UI:ContinueSearch(job)
	if self.searchJob ~= job then return end -- typed again, or closed: this search is stale
	if not self:IsShown() or self.closing or self.armedEntry then self.searchJob = nil return end
	local final, done = self:StepSearch(job)
	if not done then
		C_Timer.After(0, job.step) -- (one closure per search, not one per frame)
		return
	end
	-- the selected row (if you moved it) stays selected, and the list stays where you scrolled it
	local keep = (sel > 1 or offset > 0) and results[sel] or nil
	local keptRow = sel - offset
	results = final
	sel, offset = 1, 0
	if keep then
		for i, e in ipairs(results) do
			if e == keep then
				sel = i
				offset = math.max(0, math.min(i - keptRow, #results - ROWS))
				break
			end
		end
	end
	self.lastSearchMs, self.lastSearchCount, self.lastSearchSlices = job.ms, #results, job.slices
	self:UpdateBusy()
	self:Render()
end

function UI:Refresh()
	if not frame then return end
	-- typed faster than a frame: one search for the whole burst, on the next frame
	local now = GetTime()
	if self.refreshedAt == now then
		if not self.refreshQueued then
			self.refreshQueued = true
			C_Timer.After(0, function()
				self.refreshQueued = false
				self.refreshedAt = nil
				if self:IsShown() then self:Refresh() end
			end)
		end
		return
	end
	self.refreshedAt = now
	if self.searchJob then ns:Trace("search: started again before the last one finished (" .. (self.searchJob.slices or 0) .. " frames in)") end
	self.searchJob = nil -- a search still going on is for the old text
	self.searchedText = edit:GetText()
	local t0 = debugprofilestop and debugprofilestop()
	if self.armedEntry then self:Disarm() end -- the query changed: whatever was armed is stale
	self.pendingAfter = nil
	self.args = nil
	self.mode = "search"
	local text = edit:GetText():gsub("^%s+", "")
	local first = text:sub(1, 1)
	if first == "." then
		self.mode = "cmd"
		results = self:ArgEntries(text:sub(2)) or self:WordSearch(self:CommandEntries(), text:sub(2))
	elseif first == "/" then
		self.mode = "slash"
		local p = ns.providers.slash
		results = p and self:WordSearch(ns:GetEntries(p), text) or {}
	else
		local done
		results, done = self:RunSearch(text)
		if not done then
			C_Timer.After(0, self.searchJob.step)
		end
	end
	if t0 then self.lastSearchMs = debugprofilestop() - t0 end
	self.lastSearchCount = #results
	self.lastSearchSlices = 1
	self:UpdateBusy()
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
	if not UI:IsShown() then return end
	local e = results[sel]
	if not e or e.noActivate then return end
	-- entries may supply a link directly, or a function that builds it only when selected
	local link = e.link
	if not link and e.getLink then
		local ok, l = pcall(e.getLink, e)
		link = ok and l or nil
	end
	if not (link or e.tip or e.tooltip) then return end
	t:SetOwner(frame, "ANCHOR_NONE")
	PlaceTip(t)
	local shown = false
	if e.tooltip then -- the entry draws its own (stored items: who has how many)
		shown = pcall(e.tooltip, e, t)
	end
	if link and not shown then
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
	if mode then text = text .. (text ~= "" and "  ·  " or "") .. mode end
	if busy and busy:IsShown() then text = text .. (text ~= "" and "  ·  " or "") .. "loading..." end
	status:SetText(text)
	self:FitHints()
end

--- The key hints: each key in the text colour, its meaning dimmed, as many as fit on one
--- line beside the result count (the less useful ones go first when it's narrow).
function UI:FitHints()
	if not (hints and frame) then return end
	local t = Theme.Get()
	if not t.hints then hints:Hide() return end
	local key = "|cff" .. t.text
	local room = (t.width or 640) - 28 - (status:GetStringWidth() or 0) - 24
	-- every render asks: measure again only when the room or the colours changed
	if self.hintsRoom == room and self.hintsKey == key then return end
	self.hintsRoom, self.hintsKey = room, key
	local parts, text = {}, ""
	for _, h in ipairs(HINTS) do
		parts[#parts + 1] = key .. h[1] .. "|r " .. h[2]
		local try = table.concat(parts, "     ")
		hints:SetText(try)
		if (hints:GetStringWidth() or 0) > room then
			parts[#parts] = nil
			break
		end
		text = try
	end
	hints:SetText(text)
	self.hintCount = #parts
	hints:SetShown(text ~= "")
end

local ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12|t "

function UI:Render()
	-- nothing to draw while it's closed (a setting changed in the options panel, say): drawing
	-- then put the rows up, and the next open showed them without their animation
	if not frame or not frame:IsShown() then return end
	local t = Theme.Get()
	local light = Theme.IsLight()
	-- rows come in with the style on every open (snapNext, on open, is for the height only);
	-- only a new layout (theme changes) puts them up at once
	local animated = self:Animated() and not (self.snapNext and not self.opening)
	local now, entering = GetTime(), 0
	for i = 1, MAX_ROWS do
		local r = rows[i]
		local idx = offset + i
		local e = (i <= ROWS) and results[idx] or nil
		if e then
			-- a row that wasn't there fades in (one after another); a row that stays just
			-- takes its new text, so typing doesn't repaint the whole list
			if not r:IsShown() or r.leaving then
				r.leaving, r.slideOut = nil, nil -- (reopened while folding away: it comes back)
				if animated then
					local A = Style()
					r.fadeAt = now + entering * A.stagger
					r.slide = A.slide > 0 and A.slide or nil
					if r.slide then PlaceRow(r, -r.slide) end
					entering = entering + 1
					if not r:IsShown() then r:SetAlpha(0) end
					Wake()
				else
					r.fadeAt = nil
					r:SetAlpha(1)
				end
			end
			r:Show()
			if e.raw then
				r.label:SetText(Theme.FixColors(e.name))
			else
				local base = e.color
				if light and base == "|cffffffff" then base = nil end -- white item names vanish on light themes
				if e._pos == nil then e._pos = Positions(e, self.posTokens) end -- only for rows on screen
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
		elseif r:IsShown() and not r.leaving then
			-- no result for this row any more: it fades as the list shrinks over it
			if animated and i <= ROWS then
				r.leaving, r.leaveAt, r.fadeAt = true, now, nil
				Wake()
			else
				r:Hide()
			end
		elseif not r.leaving then
			r:Hide()
		end
	end
	self:FitHeight()
	self:PlaceSelection()
	self:SetStatus()
	self:UpdateTooltip()
	self:UpdateGhost()
	-- the list moved under the pointer (typing, scrolling): the catcher follows its row
	if catcher and catcher.entry and catcher:IsShown() then self:PlaceCatcher(catcher.row) end
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

--- Walk back (dir -1) or forward (dir 1) through the lines run before. Only from an empty
--- prompt, or while already walking: typing anything ends it.
function UI:History(dir)
	local h = ns.db and ns.db.history
	if type(h) ~= "table" or #h == 0 then return false end
	local idx = self.histIdx
	if dir < 0 then
		idx = math.min(#h, (idx or 0) + 1)
	else
		idx = (idx or 0) - 1
	end
	local text = idx >= 1 and h[idx] or ""
	self._histSet = true
	self:SetQuery(text, #text)
	self._histSet = false
	self.histIdx = idx >= 1 and idx or nil
	return true
end

--- Up: the list's selection goes up; past the first row of an empty prompt it goes back through
--- the history instead.
function UI:Up()
	if (self.histIdx or (edit:GetText() == "" and sel <= 1)) and self:History(-1) then return end
	self:Move(-1)
end

function UI:Down()
	if self.histIdx ~= nil and self:History(1) then return end
	self:Move(1)
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
	local ok, err = pcall(e.after, e)
	if not ok then ns:Trace("after-step error for " .. tostring(e.name) .. ": " .. tostring(err)) end
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
	local target = S.Resolve(e.secure, e)
	if not target then ns:Trace("secure: no binding/button for " .. e.name) return false end
	if e.isOpen and e.isOpen(e) then -- nothing to click, just point at the thing
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
	local target = S.Resolve(e.secure, e)
	if not target or (e.isOpen and e.isOpen(e)) then return false end
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
		elseif not UI:IsShown() then
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
	if self:IsShown() and not self.keys and not self.noChar then self:EnterKeys() end
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

--- The selected part of the query as byte positions (lo, hi), or nil. The drawn prompt keeps
--- its own selection: `anchor` is where it started, the caret is where it ends.
function UI:SelRange()
	local a, c = self.anchor, self.cursor
	if not (a and c) or a == c or not edit then return nil end
	local n = #edit:GetText()
	a, c = math.min(a, n), math.min(c, n)
	if a == c then return nil end
	if a < c then return a, c end
	return c, a
end

--- Where text of `pos` bytes ends on the prompt line.
local function TextX(text, pos)
	measure:SetText((text:sub(1, pos):gsub("|", "||")))
	return math.min(measure:GetStringWidth() or 0, (edit:GetWidth() or 400) - 2)
end

--- The selection band, from where the selection started to the (gliding) caret.
function UI:PlaceTextSel()
	if not selText then return end
	if not (self.keys and self:IsShown() and self.anchorX and self:SelRange()) then
		selText:Hide()
		return
	end
	local x1, x2 = self.anchorX, self.caretX or self.caretTo or 0
	if x1 > x2 then x1, x2 = x2, x1 end
	selText:ClearAllPoints()
	selText:SetPoint("LEFT", edit, "LEFT", x1, 0)
	selText:SetSize(math.max(1, x2 - x1), Theme.Get().fontSize + 5)
	selText:Show()
end

function UI:UpdateCaret()
	if not caret then return end
	if hit then hit:SetShown(self.keys and self:IsShown() and true or false) end
	if not (self.keys and self:IsShown()) then
		self.dragging = false
		caret:Hide()
		caretChar:Hide()
		if selText then selText:Hide() end
		self:UpdateGhost()
		return
	end
	local text = edit:GetText()
	self.caretTo = TextX(text, self.cursor)
	self.anchorX = self:SelRange() and TextX(text, self.anchor) or nil
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
end

--- Put the cursor (and, for a box, its character) at the caret's current x.
function UI:PlaceCaret()
	local x = self.caretX or self.caretTo or 0
	self.caretPlaced = x
	caret:ClearAllPoints()
	caret:SetPoint("LEFT", edit, "LEFT", x, 0)
	if self.caretCh and self.caretCh ~= "" and CursorStyle().box then
		caretChar:ClearAllPoints()
		caretChar:SetPoint("LEFT", edit, "LEFT", x, 0)
		caretChar:Show()
	else
		caretChar:Hide()
	end
end

--- Where the mouse is along the prompt text, in the text's own units.
local function PromptX()
	local cx = GetCursorPosition and GetCursorPosition()
	local scale, left = edit:GetEffectiveScale(), edit:GetLeft()
	if type(cx) ~= "number" or type(left) ~= "number" or type(scale) ~= "number" or scale == 0 then return 0 end
	return cx / scale - left
end

--- The caret position (in bytes) nearest to x.
local function IndexAt(x)
	local text = edit:GetText()
	local best, bestD, pos = 0, math.abs(x), 0
	while pos < #text do
		pos = NextPos(text, pos)
		local w = TextX(text, pos)
		local d = math.abs(x - w)
		if d < bestD then best, bestD = pos, d end
		if w >= x then break end
	end
	return best
end

--- Mouse down on the prompt: the cursor goes there (shift extends the selection); dragging
--- selects. The prompt stays Terminal's own, so the chosen cursor style stays too.
function UI:PressPrompt()
	if not (self.keys and edit) then return end
	local idx = IndexAt(PromptX())
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
	if not (self.dragging and self.keys) then -- the drag ended some other way (closed, focus): stop watching
		if hit then hit:SetScript("OnUpdate", nil) end
		return
	end
	local idx = IndexAt(PromptX())
	if idx ~= self.cursor then
		self.cursor = idx
		self:UpdateCaret()
	end
end

function UI:ReleasePrompt()
	self.dragging = false
	if hit then hit:SetScript("OnUpdate", nil) end
	if self.anchor == self.cursor then self.anchor = nil end
	self:UpdateCaret()
end

----------------------------------------------------------------------
-- Still loading: providers say so with `busy` (Syndicator scanning, AtlasLoot or Questie being
-- indexed, item names on their way); a spinner at the end of the prompt shows it.
----------------------------------------------------------------------

local BUSY_DOTS = 8

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
	if not (edit and self.editLeft) then return end
	edit:ClearAllPoints()
	edit:SetPoint("LEFT", frame, "TOPLEFT", self.editLeft, self.editMid)
	-- room for the spinner is always kept: resizing the box as it came and went made the game
	-- report the text as changed
	edit:SetPoint("RIGHT", frame, "TOPRIGHT", -38, self.editMid)
end

--- Show or hide the spinner. When loading ends, the results are searched again so what just
--- arrived shows up.
function UI:UpdateBusy()
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

function UI:EnterKeys()
	if not frame or self.noChar or InCombatLockdown() then return false end
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
	if not (UI.keys and UI:IsShown()) or (IsKeyDown and not IsKeyDown(self.key)) then
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
	elseif key == "BACKSPACE" and UI:SelRange() then
		local lo, hi = UI:SelRange()
		UI:SetQuery(text:sub(1, lo) .. text:sub(hi + 1), lo)
	elseif key == "BACKSPACE" then
		if ctrl then
			local before = text:sub(1, c):gsub("[^%s]*%s*$", "") -- the word left of the caret (and spaces after it)
			UI:SetQuery(before .. text:sub(c + 1), #before)
		elseif c > 0 then
			local p = PrevPos(text, c)
			UI:SetQuery(text:sub(1, p) .. text:sub(c + 1), p)
		end
	elseif key == "DELETE" and UI:SelRange() then
		local lo, hi = UI:SelRange()
		UI:SetQuery(text:sub(1, lo) .. text:sub(hi + 1), lo)
	elseif key == "DELETE" then
		if c < #text then UI:SetQuery(text:sub(1, c) .. text:sub(NextPos(text, c) + 1), c) end
	elseif key == "LEFT" then
		local lo = UI:SelRange()
		if lo and not shift then
			MoveCaret(lo, false) -- a selection collapses to its left end
		else
			MoveCaret(ctrl and WordLeft(text, c) or PrevPos(text, c), shift)
		end
	elseif key == "RIGHT" then
		local lo, hi = UI:SelRange()
		if lo and not shift then
			MoveCaret(hi, false)
		elseif not shift and not ctrl and c >= #text and UI:AcceptCompletion() then
			return -- at the end: take the suggestion
		else
			MoveCaret(ctrl and WordRight(text, c) or NextPos(text, c), shift)
		end
	elseif key == "HOME" then
		MoveCaret(0, shift)
	elseif key == "END" then
		MoveCaret(#text, shift)
	elseif key == "UP" then
		UI:Up()
	elseif key == "DOWN" then
		UI:Down()
	elseif key == "TAB" then
		-- Tab completes, like a shell; with nothing (more) to complete it moves down the list
		if shift or not UI:AcceptCompletion() then UI:Move(shift and -1 or 1) end
	elseif key == "PAGEUP" then
		UI:Move(-ROWS)
	elseif key == "PAGEDOWN" then
		UI:Move(ROWS)
	elseif ctrl then
		if key == "N" or key == "J" then UI:Move(1)
		elseif key == "P" or key == "K" then UI:Move(-1)
		elseif key == "U" then UI:SetQuery("", 0)
		elseif key == "A" then
			UI.anchor = 0; UI.cursor = #text; UI:UpdateCaret() -- select all
		elseif key == "V" or key == "C" then
			UI:EnterEdit() -- the clipboard needs the real text box (press it again there)
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
	if not self.keys or not self:IsShown() then return end
	local q, c = edit:GetText(), self.cursor
	local lo, hi = self:SelRange()
	if lo then q, c = q:sub(1, lo) .. q:sub(hi + 1), lo end -- typing replaces the selection
	self:SetQuery(q:sub(1, c) .. text .. q:sub(c + 1), c + #text)
end

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


--- The macro a click on this result runs (nil: none), and the entry view it opens.
local function ClickFor(e, shift)
	local se = SecureView(e, shift)
	if not se then return nil end
	if se.isOpen and se.isOpen(se) then return nil end -- already open: Activate only points at it
	return ns.Secure.ClickMacro(se.secure, se), se
end
UI.ClickFor = ClickFor

local function Catcher()
	if catcher or InCombatLockdown() then return catcher end
	local ok, c = pcall(CreateFrame, "Button", "TerminalClickCatcher", UIParent,
		"SecureActionButtonTemplate, SecureHandlerStateTemplate")
	if not ok or not c then return nil end
	c:Hide()
	c:RegisterForClicks("LeftButtonUp")
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

--- The pointer is over row i: if its result opens a window, lay the catcher over the row.
function UI:PlaceCatcher(i)
	if InCombatLockdown() or self.closing or not frame or not frame:IsShown() then return end
	local row, e = rows[i], results[offset + i]
	local plain = e and ClickFor(e, false)
	local shifted = e and ClickFor(e, true)
	if not (plain or shifted) then self:HideCatcher() return end
	local left, bottom, w, h = row:GetLeft(), row:GetBottom(), row:GetWidth(), row:GetHeight()
	if not (type(left) == "number" and type(bottom) == "number" and type(w) == "number" and type(h) == "number") then
		self:HideCatcher()
		return
	end
	local c = Catcher()
	if not c then return end
	local rs, us = row:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local s = (type(rs) == "number" and type(us) == "number" and us > 0) and rs / us or 1
	c:ClearAllPoints()
	c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
	c:SetSize(w * s, h * s)
	c:SetFrameStrata(frame:GetFrameStrata())
	local level = frame:GetFrameLevel()
	c:SetFrameLevel((type(level) == "number" and level or 1) + 20)
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
	local idx = offset + c.row
	self:HideCatcher()
	if results[idx] ~= e then return end
	sel = idx
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
		ns:Bump(e.freqKey)
		ns:RecordHistory(edit:GetText())
		self:Hide()
		if se.after then C_Timer.After(0.1, function() RunAfter(se) end) end
	else
		ns:Trace("click: no window macro for " .. tostring(e.name) .. ", running its usual action")
		self:Activate(idx, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
	end
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
	ns:RecordHistory(edit:GetText())
	-- windows Blizzard owns are opened by a secure click, never from our own code
	local se = SecureView(e, opts.secondary)
	if se and self:TryArmSecure(se) then return end
	local args = self.args
	local isCmd = e.kind == "cmd"
	if not opts.keepOpen and not e.staysOpen then self:Hide() end
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
-- Motion
--
-- One OnUpdate drives everything that moves: the terminal fades and drifts in when it
-- opens and out when it closes, new results fade in row by row, the selection band glides
-- to the selected row, and the caret glides as you type and breathes when idle. With
-- ".set animations off" everything snaps instead.
----------------------------------------------------------------------


local Ease, Move = Theme.Ease, Theme.Move -- ease-out cubic; and the style's movement ease
local BLINK_STEP = 1 / 30 -- resting (only the cursor blinking): 30 updates a second are plenty

function UI:Animated() return Theme.Animation() ~= nil end

--- A row in its place, or `dx` pixels to the right of it (sliding in).
PlaceRow = function(r, dx)
	local y = r.baseY or 0
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", 6 + (dx or 0), y)
	r:SetPoint("TOPRIGHT", -6 + (dx or 0), y)
end

--- Where the terminal rests (its saved spot), and drifted `dy` pixels from it.
local function Anchor(dy)
	local pt = ns.db and ns.db.point
	frame:ClearAllPoints()
	if pt then
		frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4] + (dy or 0))
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -140 + (dy or 0))
	end
end

function UI:StartOpen(reopening)
	if not self:Animated() then
		frame:SetAlpha(1)
		Anchor(0)
		return
	end
	-- reopened while still fading out: carry on from where it is
	local A = Style()
	self.phase = "open"
	local a = frame:GetAlpha()
	a = type(a) == "number" and a or 0
	self.phaseAt = GetTime() - (reopening and A.open * a or 0)
	if not reopening then
		frame:SetAlpha(0)
		Anchor(-A.drift)
	end
	self.selY = nil
	Wake()
end

function UI:StartClose()
	self.closing = true
	local a = frame:GetAlpha()
	local now = GetTime()
	self.phase, self.phaseAt, self.closeFrom = "close", now, type(a) == "number" and a or 1
	-- cascade: the rows fold away bottom-up, sliding back out to the left
	local A = Style()
	if A.foldOut then
		local shown = {}
		for _, r in ipairs(rows) do if r:IsShown() and not r.leaving then shown[#shown + 1] = r end end
		local step = #shown > 1 and math.min(A.stagger, (A.close - A.rowFade * 0.5) / (#shown - 1)) or 0
		for i, r in ipairs(shown) do
			r.leaving, r.leaveAt, r.fadeAt, r.slideOut = true, now + (#shown - i) * math.max(0, step), nil, true
		end
	end
	Wake()
end

--- Back to rest: full alpha, in place, nothing moving.
function UI:MotionReset()
	self.phase, self.closing = nil, false
	if frame then
		frame:SetAlpha(1)
		Anchor(0)
		-- (only called once the terminal has gone) rows go too, so the next open brings them in
		-- with the style again; left up, a reopen only changed their text and every style
		-- looked like a plain fade after the first open
		for _, r in ipairs(rows) do
			r.fadeAt, r.leaving = nil, nil
			r:Hide()
			r:SetAlpha(1)
			if r.slide or r.slideOut then r.slide, r.slideOut = nil, nil; PlaceRow(r, 0) end
		end
	end
	motion:Hide()
end

--- The terminal is as tall as its results: header, one row per result shown, footer. It
--- grows and shrinks smoothly as you type (snaps on open and when animations are off).
function UI:FitHeight()
	if not frame then return end
	local n = math.max(0, math.min(ROWS, #results - offset))
	local h = HEADER_H + n * ROW_H + (self.footerH or FOOTER_H)
	self.heightTo = h
	local cur = frame:GetHeight()
	if self.snapNext or not self:Animated() or type(cur) ~= "number" or cur <= 0 then
		frame:SetHeight(h)
	elseif math.abs(cur - h) > 0.5 then
		Wake()
	end
end

--- The selection band: on the selected row, gliding there unless animations are off.
function UI:PlaceSelection()
	if not selBar then return end
	local i = sel - offset
	local e = results[sel]
	if not e or e.noActivate or i < 1 or i > ROWS then
		selBar:Hide(); selEdge:Hide()
		return
	end
	self.selTo = -HEADER_H - (i - 1) * ROW_H
	if not (self:Animated() and self.selY and selBar:IsShown()) then
		self.selY = self.selTo
		self:SetSelectionY(self.selY)
	else
		Wake()
	end
	selBar:Show(); selEdge:Show()
end

function UI:SetSelectionY(y)
	self.selPlaced = y
	selBar:ClearAllPoints()
	selBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, y)
	selBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, y)
	selBar:SetHeight(ROW_H)
	selEdge:ClearAllPoints()
	selEdge:SetPoint("TOPLEFT", selBar, "TOPLEFT", 0, 0)
	selEdge:SetPoint("BOTTOMLEFT", selBar, "BOTTOMLEFT", 0, 0)
end

motion:SetScript("OnUpdate", function(self, elapsed)
	if not frame then self:Hide() return end
	-- resting: only the cursor blinks, at BLINK_STEP; anything that moves wakes it (Wake)
	self.acc = (self.acc or 0) + (elapsed or 0)
	if UI.blinkOnly and self.acc < BLINK_STEP then return end
	elapsed, self.acc = self.acc, 0
	local now = GetTime()
	local busy, blinking = false, false
	local A = Style()
	local speed = A.speed or 1
	-- open / close
	if UI.phase == "open" then
		local x = (now - UI.phaseAt) / A.open
		frame:SetAlpha(Ease((now - UI.phaseAt) / (A.fade or A.open)))
		Anchor(-A.drift * (1 - Move(A, x)))
		if x >= 1 then UI.phase = nil else busy = true end
	elseif UI.phase == "close" then
		local k = Ease((now - UI.phaseAt) / A.close)
		frame:SetAlpha((UI.closeFrom or 1) * (1 - k))
		Anchor(-A.closeDrift * k)
		if k >= 1 then
			UI.phase, UI.closing = nil, false
			frame:Hide()
			UI:MotionReset() -- back at rest for the next open (OnHide does it too)
			return
		end
		busy = true
	end
	if not frame:IsShown() then self:Hide() return end
	local blend = math.min(1, (elapsed or 0) * 18 * speed)
	-- height: grow / shrink toward the results
	if UI.heightTo then
		local cur = frame:GetHeight()
		if type(cur) == "number" then
			local d = UI.heightTo - cur
			if math.abs(d) > 0.5 then
				frame:SetHeight(cur + d * math.min(1, (elapsed or 0) * 16 * speed))
				busy = true
			elseif d ~= 0 then
				frame:SetHeight(UI.heightTo)
			end
		end
	end
	-- selection band
	if UI.selTo and UI.selY and selBar:IsShown() then
		local d = UI.selTo - UI.selY
		if math.abs(d) > 0.5 then
			UI.selY = UI.selY + d * blend
			busy = true
		else
			UI.selY = UI.selTo
		end
		if UI.selY ~= UI.selPlaced then UI:SetSelectionY(UI.selY) end
	end
	-- caret: glide, then breathe while idle
	if caret:IsShown() and UI.caretTo then
		local d = UI.caretTo - (UI.caretX or UI.caretTo)
		if math.abs(d) > 0.3 then
			UI.caretX = (UI.caretX or UI.caretTo) + d * math.min(1, (elapsed or 0) * 28 * speed)
			busy = true
		else
			UI.caretX = UI.caretTo
		end
		-- a resting caret only blinks: nothing to re-anchor
		local moved = UI.caretX ~= UI.caretPlaced
		if moved then UI:PlaceCaret() end
		local st = CursorStyle()
		local a = 1
		if st.blink then
			local idle = now - (UI.typedAt or 0) - 0.45
			if idle > 0 then
				local wave = math.cos(idle * math.pi * 2 * (Theme.Get().blinkRate or 0.8))
				-- a line breathes; a box is mostly fully on or fully off, so the letter under it is
				-- never seen half-covered
				a = st.box and math.max(0, math.min(1, 0.5 + 1.4 * wave)) or (0.55 + 0.45 * wave)
			end
			blinking = true -- blinking never settles while the caret is up
		end
		a = math.floor(a * 50 + 0.5) / 50 -- (steps the eye can't tell apart aren't redrawn)
		if a ~= UI.caretAlpha then
			UI.caretAlpha = a
			caret:SetAlpha(a)
			caretChar:SetAlpha(a)
		end
		if moved then UI:PlaceTextSel() end
	end
	-- rows that appear fade in (staggered when set); rows that go fade out, then hide
	for _, r in ipairs(rows) do
		if r.leaving then
			local x = (now - (r.leaveAt or now)) / A.rowFade
			local k = Ease(x)
			r:SetAlpha(1 - k)
			if r.slideOut then PlaceRow(r, -A.slide * Ease(x)) end -- cascade: folding away
			if k >= 1 then
				r.leaving = nil
				r:Hide()
				r:SetAlpha(1)
				if r.slideOut then r.slideOut = nil; PlaceRow(r, 0) end
			else
				busy = true
			end
		elseif r.fadeAt and r:IsShown() then
			local x = (now - r.fadeAt) / A.rowFade
			local k = Ease(x)
			r:SetAlpha(k)
			if r.slide then PlaceRow(r, -r.slide * (1 - Move(A, x))) end -- cascade: in from the left
			if k >= 1 then
				r.fadeAt = nil
				if r.slide then r.slide = nil; PlaceRow(r, 0) end
			else
				busy = true
			end
		end
	end
	UI.blinkOnly = not busy
	if not busy and not blinking then self:Hide() end
end)

----------------------------------------------------------------------
-- Completion (Tab), shell style
--
-- ".th<Tab>" completes a command, ".theme dr<Tab>" its argument, "/rel<Tab>" a slash
-- command, "@equ<Tab>" a kind, and a plain search completes to the selected result's name.
-- Several candidates: Tab fills in what they share; nothing left to add, Tab moves down the
-- list. The suggestion shows faintly after the text; Right arrow at the end takes it too.
----------------------------------------------------------------------

local function StartsWith(s, prefix)
	return ns.Lower(s:sub(1, #prefix)) == ns.Lower(prefix)
end

local function CommonPrefix(list)
	local p = list[1]
	for i = 2, #list do
		local s, j = list[i], 0
		while j < #p and j < #s and p:sub(j + 1, j + 1):lower() == s:sub(j + 1, j + 1):lower() do j = j + 1 end
		p = p:sub(1, j)
	end
	return p
end

--- Complete `word` from `cands`: the text that should replace it, and whether that's final.
local function CompleteWord(word, cands)
	local hits, seen = {}, {}
	for _, c in ipairs(cands) do
		if type(c) == "table" then c = c[1] end -- { value, detail }
		if type(c) == "string" and StartsWith(c, word) and not seen[c:lower()] then
			seen[c:lower()] = true
			hits[#hits + 1] = c
		end
	end
	if #hits == 0 then return nil end
	if #hits == 1 then return hits[1], true end
	table.sort(hits, function(a, b) return #a < #b end)
	local cp = CommonPrefix(hits)
	if #cp <= #word then cp = word end -- nothing shared beyond what's typed
	return cp, false
end

local function CommandByWord(word) return ns:FindCommand(word) end

local function ComputeCompletion(self, text)
	if text == "" or (self.cursor or #text) < #text then return nil end
	local first = text:sub(1, 1)
	if first == "." then
		local word, rest = text:sub(2):match("^(%S*)(.*)$")
		if rest == "" then
			local new, final = CompleteWord(word, ns.commandOrder)
			if new then return "." .. new .. (final and " " or "") end
			return nil
		end
		local c = CommandByWord(word)
		if not (c and c.complete) then return nil end
		local args = rest:gsub("^%s+", "")
		local argWord = args:match("(%S*)$") or ""
		local ok, cands = pcall(c.complete, args)
		if not ok or type(cands) ~= "table" then return nil end
		local new, final = CompleteWord(argWord, cands)
		if not new then return nil end
		return text:sub(1, #text - #argWord) .. new .. (final and " " or "")
	elseif first == "/" then
		if text:find("%s") then return nil end
		local cands = {}
		local p = ns.providers.slash
		if p then for _, e in ipairs(ns:GetEntries(p)) do cands[#cands + 1] = e.name end end
		local new, final = CompleteWord(text, cands)
		if new then return new .. (final and " " or "") end
		return nil
	end
	local last = text:match("(%S*)$") or ""
	if last:sub(1, 1) == "@" then
		local cands = {}
		for _, id in ipairs(ns.providerOrder) do
			local p = ns.providers[id]
			cands[#cands + 1] = "@" .. id
			for _, a in ipairs(p.aliases or {}) do cands[#cands + 1] = "@" .. a end
		end
		local new, final = CompleteWord(last, cands)
		if not new then return nil end
		return text:sub(1, #text - #last) .. new .. (final and " " or "")
	end
	-- the "Search <list> for this" row: Tab adds its @kind
	local e = results[sel]
	if e and e.completion then return e.completion end
	-- plain search: the selected result's name, when the typed words start it
	if not e or e.raw or e.noActivate or type(e.name) ~= "string" or e.kind == "calc" then return nil end
	local kinds = text:match("^(@%S+%s+)") or ""
	while true do -- every leading @kind
		local more = text:sub(#kinds + 1):match("^(@%S+%s+)")
		if not more then break end
		kinds = kinds .. more
	end
	local query = text:sub(#kinds + 1)
	if query == "" or #e.name <= #query or not StartsWith(e.name, query) then return nil end
	return kinds .. e.name
end

--- The query with the completion applied, or nil when there's nothing to complete.
--- Asked several times per keystroke (caret, ghost text, render): worked out once per state.
local memo = {}
function UI:Completion()
	if not edit or self:SelRange() then return nil end
	local text = edit:GetText()
	if memo.text == text and memo.cursor == self.cursor and memo.results == results and memo.sel == sel
		and memo.gen == ns.entriesGen then
		return memo.value
	end
	local value = ComputeCompletion(self, text)
	memo.text, memo.cursor, memo.results, memo.sel, memo.gen, memo.value = text, self.cursor, results, sel, ns.entriesGen, value
	return value
end

--- What the suggestion adds to the typed text (for the faint preview), or nil.
function UI:Suggestion()
	local text = edit and edit:GetText() or ""
	local new = self:Completion()
	if not new or #new <= #text or not StartsWith(new, text) then return nil end
	local add = new:sub(#text + 1):gsub("%s+$", "")
	return add ~= "" and add or nil
end

--- Apply the completion. False when there was nothing to complete.
function UI:AcceptCompletion()
	local text = edit and edit:GetText() or ""
	local new = self:Completion()
	if not new or new == text then return false end
	self:SetQuery(new, #new)
	return true
end

function UI:UpdateGhost()
	if not ghost then return end
	local add = self:IsShown() and self:Suggestion() or nil
	if not add then ghost:Hide() return end
	local text = edit:GetText()
	measure:SetText((text:gsub("|", "||")))
	local w = measure:GetStringWidth() or 0
	local room = (edit:GetWidth() or 400) - w - 4
	if room < 20 then ghost:Hide() return end
	ghost:SetText((add:gsub("|", "||")))
	ghost:ClearAllPoints()
	ghost:SetPoint("LEFT", edit, "LEFT", w, 0)
	ghost:SetWidth(room)
	ghost:Show()
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
		UI:MotionReset()
		if tip then tip:Hide() end
		UI:Disarm()
		UI.keys = false
		StopRepeat()
		self:EnableKeyboard(false)
		if caret then caret:Hide(); caretChar:Hide() end
		if hit then hit:Hide() end
		UI.dragging = false
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
		if not UI._histSet then UI.histIdx = nil end
		if not UI.keys then
			local cp = self:GetCursorPosition()
			if type(cp) == "number" then UI.cursor = cp end
		end
		UI.cursor = math.min(UI.cursor or #t, #t)
		-- the game can report a change without one (the box resized, say): searching again
		-- then restarted a search spread over frames forever, and reset the scroll each time
		if t ~= UI.searchedText then UI:Refresh() end
		UI:UpdateCaret()
	end)
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
	edit:SetScript("OnTabPressed", function()
		if IsShiftKeyDown() or not UI:AcceptCompletion() then UI:Move(IsShiftKeyDown() and -1 or 1) end
	end)
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

	-- the cursor lives in a frame above the text box, so a box cursor can cover the letter under it
	-- (which is then drawn again on top, in a colour that reads on the box)
	caretFrame = CreateFrame("Frame", nil, frame)
	caretFrame:SetAllPoints(edit)
	local lvl = edit:GetFrameLevel()
	caretFrame:SetFrameLevel((type(lvl) == "number" and lvl or 1) + 2)
	UI.caretFrame = caretFrame
	-- clicks and drags on the prompt move Terminal's own cursor (the real text box stays for Ctrl+C/V)
	hit = CreateFrame("Frame", nil, frame)
	hit:SetAllPoints(edit)
	hit:SetFrameLevel((type(lvl) == "number" and lvl or 1) + 1)
	hit:EnableMouse(true)
	hit:Hide()
	hit:SetScript("OnMouseDown", function(_, button) if button == nil or button == "LeftButton" then UI:PressPrompt() end end)
	hit:SetScript("OnMouseUp", function() UI:ReleasePrompt() end)
	UI.hit = hit

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

	-- the selected row: a soft band with a bright edge that glides between rows
	selBar = frame:CreateTexture(nil, "BORDER", nil, 2)
	selEdge = frame:CreateTexture(nil, "ARTWORK")
	selEdge:SetWidth(2)
	selBar:Hide(); selEdge:Hide()
	UI.selBar = selBar

	divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	-- the prompt's own background, behind the query box (Theme promptBg)
	promptBg = frame:CreateTexture(nil, "BORDER")
	UI.promptBg = promptBg

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
		b:SetScript("OnClick", function()
			if UI.closing then return end -- fading out: already done
			sel = offset + i
			UI:Activate(sel, { keepOpen = IsControlKeyDown(), secondary = IsShiftKeyDown() })
		end)
		b:SetScript("OnEnter", function()
			if UI.closing then return end
			if results[offset + i] and sel ~= offset + i then
				if UI.armedEntry then UI:Disarm() end
				sel = offset + i
				UI:Render()
			end
			UI:PlaceCatcher(i)
		end)
		b:Hide()
		rows[i] = b
	end

	-- footer: a faint rule, the result count on the left, key hints on the right, both
	-- centred on one line
	footLine = frame:CreateTexture(nil, "ARTWORK")
	footLine:SetHeight(1)
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
	frame:SetWidth(t.width)
	self.snapNext = true -- a new layout: no growing into it
	self:FitHeight()
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
	UI.editLeft, UI.editMid = 14 + pw + 8, mid
	UI:PlaceEdit()
	edit:SetHeight(t.fontSize + 14)
	busy:ClearAllPoints()
	busy:SetPoint("RIGHT", frame, "TOPRIGHT", -12, mid)
	for _, d in ipairs(busy.dots) do d:SetColorTexture(Theme.RGB(t.accent)) end
	local tr, tg, tb = Theme.RGB(t.text)
	edit:SetTextColor(tr, tg, tb)

	local ar, ag, ab = Theme.RGB(t.accent)
	caret:SetColorTexture(ar, ag, ab, 1)
	caret:SetHeight(t.fontSize + 5)
	UI.onAccent = Theme.OnColor(t.accent, t.bg)
	if UI.keys then UI:UpdateCaret() end
	selText:SetColorTexture(ar, ag, ab, 0.38)
	selBar:SetColorTexture(ar, ag, ab, 0.16)
	selEdge:SetColorTexture(ar, ag, ab, 0.9)
	local gr, gg, gb = Theme.RGB(t.dim)
	ghost:SetTextColor(gr, gg, gb, 0.75)
	self.selY = nil -- re-place the selection band for the new layout

	local dr, dg, db = Theme.RGB(t.dim)
	for i = 1, MAX_ROWS do
		local row = rows[i]
		local y = -HEADER_H - (i - 1) * ROW_H
		row:SetHeight(ROW_H)
		row.baseY, row.slide = y, nil
		PlaceRow(row, 0)
		row.icon:SetSize(ROW_H - 6, ROW_H - 6)
		row.detail:SetWidth(math.floor(t.width * 0.3))
		row.label:SetTextColor(tr, tg, tb)
		row.detail:SetTextColor(dr, dg, db)
		if i > ROWS then row:Hide() end
	end
	status:SetTextColor(dr, dg, db)
	hints:SetTextColor(dr, dg, db)
	local lr, lg, lb = Theme.RGB(t.border)
	footLine:SetColorTexture(lr, lg, lb, 0.35)
	self.hintsRoom = nil -- fonts and colours may have changed: measure the hints again
	self:FitHints()

	Fuzzy.matchColor = "|cff" .. t.match
	offset = math.max(0, math.min(offset, #results - ROWS))
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
	if not frame or not frame:IsShown() or self.closing then return end
	self:Disarm()
	self:HideCatcher()
	if tip then tip:Hide() end
	edit:ClearFocus()
	self.histIdx = nil
	-- let go of the keyboard at once, so the next key already reaches the game
	self.keys = false
	StopRepeat()
	frame:EnableKeyboard(false)
	caret:Hide()
	caretChar:Hide()
	if hit then hit:Hide() end
	if busy and busy:IsShown() then busy:Hide() end
	UI.dragging = false
	ghost:Hide()
	if self:Animated() then
		self:StartClose()
	else
		frame:Hide()
	end
end

function UI:Open(text)
	Build()
	self:Disarm()
	self.histIdx = nil
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if p.refreshOnOpen then p._dirty = true end
	end
	ns.Highlight:Clear()
	local reopening = self.closing
	self.closing = false
	frame:Show()
	self:StartOpen(reopening)
	self.cursor = #(text or "")
	self.snapNext = true -- opens at the right size; it grows and shrinks from there
	self.opening = true -- (the rows still come in with the style)
	-- SetText searches (OnTextChanged) only if the text changed; a second search in the same
	-- frame would be queued for the next one
	if edit:GetText() ~= (text or "") then edit:SetText(text or "") else self:Refresh() end
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
	if self:IsShown() then self:Hide() else self:Open() end
end

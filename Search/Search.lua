local ns = select(2, ...)

-- The search engine: scoring a row against the typed words, sorting and trimming, the searches themselves (SearchText:
-- Advanced and Simple mode, the Simple overview of categories, fuzzy finding, the "Search Questie for this" rows, close
-- spellings), command and argument rows, the empty terminal's recent picks. Moved out of UI.lua (0.43.15) as it was:
-- the window (UI.lua) shows what these give and runs them a slice at a time (UI:RunSearch).

local UI = ns.UI
local Fuzzy = ns.Fuzzy
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end
local EASY_NONE = "Nothing has that. Check the spelling, or try other words."
local EASY_NO_NPCS = "\"nearest\" needs Questie (or QuestieDB): it knows where NPCs stand."
local EASY_NOWHERE = "Can't tell where you are here (in a dungeon?)."
local EASY_NONE_NEAR = "None of those on this continent that Questie knows of."
local SLICE_CHECK = UI.SLICE_CHECK -- rows scored between looks at the clock
local TEXT_SCORE = 1.0 -- score given to a match found in an entry's secondary text
local MAX_RESULTS = 100 -- rows a search keeps
local QUESTION_MARK = 134400 -- (an icon for rows without one)

----------------------------------------------------------------------
-- Scoring
----------------------------------------------------------------------

-- rows listed without a search (the empty terminal, a command's rows, a quest brought along by
-- its item) have no matched letters: they share this one table instead of each getting its own
local NO_POS = {}
UI.NO_POS = NO_POS

--- `kind`: the row's provider id when the caller knows it, so a compact row whose kind was never
--- picked isn't read through its metatable just to find that out.
local function FreqBonus(e, kind)
	local freq = ns.db and ns.db.freq
	if not freq then return 0 end
	local k = rawget(e, "freqKey")
	local f
	if k then
		f = freq[k]
	else
		-- a compact row (its freqKey would be built on every read): looked up by its own key in what was picked
		-- of its kind (Core.lua FreqKind; the same "kind:key" its metatable builds)
		local picked = ns:FreqKind(kind or e.kind)
		if not picked then return 0 end
		local key = rawget(e, "key")
		if key == nil then key = e.name end
		f = key ~= nil and picked[key] or nil
	end
	return f and math.min(f, 20) * 0.05 or 0
end

UI._FreqBonus = FreqBonus -- (tests)

local find = string.find
-- A shorthand's full name in a row's name or text beats any match of its letters ("rfk": Razorfen Kraul's loot
-- before "Rough Flask of Kings", whose initials are r f k): above any fuzzy score a short word can get.
local SHORT_PRIO = 3.5
--- Is one of the shorthand's full names in the name (lowercase) or the text? "name", "text" or nil, and which.
local function ShortHit(xs, ln, ltext)
	for k = 1, #xs do
		if find(ln, xs[k], 1, true) then return "name", k end
	end
	if ltext then
		for k = 1, #xs do
			if find(ltext, xs[k], 1, true) then return "text", k end
		end
	end
end

-- words that could be initials ("scb", "ubrs": 2-6 letters), per word typed (a few hundred kept)
local iniShape, iniShapeN = {}, 0
local function IniShape(tk)
	local s = iniShape[tk]
	if s == nil then
		s = #tk >= 2 and #tk <= 6 and not find(tk, "[^a-z]")
		if iniShapeN >= 400 then iniShape, iniShapeN = {}, 0 end
		iniShape[tk], iniShapeN = s, iniShapeN + 1
	end
	return s
end

local byte = string.byte

--- Whether the name could have initials starting with byte c1: its first letter is c1, or it
--- starts with "the ", "a ", "an ", "and " or "of " (left out of the second set of initials).
local function StartsRight(name, lname, c1)
	local s = lname or name
	local c = byte(s, 1)
	if c and c >= 65 and c <= 90 then c = c + 32 end
	if c == c1 then return true end
	if c ~= 116 and c ~= 97 and c ~= 111 then return false end
	local c2, c3, c4 = byte(s, 2, 4)
	if c2 and c2 >= 65 and c2 <= 90 then c2 = c2 + 32 end
	if c3 and c3 >= 65 and c3 <= 90 then c3 = c3 + 32 end
	if c == 116 then return c2 == 104 and c3 == 101 and c4 == 32 end -- the
	if c == 111 then return c2 == 102 and c3 == 32 end -- of
	return c2 == 32 or (c2 == 110 and (c3 == 32 or (c3 == 100 and c4 == 32))) -- a, an, and
end

--- What the name gives a word that isn't in it as it is (best: its fuzzy score, or nil): its
--- initials ("ini"). (A shorthand's full name is looked at before: ShortHit.) Allocation-free.
local function NameExtra(tk, best, name, lname)
	local how = best and "name"
	-- initials are letters of the name in order: only a scattered match can be one, and the
	-- first word (or a leading of/the/a/an/and) must start with the first letter
	if best and IniShape(tk) then
		if StartsRight(name, lname, byte(tk, 1)) then
			local ini = Fuzzy.initials(tk, name)
			if ini and ini > best then best, how = ini, "ini" end
		end
	end
	return best, how
end

--- One typed word on a row: its score (nil: no match), how the name matched ("name": the fuzzy
--- match, "ini": the name's initials, "short": a shorthand's full name; nil: only the text), and
--- which of the shorthand's names. The initials and shorthand are looked at only when the word
--- isn't in the name as it is, so ordinary word searches rank as they always did.
--- xs: the shorthand's full names when the word is one. Allocation-free.
local function TokenScore(tk, xs, name, lname, ltext)
	if xs then
		local where, k = ShortHit(xs, lname or ns.Lower(name), ltext)
		if where == "name" then return SHORT_PRIO, "short", k end
		if where then return SHORT_PRIO, nil, nil end
	end
	local best, sub = Fuzzy.score(tk, name, lname)
	if xs and not sub then return nil end
	local how, at = best and "name", nil
	if not sub then best, how = NameExtra(tk, best, name, lname) end
	if ltext and (not best or best < TEXT_SCORE) and find(ltext, tk, 1, true) then return TEXT_SCORE, how, at end
	return best, how, at
end

local function RowText(e)
	local ltext = rawget(e, "_ltext")
	if not ltext then
		local text = rawget(e, "text")
		if text then ltext = ns.Lower(text); e._ltext = ltext end
	end
	return ltext
end

--- Per word typed: its first letter (a byte) when it could be initials, else false. Kept on the
--- tokens table (once per search).
local function IniFirst(tokens)
	local t = {}
	for i = 1, #tokens do t[i] = IniShape(tokens[i]) and byte(tokens[i], 1) or false end
	tokens.ini = t
	return t
end

--- The entry's score for these tokens, or nil. Allocation-free: matched letters (for the
--- highlight) are worked out later, only for the rows on screen (see Positions).
--- tokens.short[i]: the full names of a shorthand typed as word i (SearchText). This is
--- TokenScore written out (no calls but the matcher's): it runs for every row on every keystroke.
local function ScoreEntry(e, tokens)
	local total, nameHit = 0, false
	-- rawget: compact rows (tens of thousands of NPCs) would go through __index twice per row
	local ltext = rawget(e, "_ltext")
	if not ltext then
		local text = rawget(e, "text")
		if text then ltext = ns.Lower(text); e._ltext = ltext end
	end
	local name, lname, short = e.name, e._lname, tokens.short
	local ini = tokens.ini or IniFirst(tokens)
	for i = 1, #tokens do
		local tk = tokens[i]
		local xs = short and short[i]
		local best, sub
		local where = xs and ShortHit(xs, lname or ns.Lower(name), ltext)
		if where then
			best, sub = SHORT_PRIO, true
			if where == "name" then nameHit = true end
		else
			best, sub = Fuzzy.score(tk, name, lname)
			-- a shorthand is a place, not letters: elsewhere only the word itself counts ("sw" in Swamp), never letters
			-- scattered through a name ("rfk helm": no Rough Flask of Kings among Razorfen Kraul's helms)
			if xs and not sub then return nil end
			if best then nameHit = true end
		end
		if not sub then
			local c1 = ini[i]
			if best and c1 then -- (see NameExtra: initials only for a scattered match, first letter first)
				if StartsRight(name, lname, c1) then
					local s = Fuzzy.initials(tk, name)
					if s and s > best then best = s end
				end
			end
		end
		if ltext and (not best or best < TEXT_SCORE) and find(ltext, tk, 1, true) then best = TEXT_SCORE end
		if not best then return nil end
		total = total + best
	end
	-- (not written on compact rows: a field more grew each to the next table size, ~320 B a row over thousands; their
	-- matched letters are worked out on screen anyway, Positions)
	e._pos = nil
	if not rawget(e, "_compact") then e._nameHit = nameHit end
	return total
end

-- close spellings: how far a word may be from a name's word (4-7 letters: one edit, 8+: two)
local function NearLimit(n)
	if n < 4 then return nil end
	return n >= 8 and 2 or 1
end

--- The name's word closest to tk within `limit` edits: the distance and the word's first and
--- last byte, or nil. Words are runs of letters, digits and apostrophes.
local function NearWord(tk, lname, limit)
	local n, j, bestD, bf, bt = #tk, 1, nil, nil, nil
	while true do
		local s, f = find(lname, "[%w\128-\255']+", j)
		if not s then break end
		local wl = f - s + 1
		-- one edit leaves one of these as it was: the first letters, the second ones, or a first
		-- letter moved by one (an extra or a missing letter at the front, two swapped)
		local maybe = wl - n <= limit and n - wl <= limit
		if maybe and limit == 1 then
			local t1, t2, w1, w2 = byte(tk, 1), byte(tk, 2), byte(lname, s), byte(lname, s + 1)
			maybe = t1 == w1 or t2 == w2 or t2 == w1 or t1 == w2
		end
		if maybe then
			local d = Fuzzy.distance(tk, lname, s, f, bestD and bestD - 1 or limit)
			if d then
				bestD, bf, bt = d, s, f
				if d == 0 then break end
			end
		end
		j = f + 1
	end
	return bestD, bf, bt
end

--- The matched letters of the entry's name for these tokens (a set of byte positions).
local function Positions(e, tokens)
	local set = {}
	if not tokens or e._nameHit == false then return set end
	local name, lname, short = e.name, e._lname, tokens.short
	if UI.fzf then -- (pure fuzzy finding: the letters each word matched, nothing else)
		for _, tk in ipairs(tokens) do
			local _, pos = Fuzzy.match(tk, name, lname)
			for _, k in ipairs(pos or NO_POS) do set[k] = true end
		end
		return set
	end
	for i, tk in ipairs(tokens) do
		local xs = short and short[i]
		local _, how, at = TokenScore(tk, xs, name, lname, nil)
		if how == "name" then
			local _, pos = Fuzzy.match(tk, name, lname)
			if pos then
				for _, k in ipairs(pos) do set[k] = true end
			end
		elseif how == "ini" then
			local pos = {}
			Fuzzy.initials(tk, name, pos)
			for _, k in ipairs(pos) do set[k] = true end
		elseif how == "short" then
			local s, f = find(lname or ns.Lower(name), xs[at], 1, true)
			for k = s or 1, f or 0 do set[k] = true end
		elseif not how and UI.closeSpellings and NearLimit(#tk) then -- a close spelling: the word it's close to
			local _, s, f = NearWord(tk, lname or ns.Lower(name), NearLimit(#tk))
			for k = s or 1, f or 0 do set[k] = true end
		end
	end
	return set
end

-- (a row pinned on top has no score: Simple mode's "Advanced syntax" line, which a sliced search's first frame
-- sorts along with the rows it shows; it stays first)
local PINNED = 1e12
local function Better(a, b)
	local sa, sb = a._score or PINNED, b._score or PINNED
	if sa ~= sb then return sa > sb end
	local an, bn = a._lname or "", b._lname or ""
	if an ~= bn then return an < bn end
	return tostring(a.key) < tostring(b.key)
end

UI._Better = Better -- (tests)

--- The best MAX_RESULTS of the list, in order (a new list: the one given is left as it is). With thousands of matches,
--- a small heap keeps only the best so far instead of sorting them all. overBudget (a search spread over frames): the
--- pass over thousands of matches is spread too, the heap so far standing for it meanwhile.
local function SortAndTrim(list, limit, overBudget)
	local n, max = #list, limit or MAX_RESULTS
	if n > max * 2 then
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
		local worst -- (the kept worst's score: most rows lose to it on the score alone, with no call)
		for k = 1, n do
			local e = list[k]
			if overBudget and k % SLICE_CHECK == 0 and overBudget() then coroutine.yield(heap) end
			if size < max then
				size = size + 1
				heap[size] = e
				up(size)
				if size == max then worst = heap[1]._score or PINNED end
			else
				local s = e._score or PINNED
				if s > worst or (s == worst and Better(e, heap[1])) then
					heap[1] = e
					down(1)
					worst = heap[1]._score or PINNED
				end
			end
		end
		list = heap
	else
		local c = {}
		for k = 1, n do c[k] = list[k] end
		list = c
	end
	table.sort(list, Better)
	for i = #list, max + 1, -1 do list[i] = nil end
	return list
end

local function PseudoEntries(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = { name = line, raw = true, icon = false, noActivate = true, kindLabel = "", detail = "" }
	end
	return out
end

-- The search's helpers (a table, not locals: the file is near Lua 5.1's limit of 200 locals)
local Scan = {}

--- A copy of a list (the matches kept for the next keystroke, the early results shown while the search goes on).
function Scan.Copy(t)
	local c = {}
	for i = 1, #t do c[i] = t[i] end
	return c
end

--- For a search run by UI:RunSearch (in a coroutine): a function that says when this frame's share is used up.
--- Called directly (tests, other code), the search never pauses.
function Scan.Budget(self)
	local slicing = self.sliceUntil ~= nil and coroutine.running() ~= nil
	return function() return slicing and debugprofilestop() > self.sliceUntil end
end

--- Can the last keystroke's matches stand for these words? One more letter on the last word, or one more word, only
--- narrows (every row that has the new words had the old ones); never when the last word turned into shorthand
--- ("br" -> "brd": the shorthand matches rows the shorter word didn't), nor the other way ("sw" -> "swo": the
--- shorthand matched only its full name and the word itself).
function Scan.Narrows(last, tokens)
	local n, ln = #tokens, #last
	if n ~= ln and n ~= ln + 1 then return false end
	for i = 1, ln do
		local a, b = last[i], tokens[i]
		if (i < n and a ~= b) or (i == n and b:sub(1, #a) ~= a)
			or (i == n and a ~= b and tokens.short and tokens.short[i])
			or (a ~= b and last.short and last.short[i]) then return false end
	end
	return true
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
				e._score, e._pos = 2000, NO_POS
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
			e._score, e._pos = 0, NO_POS
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

--- A command typed by its exact name or alias (".fzf", ".rl") comes first, whatever else its letters match.
function UI:ExactCommandFirst(list, text)
	local word = text:match("^%s*(%S+)")
	local c = word and ns:FindCommand(word)
	if not c then return list end
	for i, e in ipairs(list) do
		if e.cmd == c then
			if i > 1 then table.remove(list, i); table.insert(list, 1, e) end
			break
		end
	end
	return list
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
					e._score, e._pos = 10000 - r, NO_POS
					out[#out + 1] = e
				elseif f and f > 0 and not p.explicit and not p.lazy then
					e._score, e._pos = f, NO_POS
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
			"End a search with  >> party  (or guild, raid, say, whisper Name) to send the result to chat",
			"Change the look with  .theme  and  .set , or  .options",
		})
	end
	return SortAndTrim(out)
end

UI.DATA_RETRY, UI.DATA_RETRIES = 1.1, 8 -- (seconds between, and how many: about 9 s of the game loading item data)

--- A filter met item or spell data the game was still loading ("stamina food" right after login: the food's text
--- isn't in yet, so it failed stamina): the same search runs again in a moment, from scratch (the narrowing state
--- left those rows out), until the data is in or a few tries have gone by. Typing anything ends it.
function UI:RetryWhenLoaded(text)
	local F = ns.Filters
	if not (F and F.loading) then
		if self.dataRetry and self.dataRetry.text ~= text then self.dataRetry = nil end
		return
	end
	local r = self.dataRetry
	-- (the prompt as typed: the searched text may be trimmed or have lost a ">> party")
	if not r or r.text ~= text then r = { text = text, tries = 0, typed = UI.edit:GetText() }; self.dataRetry = r end
	if r.waiting or r.tries >= UI.DATA_RETRIES then return end
	r.waiting = true
	C_Timer.After(UI.DATA_RETRY, function()
		r.waiting = false
		if self.dataRetry ~= r or not self:IsShown() or UI.edit:GetText() ~= r.typed then return end
		r.tries = r.tries + 1
		ns:Trace(("search: item data was still loading, searching %q again (%d)"):format(text, r.tries))
		self.lastScan, self.lastOverview = nil, nil
		self.refreshedAt, self.searchedText = nil, nil
		self:Refresh()
	end)
end

function UI:Search(text)
	if ns.Filters then ns.Filters.loading = nil end
	-- arithmetic: the answer is the top result (see Calc.lua)
	local calc = not self.fzf and ns.Calc and ns.Calc.Entry(text)
	local res = self:SearchText(text)
	if calc then table.insert(res, 1, calc) end
	self:RetryWhenLoaded(text)
	return res
end

--- A quest item among the matches brings its quest along, right below it ("Intact Limbs" -> its
--- quest); an item with no sure quest brings the likeliest ones, marked "maybe". Adds to `out`.
local function LinkQuests(out)
	local quests = ns.providers.quests
	if not quests then return end
	local linked, from, guessed = {}, {}, {}
	for _, e in ipairs(out) do
		if e.questID and e.kind ~= "quests" then
			local best = linked[e.questID]
			if not best or e._score > best then linked[e.questID] = e._score; from[e.questID] = e end
		end
	end
	for _, e in ipairs(out) do
		if e.guessIDs and e.kind ~= "quests" and not e.questID then
			for _, id in ipairs(e.guessIDs) do
				if not linked[id] then
					linked[id] = e._score; from[id] = e; guessed[id] = true
				end
			end
		end
	end
	if not next(linked) then return end
	local present = {} -- quests already among the results
	for _, e in ipairs(out) do if e.kind == "quests" then present[e] = true end end
	for _, q in ipairs(ns:GetEntries(quests)) do
		local s = linked[q.questID]
		if s then
			if not present[q] then
				q._pos = NO_POS
				out[#out + 1] = q
			end
			-- directly under its item when the item itself was searched for by name; an item
			-- that only matched through its quest's text stays below the quest
			local it = from[q.questID]
			if not present[q] or it._nameHit then
				q._score = s - 0.001
				UI.linked[q] = it
				UI.linkedGuess[q] = guessed[q.questID] or nil
			end
		end
	end
end

--- Simple mode: an action word ("use hearthstone", "nearest innkeeper"; Easy.ACTIONS) first, or a nearest-type one
--- last ("mining trainer nearby"), taken out of the tokens. The action, or nil.
function Scan.TakeAction(tokens, filters)
	local a = ns.Easy.Action(tokens[1])
	if a and (#tokens > 1 or filters) then
		table.remove(tokens, 1)
		return a
	end
	if #tokens > 1 then
		-- "nearest"/"nearby"/"closest" said last: "mining trainer nearby"
		local b = ns.Easy.Action(tokens[#tokens])
		if b and b.nearest then
			table.remove(tokens)
			return b
		end
	end
end

--- Simple mode: the tokens without a sentence's little words (Easy.STOP), unless nothing else would be left (and no
--- everyday word was typed).
function Scan.DropStop(tokens, softs)
	local kept = {}
	for k = 1, #tokens do if not ns.Easy.STOP[tokens[k]] then kept[#kept + 1] = tokens[k] end end
	if #kept > 0 or softs then return kept end
	return tokens
end

--- tokens.short[i]: the full names of word i when it's a shorthand ("brd", "strat", "sw").
function Scan.FillShorthand(tokens)
	local SH = ns.Shorthand
	if not SH then return end
	for i = 1, #tokens do
		local xs = SH[tokens[i]]
		if xs then
			tokens.short = tokens.short or {}
			tokens.short[i] = xs
		end
	end
end

--- Simple mode's "nearest ...": a game object asked for ("nearest mailbox": QuestieDB's objects) gives its rows at
--- once; else where you are, for the NPCs that match. Returns the rows to list now (rows, or a line saying why
--- not), or nil, your position and the faction filter to add ("nearest repair": someone who'll serve you, so only
--- NPCs friendly to your faction; "nearest hogger": a name, anyone).
function Scan.NearestStart(tokens, filters, softWords)
	local I = ns.Integrations
	local okind = I and I.ObjectKind and I.ObjectKind(tokens)
	if okind then
		local spot = I.Here()
		if not spot then return PseudoEntries({ EASY_NOWHERE }) end
		local rows = I.NearestObjectRows(okind, spot, filters and function(e) return ns.Filters.Pass(e, filters) end)
		if rows and #rows > 0 then return rows end
		if rows then return PseudoEntries({ EASY_NONE }) end
	end
	if not ns.providers.npc then return PseudoEntries({ EASY_NO_NPCS }) end
	local here = ns.Integrations and ns.Integrations.Here()
	if not here then return PseudoEntries({ EASY_NOWHERE }) end
	local role = false
	for _, w in ipairs(softWords or {}) do if ns.Easy.ROLE_WORDS[w] then role = true break end end
	return nil, here, role and ns.Filters and ns.Filters.Parse("faction:friendly")
end

--- The matched rows that have a distance (Questie's NPCs, rows with a place of their own: @mailbox), each as a view
--- saying how far ("120 yd", a spot row keeping its zone as the arrow's live text writes it: "120 yd  The Barrens")
--- and scored closest first; sort:nearest keeps every other row too, after them. Pauses with the search.
function Scan.NearestViews(out, here, sortNear, overBudget)
	local I, kept = ns.Integrations, {}
	for i = 1, #out do
		local e = out[i]
		local d = I.RowDistance(e, here)
		if d then
			local zone = rawget(e, "wcont") and e.zone
			kept[#kept + 1] = setmetatable({ detail = ("%.0f yd"):format(d) .. (zone and ("  " .. zone) or ""), _score = 1e6 - d, _dist = d }, { __index = e })
		elseif sortNear then
			kept[#kept + 1] = e
		end
		if i % 32 == 0 and overBudget() then coroutine.yield(kept) end
	end
	return kept
end

function UI:SearchText(text)
	self.closeSpellings = nil -- (set when only close spellings matched: the footer says so)
	self.softRelaxed = nil -- (easy mode: nothing passed every everyday word, the closest shown: the footer says so)
	local softs, hard, softWords -- (the everyday words' filters, the typed key:value ones, the everyday words)
	self.linkedGuess = {}
	self.linked = {} -- quest entry -> the item that brought it along (drawn with an arrow)
	self.answerNote, self.pipeTrail = nil, nil -- (a question's note, a chain's path: only for their own searches)
	if self.fzf then
		self.noPosition, self.action, self.place = nil, nil, nil
		return self:FuzzySearch(text)
	end
	-- a chain ("thorium belt > mats", "mats for thorium belt"): Pipes.lua; the footer shows its trail
	local chain = ns.Pipes and ns.Pipes.Canonical(text)
	if chain then
		self.noPosition, self.action, self.place = nil, nil, nil
		if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
		self.posTokens = {}
		local rows, trail = ns.Pipes.Search(chain)
		self.pipeTrail = trail
		return rows
	end
	-- a question in plain words ("where should i level", "what dungeon should i do"): its answer (Zones.lua)
	local cbAsk = ns.CombatLog and ns.CombatLog.Question(text)
	if cbAsk then
		self.noPosition, self.action, self.place = nil, nil, nil
		if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
		self.posTokens = {}
		local rows, note = ns.CombatLog.Answer(cbAsk)
		self.answerNote = note
		return rows
	end
	local ask, said = ns.Zones and ns.Zones.Question(text)
	if ask then
		self.noPosition, self.action, self.place = nil, nil, nil
		if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
		self.posTokens = {}
		local rows, note = ns.Zones.Answer(ask, said)
		self.answerNote = note
		return rows
	end
	local kinds, tokens, filters, fsig = nil, {}, nil, {}
	local simple = EasyOn()
	-- Simple mode doesn't take Advanced syntax (@kind, key:value, >>): a row on top says where it lives (Refresh
	-- already took a ">>" off); the plain words are still searched
	local blocked = simple and self.blockedSyntax or nil
	local function Finish(res)
		-- a list that asks the server first (@who): its own row on top
		if kinds then
			for k in pairs(kinds) do
				local p = ns.providers[k]
				local row = p and p.leadRow and p.leadRow(p, text)
				if row then table.insert(res, 1, row) end
			end
		end
		if not blocked then return res end
		-- only a ">>" typed: where sending lives in Simple mode (the right-click menu); else the Advanced row
		local out = { blocked == "send" and ns.Easy.SEND_ROW or ns.Easy.ADVANCED_ROW }
		for i = 1, #res do out[i + 1] = res[i] end
		return out
	end
	local sortNear -- Advanced "sort:nearest": NPCs closest first, the rest after
	self.noPosition = nil
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = w end
	-- Simple mode: two everyday words that mean one thing ("attack power food", "spell power")
	if simple then
		ns.Easy.JoinPairs(words)
		ns.Easy.JoinLogic(words) -- "sword or axe" -> sword|axe, "not boe" -> -boe
	end
	-- Simple mode: a plain word in a "|" list or after "-" is an everyday word when it is one ("-junk" = not grey)
	local plainWord = simple and function(lw)
		return ns.Easy.Word(lw) or function(e) return ns.Filters.RowHas(e, lw) end
	end or nil
	for _, w in ipairs(words) do
		if simple and ns.Easy.IsAdvancedWord(w) then
			blocked = true
		elseif ns.Filters and ns.Filters.SortOf and ns.Filters.SortOf(w) then
			sortNear = true
			fsig[#fsig + 1] = "^near"
		elseif w:sub(1, 1) == "@" then
			local p = ns:ResolveProvider(w:sub(2))
			if p then
				kinds = kinds or {}
				kinds[p.id] = true
			end
		else
			-- lvl:20-30, slot:wrist, zone:ashenvale, is:todo... (Filters.lua); anything else is text
			local f = ns.Filters and ns.Filters.Parse(w, plainWord)
			-- Simple mode: a few everyday words are strict ("upgrades": only what suits you, never relaxed away)
			if not f and simple and ns.Easy.HARD_WORDS[ns.Lower(w)] then f = ns.Filters.Parse(ns.Easy.WORDS[ns.Lower(w)]) end
			-- easy mode: everyday words ("rare", "ready", "vendor") are soft filters (Easy.lua)
			local soft = not f and ns.Easy and ns.Easy.Word(w)
			if f or soft then
				filters = filters or {}
				filters[#filters + 1] = f or soft
				fsig[#fsig + 1] = (soft and "~" or "") .. ns.Lower(w)
				if soft then
					softs, softWords = softs or {}, softWords or {}
					softs[#softs + 1] = soft
					softWords[#softWords + 1] = ns.Lower(w)
				else
					hard = hard or {}
					hard[#hard + 1] = f
				end
			else
				tokens[#tokens + 1] = ns.Lower(w)
			end
		end
	end
	-- "@profession is:skillup": what's asked is recipes (only they have a difficulty): searched too
	if kinds and kinds.professions and not kinds.recipes and ns.Filters and ns.Filters.RecipeWord then
		for _, w in ipairs(words) do
			if ns.Filters.RecipeWord(w) then kinds.recipes = true break end
		end
	end
	-- Simple mode: the first word can say what to do ("use hearthstone", "nearest innkeeper"; Easy.ACTIONS)
	local act
	if simple and tokens[1] then act = Scan.TakeAction(tokens, filters) end
	self.action = act
	-- Simple mode: a place named among the words ("vendor ratchet", "trainer in booty bay", "food barrens"): NPCs
	-- there, other rows that name it (Integrations.FindPlace / PlaceFilter); checked after the cheaper filters
	self.place = nil
	if simple and #tokens > 0 and ns.Integrations and ns.Integrations.FindPlace then
		local place, rest = ns.Integrations.FindPlace(tokens)
		if place and (#rest > 0 or filters or act) then
			tokens = rest
			local f = ns.Integrations.PlaceFilter(place)
			filters, hard = filters or {}, hard or {}
			filters[#filters + 1] = f
			hard[#hard + 1] = f
			fsig[#fsig + 1] = "@" .. place.key
			self.place = place
		end
	end
	-- easy mode: the little words of a sentence aren't asked for ("food that gives stamina", "shield from kresh")
	if ns.Easy and ns.Easy.On() and #tokens > 0 then tokens = Scan.DropStop(tokens, softs) end
	local empty = #tokens == 0
	-- "brd", "strat", "sw": also the place's full name (Shorthand.lua), looked up once per search (before
	-- the Simple overview, which scores with them too)
	Scan.FillShorthand(tokens)
	-- (set before any early return: rows listed straight away, "nearest mailbox", light up these words, not the last search's)
	self.posTokens = tokens
	-- easy mode (no @kind typed): nothing typed lists nothing (a line says what to do, and the category picked
	-- is let go); typed: the categories that have it, to pick from (EasyOverview); a category picked stands for
	-- its @kinds, and its own test (Emotes: the slash rows that are emotes)
	local easyCat, here
	if simple and not kinds then
		-- (no reset of lastScan here: its signature holds the lists and filters searched, so a category picked
		-- for you, or by you, narrows keystroke by keystroke like Advanced does)
		-- a category picked for you (only one had it) is worked out again with every keystroke
		if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
		if empty and not filters then
			self.category = nil
			-- just the prompt: its faint placeholder says what to type (UpdateGhost); Down asked for your recent picks
			return Finish(self.showRecent and not blocked and self:FrequentEntries() or {})
		end
		if act and act.map then
			-- an action word: the kinds it works on, no categories to pick from
			kinds = {}
			for k in pairs(act.map) do if ns.providers[k] then kinds[k] = true end end
			if act.keep then
				filters, hard = filters or {}, hard or {}
				filters[#filters + 1], hard[#hard + 1] = act.keep, act.keep
				fsig[#fsig + 1] = "!" .. act.label
			end
			if act.nearest then
				local early, friendly
				early, here, friendly = Scan.NearestStart(tokens, filters, softWords)
				if early then return Finish(early) end
				if friendly then
					filters, hard = filters or {}, hard or {}
					filters[#filters + 1], hard[#hard + 1] = friendly, friendly
					fsig[#fsig + 1] = "faction:friendly"
				end
			end
			fsig[#fsig + 1] = "!" .. act.label
		else
			easyCat = self.category and ns.Easy.BY_ID[self.category]
			if not easyCat then
				local ov = self:EasyOverview(tokens, filters, hard, softs, softWords, table.concat(fsig, " "))
				-- only one category has it: straight to its results (no step to take)
				if #ov == 1 and ov[1].catId then
					self.category, self.categoryAuto = ov[1].catId, true
					easyCat = ns.Easy.BY_ID[ov[1].catId]
					self.softRelaxed = nil
				else
					return Finish(ov)
				end
			end
		end
	end
	if easyCat then
		kinds = ns.Easy.Kinds(easyCat.id)
		if easyCat.keep then
			filters = filters or {}
			filters[#filters + 1] = easyCat.keep
			hard = hard or {}
			hard[#hard + 1] = easyCat.keep
			fsig[#fsig + 1] = "#" .. easyCat.id
		end
	end
	-- nothing typed: just the prompt (Down brings back the last search, else your recent picks)
	if empty and not kinds and not filters then
		self.lastScan, self.lastOverview = nil, nil
		return self.showRecent and self:FrequentEntries() or {}
	end
	local Pass = ns.Filters and ns.Filters.Pass

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
	sig = table.concat(sig, ",") .. "|" .. table.concat(fsig, " ") -- (other filters: not a narrowing of the last scan)
	-- typing one more letter, or one more word, can only narrow the matches: score just the last
	-- ones again (every one of them had the earlier words, so a new word still picks from them)
	local last = self.lastScan
	if last and last.gen ~= ns.entriesGen then last, self.lastScan = nil, nil end -- (its rows may be freed lists')
	local candidates
	if not empty and fresh and last and last.sig == sig and Scan.Narrows(last.tokens, tokens) then candidates = last.matches end
	-- kind: the list's id when known (compact rows of kinds never picked are then not read for it)
	local function consider(e, kind)
		if empty then
			if filters and not Pass(e, filters) then return end
			e._score = FreqBonus(e, kind) + (rawget(e, "_rank") or 0)
			-- (compact rows get no field more: Render works their letters out on screen, none with no words)
			if rawget(e, "_compact") then e._pos = nil else e._pos = NO_POS end
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s and (not filters or Pass(e, filters)) then -- (filters only on what matched: cheaper)
				e._score = s + FreqBonus(e, kind) + (rawget(e, "_rank") or 0) -- (rank: a list's own order, < 1)
				out[#out + 1] = e
			end
		end
	end
	self.lastSearchNarrowed = candidates and true or false
	-- run by UI:RunSearch: past this frame's share, hand back what matched so far and go on
	-- in the next frame (tens of thousands of NPCs or quests no longer hitch one frame)
	local overBudget = Scan.Budget(self)
	if candidates then
		for i = 1, #candidates do
			consider(candidates[i])
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = ns:GetEntries(p)
			if overBudget() then coroutine.yield(out) end -- (reading the list may have taken the share)
			local id = p.id
			for i = 1, #list do
				consider(list[i], id)
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	if not empty then
		-- (out itself: SortAndTrim leaves it as it is; rows added to it below only make the net wider)
		self.lastScan = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = out }
		-- easy mode, nothing passed every everyday word ("rare shield wailing caverns" for a green shield):
		-- the rows with the typed words, those passing more of the everyday words first
		if #out == 0 and softs then self:RelaxSoft(included, tokens, hard, softs, out, overBudget) end
		-- nothing has every word: names within an edit or two of them ("hearhtstone")
		if #out == 0 then self:CloseSpellings(included, tokens, filters, out, overBudget) end
	end
	-- easy mode: nothing in the picked category: the categories that have it instead
	if easyCat and #out == 0 then
		local function Without(list)
			if not list then return nil end
			local rest = {}
			for _, f in ipairs(list) do if f ~= easyCat.keep then rest[#rest + 1] = f end end
			return #rest > 0 and rest or nil
		end
		self.category, self.categoryAuto, self.closeSpellings, self.softRelaxed = nil, nil, nil, nil
		return Finish(self:EasyOverview(tokens, Without(filters), Without(hard), Without(softs), softWords))
	end
	-- "sort:nearest" (Advanced): where you are, once (an instance or no map: no sorting, the footer says so)
	if sortNear and not here then
		here = ns.Integrations and ns.Integrations.Here and ns.Integrations.Here()
		if not here then self.noPosition = true end
	end
	-- "nearest": the NPCs that matched, closest first, how far in the detail column (none known: left out;
	-- sort:nearest keeps every other row, after the NPCs)
	if here then
		out = Scan.NearestViews(out, here, sortNear, overBudget)
		if #out == 0 and not sortNear then return Finish(PseudoEntries({ EASY_NONE_NEAR })) end
	end
	if not empty and (not kinds or kinds.quests) then LinkQuests(out) end
	local res = SortAndTrim(out, nil, overBudget)
	if act and act.map and #res == 0 then return Finish(PseudoEntries({ EASY_NONE })) end -- ("use xyzzy": say so)
	-- an action word: each row's Enter does it ("use": the item's Shift+Enter action)
	if act and act.map then
		for i = 1, #res do res[i] = ns.Easy.ActionView(res[i], act) end
	end
	-- nothing here has what was typed in its name, but a list only searched with @kind does
	-- (Questie's quests, NPCs): a row on top offers it (Tab or Enter adds the @kind)
	if not kinds and not empty and not filters then
		local hints, at = self:BigListHint(text, tokens, res, overBudget)
		for i, hint in ipairs(hints or {}) do table.insert(res, math.min((at or 1) + i - 1, #res + 1), hint) end
	end
	return Finish(res)
end

--- Pure fuzzy finding (Tab+`, UI.fzf), like fzf: every list there is (the ones only searched with @kind too),
--- each typed word matched by its letters in order against the NAME only (no text, initials, shorthand, close
--- spellings, filters, @kinds, picks history, hint rows or linked quests). The best FZF_MAX, to go through with the
--- arrow keys. Lists made from another one (@gear, @consumable, @mats: copies of the item rows) are left out, and a
--- row two lists share (earned achievements) is listed once. Narrows from the last keystroke's matches and is
--- spread over frames like the usual search.
local FZF_MAX = 500
local FZF_LEN = 0.001 -- (equal matches: the shorter name first, as fzf does)
function UI:FuzzySearch(text)
	local tokens = {}
	for w in text:gmatch("%S+") do tokens[#tokens + 1] = ns.Lower(w) end
	self.posTokens = tokens
	if #tokens == 0 then self.lastFzf = nil return {} end
	local included, sig, fresh = {}, {}, true
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if not p.follows then
			included[#included + 1] = p
			sig[#sig + 1] = id
			if p._dirty or not p._entries then fresh = false end
		end
	end
	sig = table.concat(sig, ",")
	-- one more letter or one more word only narrows (letters in order: "frst" holds whatever "frs" didn't lose)
	local last, candidates = self.lastFzf, nil
	if last and last.gen ~= ns.entriesGen then last, self.lastFzf = nil, nil end
	local n = #tokens
	if fresh and last and last.sig == sig and Scan.Narrows(last.tokens, tokens) then candidates = last.matches end
	local out, seen = {}, {}
	local score = Fuzzy.score
	local function consider(e)
		local name = e.name
		if type(name) ~= "string" then return end
		local lname, total = e._lname, 0
		for i = 1, n do
			local s = score(tokens[i], name, lname)
			if not s then return end
			total = total + s
		end
		if seen[e] or e.noActivate then return end -- (only matches are remembered: no table of every row)
		seen[e] = true
		e._score, e._pos = total - #name * FZF_LEN, nil
		if not rawget(e, "_compact") then e._nameHit = true end
		out[#out + 1] = e
	end
	self.lastSearchNarrowed = candidates and true or false
	local overBudget = Scan.Budget(self)
	if candidates then
		for i = 1, #candidates do
			consider(candidates[i])
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = ns:GetEntries(p)
			if overBudget() then coroutine.yield(out) end
			for i = 1, #list do
				consider(list[i])
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	self.lastFzf = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = out }
	return SortAndTrim(out, FZF_MAX, overBudget)
end

--- The text a prompt keeps when it turns to pure fuzzy finding: its plain words (no @kinds, key:value filters,
--- -not / a|b words, sort:, nor a ">> channel"; a .command or /slash line: nothing), a space after them.
function UI.FuzzyPlain(text)
	local first = text:match("^%s*(.)")
	if first == "." or first == "/" then return "" end
	if ns.Share then
		local query, rest = ns.Share.Split(text)
		if rest then text = query end
	end
	local F, out = ns.Filters, {}
	for w in text:gmatch("%S+") do
		local key = w:match("^(%a+):")
		local skip = w:sub(1, 1) == "@" or w:find("^[-!]%a") or w:find("[|&]")
			or (F and F.SortOf and F.SortOf(w)) or (key and F and F.IsKey and F.IsKey(key))
		if not skip then out[#out + 1] = w end
	end
	return #out > 0 and (table.concat(out, " ") .. " ") or ""
end

local function PickCategory(e) UI:SetCategory(e.catId) end
local SOFT_PASS = 2.0 -- easy mode's relaxed pass: each everyday word a row passes (beats any score gap)

--- Easy mode, typed before a category is picked: one row per category that has matches ("Bags  Rumsey Rum
--- +2 more"), the best match first; Enter or a click picks it. Questie's lists are counted by their name index.
--- Spread over frames like the search.
--- (fsig: the search's filter signature. When the words only grew since the last overview, under the same filters
--- and the same lists, each list is scanned from the rows that matched last time, not in full: lastOverview.)
function UI:EasyOverview(tokens, filters, hard, softs, softWords, fsig)
	local reuse, last = nil, self.lastOverview
	if last and fsig and last.sig == fsig and last.gen == ns.entriesGen and #tokens > 0 and Scan.Narrows(last.tokens, tokens) then
		reuse = last
	end
	local keep = { sig = fsig, tokens = tokens, rows = {} }
	local overBudget = Scan.Budget(self)
	-- (pausing shows what's already on screen: an empty list collapsed the frame to the bare prompt for a frame)
	local function tick() if overBudget() then coroutine.yield(UI.Results()) end end
	local Pass = ns.Filters and ns.Filters.Pass
	local empty = #tokens == 0
	-- Questie's lists are looked up by name only: the typed words, and the everyday words as name words
	-- ("sword": NPCs called Sword...), never with a key:value filter
	local nameWords = tokens
	if softWords and not hard then
		nameWords = {}
		for k = 1, #tokens do nameWords[k] = tokens[k] end
		for k = 1, #softWords do nameWords[#nameWords + 1] = softWords[k] end
	end
	-- relaxed: nothing anywhere passed every everyday word, so they only rank (as in RelaxSoft)
	local function scan(relaxed)
		local out = {}
		for _, c in ipairs(ns.Easy.Visible()) do
			local count, best, bestScore = 0, nil, nil
			for _, id in ipairs(c.kinds) do
				local p = ns.providers[id]
				if p and p.hintFind and not self.place then
					if #nameWords > 0 and not hard and not relaxed then
						local first, n = p.hintFind(p, nameWords, tick)
						if first and (n or 0) > 0 then
							count = count + n
							if not bestScore then best, bestScore = first, TEXT_SCORE end
						end
					end
				elseif p then
					local gen = ns.entriesGen
					local list = ns:GetEntries(p)
					local lkey = c.id .. "/" .. id
					-- (a list rebuilt meanwhile is scanned in full: its old rows may be gone)
					if reuse and not relaxed and gen == ns.entriesGen and reuse.rows[lkey] then list = reuse.rows[lkey] end
					local kept = (not relaxed and not empty) and {} or nil
					if kept then keep.rows[lkey] = kept end
					local need = filters
					if relaxed then need = hard end -- (nil: no typed key:value filter)
					for i = 1, #list do
						local e = list[i]
						local sc = (not c.keep or c.keep(e)) and (empty and 0 or ScoreEntry(e, tokens)) or nil
						if sc and (not need or Pass(e, need)) then
							if kept then kept[#kept + 1] = e end
							if relaxed then
								for k = 1, #softs do
									local ok, yes = pcall(softs[k], e)
									if ok and yes then sc = sc + SOFT_PASS * ns.Easy.Weight(softs[k]) end
								end
							end
							count = count + 1
							if not bestScore or sc > bestScore then best, bestScore = e.name, sc end
						end
						if i % SLICE_CHECK == 0 then tick() end
					end
				end
			end
			if count > 0 then
				out[#out + 1] = {
					name = c.label, catId = c.id, kind = "category", icon = c.icon or QUESTION_MARK, kindLabel = "",
					detail = tostring(best) .. (count > 1 and ("  +%d more"):format(count - 1) or ""),
					staysOpen = true, activate = PickCategory, _score = bestScore or 0, _pos = NO_POS,
				}
			end
		end
		return out
	end
	local out = scan(false)
	keep.gen = ns.entriesGen
	self.lastOverview = (fsig and #tokens > 0) and keep or nil
	self.lastOverviewReused = reuse ~= nil -- (tests)
	if #out == 0 and softs and not empty then
		out = scan(true)
		if #out > 0 then self.softRelaxed = true end
	end
	table.sort(out, function(a, b) return a._score > b._score end)
	if #out == 0 then return PseudoEntries({ EASY_NONE }) end
	return out
end


--- Easy mode: the typed words matched nothing that passes every everyday word. The rows with the words
--- (and every typed key:value filter) are listed instead, ranked by the everyday words they pass (what an item
--- is, "shield", counts for more than how rare it is: Easy.Weight).
function UI:RelaxSoft(included, tokens, hard, softs, out, overBudget)
	local Pass = ns.Filters and ns.Filters.Pass
	for _, p in ipairs(included) do
		local list = ns:GetEntries(p)
		local id = p.id
		for i = 1, #list do
			local e = list[i]
			local sc = ScoreEntry(e, tokens)
			if sc and (not hard or Pass(e, hard)) then
				local passed = 0
				for k = 1, #softs do
					local ok, yes = pcall(softs[k], e)
					if ok and yes then passed = passed + ns.Easy.Weight(softs[k]) end
				end
				e._score = sc + passed * SOFT_PASS + FreqBonus(e, id) + (rawget(e, "_rank") or 0)
				out[#out + 1] = e
			end
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	end
	if #out > 0 then self.softRelaxed = true end
end

local NEAR_WORD = 1.0 -- a word matched by a close spelling (then each edit costs NEAR_EDIT)
local NEAR_EDIT = 10   -- (closer spellings always first; the usual score orders the rest)

--- The fallback when nothing has every typed word: rows whose name has, for each word it lacks, a
--- word within NearLimit edits ("fireblal": Fireball). Only runs on an empty result, so it may
--- cost more than the scan, but rows too short are skipped and it pauses with the search
--- (overBudget; never inside a pcall). Adds to `out`; the footer then says these are close spellings.
function UI:CloseSpellings(included, tokens, filters, out, overBudget)
	-- need: the shortest name that could hold a close spelling of one of the words
	local limits, need = {}, nil
	for i = 1, #tokens do
		limits[i] = NearLimit(#tokens[i])
		if limits[i] then
			local least = #tokens[i] - limits[i]
			if not need or least < need then need = least end
		end
	end
	if not need then return end
	local Pass = ns.Filters and ns.Filters.Pass
	local short, single = tokens.short, #tokens == 1
	for _, p in ipairs(included) do
		local list = ns:GetEntries(p)
		if overBudget() then coroutine.yield(out) end
		local id = p.id
		for r = 1, #list do
			local e = list[r]
			local name, lname = e.name, rawget(e, "_lname")
			if type(name) == "string" and #name >= need then
				lname = lname or ns.Lower(name)
				local total, edits = 0, 0
				for i = 1, #tokens do
					local tk = tokens[i]
					-- (one word: nothing had it, so no row needs looking at as it is)
					local sc
					if not single then sc = TokenScore(tk, short and short[i], name, lname, RowText(e)) end
					if sc then
						total = total + sc
					else
						local d = limits[i] and NearWord(tk, lname, limits[i])
						if not d then total = nil break end
						total, edits = total + NEAR_WORD, edits + d
					end
				end
				if total and edits > 0 and (not filters or Pass(e, filters)) then
					e._score = total - edits * NEAR_EDIT + FreqBonus(e, id)
					e._pos = nil
					if not rawget(e, "_compact") then e._nameHit = true end
					out[#out + 1] = e
				end
			end
			if r % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	end
	if #out > 0 then self.closeSpellings = true end
end

-- the lists offered by that row, in order: big databases only searched with @kind
local HINT_KINDS = { "stored", "questie", "npc" }
-- a list's row is left out when one of your own results with every typed word in its name is of
-- these kinds: Questie's quests when the quest is in your log ("Steelsnap": your quest, and still
-- the row for Questie's NPC of that name). Lists not here are offered whatever you have (you have
-- no NPC rows); hintSecond lists (@stored: the same item on an alt) always are.
local HINT_SAME = { questie = { quests = true } }
UI.HINT_SAME = HINT_SAME

local function NameHasAll(e, tokens)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	for i = 1, #tokens do
		if not ln:find(tokens[i], 1, true) then return false end
	end
	return true
end

-- (a row that writes into the prompt leaves a space after it, for the next word)
local function HintActivate(e)
	local t = e.completion
	if not t:find("%s$") then t = t .. " " end
	UI:SetQuery(t, #t)
end

-- A list with this many matches or fewer shows them as results instead of a "Search ... for this"
-- row (a row to step through for one NPC was a wasted step). Questie's name index hands back as
-- many ids (Integrations' HINT_FEW, at least as many).
local HINT_FEW = 2
UI.HINT_FEW = HINT_FEW

--- The "Search <list> for this" rows (and where they go), or nil. When an @kind list has a match:
--- by name (a plain substring look) in the huge lists, or a full match (hintFull: @stored, by item
--- and holder); on top, or second when your own results have the words in a name (see HINT_SAME).
--- A list with only HINT_FEW matches or fewer gives those rows instead of its hint row.
--- Spread over frames like the search.
function UI:BigListHint(text, tokens, res, overBudget)
	local typed = 0
	for i = 1, #tokens do typed = typed + #tokens[i] end
	if typed < 3 then return nil end
	-- your own results have it by name: a list is still offered, as the second row under your best
	-- one, unless one of yours is the same sort of thing (HINT_SAME: the quest in your log)
	local mine, kinds = false, nil
	for _, e in ipairs(res) do
		if NameHasAll(e, tokens) then
			mine = true
			kinds = kinds or {}
			kinds[e.kind or ""] = true
		end
	end
	local hints = {} -- one row per list that has it (a name can be a quest and an NPC both)
	local fewMax = UI.HINT_FEW -- (this many matches or fewer: the rows themselves)
	for _, id in ipairs(HINT_KINDS) do
		local p = ns.providers[id]
		local same = HINT_SAME[id]
		local covered = false
		if p and same and kinds and not p.hintSecond then
			for k in pairs(kinds) do
				if same[k] then covered = true break end
			end
		end
		if p and p.explicit and not covered then
			local firstName, count, few = nil, 0, nil
			if p.hintFind then
				-- the list's own name index (Questie's: one text, not its thousands of rows)
				local ids
				firstName, count, ids = p.hintFind(p, tokens, function() if overBudget() then coroutine.yield(res) end end)
				local want = math.min(count, fewMax)
				if firstName and count <= fewMax and p.hintRow and type(ids) == "table" and #ids >= want then
					few = {}
					for k = 1, want do
						local row = p.hintRow(p, ids[k])
						if not row then few = nil break end
						few[#few + 1] = row
					end
				end
			else
				local list = ns:GetEntries(p)
				few = {}
				for i = 1, #list do
					local e = list[i]
					if (p.hintFull and ScoreEntry(e, tokens)) or (not p.hintFull and NameHasAll(e, tokens)) then
						count = count + 1
						firstName = firstName or e.name
						if count <= fewMax then few[count] = e end
						if count >= 100 then break end
					end
					if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(res) end
				end
				if count > fewMax or count == 0 then few = nil end
			end
			if firstName and few and #few > 0 then
				-- only one or two: the rows themselves, where the hint would have gone
				for _, e in ipairs(few) do
					local dup = false
					for k = 1, #hints do if hints[k] == e then dup = true break end end
					for k = 1, #res do if res[k] == e then dup = true break end end
					if not dup then
						e._pos = nil
						if not rawget(e, "_compact") then e._nameHit = true end
						hints[#hints + 1] = e
					end
				end
			elseif firstName then
				local kind = "@" .. (p.aliases and p.aliases[1] or id)
				local query = text:gsub("^%s+", "")
				hints[#hints + 1] = {
					name = ("Search %s for this"):format(p.hintLabel or p.label), kindLabel = "|cff33ff99Tab|r",
					detail = firstName .. (count > 1 and ("  +%s more"):format(count >= 100 and "99" or count - 1) or ""),
					icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
					completion = kind .. " " .. query, staysOpen = true, activate = HintActivate,
					_score = math.huge, _pos = NO_POS,
				}
			end
		end
	end
	if #hints > 0 then return hints, mine and 2 or 1 end
end

-- for the window (UI.lua): the matched letters of a row on screen, the sorting, the scan's helpers
UI.Positions, UI.SortAndTrim, UI.Scan, UI.HintActivate = Positions, SortAndTrim, Scan, HintActivate

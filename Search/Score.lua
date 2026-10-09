local ns = select(2, ...)

-- Scoring a row against the typed words (ScoreEntry; TokenScore for one word), the letters a row on screen matched
-- (Positions), the close spellings' measures (NearLimit, NearWord), and sorting and trimming the matches (Better,
-- SortAndTrim). Moved out of Search.lua as it was: Search.lua takes these from ns.Score at load (as locals, so a row
-- costs what it did), and the window reads UI.Positions / UI.SortAndTrim.

local UI = ns.UI
local Fuzzy = ns.Fuzzy
local SLICE_CHECK = UI.SLICE_CHECK -- rows scored between looks at the clock
local TEXT_SCORE = 1.0 -- score given to a match found in an entry's secondary text
local MAX_RESULTS = 100 -- rows a search keeps

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

ns.Score = {
	NO_POS = NO_POS, TEXT_SCORE = TEXT_SCORE, MAX_RESULTS = MAX_RESULTS,
	FreqBonus = FreqBonus, ScoreEntry = ScoreEntry, TokenScore = TokenScore, RowText = RowText,
	NearLimit = NearLimit, NearWord = NearWord, Positions = Positions, Better = Better, SortAndTrim = SortAndTrim,
}
-- for the window (UI.lua): the matched letters of a row on screen, the sorting
UI.Positions, UI.SortAndTrim = Positions, SortAndTrim

local ns = select(2, ...)
local L = ns.L

-- The search engine: the searches themselves (UI:Search, SearchText and its steps: the lists asked, the rows collected
-- and narrowed, the results finished; fuzzy finding). Command and argument rows and the empty terminal's recent picks
-- are CommandRows.lua (0.69.8).
-- Beside it: the line read into the query (Query.lua), "nearest" (Nearest.lua), what runs when nothing matches
-- (Fallbacks.lua: relaxed, close spellings, the "Search Questie for this" rows), Simple mode's overview (Overview.lua),
-- the questions (Questions/), Alt+` (Printers.lua), "Why is this here?" (Why.lua); scoring a row and sorting the
-- matches are in Score.lua. Moved out of UI.lua (0.43.15) as it was: the window (UI.lua) shows what these give and runs
-- them a slice at a time (UI:RunSearch).

local UI = ns.UI
local Fuzzy = ns.Fuzzy
local EASY_NONE = L["Nothing has that. Check the spelling, or try other words."]
local MISSING_GONE = L["Restart the game for the recipes you don't know: this update added a file, and a /reload doesn't load new files."]
local GROUP_QUESTS_GONE = L["Restart the game for party quests: this update added a file, and a /reload doesn't load new files."]
local SLICE_CHECK = UI.SLICE_CHECK -- rows scored between looks at the clock
local QUESTION_MARK = 134400 -- (an icon for rows without one)
-- scoring and sorting (Score.lua), as locals: they run for every row
local Score = ns.Score
local NO_POS, MAX_RESULTS = Score.NO_POS, Score.MAX_RESULTS
local FreqBonus, ScoreEntry = Score.FreqBonus, Score.ScoreEntry
local SortAndTrim = Score.SortAndTrim

local function PseudoEntries(lines) -- (lines saying something: ns.NoteRow each)
	local out = {}
	-- (nothing found: where to say so, .report; 0.67.11)
	for i, line in ipairs(lines) do out[i] = ns.NoteRow(line, line == EASY_NONE and ns.Report and ns.Report.HINT or nil) end
	return out
end

-- The search's helpers (a table: SearchText's steps and what they share)
local Scan = {}
-- (for the files split off this one, which load after it: Query, Nearest, Fallbacks, Questions, Printers, Why, Overview)
Scan.EASY_NONE, Scan.PseudoEntries, Scan.QUESTION_MARK = EASY_NONE, PseudoEntries, QUESTION_MARK
Scan.GROUP_QUESTS_GONE = GROUP_QUESTS_GONE

--- For a search run by UI:RunSearch (in a coroutine): a function that says when this frame's share is used up.
--- Called directly (tests, other code), the search never pauses.
function Scan.Budget(self)
	local slicing = self.sliceUntil ~= nil and coroutine.running() ~= nil
	return function() return slicing and debugprofilestop() > self.sliceUntil end
end

--- The typed words, split at spaces, but a "quoted phrase" is one string (0.52.13, the player's ask: "outlaw saber"
--- is one thing, not two words): the words, and the phrases (quote marks off, inner spaces as one) apart, in order.
--- An open quote runs to the end (while it's being typed). A quote inside a word joins the phrase to it, quote marks
--- off: in:"elwynn forest" is the word in:elwynn forest, -"outlaw saber" the word -outlaw saber.
--- (Read off the line's tokens: Lex.lua, docs/FRONT_END.md)
function Scan.Words(text)
	return ns.Lex.Words(text)
end
ns.Words = Scan.Words -- (what's said of a search reads its words the same way: Share.lua)

--- Can the last keystroke's matches stand for these words? One more letter on the last word, or one more word, only
--- narrows (every row that has the new words had the old ones); never when the last word turned into shorthand
--- ("br" -> "brd": the shorthand matches rows the shorter word didn't), nor the other way ("sw" -> "swo": the
--- shorthand matched only its full name and the word itself).
function Scan.Narrows(last, tokens)
	local n, ln = #tokens, #last
	if n ~= ln and n ~= ln + 1 then return false end
	local ea, eb = last.exact, tokens.exact
	for i = 1, ln do
		local a, b = last[i], tokens[i]
		-- (a word turned into a "quoted phrase" or back: it matches other rows, not fewer of the same)
		if ((ea and ea[a]) or false) ~= ((eb and eb[b]) or false) then return false end
		if (i < n and a ~= b) or (i == n and b:sub(1, #a) ~= a)
			or (i == n and a ~= b and tokens.short and tokens.short[i])
			or (a ~= b and last.short and last.short[i]) then return false end
	end
	return true
end

----------------------------------------------------------------------
-- Searching
----------------------------------------------------------------------

UI.DATA_RETRY, UI.DATA_RETRIES = 1.1, 8 -- (seconds between, and how many: about 9 s of the game loading item data)
local BEST_BASE = 1e6 -- (sort:best: an upgrade's score, its gain added: above every other row's)

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
		ns:Trace(("search: item data was still loading, searching %q again (%d)"):format(ns.MaskSecret(text), r.tries))
		self.lastScan, self.lastExtra = nil, nil
		self.refreshedAt, self.searchedText = nil, nil
		self.quietRedo = true -- (the list stays as it is till this search is done: UI:Refresh)
		self:Refresh()
	end)
end

function UI:Search(text)
	if ns.Filters then
		ns.Filters.loading = nil
		ns.Filters.fitMade = nil -- (is:upgrade's filter says so when it's made: its rows' tooltips say why)
		if ns.Filters.ResetAsks then ns.Filters.ResetAsks() end -- (items the client hasn't loaded: a few asked per search)
	end
	-- arithmetic: the answer is the top result (see Calc.lua)
	-- (not in Ctrl+R's history search either: "3*4" there is a line to find; 0.63.7, review)
	local calc = not (self.fzf or self.histSearch) and ns.Calc and ns.Calc.Entry(text)
	-- (a sum answered: its characters aren't words to look for close spellings of, nor is "Nothing has that" said
	-- under the answer; 0.50.7, review: "3*45g" ran a close-spellings pass over every list on each keystroke)
	self.calcAnswered = calc and true or nil
	local res = self:SearchText(text)
	-- (a date's or a level's words that are a name's, "Tonight We Dine", "Last Day of Summer", "Next Level Thinking":
	-- read as the date or level, nothing had it; the claims that may be plain words (their alt, PlainNumbers.lua's plain
	-- stage) read so, kept when a name has their words; else the search as it was, made again for what it set; review.
	-- No name has them: no second search, FRONT_END.md 4.5)
	-- (secondLook: the line the second look was kept for, so Alt+` writes it as searched: ns.QueryToAdvanced; review)
	self.secondLook = nil
	local alts = Scan.AltPhrases(self.whyQ and self.whyQ.reading)
	if alts and not Scan.AnyReal(res) and Scan.AnyNameHas(alts) then
		local again = self:SearchText(text, { noAlt = true })
		if Scan.NamesHave(again, alts) then
			res = again
			self.secondLook = (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
		else
			res = self:SearchText(text)
		end
	end
	-- (upgrades weighed: the footer says how to judge them otherwise; 0.65.9, the player: "a gentle extended footer
	-- reminder for user to set .weights if they do not like the results of upgrade searching")
	self.weightsNote = ns.Filters and ns.Filters.fitMade and L["Not what you'd pick? .weights sets how upgrades are judged"] or nil
	if calc then
		for i = #res, 1, -1 do
			if res[i].noActivate and res[i].name == EASY_NONE then table.remove(res, i) end
		end
		table.insert(res, 1, calc)
	end
	-- "| sum value", "| group zone": what was found, summed up (Aggregate.lua; its item data asked for as filters do)
	local agg = self:AggregateOver(res)
	-- (the rows before they're summed up: the bar's Sort and Group menus read what fields they have; Bar.lua)
	self.ungrouped = nil
	if agg and ns.Aggregate then self.ungrouped = res; res = ns.Aggregate.Apply(agg, res, agg.base) end
	self:RetryWhenLoaded(text)
	return res
end

--- The steps after the search that sum up or keep these rows (UI.aggregate), or nil: the bar's Group, top N and a
--- comparison said in words aren't over Simple mode's categories (review). The search's end and its first look.
function UI:AggregateOver(res)
	local agg = self.aggregate
	if agg and (agg.fromBar or agg.topWords) and ns.Bar and ns.Bar.Overview(res) then return nil end
	return agg
end

--- The words of the reading's claims that may be plain words instead (a claim's alt), lowercase, or nil.
function Scan.AltPhrases(r)
	local out
	for _, c in ipairs(r and r.claims or {}) do
		if c.alt and c.phrase then
			out = out or {}
			out[#out + 1] = ns.Lower(c.phrase)
		end
	end
	return out
end

--- A match (a row, or Simple mode's category of them), not a line saying something.
local function Found(e) return type(e) == "table" and not (e.raw or e.noActivate or e.completion or e.lead or e.syntaxRow) end
function Scan.AnyReal(rows)
	for _, e in ipairs(rows or {}) do if Found(e) then return true end end
	return false
end
--- Whether any row of the lists made so far has each of the phrases in its name: worked out once for the phrases while
--- the lists stay the same (each keystroke of "swords 3 levels above me sorted by level" asks again; review: two more
--- searches a keystroke, when it only had to look at the names once).
local nameHas = { key = nil, yes = false }
function Scan.AnyNameHas(phrases)
	local key = table.concat(phrases, "\001") .. "\002" .. tostring(ns.entriesGen)
	if nameHas.key == key then return nameHas.yes end
	local yes = false
	for _, p in pairs(ns.providers) do
		for _, e in ipairs(rawget(p, "_entries") or {}) do
			local n = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
			local all = true
			for _, ph in ipairs(phrases) do if not n:find(ph, 1, true) then all = false break end end
			if all then yes = true break end
		end
		if yes then break end
	end
	nameHas.key, nameHas.yes = key, yes
	return yes
end
--- Whether a match's name (a category's: its best match's, in its details) has each of the phrases.
function Scan.NamesHave(rows, phrases)
	for _, e in ipairs(rows or {}) do
		if Found(e) then
			local n = ns.Lower(ns.Plain(tostring((e.catId and e.detail) or e.name or "")))
			local all = true
			for _, p in ipairs(phrases) do if not n:find(p, 1, true) then all = false break end end
			if all then return true end
		end
	end
	return false
end

--- A quest item among the matches brings its quest along, right below it ("Intact Limbs" -> its
--- quest); an item with no sure quest brings the likeliest ones, marked "maybe". Adds to `out`.
local function LinkQuests(out)
	local quests = ns.providers.quests
	if not quests then return end
	local linked, from, guessed = {}, {}, {}
	local present = {} -- quests already among the results
	local guessers -- (rows with only likely quests: they link what no sure one did, after all of those)
	-- one look at each match. Compact rows are skipped unread (_compact is a field of their own, or of the row a
	-- "nearest" view stands for): only item and quest-log rows carry a quest, and those are never compact; the big
	-- lists' thousands of matches went through their metatables here, three times each
	for i = 1, #out do
		local e = out[i]
		if not e._compact then
			local qid, isQuest = e.questID, e.kind == "quests"
			if isQuest then
				present[e] = true
			elseif qid then
				local best = linked[qid]
				if not best or e._score > best then linked[qid] = e._score; from[qid] = e end
			elseif e.guessIDs then
				guessers = guessers or {}
				guessers[#guessers + 1] = e
			end
		end
	end
	for k = 1, guessers and #guessers or 0 do
		local e = guessers[k]
		for _, id in ipairs(e.guessIDs) do
			if not linked[id] then
				linked[id] = e._score; from[id] = e; guessed[id] = true
			end
		end
	end
	if not next(linked) then return end
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

UI._Scan = Scan -- (tests)

--- What a search tells the window, cleared for this one.
function Scan.ResetFlags(self)
	self.closeSpellings = nil -- (set when only close spellings matched: the footer says so)
	self.softRelaxed = nil -- (easy mode: nothing passed every everyday word, the closest shown: the footer says so)
	self.linkedGuess = {}
	self.linked = {} -- quest entry -> the item that brought it along (drawn with an arrow)
	self.answerNote, self.pipeTrail = nil, nil -- (a question's note, a chain's path: only for their own searches)
	self.showField = nil -- (an answer's rows keep their own detail; a search sorted by AH value sets it: Scan.Parse)
	self.weightsNote = nil -- (upgrades weighed: UI:Search says so once done)
	self.flightNote = nil -- (flight paths listed on a continent no flight master's map was read on: Scan.FlightNote)
	self.missingNote = nil -- (recipes you don't know listed, a profession's window not read yet: MissingRecipes.LeadRow)
	self.overviewWinner = nil -- (Simple mode's overview: the clear winner shown above its categories: Scan.Overview)
	self.typedPicks = nil -- (Simple mode: the filters and the sort typed as words, which the bar shows: Bar.lua)
end

--- Flight paths among the rows while no flight master's map has been read on your continent: the footer says so (what
--- they say of themselves there is "not checked yet"). Only for searches of the flight paths' list (@flight, Simple
--- mode's Places), and compact rows (never flight paths) aren't read: a row's kind goes through their __index.
function Scan.FlightNote(res)
	local I = ns.Integrations
	local FL = I and I.Flights
	if not FL then return end
	for i = 1, #res do
		local e = res[i]
		if not rawget(e, "_compact") and e.kind == "flight" then
			local here = I.Here()
			if here and not FL.Checked(here.cont) then UI.flightNote = FL.UNCHECKED_NOTE end
			return
		end
	end
end

--- The rows a search ends with (q.kinds as they are by then): its lists' lead lines on top.
function Scan.Finish(q, res)
	if q.kinds and q.kinds.flight then Scan.FlightNote(res) end
	-- a list that asks the server first (@who), or says why it lists nothing (@recipe is:unknown): its own row on top
	-- (given the rows so far)
	local function Leads(set)
		-- (in the lists' own order, the last one's on top: not the set's hash order, which could change between sessions;
		-- review, 0.53.6)
		for _, k in ipairs(ns.providerOrder) do
			local p = set[k] and ns.providers[k]
			local row = p and p.leadRow and p.leadRow(p, q.text, res)
			if row then row.lead = true; table.insert(res, 1, row) end -- (asks something: not a result to send)
		end
	end
	if q.kinds then Leads(q.kinds) end
	if q.also then Leads(q.also) end
	if q.missingGone then table.insert(res, 1, PseudoEntries({ MISSING_GONE })[1]) end
	if q.goneLine then table.insert(res, 1, PseudoEntries({ q.goneLine })[1]) end
	return res
end

--- Simple mode with no @kind typed: "nearest" (where you are; a game object or flight path listed at once), else a
--- category (picked, or the only one that has it). The rows to finish with instead of searching (just the prompt,
--- "nearest" stopping early, the categories to pick from), or nil: q.kinds, q.easyCat (and q.here) say what to search.
function Scan.SimpleScope(self, q)
	if not q.simple then return end
	-- (no reset of lastScan here: its signature holds the lists and filters searched, so a category picked for you, or
	-- by you, narrows keystroke by keystroke like Advanced does)
	-- a category picked for you (only one had it) is worked out again with every keystroke (an @kind typed: none; review,
	-- 0.55.18: the one opened for "horse" stayed on for "@item iron", the footer said Collections)
	if self.categoryAuto then self.category, self.categoryAuto = nil, nil end
	if q.typedKinds then return end
	if q.empty and not q.filters then
		self.category = nil
		-- just the prompt: its faint placeholder says what to type (UpdateGhost); Down asked for your recent picks
		return self.showRecent and self:FrequentEntries() or {}
	end
	local act = q.act
	if act and act.map then
		-- an action word: its lists (Scan.UseAction), no categories to pick from
		if act.nearest then
			local early, here, friendly = Scan.NearestStart(q.tokens, q.filters, q.softWords, q.strictWords, (q.actWord and act.far) or (not q.actWord and q.sortFar))
			if early then return early end
			q.here = here
			Scan.AddFilter(q, friendly, "hard", "faction:friendly", nil, "faction:friendly")
		end
		return
	end
	local easyCat = self.category and ns.Easy.BY_ID[self.category]
	-- (a word naming the kind, "hogger quest": its category, opened for you as one with the only matches is; Scan.KindWord)
	if not easyCat and q.kindCat and ns.Easy.BY_ID[q.kindCat] then
		self.category, self.categoryAuto = q.kindCat, true
		easyCat = ns.Easy.BY_ID[q.kindCat]
	end
	-- (top N said, "top 5 upgrades": the first five of every list together, not the categories to pick from; 0.66.x,
	-- the player: "top 5" showed the categories)
	local agg = self.aggregate
	if not easyCat and agg and agg.first and agg.topWords then return end
	if not easyCat then return Scan.Overview(self, q) end -- (the categories; or the only one, opened for you)
	q.kinds, q.easyCat = ns.Easy.Kinds(easyCat.id), easyCat
	-- ("mounts", "toys": that one list of the category's)
	if q.kindOnly and easyCat.id == q.kindCat and q.kinds and q.kinds[q.kindOnly] then q.kinds = { [q.kindOnly] = true } end
	-- (a list only searched when asked, the recipes you don't know with is:unknown: with its category's; ALSO_CATEGORY)
	for id in pairs(q.also or {}) do if Scan.ALSO_CATEGORY[id] == easyCat.id then q.kinds[id] = true end end
	Scan.AddFilter(q, easyCat.keep, "hard", easyCat.keep and ("#" .. easyCat.id))
end

--- The lists searched (the @kinds or the category's, else every list not only searched by @kind), the signature a
--- narrowing must match, and whether every one is built already (nothing to collect again). A list searched without
--- being named (no @kind, category or action) that has a `plain` view gives only that (`included.plain`: earned
--- achievements, not every one).
function Scan.Lists(q)
	local kinds, fsig = q.kinds, q.fsig
	local included = {}
	local fresh = true -- every list read is already built (nothing to re-collect)
	local sig = {}
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		local inc
		if kinds then inc = kinds[id] else inc = not p.explicit or (q.also ~= nil and q.also[id]) end
		if inc then
			included[#included + 1] = p
			sig[#sig + 1] = id
			if not kinds and p.plain then
				included.plain = included.plain or {}
				included.plain[p] = true
				sig[#sig] = id .. "~" -- (its plain view: never a narrowing of the whole list, nor the other way)
			end
			if p._dirty or not p._entries then fresh = false end
			-- (a list made from another, @gear from @item: stale while that one is, though it has no events of its own;
			-- review, 0.48.6: narrowing kept a sold sword in @gear)
			local src = p.follows and ns.providers[p.follows]
			if src and (src._dirty or not src._entries) then fresh = false end
		end
	end
	sig = table.concat(sig, ",") .. "|" .. table.concat(fsig, " ") -- (other filters: not a narrowing of the last scan)
	return included, sig, fresh
end

--- The rows a search reads of a list it includes: its plain view when Scan.Lists said so, else all of them.
local function RowsOf(included, p)
	local list = ns:GetEntries(p)
	if included.plain and included.plain[p] then return p.plain(p, list) end
	return list
end
Scan.RowsOf = RowsOf -- (Fallbacks.lua: the relaxed pass and close spellings read the same rows)

--- Every row of the lists that has the words and passes the filters, scored; or the last keystroke's matches scored
--- again when the words only grew (Scan.Narrows). Spread over frames (q.overBudget, set here).
function Scan.Collect(self, q, included, sig, fresh)
	local empty, filters, tokens = q.empty, q.filters, q.tokens
	local Pass = ns.Filters and ns.Filters.Pass
	local out = {}
	-- typing one more letter, or one more word, can only narrow the matches: score just the last
	-- ones again (every one of them had the earlier words, so a new word still picks from them)
	-- (q.slot: which narrowing this is: the search's own, or the lists Simple mode's overview only counted, searched after
	-- it opened their category: Scan.Search)
	local slot = q.slot or "lastScan"
	local last = self[slot]
	if last and last.gen ~= ns.entriesGen then last, self[slot] = nil, nil end -- (its rows may be freed lists')
	local candidates
	if not empty and fresh and last and last.sig == sig and not q.volatile and Scan.Narrows(last.tokens, tokens) then
		candidates = last.matches
	end
	-- kind: the list's id when known (compact rows of kinds never picked are then not read for it)
	local function consider(e, kind, picked)
		if empty then
			if filters and not Pass(e, filters) then return end
			e._score = FreqBonus(e, kind, picked) + (rawget(e, "_rank") or 0)
			-- (compact rows get no field more: Render works their letters out on screen, none with no words)
			-- (cleared only when there: Score.lua's ScoreEntry says why)
			if not rawget(e, "_compact") then e._pos = NO_POS elseif rawget(e, "_pos") ~= nil then e._pos = nil end
			out[#out + 1] = e
		else
			local s = ScoreEntry(e, tokens)
			if s and (not filters or Pass(e, filters)) then -- (filters only on what matched: cheaper)
				e._score = s + FreqBonus(e, kind, picked) + (rawget(e, "_rank") or 0) -- (rank: a list's own order, < 1)
				out[#out + 1] = e
			end
		end
	end
	self.lastSearchNarrowed = candidates and true or false
	-- run by UI:RunSearch: past this frame's share, hand back what matched so far and go on
	-- in the next frame (tens of thousands of NPCs or quests no longer hitch one frame)
	local overBudget = Scan.Budget(self)
	-- (which list each run of matches came from, kept with them: narrowing the next keystroke gives each its list's id,
	-- so a compact row's pick history is looked up once per list, as the full scan does, not once per row; review,
	-- 0.53.6. A last mark with no id: rows added after, close spellings, are looked up per row as before)
	local spans = {}
	local function Span(id) spans[#spans + 1] = { from = #out + 1, id = id } end
	if candidates then
		local sp, j, id, picked = last.spans, 0, nil, nil
		for i = 1, #candidates do
			while sp and sp[j + 1] and sp[j + 1].from <= i do
				j = j + 1
				id = sp[j].id
				picked = id and ns:FreqKind(id) or nil
				Span(id)
			end
			consider(candidates[i], id, picked)
			if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
		end
	else
		for _, p in ipairs(included) do
			local list = RowsOf(included, p)
			if overBudget() then coroutine.yield(out) end -- (reading the list may have taken the share)
			local id = p.id
			Span(id)
			local picked = ns:FreqKind(id) -- (what was picked of this list: once, not per row)
			for i = 1, #list do
				consider(list[i], id, picked)
				if i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(out) end
			end
		end
	end
	Span(nil)
	q.overBudget, q.spans = overBudget, spans
	return out
end

--- A category Simple mode's overview opened for you: its lists the overview only counted by name (Questie's, @stored)
--- searched now, as the overview found the rest (strictly, relaxed, or by close spellings), with a narrowing of their
--- own (lastExtra). The matches, those added to a copy of `matched`.
function Scan.Extra(self, q, matched)
	local out = {}
	for i = 1, #matched do out[i] = matched[i] end
	local eq = setmetatable({ kinds = q.extraKinds, slot = "lastExtra" }, { __index = q })
	local included, sig, fresh = Scan.Lists(eq)
	local narrowed = self.lastSearchNarrowed -- (the overview's: what the search narrowed is its matches, not these few lists)
	local more = Scan.Collect(self, eq, included, sig, fresh)
	self.lastSearchNarrowed = narrowed
	if not (ns.Filters and ns.Filters.loading) and not q.empty then
		self.lastExtra = { sig = sig, gen = ns.entriesGen, tokens = q.tokens, matches = more, spans = eq.spans }
	end
	if self.softRelaxed and q.softs and #more == 0 then
		more = {}
		self:RelaxSoft(included, q.tokens, q.hard, q.softs, more, eq.overBudget)
	elseif self.closeSpellings and #more == 0 then
		more = {}
		self:CloseSpellings(included, q.tokens, q.hard, more, eq.overBudget)
	end
	for i = 1, #more do out[#out + 1] = more[i] end
	return out
end

--- The best rows, in order: a quest item's quest brought along, Simple mode's action on each, the "Search <list> for
--- this" rows (an action word with nothing to do it to: a line saying so).
--- A quest from your log and its Questie copy both listed (Simple mode's Quests, @quests @questie): only the log's row
--- (it opens your quest log), as a hint row isn't offered for a list whose copy you have (UI.HINT_SAME).
function Scan.OneQuest(res)
	local inLog
	for i = 1, #res do
		local e = res[i]
		if e.kind == "quests" and e.questID then inLog = inLog or {}; inLog[e.questID] = true end
	end
	if not inLog then return res end
	local out = {}
	for i = 1, #res do
		local e = res[i]
		if not (e.kind == "questie" and inLog[rawget(e, "key")]) then out[#out + 1] = e end
	end
	return out
end

function Scan.Finalize(self, q, out)
	local text, kinds, tokens, empty, filters, act, overBudget = q.text, q.kinds, q.tokens, q.empty, q.filters, q.act, q.overBudget
	-- (summed up, "| count": only what was found, no quest brought along)
	if not empty and (not kinds or kinds.quests) and not self.aggregate then LinkQuests(out) end
	-- sort:best (Simple mode's "upgrades"): the biggest upgrades first, by how much each beats what you wear (the gain
	-- is:upgrade worked out for it); the other rows after them, as they were
	if q.sortBest and ns.Filters and ns.Filters.GainOf and ns.Filters.fitMade then
		local GainOf = ns.Filters.GainOf
		for i = 1, #out do
			local g = GainOf(out[i])
			if g then out[i]._score = BEST_BASE + g.gain end
		end
	end
	-- (a Simple mode category: every match its row counted, up to Score.LIST_MAX; not "nearest", measured for the
	-- closest MAX_RESULTS only)
	-- (summed up, "| sum value": every match as it is, nothing to sort or trim; release review: at most 5000 counted)
	if ns.Aggregate and ns.Aggregate.Summing(self.aggregate) then
		-- (a quest in your log counted once, not with its Questie copy too; review, 0.53.6)
		if kinds and kinds.quests and kinds.questie then out = Scan.OneQuest(out) end
		-- ("| first 10 | sum value": the first ten by the sort typed; "| except @bank" listed by it: its order is set
		-- here, as the steps sort by it after; 0.66.7, review)
		-- (rows taken out by "| except" after: every row in its order, else those kept were the ones gone, and the rest
		-- came by relevance; review)
		local agg = self.aggregate
		if (agg.first or not agg.last) and q.sortField and ns.Bar then
			ns.Bar.SortRows(out, q.sortField, #(agg.wheres or {}) > 0 and #out or agg.first or Score.MAX_RESULTS, overBudget)
		end
		return out
	end
	-- (Simple mode's bar: sorted by name, level, value... the rows that have it first, in its order; Bar.lua)
	-- ("| first 3": how many matched, for the footer's "3 of 250", before the best are kept)
	if self.aggregate and self.aggregate.first then self.aggregate.matched = #out end
	local limit = (q.easyCat and (not q.here or q.nearDefault)) and Score.LIST_MAX or nil
	if q.sortField and ns.Bar then ns.Bar.SortRows(out, q.sortField, limit or Score.MAX_RESULTS, overBudget) end
	local res = SortAndTrim(out, limit, overBudget)
	if kinds and kinds.quests and kinds.questie then res = Scan.OneQuest(res) end
	if act and act.map and #res == 0 then return PseudoEntries({ EASY_NONE }) end -- ("use xyzzy": say so)
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
	return res
end

--- how: Scan.Parse's (nil: as typed).
function UI:SearchText(text, how)
	Scan.ResetFlags(self)
	-- (what this search read, set below: none for Ctrl+R's history and fuzzy finding, not the last search's; UI:Search's
	-- second look reads it, review)
	self.whyQ = nil
	-- Ctrl+R: the lines you ran, nothing else (UI/Modes.lua)
	if self.histSearch then
		self.noPosition, self.action, self.place = nil, nil, nil
		return self:HistorySearch(text)
	end
	if self.fzf then
		self.noPosition, self.action, self.place = nil, nil, nil
		return self:FuzzySearch(text)
	end
	-- a phrase in the client's language: the English line it stands for (Simple.lua's E.PHRASES)
	if ns.Easy and ns.Easy.English then text = ns.Easy.English(text) end
	-- a chain or a question in plain words: its own answer, not a search (Scan.ANSWERS)
	local answer = Scan.Answer(self, text)
	if answer then self.whyQ = { answer = text } return answer end
	local q = Scan.Parse(self, text, how)
	self.whyQ = q -- (what the search read: a row's "Why is this here?", UI:WhyLines)
	Scan.ActionAndPlace(self, q)
	Scan.Prepare(self, q)
	if q.simple then
		local act = q.act
		-- (an action that is the sort, "nearest": its word, where it is in the line, the action's claim's last token)
		local ac, actSort = q.srcAction, nil
		if act and act.nearest and q.actWord then
			actSort = { id = act.far and "-distance" or "distance", word = q.actWord,
				src = ac and ns.Phrase.Span(q.reading, ac.to, ac.to) or nil }
		end
		self.typedPicks = { filters = q.picks or {}, sort = q.typedSort or actSort }
	end
	local rows = Scan.SimpleScope(self, q)
	if rows then return Scan.Finish(q, rows) end
	-- nothing typed: just the prompt (Down brings back the last search, else your recent picks)
	if q.empty and not q.kinds and not q.filters then
		self.lastScan, self.lastExtra = nil, nil
		return self.showRecent and self:FrequentEntries() or {}
	end
	-- (a category the overview opened for you: its matches are found already, and its lists only counted are searched
	-- now; else the search)
	local out = q.matched
	if out then
		if q.extraKinds then out = Scan.Extra(self, q, out) end
	else
		local included, sig, fresh = Scan.Lists(q)
		out = Scan.Collect(self, q, included, sig, fresh)
		Scan.Fallbacks(self, q, out, included, sig)
	end
	-- easy mode: nothing in the picked category: the categories that have it instead
	if q.easyCat and #out == 0 then
		local keep = q.easyCat.keep
		self.category, self.categoryAuto, self.closeSpellings, self.softRelaxed = nil, nil, nil, nil
		-- (with the search's own signature, the category's test and "#id" left out, and what was typed: the clear winner
		-- and narrowing as when no category was picked; review, 0.48.6)
		if keep then Scan.DropFilters(q, { [keep] = true }, "#" .. q.easyCat.id) end
		q.kinds, q.easyCat = nil, nil
		return Scan.Finish(q, Scan.Overview(self, q, true))
	end
	local stop
	out, stop = Scan.Nearest(self, q, out)
	if stop then return Scan.Finish(q, stop) end
	-- "sort:plan": the recipes that still give skill, by the crafts your materials cover; the footer says the skill
	if q.sortPlan and ns.Plan then
		local note
		out, note = ns.Plan.Rows(out)
		self.answerNote = note
	end
	return Scan.Finish(q, Scan.Finalize(self, q, out))
end

--- Pure fuzzy finding (Tab+`, UI.fzf), like fzf: every list there is (the ones only searched with @kind too),
--- each typed word matched by its letters in order against the NAME only (no text, initials, shorthand, close
--- spellings, filters, @kinds, picks history, hint rows or linked quests). The best FZF_MAX, to go through with the
--- arrow keys. Lists made from another one (@gear, @consumable, @mats: copies of the item rows) are left out, and a
--- row two lists share is listed once; every list is read whole (no plain view). Narrows from the last keystroke's
--- matches and is spread over frames like the usual search.
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
		for i = n, 1, -1 do -- (the last word first: narrowing, only it can turn a row away)
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
	if ns.Aggregate then text = (ns.Aggregate.Split(text)) end -- (nor "| sum value")
	-- (quoted phrases as their words, no quote marks: every letter is searched there; a quoted filter value stays with its
	-- filter; release review)
	local words, phrases = Scan.Words(text)
	local F, out = ns.Filters, {}
	for _, w in ipairs(words) do
		local key = w:match("^(%a+):")
		local skip = w:sub(1, 1) == "@" or w:find("^[-!][%a\128-\255]") or w:find("[|&]") -- ("-малое" too, 0.49.2)
			or (F and F.SortOf and F.SortOf(w)) or (key and F and F.IsKey and F.IsKey(key))
		if not skip then out[#out + 1] = w end
	end
	for _, ph in ipairs(phrases) do out[#out + 1] = ph end
	return #out > 0 and (table.concat(out, " ") .. " ") or ""
end


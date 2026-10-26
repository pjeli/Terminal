local ns = select(2, ...)
local L = ns.L

-- Simple mode's overview: one row per category that has the words (Scan.Overview), how they're ranked, the categories
-- you picked for words before (UI.CategoryPicks), the clear winner shown above them. Moved out of Search.lua as it was.

local UI = ns.UI
local Scan = UI._Scan
local Fuzzy = ns.Fuzzy
local SLICE_CHECK = UI.SLICE_CHECK
local EASY_NONE, PseudoEntries, QUESTION_MARK = Scan.EASY_NONE, Scan.PseudoEntries, Scan.QUESTION_MARK
local Score = ns.Score
local NO_POS, TEXT_SCORE, FreqBonus = Score.NO_POS, Score.TEXT_SCORE, Score.FreqBonus

-- Ranking the categories (0.56.11, the player: "reagent" listed NPCs last, under a keybinding named Toggle Reagent Bag,
-- when three dozen reagent vendors matched). A category's best match decides, as before; Questie's lists are scored
-- as a row would be (HintScore: they were all given the lowest score, a match in some text), and then:
local ROLE_MIN, ROLE_BONUS = 3, 2.0 -- a word that is the title of several NPCs names a job (Reagent Vendor): those are wanted
local BREADTH, BREADTH_MAX = 0.15, 0.75 -- more matches, a little higher (by log2 of the count): close best matches told apart
local PICK_BONUS, PICK_MAX = 1.0, 3 -- each time the category was picked for these words (db.catPicks), up to three times
local PICKS_KEPT = 300 -- (words remembered; the longest unused go first)

--- The categories picked for these words before (Simple mode's overview): category id -> times, the words as typed
--- counting fully and longer ones they start ("reag" as "reagent" is typed) for half. Empty when there are none.
function UI.CategoryPicks(want)
	local all, out = ns.db and ns.db.catPicks, {}
	if type(all) ~= "table" or type(want) ~= "string" then return out end
	local exact, longer = {}, {}
	local function Add(into, t)
		for cat, n in pairs(t) do
			if cat ~= "t" and type(n) == "number" then into[cat] = (into[cat] or 0) + math.min(n, PICK_MAX) end
		end
	end
	if type(all[want]) == "table" then Add(exact, all[want]) end
	if #want >= 3 then
		for text, t in pairs(all) do
			if text ~= want and type(t) == "table" and text:sub(1, #want) == want then Add(longer, t) end
		end
	end
	-- (up to three picks in all: the longer words' together count half, never more; release review: "reagent",
	-- "reagents" and "reagent vendor" added up to 4.5 for "rea")
	for cat, n in pairs(exact) do out[cat] = n end
	for cat, n in pairs(longer) do out[cat] = math.min(PICK_MAX, (out[cat] or 0) + math.min(n, PICK_MAX) * 0.5) end
	return out
end

--- A category picked from the overview for these words (Enter, a click, Tab): remembered for the next time.
function UI.NoteCategoryPick(want, catId)
	if type(want) ~= "string" or want == "" or type(catId) ~= "string" or not ns.db then return end
	local all = ns.db.catPicks
	if type(all) ~= "table" then all = {}; ns.db.catPicks = all end
	local t = all[want]
	if type(t) ~= "table" then
		t = {}
		all[want] = t
		local n, oldest, oldestT = 0, nil, nil
		for text, o in pairs(all) do
			n = n + 1
			local ot = type(o) == "table" and tonumber(o.t) or 0
			if text ~= want and (not oldestT or ot < oldestT) then oldest, oldestT = text, ot end
		end
		if n > PICKS_KEPT and oldest then all[oldest] = nil end
	end
	t[catId] = math.min((t[catId] or 0) + 1, PICK_MAX)
	t.t = time and time() or 0
end

--- What a category's row adds to its best match: its count, a job's title (Questie's NPCs), the player's picks.
local function CategoryBonus(b, count, picks)
	local bonus = math.min(BREADTH_MAX, BREADTH * math.log(math.max(count, 1)) / math.log(2))
	if b.role then bonus = bonus + ROLE_BONUS end
	return bonus + (picks[b.c.id] or 0) * PICK_BONUS
end

--- A Questie list's first match, scored as a row of it would be: each word by its score in the name, else in the
--- NPC's title (the index line's "<...>"), else as found in some text. And whether a word was only in the title.
local function HintScore(words, first, line)
	local name, title
	if type(line) == "string" then
		name, title = line:match("^(.-) <(.*)>$")
		name = name or line
	else
		name = ns.Lower(tostring(first))
	end
	local total, inTitle = 0, false
	for k = 1, #words do
		local s = Fuzzy.score(words[k], name)
		if not s and title then
			s = Fuzzy.score(words[k], title)
			if s then inTitle = true end
		end
		total = total + (s or TEXT_SCORE)
	end
	return total, inTitle
end
UI._HintScore = HintScore -- (tests)

local function PickCategory(e)
	UI.NoteCategoryPick(e.pickText, e.catId)
	UI:SetCategory(e.catId)
end

--- The words Questie's lists are looked up by in the overview: by name only, the typed words and the everyday words
--- as name words ("sword": NPCs called Sword...; "battlemaster", a strict one: NPCs titled so), never with any other
--- hard filter (a "not", an "or").
local function OverviewNameWords(tokens, hard, softWords, strictWords)
	local nameWords = tokens
	if (softWords or strictWords) and not hard then
		nameWords = {}
		for k = 1, #tokens do nameWords[k] = tokens[k] end
		for _, list in ipairs({ softWords or false, strictWords or false }) do
			for k = 1, list and #list or 0 do nameWords[#nameWords + 1] = list[k] end
		end
	end
	return nameWords
end

--- What was typed, as a name would be written (lowercase, one space between words), for the overview's clear winner.
function Scan.Typed(text)
	if type(text) ~= "string" then return nil end
	local t = ns.Lower(text):gsub('"', ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if t == "" then return nil end
	return t
end

-- A category of several lists: which of them had matches, after its name, as the results' kind column names them
-- (0.48.4, the player: "Game  World Map +3 more" didn't say the 3 were keybindings), the most matches first.
local KINDS_SHOWN = 3
local function KindsNote(c, counts)
	local loaded, found = 0, {}
	for i, id in ipairs(c.kinds) do
		local p = ns.providers[id]
		if p then
			loaded = loaded + 1
			if (counts[id] or 0) > 0 then found[#found + 1] = { p = p, n = counts[id], i = i } end
		end
	end
	if loaded < 2 or #found == 0 then return nil end
	table.sort(found, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.i < b.i end)
	local parts = {}
	for k = 1, math.min(#found, KINDS_SHOWN) do
		local p = found[k].p
		parts[k] = ns:KindLabel(p)
	end
	local note = table.concat(parts, ns.DETAIL_SEP)
	if #found > KINDS_SHOWN then note = note .. "  " .. L["+%d more"]:format(#found - KINDS_SHOWN) end
	return note
end

--- The overview's row for a category: its best match and how many more (Enter or a click picks it), and what it holds.
local function CategoryRow(c, best, bestScore, count, counts, hinted)
	return {
		count = count, countExact = not hinted or nil, -- (what stepping in should list: UI:SetCategory, UI:NoteCountChange)
		name = c.label, catId = c.id, kind = "category", icon = c.icon or QUESTION_MARK, kindLabel = "",
		detail = tostring(best) .. (count > 1 and ("  " .. L["+%d more"]:format(count - 1)) or ""),
		labelNote = KindsNote(c, counts),
		staysOpen = true, activate = PickCategory, _score = bestScore or 0, _pos = NO_POS,
	}
end

-- The clear winner (0.48.4, the player's ask): a row named exactly what was typed ("world map", "hearthstone"; a
-- leading "the", or a command's "/" or ".", not needed), shown above the categories to act on at once. Only when every
-- such row is in one category, and there are no more than WINNER_MAX of them (your bags' Hearthstone and the one on an
-- alt: one thing); names in two categories (Mining, the profession and the skill) are for the categories to tell apart.
local WINNER_MAX = 2
local function ExactName(name, want)
	if type(name) ~= "string" then return false end
	-- (by length first: it's asked of every match, thousands in a broad search; nothing made unless it may be it)
	local n, w = #name, #want
	if n == w then return name == want end
	if n == w + 1 then
		local b = name:byte(1)
		return (b == 47 or b == 46) and name:sub(2) == want -- ("/dance", ".mem")
	end
	if n == w + 4 then return name:sub(1, 4) == "the " and name:sub(5) == want end
	return false
end
local function Winner(exacts, cats)
	if cats < 2 or #exacts == 0 or #exacts > WINNER_MAX then return nil end
	local best
	for _, x in ipairs(exacts) do
		if x.cat ~= exacts[1].cat then return nil end
		if not best or x.sc > best.sc then best = x end
	end
	return best.e
end

--- Simple mode, before a category is picked: one row per category that has matches ("Items  Rumsey Rum +2 more", and
--- which of its lists had them), the best match first; Enter or a click picks it. A row named exactly what was typed
--- (Scan.Typed) goes above them when it's the clear winner (Winner). 0.55.5, the search's rewrite: a view of one search,
--- not a second one. The lists of every category are searched as any search is (Scan.Collect: the same scoring,
--- narrowing, relaxing and close spellings), then the matches are grouped by category (Easy.CategoryOf); Questie's lists
--- are counted by their name index (hintFind), as reading them whole on every keystroke would cost too much.
--- Returns the category rows; or nil, with the only category that has matches opened for you (self.category,
--- categoryAuto; q.kinds, q.easyCat) and its rows in q.matched when they're all here (none of them only counted).
--- noAuto: the category rows even when there's one (a picked category that had nothing: Scan.Search's fallback).
-- A list only searched when asked for (Scan.Parse's q.also, "is:unknown": the recipes you don't know) and the category
-- its rows show in, in Simple mode (0.55.18, review: typed there, it found nothing).
Scan.ALSO_CATEGORY = { missing = "crafting" }

function Scan.Overview(self, q, noAuto)
	local tokens, empty = q.tokens, q.empty
	-- the lists: every category's, but Questie's (counted by name below)
	local kinds, hinting = {}, {}
	for _, c in ipairs(ns.Easy.Visible()) do
		for _, id in ipairs(c.kinds) do
			local p = ns.providers[id]
			-- (with a place, read whole: a name lookup can't say where)
			if p and p.hintFind and not self.place then hinting[#hinting + 1] = { c = c, p = p } elseif p then kinds[id] = true end
		end
	end
	for id in pairs(q.also or {}) do if ns.providers[id] and Scan.ALSO_CATEGORY[id] then kinds[id] = true end end
	local oq = setmetatable({ kinds = kinds }, { __index = q }) -- (the query, over those lists)
	local included, sig, fresh = Scan.Lists(oq)
	local out = Scan.Collect(self, oq, included, sig, fresh)
	Scan.Fallbacks(self, oq, out, included, sig)
	q.overBudget = oq.overBudget
	local relaxed = self.softRelaxed or self.closeSpellings
	-- each match to its category (a list in two categories, the slash commands and the emotes, by the category's test)
	local byCat, order = {}, {}
	local want = Scan.Typed(q.text)
	local exacts = {} -- (rows named exactly what was typed: the clear winner, maybe)
	local loggedNames = {} -- (your quest log's matches: Questie's name count has them too)
	local overBudget = q.overBudget
	local Ez, BY_ID = ns.Easy, ns.Easy.BY_ID
	-- (a kind's category once, when it doesn't hang on the row: ~1.7 µs a match was a third of a 100k overview; each row's
	-- kind read once, not through its metatable three times. 0.63.7, review)
	local fixed = {}
	for i, e in ipairs(out) do
		-- (spread over frames too: 0.59.0, the stress test, 200,000 matches sorted into categories in one frame)
		if overBudget and i % SLICE_CHECK == 0 and overBudget() then coroutine.yield(UI.Results()) end
		local kind = e.kind
		local cid = kind and fixed[kind]
		if cid == nil then
			cid = kind and Ez.FixedCategory(kind)
			if kind then fixed[kind] = cid or false end
		end
		local c = BY_ID[cid or Ez.CategoryOf(e) or Scan.ALSO_CATEGORY[kind] or ""]
		if c then
			local b = byCat[c.id]
			if not b then b = { c = c, rows = {}, counts = {} }; byCat[c.id] = b; order[#order + 1] = b end
			b.rows[#b.rows + 1] = e
			b.counts[kind] = (b.counts[kind] or 0) + 1
			local sc = e._score
			if not b.score or sc > b.score then b.best, b.score = e.name, sc end
			if want and not relaxed and not empty and not e.noActivate
				and ExactName(rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)), want) then
				exacts[#exacts + 1] = { e = e, cat = c.id, sc = e._score }
			end
			if kind == "quests" then loggedNames[#loggedNames + 1] = rawget(e, "_lname") or "" end
		end
	end
	-- Questie's lists, by name (the typed words and the everyday words as name words; never with another hard filter,
	-- which a name can't be judged by, nor with a place, nor once nothing passed the everyday words)
	local hardOther = q.hard and #q.hard > (q.strictWords and #q.strictWords or 0) or nil
	local nameWords = OverviewNameWords(tokens, hardOther, q.softWords, q.strictWords)
	if #nameWords > 0 and not hardOther and not relaxed and not self.place then
		local function tick() if overBudget and overBudget() then coroutine.yield(UI.Results()) end end
		for _, h in ipairs(hinting) do
			local c, p = h.c, h.p
			local first, n, ids, line = p.hintFind(p, nameWords, tick)
			if first and (n or 0) > 0 then
				if p.id == "questie" then -- (a quest from your log counted once: its row here, not Questie's name count too)
					for _, ln in ipairs(loggedNames) do
						local all = true
						for w = 1, #nameWords do if not ln:find(nameWords[w], 1, true) then all = false break end end
						if all then n = n - 1 end
					end
					n = math.max(0, n)
				end
				if n > 0 then
					local b = byCat[c.id]
					if not b then b = { c = c, rows = {}, counts = {} }; byCat[c.id] = b; order[#order + 1] = b end
					b.hinted, b.n = true, (b.n or 0) + n
					b.counts[p.id] = (b.counts[p.id] or 0) + n
					local sc, inTitle = HintScore(nameWords, first, line)
					if inTitle and n >= ROLE_MIN then b.role = true end
					if not b.score or sc > b.score then b.best, b.score = first, sc end
					-- (the only one, named exactly that: Hogger)
					if want and not empty and n == 1 and ExactName(ns.Lower(tostring(first)), want) and p.hintRow
						and type(ids) == "table" and ids[1] then
						local row = p.hintRow(p, ids[1])
						if row and not row.noActivate then
							if row._score == nil then row._score = TEXT_SCORE end
							exacts[#exacts + 1] = { e = row, cat = c.id, sc = TEXT_SCORE + FreqBonus(row, p.id) }
						end
					end
				end
			end
		end
	end
	self.overviewWinner = nil
	local rows = {}
	local picks = UI.CategoryPicks(want)
	for _, b in ipairs(order) do
		local count = #b.rows + (b.n or 0)
		local row = CategoryRow(b.c, b.best, b.score, count, b.counts, b.hinted)
		row._score, row.pickText = row._score + CategoryBonus(b, count, picks), want
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) return a._score > b._score end)
	if #rows == 0 then
		-- (0.56.2, the player: "Did you mean...?") the phrases closest to it, under the note; the note keeps what was
		-- typed, for .missed when the terminal closes on it (DidYouMean.lua)
		local none = PseudoEntries({ EASY_NONE })
		none[1].missedText = q.text
		local DYM = ns.DidYouMean
		for _, r in ipairs(DYM and not empty and DYM.Rows(q.text) or {}) do none[#none + 1] = r end
		return none
	end
	-- only one category has it: straight to its results (no step to take); its rows are these, unless some were only
	-- counted by name (Questie's: then the category is searched as picked)
	if #rows == 1 and not noAuto then
		local b = byCat[rows[1].catId]
		self.category, self.categoryAuto = b.c.id, true
		q.kinds, q.easyCat = ns.Easy.Kinds(b.c.id), b.c
		for id in pairs(q.also or {}) do if Scan.ALSO_CATEGORY[id] == b.c.id then q.kinds[id] = true end end
		Scan.AddFilter(q, b.c.keep, "hard", b.c.keep and ("#" .. b.c.id))
		-- its matches are found already; its lists only counted by name (Questie's, @stored) are searched after (q.extraKinds)
		q.matched = b.rows
		for _, h in ipairs(hinting) do
			if h.c == b.c then q.extraKinds = q.extraKinds or {}; q.extraKinds[h.p.id] = true end
		end
		return nil
	end
	-- copying every result ("linen to csv"): every category's rows, not the categories themselves (release review: the
	-- CSV had a line per category); summed up too, "q:rare type:sword | group by dungeon" (0.55.12, the player's
	-- screenshot: the categories were grouped, none has a dungeon: 0 results)
	local summing = ns.Aggregate and ns.Aggregate.Summing(self.aggregate)
	if not noAuto and ((self.sendTo and self.sendTo.copy and self.sendTo.all) or summing) then
		q.kinds = {}
		for _, b in ipairs(order) do for k in pairs(ns.Easy.Kinds(b.c.id) or {}) do q.kinds[k] = true end end
		-- (the rows found already, the lists only counted by name searched after: not every list read a second time, which
		-- also took the overview's narrowing away; 0.55.18, review: two full passes a keystroke)
		local cats = {}
		for _, b in ipairs(order) do cats[b.c] = true end
		q.matched = out
		for _, h in ipairs(hinting) do
			if cats[h.c] then q.extraKinds = q.extraKinds or {}; q.extraKinds[h.p.id] = true end
		end
		return nil
	end
	-- (the clear winner on top, to act on at once; the categories still narrow the rest)
	local winner = not relaxed and Winner(exacts, #rows) or nil
	if winner then
		table.insert(rows, 1, winner)
		self.overviewWinner = winner
	end
	return rows
end

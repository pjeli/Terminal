local ns = select(2, ...)
local L = ns.L

-- When the words find nothing (Scan.Fallbacks): Simple mode's closest by the everyday words (UI:RelaxSoft), close
-- spellings (UI:CloseSpellings), and the rows that offer the big lists only searched when named (UI:BigListHint: "Search
-- Questie for this"). Moved out of Search.lua as it was.

local UI = ns.UI
local Scan = UI._Scan
local SLICE_CHECK = UI.SLICE_CHECK
local RowsOf = Scan.RowsOf
local Score = ns.Score
local NO_POS = Score.NO_POS
local FreqBonus, ScoreEntry, TokenScore, RowText = Score.FreqBonus, Score.ScoreEntry, Score.TokenScore, Score.RowText
local NearLimit, NearWord = Score.NearLimit, Score.NearWord

--- The matches kept for the next keystroke; nothing matched: Simple mode's closest by the everyday words, else close
--- spellings (added to out).
function Scan.Fallbacks(self, q, out, included, sig)
	local empty, tokens, hard, softs, overBudget = q.empty, q.tokens, q.hard, q.softs, q.overBudget
	if not empty then
		-- (out itself: SortAndTrim leaves it as it is; rows added to it below only make the net wider)
		-- (not while a filter met data still loading: the rows it couldn't judge are left out, and the next letter
		-- would narrow from what's left, judge nothing and never ask again)
		local slot = q.slot or "lastScan"
		if not (ns.Filters and ns.Filters.loading) then
			self[slot] = { sig = sig, gen = ns.entriesGen, tokens = tokens, matches = out, spans = q.spans }
		else
			self[slot] = nil
		end
		-- easy mode, nothing passed every everyday word ("rare shield wailing caverns" for a green shield):
		-- the rows with the typed words, those passing more of the everyday words first
		if #out == 0 and softs then self:RelaxSoft(included, tokens, hard, softs, out, overBudget) end
		-- nothing has every word: names within an edit or two of them ("hearhtstone"); not for a sum the calculator answered
		-- (nor for a sum: "lnen clth | count" counts nothing, not the close spellings; review, 0.53.6)
		-- (with the hard filters only: an everyday word, relaxed above, is no reason to leave a close spelling out)
		if #out == 0 and not self.calcAnswered and not (ns.Aggregate and ns.Aggregate.Summing(self.aggregate)) then
			self:CloseSpellings(included, tokens, hard, out, overBudget)
		end
	end
end

local SOFT_PASS = 2.0 -- easy mode's relaxed pass: each everyday word a row passes (beats any score gap)

--- How many of Simple mode's everyday words a row passes, each counted by its weight (Easy.Weight: "shield" counts for
--- more than "rare"). `weights`: SoftWeights(softs), worked out once per search, not per row (review, 0.53.6: the
--- overview and RelaxSoft each had a copy, weighing every filter again for every row).
local function SoftWeights(softs)
	local w = {}
	for k = 1, #softs do w[k] = ns.Easy.Weight(softs[k]) end
	return w
end
local function SoftPassed(softs, weights, e)
	local passed = 0
	for k = 1, #softs do
		local ok, yes = pcall(softs[k], e)
		if ok and yes then passed = passed + weights[k] end
	end
	return passed
end

--- Easy mode: the typed words matched nothing that passes every everyday word. The rows with the words
--- (and every typed key:value filter) are listed instead, ranked by the everyday words they pass (what an item
--- is, "shield", counts for more than how rare it is: Easy.Weight).
function UI:RelaxSoft(included, tokens, hard, softs, out, overBudget)
	local Pass = ns.Filters and ns.Filters.Pass
	local weights
	for _, p in ipairs(included) do
		local list = RowsOf(included, p)
		local id = p.id
		for i = 1, #list do
			local e = list[i]
			local sc = ScoreEntry(e, tokens)
			if sc and (not hard or Pass(e, hard)) then
				weights = weights or SoftWeights(softs)
				e._score = sc + SoftPassed(softs, weights, e) * SOFT_PASS + FreqBonus(e, id) + (rawget(e, "_rank") or 0)
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
	local exact = tokens.exact
	for i = 1, #tokens do
		limits[i] = not (exact and exact[tokens[i]]) and NearLimit(#tokens[i]) or nil -- (a "quoted phrase": as it is only)
		if limits[i] then
			local least = #tokens[i] - limits[i]
			if not need or least < need then need = least end
		end
	end
	if not need then return end
	local Pass = ns.Filters and ns.Filters.Pass
	local short, single = tokens.short, #tokens == 1
	for _, p in ipairs(included) do
		local list = RowsOf(included, p)
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
					if not single then sc = TokenScore(tk, short and short[i], name, lname, RowText(e), exact and exact[tk]) end
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
					if rawget(e, "_pos") ~= nil then e._pos = nil end
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
	-- ("Search Questie for this" is a step: Shift+Left goes back; a pick list's "@item" is only typing)
	if e.syntaxRow then UI:SetQuery(t, #t) else UI:WalkTo(t, e) end
end

-- A list with this many matches or fewer shows them as results instead of a "Search ... for this"
-- row (a row to step through for one NPC was a wasted step). Questie's name index hands back as
-- many ids (Integrations' HINT_FEW, at least as many).
local HINT_FEW = 2
UI.HINT_FEW = HINT_FEW

--- What a big @kind list has of the words: the first name, how many (100 at most counted), and the rows themselves
--- when there are only fewMax or fewer (nil otherwise). Pauses with the search (overBudget, handing back res).
local function HintMatches(p, tokens, res, overBudget, fewMax)
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
	return firstName, count, few
end

--- Only one or two: the rows themselves go where the hint would have gone (each once, and not one already listed).
local function AddFewRows(hints, few, res)
	for _, e in ipairs(few) do
		local dup = false
		for k = 1, #hints do if hints[k] == e then dup = true break end end
		for k = 1, #res do if res[k] == e then dup = true break end end
		if not dup then
			if rawget(e, "_pos") ~= nil then e._pos = nil end
			if not rawget(e, "_compact") then e._nameHit = true end
			hints[#hints + 1] = e
		end
	end
end

--- The "Search <list> for this" row: Tab or Enter writes the @kind before the words.
local function HintRow(p, id, text, firstName, count)
	local kind = ns:KindName(p) or ("@" .. id)
	local query = text:gsub("^%s+", "")
	return {
		name = L["Search %s for this"]:format(p.hintLabel or p.label), kindLabel = "|cff33ff99Tab|r",
		detail = firstName .. (count > 1 and ("  " .. L["+%d more"]:format(count >= 100 and 99 or count - 1)) or ""),
		icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		completion = kind .. " " .. query, staysOpen = true, activate = HintActivate,
		_score = math.huge, _pos = NO_POS,
	}
end

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
			local firstName, count, few = HintMatches(p, tokens, res, overBudget, fewMax)
			if firstName and few and #few > 0 then
				-- only one or two: the rows themselves, where the hint would have gone
				AddFewRows(hints, few, res)
			elseif firstName then
				hints[#hints + 1] = HintRow(p, id, text, firstName, count)
			end
		end
	end
	if #hints > 0 then return hints, mine and 2 or 1 end
end

-- for the window (UI.lua): the "Search ... for this" rows' Enter
UI.HintActivate = HintActivate

local ns = select(2, ...)
local L = ns.L

-- "Did you mean...?" (0.56.2, the player's ask): when a plain-words search finds nothing at all ("Nothing has that"),
-- the phrases Terminal understands that are closest to it come under the note, each a row Enter searches:
--
--   a spelling put right   "nearest inkeeper"         -> nearest innkeeper (each word not known, the closest known word)
--   a phrase it's like     "flight paths i dont have" -> unlearned flight paths (the examples, by the words they share)
--   a category named       "commands reload"          -> Look in Commands: reload (a category's name searched as a
--                                                        word; only when the category has it)
--
-- The words it knows: Simple mode's examples (those whose addon is there, and the ones made for your character), its
-- everyday words (Easy.WORDS) and the categories' names. Shift+Left comes back to what you typed.
--
-- .missed: the searches that found nothing, kept here (TerminalDB.missed, never sent anywhere) so you can see which
-- words you reach for: one is kept when Terminal closes on "Nothing has that", or when a suggestion is taken (and
-- which). `.missed <search>` tries one again; `.missed clear` forgets them.

local DYM = {}
ns.DidYouMean = DYM

local Lower = ns.Lower
DYM.MAX = 3 -- suggestions under the note
DYM.KEEP = 50 -- searches kept by .missed
DYM.MIN_SCORE = 0.5 -- a phrase shares at least half of the words (of the longer one)

-- (words that say little: left out when phrases are compared)
local STOP = {}
for w in ("the a an of to for is are do does i me can in on at"):gmatch("%S+") do STOP[w] = true end
-- (words a phrase may share, but not on their own: "my atunements" isn't "my mail")
local WEAK = {}
for w in ("my what whats where how who which when should could will get"):gmatch("%S+") do WEAK[w] = true end

local function Words(s)
	local out = {}
	for w in Lower(tostring(s or "")):gsub("'", ""):gmatch("[^%s%p]+") do out[#out + 1] = w end
	return out
end
DYM.Words = Words

--- The edit distance between two words (letters added, dropped, changed or two swapped), or `cap` + 1 past `cap`.
local function Distance(a, b, cap)
	local la, lb = #a, #b
	if math.abs(la - lb) > cap then return cap + 1 end
	local prev2, prev, cur = {}, {}, {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		cur = { [0] = i }
		local best = i
		local ca = a:byte(i)
		for j = 1, lb do
			local cb = b:byte(j)
			local cost = ca == cb and 0 or 1
			local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
			if i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == cb then v = math.min(v, prev2[j - 2] + 1) end
			cur[j] = v
			if v < best then best = v end
		end
		if best > cap then return cap + 1 end
		prev2, prev = prev, cur
	end
	return prev[lb]
end
DYM.Distance = Distance

-- (how many letters a word may be off by: none under 5 letters, one up to 6, two from 7)
local function Allowed(w) return (#w >= 7 and 2) or (#w >= 5 and 1) or 0 end
local function Single(w) return (#w > 3 and w:sub(-1) == "s") and w:sub(1, -2) or w end

--- Do these two words say the same (the same, a plural, or a close spelling)?
local function Close(a, b)
	if a == b then return true end
	local sa, sb = Single(a), Single(b)
	if sa == sb then return true end
	local cap = Allowed(#sa >= #sb and sa or sb) -- (by the longer: "levl" is "level", "dont" isn't "done")
	return cap > 0 and Distance(sa, sb, cap) <= cap
end
DYM.Close = Close

----------------------------------------------------------------------
-- What Terminal understands
----------------------------------------------------------------------

--- The phrases to suggest: Simple mode's examples you could use now (their addon there), your own.
function DYM.Phrases()
	local E = ns.Easy
	local out, seen = {}, {}
	local function add(s)
		if type(s) ~= "string" or seen[s] then return end
		seen[s] = true
		out[#out + 1] = s
	end
	local has = E and E.HasForExample or function() return true end
	for _, x in ipairs(E and E.SIMPLE or {}) do
		if not x.tip and has(x[2]) then add(x[1]) end
	end
	local ok, mine = pcall(function() return E and E.PersonalTagged and E.PersonalTagged(false) end)
	for _, x in ipairs(ok and type(mine) == "table" and mine or {}) do add(x[1]) end
	return out
end

--- Every word Terminal knows: the phrases' words and Simple mode's everyday words. A set. (Not the categories' names:
--- searched, they find nothing; "Look in" says them, DYM.Categories.)
function DYM.Vocabulary(phrases)
	local E = ns.Easy
	local set = {}
	for _, p in ipairs(phrases or DYM.Phrases()) do for _, w in ipairs(Words(p)) do set[w] = true end end
	for w in pairs(E and E.WORDS or {}) do
		if type(w) == "string" and not w:find("%s") then set[Lower(w)] = true end
	end
	return set
end

----------------------------------------------------------------------
-- The suggestions
----------------------------------------------------------------------

--- The line with each word Terminal doesn't know put right (the closest known word, none too far off), or nil when
--- nothing changed or a word is still unknown.
function DYM.Corrected(text, vocab)
	local words = Words(text)
	local changed = false
	for i, w in ipairs(words) do
		if not vocab[w] and #w >= 5 then -- (shorter ones: too many words are a letter apart, "dont" and "done")
			local best, bestD
			local cap = Allowed(w)
			for v in pairs(vocab) do
				if #v >= 5 then
					local d = Distance(w, v, cap)
					if d <= cap and (not bestD or d < bestD or (d == bestD and v < best)) then best, bestD = v, d end
				end
			end
			if best then words[i] = best; changed = true end
		end
	end
	-- (only a line Terminal would understand every word of: "wher should i levl" is no better than what was typed)
	for _, w in ipairs(words) do if not (vocab[w] or STOP[w]) then return nil end end
	return changed and table.concat(words, " ") or nil
end

--- How alike a phrase is to what was typed: the share of words they have in common (of the longer one's).
function DYM.Score(typed, phrase)
	local tw, pw = {}, {}
	for _, w in ipairs(Words(typed)) do if not STOP[w] then tw[#tw + 1] = w end end
	for _, w in ipairs(Words(phrase)) do if not STOP[w] then pw[#pw + 1] = w end end
	if #tw == 0 or #pw == 0 then return 0 end
	local hit, strong = 0, false
	for _, t in ipairs(tw) do
		for _, p in ipairs(pw) do
			if Close(t, p) then
				hit = hit + 1
				if not WEAK[p] then strong = true end
				break
			end
		end
	end
	if not strong then return 0 end
	return hit / math.max(#tw, #pw)
end

--- Does the category have a row named with every one of these words (its lists, by name)?
function DYM.HasIn(cat, words)
	if #words == 0 then return false end
	for _, id in ipairs(cat.kinds or {}) do
		local p = ns.providers[id]
		-- (Questie's lists: by their name index, as the overview counts them; never read whole for this)
		if p and p.hintFind then
			local ok, first, n = pcall(p.hintFind, p, words, function() end)
			if ok and (first or (tonumber(n) or 0) > 0) then return true end
			p = nil
		end
		local ok, rows = false, nil
		if p then ok, rows = pcall(ns.GetEntries, ns, p) end
		for _, e in ipairs(ok and type(rows) == "table" and rows or {}) do
			local n = type(e) == "table" and (rawget(e, "_lname") or (type(e.name) == "string" and Lower(e.name)))
			if type(n) == "string" then
				local all = true
				for _, w in ipairs(words) do if not n:find(w, 1, true) then all = false break end end
				if all and (not cat.keep or cat.keep(e)) then return true end
			end
		end
	end
	return false
end

--- The categories a typed word names ("emotes", "colections") that have the rest of the words: { cat, rest }.
function DYM.Categories(text)
	local E = ns.Easy
	local words = Words(text)
	local out = {}
	if #words < 2 then return out end -- (a category alone: nothing to look for in it)
	for _, c in ipairs(E and E.Visible and E.Visible() or {}) do
		local names = Words(c.label)
		if #names == 1 then -- ("Dungeon loot", "Guild & friends": two words each, said as a phrase, not a word)
			for i, w in ipairs(words) do
				if Close(w, names[1]) then
					local rest = {}
					for k, x in ipairs(words) do if k ~= i then rest[#rest + 1] = x end end
					if DYM.HasIn(c, rest) then out[#out + 1] = { cat = c, rest = table.concat(rest, " ") } end
					break
				end
			end
		end
	end
	return out
end

local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Take a suggestion: kept by .missed (what was typed and what was taken), then searched; Shift+Left comes back.
local function Take(e)
	DYM.Record(e.missedFrom, e.took)
	local UI = ns.UI
	if not UI then return end
	UI:WalkTo(e.searchText)
	if e.catId then UI:SetCategory(e.catId) end
end

local function Row(name, searchText, from, detail, catId)
	return { kind = "suggestion", kindLabel = "", name = name, icon = ICON, detail = detail, key = "dym:" .. name,
		searchText = searchText, missedFrom = from, took = name, catId = catId, raw = true,
		activate = Take, staysOpen = true, actionVerb = L["search this"], _score = 0 }
end

--- The suggestion rows for a search that found nothing (at most DYM.MAX), the closest first.
function DYM.Rows(text)
	if type(text) ~= "string" or not text:find("%a") then return {} end
	local phrases = DYM.Phrases()
	local vocab = DYM.Vocabulary(phrases)
	local typed = Lower(text):gsub("^%s+", ""):gsub("%s+$", "")
	local out, seen = {}, { [typed] = true }
	local function add(r) if not seen[r.searchText] and #out < DYM.MAX then seen[r.searchText] = true; out[#out + 1] = r end end
	local fixed = DYM.Corrected(typed, vocab)
	if fixed then add(Row(fixed, fixed, text, L["Did you mean this?"])) end
	local scored = {}
	for _, p in ipairs(phrases) do
		local s = DYM.Score(typed, p)
		if s >= DYM.MIN_SCORE then scored[#scored + 1] = { p, s } end
	end
	table.sort(scored, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		if #a[1] ~= #b[1] then return #a[1] < #b[1] end
		return a[1] < b[1]
	end)
	for _, x in ipairs(scored) do add(Row(x[1], x[1], text, L["Did you mean this?"])) end
	for _, x in ipairs(DYM.Categories(typed)) do
		local r = Row(L["Look in %s: %s"]:format(x.cat.label, x.rest), x.rest, text, L["Its category's name, searched as a word"], x.cat.id)
		r.key = "dym:cat:" .. x.cat.id
		seen[r.key] = nil
		if #out < DYM.MAX then out[#out + 1] = r end
	end
	return out
end

----------------------------------------------------------------------
-- .missed: the searches that found nothing
----------------------------------------------------------------------

local function Store()
	local db = ns.db
	if not db then return nil end
	db.missed = type(db.missed) == "table" and db.missed or {}
	return db.missed
end
local function Now() return (type(time) == "function" and time()) or 0 end

--- Keep a search that found nothing (and the suggestion taken for it, if any): once per search, the newest first.
function DYM.Record(text, took)
	local list = Store()
	text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if not list or text == "" then return end
	local at
	for i, m in ipairs(list) do if m.t == text then at = i break end end
	local m = at and table.remove(list, at) or { t = text, n = 0 }
	m.n, m.at = (m.n or 0) + 1, Now()
	if took then m.took = took end
	table.insert(list, 1, m)
	while #list > DYM.KEEP do table.remove(list) end
end

--- The terminal closing on "Nothing has that": what was typed is kept (once).
function DYM.NoteClosed(results)
	local e = results and results[1]
	if type(e) == "table" and rawget(e, "missedText") and not rawget(e, "missedKept") then
		e.missedKept = true
		DYM.Record(e.missedText)
	end
end

local function Said(m)
	local parts = { (m.n or 1) == 1 and L["once"] or L["%d times"]:format(m.n) }
	if (m.at or 0) > 0 and Now() > 0 then parts[#parts + 1] = ns.Ago(Now() - m.at) end
	if m.took then parts[#parts + 1] = L["you took: %s"]:format(m.took) end
	return table.concat(parts, ns.DETAIL_SEP or " · ")
end

ns:RegisterCommand("missed", {
	desc = L["The searches that found nothing, kept here to try again (.missed clear forgets them)"],
	staysOpen = true,
	complete = function()
		local out = {}
		for _, m in ipairs(Store() or {}) do out[#out + 1] = { m.t, Said(m) } end
		out[#out + 1] = { "clear", L["forget them all"] }
		return out
	end,
	run = function(args)
		local list = Store() or {}
		local a = tostring(args or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if Lower(a) == "clear" then
			for i = #list, 1, -1 do list[i] = nil end
			return { L["Forgot the searches that found nothing."] }
		end
		if a ~= "" then
			local UI = ns.UI
			if UI and UI.SetQuery then UI:SetQuery(a, #a) end
			return nil
		end
		if #list == 0 then return { L["No search has come up empty yet."] } end
		local lines = { L["Searches that found nothing, newest first (.missed <search> tries one again):"] }
		for _, m in ipairs(list) do lines[#lines + 1] = ("  %s  (%s)"):format((m.t:gsub("|", "||")), Said(m)) end
		return lines
	end,
})

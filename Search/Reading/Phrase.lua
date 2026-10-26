local ns = select(2, ...)

----------------------------------------------------------------------
-- Phrases: the line's tokens (Lex.lua) read into claims, once (docs/FRONT_END.md, 4.2-4.3). A recognizer looks at a
-- token and may claim a span of them as one thing (a send, a step, a top N...); the stages run in a fixed order, each
-- over the tokens the earlier stages left, and within a stage the line is walked left to right, the recognizers asked
-- in their priority's order: the first claim wins and the walk goes on after it. Who reads the line (the search, the
-- bar, Alt+`) reads this reading, not the text again.
--
-- A claim: { from, to = token indexes, kind, spec = its Advanced form where it has one, said = the line's text of the
-- span, by = the recognizer's id, keep = true when its words stay the search's own (claimed for what they say, not
-- taken out), and what the recognizer read (n, step, channel...) }.
-- (Phase 3: the send, steps, plain and join stages; the action and the place are noted on the reading by
-- Scan.ActionAndPlace, which reads them once the filters are known: Phrase.Note.)
----------------------------------------------------------------------

local Phrase = {}
ns.Phrase = Phrase

local byStage = {} -- stage -> its recognizers, the highest priority first
local byId = {}

--- A recognizer: { id, stage, priority, first = { words it can start at } (nil: any), classes = { token classes it may
--- claim } (default: words), modes = { simple = true, advanced = true } (default: Simple mode), lang = a client's
--- language it's for (nil: every client), firstMatch = function(low) (a test for the words it can start at, beside
--- first: "3 levels above me" starts at any number), at = function(reading, i, ctx) -> claim or nil }. Or, instead of at, a pass:
--- function(reading, ctx), reading the stage's whole line at once (the join stage's units). Registered again by its id:
--- replaced.
function Phrase.Register(rec)
	assert(type(rec) == "table" and rec.id and rec.stage and (type(rec.at) == "function" or type(rec.pass) == "function"),
		"Phrase.Register: id, stage and at or pass")
	rec.priority = rec.priority or 0
	rec.classes = rec.classes or { word = true }
	rec.modes = rec.modes or { simple = true }
	if rec.first then
		local set = {}
		for _, w in ipairs(rec.first) do set[w] = true end
		rec.firstSet = set
	end
	local list = byStage[rec.stage] or {}
	byStage[rec.stage] = list
	local old = byId[rec.id]
	if old then
		for i = #list, 1, -1 do if list[i] == old then table.remove(list, i) end end
	end
	byId[rec.id] = rec
	list[#list + 1] = rec
	table.sort(list, function(a, b) return a.priority > b.priority or (a.priority == b.priority and a.id < b.id) end)
	return rec
end

--- (tests) A recognizer taken away again.
function Phrase.Unregister(id)
	local old = byId[id]
	if not old then return end
	local list = byStage[old.stage] or {}
	for i = #list, 1, -1 do if list[i] == old then table.remove(list, i) end end
	byId[id] = nil
	Phrase.Forget()
end

--- May this recognizer's claim have tokens from..to? (none taken already, each of a class it may claim)
local function Allowed(r, rec, from, to)
	if not (from and to and from >= 1 and to <= #r.toks and from <= to) then return false end
	for k = from, to do
		if r.taken[k] or not rec.classes[r.toks[k].class] then return false end
	end
	return true
end

local function Take(r, c)
	local toks = r.toks
	if c.from and c.to and c.from <= c.to then
		c.said = r.line:sub(toks[c.from].s, toks[c.to].e)
		if not c.keep then for k = c.from, c.to do r.taken[k] = c end end
	end
	r.claims[#r.claims + 1] = c
	if c.kind and r[c.kind] == nil then r[c.kind] = c end
end

local function Asked(rec, mode, ctx)
	return rec.modes[mode] and (not rec.lang or rec.lang == ctx.locale) and (not ctx.only or ctx.only[rec.id])
end

local function RunStage(r, stage, ctx)
	local recs = byStage[stage]
	if not recs then return end
	local mode = ctx.simple and "simple" or "advanced"
	-- a pass reads the stage's whole line at once, in its priority's order before the others: what has to see every word
	-- first ("not" read everywhere before any "or": Joins.lua). The others, the ones asked, are picked out once
	-- (most stages have a few; the join stage none)
	local points, n = nil, 0
	for _, rec in ipairs(recs) do
		if Asked(rec, mode, ctx) then
			if rec.pass then rec.pass(r, ctx)
			elseif rec.at then
				points = points or {}
				n = n + 1
				points[n] = rec
			end
		end
	end
	if not points then return end
	local toks, taken = r.toks, r.taken
	local i = 1
	while i <= #toks do
		local nextI = i + 1
		if not taken[i] then
			local low = toks[i].low
			-- (a claim that keeps its words is a note on them, not a taking: the recognizers after it are asked too, and the
			-- walk goes on at the next token; one that takes them ends the asking, the walk going on after its span)
			for p = 1, n do
				local rec = points[p]
				local set, match = rec.firstSet, rec.firstMatch
				if (not set and not match) or (set and set[low]) or (match and match(low)) then
					local c = rec.at(r, i, ctx)
					if c and c.keep then
						c.by, c.stage = rec.id, stage
						Take(r, c)
					elseif c and Allowed(r, rec, c.from, c.to) then
						if c.alt and ctx.noAlt then
							-- (read as plain words this time: its words left as they are, nothing else asked at them. Only a
							-- claim the first reading would have made: one it may not make is no claim either time, and the
							-- recognizers after it are asked, as they were then; review)
							nextI = math.max(i, c.to) + 1
							break
						end
						c.by, c.stage = rec.id, stage
						Take(r, c)
						nextI = math.max(i, c.to) + 1
						break
					end
				end
			end
		end
		i = nextI
	end
end

--- (for recognizers) The tokens no claim has taken, in order, before token `upTo` (nil: all of them).
function Phrase.Free(r, upTo)
	local out = {}
	for k = 1, upTo and upTo - 1 or #r.toks do
		if not r.taken[k] then out[#out + 1] = r.toks[k] end
	end
	return out
end

--- Where tokens from..to are in the reading's line: { from, to, s, e = their bytes (inclusive), line, said = that text },
--- or nil. (What the bar cuts out by, Bar.lua's DropTyped, and where a filter came from, Search.lua's q.src)
function Phrase.Span(r, from, to)
	local a, b = r and from and r.toks[from], r and to and r.toks[to]
	if not (a and b) then return nil end
	return { from = from, to = to, s = a.s, e = b.e, line = r.line, said = r.line:sub(a.s, b.e) }
end

--- The spans of a unit's own tokens: a joined one's (Phrase.Join: "not boe", "sword or axe") each of its parts', the
--- others its own; a "quoted phrase" between a join's words is in none of them (the bar takes these out: Bar.lua).
function Phrase.Pieces(r, u)
	local out = {}
	local function Add(x)
		if x.parts then
			for _, p in ipairs(x.parts) do Add(p) end
		else
			local sp = Phrase.Span(r, x.from, x.to)
			if sp then out[#out + 1] = sp end
		end
	end
	Add(u)
	return out
end

--- Is any of tokens from..to a "quoted phrase"?
function Phrase.HasQuoted(r, from, to)
	for k = from or 1, to or 0 do
		if r.toks[k] and r.toks[k].class == "quoted" then return true end
	end
	return false
end

--- (for recognizers) A token's text lowercased as typed (quote marks and all: what the line's words were before the
--- lexer), kept on the reading.
function Phrase.LowText(r, k)
	local lt = r.lowText
	if not lt then lt = {}; r.lowText = lt end
	local v = lt[k]
	if v == nil then v = ns.Lower(r.toks[k].text); lt[k] = v end
	return v
end

-- the last few lines read, per mode, for this frame only (what a recognizer reads may change between frames: a list
-- loaded, a question's data in)
local CACHE_SIZE = 8
local cache, order, cacheAt = {}, {}, nil

--- (for recognizers) The line's words: its tokens but the "quoted phrases" (searched apart, as Scan.Words gives them),
--- in order: r.wv = their token indexes, r.wpos = token index -> its place among them, r.wlow = their values lowered.
function Phrase.WordView(r)
	if r.wv then return r.wv end
	local wv, wpos, wlow = {}, {}, {}
	for k, t in ipairs(r.toks) do
		if t.class ~= "quoted" then
			wv[#wv + 1] = k
			wpos[k] = #wv
			wlow[#wv] = t.low
		end
	end
	r.wv, r.wpos, r.wlow = wv, wpos, wlow
	return wv
end

--- The words the search reads, once the plain stage has read them: { word, low = it lowered (a line's word; the others:
--- Phrase.Low), from, to = its tokens, by, claim, phrase = a plain claim's words as they were joined (E.PlainNumbers'
--- said) }, one a word (a date that is two filters, two).
local function Units(r)
	local units = {}
	for _, k in ipairs(Phrase.WordView(r)) do
		local c = r.taken[k]
		if not c then
			local t = r.toks[k]
			units[#units + 1] = { word = t.value, low = t.low, from = k, to = k, by = "word" }
		elseif c.from == k and c.words then
			for _, w in ipairs(c.words) do
				units[#units + 1] = { word = w, from = c.from, to = c.to, by = c.by, claim = c, phrase = c.phrase }
			end
		end
	end
	r.units = units
	return units
end

--- (for the join stage's passes) A unit's word lowered, worked out once.
function Phrase.Low(u)
	local l = u.low
	if not l then l = ns.Lower(u.word); u.low = l end
	return l
end

--- (for the join stage's passes) Two or more units read as one: their span, the new word, who joined them; recorded as a
--- claim on the reading (it keeps the words: they're the plain claims' or the line's own).
function Phrase.Join(r, list, word, by)
	local from, to = list[1].from, list[#list].to
	local u = { word = word, from = from, to = to, by = by, parts = list }
	if from and to and r then
		Take(r, { from = from, to = to, keep = true, kind = "join", spec = word, by = by, stage = "join" })
	end
	return u
end

--- A claim read by who has the query, not the line alone (the action and the place: Scan.ActionAndPlace, after the
--- filters are read), over these units' tokens: recorded on the reading once (it keeps the words: the action's and
--- the place's words are taken out of the query, not the line). Gives the claim, or nil.
function Phrase.Note(r, units, kind, fields)
	if not (r and units and units[1]) then return nil end
	local from, to
	for _, u in ipairs(units) do
		if not (u and u.from) then return nil end
		from = math.min(from or u.from, u.from)
		to = math.max(to or u.to, u.to)
	end
	-- (the same line, read again this frame, keeps its reading: the same claim isn't made twice)
	local had = r[kind]
	if had and had.from == from and had.to == to then return had end
	local c = { from = from, to = to, keep = true, kind = kind, by = kind, stage = kind }
	for k, v in pairs(fields or {}) do c[k] = v end
	Take(r, c)
	return c
end

--- The tokens no claim took, in order (with the claims that take theirs, every token once); made when asked. (Nothing
--- in the addon reads them yet: the tests check invariant 2 with them, FRONT_END.md section 6.)
function Phrase.Rest(r)
	if r.rest then return r.rest end
	local rest = {}
	for k = 1, #r.toks do if not r.taken[k] then rest[#rest + 1] = r.toks[k] end end
	r.rest = rest
	return rest
end

--- The line read: { line, toks, claims, taken = token -> its claim, send, copy, steps,
--- top, setop, per, base, query; and for the search's own reading, units }.
--- ctx: { simple = Simple mode's reading, noSend = no send stage; parse = the search's words (a line whose send and
--- steps are off already: the plain and join stages, and r.units), noAlt = no claim that may be plain words instead
--- (a claim's alt: a date's words that are a name's searched as they are, UI:Search), only = { recognizer id = true }:
--- those alone asked (Scan.ReadQuestion's dates) }.
function Phrase.ReadLine(line, ctx)
	line = tostring(line or "")
	ctx = ctx or {}
	local now = _G.GetTime and _G.GetTime() or 0
	if cacheAt ~= now then cache, order, cacheAt = {}, {}, now end
	local only = ""
	if ctx.only then
		local ids = {}
		for id in pairs(ctx.only) do ids[#ids + 1] = id end
		table.sort(ids)
		only = "o" .. table.concat(ids, ",")
	end
	local key = (ctx.simple and "s" or "a") .. (ctx.noSend and "n" or "") .. (ctx.parse and "p" or "") .. (ctx.noAlt and "x" or "")
		.. only .. "\0" .. line
	local hit = cache[key]
	if hit then return hit end
	local lex = ns.Lex.Read(line)
	local r = { line = line, toks = lex.toks, claims = {}, taken = {}, ctx = ctx }
	if ctx.parse then
		r.base, r.sendEnd = line, #r.toks + 1
		if ctx.simple then RunStage(r, "plain", ctx) end
		Units(r)
		if ctx.simple then RunStage(r, "join", ctx) end
	else
		-- (ctx.noSend: a line whose send is off already, or never one: A.Split's, its last step running to the end)
		if not ctx.noSend then RunStage(r, "send", ctx) end
		-- what's searched once the send is off: the line before a ">>" (its spaces at the end off), the copy's search, or
		-- the line (UI/Results.lua's TakeSendTo)
		if r.send then r.base = (line:sub(1, r.send.at - 1):gsub("%s+$", ""))
		elseif r.copy then r.base = r.copy.query
		else r.base = line end
		r.sendEnd = r.send and r.send.from or (r.copy and r.copy.from) or (#r.toks + 1)
		RunStage(r, "steps", ctx)
		r.query = Phrase.StepsQuery(r)
	end
	if #order >= CACHE_SIZE then cache[table.remove(order, 1)] = nil end
	order[#order + 1] = key
	cache[key] = r
	return r
end

--- A list of words read as a line would be, for who has words, not a line (E.PlainNumbers', E.JoinLogic's callers):
--- each word one token (its class the lexer's), the stages asked (ctx.stages: { "plain" }, { "join" }...; ctx.only:
--- those recognizers alone). Gives the reading, its units the words as read.
function Phrase.ReadWords(words, ctx)
	local toks, pos = {}, 1
	for i, w in ipairs(words) do
		w = tostring(w)
		toks[i] = { text = w, value = w, low = ns.Lower(w), s = pos, e = pos + #w - 1, class = ns.Lex.Class(w), i = i }
		pos = pos + #w + 1
	end
	local r = { line = table.concat(words, " "), toks = toks, claims = {}, taken = {}, ctx = ctx, sendEnd = #toks + 1 }
	r.base = r.line
	local units = false
	for _, stage in ipairs(ctx.stages or {}) do
		if (stage == "join" or stage == "action" or stage == "place") and not units then Units(r); units = true end
		RunStage(r, stage, ctx)
	end
	if not units then Units(r) end
	return r
end

--- (tests) the lines read forgotten
function Phrase.Forget() cache, order, cacheAt = {}, {}, nil end

--- What the search reads once the steps are off (TakeAggregate's text): before a "|" (its spaces at the end off); the
--- line with its top N and comparison taken out (StepWords.lua: their words gone, or the line as it was); else the base.
--- (A "per" line is searched as its own Advanced line: r.per.query, read by TakeAggregate itself.)
function Phrase.StepsQuery(r)
	if r.steps then return r.steps.query end
	local top, setop = r.top, r.setop
	if not (top or setop) then return r.base end
	local toks = r.toks
	-- (a comparison said alone, "not in my bank": taken from your items, a top N before it or not, "3 not in my bank";
	-- StepWords.lua)
	if setop and setop.base then return setop.base end
	if top and not top.keep then
		-- (the words left joined by single spaces, as the line's words were put back together; a count of places
		-- "nearest" first: StepWords.lua's TopN)
		local out = {}
		for k = 1, r.sendEnd - 1 do
			local c = r.taken[k]
			if not c or (c ~= top and c ~= setop and c.keep) then out[#out + 1] = toks[k].text end
		end
		return (top.prefix or "") .. table.concat(out, " ")
	end
	if setop then
		-- (the line as typed, its last words gone: "Hogger but not in my bank" keeps "Hogger"; StepWords.lua's SetOp)
		return (r.base:sub(1, toks[setop.from].s - 1):gsub("%s+$", ""):gsub("^%s+", ""))
	end
	return r.base
end

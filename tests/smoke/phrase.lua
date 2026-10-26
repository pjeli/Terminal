-- Phrases (Search/Reading/Phrase.lua, docs/FRONT_END.md Phase 2): the registry of recognizers and the line read into claims;
-- the send and steps readers moved into it, giving what they gave before.
local T = ...
local ns, check = T.ns, T.check
local P, E, SH, A = ns.Phrase, ns.Easy, ns.Share, ns.Aggregate
local Lower = ns.Lower
io.write("[phrase: the line read into claims]\n")

-- the readers as they were before the registry (0.52.12-0.67.5), word for word: what the wrappers must give
local Old = {}
function Old.Split(text)
	if type(text) ~= "string" or not text:find(">>", 1, true) then return text, nil end
	local at, all
	for pos, w in text:gmatch("()(%S+)") do
		if w:sub(1, 2) == ">>" then at, all = pos, w:sub(3, 3) == ">" end
	end
	if not at then return text, nil end
	return text:sub(1, at - 1), (text:sub(at + (all and 3 or 2)):gsub("^%s+", ""):gsub("%s+$", "")), all or nil
end
function Old.PlainCopy(text)
	if type(text) ~= "string" then return nil end
	local query, pre, how = text:match("^(.-%S)%s+(%a%a)%s+(%a+)%s*$")
	if not query then return nil end
	pre, how = Lower(pre), Lower(how)
	if (pre ~= "to" and pre ~= "as") or (how ~= "csv" and how ~= "text") then return nil end
	return query, how
end
function Old.ASplit(text)
	if type(text) ~= "string" or not text:find("|", 1, true) then return text, nil end
	local parts, from, quoted = {}, 1, false
	for i = 1, #text do
		local c = text:sub(i, i)
		if c == '"' then
			quoted = not quoted
		elseif c == "|" and not quoted then
			local before, after = i == 1 and " " or text:sub(i - 1, i - 1), i == #text and " " or text:sub(i + 1, i + 1)
			if before:find("%s") and after:find("%s") then
				parts[#parts + 1] = text:sub(from, i - 1)
				from = i + 1
			end
		end
	end
	if #parts == 0 then return text, nil end
	parts[#parts + 1] = text:sub(from)
	local query = table.remove(parts, 1):gsub("%s+$", "")
	for k, p in ipairs(parts) do parts[k] = p:gsub("^%s+", ""):gsub("%s+$", "") end
	return query, parts
end
local TOP_LEAD = { the = true, my = true }
function Old.TopN(text)
	if type(text) ~= "string" then return text, nil end
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = w end
	if #words < 2 then return text, nil end
	local lw = {}
	for i, w in ipairs(words) do lw[i] = Lower(w) end
	local function Num(w) return tonumber(w and w:match("^(%d+)$") or "") or (w and E.NUMBER_WORDS[w]) end
	local function NumOpening(k)
		local d = tonumber(lw[k] and lw[k]:match("^(%d+)$") or "")
		if d then return d end
		local w = lw[k] and E.NUMBER_WORDS[lw[k]]
		if w and E.RANK_WORDS[lw[k + 1] or ""] then return w end
	end
	local function Rest(from, skip)
		local out = {}
		for i = 1, #words do if i < from or i >= from + skip then out[#out + 1] = words[i] end end
		return table.concat(out, " ")
	end
	local function Placed(rest)
		local I = ns.Integrations
		local ws = {}
		for w in Lower(rest):gmatch("%S+") do if not TOP_LEAD[w] then ws[#ws + 1] = w end end
		for _, w in ipairs(ws) do if E.RANK_WORDS[w] then return rest end end
		if I and I.ObjectKind and I.ObjectKind(ws) then return "nearest " .. rest end
		return rest
	end
	local i = 1
	if TOP_LEAD[lw[1]] then i = 2 end
	if E.RANK_WORDS[lw[i] or ""] and lw[i + 1] and lw[i + 2] then
		local d = Num(lw[i + 1])
		if d and d >= 1 and not E.NOT_COUNTED[lw[i + 2]] and lw[i + 2]:match("^[%a\128-\255]") then
			return Rest(i + 1, 1), math.min(d, 100)
		end
	end
	local n = NumOpening(i)
	if not n and (lw[i] == "top" or lw[i] == "first") and Num(lw[i + 1]) and lw[i + 2] then
		n = Num(lw[i + 1])
		if n < 1 or E.NOT_COUNTED[lw[i + 2]] then return text, nil end
		return Placed(Rest(i, 2)), math.min(n, 100)
	end
	if n then
		local nxt = lw[i + 1]
		if not nxt or E.NOT_COUNTED[nxt] or not nxt:match("^[%a\128-\255]") then return text, nil end
		if n < 1 then return text, nil end
		return Placed(Rest(i, 1)), math.min(n, 100)
	end
	if lw[1] == "the" and E.RANK_WORDS[lw[2]] and lw[3] then
		local k = 3
		while lw[k + 1] and (E.RANK_WORDS[lw[k]] or E.ORDER_ADJ[lw[k]]) do k = k + 1 end
		local noun = lw[k]
		if noun:find("[^s]s$") and not E.ONE_PAIR[noun] then return text, nil end
		if E.NOT_A_NOUN[noun] then return text, nil end
		return text, 1
	end
	return text, nil
end
local oldTails
function Old.SetOp(text)
	if type(text) ~= "string" then return text, nil end
	if not oldTails then
		oldTails = {}
		for phrase, list in pairs(E.LIST_PHRASES) do
			for _, group in ipairs({ { { "but not", "and not", "except", "not" }, "except" }, { { "and also", "plus" }, "also" } }) do
				for _, joiner in ipairs(group[1]) do oldTails[#oldTails + 1] = { " " .. joiner .. " " .. phrase, group[2] .. " " .. list } end
			end
		end
	end
	local lt = Lower(text)
	local last = lt:match("(%S+)%s*$")
	if not last or not (last == "bank" or last == "bags" or last == "me" or last == "alts" or last == "log" or last == "mail") then
		return text, nil
	end
	lt = lt:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	for _, t in ipairs(oldTails) do
		local tail = t[1]
		if #lt > #tail and lt:sub(-#tail) == tail then
			local rest = (text:gsub("%s+$", ""))
			for _ in tail:gmatch("%S+") do rest = (rest:gsub("%s*%S+$", "")) end
			rest = (rest:gsub("^%s+", ""))
			if rest:find("%S") then return rest, t[2] end
		end
	end
	-- (since FRONT_END.md 10.7, the player's call: a leaving out said alone is taken from your items, not your log's)
	for _, t in ipairs(oldTails) do
		if " " .. lt == t[1] then
			if t[2]:find("^except ") and not t[2]:find("@quest", 1, true) then return "@item", t[2] end
			return text, nil
		end
	end
	return text, nil
end

local function Pack(...)
	local out = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		out[#out + 1] = type(v) == "table" and ("{" .. table.concat(v, "|") .. "}") or tostring(v)
	end
	return table.concat(out, " ; ")
end

local corpus = {}
for line in io.lines("Terminal/tests/parse_corpus.txt") do
	line = line:gsub("\r$", "")
	if line ~= "" and not line:find("^#") then corpus[#corpus + 1] = line end
end
local AWKWARD = { "linen", "linen >> party", "linen >>party", "linen >>> raid", "a >> b >> c", "lvl:>>20 linen", ">> party",
	"linen >>", "linen to csv", "linen as text", "  linen  to  csv  ", "to csv", "linen to CSV", "linen to cvs",
	"in:bags | sum value", "| count", "a | b | c", "a |b", "a| b", "x | ", "linen | count >> party",
	"the 3 nearest mailboxes", "nearest 3 mailboxes", "top 5 upgrades", "top 0 swords", "5 swords", "3 stacks of linen",
	"the closest innkeeper", "the best of both worlds", "the five sorrows", "the three nearest innkeepers",
	"2 mailboxes", "the 2 nearest mailboxes but not in my bank", "cloth but not in my bank", "Hogger  but not in my bank",
	"cloth plus my alts", "not in my bank", "3 but not in my bank", "cloth except my bank", "linen and also my alts",
	"cloth and not in my bank", "linen on my alts", "top 3 flight masters" }
-- (each reader, before and now, over every line)
do
	local bad = {}
	local all = {}
	for _, l in ipairs(corpus) do all[#all + 1] = l end
	for _, l in ipairs(AWKWARD) do all[#all + 1] = l end
	for _, l in ipairs(all) do
		for _, pair in ipairs({ { "Split", SH.Split, Old.Split }, { "PlainCopy", SH.PlainCopy, Old.PlainCopy },
			{ "A.Split", A.Split, Old.ASplit }, { "TopN", E.TopN, Old.TopN }, { "SetOp", E.SetOp, Old.SetOp } }) do
			local now, before = Pack(pair[2](l)), Pack(pair[3](l))
			if now ~= before then bad[#bad + 1] = ("%s(%q): before %s, now %s"):format(pair[1], l, before, now) end
		end
	end
	check(#bad == 0, ("phrase: the send and step readers give what they gave before, over %d lines (%d differ): %s")
		:format(#all, #bad, table.concat(bad, "  //  ", 1, math.min(#bad, 6))))
end

-- (a "quoted phrase" is opaque: what's inside it is never a send or a step; docs/FRONT_END.md invariant 7. Before the
-- registry a ">>" inside quotes split the line: the one change, on purpose)
do
	check(SH.Split('"a >> b" c') == '"a >> b" c' and select(2, SH.Split('"a >> b" c')) == nil,
		"phrase: a >> inside quotes isn't a send")
	check(select(2, A.Split('"x | y" z')) == nil, "phrase: a | inside quotes isn't a step")
	local r = P.ReadLine('"the 3 nearest" mailboxes', { simple = true })
	check(not r.top, "phrase: a quoted phrase's number isn't a top N")
end

-- the reading's invariants (docs/FRONT_END.md section 6) over the corpus, in both modes
do
	local bad = {}
	for _, l in ipairs(corpus) do
		for _, simple in ipairs({ true, false }) do
			local r = P.ReadLine(l, { simple = simple })
			local seen = {}
			for _, c in ipairs(r.claims) do
				if c.from and c.to and c.from <= c.to then
					-- 1: spans are honest
					if c.said ~= r.line:sub(r.toks[c.from].s, r.toks[c.to].e) then bad[#bad + 1] = l .. ": said" end
					-- 2: claims that take their words never overlap
					if not c.keep then
						for k = c.from, c.to do
							if seen[k] then bad[#bad + 1] = l .. ": overlap" end
							seen[k] = true
						end
					end
				end
			end
			-- 2: with the rest, every token once
			for _, t in ipairs(P.Rest(r)) do
				if seen[t.i] then bad[#bad + 1] = l .. ": rest overlaps" end
				seen[t.i] = true
			end
			for k = 1, #r.toks do if not seen[k] then bad[#bad + 1] = l .. ": token " .. k .. " nowhere" end end
		end
	end
	check(#bad == 0, "phrase: spans honest, no overlaps, claims and rest cover every token once: " .. table.concat(bad, "; ", 1, math.min(#bad, 6)))
	-- 3: pure: the same line read again (another frame) gives the same claims
	local function Claims(l, simple)
		P.Forget()
		local out = {}
		for _, c in ipairs(P.ReadLine(l, { simple = simple }).claims) do out[#out + 1] = tostring(c.by) .. "@" .. tostring(c.from) .. "-" .. tostring(c.to) end
		return table.concat(out, " ")
	end
	local diff = 0
	for _, l in ipairs(corpus) do if Claims(l, true) ~= Claims(l, true) then diff = diff + 1 end end
	check(diff == 0, "phrase: a line read twice is read the same")
end

-- what a claim may take: only tokens of its classes, never one taken already; priorities settle a token two can start at
do
	P.Register({ id = "test-greedy", stage = "steps", priority = 99, modes = { simple = true },
		at = function(r, i) if r.toks[i].low == "grab" then return { from = i, to = #r.toks, kind = "test" } end end })
	local r = P.ReadLine("grab q:rare linen", { simple = true })
	check(not r.test, "phrase: a words-only claim can't take a syntax token (q:rare)")
	r = P.ReadLine("grab some linen", { simple = true })
	check(r.test and r.test.from == 1 and r.test.to == 3 and #P.Rest(r) == 0, "phrase: ... and takes words")
	r = P.ReadLine("grab some linen", { simple = false })
	check(not r.test, "phrase: a Simple mode recognizer isn't asked in Advanced mode")
	P.Register({ id = "test-greedy", stage = "steps", priority = 99, modes = { simple = true }, first = { "nab" },
		at = function(r, i) return { from = i, to = i, kind = "test" } end })
	r = P.ReadLine("grab nab", { simple = true })
	check(r.test and r.test.from == 2, "phrase: a recognizer with first words is asked only at them")
	P.Register({ id = "test-low", stage = "steps", priority = 1, modes = { simple = true },
		at = function(r, i) if r.toks[i].low == "nab" then return { from = i, to = i, kind = "testlow" } end end })
	r = P.ReadLine("grab nab", { simple = true })
	check(r.test and not r.testlow, "phrase: the higher priority's claim wins a token")
	P.Unregister("test-greedy"); P.Unregister("test-low")
	-- (review) the second look (noAlt) refuses only a claim the first reading would have made: an alt claim over a
	-- syntax token is none, and the recognizer after it is asked at that word both times
	P.Register({ id = "test-alt", stage = "plain", priority = 99, first = { "zzalt" },
		at = function(r, i) return { from = i, to = i + 1, kind = "testalt", alt = "words", words = { "is:x" }, phrase = "zz" } end })
	P.Register({ id = "test-after", stage = "plain", priority = 98, first = { "zzalt" },
		at = function(r, i) return { from = i, to = i, kind = "testafter", words = { "is:y" }, phrase = "zzalt" } end })
	P.Forget()
	local r1 = P.ReadLine("zzalt q:rare linen", { simple = true, parse = true })
	P.Forget()
	local r2 = P.ReadLine("zzalt q:rare linen", { simple = true, parse = true, noAlt = true })
	check(r1.testafter and not r1.testalt and r2.testafter, "phrase: noAlt refuses only a claim that could be made: "
		.. tostring(r1.testafter ~= nil) .. " " .. tostring(r2.testafter ~= nil))
	P.Unregister("test-alt"); P.Unregister("test-after")
	r = P.ReadLine("grab nab", { simple = true })
	check(not r.test and not r.testlow and #P.Rest(r) == 2, "phrase: recognizers taken away")
end

-- (review) a two-word everyday word added after the pairs were first looked at is joined too
do
	E.JoinPairs({ "linen", "cloth" })
	E.WORDS["zzq zzr"] = "is:zz"
	local words = { "zzq", "zzr", "linen" }
	E.JoinPairs(words)
	rawset(E.WORDS, "zzq zzr", nil)
	check(words[1] == "zzq zzr" and words[2] == "linen", "phrase: a pair added later is joined: " .. table.concat(words, ","))
end

-- the readings the search uses
do
	local function R(l, simple) P.Forget() return P.ReadLine(l, { simple = simple ~= false }) end
	local r = R("copper bar >> party")
	check(r.send and r.send.channel == "party" and r.base == "copper bar" and r.send.said == ">> party", "phrase: a send, its channel and what's searched")
	r = R("linen to csv")
	check(r.copy and r.copy.how == "csv" and r.base == "linen" and not r.send, "phrase: a copy said in words (Simple mode)")
	check(not R("linen to csv", false).copy, "phrase: ... not in Advanced mode")
	r = R("in:bags | sum value | count >> party")
	check(r.steps and r.steps.query == "in:bags" and table.concat(r.steps.list, ";") == "sum value;count" and r.send, "phrase: steps before a send")
	r = R("the 3 nearest mailboxes but not in my bank")
	check(r.top and r.top.n == 3 and r.setop and r.setop.step == "except @bank" and r.query == "the nearest mailboxes",
		"phrase: a top N and a comparison together: " .. tostring(r.query))
	check(not R("the 3 nearest mailboxes", false).top, "phrase: top N in words is Simple mode's")
	r = R("Hogger but not in my bank")
	check(r.setop and r.query == "Hogger", "phrase: the search's words as typed (Hogger): " .. tostring(r.query))
	r = R("the closest innkeeper")
	check(r.top and r.top.keep and r.top.n == 1 and r.query == "the closest innkeeper" and #P.Rest(r) == 3,
		"phrase: the closest one: its words stay the search's")
	r = R("in:bags | first 3")
	check(r.steps and not r.top, "phrase: steps typed: no top N in words")
end

-- one reading a frame: asked again, the same table; the next frame reads anew
do
	-- (the game's time stands still through a frame: the harness's moves on every call)
	local getTime = _G.GetTime
	_G.GetTime = function() return 100 end
	P.Forget()
	local a = P.ReadLine("rare sword", { simple = true })
	check(P.ReadLine("rare sword", { simple = true }) == a, "phrase: the same line, the same frame: the same reading")
	check(P.ReadLine("rare sword", { simple = false }) ~= a, "phrase: each mode its own reading")
	_G.GetTime = function() return 101 end
	check(P.ReadLine("rare sword", { simple = true }) ~= a, "phrase: another frame: read again")
	_G.GetTime = getTime
end

-- Phase 3: the plain words, the joins, the action and the place, read on the line's reading
io.write("[phrase: plain words, joins, action and place]\n")
do
	-- the joins as they were (0.53.6-0.67.5), word for word
	local function OldPairs(words)
		local i = 1
		while i < #words do
			local pair = Lower(words[i] .. " " .. words[i + 1])
			if E.WORDS[pair] then words[i] = pair; table.remove(words, i + 1) end
			i = i + 1
		end
	end
	local function OldLogic(words)
		local i = 1
		while i < #words do
			local lw, nw = Lower(words[i]), Lower(words[i + 1])
			local leads = i > 1 or E.WORDS[nw] ~= nil or E.IsAdvancedWord(words[i + 1])
			if E.NOT_WORDS[lw] and leads and not E.OR_WORDS[nw] and not E.NOT_WORDS[nw] then
				words[i] = "-" .. words[i + 1]
				table.remove(words, i + 1)
			end
			i = i + 1
		end
		i = 2
		while i < #words do
			if E.OR_WORDS[Lower(words[i])] then
				local stop = i + 1
				while stop + 1 <= #words and not E.OR_WORDS[Lower(words[stop + 1])] and not words[stop + 1]:find("^[-!][%a\128-\255]") do
					stop = stop + 1
				end
				local n = stop - i
				local from = i - 1
				if not words[from]:find("|", 1, true) then
					while from > 1 and i - from < n and not words[from - 1]:find("|", 1, true) do from = from - 1 end
				end
				local left = table.concat(words, "&", from, i - 1)
				local right = table.concat(words, "&", i + 1, stop)
				for _ = from, stop do table.remove(words, from) end
				table.insert(words, from, left .. "|" .. right)
				i = from + 1
			else
				i = i + 1
			end
		end
		return words
	end
	local LISTS = { { "rare", "sword", "or", "axe", "not", "boe" }, { "not" }, { "no", "rest", "for", "the", "wicked" },
		{ "without", "cloth" }, { "not", "is:boe" }, { "rare", "sword", "or", "rare", "axe" }, { "sword", "or", "not", "boe" },
		{ "cheap", "rare", "sword", "or", "epic", "axe", "or", "blue", "mace" }, { "attack", "power", "food" },
		{ "spell", "power", "or", "attack", "power" }, { "or", "sword" }, { "sword", "or" }, { "a", "or", "b", "or" } }
	for _, l in ipairs(corpus) do
		local words = ns.Lex.Words(l)
		LISTS[#LISTS + 1] = (E.PlainNumbers(words))
	end
	local bad = {}
	for _, list in ipairs(LISTS) do
		local a, b = {}, {}
		for k, w in ipairs(list) do a[k], b[k] = w, w end
		OldPairs(a); OldLogic(a)
		E.JoinPairs(b); E.JoinLogic(b)
		if table.concat(a, " ") ~= table.concat(b, " ") then
			bad[#bad + 1] = ("%s: before %s, now %s"):format(table.concat(list, " "), table.concat(a, " "), table.concat(b, " "))
		end
	end
	check(#bad == 0, ("phrase: the joins give what they gave before, over %d lists: %s"):format(#LISTS, table.concat(bad, "; ", 1, math.min(#bad, 5))))
	local w = { "not", "boe" }
	check(E.JoinLogic(w) == w and w[1] == "-boe" and #w == 1, "phrase: E.JoinLogic still changes its list in place")
	check(E.PlainDates("loot today") == "loot since:today" and E.PlainDates("hogger") == "hogger", "phrase: E.PlainDates")
	local out, said = E.PlainNumbers({ "swords", "between", "level", "20", "and", "30" })
	check(out[2] == "lvl:20-30" and said["lvl:20-30"] == "between level 20 and 30", "phrase: E.PlainNumbers' words and what they said")
end

-- the search's own reading: plain claims only take the line's plain words, never a quoted phrase or syntax
do
	local bad = {}
	for _, l in ipairs(corpus) do
		P.Forget()
		local r = P.ReadLine(l, { simple = true, parse = true })
		local taken = {}
		for _, c in ipairs(r.claims) do
			if c.from and c.said ~= r.line:sub(r.toks[c.from].s, r.toks[c.to].e) then bad[#bad + 1] = l .. ": said" end
			if c.kind == "plain" then
				for k = c.from, c.to do
					if r.toks[k].class ~= "word" then bad[#bad + 1] = l .. ": a plain claim took a " .. r.toks[k].class end
					if taken[k] then bad[#bad + 1] = l .. ": overlap" end
					taken[k] = true
				end
			end
		end
	end
	check(#bad == 0, "phrase: the search's readings: spans honest, plain words only, no overlaps: " .. table.concat(bad, "; ", 1, math.min(#bad, 5)))
	local r = P.ReadLine('mail older than "20 days" ago', { simple = true, parse = true })
	check(not r.plain, "phrase: words inside a quoted phrase are never a plain phrase's")
end

-- where each filter, sort, action and place came from (q.src, docs/FRONT_END.md 4.4)
do
	local UI = ns.UI
	local wasEasy = ns.db.easyMode
	ns.db.easyMode = true
	local function Q(line)
		local q = UI._Scan.Parse(UI, line)
		UI._Scan.ActionAndPlace(UI, q)
		return q
	end
	local function SrcOf(q, spec)
		for f, c in pairs(q.src or {}) do if q.specOf and q.specOf[f] == spec then return c.said end end
		return nil
	end
	local ok, err = pcall(function()
	local q = Q("swords between level 20 and 30")
	check(SrcOf(q, "lvl:20-30") == "between level 20 and 30", "phrase: a number said in words: its words (" .. tostring(SrcOf(q, "lvl:20-30")) .. ")")
	q = Q("sword or axe not boe")
	check(SrcOf(q, "-is:boe") == "not boe", "phrase: \"not boe\": both words (" .. tostring(SrcOf(q, "-is:boe")) .. ")")
	check(SrcOf(q, "type:sword|type:axe") == "sword or axe", "phrase: \"sword or axe\": its three words")
	q = Q("rare  sword")
	check(SrcOf(q, "q:rare") == "rare" and q.src and next(q.src) ~= nil, "phrase: an everyday word: itself")
	-- (the bar's pick and q.src: one span, where the filter is said; review)
	local same = false
	for f, c in pairs(q.src or {}) do
		if q.specOf[f] == "q:rare" then for _, p in ipairs(q.picks or {}) do if p.spec == "q:rare" and p.src == c then same = true end end end
	end
	check(same, "phrase: the bar's pick holds q.src's span, not a copy")
	q = Q("the most valuable linen")
	check(q.srcSort and q.srcSort.said == "most valuable", "phrase: an order said in words: its words")
	q = Q("use hearthstone")
	check(q.srcAction and q.srcAction.said == "use" and q.reading.action == q.srcAction, "phrase: the action's word, a claim on the reading")
	q = Q("the nearest innkeeper")
	check(q.srcAction and q.srcAction.said == "the nearest", "phrase: an article before the action goes with it: " .. tostring(q.srcAction and q.srcAction.said))
	-- (a plain phrase never reads across a "quoted phrase": FRONT_END.md 10.6)
	q = Q('under "bob" level 25')
	local words = table.concat(q.tokens, ",")
	check(words == "under,bob" and SrcOf(q, "lvl:25") == "level 25", "phrase: a quoted phrase splits a plain phrase: " .. words)
	end)
	ns.db.easyMode = wasEasy -- (put back whatever happened: the files after this one read it)
	check(ok, "phrase: q.src: " .. tostring(err))
end

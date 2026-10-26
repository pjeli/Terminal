-- The lexer (Search/Reading/Lex.lua, docs/FRONT_END.md Phase 1): the line read once into tokens, with their bytes, classes
-- and what's still being typed; Scan.Words read off them exactly as before.
local T = ...
local ns, check = T.ns, T.check
local Lex, E = ns.Lex, ns.Easy
io.write("[lex: the line read once into tokens]\n")

-- Scan.Words as it was before the lexer (0.52.13-0.67.5), word for word: what Lex.Words must give for any line
local function OldWords(text)
	local words, phrases = {}, {}
	text = text or ""
	local i, n = 1, #text
	while i <= n do
		local s = text:find("%S", i)
		if not s then break end
		local q = text:find('"', s, true)
		local e = (text:find("%s", s) or n + 1) - 1
		if q and q <= e then
			local close = text:find('"', q + 1, true) or n + 1
			local inside = text:sub(q + 1, close - 1):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
			local before = text:sub(s, q - 1)
			local after_e = (text:find("%s", close + 1) or n + 1) - 1
			local after = close <= n and text:sub(close + 1, after_e) or ""
			if before == "" then
				if inside ~= "" then phrases[#phrases + 1] = inside end
				if after ~= "" then words[#words + 1] = after end
			elseif inside ~= "" or after ~= "" then
				words[#words + 1] = before .. inside .. after
			else
				words[#words + 1] = before
			end
			i = math.max(after_e, close) + 1
		else
			words[#words + 1] = text:sub(s, e)
			i = e + 1
		end
	end
	return words, phrases
end
local function Same(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end
local function Show(t) return "[" .. table.concat(t, "][") .. "]" end

-- the corpus's lines, and lines made to be awkward
local corpus = {}
for line in io.lines("Terminal/tests/parse_corpus.txt") do
	line = line:gsub("\r$", "")
	if line ~= "" and not line:find("^#") then corpus[#corpus + 1] = line end
end
local AWKWARD = { "", " ", "   ", '"', '""', '" "', '"a b"c', '"a b" c', 'x"a b"c d', 'in:"Scarlet Monastery" sword',
	'-"outlaw saber"', '"tonight we', 'in:"', 'a"', 'a""b', '"a""b"', '  "  spaced   out  "  ', 'a "b" "c d" e"f g"h',
	"  linen   cloth ", "linen\tcloth", "Schwarzfelsspitze Чёрная Ведьма", "linen |", "linen >>", "lvl:", "@np" }
do
	local bad = {}
	local all = {}
	for _, l in ipairs(corpus) do all[#all + 1] = l end
	for _, l in ipairs(AWKWARD) do all[#all + 1] = l end
	-- (and random lines of quotes, spaces and letters: every way a quote can fall)
	local seed = 12345
	local PIECES = { "a", "bc", '"', " ", "  ", "x:", "|", ">>", "é", "-" }
	for _ = 1, 3000 do
		local parts = {}
		for _ = 1, 1 + seed % 9 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			parts[#parts + 1] = PIECES[math.floor(seed / 65536) % #PIECES + 1]
		end
		all[#all + 1] = table.concat(parts)
	end
	for _, l in ipairs(all) do
		local w1, p1 = OldWords(l)
		local w2, p2 = Lex.Words(l)
		if not (Same(w1, w2) and Same(p1, p2)) then
			bad[#bad + 1] = ("%q: before %s %s, now %s %s"):format(l, Show(w1), Show(p1), Show(w2), Show(p2))
		end
	end
	check(#bad == 0, ("lex: Scan.Words gives what it gave before, over %d lines (%d differ): %s"):format(#all, #bad,
		table.concat(bad, "; ", 1, math.min(#bad, 5))))
	local w = ns.Words('linen "outlaw saber"')
	check(w[1] == "linen", "lex: ns.Words (Share.lua's) reads through the lexer too")
end

-- every token's bytes are the line's own, in order, never overlapping (invariant 1's ground)
do
	local bad = {}
	local function Check(line)
		local r = Lex.Read(line)
		local last = 0
		for i, t in ipairs(r.toks) do
			if t.i ~= i or t.s <= last or t.e < t.s or line:sub(t.s, t.e) ~= t.text or t.low ~= ns.Lower(t.value) then
				bad[#bad + 1] = ("%q token %d"):format(line, i)
			end
			if t.class ~= "quoted" and not t.text:find('"', 1, true) and t.text ~= t.value then
				bad[#bad + 1] = ("%q token %d: a plain word's value is its text"):format(line, i)
			end
			last = t.e
		end
	end
	for _, l in ipairs(corpus) do Check(l) end
	for _, l in ipairs(AWKWARD) do Check(l) end
	check(#bad == 0, "lex: tokens' spans are the line's own bytes, in order: " .. table.concat(bad, "; ", 1, math.min(#bad, 5)))
end

local function Toks(line)
	local out = {}
	for _, t in ipairs(Lex.Read(line).toks) do
		out[#out + 1] = ("%s:%s@%d-%d%s"):format(t.class, t.value, t.s, t.e, t.open and "*" or "")
	end
	return table.concat(out, " ")
end

-- spans, quotes, ops, UTF-8, spaces
do
	local CASES = {
		{ '"a b"c', "quoted:a b@1-5 word:c@6-6*" },
		{ '"a b" c', "quoted:a b@1-5 word:c@7-7*" },
		{ 'in:"Scarlet Monastery" sword', "syntax:in:Scarlet Monastery@1-22 word:sword@24-28*" },
		{ '"tonight we', "quoted:tonight we@1-11*" },
		{ '"tonight we  ', "quoted:tonight we@1-13*" },
		{ 'sword "', "word:sword@1-5 quoted:@7-7*" },
		{ "linen | count", "word:linen@1-5 op:|@7-7 word:count@9-13*" },
		{ "q:rare|epic", "syntax:q:rare|epic@1-11*" },
		{ "copper bar >> party", "word:copper@1-6 word:bar@8-10 op:>>@12-13 word:party@15-19*" },
		{ "linen >>> raid", "word:linen@1-5 op:>>>@7-9 word:raid@11-14*" },
		{ "thorium belt > mats", "word:thorium@1-7 word:belt@9-12 op:>@14-14 word:mats@16-19*" },
		{ "a>b a|b", "word:a>b@1-3 word:a|b@5-7*" },
		{ "  linen   cloth ", "word:linen@3-7 word:cloth@11-15" },
		{ "Schwarzfelsspitze Чёрная", "word:Schwarzfelsspitze@1-17 word:Чёрная@19-30*" },
	}
	for _, c in ipairs(CASES) do
		local got = Toks(c[1])
		check(got == c[2], ("lex: %q -> %s: %s"):format(c[1], c[2], got))
	end
	check(Lex.Read("Чёрная Ведьма").toks[1].low == ns.Lower("Чёрная") and ns.Lower("Чёрная") ~= "Чёрная",
		"lex: a token's low is ns.Lower's (UTF-8 letters folded): " .. tostring(Lex.Read("Чёрная Ведьма").toks[1].low))
	check(Lex.Read("Hogger").toks[1].text == "Hogger" and Lex.Read("Hogger").toks[1].low == "hogger", "lex: case kept in text, low lowered")
end

-- each token's class
do
	local function Class(w) return Lex.Read(w).toks[1].class end
	for _, w in ipairs({ "q:rare|epic", "-is:boe", "@npc", 'in:"Scarlet Monastery"', ">>party", "sort:quality,-level", "do:use" }) do
		check(Class(w) == "syntax", ("lex: %q is syntax: %s"):format(w, Class(w)))
	end
	for _, w in ipairs({ "-boe", "sword|axe", "1g50s", "50%", "rare&sword", "hogger", "a>b" }) do
		check(Class(w) == "word", ("lex: %q is a word: %s"):format(w, Class(w)))
	end
	for _, w in ipairs({ "|", ">", ">>", ">>>" }) do check(Class(w) == "op", ("lex: %q is op: %s"):format(w, Class(w))) end
	check(Class('"tonight we dine"') == "quoted", "lex: a quoted phrase is quoted")
	-- (a - or ! before an @kind, "-@npc": a word, as E.IsAdvancedWord has always said; docs/FRONT_END.md 4.1 calls it
	-- syntax: recorded there, section 10, not changed in a move)
	check(Class("-@npc") == "word" and Class("!@npc") == "word", "lex: -@npc is a word, as before")
	-- E.IsAdvancedWord agrees with the lexer's classes for every word of the corpus
	local bad = {}
	for _, l in ipairs(corpus) do
		for _, t in ipairs(Lex.Read(l).toks) do
			if t.class ~= "quoted" and E.IsAdvancedWord(t.value) ~= (t.class ~= "word") then bad[#bad + 1] = t.value end
		end
	end
	check(#bad == 0, "lex: E.IsAdvancedWord agrees with the classes over the corpus: " .. table.concat(bad, " "))
end

-- half-typed lines: no error, the last token open
do
	for _, l in ipairs({ "lvl:", "@np", '"tonight we', "linen |", "linen >>", 'in:"elwynn', "q:rare|", "-" }) do
		local ok, r = pcall(Lex.Read, l)
		local last = ok and r.toks[#r.toks]
		check(ok and last and last.open, ("lex: %q half typed: read, its last token open"):format(l))
	end
	local r = Lex.Read("linen ")
	check(r.toks[1] and not r.toks[1].open, "lex: a space after the last word: it's done")
	check(#Lex.Read("").toks == 0 and #Lex.Read("   ").toks == 0, "lex: nothing typed: no tokens")
end

-- how a line is split comes from the client's language: at spaces for every one today
do
	local locale = _G.GetLocale
	local bad = {}
	for _, loc in ipairs({ "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "ruRU", "koKR", "ptBR", "itIT", "zhCN", "zhTW", "xxXX" }) do
		_G.GetLocale = function() return loc end
		Lex.Forget()
		if Toks("sword or axe") ~= "word:sword@1-5 word:or@7-8 word:axe@10-12*" then bad[#bad + 1] = loc end
	end
	_G.GetLocale = locale
	Lex.Forget()
	check(#bad == 0, "lex: every client's language splits at spaces (Lex.SPLIT falls back): " .. table.concat(bad, " "))
end

-- the last few lines read are kept: one keystroke asks for its line several times
do
	Lex.Forget()
	local a = Lex.Read("rare sword")
	check(Lex.Read("rare sword") == a, "lex: the same line asked again: the same reading")
	for i = 1, 20 do Lex.Read("line " .. i) end
	check(Lex.Read("rare sword") ~= a, "lex: only the last few kept")
	local w = Lex.Words("rare sword")
	w[1] = "changed"
	check(Lex.Words("rare sword")[1] == "rare", "lex: Words' lists are new each time (a reader may change them)")
end

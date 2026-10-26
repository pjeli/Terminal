local ns = select(2, ...)

----------------------------------------------------------------------
-- The prompt's line read into tokens, once (docs/FRONT_END.md, 4.1): what Simple mode's plain words, the questions,
-- the steps, the sends and Advanced syntax all read, instead of each splitting and lowercasing the line again.
--
-- A token: { text = as typed (the line's own bytes), value = what the search reads ("quotes" off, a phrase's inner
-- spaces as one), low = ns.Lower(value), s, e = its bytes in the line (inclusive), class, open, i = its place }.
-- Classes: "op" a |, >, >> or >>> standing alone; "quoted" a "quoted phrase" (searched as it is, never a filter);
-- "syntax" Advanced syntax (an @kind, a key:value in any part of a|b or a&b, >>party); "word" anything else, Simple
-- mode's own forms too (-boe, sword|axe, 1g50s, 50%). `open`: the last token, still being typed (no space after it, or
-- an unclosed quote); for completing what's being typed (docs/FRONT_END.md 4.1): nothing reads it yet but lex.lua's tests.
-- The split follows Scan.Words' rules exactly (Search.lua: its words and phrases are read off these tokens).
----------------------------------------------------------------------

local Lex = {}
ns.Lex = Lex

local Lower = ns.Lower

--- Is this word Advanced mode's syntax (an @kind, a key:value filter, >>), or a | or > standing alone? (Simple.lua's
--- E.IsAdvancedWord is this.)
function Lex.IsAdvanced(w)
	-- (a ">" standing alone is a chain's link: Simple mode says chains in words, "mats for x", 0.45.13)
	-- (a "|" standing alone too: Advanced mode's "| sum value", 0.52.13)
	if w == ">" or w == "|" or w:sub(1, 1) == "@" or w:sub(1, 2) == ">>" then return true end
	-- "-q:poor", "!is:boe", "q:rare|epic", "boe|slot:head": a key:value in any part (plain -word / a|b are Simple's too)
	for part in w:gmatch("[^|&]+") do
		local key = part:gsub("^[-!]", ""):match("^(%a+):")
		if key ~= nil and ns.Filters ~= nil and ns.Filters.IsKey(key) then return true end
	end
	return false
end

local OPS = { ["|"] = true, [">"] = true, [">>"] = true, [">>>"] = true }

--- An unquoted token's class: "op", "syntax" or "word".
function Lex.Class(w)
	if OPS[w] then return "op" end
	return Lex.IsAdvanced(w) and "syntax" or "word"
end

local function Token(toks, line, s, e, value, class, unclosed)
	toks[#toks + 1] = { text = line:sub(s, e), value = value, low = Lower(value), s = s, e = e, class = class or Lex.Class(value),
		open = unclosed or nil, i = #toks + 1 }
end

--- The line split at its spaces, a "quoted phrase" kept whole: Scan.Words' rules (0.52.13), with positions.
--- A word that starts with a quote is a phrase (and what follows its closing quote, up to a space, a word of its own:
--- "a b"c); a quote inside a word joins the phrase to it, quote marks off (in:"elwynn forest"); an open quote runs to
--- the end.
local function SplitSpaces(line)
	local toks = {}
	local i, n = 1, #line
	while i <= n do
		local s = line:find("%S", i)
		if not s then break end
		local q = line:find('"', s, true)
		local e = (line:find("%s", s) or n + 1) - 1
		if q and q <= e then
			local closeAt = line:find('"', q + 1, true)
			local close = closeAt or n + 1
			local inside = line:sub(q + 1, close - 1):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
			local before = line:sub(s, q - 1)
			local afterE = (line:find("%s", close + 1) or n + 1) - 1
			local after = close <= n and line:sub(close + 1, afterE) or ""
			local stop = math.max(afterE, math.min(close, n))
			if before == "" then
				-- the phrase (an empty one too: "" being typed is still a token, to say it's open), then what follows it
				Token(toks, line, q, math.min(close, n), inside, "quoted", not closeAt)
				if after ~= "" then Token(toks, line, close + 1, afterE, after) end
			elseif inside ~= "" or after ~= "" then
				Token(toks, line, s, stop, before .. inside .. after, nil, not closeAt)
			else
				Token(toks, line, s, stop, before, nil, not closeAt)
			end
			i = stop + 1
		else
			Token(toks, line, s, e, line:sub(s, e))
			i = e + 1
		end
	end
	-- (the last token, with no space after it, is still being typed: "lvl:", "@np", "linen |")
	local last = toks[#toks]
	if last and last.e == n and not line:sub(n, n):find("%s") then last.open = true end
	return toks
end

--- How a client's language splits a line into words: at spaces for every language that writes them. (Chinese writes
--- none: a splitter of its own would go here, docs/FRONT_END.md 4.7; until then a line is split at spaces there too.)
Lex.SPLIT = { default = SplitSpaces }

local function Splitter()
	local locale = _G.GetLocale and _G.GetLocale()
	return Lex.SPLIT[locale] or Lex.SPLIT.default
end

-- the last few lines read: one keystroke asks for its line several times (the reading's tokens are shared: never
-- changed by who reads them)
local CACHE_SIZE = 8
local cache, order = {}, {}

--- The line read: { line = line, toks = { token, ... } }. Never fails, whatever's half typed.
function Lex.Read(line)
	line = tostring(line or "")
	local hit = cache[line]
	if hit then return hit end
	local r = { line = line, toks = Splitter()(line) }
	if #order >= CACHE_SIZE then cache[table.remove(order, 1)] = nil end
	order[#order + 1] = line
	cache[line] = r
	return r
end

--- (tests) the lines read forgotten
function Lex.Forget() cache, order = {}, {} end

--- The reading's words and phrases, as Scan.Words gives them: the tokens' values apart from the quoted phrases' (an
--- empty phrase left out), and the phrases. New lists each time (who reads them may change them).
function Lex.Words(line)
	local words, phrases = {}, {}
	for _, t in ipairs(Lex.Read(line).toks) do
		if t.class == "quoted" then
			if t.value ~= "" then phrases[#phrases + 1] = t.value end
		else
			words[#words + 1] = t.value
		end
	end
	return words, phrases
end

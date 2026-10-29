local ns = select(2, ...)

-- Numbers, dates, levels from yours and orders said in plain words (docs/FRONT_END.md, Phase 3): the plain stage's
-- recognizers, and their word-list wrappers E.PlainNumbers and E.PlainDates. (Was PlainWords.lua, split out of Easy.lua;
-- top N and comparisons said in words: StepWords.lua; the pairs, "not" and "or": Joins.lua.)

local E = ns.Easy

----------------------------------------------------------------------
-- Numbers in plain words (0.66.5, the player): "swords between level 20 and 30", "quests under level 25", "items worth
-- more than 1g", "bags with at least 10 slots", "gear with durability below 50%" are the Advanced filters lvl:20-30,
-- lvl:<25, value:>1g, slots:>=10, dura:<50. Alt+` writes them so; the bar shows them as typed filters.
----------------------------------------------------------------------
E.NUM_FIELDS = { level = "lvl", levels = "lvl", lvl = "lvl", lvls = "lvl", ["item level"] = "ilvl", ["item levels"] = "ilvl",
	ilvl = "ilvl", itemlevel = "ilvl", worth = "value", value = "value", valued = "value", ["sells for"] = "value",
	slot = "slots", slots = "slots", durability = "dura", dura = "dura",
	-- what a spell does (0.68.8): "30 yards", "30 yard range", "range over 20", "cooldown under 10", "10 sec cooldown",
	-- "cast time under 2", "2 second cast", "costing under 100", "under 100 mana"
	range = "range", yards = "range", yard = "range", yd = "range", ["yard range"] = "range", ["yards range"] = "range",
	["yd range"] = "range", cooldown = "cd", ["sec cooldown"] = "cd", ["second cooldown"] = "cd", ["seconds cooldown"] = "cd",
	["cast time"] = "cast", ["sec cast"] = "cast", ["second cast"] = "cast", costing = "cost", cost = "cost",
	mana = "cost", rage = "cost", energy = "cost" }
-- (the fields said after the number: "10 slots", "50% durability", "30 yards", "10 sec cooldown", "100 mana")
E.NUM_AFTER = { slots = true, dura = true, range = true, cd = true, cast = true, cost = true }
E.NUM_BEFORE = { ["<"] = { "under", "below", "less than", "lower than", "fewer than", "cheaper than", "smaller than", "beneath" },
	[">"] = { "over", "above", "more than", "greater than", "higher than", "bigger than", "larger than", "pricier than" },
	[">="] = { "at least", "min", "minimum", "no less than" },
	["<="] = { "at most", "up to", "max", "maximum", "no more than" } }
E.NUM_AFTERWARDS = { [">="] = { "or more", "or higher", "or above", "or over", "and up", "and above", "or better", "plus" },
	["<="] = { "or less", "or lower", "or below", "or fewer", "or under", "and under", "and below" } }
local MONEY_WORDS = { g = "g", gold = "g", s = "s", silver = "s", c = "c", copper = "c" }

--- Reads "20", "1g", "1g50s", "1 gold 50 silver", "50%" at words[i] for a field (key): its text for the filter and how
--- many words it took; nil when it isn't one. A money amount says "money".
local function NumAt(lw, i, key)
	local w = lw[i]
	if not w then return nil end
	if key == "dura" then
		local n = w:match("^(%d+)%%?$")
		if n then return n, 1 end
		return nil
	end
	-- money: one word ("1g50s") or a number and its unit's word ("1 gold 50 silver")
	if (key == "value" or key == nil) then
		local F = ns.Filters
		if w:find("^[%d%.]+[gsc]") and F and F.Copper and F.Copper(w) then return w, 1, true end
		local n, used, text = 0, 0, ""
		while lw[i + used] and lw[i + used + 1] do
			local num, unit = lw[i + used]:match("^(%d+)$"), MONEY_WORDS[lw[i + used + 1]]
			if not (num and unit and #lw[i + used + 1] > 1) then break end
			text = text .. num .. unit
			used = used + 2
			n = n + 1
		end
		if n > 0 then return text, used, true end
		if key == nil then return nil end
	end
	local n = w:match("^(%d+)$")
	if n then return n, 1 end
	return nil
end

--- A phrase from E.NUM_BEFORE / NUM_AFTERWARDS starting at words[i]: its operator and how many words; or nil. (Each
--- list's phrases split once, by their first word: this runs for every word of every Simple search; review.)
local opIndex = {}
local function OpAt(lw, i, list)
	local idx = opIndex[list]
	if not idx then
		idx = {}
		for op, said in pairs(list) do
			for _, phrase in ipairs(said) do
				local parts = {}
				for part in phrase:gmatch("%S+") do parts[#parts + 1] = part end
				idx[parts[1]] = idx[parts[1]] or {}
				table.insert(idx[parts[1]], { op = op, parts = parts })
			end
		end
		opIndex[list] = idx
	end
	for _, c in ipairs(idx[lw[i] or ""] or {}) do
		local ok = true
		for n = 2, #c.parts do if lw[i + n - 1] ~= c.parts[n] then ok = false break end end
		if ok then return c.op, #c.parts end
	end
end

--- A field's word at words[i] (one or two words): its key and how many words; or nil.
local function FieldAt(lw, i)
	local two = lw[i + 1] and E.NUM_FIELDS[lw[i] .. " " .. lw[i + 1]]
	if two then return two, 2 end
	local one = E.NUM_FIELDS[lw[i] or ""]
	if one then return one, 1 end
end

--- "between 20 and 30", "from 20 to 30", "20 to 30", "20-30", "20+": a range at words[i] for key: its text and how many
--- words; nil when there's none.
local function SpanAt(lw, i, key)
	local w = lw[i]
	if not w then return nil end
	if (w == "between" or w == "from") and lw[i + 1] then
		local a, na = NumAt(lw, i + 1, key)
		local joiner = lw[i + 1 + (na or 0)]
		if a and (joiner == "and" or joiner == "to" or joiner == "through" or joiner == "-") then
			local b, nb = NumAt(lw, i + 2 + na, key)
			-- (money: the unit said once at the end is both ends', "between 10 and 50 silver"; review)
			if b and key == "value" and a:match("^%d+$") and b:match("[gsc]$") then a = a .. b:match("([gsc])$") end
			if b then return a .. "-" .. b, 2 + na + nb end
		end
		return nil
	end
	if key ~= "value" and (w:match("^%d+%-%d+$") or w:match("^%d+%+$")) then return w, 1 end
	local a, na = NumAt(lw, i, key)
	if a then
		local joiner = lw[i + na]
		if joiner == "to" or joiner == "through" or joiner == "-" then
			local b, nb = NumAt(lw, i + na + 1, key)
			if b and key == "value" and a:match("^%d+$") and b:match("[gsc]$") then a = a .. b:match("([gsc])$") end
			if b then return a .. "-" .. b, na + 1 + nb end
		end
	end
	return nil
end

--- After a field: "under 25", "between 20 and 30", "25 or higher", "20-30", "25": the filter's value and how many words.
local function ValueAt(lw, i, key, bare)
	local span, ns_ = SpanAt(lw, i, key)
	if span then return span, ns_ end
	local op, no = OpAt(lw, i, E.NUM_BEFORE)
	if op then
		local v, nv = NumAt(lw, i + no, key)
		if v then return op .. v, no + nv end
		return nil
	end
	local v, nv = NumAt(lw, i, key)
	if v then
		local post, np = OpAt(lw, i + nv, E.NUM_AFTERWARDS)
		if post then return post .. v, nv + np end
		-- (a number alone: that one, "level 25"; never a bare amount of money)
		if bare and key ~= "value" then return v, nv end
	end
	return nil
end

local OrderAt -- (below)
-- Dates in plain words (0.66.8, the player): "loot from yesterday", "my mail older than 20 days", "auctions sold this week",
-- "what killed me today", "in the last 3 days", "this session": since: and older: (Filters/Others.lua).
local TIME_UNITS = { minute = "m", minutes = "m", min = "m", mins = "m", hour = "h", hours = "h", hr = "h", hrs = "h",
	day = "d", days = "d", week = "w", weeks = "w" }
--- Dates at words[i]: the filter words ({ "since:yesterday", "older:today" }) and how many words; or nil.
local function DateAt(lw, i)
	local w = lw[i]
	if not w then return nil end
	local lead = 0
	if w == "from" or w == "on" then lead = 1 end -- ("from yesterday", "on yesterday's")
	local x = lw[i + lead]
	if x == "today" or x == "tonight" then return { "since:today" }, lead + 1 end
	if x == "yesterday" then return { "since:yesterday", "older:today" }, lead + 1 end
	if w == "since" then
		local y = lw[i + 1]
		if y == "yesterday" or y == "today" then return { "since:" .. y }, 2 end
		if y == "login" or (y == "i" and lw[i + 2] == "logged" and lw[i + 3] == "in") then return { "since:login" }, y == "login" and 2 or 4 end
	end
	if w == "this" then
		local y = lw[i + 1]
		if y == "week" then return { "since:week" }, 2 end
		if y == "month" then return { "since:month" }, 2 end
		if y == "session" then return { "since:login" }, 2 end
	end
	-- "last 3 days", "past 2 hours", "in the last 10 minutes", "last hour", "last week"
	local k = i
	if w == "in" and lw[i + 1] == "the" then k = i + 2 end
	-- (not a name's "the last day", "of the past hour": only "last 3 days", "in the last hour"; review)
	local before = lw[i - 1]
	if k == i and (before == "the" or before == "of" or before == "a" or before == "an") then k = nil end
	if k and (lw[k] == "last" or lw[k] == "past") then
		local n = lw[k + 1] and lw[k + 1]:match("^(%d+)$")
		local unit = TIME_UNITS[lw[k + (n and 2 or 1)] or ""]
		if unit then
			if not n and unit == "w" then return { "since:week" }, k + 2 - i end
			return { "since:" .. (n or "1") .. unit }, k + (n and 3 or 2) - i
		end
	end
	-- "older than 20 days", "more than 2 weeks old"
	if w == "older" and lw[i + 1] == "than" then
		local n = lw[i + 2] and lw[i + 2]:match("^(%d+)$")
		local unit = n and TIME_UNITS[lw[i + 3] or ""]
		if unit then return { "older:" .. n .. unit }, 4 end
		if lw[i + 2] == "yesterday" or lw[i + 2] == "today" then return { "older:" .. lw[i + 2] }, 3 end
	end
	if (w == "more" or w == "over") and (w == "over" or lw[i + 1] == "than") then
		local j = w == "over" and i + 1 or i + 2
		local n = lw[j] and lw[j]:match("^(%d+)$")
		local unit = n and TIME_UNITS[lw[j + 1] or ""]
		if unit and lw[j + 2] == "old" then return { "older:" .. n .. unit }, j + 3 - i end
	end
end

-- Levels relative to you (0.66.6, the player): "3 levels above me", "within 5 levels of me", "up to 3 levels above me",
-- "above my level", "around my level", "next level" are lvl:me+3, lvl:me-5..me+5, lvl:me..me+3, lvl:>me,
-- lvl:me-2..me+3, lvl:me+1: they move with you as you level.
local ABOVE = { above = "+", over = "+", higher = "+", below = "-", under = "-", lower = "-", beneath = "-" }
local ME = { me = 1, mine = 1, ["my level"] = 2, ["my lvl"] = 2 }
--- "me", "mine", "my level" at words[i]: how many words; or nil.
local function MeAt(lw, i)
	local two = lw[i + 1] and ME[lw[i] .. " " .. lw[i + 1]]
	if two then return 2 end
	if ME[lw[i] or ""] == 1 then return 1 end
end
--- A level relative to yours at words[i]: the lvl: value and how many words; or nil.
local function RelativeAt(lw, i)
	local w = lw[i]
	if not w then return nil end
	-- "next level"
	if w == "next" and (lw[i + 1] == "level" or lw[i + 1] == "lvl") then return "me+1", 2 end
	-- "around my level", "near my level", "about my level"
	if (w == "around" or w == "near" or w == "about") then
		local n = MeAt(lw, i + 1)
		if n == 2 then return "me-2..me+3", 1 + n end
	end
	-- "at my level", "my level" alone: yours
	if w == "at" and MeAt(lw, i + 1) == 2 then return "me", 3 end
	-- "above my level", "below my level", "higher than me", "lower than my level"
	local sign = ABOVE[w]
	if sign then
		local j = i + 1
		if lw[j] == "than" then j = j + 1 end
		local n = MeAt(lw, j)
		if n and (n == 2 or j > i + 1) then return (sign == "+" and ">me" or "<me"), j - i + n end
	end
	-- "up to 3 levels above me", "3 levels above me", "within 5 levels of me", "3 levels above my level"
	local upTo = 0
	if w == "up" and lw[i + 1] == "to" then upTo = 2 end
	local within = w == "within" and 1 or 0
	local k = i + upTo + within
	local num = lw[k] and lw[k]:match("^(%d+)$")
	if num and (lw[k + 1] == "levels" or lw[k + 1] == "level" or lw[k + 1] == "lvls") then
		if within == 1 then
			if lw[k + 2] == "of" then
				local n = MeAt(lw, k + 3)
				if n then return ("me-%s..me+%s"):format(num, num), k + 3 + n - i end
			end
			return nil
		end
		local s2 = ABOVE[lw[k + 2] or ""]
		if s2 then
			local j = k + 3
			if lw[j] == "than" then j = j + 1 end
			local n = MeAt(lw, j)
			if n then
				local v
				if upTo > 0 then v = s2 == "+" and ("me..me+" .. num) or ("me-" .. num .. "..me")
				else v = "me" .. s2 .. num end
				return v, j + n - i
			end
		end
	end
end

-- Orders in plain words (0.66.7, with top N: "my 10 most valuable items", "the cheapest linen"): the sort they say.
E.ORDER_WORDS = { ["most valuable"] = "value", ["least valuable"] = "-value", cheapest = "-value", ["most expensive"] = "value",
	priciest = "value", ["highest level"] = "-level", ["lowest level"] = "level", ["highest item level"] = "ilvl",
	["lowest item level"] = "-ilvl", ["best quality"] = "quality", ["worst quality"] = "-quality" }
--- An order's words at words[i] (up to three): the sort and how many words; or nil.
local orderFirst -- (the first words of E.ORDER_WORDS: most words start none, and are passed at once)
OrderAt = function(lw, i)
	if not orderFirst then
		orderFirst = {}
		for phrase in pairs(E.ORDER_WORDS) do orderFirst[phrase:match("^%S+")] = true end
	end
	-- ("best upgrades", "biggest upgrades": the biggest first, sort:best; 0.66.x)
	if (lw[i] == "best" or lw[i] == "biggest") and (lw[i + 1] == "upgrade" or lw[i + 1] == "upgrades") then return "best", 1 end
	if not orderFirst[lw[i] or ""] then return nil end
	for n = 3, 1, -1 do
		if lw[i + n - 1] then
			local id = E.ORDER_WORDS[table.concat(lw, " ", i, i + n - 1)]
			if id then return id, n end
		end
	end
end

-- The plain stage's recognizers (Phrase.lua; docs/FRONT_END.md Phase 3): the numbers, dates, levels from yours and
-- orders said in plain words, read at each word in this order (the first that reads one wins, the walk going on after
-- its words), each claim the filter words it stands for ("lvl:<25"; a date may be two: "since:yesterday older:today").
-- They read the line's words (Phrase.WordView: a "quoted phrase" is none of them) lowered.

--- A plain recognizer's at() from a reader: reader(lw, i) -> its filter words and how many words it took, or nil.
local function PlainAt(reader)
	return function(r, i)
		local P = ns.Phrase
		P.WordView(r)
		local wi = r.wpos[i]
		if not wi then return nil end
		local words, take = reader(r.wlow, wi)
		if not words then return nil end
		local last = r.wv[wi + take - 1]
		if not last then return nil end
		local vals = {}
		for j = wi, wi + take - 1 do vals[#vals + 1] = r.toks[r.wv[j]].value end
		-- (phrase: its words as they were joined, single spaces: what the bar took back out of the line, E.PlainNumbers' said)
		local c = { from = i, to = last, kind = "plain", words = words, phrase = table.concat(vals, " "), spec = table.concat(words, " ") }
		-- (alt: its words may be a name's instead, "Tonight We Dine", "Last Day of Summer", "Next Level Thinking": a date's
		-- or a level from yours'. UI:Search reads them as plain words when nothing had the date and a name has them)
		for _, w in ipairs(words) do
			if w:find("^since:") or w:find("^older:") or w:find("^lvl:.*me") then c.alt = "words" break end
		end
		return c
	end
end
--- (first: the words a phrase of its can start with; firstMatch: a test for the others, numbers. Only those words are
--- asked: most of a line's words start none)
local function Plain(id, priority, reader, first, firstMatch)
	ns.Phrase.Register({ id = id, stage = "plain", priority = priority, at = PlainAt(reader), first = first, firstMatch = firstMatch })
end
-- the first words of a vocabulary's phrases ("less than" -> "less"), for Plain's first
local function FirstWords(...)
	local set, out = {}, {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			local phrases = type(v) == "table" and v or { k }
			for _, ph in ipairs(phrases) do
				local w = tostring(ph):match("^(%S+)")
				if w and not set[w] then set[w] = true; out[#out + 1] = w end
			end
		end
	end
	return out
end
local function IsNumber(low) return low:find("^%d") ~= nil end

-- dates: "yesterday", "this week", "older than 20 days" (0.66.8)
Plain("dates", 70, function(lw, i) return DateAt(lw, i) end,
	{ "from", "on", "today", "tonight", "yesterday", "since", "this", "in", "last", "past", "older", "more", "over" })
-- levels from yours: "3 levels above me", "next level"
Plain("relative", 60, function(lw, i)
	local rel, nr = RelativeAt(lw, i)
	if rel then return { "lvl:" .. rel }, nr end
end, FirstWords({ next = 1, around = 1, near = 1, about = 1, at = 1, up = 1, within = 1 }, ABOVE), IsNumber)
-- an order said: "most valuable", "cheapest", "highest level" (0.66.7)
Plain("order", 50, function(lw, i)
	local so, nso = OrderAt(lw, i)
	if so then return { "sort:" .. so }, nso end
end, FirstWords(E.ORDER_WORDS, { best = 1, biggest = 1 }))
-- a field, then its value: "level under 25", "worth more than 1g", "level 20-30", "level 25 or higher"
Plain("field", 40, function(lw, i)
	local f, nf = FieldAt(lw, i)
	if not f then return nil end
	-- (a number alone after the field: only a level's, "level 25"; "slot 2" is no bag's)
	local v, nv = ValueAt(lw, i + nf, f, f == "lvl" or f == "ilvl")
	if v then return { f .. ":" .. v }, nf + nv end
end, FirstWords(E.NUM_FIELDS))
-- "between level 20 and 30", "from level 20 to 30"
Plain("between", 30, function(lw, i)
	if not (lw[i] == "between" or lw[i] == "from") then return nil end
	local f2, n2 = FieldAt(lw, i + 1)
	if not f2 then return nil end
	local copy = { lw[i] }
	for j = i + 1 + n2, #lw do copy[#copy + 1] = lw[j] end
	local v, nv = SpanAt(copy, 1, f2)
	if v then return { f2 .. ":" .. v }, nv + n2 end
end, { "between", "from" })
-- "under level 25", "at least level 10", "at least 10 slots", "more than 1g", "over 50 silver"
Plain("op", 20, function(lw, i)
	local op, no = OpAt(lw, i, E.NUM_BEFORE)
	if not op then return nil end
	local f2, n2 = FieldAt(lw, i + no)
	if f2 then
		local v, nv = NumAt(lw, i + no + n2, f2)
		if v then return { f2 .. ":" .. op .. v }, no + n2 + nv end
		return nil
	end
	local v, nv, money = NumAt(lw, i + no, nil)
	if not v then v, nv = NumAt(lw, i + no, "slots") end
	-- ("under 50% durability": a per cent, said only of durability; review)
	local pct
	if not v then v, nv = NumAt(lw, i + no, "dura"); pct = v ~= nil end
	if not v then return nil end
	local f3, n3 = FieldAt(lw, i + no + nv)
	if pct and f3 ~= "dura" then f3 = nil end
	if f3 and (E.NUM_AFTER[f3] or (f3 == "value" and money)) then return { f3 .. ":" .. op .. v }, no + nv + n3 end
	if money then return { "value:" .. op .. v }, no + nv end
end, FirstWords(E.NUM_BEFORE))
-- "10 slots or more", "10 slots", "50% durability or less"
Plain("after", 10, function(lw, i)
	local v, nv = NumAt(lw, i, "slots")
	local pct
	if not v then v, nv = NumAt(lw, i, "dura"); pct = v ~= nil end
	if not v then return nil end
	local f3, n3 = FieldAt(lw, i + nv)
	if pct and f3 ~= "dura" then f3 = nil end
	if f3 and E.NUM_AFTER[f3] then
		local post, np = OpAt(lw, i + nv + n3, E.NUM_AFTERWARDS)
		return { f3 .. ":" .. (post or "") .. v }, nv + n3 + (np or 0)
	end
end, nil, IsNumber)

--- The numbers said in plain words made filters: a new list of words (the phrase's place holding its filter, "lvl:<25"),
--- and each filter's words as typed (for the bar to take back out of the line). Words that aren't a number phrase stay.
--- (Read by the plain stage's recognizers above, over these words)
function E.PlainNumbers(words)
	local r = ns.Phrase.ReadWords(words, { simple = true, stages = { "plain" } })
	local out, said = {}, {}
	for _, u in ipairs(r.units) do
		out[#out + 1] = u.word
		if u.claim then said[u.word] = u.phrase end
	end
	return out, said
end

--- The line with only its dates said as filters ("loot today" -> "loot since:today"); the line itself when it has none.
function E.PlainDates(text)
	if type(text) ~= "string" or not text:find("%S") then return text end
	local words = {}
	for w in text:gmatch("%S+") do words[#words + 1] = w end
	-- (the dates' recognizer alone, over the line's words)
	local r = ns.Phrase.ReadWords(words, { simple = true, stages = { "plain" }, only = { dates = true } })
	if not r.plain then return text end
	local out = {}
	for _, u in ipairs(r.units) do out[#out + 1] = u.word end
	return table.concat(out, " ")
end

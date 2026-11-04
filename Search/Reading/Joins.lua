local ns = select(2, ...)

-- The join stage (docs/FRONT_END.md, Phase 3): two everyday words that mean one thing as one ("attack power"),
-- "not boe" as -boe, "sword or axe" as sword|axe; its passes, and their wrappers E.JoinPairs and E.JoinLogic.
-- Moved out of PlainWords.lua (now PlainNumbers.lua) as it was.

local E = ns.Easy

-- The join stage's passes (Phrase.lua; docs/FRONT_END.md Phase 3), over the words as the plain stage left them (a filter
-- said in words is one: "not under level 25" is -lvl:<25), in this order: the pairs, then every "not", then every "or"
-- ("rare sword or axe not boe": the "not boe" is read before the "or" looks how far its side goes).

--- The first words of E.WORDS' two-word entries ("attack" for "attack power"), made once: again for another table, or
--- once a word is added to it (E.WORDS["x y"] = ...: its metatable says so; review: a pair added later was never joined).
local pairFirst, pairOf, pairGame = nil, nil, nil
do
	local mt = getmetatable(E.WORDS)
	if not mt then mt = {}; setmetatable(E.WORDS, mt) end
	if mt.__newindex == nil then mt.__newindex = function(t, k, v) rawset(t, k, v); pairOf = nil end end
end
function E.PairFirst()
	-- (and the game's own words in the client's language, E.GameWords: "puissance d'attaque", "poder de ataque"; 0.69.6)
	local game = E.GameWords and E.GameWords() or {}
	if pairOf ~= E.WORDS or pairGame ~= game then
		pairFirst, pairOf, pairGame = {}, E.WORDS, game
		for _, t in ipairs({ E.WORDS, game }) do
			for k in pairs(t) do
				local a = type(k) == "string" and k:match("^(%S+) %S")
				if a then pairFirst[a] = true end
			end
		end
	end
	return pairFirst
end

--- Two everyday words that mean one thing joined into one ("attack power food" -> "attack power", "food").
local function JoinPairsIn(r, units)
	local i = 1
	local Low, first = ns.Phrase.Low, E.PairFirst()
	while i < #units do
		-- (only a word some pair starts with is looked at with the next)
		local pair = first[Low(units[i])] and (Low(units[i]) .. " " .. Low(units[i + 1]))
		-- (three words first: "poder de ataque", the client's name for attack power)
		local three = pair and units[i + 2] and (pair .. " " .. Low(units[i + 2]))
		if three and E.WORDS[three] then
			units[i] = ns.Phrase.Join(r, { units[i], units[i + 1], units[i + 2] }, three, "pairs")
			table.remove(units, i + 2)
			table.remove(units, i + 1)
		elseif pair and E.WORDS[pair] then
			units[i] = ns.Phrase.Join(r, { units[i], units[i + 1] }, pair, "pairs")
			table.remove(units, i + 1)
		end
		i = i + 1
	end
end
ns.Phrase.Register({ id = "pairs", stage = "join", priority = 30, pass = function(r) JoinPairsIn(r, r.units) end })

--- Two everyday words that mean one thing joined into one ("attack power food" -> "attack power", "food"). Works on
--- the list in place. (The join stage's "pairs" pass, over these words)
function E.JoinPairs(words)
	local r = ns.Phrase.ReadWords(words, { simple = true, stages = { "join" }, only = { pairs = true } })
	for k = #words, 1, -1 do words[k] = nil end
	for k, u in ipairs(r.units) do words[k] = u.word end
end

-- the join stage's "not" and "or": Simple mode's words for Advanced mode's - and |
E.NOT_WORDS = { ["not"] = true, no = true, without = true, except = true }
E.OR_WORDS = { ["or"] = true }

--- Simple mode's "or" and "not" in words, made into F.Parse's - | &: "not boe" / "without cloth" -> "-boe", "-cloth";
--- "sword or axe" -> "sword|axe"; "rare sword or rare axe" -> "rare&sword|rare&axe": the words after "or" (up to the
--- next "or" or a "not") are one side, and as many words before it the other (a side already joined stands alone), so "rare
--- sword or axe" keeps rare for both. A "not"/"or" with nothing to join stays a word. Works on the list in place.
local function JoinNotIn(r, units)
	local i = 1
	while i < #units do -- not first: "sword or not boe" = sword|-boe
		local w2 = units[i + 1].word
		local lw, nw = ns.Phrase.Low(units[i]), ns.Phrase.Low(units[i + 1])
		-- (first, it's a "not" only before an everyday word or a filter, "without cloth", "not boe": else a name's own
		-- first word, "No Rest for the Wicked", "Without a Trace"; review, 0.53.6)
		local leads = i > 1 or E.WORDS[nw] ~= nil or E.IsAdvancedWord(w2)
		if E.NOT_WORDS[lw] and leads and not E.OR_WORDS[nw] and not E.NOT_WORDS[nw] then
			units[i] = ns.Phrase.Join(r, { units[i], units[i + 1] }, "-" .. w2, "not")
			table.remove(units, i + 1)
		end
		i = i + 1
	end
end

local function JoinOrIn(r, units)
	local i = 2
	while i < #units do
		if E.OR_WORDS[ns.Phrase.Low(units[i])] then
			local stop = i + 1
			-- (a "not" after it is for the whole search: "rare sword or axe not boe"; any language's letter after the -,
			-- 0.49.2, review: "-малое" too)
			while stop + 1 <= #units and not E.OR_WORDS[ns.Phrase.Low(units[stop + 1])] and not units[stop + 1].word:find("^[-!][%a\128-\255]") do
				stop = stop + 1
			end
			local n = stop - i
			local from = i - 1
			if not units[from].word:find("|", 1, true) then
				while from > 1 and i - from < n and not units[from - 1].word:find("|", 1, true) do from = from - 1 end
			end
			local lefts, rights, parts = {}, {}, {}
			for k = from, i - 1 do lefts[#lefts + 1] = units[k].word end
			for k = i + 1, stop do rights[#rights + 1] = units[k].word end
			for k = from, stop do parts[#parts + 1] = units[k] end
			local u = ns.Phrase.Join(r, parts, table.concat(lefts, "&") .. "|" .. table.concat(rights, "&"), "or")
			for _ = from, stop do table.remove(units, from) end
			table.insert(units, from, u)
			i = from + 1
		else
			i = i + 1
		end
	end
end
-- A state said in a sentence (1.0.46, the reach audit: "quests i haven't done" read is:done, the opposite): "haven't",
-- "not", "never", "not yet" before a state word (done, completed, finished, earned, learned, known, ready...)
-- turn it round, and the sentence's own words around it go ("i have", "you", "yet" after it): "quests i haven't done" ->
-- -done, "quests not yet done" -> -done, "quests i have done" -> done; "mail i haven't read" -> unread.
local STATE_NOT = { ["not"] = true, never = true, ["haven't"] = true, havent = true, ["hasn't"] = true, hasnt = true,
	["didn't"] = true, didnt = true, ["havn't"] = true, havnt = true }
local STATE_HAVE = { have = true, has = true, had = true, ["i've"] = true, ive = true, ["we've"] = true, ["you've"] = true }
local STATE_WHO = { i = true, you = true, we = true }
local STATE_ONLY_NOT = { read = "unread" } -- (a word that is a state only turned round: "haven't read" is unread)
local function StateOf(lw)
	local spec = E.WORDS[lw]
	if type(spec) == "string" and spec:find("^%-?is:") then return true end
	return STATE_ONLY_NOT[lw] ~= nil
end
-- (a state word that is already turned round, "undone" -> -is:done, turned round again: the word for is:done,
-- "done", not "--is:done"; review, 1.0.66)
local positiveOf = {}
local function Positive(lw)
	local spec = E.WORDS[lw]
	if type(spec) ~= "string" or not spec:find("^%-is:") then return nil end
	local want = spec:sub(2)
	local got = positiveOf[want]
	if got == nil then
		got = false
		for k, v in pairs(E.WORDS) do
			if v == want and not k:find(" ", 1, true) and (not got or #k < #got) then got = k end
		end
		positiveOf[want] = got
	end
	return got or nil
end
local function JoinStateIn(r, units)
	local Low = ns.Phrase.Low
	local i = 1
	while i <= #units do
		local lw = Low(units[i])
		if StateOf(lw) then
			local from, neg, j = i, false, i - 1
			if j >= 1 and Low(units[j]) == "yet" then j = j - 1 end
			if j >= 1 and STATE_NOT[Low(units[j])] then neg, from, j = true, j, j - 1 end
			if j >= 1 and STATE_HAVE[Low(units[j])] then from, j = j, j - 1 end
			-- ("i" before a state said in two words, "i don't know": the sentence's too; 1.0.54)
			if j >= 1 and STATE_WHO[Low(units[j])] and (from < i or lw:find(" ", 1, true)) then from = j end
			local to = i
			if units[i + 1] and Low(units[i + 1]) == "yet" and (neg or from < i) then to = i + 1 end
			local only = STATE_ONLY_NOT[lw]
			if (from < i or to > i) and not (only and not neg) then
				local pos = neg and Positive(lw)
				local word = only or pos or ((neg and "-" or "") .. units[i].word)
				local parts = {}
				for k = from, to do parts[#parts + 1] = units[k] end
				local u = ns.Phrase.Join(r, parts, word, "not")
				for _ = from, to do table.remove(units, from) end
				table.insert(units, from, u)
				i = from
			end
		end
		i = i + 1
	end
end
ns.Phrase.Register({ id = "notstate", stage = "join", priority = 25, pass = function(r) JoinStateIn(r, r.units) end })
ns.Phrase.Register({ id = "not", stage = "join", priority = 20, pass = function(r) JoinNotIn(r, r.units) end })
ns.Phrase.Register({ id = "or", stage = "join", priority = 10, pass = function(r) JoinOrIn(r, r.units) end })

--- (The join stage's "not" and "or" passes, over these words, in place)
function E.JoinLogic(words)
	local r = ns.Phrase.ReadWords(words, { simple = true, stages = { "join" }, only = { ["not"] = true, ["or"] = true } })
	for k = #words, 1, -1 do words[k] = nil end
	for k, u in ipairs(r.units) do words[k] = u.word end
	return words
end

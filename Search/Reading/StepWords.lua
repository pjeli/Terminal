local ns = select(2, ...)

-- The steps said in plain words (docs/FRONT_END.md, Phase 2): top N ("the 3 nearest mailboxes") and comparing with
-- one of your lists ("but not in my bank"), the steps stage's recognizers, and their wrappers E.TopN and E.SetOp.
-- Moved out of PlainWords.lua (now PlainNumbers.lua) as it was.

local E = ns.Easy
local Lower = ns.Lower

-- Top N in plain words (0.66.7, the player): "the 3 nearest mailboxes", "top 5 upgrades", "my 10 most valuable items",
-- "5 swords" (the first five by how well they match), "the closest innkeeper" (one). The number beside a ranking word,
-- or opening the line; not one that's part of the search ("3 stacks of linen", "10 slot bag", "level 20 swords").
E.NUMBER_WORDS = { one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
	eleven = 11, twelve = 12, fifteen = 15, twenty = 20, fifty = 50, hundred = 100 }
E.RANK_WORDS = { nearest = true, closest = true, farthest = true, furthest = true, cheapest = true, best = true,
	priciest = true, most = true, least = true, highest = true, lowest = true, newest = true, oldest = true, biggest = true }
-- (a number followed by these is part of the search: an amount, a level, a time)
E.NOT_COUNTED = { stack = true, stacks = true, x = true, of = true, slot = true, slots = true, level = true, levels = true,
	gold = true, silver = true, copper = true, g = true, s = true, c = true, percent = true, ["%"] = true, durability = true,
	day = true, days = true, hour = true, hours = true, minute = true, minutes = true, week = true, weeks = true,
	month = true, months = true, ago = true, to = true, ["and"] = true, ["or"] = true, handed = true, hand = true,
	piece = true, pieces = true, point = true, points = true, yards = true, yard = true, yd = true, yds = true }
local TOP_LEAD = { the = true, my = true }
E.NOT_A_NOUN = { of = true, ["and"] = true, ["or"] = true, the = true, a = true, an = true, ["in"] = true, on = true, to = true,
	["for"] = true, with = true, at = true, by = true, from = true }
-- (an order's own words before the thing: "most valuable", "highest level", "best quality")
E.ORDER_ADJ = { valuable = true, expensive = true, level = true, quality = true, priced = true, item = false }
-- (one thing, named as a pair: "the cheapest boots" is one pair of boots)
E.ONE_PAIR = { boots = true, gloves = true, leggings = true, bracers = true, pants = true, trousers = true, shoulders = true,
	gauntlets = true, greaves = true, sabatons = true, handwraps = true, wristguards = true, spaulders = true, legguards = true,
	treads = true, slippers = true, sandals = true, britches = true, breeches = true, kilts = true, mitts = true, bindings = true }
--- The top N said at the start of these tokens (the search's, before any send): a claim { from, to = the tokens taken
--- out, n, rest = the line without them (its words joined by single spaces; a count of places "nearest" first), prefix
--- = "nearest " when put first }, one that keeps its words ("the closest innkeeper": one, keep = true), or nil.
--- r is the reading (Phrase.lua); W its tokens to look at.
local function TopOf(r, W)
	if #W < 2 then return nil end
	local P = ns.Phrase
	local function lw(k) return W[k] and P.LowText(r, W[k].i) or nil end
	local function Num(w) return tonumber(w and w:match("^(%d+)$") or "") or (w and E.NUMBER_WORDS[w]) end
	-- (a number said in words only beside a ranking word, "the three nearest": "the five sorrows", "two halves become
	-- one" are names; review)
	local function NumOpening(k)
		local d = tonumber(lw(k) and lw(k):match("^(%d+)$") or "")
		if d then return d end
		local w = lw(k) and E.NUMBER_WORDS[lw(k)]
		if w and E.RANK_WORDS[lw(k + 1) or ""] then return w end
	end
	local function Rest(from, skip)
		local out = {}
		for k = 1, #W do if k < from or k >= from + skip then out[#out + 1] = W[k].text end end
		return table.concat(out, " ")
	end
	-- (a count of places, "2 mailboxes", "top 3 flight masters": the nearest ones, what else a count of them means)
	local function Placed(rest)
		local I = ns.Integrations
		local ws = {}
		for w in Lower(rest):gmatch("%S+") do if not TOP_LEAD[w] then ws[#ws + 1] = w end end
		for _, w in ipairs(ws) do if E.RANK_WORDS[w] then return rest end end
		if I and I.ObjectKind and I.ObjectKind(ws) then return "nearest " .. rest, "nearest " end
		return rest
	end
	local function Claim(from, skip, n, placed)
		local rest, prefix = Rest(from, skip), nil
		if placed then rest, prefix = Placed(rest) end
		return { from = W[from].i, to = W[from + skip - 1].i, kind = "top", n = math.min(n, 100), rest = rest, prefix = prefix,
			spec = "| first " .. math.min(n, 100) }
	end
	local i = 1
	if TOP_LEAD[lw(1)] then i = 2 end
	-- "nearest 3 mailboxes", "closest 5 innkeepers": the number after the ranking word
	if E.RANK_WORDS[lw(i) or ""] and lw(i + 1) and lw(i + 2) then
		local d = Num(lw(i + 1))
		if d and d >= 1 and not E.NOT_COUNTED[lw(i + 2)] and lw(i + 2):match("^[%a\128-\255]") then
			return Claim(i + 1, 1, d)
		end
	end
	local n = NumOpening(i)
	-- "top 5 upgrades", "first 3 quests"
	if not n and (lw(i) == "top" or lw(i) == "first") and Num(lw(i + 1)) and lw(i + 2) then
		n = Num(lw(i + 1))
		if n < 1 or E.NOT_COUNTED[lw(i + 2)] then return nil end -- ("top 0 swords": no count; review)
		return Claim(i, 2, n, true)
	end
	if n then
		local nxt = lw(i + 1)
		-- (a word must follow: "3 + 4" is a sum, "2 handed swords" a kind of sword)
		if not nxt or E.NOT_COUNTED[nxt] or not nxt:match("^[%a\128-\255]") then return nil end
		-- (opening the line, or after "the" / "my": "5 swords", "the 3 nearest mailboxes", "my 10 most valuable items")
		if n < 1 then return nil end
		return Claim(i, 1, n, true)
	end
	-- "the closest innkeeper", "the cheapest linen": one ("the cheapest upgrades on the ah", plural: all of them)
	if lw(1) == "the" and E.RANK_WORDS[lw(2)] and lw(3) then
		-- (the thing named: past the order's own words, "the most valuable items", "the highest level sword")
		local k = 3
		while lw(k + 1) and (E.RANK_WORDS[lw(k)] or E.ORDER_ADJ[lw(k)]) do k = k + 1 end
		local noun = lw(k)
		if noun:find("[^s]s$") and not E.ONE_PAIR[noun] then return nil end
		-- (no thing named: "the best of both worlds" is a name; review)
		if E.NOT_A_NOUN[noun] then return nil end
		return { from = W[1].i, to = W[2].i, keep = true, kind = "top", n = 1, spec = "| first 1" }
	end
	return nil
end

--- Is there a "|" standing alone among the search's tokens? (Steps typed: no top N or comparison in words.)
local function PipeIn(r)
	for k = 1, r.sendEnd - 1 do
		local t = r.toks[k]
		if not r.taken[k] and t.class == "op" and t.text == "|" then return true end
	end
	return false
end

-- the top N in words, at the start of the search (Simple mode): "the 3 nearest mailboxes", "top 5 upgrades", "the
-- closest innkeeper"; not with steps typed ("| first 3" is the step itself)
ns.Phrase.Register({ id = "top", stage = "steps", priority = 20,
	at = function(r, i)
		if i ~= 1 or PipeIn(r) then return nil end
		return TopOf(r, ns.Phrase.Free(r, r.sendEnd))
	end })

--- The line with its top N taken out, and N; or the line and nil. "the 3 nearest mailboxes" -> "the nearest mailboxes", 3.
--- (Read as the top recognizer reads it: TopOf, over the line's own tokens)
function E.TopN(text)
	if type(text) ~= "string" then return text, nil end
	local r = { line = text, toks = ns.Lex.Read(text).toks }
	local c = TopOf(r, r.toks)
	if not c then return text, nil end
	if c.keep then return text, 1 end
	return c.rest, c.n
end

-- Comparing two searches in plain words (0.66.10): "mats on my alts but not on me", "cloth except my bank", "linen
-- plus my alts": the second is one of your own lists, said at the end.
E.LIST_PHRASES = { ["my bank"] = "@bank", ["in my bank"] = "@bank", ["the bank"] = "@bank", ["my bags"] = "@item in:bags",
	["in my bags"] = "@item in:bags", ["on me"] = "@item in:bags", ["my alts"] = "@stored", ["on my alts"] = "@stored",
	["my quest log"] = "@quest", ["in my log"] = "@quest", ["my log"] = "@quest", ["my mail"] = "@mail", ["in my mail"] = "@mail",
	-- (said without "my": "linen not in bank" read -in and the banker role, the player's call; FRONT_END.md 10.7)
	["in bank"] = "@bank", ["in the bank"] = "@bank", ["in bags"] = "@item in:bags", ["in the bags"] = "@item in:bags",
	["on alts"] = "@stored", ["on the alts"] = "@stored", ["in my quest log"] = "@quest", ["in the quest log"] = "@quest",
	["in the log"] = "@quest", ["in mail"] = "@mail", ["in the mail"] = "@mail" }
local SET_EXCEPT = { "but not", "and not", "except", "not" }
local SET_ALSO = { "and also", "plus" }
local setTails -- { [the tail's words, "but not in my bank"] = "except @bank" }, made once
local SET_LAST = { bank = true, bags = true, me = true, alts = true, log = true, mail = true }
E.ALONE_BASE = "@item" -- (a comparison said alone, "not in my bank": what it's taken from)
local function SetTails()
	if not setTails then
		setTails = {}
		for phrase, list in pairs(E.LIST_PHRASES) do
			for _, group in ipairs({ { SET_EXCEPT, "except" }, { SET_ALSO, "also" } }) do
				for _, joiner in ipairs(group[1]) do setTails[joiner .. " " .. phrase] = group[2] .. " " .. list end
			end
		end
	end
	return setTails
end

--- A comparison said at the end of these tokens, starting at W[k]: its step ("except @bank"), or nil. Only a line
--- ending in one of the lists' last words can have one; the earliest start is the longest tail ("but not in my bank",
--- not "not in my bank").
local function SetOpAt(r, W, k)
	local P = ns.Phrase
	local n = #W
	if n == 0 or not SET_LAST[P.LowText(r, W[n].i)] then return nil end
	local ws = {}
	for j = k, n do ws[#ws + 1] = P.LowText(r, W[j].i) end
	return SetTails()[table.concat(ws, " ")]
end

--- May this comparison be said alone ("not in my bank", "not on my alts": your items but that list's, the player's call;
--- FRONT_END.md 10.7)? Only a leaving out, and not your quest log's: no list of items is it.
local function Alone(step)
	return step:find("^except ") ~= nil and not step:find("@quest", 1, true)
end

-- a comparison said at the end of the search (Simple mode): "cloth but not in my bank", "linen plus my alts"; with
-- something before it (the top N's words gone don't count, its "nearest" does), and not with steps typed
ns.Phrase.Register({ id = "setop", stage = "steps", priority = 10,
	first = { "but", "and", "except", "not", "plus" }, -- (SET_EXCEPT's and SET_ALSO's joiners' first words)
	at = function(r, i)
		local last = r.toks[r.sendEnd - 1]
		if not (last and SET_LAST[ns.Phrase.LowText(r, last.i)]) or PipeIn(r) then return nil end
		local W = ns.Phrase.Free(r, r.sendEnd)
		local k
		for j, t in ipairs(W) do if t.i == i then k = j end end
		if not k then return nil end
		local step = SetOpAt(r, W, k)
		if not step then return nil end
		if k == 1 and not (r.top and r.top.prefix) then
			-- (said alone: before, "not" was a word and "bank" the banker role)
			if not Alone(step) then return nil end
			return { from = i, to = W[#W].i, kind = "setop", step = step, spec = "| " .. step, base = E.ALONE_BASE }
		end
		return { from = i, to = W[#W].i, kind = "setop", step = step, spec = "| " .. step }
	end })

--- The line with a comparison at its end taken out, and its step ("except @bank"); or the line and nil. Said alone,
--- what it's taken from: "not in my bank" -> "@item", "except @bank".
--- (Read as the setop recognizer reads it: SetOpAt, over the line's own tokens; the line as typed, its last words gone:
--- "Hogger but not in my bank" keeps "Hogger"; review)
function E.SetOp(text)
	if type(text) ~= "string" then return text, nil end
	local r = { line = text, toks = ns.Lex.Read(text).toks }
	for k = 1, #r.toks do
		local step = SetOpAt(r, r.toks, k)
		if step and k == 1 then
			if Alone(step) then return E.ALONE_BASE, step end
			return text, nil
		elseif step then
			return (text:sub(1, r.toks[k].s - 1):gsub("%s+$", ""):gsub("^%s+", "")), step
		end
	end
	return text, nil
end

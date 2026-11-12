local ns = select(2, ...)
local L = ns.L

-- Running a chain: `a > b > c` split into its parts, each relation run on the rows before it, the phrases that mean a
-- chain in plain words, and `.chains`. The rows and relations are Chains.lua's and ChainLearn.lua's, loaded just before
-- this (1.4.2: one file until then).

local P = ns.Pipes
local Pressed = ns.Bags.Pressed
local SimpleOn, Entries, ItemOf, ItemName, Icon = P._.SimpleOn, P._.Entries, P._.ItemOf, P._.ItemName, P._.Icon
local REAGENT_LABEL, ShowItem = P._.REAGENT_LABEL, P._.ShowItem

----------------------------------------------------------------------
-- Running a chain
----------------------------------------------------------------------

local function Id(e)
	local k = rawget(e, "key")
	if k == nil then
		-- (a view, View's or NearSaid's: the row it shows and how it was found)
		local mt = getmetatable(e)
		local base = mt and type(mt.__index) == "table" and mt.__index or nil
		k = base and rawget(base, "key")
		if k == nil then return e end
		return tostring(base.kind) .. ":" .. tostring(k) .. "|" .. tostring(rawget(e, "pipeHow") or "")
	end
	return tostring(e.kind) .. ":" .. tostring(k)
end
P.Id = Id -- (tests)

--- The rows a relation gives for these, each once.
function P.Run(name, rows)
	local out, seen = {}, {}
	for _, def in ipairs(P.relations[name] or {}) do
		local mine = {}
		for _, e in ipairs(rows) do
			if def.applies(e) then mine[#mine + 1] = e end
		end
		if #mine > 0 then
			local ok, res = pcall(def.run, mine)
			if not ok then
				ns:Trace("chain " .. name .. " failed: " .. tostring(res))
			elseif type(res) == "table" then
				for _, r in ipairs(res) do
					local id = Id(r)
					if type(r.name) == "string" and r.name ~= "" and not seen[id] then
						seen[id] = true
						out[#out + 1] = r
						if #out >= P.MAX_OUT then break end
					end
				end
			end
		end
	end
	return out
end

--- The relations some of these rows can go through: { name, desc }.
function P.Applicable(rows)
	local out = {}
	for _, name in ipairs(P.order) do
		local desc
		for _, def in ipairs(P.Available(name) and P.relations[name] or {}) do
			for _, e in ipairs(rows) do
				if def.applies(e) then desc = def.desc break end
			end
			if desc then break end
		end
		if desc then out[#out + 1] = { name, desc } end
	end
	return out
end

local function Tokens(text)
	local t = {}
	for w in ns.Lower(text or ""):gmatch("%S+") do t[#t + 1] = w end
	return t
end

-- a row's name score for every word (nil: some word doesn't match), its lowercase name, and whether every word is in
-- it as typed (not only its letters scattered: "core" is in "Comfortable", c-o-r-e)
local function NameScore(e, tokens)
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	local sum, whole = 0, true
	for _, tk in ipairs(tokens) do
		local s, sub = ns.Fuzzy.score(tk, ln, ln)
		if not s then return nil end
		sum = sum + s
		-- (an apostrophe left out still counts: "agamaggans clutch")
		if not sub and tk:find("'", 1, true) == nil and ln:find("'", 1, true) then
			sub = ln:gsub("'", ""):find(tk, 1, true) ~= nil
		end
		whole = whole and (sub and true or false)
	end
	return sum, ln, whole
end

-- (the recipes you don't know last: "where to learn anvil", a recipe AtlasLoot doesn't list)
P.SEED_KINDS = { "recipes", "items", "loot", "stored", "missing" }

P.CHOICES = 8 -- (names offered when the words fit several)

-- The last seed's look, for the next keystroke: { gen, kinds, tokens, cands = the rows whose names had every word,
-- filters aside, in order }. One more letter or word only narrows those (a name with the new words had the old ones),
-- so while the same lists stand (none rebuilt since) the next look goes over them alone.
local lastSeed

-- one more letter on the last word, or one more word
local function Grew(last, tokens)
	local n, ln = #tokens, #last
	if ln == 0 or (n ~= ln and n ~= ln + 1) then return false end
	for i = 1, ln do
		local a, b = last[i], tokens[i]
		if (i < n and a ~= b) or (i == n and b:sub(1, #a) ~= a) then return false end
	end
	return true
end

-- the last look's rows when they can stand for these lists and words; nil: look at every row
local function SeedFrom(kinds, tokens)
	local last = lastSeed
	if not (last and last.gen == ns.entriesGen and #last.kinds == #kinds and Grew(last.tokens, tokens)) then return nil end
	for k, kind in ipairs(kinds) do
		if last.kinds[k] ~= kind then return nil end
		local p = ns.providers[kind]
		if p and (p._dirty or not p._entries) then return nil end -- (to be collected again: its rows may change)
	end
	for _, kind in ipairs(kinds) do Entries(kind) end -- (read as the whole look reads them: nothing to collect)
	if last.gen ~= ns.entriesGen then return nil end -- (reading one rebuilt it: a list made from another)
	return last.cands
end

-- The typed words: the lists an @kind picks (else P.SEED_KINDS), the key:value filters, and the name's words
-- (lowercase), alone and joined.
local function SeedParse(text, seedKinds, alsoKinds)
	local kinds, filters, words = {}, {}, {}
	for w in (text or ""):gmatch("%S+") do
		if w:sub(1, 1) == "@" and #w > 1 then
			-- (as the search reads an @kind: its id, an alias or the start of its id)
			local p = ns:ResolveProvider(w:sub(2))
			if p then kinds[#kinds + 1] = p.id else words[#words + 1] = w end
		else
			local f = (w:find("[:|]") or w:find("^[-!][%a\128-\255]")) and ns.Filters and ns.Filters.Parse(w) -- ("-малое")
			if f then filters[#filters + 1] = f else words[#words + 1] = w end
		end
	end
	if #kinds == 0 then
		kinds = seedKinds or P.SEED_KINDS
		if alsoKinds then
			local all = {}
			for _, k in ipairs(kinds) do all[#all + 1] = k end
			for _, k in ipairs(alsoKinds) do all[#all + 1] = k end
			kinds = all
		end
	end
	local tokens = Tokens(table.concat(words, " "))
	local whole = table.concat(tokens, " ")
	return kinds, filters, tokens, whole
end

-- a name's words without a leading article ("the black book" -> "black book"): the plain words drop it ("mats for the
-- black book" asks for "black book > mats"), so a name with one is exact without it too
local function Bare(ln)
	return ln:match("^the (.+)$") or ln:match("^an? (.+)$")
end

-- The rows of those lists whose names have the words and that pass the filters: the exact names (else those exact
-- but for a leading article), those with every word in the name as typed ({ row, score, lowercase name }), and the
-- closest of the rest; with no words, every row that passes. `from`: the last look's rows, standing for every list
-- (SeedFrom). Also gives the rows whose names had the words (filters aside), for the next keystroke.
local function SeedScan(kinds, filters, tokens, whole, from)
	local all, exact, exactBare = {}, {}, {}
	local subs, near, nearS = {}, nil, nil -- (every word in the name as typed; the closest of the rest)
	local wantAll = #tokens == 0
	local cands = {}
	-- (run in the spread-out search's coroutine: AtlasLoot's thousands of rows go over several frames, UI:RunSearch)
	local UI, n = ns.UI, 0
	local slicing = UI and UI.sliceUntil and coroutine.running() and debugprofilestop
	for k = 1, from and 1 or #kinds do
		for _, e in ipairs(from or Entries(kinds[k])) do
			n = n + 1
			if slicing and n % 64 == 0 and UI.sliceUntil and debugprofilestop() > UI.sliceUntil then coroutine.yield(UI.Results()) end
			local s, ln, typed = 0, nil, false
			if not wantAll then s, ln, typed = NameScore(e, tokens) end
			-- (help lines left out: asked only of a match, compact rows answer these through their metatable)
			if s and not (e.noActivate or e.raw) then
				if not wantAll then cands[#cands + 1] = e end
				do
					local ok = true
					for _, f in ipairs(filters) do
						local okF, yes = pcall(f, e)
						if not (okF and yes) then ok = false break end
					end
					if ok then
						if wantAll then all[#all + 1] = e
						elseif typed then subs[#subs + 1] = { e, s, ln }
						elseif not nearS or s > nearS then near, nearS = e, s end
						if ln and ln == whole then exact[#exact + 1] = e
						elseif ln and typed and Bare(ln) == whole then exactBare[#exactBare + 1] = e end
					end
				end
			end
		end
	end
	return all, #exact > 0 and exact or exactBare, subs, near, cands
end

-- each item once (a recipe and the item it makes are one), at most MAX_LEFT
local function Once(list)
	local out, seen = {}, {}
	for _, e in ipairs(list) do
		local id = ItemOf(e) or Id(e)
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = e
			if #out >= P.MAX_LEFT then break end
		end
	end
	return out
end

-- reagent rows for the items known by exactly this (lowercase) name: your recipes' reagents, else Questie's items (your
-- recipes' reagents by lowercase name, made once per recipes list: every keystroke whose words matched no name read
-- every reagent's name again; made again while some names are still coming.)
local reagents = { list = nil, byName = nil, whole = false }
local function ReagentIds(whole)
	local list = Entries("recipes")
	if reagents.list ~= list or not reagents.whole then
		local byName, all, seen = {}, true, {}
		for _, r in ipairs(list) do
			for _, rg in ipairs(r.reagents or {}) do
				local id = rg[1]
				if type(id) == "number" and not seen[id] then
					local n = ItemName(id)
					if n then
						seen[id] = true
						local ln = ns.Lower(n)
						byName[ln] = byName[ln] or {}
						table.insert(byName[ln], id)
					else
						all = false
					end
				end
			end
		end
		reagents.list, reagents.byName, reagents.whole = list, byName, all
	end
	return reagents.byName[whole]
end

local function SeedByReagentName(whole)
	local out = {}
	local ids = ReagentIds(whole) or {}
	if #ids == 0 and ns.Filters and ns.Filters.QuestieItemIds then ids = ns.Filters.QuestieItemIds(whole) end
	for _, id in ipairs(ids) do
		out[#out + 1] = Pressed({ key = id, kind = "reagent", kindLabel = REAGENT_LABEL, name = ItemName(id) or whole,
			itemID = id, link = "item:" .. id, icon = Icon(id) }, ShowItem)
	end
	return out
end

-- one name (a recipe and the item it makes are one): its rows; several: which one?
local function SeedChoices(subs)
	local byName, names = {}, {}
	for _, m in ipairs(subs) do
		local g = byName[m[3]]
		if not g then g = { rows = {}, s = m[2] }; byName[m[3]] = g; names[#names + 1] = m[3] end
		g.rows[#g.rows + 1] = m[1]
		if m[2] > g.s then g.s = m[2] end
	end
	if #names == 1 then return Once(byName[names[1]].rows) end
	table.sort(names, function(a, b)
		if byName[a].s ~= byName[b].s then return byName[a].s > byName[b].s end
		return a < b
	end)
	local choices = {}
	for i = 1, math.min(#names, P.CHOICES) do choices[i] = byName[names[i]].rows[1] end
	choices.total = #names
	return {}, nil, choices
end

--- Where a chain starts: rows of your recipes, bags, AtlasLoot and alts whose names have the words (an @kind picks the
--- lists, key:value filters narrow them). An exact name keeps only those rows (or "mats for thorium belt" would add up
--- every belt); else the one name that has every word as typed; with only filters typed, every row that passes. Never a
--- guess: no name with every word -> {} and the closest name (second result); several -> {} and those names to pick
--- from (third result: rows, best first); `applies` (a row -> whether the link can go on from it) keeps, of several
--- names, those it can, when some can. `alsoKinds`: lists looked in as well as the usual ones (a relation's other
--- definitions' own: "fireball > learn" looks in What's Training's spells too, P.AlsoSeeds).
function P.Seed(text, seedKinds, alsoKinds, applies)
	local kinds, filters, tokens, whole = SeedParse(text, seedKinds, alsoKinds)
	local from = SeedFrom(kinds, tokens)
	local gen = ns.entriesGen
	local all, exact, subs, near, cands = SeedScan(kinds, filters, tokens, whole, from)
	-- (for the next keystroke: not when a list was rebuilt meanwhile, the rows looked at may be its old ones)
	lastSeed = #tokens > 0 and gen == ns.entriesGen and { gen = gen, kinds = kinds, tokens = tokens, cands = cands } or nil
	if #exact > 0 then return Once(exact) end
	-- nothing of yours by that name: an item the game or Questie knows by exactly that name (a reagent you don't
	-- carry: "where to get copper ore")
	if #subs == 0 and #all == 0 and whole ~= "" and not seedKinds then
		local out = SeedByReagentName(whole)
		-- (the phrase took a leading article off, "where to get the collector's ring": a name may begin with one)
		for _, a in ipairs(#out == 0 and P.ARTICLES or {}) do
			out = SeedByReagentName(a .. whole)
			if #out > 0 then break end
		end
		if #out > 0 then return Once(out) end
	end
	if #tokens == 0 then return Once(all) end -- (only filters typed: every row that passes)
	if #subs == 0 then return {}, near end
	-- (the names the chain's link can go on from, when some can: "where to learn dagger" is the Daggers weapon skill,
	-- not a pick among every dagger AtlasLoot knows)
	if applies and #subs > 1 then
		local fit = {}
		for _, m in ipairs(subs) do if applies(m[1]) then fit[#fit + 1] = m end end
		if #fit > 0 then subs = fit end
	end
	return SeedChoices(subs)
end

-- what walking on from a row means: a reagent -> where to get it; a recipe or crafted item -> its mats
local function NextOf(e, from)
	if e.kind == "reagent" then return "sources" end
	if e.kind == "attune" then return nil end -- (Attune's steps open Attune: an item step isn't walked on to its mats)
	if from ~= "mats" and P.Reagents(e) then return "mats" end
end

local function Walk(v)
	local UI = ns.UI
	local t = v.pipeChain
	-- (Simple mode: the next step in its own words, "where to get Thorium Bar", never a ">" chain)
	if SimpleOn() and v.pipeName and P.SIMPLE[v.pipeNext] then t = P.Phrase(v.pipeName, v.pipeNext) end
	UI:WalkTo(t, v) -- (the step before kept: Shift+Left goes back to it)
end
local function Opens(v, ...)
	local o = v.pipeOf
	if o and o.activate then return o.activate(o, ...) end
end

--- A row as a chain shows it: Enter walks on (when there's a step), Shift+Enter does the row's own Enter.
function P.WalkView(e, chain, from)
	local nxt = NextOf(e, from)
	if not nxt then return e end
	local name = type(e.name) == "string" and e.name:gsub("%s+x%d+$", "") or ""
	return setmetatable({
		pipeChain = chain .. " " .. name .. " > " .. nxt, pipeNext = nxt, pipeOf = e, pipeName = name,
		activate = Walk, staysOpen = true, secure = false, isOpen = false, after = false,
		secondary = Opens, secondarySecure = e.secure or false, secondaryIsOpen = e.isOpen or false,
		secondaryAfter = e.after or false, secondaryStaysOpen = false,
	}, { __index = e })
end

local function Line(text) return { name = text, kind = "pipe", noActivate = true, raw = true, _score = 1e12 } end
local function PickRelation(e) local UI = ns.UI UI:WalkTo(e.completion, e) end -- (Shift+Left: back to the choices)

-- each part's rows, by the chain up to it: typing on in the last part doesn't redo the ones before it (kept while
-- no list was rebuilt and nothing was still loading; at most STEPS_MAX, then it starts over: a key a letter typed)
P.STEPS_MAX = 64
local stepCache, stepGen, stepCount = {}, -1, 0
local function Cached(key) if stepGen == ns.entriesGen then return stepCache[key] end end
local function Keep(key, rows)
	-- (an item name, or data a filter reads, still loading: the answer is short; the search runs again once it's in)
	if P.loading or (ns.Filters and ns.Filters.loading) then return end
	if stepGen ~= ns.entriesGen then stepCache, stepGen, stepCount = {}, ns.entriesGen, 0 end
	if stepCache[key] == nil then
		if stepCount >= P.STEPS_MAX then stepCache, stepCount = {}, 0 end
		stepCount = stepCount + 1
	end
	stepCache[key] = rows
end
P.ClearSteps = function() stepCache, stepGen, stepCount, lastSeed = {}, -1, 0, nil end

--- What a link's rows came from, for chat: the one row passed on ("Thorium Belt"), else the first part as typed
--- (several rows: "copper" -> "Copper"; its @kind and filters left out); nil when neither says.
function P.FromName(left, typed)
	if #left == 1 and type(left[1].name) == "string" then
		local n = ns.Plain(left[1].name):gsub("%s+x%d+$", "")
		if n ~= "" then return n end
	end
	if type(typed) ~= "string" then return nil end
	local t = typed:gsub("@%S+", ""):gsub("%S+:%S*", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if t == "" then return nil end
	return ns.Titled(t)
end

-- "Keep typing" while the first part has under 3 letters (and no @kind or filter)
local function KeepTyping(stages, trail)
	-- (a name still being typed: "where to get t" would match half of AtlasLoot)
	local letters = #(stages[1].text:gsub("@%S+", ""):gsub("%S+:%S*", ""):gsub("[%s%p]", ""))
	if letters < 3 and not stages[1].text:find("[@:]") then
		return { Line(L["Keep typing the name: %s"]:format(trail[1])) }, trail[1]
	end
end

-- the first link's own way to start, when it has one (chain: Questie's quests by name, else the quests rewarding an item
-- by that name; Rewards.lua)
local function FirstDef(stages)
	local name = stages[2] and P.Find(stages[2].word)
	return name and P.relations[name] and P.relations[name][1] or nil, name
end

--- The lists a relation's other definitions start from as well (`seedAlso`: What's Training's spells for "> learn"),
--- those that are there; nil: none.
function P.AlsoSeeds(name)
	local out
	for k, def in ipairs(name and P.relations[name] or {}) do
		if k > 1 and def.seedAlso and (not def.available or def.available()) then
			for _, kind in ipairs(def.seedAlso) do
				if ns.providers[kind] or P.LISTS[kind] then out = out or {}; out[#out + 1] = kind end
			end
		end
	end
	return out
end

-- the first part's rows, kept by its text (the closest name or the names to pick from ride on the list)
local function SeedRows(key, stages)
	local def, name = FirstDef(stages)
	local kinds = def and def.seedKinds
	-- (a link two parts give, "> rewards": a quest's (Rewards.lua) and a faction's (OneForAll): each one's lists)
	if kinds and name and #P.relations[name] > 1 then
		local all, seen = {}, {}
		for _, d in ipairs(P.relations[name]) do
			if not d.available or d.available() then
				for _, k in ipairs(d.seedKinds or P.SEED_KINDS) do if not seen[k] then seen[k] = true; all[#all + 1] = k end end
			end
		end
		kinds = all
	end
	local also = not kinds and P.AlsoSeeds(name) or nil
	-- (the same words start another list there; and the names to pick from are those the first link takes: kept by it
	-- too. "copper > mats" then "copper > uses" offered mats' names, Copper Ore missing)
	if name then key = key .. " @" .. name end
	local rows = Cached(key)
	if not rows then
		local near, choices
		rows, near, choices = P.Seed(stages[1].text, kinds, also, name and function(e)
			for _, d in ipairs(P.relations[name]) do
				if not d.available or d.available() then
					local ok, yes = pcall(d.applies, e)
					if ok and yes then return true end
				end
			end
			return false
		end)
		if #rows == 0 and not choices and def and def.seedFallback then
			local fb = def.seedFallback(stages[1].text)
			if fb and #fb > 0 then rows, near = Once(fb), nil end
		end
		rows.near, rows.choices = near, choices -- (kept with them: the cache hands back the list alone)
		Keep(key, rows)
	end
	return rows
end

-- a name to pick, or the closest one offered: Enter writes the chain with it
local function Pick(e, i, oneRel, rest)
	local n = ns.Plain(tostring(e.name)):gsub("%s+x%d+$", "")
	-- (Simple mode: "mats for <Name>", never a ">" chain)
	local done = oneRel and P.Phrase(n, oneRel) or (n .. " " .. rest)
	return { name = n, kind = "pipe", kindLabel = e.kindLabel or e.label, detail = e.detail, icon = e.icon,
		completion = done, staysOpen = true, activate = PickRelation, _score = 1e6 - i }
end

-- never a guess: the names to pick from, or the closest one offered (Enter writes the chain with it)
local function NoSeedRows(chain, stages, rows, trail)
	-- (the links after the name, made again from the stages: spaces typed twice made an offset into the chain miss)
	local after = {}
	for i = 2, #stages do after[#after + 1] = "> " .. stages[i].text end
	local rest = table.concat(after, " ")
	local oneRel = #stages == 2 and P.Find(stages[2].word) and (stages[2].rest or "") == "" and P.Find(stages[2].word)
	if rows.choices then
		local out = { Line(L["%d names have \"%s\": pick one"]:format(rows.choices.total, trail[1])) }
		for i, e in ipairs(rows.choices) do out[#out + 1] = Pick(e, i, oneRel, rest) end
		return out, trail[1] .. " > ?"
	end
	local def = FirstDef(stages)
	local out = { Line(((def and def.seedNone) or L["Nothing called \"%s\" in your bags, recipes, AtlasLoot or alts"]):format(trail[1])) }
	if rows.near then
		local d = Pick(rows.near, 1, oneRel, rest)
		d.name = L["Did you mean %s?"]:format(d.name)
		out[2] = d
	end
	return out, trail[1]
end

-- a link still being typed (or not one): the relations these rows can go through, to pick from
local function RelationChoices(chain, s, rows, trail)
	local out = {}
	local lw = ns.Lower(s.word or "")
	local before = chain:sub(1, (chain:find(">[^>]*$")) or #chain)
	for _, a in ipairs(P.Applicable(P.Left(rows))) do
		if lw == "" or a[1]:sub(1, #lw) == lw or (P.LABELS[a[1]] or ""):sub(1, #lw) == lw then
			local done = before .. " " .. a[1] .. " "
			out[#out + 1] = { name = a[1], kind = "pipe", kindLabel = "|cff33ff99" .. L["link"] .. "|r", detail = a[2],
				completion = done, staysOpen = true, activate = PickRelation, _score = 1e6 - #out }
		end
	end
	if #out == 0 then
		local names = {}
		for _, name in ipairs(P.order) do if P.Available(name) then names[#names + 1] = name end end
		out[1] = Line(L["No link called \"%s\": %s"]:format(s.word or "", table.concat(names, ", ")))
	end
	trail[#trail + 1] = "?"
	return out, table.concat(trail, " > ")
end

local function ByScore(a, b) return a.s > b.s end

-- the rows whose names have every word, best first
local function NarrowByName(rows, tokens)
	local kept = {}
	for _, e in ipairs(rows) do
		local sc = NameScore(e, tokens)
		if sc then kept[#kept + 1] = { e = e, s = sc } end
	end
	table.sort(kept, ByScore)
	rows = {}
	for _, k in ipairs(kept) do rows[#rows + 1] = k.e end
	return rows
end

-- the last part's rows as the chain shows them: Enter walks on where there's a step; each says what the chain makes
-- of it (for chat)
local function FinalRows(rows, stages, base, from, lastRel, lastFrom)
	local out = {}
	for i, e in ipairs(rows) do
		local v = (#stages > 1) and P.WalkView(e, base, from) or e
		if v == e then v = setmetatable({}, { __index = e }) end
		v._score = 1e6 - i
		-- (what the chain says this row is, for chat: "Mats for Thorium Belt: 8x [Thorium Bar]", Share.ChainContext)
		v.pipeRel, v.pipeFrom = lastRel, lastFrom
		out[#out + 1] = v
	end
	return out
end

-- The lists a chain reads (the usual ones, and any @kind's), built again first when they changed since: the steps
-- kept go with the lists they were made from (bars you just bought show in "have" at once). A list never built isn't
-- built here (no step read it).
local function Refreshed(text)
	for _, k in ipairs(P.SEED_KINDS) do
		local p = ns.providers[k]
		if p and p._entries then ns:GetEntries(p) end
	end
	for w in text:gmatch("@(%S+)") do
		local p = ns:ResolveProvider(w)
		if p and p._entries then ns:GetEntries(p) end
	end
end

-- Simple mode's words for a link that gave nothing ("Nothing uses Hearthstone"): it never shows ">"
P.SIMPLE_NONE = { mats = L["No mats for %s: it isn't crafted"], uses = L["Nothing uses %s"], sources = L["Nowhere known to get %s"],
	alts = L["No %s on your alts"], learn = L["Nowhere known to learn %s"], chain = L["No quests lead up to %s"] }

local function NothingThere(trail, stages, rel, from)
	local f = SimpleOn() and #stages == 2 and (stages[2].rest or "") == "" and P.SIMPLE_NONE[rel]
	local said = table.concat(trail, " > ")
	if f then return { Line(f:format(from or trail[1])) }, said end
	return { Line(L["Nothing there: %s"]:format(SimpleOn() and P.SimpleLabel(said) or said)) }, said
end

--- Runs a chain: rows, and the footer's trail ("thorium belt > mats > thorium bar > sources").
function P.Search(chain)
	local stages = P.Split(chain)
	if not stages then return {}, nil end
	P.loading = false
	Refreshed(stages[1].text)
	local trail = { (stages[1].text:gsub("^%s+", ""):gsub("%s+$", "")) }
	local wait, said = KeepTyping(stages, trail)
	if wait then return wait, said end
	local key = ns.Lower(trail[1])
	local rows = SeedRows(key, stages)
	if #rows == 0 then return NoSeedRows(chain, stages, rows, trail) end
	local from, lastRel, lastFrom
	-- (walking on from the last part's rows: the chain up to its link word, then the row's name)
	local base = chain:sub(1, (chain:find(">[^>]*$"))) .. " " .. (stages[#stages].word or "")
	for i = 2, #stages do
		local s = stages[i]
		local name = P.Find(s.word)
		if not name then return RelationChoices(chain, s, rows, trail) end
		key = key .. " > " .. name
		lastRel, lastFrom = name, P.FromName(P.Left(rows), i == 2 and trail[1] or nil)
		local got = Cached(key)
		if not got then
			got = P.Run(name, P.Left(rows))
			Keep(key, got)
		end
		rows = got
		trail[#trail + 1] = P.LABELS[name] or name
		from = name
		local tokens = Tokens(s.rest)
		if #tokens > 0 then key = key .. " " .. table.concat(tokens, " ") end
		if #tokens > 0 then
			rows = NarrowByName(rows, tokens)
			trail[#trail + 1] = (s.rest:gsub("^%s+", ""):gsub("%s+$", ""))
			if i < #stages then from = nil end -- (narrowed to a row: the next link starts from it)
		end
		if #rows == 0 then return NothingThere(trail, stages, name, lastFrom) end
	end
	return FinalRows(rows, stages, base, from, lastRel, lastFrom), table.concat(trail, " > ")
end

--- The rows to pass on: real results (not hints or help lines), each once, at most MAX_LEFT.
function P.Left(rows)
	local out, seen = {}, {}
	for _, e in ipairs(rows or {}) do
		if not (e.raw or e.noActivate or e.completion or e.kind == "calc") then
			local o = rawget(e, "pipeOf") or e
			local id = Id(o)
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = o
				if #out >= P.MAX_LEFT then break end
			end
		end
	end
	return out
end

ns:RegisterCommand("chains", {
	desc = L["Chains: pass a search on with > (thorium belt > mats, copper bar > uses, mageweave > sources), or in plain words (mats for thorium belt)"],
	aliases = { "pipes", "pipe", "links" },
	run = function()
		local lines = { L["Chains: a  >  passes what a search found on (Enter on a row walks on, Shift+Enter opens it):"] }
		for _, name in ipairs(P.order) do
			-- (only the links you can use: steps and attunement need Attune, chain Questie)
			local def = P.Available(name) and P.relations[name][1]
			if def then
				lines[#lines + 1] = ("  %s%s  -  %s"):format(name, #def.aliases > 0 and (" (" .. table.concat(def.aliases, ", ") .. ")") or "", def.desc)
			end
		end
		lines[#lines + 1] = L["In plain words: mats for thorium belt, what uses copper bar, where to get thorium bar, who sells mageweave, where to learn thorium belt."]
		return lines
	end,
})

local find = string.find
local ns = select(2, ...)
local L = ns.L

-- The bar (0.55.1, experimental; the player: "if we are outside of advanced mode, let's try to add some tabs for
-- filtering, sorting, grouping, and a little announcement horn for putting out to say, party, raid, text"): a strip
-- under the prompt in Simple mode, so what Advanced syntax does is a click away.
--
--   Filter   what the shown lists can be narrowed by: quality, usable, upgrades, known spells, complete quests...
--            (several at once; each an Advanced filter the search takes as it takes a typed one)
--   Sort     nearest first, or by name, level, item level, quality, value, count (what the rows have)
--   Group    a row per zone, quality, type, slot, dungeon... with how many in each (Advanced's "| group by")
--   (horn)   the selected result, or all of them, to say, party, raid, guild..., or copied as text or CSV
--
-- What the words typed already ask shows too ("rare sword": Filter: Rare; "nearest ...": Sort: Nearest first), and
-- unticking it takes the word out of the line: the bar is one more way to write the search's query (0.55.7). A question's
-- answer ("my auctions") is filtered, sorted and grouped like any search's rows.
-- A click on one opens its menu; a right-click clears it. What's picked lasts while the prompt has words and goes
-- when it's cleared or the terminal closes. Typing Advanced syntax takes the bar away (that line is Advanced); Alt+`,
-- or Advanced syntax typed after the words, writes what's picked into the line ("q:rare+ sort:nearest | group by
-- zone": the search's query printed, Search.lua's ns.QueryToAdvanced). While the categories show (nothing picked yet), only Filter works: they count what passes it.

local UI, Theme = ns.UI, ns.Theme
local B = {}
ns.Bar = B

B.H = 22
local state = { filters = {}, sort = nil, group = nil }
B.state = state -- (tests)

-- what Filter offers: the filter (an Advanced one), what it says; shown when a list it judges is shown (F.APPLIES)
B.FILTERS = {
	{ id = "q:uncommon+", label = L["Uncommon or better"] },
	{ id = "q:rare+", label = L["Rare or better"] },
	{ id = "q:epic+", label = L["Epic or better"] },
	{ id = "is:upgrade", label = L["Upgrades"] },
	{ id = "is:usable", label = L["Usable"] },
	{ id = "is:boe", label = L["Bind on equip"] },
	{ id = "is:quest", label = L["Quest items"] },
	{ id = "is:known", label = L["Known"] },
	{ id = "is:unknown", label = L["Not known yet"] },
	{ id = "is:ready", label = L["Ready (off cooldown)"] },
	-- (0.55.15, the player: "missing the is:unplaced / missing from my action bars filter") every list's own, offered
	-- where its list is shown (F.APPLIES)
	{ id = "is:unplaced", label = L["Not on my action bars"] },
	{ id = "is:passive", label = L["Passive"] },
	{ id = "is:capped", label = L["Capped"] },
	{ id = "is:drop", label = L["Quests to drop"] },
	{ id = "is:grey", label = L["Grey"] },
	{ id = "is:learnable", label = L["Can learn now"] },
	{ id = "is:shareable", label = L["Can share"] },
	{ id = "is:dead", label = L["Dead"] },
	{ id = "is:unbuffed", label = L["Missing a buff"] },
	{ id = "is:damaged", label = L["Needs repair"] },
	{ id = "is:expiring", label = L["Running out soon"] },
	{ id = "is:unread", label = L["Unread"] },
	{ id = "is:sold", label = L["Sold"] },
	{ id = "is:holiday", label = L["Holidays"] },
	{ id = "is:invite", label = L["Invites"] },
	{ id = "is:mine", label = L["Mine"] },
	{ id = "is:complete", label = L["Complete"] },
	{ id = "is:todo", label = L["Not done yet"] },
	{ id = "is:craftable", label = L["Craftable"] },
	{ id = "is:skillup", label = L["Gives skill"] },
	{ id = "faction:friendly", label = L["Friendly"] },
	{ id = "is:vendor", label = L["Vendors"] },
	{ id = "is:trainer", label = L["Trainers"] },
	{ id = "is:online", label = L["Online"] },
}
-- what Sort offers: nearest (sort:nearest's lists), else a field the rows have (Aggregate's, and the name)
-- a sort's way, in the menu: the game's sort arrow (down as drawn, up flipped)
B.ARROW = "Interface\\Buttons\\UI-SortArrow"
B.WORD_SORTS = { name = true, owner = true, line = true } -- (sorts by words: A-Z first when picked)
B.SORTS = {
	{ id = "nearest", label = L["Nearest first"], near = true },
	{ id = "name", label = L["Name"], field = "name", asc = true },
	{ id = "level", label = L["Level"], field = "level", asc = true },
	{ id = "ilvl", label = L["Item level"], field = "ilvl" },
	{ id = "quality", label = L["Quality"], field = "quality" },
	{ id = "value", label = L["Value"], field = "value" },
	{ id = "count", label = L["Count"], field = "count" },
	{ id = "damage", label = L["Biggest hit"], field = "damage" },
	{ id = "line", label = L["Line by line"], field = "line", asc = true },
	{ id = "owner", label = L["Owner"], field = "owner", asc = true }, -- (friends' items, Terminal: Share; 0.58.6)
}
-- what Group offers: Aggregate's fields that name something
B.GROUPS = { "kind", "owner", "zone", "quality", "type", "slot", "dungeon", "raid", "boss", "level" }

local function E() return ns.Easy end
local function ById(list, id) for _, o in ipairs(list) do if o.id == id then return o end end end
--- A sort's id without its direction, and whether it's the other way round ("-level": the highest first; 0.65.5).
local function SortParts(id)
	if type(id) == "string" and id:sub(1, 1) == "-" then return id:sub(2), true end
	return id, false
end
B.SortParts = SortParts
--- Which way a sort goes: true for ascending (A-Z, the lowest first), from its field's own way and the - before it.
local function Ascending(s, rev)
	local asc = s.asc and true or false
	if rev then asc = not asc end
	return asc
end
B.Ascending = function(id)
	local base, rev = SortParts(id)
	local s = ById(B.SORTS, base)
	return s and Ascending(s, rev) or false
end
B.ById = ById

--- Is the bar in use: Simple mode (not a line run in Advanced, not fuzzy finding), searching, words typed?
function B.On()
	local Ez = E()
	-- (Ctrl+R's history search: its lines, nothing to filter; 0.63.7, review)
	if not (UI.frame and Ez and Ez.On and Ez.On()) or Ez.temp or UI.fzf or UI.histSearch then return false end
	if UI.mode ~= "search" then return false end
	local text = UI.edit and UI.edit:GetText() or ""
	if not text:find("%S") then return false end
	local first = text:match("^%s*(.)")
	return first ~= "." and first ~= "/"
end

--- What's picked, for the search: only in Simple mode (the bar's own), else nothing.
function B.Active()
	local Ez = E()
	if not (Ez and Ez.On and Ez.On()) or Ez.temp or UI.fzf or UI.histSearch then return nil end
	if #state.filters == 0 and not state.sort and not state.group then return nil end
	return state
end

--- The group the rows are in: a "| group by" typed, else the bar's (unless steps typed sum them up their own way).
function B.GroupOn()
	if UI.typedGroup then return UI.typedGroup.id, true end
	if UI.barGroupIgnored then return nil end
	return state.group, false
end

--- What's picked, copied (Alt+` keeps it to come back to: UI:BackToSimple), and put back.
function B.Save()
	local f = {}
	for i, id in ipairs(state.filters) do f[i] = id end
	return { filters = f, sort = state.sort, group = state.group }
end
function B.Restore(saved)
	state.filters, state.sort, state.group = {}, saved.sort, saved.group
	for i, id in ipairs(saved.filters or {}) do state.filters[i] = id end
end

function B.Reset()
	local had = #state.filters > 0 or state.sort or state.group
	state.filters, state.sort, state.group = {}, nil, nil
	if B.menu then B.menu:Hide() end
	if B.tipUp then B.tipUp = nil; if B.tip then B.tip:Hide() end end
	return had
end

--- The filters and the sort typed as words in Simple mode ("rare", "usable", "nearest"), as the search read them
--- (Search.lua's UI.typedPicks): shown as picked, and taken back out of the line from here (0.55.7, the search's rewrite:
--- the bar edits the query, the words typed included). Filters only of the kinds Filter offers (quality, is:, friendly).
local SHOWN_SPEC = { "^%-?is:", "^%-?q:", "^faction:" }
function B.Typed()
	local t = UI.typedPicks
	-- (a "| group by zone" typed: TakeAggregate's, Results.lua)
	local out = { filters = {}, sort = t and t.sort or nil, group = UI.typedGroup }
	for _, p in ipairs(t and t.filters or {}) do
		local spec = p.spec
		-- (an everyday word's of those kinds, "rare"; any filter typed as key:value, in:"Scarlet Monastery" a group's Enter
		-- wrote (0.55.14): you're in that group, the bar says so and takes it back out)
		local shown = type(p.word) == "string" and p.word:find("^[-!]?%a+:") ~= nil
		for _, pat in ipairs(SHOWN_SPEC) do if type(spec) == "string" and spec:find(pat) then shown = true break end end
		if shown then out.filters[#out.filters + 1] = p end
	end
	return out
end

--- What a filter typed is called on the bar: Filter's own name for it; else in words, "q:rare" Rare, "q:rare+" Rare or
--- better, "is:unlearned" Unlearned, "-is:boe" Not boe; else the word as typed (0.55.12, the player's screenshot said
--- "Q:rare").
function B.SpecLabel(spec, word)
	local o = ById(B.FILTERS, spec)
	if o then return o.label end
	local neg, key, val = tostring(spec):match("^([-!]?)(%a+):([%w_]+%+?)$")
	local out
	if key == "q" or key == "quality" then
		local plus = val:find("%+$")
		val = val:gsub("%+$", "")
		out = ns.UpperFirst(val) .. (plus and (" " .. L["or better"]) or "")
	elseif key == "is" then
		out = ns.UpperFirst((val:gsub("_", " ")))
	end
	-- (a value of several words, quoted or with _: in:"Scarlet Monastery - Cathedral" In Scarlet Monastery - Cathedral)
	if not out then
		local n2, k2, v2 = tostring(spec):match("^([-!]?)(%a+):(.+)$")
		if k2 then
			v2 = v2:gsub('"', ""):gsub("_", " ")
			k2 = ns.Lower(k2)
			if k2 == "in" or k2 == "zone" or k2 == "where" then out = L["In %s"]:format(v2)
			elseif k2 == "lvl" or k2 == "level" then out = L["Level %s"]:format(v2)
			else out = ns.UpperFirst(v2) end
			neg = n2
		end
	end
	if out and neg ~= "" then return L["Not %s"]:format(ns.Lower(out)) end
	return out or ns.UpperFirst(word or tostring(spec))
end

--- Words taken out of the prompt (case aside, whole words; a phrase's spaces any spaces), the search run again.
function B.DropWords(words)
	local edit = UI.edit
	if not edit then return end
	local text = edit:GetText() or ""
	-- the ways each may stand in the line: a filter's value of several words is read without its quotes (in:Scarlet
	-- Monastery; the line has them); "not boe" is read as -boe (Easy.JoinLogic: the line has the words; 0.55.18)
	local forms = {}
	for _, w in ipairs(words) do
		forms[#forms + 1] = w
		local k, v = w:match("^([-!]?%a+:)(.+)$")
		if k and v:find("%s") and not v:find('"', 1, true) then forms[#forms + 1] = k .. '"' .. v .. '"' end
		local neg = w:match("^[-!]([^:]+)$")
		if neg then
			for nw in pairs(ns.Easy and ns.Easy.NOT_WORDS or {}) do forms[#forms + 1] = nw .. " " .. neg end
		end
	end
	-- (every time it's there, whole words only, never inside a "quoted phrase": that's searched as it is)
	local function Quoted(at)
		local n = 0
		for _ in text:sub(1, at - 1):gmatch('"') do n = n + 1 end
		return n % 2 == 1
	end
	for _, w in ipairs(forms) do
		local pat = ns.Lower(w):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%s+", "%%s+")
		local from = 1
		while true do
			local lower = ns.Lower(text)
			local a, b = lower:find(pat, from)
			if not a then break end
			local before, after = lower:sub(a - 1, a - 1), lower:sub(b + 1, b + 1)
			if (a == 1 or before:find("%s")) and (after == "" or after:find("%s")) and not Quoted(a) then
				text = text:sub(1, a - 1) .. text:sub(b + 1)
				from = a
			else
				from = a + 1
			end
		end
	end
	local had = (edit:GetText() or ""):find("%s$") -- (a space typed after the last word stays: the next word is on its way)
	text = text:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if had and text ~= "" then text = text .. " " end
	if UI.SetQuery then UI:SetQuery(text, #text) else edit:SetText(text) end
end

--- The search's sort for a field (Search.lua's Scan.Finalize): the rows that have it in its order (the biggest first,
--- or A-Z / the lowest first), then the rest as they were. Changes their scores.
local function NumOf(field, e)
	local A = ns.Aggregate
	local f = A and A.FIELDS[field]
	if not (f and f.num) then return nil end
	local ok, n = pcall(f.num, e)
	return ok and type(n) == "number" and n or nil
end
local function Real(e) return type(e) == "table" and not (e.raw or e.noActivate or e.completion or e.lead or e.catId or e.syntaxRow) end
B.Real = Real

local function KeyOf(s, e)
	if s.field == "name" then
		-- (the lowered name the search keeps, when it has no colour codes to take out: a sort of 100k rows; 0.63.7)
		local ln = rawget(e, "_lname")
		if ln and not find(ln, "|", 1, true) then return ln end
		return ns.Lower(ns.Plain(tostring(e.name or "")))
	end
	-- (a field of words, the owner: A-Z by it)
	local A = ns.Aggregate
	local f = A and A.FIELDS[s.field]
	if f and f.text and not f.num then
		local ok, t = pcall(f.text, e, f)
		return ok and type(t) == "string" and ns.Lower(ns.Plain(t)) or nil
	end
	return NumOf(s.field, e)
end
local function Keyed(s, rows, asc)
	if asc == nil then asc = s.asc end
	local keyed, rest = {}, {}
	-- (a tie-breaker field, lowest first: sort:slots, then the level; 0.65.3)
	local tie = s.tie and { field = s.tie }
	for i, e in ipairs(rows) do
		if Real(e) then
			local k = KeyOf(s, e)
			if k ~= nil then keyed[#keyed + 1] = { e = e, k = k, i = i, t = tie and KeyOf(tie, e) or nil } else rest[#rest + 1] = e end
		end
	end
	table.sort(keyed, function(a, b)
		if a.k ~= b.k then
			if asc then return a.k < b.k end
			return a.k > b.k
		end
		if a.t ~= b.t and a.t ~= nil and b.t ~= nil then return a.t < b.t end
		return a.i < b.i
	end)
	return keyed, rest
end

--- The search's rows in a field's order (Search.lua's Finalize, "sort:name" typed or picked on the bar): the rows that
--- have it scored above any search score, in its order (a pinned row stays on top). Past 5000 rows, only the first
--- `keep` (the rows shown) are found, with a bounded heap: not every row sorted (0.63.7, review: past 5000 the sort was
--- skipped, "@stress1 ka sort:name" listed by relevance). `overBudget`: the search's clock, to yield on.
function B.SortRows(rows, id, keep, overBudget)
	local base, rev = SortParts(id)
	local s = ById(B.SORTS, base)
	if not (s and s.field) then return rows end
	local asc = Ascending(s, rev)
	if #rows <= 5000 then
		local keyed = Keyed(s, rows, asc)
		for i, r in ipairs(keyed) do r.e._score = 1e10 - i end
		return rows
	end
	keep = keep or 100
	-- (a before b in the field's order; the earlier row first on a tie)
	local function Before(a, b)
		if a.k ~= b.k then if asc then return a.k < b.k end return a.k > b.k end
		return a.i < b.i
	end
	local heap, size = {}, 0 -- (the last of the kept ones on top)
	local function up(i)
		while i > 1 do
			local p = math.floor(i / 2)
			if Before(heap[p], heap[i]) then heap[p], heap[i] = heap[i], heap[p]; i = p else break end
		end
	end
	local function down(i)
		while true do
			local l, r, w = i * 2, i * 2 + 1, i
			if l <= size and Before(heap[w], heap[l]) then w = l end
			if r <= size and Before(heap[w], heap[r]) then w = r end
			if w == i then return end
			heap[w], heap[i] = heap[i], heap[w]
			i = w
		end
	end
	local check = UI.SLICE_CHECK or 500
	for i, e in ipairs(rows) do
		if overBudget and i % check == 0 and overBudget() then coroutine.yield(rows) end -- (the matches so far, as the scan yields)
		if Real(e) then
			local k = KeyOf(s, e)
			if k ~= nil then
				local r = { e = e, k = k, i = i }
				if size < keep then
					size = size + 1
					heap[size] = r
					up(size)
				elseif Before(r, heap[1]) then
					heap[1] = r
					down(1)
				end
			end
		end
	end
	table.sort(heap, Before)
	for i, r in ipairs(heap) do r.e._score = 1e10 - i end
	return rows
end

--- A question's rows in a field's order (Search.lua's Scan.AnswerView: an answer isn't scored): each run of results
--- between its lines (a heading, a note) sorted on its own, the rows with the field first. A new list.
function B.Order(rows, id)
	local base, rev = SortParts(id)
	local s = ById(B.SORTS, base)
	if not (s and s.field) or #rows > 5000 then return rows end
	local asc = Ascending(s, rev)
	local out, run = {}, {}
	local function Flush()
		if #run == 0 then return end
		local keyed, rest = Keyed(s, run, asc)
		for _, r in ipairs(keyed) do out[#out + 1] = r.e end
		for _, e in ipairs(rest) do out[#out + 1] = e end
		run = {}
	end
	for _, e in ipairs(rows) do
		if Real(e) then run[#run + 1] = e else Flush(); out[#out + 1] = e end
	end
	Flush()
	return out
end

--- The lists the shown rows come from (a category's lists for its row), and whether the categories show.
local function ShownKinds()
	local kinds, overview = {}, false
	for _, e in ipairs(UI.results or {}) do
		if type(e) == "table" then
			if e.catId then
				overview = true
				for k in pairs(ns.Easy.Kinds(e.catId) or {}) do kinds[k] = true end
			elseif Real(e) and e.kind then
				kinds[e.kind] = true
			end
		end
	end
	return kinds, overview
end
B.ShownKinds = ShownKinds

--- Do these rows show Simple mode's categories (nothing picked yet)?
function B.Overview(rows)
	for _, e in ipairs(rows or {}) do if type(e) == "table" and e.catId then return true end end
	return false
end

--- Does this filter judge a list that's shown (F.APPLIES; a key it doesn't list: never offered)?
local function Fits(id, kinds)
	local F = ns.Filters
	local key, val = id:match("^(%a+):(.+)$")
	local ap = F and F.APPLIES and F.APPLIES[key]
	if not ap then return false end
	local where = ap[val] or ap["*"]
	for _, k in ipairs(where or {}) do if kinds[k] then return true end end
	return false
end
B.Fits = Fits

--- The options a menu offers now: { id, label, on }.
function B.Options(which)
	local kinds, overview = ShownKinds()
	local out = {}
	local typed = B.Typed()
	if which == "filter" then
		local on, listed = {}, {}
		for _, id in ipairs(state.filters) do on[id] = true end
		-- (typed ones first: "usable" typed is Usable ticked; one Filter doesn't offer, its word: "Rare")
		for _, p in ipairs(typed.filters) do
			if not listed[p.spec] then
				listed[p.spec] = true
				out[#out + 1] = { id = p.spec, label = B.SpecLabel(p.spec, p.word), on = true, typed = p.word }
			end
		end
		for _, o in ipairs(B.FILTERS) do
			if not listed[o.id] and (on[o.id] or Fits(o.id, kinds)) then out[#out + 1] = { id = o.id, label = o.label, on = on[o.id] } end
		end
		return out
	end
	if overview then return out end
	-- (the rows' own fields: the first few dozen are asked)
	-- (the rows' own fields: the first hundred are asked)
	-- (grouped: the rows the groups were made of, so another group can be picked from them)
	local sample = {}
	local from = UI.results or {}
	if UI.ungrouped and from[1] and from[1].kind == "aggregate" then from = UI.ungrouped end
	for _, e in ipairs(from) do
		if Real(e) then sample[#sample + 1] = e; if #sample >= 100 then break end end
	end
	local A = ns.Aggregate
	-- (0.55.14, the player: "I am already in a chosen group and it is letting me group again" (a group's Enter: its rows
	-- all in one dungeon) only what tells the rows apart: two values or more, as a sort or a group by one value does
	-- nothing)
	local function Has(field)
		if field == "name" then return #sample >= 2 end
		local f = A and A.FIELDS[field]
		if not f then return false end
		local first
		for _, e in ipairs(sample) do
			local ok, v
			if f.text then ok, v = pcall(f.text, e, f) else ok, v = pcall(f.num, e) end
			if ok and v ~= nil then
				if first == nil then first = v elseif v ~= first then return true end
			end
		end
		return false
	end
	if which == "sort" then
		local pickedBase, pickedRev = SortParts(state.sort)
		local typedBase, typedRev = SortParts(typed.sort and typed.sort.id)
		for _, o in ipairs(B.SORTS) do
			local typedHere = typedBase == o.id
			local fits = o.near and Fits("sort:nearest", kinds) or (o.field and Has(o.field))
			local on = pickedBase == o.id or typedHere
			if fits or on then
				-- (which way: an arrow, up for ascending, down for descending, in the tick's place; 0.65.5, the player)
				local rev = (pickedBase == o.id and pickedRev) or (pickedBase ~= o.id and typedHere and typedRev)
				-- (asc: true, false or nil, not on: not "on and Ascending() or nil", which made a descending one's false nil)
				local asc
				if on and o.field then asc = Ascending(o, rev) end
				out[#out + 1] = { id = o.id, label = o.label, on = on, typed = typedHere and pickedBase ~= o.id and typed.sort.word or nil,
					asc = asc }
			end
		end
	elseif which == "group" then
		local tg = typed.group
		local on = B.GroupOn()
		for _, id in ipairs(B.GROUPS) do
			local typedHere = tg and tg.id == id
			if Has(id) or on == id or typedHere then
				local f = A.FIELDS[id]
				out[#out + 1] = { id = id, label = ns.UpperFirst(f and f.label or id), on = on == id,
					typed = typedHere and tg.word or nil }
			end
		end
	end
	return out
end

--- Pick or drop an option: Filter's add up, Sort's and Group's are one each. The terminal searches again.
function B.Pick(which, id)
	local typed = B.Typed()
	if which == "filter" then
		-- (one typed as a word, not picked here: its word taken out of the line)
		local mine = false
		for _, f in ipairs(state.filters) do if f == id then mine = true end end
		if not mine then
			for _, p in ipairs(typed.filters) do
				if p.spec == id then B.DropWords({ p.word }) B.Update() return end
			end
		end
		local had
		for i, f in ipairs(state.filters) do if f == id then table.remove(state.filters, i); had = true break end end
		if not had then state.filters[#state.filters + 1] = id end
	elseif which == "sort" then
		-- (the one picked again: the other way round, the highest first or the lowest; "Best match" undoes it; 0.65.5)
		local o = ById(B.SORTS, id)
		local turns = o and o.field and true or false
		local pickedBase, pickedRev = SortParts(state.sort)
		local typedBase, typedRev = SortParts(typed.sort and typed.sort.id)
		if typedBase == id and pickedBase ~= id then
			-- (typed as a word: the word goes, and the bar's own sort is it turned round; one that doesn't turn, nearest,
			-- just goes, as before)
			if turns then state.sort = typedRev and id or ("-" .. id) end
			B.DropWords({ typed.sort.word })
			B.Update()
			return
		end
		if pickedBase == id then
			if not turns then state.sort = nil B.Changed() return end -- (nearest first: no other way round; unpicked, as before)
			state.sort = pickedRev and id or ("-" .. id)
			B.Changed()
			return
		end
		-- (picked: the highest first, as the player said, "assume descending at first" (0.65.5): the level too; the
		-- words' sorts, a name, an owner, an attunement's lines, A-Z first; picked again, the other way)
		state.sort = (turns and o.asc and not B.WORD_SORTS[id]) and ("-" .. id) or id
		-- (another sort picked: a sort: typed goes from the line, one sort at a time; "nearest" stays, it says the NPCs)
		if state.sort and typed.sort and typed.sort.drop then
			B.DropWords({ typed.sort.word })
			B.Update()
			return
		end
	elseif which == "group" then
		-- (a group typed: unticked, or another picked, its step goes from the line; the bar's own group then)
		if typed.group then
			state.group = (typed.group.id ~= id) and id or nil
			-- ("quests per zone": the words were the group; its list is what's left, "@questie")
			if typed.group.rest and UI.edit then UI:SetQuery(typed.group.rest, #typed.group.rest)
			else B.DropWords({ typed.group.word }) end
			B.Update()
			return
		end
		state.group = (state.group ~= id) and id or nil
	end
	B.Changed()
end

--- Nothing picked for Filter, Sort or Group: the words typed for it taken out of the line too.
function B.Clear(which)
	local typed, words = B.Typed(), {}
	if which == "filter" then
		state.filters = {}
		for _, p in ipairs(typed.filters) do words[#words + 1] = p.word end
	elseif which == "sort" then
		state.sort = nil
		if typed.sort then words[1] = typed.sort.word end
	else
		state.group = nil
		if typed.group then words[1] = typed.group.word end
	end
	if #words > 0 then B.DropWords(words) end
	B.Changed()
end

--- Something picked or dropped: the search again (its filters, sort and summing), the bar redrawn.
function B.Changed()
	UI.lastScan, UI.lastExtra = nil, nil -- (another filter: not a narrowing of the last keystroke's matches)
	if UI.frame and UI:IsShown() then UI:Research() end
	B.Update()
end

----------------------------------------------------------------------
-- The strip and its menu
----------------------------------------------------------------------

local strip
local HORN = "Interface\\Icons\\INV_Misc_Horn_01"
-- the speaker (a megaphone's look): the chat frame's voice button's atlas, the voice chat's own; else the old voice
-- chat textures (a speaker, its sound waves over it); else the horn
local SPEAKER_ATLASES = { "chatframe-button-icon-speaker-on", "voicechat-icon-speaker" }
local SPEAKER, WAVES = "Interface\\Common\\VoiceChat-Speaker", "Interface\\Common\\VoiceChat-On"

--- The send button's picture on these textures: which one was used ("atlas:<name>", "file", "horn").
function B.SpeakerIcon(icon, waves)
	waves:Hide()
	local CT = _G.C_Texture
	if CT and CT.GetAtlasInfo and icon.SetAtlas then
		for _, name in ipairs(SPEAKER_ATLASES) do
			local ok, info = pcall(CT.GetAtlasInfo, name)
			if ok and info and pcall(icon.SetAtlas, icon, name) then return "atlas:" .. name end
		end
	end
	-- (SetTexture says whether the file was there; a client that says nothing: taken as there)
	local ok, there = pcall(icon.SetTexture, icon, SPEAKER)
	if ok and there ~= false then
		if waves:SetTexture(WAVES) ~= false then waves:Show() end
		return "file"
	end
	icon:SetTexture(HORN)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return "horn"
end

local function Label(which, typed)
	typed = typed or B.Typed()
	if which == "filter" then
		-- (what's picked here and what's typed: one list, the typed words' once each)
		local labels, seen = {}, {}
		for _, p in ipairs(typed.filters) do
			if not seen[p.spec] then seen[p.spec] = true; labels[#labels + 1] = B.SpecLabel(p.spec, p.word) end
		end
		for _, id in ipairs(state.filters) do
			if not seen[id] then seen[id] = true; local o = ById(B.FILTERS, id); labels[#labels + 1] = o and o.label or id end
		end
		if #labels == 1 then return L["Filter: %s"]:format(labels[1]) end
		if #labels > 1 then return L["Filter: %d"]:format(#labels) end
		return L["Filter"]
	elseif which == "sort" then
		local base = SortParts(state.sort or (typed.sort and typed.sort.id))
		local o = base and ById(B.SORTS, base)
		return o and L["Sort: %s"]:format(o.label) or L["Sort"]
	else
		local g = B.GroupOn() -- (a group typed is the one summed up: TakeAggregate; steps typed: none of the bar's)
		local f = g and ns.Aggregate and ns.Aggregate.FIELDS[g]
		return f and L["Group: %s"]:format(ns.UpperFirst(f.label)) or B.GroupWord()
	end
end

--- The Group button's word when nothing's grouped: "Group" (0.56.1, the player). Translated as "Group by", since "Group"
--- is also the party's word and some languages say the two differently (zhCN: 队伍, the party; 分组, grouping).
function B.GroupWord()
	local t = L["Group by"]
	if t == "Group by" then t = L["Group"] end -- (English, or not translated yet)
	return t
end

local function Build()
	if strip or not UI.frame then return strip end
	strip = CreateFrame("Frame", nil, UI.frame)
	strip.buttons = {}
	for _, which in ipairs({ "filter", "sort", "group" }) do
		local b = CreateFrame("Button", nil, strip)
		b.which = which
		b.text = b:CreateFontString(nil, "OVERLAY")
		b.text:SetFontObject(Theme.fonts.small)
		b.text:SetPoint("CENTER", 0, 0)
		b.text:SetWordWrap(false)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		-- (its key's letter underlined, Alt+F, Alt+S, Alt+G: B.Underline)
		b.under = b:CreateTexture(nil, "OVERLAY")
		b.under:SetHeight(1)
		b.under:Hide()
		if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
		b:SetScript("OnClick", function(_, button)
			if UI.closing then return end
			if button == "RightButton" then B.Clear(which) B.HideMenu() return end
			if b.off then return end
			if B.menu and B.menu:IsShown() and B.menu.which == which then B.HideMenu() return end
			B.ShowMenu(which, b)
		end)
		b:SetScript("OnEnter", function() b.hover = true; B.Shade(b) end) -- (only its shade: nothing moves under the pointer)
		b:SetScript("OnLeave", function() b.hover = nil; B.Shade(b) end)
		strip.buttons[#strip.buttons + 1] = b
	end
	strip.measure = strip:CreateFontString(nil, "OVERLAY") -- (B.Underline's ruler: never shown)
	strip.measure:SetFontObject(Theme.fonts.small)
	strip.measure:Hide()
	local horn = CreateFrame("Button", nil, strip)
	-- (0.55.9, the player: "more like a megaphone": the game's own speaker on a dark square with a thin edge)
	horn.bg = horn:CreateTexture(nil, "BACKGROUND")
	horn.bg:SetAllPoints()
	horn.edges = {}
	for i = 1, 4 do horn.edges[i] = horn:CreateTexture(nil, "BORDER") end
	local e1, e2, e3, e4 = horn.edges[1], horn.edges[2], horn.edges[3], horn.edges[4]
	e1:SetPoint("TOPLEFT"); e1:SetPoint("TOPRIGHT"); e1:SetHeight(1)
	e2:SetPoint("BOTTOMLEFT"); e2:SetPoint("BOTTOMRIGHT"); e2:SetHeight(1)
	e3:SetPoint("TOPLEFT"); e3:SetPoint("BOTTOMLEFT"); e3:SetWidth(1)
	e4:SetPoint("TOPRIGHT"); e4:SetPoint("BOTTOMRIGHT"); e4:SetWidth(1)
	horn.icon = horn:CreateTexture(nil, "ARTWORK")
	horn.icon:SetPoint("TOPLEFT", 2, -2)
	horn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	horn.waves = horn:CreateTexture(nil, "OVERLAY")
	horn.waves:SetAllPoints(horn.icon)
	B.SpeakerIcon(horn.icon, horn.waves)
	if horn.RegisterForClicks then horn:RegisterForClicks("LeftButtonUp") end
	horn:SetScript("OnClick", function() if not UI.closing then B.Horn() end end)
	horn:SetScript("OnEnter", function()
		-- (its own tooltip, as the spinner's: the game's faded with the interface under .zen; Zen.lua keeps this one)
		if not B.tip then
			local ok, tip = pcall(CreateFrame, "GameTooltip", "TerminalBarTip", UIParent, "GameTooltipTemplate")
			B.tip = ok and tip or nil
			if B.tip and ns.Zen then ns.Zen.Made(B.tip) end
		end
		local tip = B.tip
		if not tip then return end
		-- (0.55.10, the player's screenshot: it sat over the selected row's tooltip beside the terminal) that one put
		-- away while the pointer is here, and this one growing left, over the terminal
		if UI.HideTooltip then UI:HideTooltip() end
		B.tipUp = true
		tip:SetOwner(horn, "ANCHOR_TOPLEFT")
		tip:SetText(L["Send or copy all"], 1, 1, 1)
		tip:AddLine(L["Every result at once, to say, party, raid, guild..., or copied as text or CSV (one result: right-click it)"], 0.8, 0.8, 0.8, true)
		tip:Show()
	end)
	horn:SetScript("OnLeave", function()
		if B.tip then B.tip:Hide() end
		B.tipUp = nil
		if UI.UpdateTooltip and UI:IsShown() then UI:UpdateTooltip() end -- (the selected row's back)
	end)
	strip.horn = horn
	B.strip = strip
	return strip
end

--- How tall the bar is now (0: not shown), for the header (List.lua's HeaderH).
function B.Height() return B.On() and B.H or 0 end

--- Shown or hidden, its labels: from the footer's update (List.lua), on every keystroke and selection.
function B.Update()
	if not UI.frame then return end
	local h = B.Height()
	if h ~= (UI.barH or 0) then
		UI.barH = h
		if UI.LayoutHeader then UI:LayoutHeader() end
		if UI.FitHeight then UI:FitHeight() end
		UI.selY = nil
		if UI.PlaceSelection then UI:PlaceSelection() end
	end
	local s = Build()
	if not s then return end
	s:SetShown(h > 0)
	if h == 0 then
		B.HideMenu()
		-- (gone under the pointer: no OnLeave may come; its tooltip goes, and the row's may show again)
		if B.tipUp then B.tipUp = nil; if B.tip then B.tip:Hide() end end
		return
	end
	local t = Theme.Get()
	local classic = t.frame == "classic"
	local inset = classic and 9 or 6
	local top = (UI.tabsH or 0) + ns.UI.layout.HEADER_H + (UI.promptExtra or 0) - 4
	local _, overview = ShownKinds()
	-- (placed again only when where it goes or a label's width changed: a frame moved under the pointer loses it, so
	-- placing the buttons on every footer update took every hover and click away; 0.55.1, the player: "mousing over and
	-- clicking do nothing")
	local widths = {}
	local typed = B.Typed() -- (once per update, not per button: it runs on every keystroke; review, 0.57.7)
	for i, b in ipairs(s.buttons) do
		local label = Label(b.which, typed)
		if b.label ~= label then b.label = label; b.text:SetText(label); B.Underline(b) end
		widths[i] = math.ceil((b.text:GetStringWidth() or 40) + 18)
	end
	local laid = table.concat({ inset, top, h, table.concat(widths, ",") }, ":")
	if s.laid ~= laid then
		s.laid = laid
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", inset, -top)
		s:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -inset, -top)
		s:SetHeight(h - 2)
		local x = 0
		for i, b in ipairs(s.buttons) do
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", s, "TOPLEFT", x, 0)
			b:SetSize(widths[i], h - 2)
			b:Show()
			x = x + widths[i] + 4
		end
		for _, b in ipairs(s.buttons) do B.Underline(b) end
		local horn = s.horn
		horn:ClearAllPoints()
		horn:SetPoint("RIGHT", s, "RIGHT", -2, 0)
		horn:SetSize(h - 4, h - 4)
	end
	for _, b in ipairs(s.buttons) do
		local active = (b.which == "filter" and (#state.filters > 0 or #typed.filters > 0)) or (b.which == "sort" and (state.sort or typed.sort))
			or (b.which == "group" and B.GroupOn())
		b.off = overview and b.which ~= "filter" and not active
		b.active = active and true or false
		local col = b.off and t.dim or (active and t.accent or t.text)
		b.text:SetTextColor(Theme.RGB(col))
		b.under:SetColorTexture(Theme.RGB(col))
		B.Shade(b)
	end
	s.horn.off = not B.FirstReal()
	s.horn:SetAlpha(s.horn.off and 0.35 or 1)
	s.horn.bg:SetColorTexture(0, 0, 0, 0.6)
	local br, bg, bb = Theme.RGB(t.border)
	for _, edge in ipairs(s.horn.edges) do edge:SetColorTexture(br, bg, bb, 1) end
end

-- each button's key: Alt+F, Alt+S, Alt+G (Keys.lua)
B.KEY_LETTER = { filter = "f", sort = "s", group = "g" }

--- Its key's letter underlined in its label, as a menu's keys are shown (0.56.7, the player: "a hint that there is a
--- shortcut"): the first F of "Filter", S of "Sort", G of "Group". A language whose word hasn't that letter: none.
function B.Underline(b)
	local u, label = b.under, ns.Plain and ns.Plain(tostring(b.label or "")) or tostring(b.label or "")
	local letter = B.KEY_LETTER[b.which]
	local at = letter and label:lower():find(letter, 1, true)
	-- (only in the button's own word, before its ":" and what's picked: "Ordenado: Más cercano" has no s of its own;
	-- release review, the s of "Más" was underlined)
	local stop = math.min(label:find(":", 1, true) or #label + 1, label:find("\239\188\154", 1, true) or #label + 1)
	if at and at >= stop then at = nil end
	local m = strip and strip.measure
	if not (at and m) then u:Hide() return end
	m:SetText(label:sub(1, at - 1))
	local before = at > 1 and (m:GetStringWidth() or 0) or 0
	m:SetText(label:sub(at, at))
	local wide = m:GetStringWidth() or 0
	if wide <= 0 then u:Hide() return end
	u:ClearAllPoints()
	u:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", math.floor(before + 0.5), 0)
	u:SetWidth(math.max(1, math.floor(wide + 0.5)))
	u:Show()
	b.underAt, b.underWide = before, wide -- (tests)
end

--- A button's background: the accent, stronger when it has something picked, a little more under the pointer.
function B.Shade(b)
	local ar, ag, ab = Theme.RGB(Theme.Get().accent)
	b.bg:SetColorTexture(ar, ag, ab, (b.active and 0.18 or 0) + (b.hover and not b.off and 0.14 or 0))
end

local MENU_W, LINE = 180, 20
local function MenuFrame()
	if B.menu then return B.menu end
	local m = CreateFrame("Frame", "TerminalBarMenu", UIParent, "BackdropTemplate")
	if ns.Zen then ns.Zen.Made(m) end -- (made while .zen has the interface faded: kept up, Zen.lua; else it faded with it)
	m:SetFrameStrata("TOOLTIP")
	m:SetClampedToScreen(true)
	m:EnableMouse(true)
	m.lines = {}
	pcall(m.RegisterEvent, m, "GLOBAL_MOUSE_DOWN")
	m:SetScript("OnEvent", function()
		if m:IsShown() and not (m.IsMouseOver and m:IsMouseOver()) and not (m.owner and m.owner.IsMouseOver and m.owner:IsMouseOver()) then
			m:Hide()
		end
	end)
	m:Hide()
	B.menu = m
	return m
end

local function MenuLine(m, i)
	local b = m.lines[i]
	if b then return b end
	b = CreateFrame("Button", nil, m)
	b:SetSize(MENU_W - 8, LINE)
	b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * LINE)
	b.fs = b:CreateFontString(nil, "OVERLAY")
	b.fs:SetFontObject(Theme.fonts.small)
	b.fs:SetPoint("LEFT", 20, 0)
	b.fs:SetPoint("RIGHT", -6, 0)
	b.fs:SetJustifyH("LEFT")
	b.check = b:CreateTexture(nil, "OVERLAY")
	b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.check:SetSize(14, 14)
	b.check:SetPoint("LEFT", 3, 0)
	-- (a sort's way: the game's sort arrow, as its auction house columns show it, up or down; 0.65.5)
	b.arrow = b:CreateTexture(nil, "OVERLAY")
	b.arrow:SetTexture(B.ARROW)
	b.arrow:SetSize(9, 8)
	b.arrow:SetPoint("CENTER", b.check, "CENTER", 0, 0)
	b.arrow:Hide()
	b.hl = b:CreateTexture(nil, "BACKGROUND")
	b.hl:SetAllPoints()
	b.hl:Hide()
	b:SetScript("OnEnter", function() b.hl:Show() end)
	b:SetScript("OnLeave", function() if not (m.keys and m.keySel == i) then b.hl:Hide() end end)
	b:SetScript("OnClick", function()
		local which, id = m.which, b.id
		if id == nil then return end -- (a line saying something: nothing to pick)
		if id == false then B.Clear(which) m:Hide() return end
		B.Pick(which, id)
		-- (filters add up: it stays open, the keys' line where it was)
		-- (the keys' line: the one picked again, found by what it is; a typed one unticked has gone: the line where it was)
		if which == "filter" then B.ShowMenu(which, m.owner, m.keys, m.keys and m.keySel, id) else m:Hide() end
	end)
	m.lines[i] = b
	return b
end

local function HasOn(opts) for _, o in ipairs(opts) do if o.on then return true end end return false end

--- A button's menu, under it: its options, the ones picked ticked (typed ones say so), "None" on top to clear.
function B.ShowMenu(which, owner, keys, sel, selId)
	local m = MenuFrame()
	local t = Theme.Get()
	local opts = B.Options(which)
	local items = { { id = false, label = which == "filter" and L["No filter"] or which == "sort" and L["Best match"] or L["No groups"],
		on = #opts == 0 or not HasOn(opts) } }
	for _, o in ipairs(opts) do items[#items + 1] = o end
	if #opts == 0 then items[#items + 1] = { label = L["Nothing to pick for these results"], dead = true } end
	m.which, m.owner = which, owner
	for i, it in ipairs(items) do
		local b = MenuLine(m, i)
		-- ("No filter" is false: kept, not turned into nil by an and/or; a line saying something has none)
		if it.dead then b.id = nil else b.id = it.id end
		b.fs:SetText(it.typed and L["%s (typed)"]:format(it.label) or it.label)
		b.fs:SetTextColor(Theme.RGB(it.dead and t.dim or (it.on and t.accent or t.text)))
		local way = it.on and it.asc ~= nil
		b.check:SetShown((it.on and not way) and true or false)
		b.arrow:SetShown(way and true or false)
		if way then
			if it.asc then b.arrow:SetTexCoord(0, 0.5625, 1, 0) else b.arrow:SetTexCoord(0, 0.5625, 0, 1) end -- (up / down)
			b.arrow:SetVertexColor(Theme.RGB(t.accent))
		end
		b.hl:SetColorTexture(Theme.RGB(t.accent))
		b.hl:SetAlpha(0.25)
		b.hl:Hide()
		b:EnableMouse(not it.dead)
		b:Show()
	end
	for i = #items + 1, #m.lines do m.lines[i]:Hide() end
	-- (opened from the keys, Alt+F/S/G: a line picked to move from, the one ticked first; B.MenuKey)
	m.n, m.keys, m.keySel = #items, keys and true or nil, nil
	if keys then
		local first, byId
		for i, it in ipairs(items) do
			if it.on and i > 1 then first = first or i end
			if selId ~= nil and it.id == selId and not it.dead then byId = byId or i end
		end
		B.MenuSelect(byId or (sel and math.min(sel, #items)) or first or 1)
	end
	m:SetSize(MENU_W, #items * LINE + 8)
	ns.Panel.Flat(m)
	local r, g, bb = Theme.RGB(t.bg)
	m:SetBackdropColor(r, g, bb, 0.97)
	m:SetBackdropBorderColor(Theme.RGB(t.border))
	m:SetScale(t.scale or 1)
	m:ClearAllPoints()
	-- (by screen position, as the row menu is: never anchored into the terminal's frame)
	local left, bottom, os, ms = owner:GetLeft(), owner:GetBottom(), owner:GetEffectiveScale(), m:GetEffectiveScale()
	if type(left) == "number" and type(bottom) == "number" and type(os) == "number" and type(ms) == "number" and ms > 0 then
		m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * os / ms, bottom * os / ms - 2)
	else
		m:SetPoint("CENTER", UIParent, "CENTER")
	end
	m:Show()
end

function B.HideMenu() if B.menu then B.menu:Hide() end end

----------------------------------------------------------------------
-- The keys (0.55.13, the player: "allow Alt+F, Alt+S and Alt+G to step into the filter, sort and group menus"): the
-- menu opens with a line picked; Up/Down (Tab) move, Enter or Space picks (Filter's stay open), Left/Right go to the
-- next menu, Esc closes it. Any other key closes it and does what it does.
----------------------------------------------------------------------

B.ALT_KEYS = { F = "filter", S = "sort", G = "group" }

--- Alt+F's character, when the client types one for it (Windows types the f, a Mac's Option+F ƒ; 0.55.19, the player:
--- "pressing Alt+G is both typing g and opening the menu"): not typed. Only that key's letter, or a character a Mac
--- makes of it, and only before the next key goes down (Keys.lua): nothing coming, the next letter isn't eaten.
function B.SwallowAltChar(key)
	UI.swallowChar = { at = GetTime(), letter = type(key) == "string" and ns.Lower(key) or nil }
end
local ORDER = { "filter", "sort", "group" }

--- Line `i` of the open menu picked from the keys (round the ends; a line saying something skipped).
function B.MenuSelect(i, dir)
	local m = B.menu
	if not (m and m.n and m.n > 0) then return end
	for _ = 1, m.n do
		i = (i - 1) % m.n + 1
		if m.lines[i].id ~= nil then break end
		i = i + (dir or 1)
	end
	if m.keySel and m.lines[m.keySel] then m.lines[m.keySel].hl:Hide() end
	m.keySel = i
	m.lines[i].hl:Show()
end

--- Alt+F / Alt+S / Alt+G: that menu, from the keys. False when the bar isn't showing (the key does what it did).
function B.KeyOpen(which)
	if not B.On() then return false end
	B.Update()
	local s = B.strip
	if not s then return false end
	if UI.HideRowMenu then UI:HideRowMenu() end -- (one menu from the keys at a time)
	for _, b in ipairs(s.buttons) do
		-- (one that can't be used now, Sort and Group over the categories, as a click: the key taken, nothing opened)
		if b.which == which then
			if b.off then B.HideMenu() return true end
			B.ShowMenu(which, b, true)
			return true
		end
	end
	return false
end

--- A key while a bar menu opened from the keys is up: true when it was the menu's.
function B.MenuKey(f, key)
	local m = B.menu
	if not (m and m.keys and m:IsShown()) then return false end
	local function Took() f:SetPropagateKeyboardInput(false) return true end
	if IsAltKeyDown and IsAltKeyDown() and B.ALT_KEYS[key] then
		B.SwallowAltChar(key)
		if B.ALT_KEYS[key] == m.which then B.HideMenu() else B.KeyOpen(B.ALT_KEYS[key]) end
		return Took()
	end
	if key == "UP" or (key == "TAB" and IsShiftKeyDown()) then
		B.MenuSelect((m.keySel or 1) - 1, -1)
	elseif key == "DOWN" or key == "TAB" then
		B.MenuSelect((m.keySel or 0) + 1, 1)
	elseif key == "LEFT" or key == "RIGHT" then
		-- (the next menu that can be used: Filter alone over the categories)
		local at, step = 1, key == "LEFT" and -1 or 1
		for i, w in ipairs(ORDER) do if w == m.which then at = i end end
		local off = {}
		for _, b in ipairs(B.strip and B.strip.buttons or {}) do off[b.which] = b.off end
		for _ = 1, #ORDER do
			at = (at - 1 + step) % #ORDER + 1
			if not off[ORDER[at]] then break end
		end
		if ORDER[at] ~= m.which then B.KeyOpen(ORDER[at]) end
	elseif key == "ENTER" or key == "NUMPADENTER" or key == "SPACE" then
		if key == "SPACE" then UI.swallowChar = { at = GetTime(), ch = " " } end
		local b = m.keySel and m.lines[m.keySel]
		if b then b:GetScript("OnClick")(b) end
	elseif key == "ESCAPE" or ns.IsTickKey(key) then
		B.HideMenu()
	else
		B.HideMenu()
		return false
	end
	return Took()
end

--- The first result to send (the selected one when it is one), its place in the list; nil when none is.
function B.FirstReal()
	local res = UI.results or {}
	if Real(res[UI.sel]) then return UI.sel end
	for i, e in ipairs(res) do if Real(e) then return i end end
	-- (grouped or summed up: its rows, to copy out all of them; 0.55.18, review: the button was greyed out)
	for i, e in ipairs(res) do if type(e) == "table" and e.kind == "aggregate" and not e.noActivate then return i end end
end

--- The send button: every result at once, to a channel or copied (0.55.12, the player: the "All" lines only here; a
--- row's own are its right-click menu's).
function B.Horn()
	B.HideMenu()
	local i = B.FirstReal()
	if not i then ns:Print(L["Nothing to send yet: search for something first."]) return end
	UI:ShowRowMenu(i, false, true)
end

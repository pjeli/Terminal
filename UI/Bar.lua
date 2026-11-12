local find = string.find
local ns = select(2, ...)
local L = ns.L

-- The bar (0.55.1, experimental; the player: "if we are outside of advanced mode, let's try to add some tabs for
-- filtering, sorting, grouping, and a little announcement horn for putting out to say, party, raid, text"): a strip
-- under the prompt in Simple mode, so what Advanced syntax does is a click away.
--
--   Filter   what the shown lists can be narrowed by: quality, usable, upgrades, known spells, complete quests...
--            (several at once; each an Advanced filter the search takes as it takes a typed one)
--   Sort     by distance, or by name, level, item level, quality, value, count (what the rows have), either way
--   Group    a row per zone, quality, type, slot, dungeon... with how many in each (Advanced's "| group by")
--   (horn)   the selected result, or all of them, to say, party, raid, guild..., or copied as text or CSV
--
-- What the words typed already ask shows too ("rare sword": Filter: Rare; "nearest ...": Sort: Distance), and unticking
-- it takes the word out of the line: the bar is one more way to write the search's query. A question's answer ("my
-- auctions") is filtered, sorted and grouped like any search's rows. A click on one opens its menu; a right-click
-- clears it. What's picked lasts while the prompt has words and goes when it's cleared or the terminal closes. Typing
-- Advanced syntax takes the bar away (that line is Advanced); Alt+`, or Advanced syntax typed after the words, writes
-- what's picked into the line ("q:rare+ sort:distance | group by zone": the search's query printed, Search.lua's
-- ns.QueryToAdvanced). While the categories show (nothing picked yet), only Filter works: they count what passes it.

local UI, Theme = ns.UI, ns.Theme
local B = {}
ns.Bar = B

B.H = 22
local state = { filters = {}, sort = nil, group = nil, thenBy = nil } -- (thenBy: Sort's "then by", Shift picked)
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
	-- every list's own, offered where its list is shown (F.APPLIES)
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
	-- (OneForAll's and AtlasLoot's, in @reputation. Only when there are some: on a plain reputation list they only
	-- emptied it)
	{ id = "is:reward", label = L["Quartermaster rewards"], needs = "repReward" },
	{ id = "is:canbuy", label = L["Can buy now"], needs = "repReward" },
}
-- what Sort offers: distance (sort:distance's lists), else a field the rows have (Aggregate's, and the name)
-- a sort's way, in the menu: the game's sort arrow (down as drawn, up flipped)
B.ARROW = "Interface\\Buttons\\UI-SortArrow"
-- (the sorts picked the lowest first: by words, A-Z; distance, the nearest)
B.LOW_FIRST = { name = true, owner = true, line = true, distance = true }
B.SORTS = {
	{ id = "distance", label = L["Distance"], near = true, asc = true },
	{ id = "name", label = L["Name"], field = "name", asc = true },
	{ id = "level", label = L["Level"], field = "level", asc = true },
	{ id = "ilvl", label = L["Item level"], field = "ilvl" },
	{ id = "quality", label = L["Quality"], field = "quality" },
	{ id = "value", label = L["Value"], field = "value" },
	{ id = "count", label = L["Count"], field = "count" },
	{ id = "damage", label = L["Biggest hit"], field = "damage" },
	{ id = "line", label = L["Line by line"], field = "line", asc = true },
	{ id = "owner", label = L["Owner"], field = "owner", asc = true }, -- (friends' items, Terminal: Share)
	{ id = "standing", label = L["Standing"], field = "standing", asc = true }, -- (reputations and their rewards)
	{ id = "progress", label = L["Progress"], field = "progress" }, -- (achievements, quests: the closest to done first)
	-- (the rows in their lists' own order, never your picks first: a search question's line; docs/QUESTIONS.md. No
	-- Aggregate field: not on the bar's Sort, which offers the fields rows have)
	{ id = "list", label = L["List order"], field = "list", asc = true },
	-- (your quest log's grey quests first, then by level, then by name: "quests to drop")
	{ id = "grey", label = L["Grey first"], field = "grey", asc = true, tie = "level" },
	-- (recipes to learn: the least skill first, then by profession and name, "recipes i can learn")
	{ id = "need", label = L["Skill needed"], field = "need", asc = true, tie = "prof" },
}
B.DISTANCE_FIELD = { id = "distance", field = "distance", asc = true } -- (a later part of a sort: SortSpec)
-- what Group offers: Aggregate's fields that name something
B.GROUPS = { "kind", "owner", "faction", "standing", "zone", "quality", "type", "slot", "dungeon", "raid", "boss", "level" }

local function E() return ns.Easy end
local function ById(list, id) for _, o in ipairs(list) do if o.id == id then return o end end end
--- A sort's id without its direction, and whether it's the other way round ("-level": the highest first).
local function SortParts(id)
	if type(id) == "string" and id:sub(1, 1) == "-" then return id:sub(2), true end
	return id, false
end
--- Which way a sort goes: true for ascending (A-Z, the lowest first), from its field's own way and the - before it.
local function Ascending(s, rev)
	local asc = s.asc and true or false
	if rev then asc = not asc end
	return asc
end
B.ById = ById

--- Is the bar in use: Simple mode (not a line run in Advanced, not fuzzy finding), searching, words typed?
function B.On()
	local Ez = E()
	-- (Ctrl+R's history search: its lines, nothing to filter)
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
	if #state.filters == 0 and not state.sort and not state.group and not state.thenBy then return nil end
	return state
end

--- The bar's sort as the search takes it: with its "then by" (Shift picked) after it ("level,name"), never after
--- distance (Query.lua's Scan.Parse).
function B.SortWord(st)
	st = st or state
	local s = st and st.sort
	if not s then return nil end
	if st.thenBy and s ~= "distance" and s ~= "-distance" then
		local first = (s .. ","):match("^([^,]*),")
		return first .. "," .. st.thenBy
	end
	return s
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
	return { filters = f, sort = state.sort, group = state.group, thenBy = state.thenBy }
end
function B.Restore(saved)
	state.filters, state.sort, state.group, state.thenBy = {}, saved.sort, saved.group, saved.thenBy
	for i, id in ipairs(saved.filters or {}) do state.filters[i] = id end
end

function B.Reset()
	local had = #state.filters > 0 or state.sort or state.group or state.thenBy
	state.filters, state.sort, state.group, state.thenBy = {}, nil, nil, nil
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
		-- (an everyday word's of those kinds, "rare"; any filter typed as key:value, in:"Scarlet Monastery" a group's
		-- Enter wrote: you're in that group, the bar says so and takes it back out)
		local shown = (type(p.word) == "string" and p.word:find("^[-!]?%a+:") ~= nil) or p.plain == true
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
			elseif (k2 == "lvl" or k2 == "level") and v2:find("me", 1, true) and ns.Easy and ns.Easy.LevelSay then
				out = ns.UpperFirst(ns.Easy.LevelSay(v2)) -- ("3 levels above yours"; review)
			elseif k2 == "since" and ns.Easy and ns.Easy.SinceSay then out = ns.Easy.SinceSay(v2, true)
			elseif (k2 == "older" or k2 == "before") and ns.Easy and ns.Easy.TimeSay then
				out = (v2:find("^%d") and L["Older than %s"] or L["Before %s"]):format(ns.Easy.TimeSay(v2))
			elseif k2 == "lvl" or k2 == "level" then out = L["Level %s"]:format(v2)
			elseif k2 == "ilvl" or k2 == "itemlevel" then out = L["Item level %s"]:format(v2)
			elseif k2 == "value" or k2 == "worth" then out = L["Worth %s"]:format(v2)
			elseif k2 == "slots" then out = L["Slots %s"]:format(v2)
			elseif k2 == "dura" or k2 == "durability" then out = L["Durability %s%%"]:format(v2)
			else out = ns.UpperFirst(v2) end
			neg = n2
		end
	end
	if out and neg ~= "" then return L["Not %s"]:format(ns.Lower(out)) end
	return out or ns.UpperFirst(word or tostring(spec))
end

--- The prompt set to what's left once words were taken out of `old`: one space between words, none at the ends, but a
--- space typed after the last word stays (the next word is on its way). The search runs again.
local function Put(text)
	if UI.SetQuery then UI:SetQuery(text, #text) else UI.edit:SetText(text) end
end
local function SetLeft(old, text)
	local had = old:find("%s$")
	text = text:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if had and text ~= "" then text = text .. " " end
	Put(text)
end

--- Words taken out of the prompt (case aside, whole words; a phrase's spaces any spaces), the search run again.
function B.DropWords(words)
	local edit = UI.edit
	if not edit then return end
	local text = edit:GetText() or ""
	-- the ways each may stand in the line: a filter's value of several words is read without its quotes (in:Scarlet
	-- Monastery; the line has them); "not boe" is read as -boe (Easy.JoinLogic: the line has the words)
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
		local pat = ns.EscapePattern(ns.Lower(w)):gsub("%s+", "%%s+")
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
	SetLeft(edit:GetText() or "", text)
end

--- The prompt's text with these spans of it ({ s, e = bytes, line = the line read, pieces = the spans to take out
--- instead, a join's words around a "quoted phrase" }, the search's: Search.lua's Picked) cut out, or put `new` in place
--- of them; nil when they don't fit the prompt any more (it isn't the line read).
local function CutSpans(text, spans, new)
	local list, seen = {}, {}
	for _, sp in ipairs(spans) do
		if not (type(sp) == "table" and sp.s and sp.e and sp.line) or text:sub(1, #sp.line) ~= sp.line then return nil end
		-- (and the prompt goes on after it with a new word, or not at all: "under level 25" isn't "under level 2" read
		-- a keystroke ago, whose span would leave the "5"; review)
		local after = text:sub(#sp.line + 1, #sp.line + 1)
		if after ~= "" and not after:find("%s") then return nil end
		for _, piece in ipairs(sp.pieces or { sp }) do
			local key = piece.s .. ":" .. piece.e
			if not seen[key] then seen[key] = true; list[#list + 1] = piece end
		end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a.s > b.s end) -- (the last first: the earlier ones' bytes stay where they were)
	for k = 2, #list do if list[k].e >= list[k - 1].s then return nil end end -- (overlapping: not one of the line's readings)
	for _, sp in ipairs(list) do text = text:sub(1, sp.s - 1) .. (new or "") .. text:sub(sp.e + 1) end
	return text
end
B.CutSpans = CutSpans

--- Typed picks ({ word, src }: B.Typed's filters, sort, group) taken out of the prompt: each by where it is in the line
--- (FRONT_END.md 4.4: never another filter's words that read the same, "boe linen not boe" unticked Boe keeps "not
--- boe"; a filter typed twice is two items, B.Pick passes both);
--- the prompt changed since it was read, by their words as before (B.DropWords).
function B.DropTyped(items)
	local edit = UI.edit
	if not edit then return end
	local spans, words = {}, {}
	for _, it in ipairs(items) do
		spans[#spans + 1] = it.src or false
		words[#words + 1] = it.word
	end
	local old = edit:GetText() or ""
	local text = CutSpans(old, spans)
	if not text then return B.DropWords(words) end
	SetLeft(old, text)
end

--- A typed pick's word in the prompt in place of another word ({ word, src }): by where it is, else by its word.
function B.SwapTyped(item, new)
	local edit = UI.edit
	if not (edit and item) then return end
	local text = CutSpans(edit:GetText() or "", { item.src or false }, new)
	if not text then return B.SwapWord(item.word, new) end
	Put(text)
end

--- A word of the line in place of another (whole words, the first one): "nearest mailbox" -> "farthest mailbox".
function B.SwapWord(old, new)
	local edit = UI.edit
	if not (edit and type(old) == "string" and old ~= "") then return end
	local text = edit:GetText() or ""
	local lower = ns.Lower(text)
	local pat = ns.EscapePattern(ns.Lower(old))
	local from = 1
	while true do
		local a, b = lower:find(pat, from)
		if not a then return end
		local before, after = lower:sub(a - 1, a - 1), lower:sub(b + 1, b + 1)
		if (a == 1 or before:find("%s")) and (after == "" or after:find("%s")) then
			text = text:sub(1, a - 1) .. new .. text:sub(b + 1)
			Put(text)
			return
		end
		from = a + 1
	end
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
	-- (sort:list: the list's own order, its _rank (ns.RankInOrder: the first highest); a list without one keeps the order
	-- it gives its rows, every key the same and Keyed's tie the row's place)
	if s.field == "list" then
		local r = rawget(e, "_rank")
		if r == nil then r = e._rank end
		return -(tonumber(r) or 0)
	end
	if s.field == "name" then
		-- (the lowered name the search keeps, when it has no colour codes to take out: a sort of 100k rows)
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
--- Of two rows' keys for the "then by" sorts (`more`: { { s, asc } ... }), which comes first: -1, 1, or 0 for a tie (a
--- row without the field after one with it).
local function ThenOrder(more, am, bm)
	for j, m in ipairs(more) do
		local x, y = am[j], bm[j]
		if x ~= y then
			if x == nil then return 1 end
			if y == nil then return -1 end
			if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
			if m.asc then return x < y and -1 or 1 end
			return x > y and -1 or 1
		end
	end
	return 0
end
local function MoreKeys(more, e)
	if not more then return nil end
	local t = {}
	for j, m in ipairs(more) do t[j] = KeyOf(m.s, e) end
	return t
end
local function Keyed(s, rows, asc, more)
	if asc == nil then asc = s.asc end
	if more and #more == 0 then more = nil end
	local keyed, rest = {}, {}
	-- (a tie-breaker field, lowest first: sort:slots, then the level)
	local tie = s.tie and { field = s.tie }
	for i, e in ipairs(rows) do
		if Real(e) then
			local k = KeyOf(s, e)
			if k ~= nil then keyed[#keyed + 1] = { e = e, k = k, i = i, t = tie and KeyOf(tie, e) or nil, m = MoreKeys(more, e) }
			else rest[#rest + 1] = e end
		end
	end
	-- (a sort with a tie field, sort:slots: then by name, as its question lists them; the rows without the field after,
	-- by the tie field then the name too, not as they came: 0.65.x review, Simple and Advanced listed them otherwise)
	local NAME = tie and { field = "name" }
	table.sort(keyed, function(a, b)
		if a.k ~= b.k then
			if asc then return a.k < b.k end
			return a.k > b.k
		end
		-- (then by the fields typed after it: sort:quality,-level)
		if more then
			local o = ThenOrder(more, a.m, b.m)
			if o ~= 0 then return o < 0 end
		end
		if a.t ~= b.t and a.t ~= nil and b.t ~= nil then return a.t < b.t end
		if NAME then
			local an, bn = KeyOf(NAME, a.e), KeyOf(NAME, b.e)
			if an ~= bn then return an < bn end
		end
		return a.i < b.i
	end)
	if tie and #rest > 1 then
		local r = {}
		for i, e in ipairs(rest) do r[i] = { e = e, i = i, t = KeyOf(tie, e), n = KeyOf(NAME, e) } end
		table.sort(r, function(a, b)
			if a.t ~= b.t then
				if a.t == nil then return false end
				if b.t == nil then return true end
				return a.t < b.t
			end
			if a.n ~= b.n then return a.n < b.n end
			return a.i < b.i
		end)
		for i, x in ipairs(r) do rest[i] = x.e end
	end
	return keyed, rest
end

--- The search's rows in a field's order (Search.lua's Finalize, "sort:name" typed or picked on the bar): the rows that
--- have it scored above any search score, in its order (a pinned row stays on top). Past 5000 rows, only the first
--- `keep` (the rows shown) are found, with a bounded heap: not every row sorted. `overBudget`: the search's clock, to
--- yield on. A sort's id (several: "quality,-level") as its first field's sort, its way, and the fields after it, each
--- with its way: s, asc, { { s, asc } ... }; nil when the first isn't a field's.
local function SortSpec(id)
	local parts = {}
	if type(id) == "string" then for part in (id .. ","):gmatch("([^,]*),") do if part ~= "" then parts[#parts + 1] = part end end end
	local base, rev = SortParts(parts[1])
	local s = ById(B.SORTS, base)
	if not (s and s.field) then return nil end
	local more = {}
	for j = 2, #parts do
		local b2, r2 = SortParts(parts[j])
		local s2 = ById(B.SORTS, b2)
		-- (distance after a field: the yards the search worked out)
		if b2 == "distance" then s2 = B.DISTANCE_FIELD end
		if s2 and s2.field then more[#more + 1] = { s = s2, asc = Ascending(s2, r2) } end
	end
	return s, Ascending(s, rev), more
end
B.SortSpec = SortSpec

function B.SortRows(rows, id, keep, overBudget)
	local s, asc, more = SortSpec(id)
	if not s then return rows end
	if #rows <= 5000 then
		local keyed, rest = Keyed(s, rows, asc, more)
		for i, r in ipairs(keyed) do r.e._score = 1e10 - i end
		-- (a sort with a tie field: the rows without the field after, in the tie's order; Keyed)
		if s.tie then for i, e in ipairs(rest) do e._score = 1e9 - i end end
		return rows
	end
	keep = keep or 100
	-- (a before b in the field's order; the earlier row first on a tie)
	if #more == 0 then more = nil end
	local function Before(a, b)
		if a.k ~= b.k then if asc then return a.k < b.k end return a.k > b.k end
		if more then
			-- (the "then by" keys worked out only for rows that tie: not for every row; review)
			if not a.m then a.m = MoreKeys(more, a.e) end
			if not b.m then b.m = MoreKeys(more, b.e) end
			local o = ThenOrder(more, a.m, b.m)
			if o ~= 0 then return o < 0 end
		end
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
			local top = size >= keep and heap[1]
			-- (one that's plainly after the last kept: no table made for it, past 5000 rows most aren't kept; review)
			if k ~= nil and not (top and top.k ~= k and (asc and k > top.k or not asc and k < top.k)) then
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
	local s, asc, more = SortSpec(id)
	if not s or #rows > 5000 then return rows end
	local out, run = {}, {}
	local function Flush()
		if #run == 0 then return end
		local keyed, rest = Keyed(s, run, asc, more)
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
		local function Some(field)
			for _, e in ipairs(UI.results or {}) do if type(e) == "table" and e[field] then return true end end
			for _, e in ipairs(UI.ungrouped or {}) do if type(e) == "table" and e[field] then return true end end
			return false
		end
		for _, o in ipairs(B.FILTERS) do
			if not listed[o.id] and (on[o.id] or (Fits(o.id, kinds) and not (o.needs and not Some(o.needs)))) then
				out[#out + 1] = { id = o.id, label = o.label, on = on[o.id] }
			end
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
	-- ("I am already in a chosen group and it is letting me group again" (a group's Enter: its rows all in one dungeon)
	-- only what tells the rows apart: two values or more, as a sort or a group by one value does nothing)
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
		-- (a typed sort of several fields, sort:quality,-level: its first is the sort, the next its "then by")
		local typedList = ns.Filters and ns.Filters.SortList and ns.Filters.SortList(typed.sort and typed.sort.id) or {}
		local typedBase, typedRev = SortParts(typedList[1])
		local thenBase, thenRev = SortParts(state.thenBy or (not state.sort and typedList[2]) or nil)
		for _, o in ipairs(B.SORTS) do
			local typedHere = typedBase == o.id
			local fits = o.near and Fits("sort:distance", kinds) or (o.field and Has(o.field))
			local on = pickedBase == o.id or typedHere
			local isThen = not on and thenBase == o.id and o.field and true or false
			if isThen then
				-- (the "then by": its arrow too, said as such)
				out[#out + 1] = { id = o.id, label = o.label, on = true, thenBy = true, asc = Ascending(o, thenRev) }
			elseif fits or on then
				-- (which way: an arrow, up for ascending, down for descending, in the tick's place) (a word typed that
				-- sorts by distance, "farthest innkeeper": the search goes by it, so the arrow does too; 0.65.x review:
				-- the arrow said nearest over the farthest listed)
				local said = typedHere and typed.sort and not typed.sort.drop
				local rev = (said and typedRev) or (pickedBase == o.id and pickedRev) or (pickedBase ~= o.id and typedHere and typedRev)
				-- (asc: true, false or nil, not on: not "on and Ascending or nil", which made a descending one's false nil)
				local asc
				if on and (o.field or o.near) then asc = Ascending(o, rev) end
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
function B.Pick(which, id, thenBy)
	local typed = B.Typed()
	if which == "sort" and thenBy then return B.PickThen(id) end
	if which == "filter" then
		-- (one typed as a word, not picked here: its word taken out of the line)
		local mine = false
		for _, f in ipairs(state.filters) do if f == id then mine = true end end
		if not mine then
			-- (every place it was typed, "rare sword rare": unticked, it's gone; only those, never another filter's words
			-- that read the same: "boe linen not boe" keeps "not boe")
			local said = {}
			for _, p in ipairs(typed.filters) do if p.spec == id then said[#said + 1] = p end end
			if #said > 0 then B.DropTyped(said) B.Update() return end
		end
		local had
		for i, f in ipairs(state.filters) do if f == id then table.remove(state.filters, i); had = true break end end
		if not had then state.filters[#state.filters + 1] = id end
	elseif which == "sort" then
		-- (the one picked again: the other way round, the highest first or the lowest; "Best match" undoes it)
		local o = ById(B.SORTS, id)
		local turns = o and (o.field or o.near) and true or false
		local pickedBase, pickedRev = SortParts(state.sort)
		-- (a typed sort of several fields, sort:quality,-count: its first is the one shown as on; review: the whole list
		-- was compared with the pick, and never matched)
		local typedList = typed.sort and ns.Filters.SortList(typed.sort.id) or {}
		local typedBase, typedRev = SortParts(typedList[1])
		-- (a word typed that says the sort, "nearest mailbox": turned round, the word is ("farthest mailbox"), as the word
		-- says the list too: taken out, "mailbox" alone searched no mailboxes; 0.65.x review)
		if typedBase == id and typed.sort and not typed.sort.drop and o and o.near then
			state.sort = nil
			B.SwapTyped(typed.sort, typedRev and "nearest" or "farthest")
			B.Update()
			return
		end
		if typedBase == id and pickedBase ~= id then
			-- (typed as a word: the word goes, and the bar's own sort is it turned round; one that doesn't turn, nearest,
			-- just goes, as before)
			if turns then state.sort = typedRev and id or ("-" .. id) end
			-- (and its "then by" kept, the bar's own now)
			if turns and typedList[2] and not state.thenBy then state.thenBy = typedList[2] end
			B.DropTyped({ typed.sort })
			B.Update()
			return
		end
		if pickedBase == id then
			if not turns then state.sort = nil B.Changed() return end -- (one with no other way round: unpicked)
			state.sort = pickedRev and id or ("-" .. id)
			B.Changed()
			return
		end
		-- (picked: the highest first, as the player said, "assume descending at first": the level too; the words'
		-- sorts, a name, an owner, an attunement's lines, A-Z first; picked again, the other way)
		state.sort = (turns and o.asc and not B.LOW_FIRST[id]) and ("-" .. id) or id
		-- (another sort picked: a sort: typed goes from the line, one sort at a time; "nearest" stays, it says the NPCs)
		if state.sort and typed.sort and typed.sort.drop then
			B.DropTyped({ typed.sort })
			B.Update()
			return
		end
	elseif which == "group" then
		-- (a group typed: unticked, or another picked, its step goes from the line; the bar's own group then)
		if typed.group then
			state.group = (typed.group.id ~= id) and id or nil
			-- ("quests per zone": the words were the group; its list is what's left, "@questie")
			if typed.group.rest and UI.edit then UI:SetQuery(typed.group.rest, #typed.group.rest)
			else B.DropTyped({ typed.group }) end
			B.Update()
			return
		end
		state.group = (state.group ~= id) and id or nil
	end
	B.Changed()
end

--- Shift picked on Sort: rows that tie on the sort go by this one. Picked again: the other way round; a third time:
--- gone. Nothing sorted yet: it's the sort. A typed sort of several fields (sort:quality,-level) becomes the bar's own
--- first, its word taken out.
function B.PickThen(id)
	local typed = B.Typed()
	local o = ById(B.SORTS, id)
	if not (o and o.field) then return B.Pick("sort", id) end
	local list = ns.Filters and ns.Filters.SortList and ns.Filters.SortList(typed.sort and typed.sort.id) or {}
	local dropWord -- (the typed sort, to take out of the line)
	local firstField = list[1] and ById(B.SORTS, (SortParts(list[1])))
	if not state.sort and list[1] and firstField and firstField.field then
		-- (the typed sort is the bar's own now: its first field, and its "then by" when it had one)
		state.sort = list[1]
		if list[2] and not state.thenBy then state.thenBy = list[2] end
		dropWord = typed.sort.drop and typed.sort or nil
	end
	local base = SortParts(state.sort)
	if not state.sort or base == "distance" or base == id then
		if dropWord then state.sort, state.thenBy = nil, nil end
		return B.Pick("sort", id)
	end
	local thenBase, thenRev = SortParts(state.thenBy)
	local first = (o.asc and not B.LOW_FIRST[id]) and ("-" .. id) or id -- (the way a pick starts: as Sort's)
	if thenBase ~= id then state.thenBy = first
	elseif state.thenBy == first then state.thenBy = (thenRev and id) or ("-" .. id)
	else state.thenBy = nil end
	if dropWord then B.DropTyped({ dropWord }) B.Update() return end
	B.Changed()
end

--- Nothing picked for Filter, Sort or Group: the words typed for it taken out of the line too.
function B.Clear(which)
	local typed, items = B.Typed(), {}
	if which == "filter" then
		state.filters = {}
		for _, p in ipairs(typed.filters) do items[#items + 1] = p end
	elseif which == "sort" then
		state.sort, state.thenBy = nil, nil
		if typed.sort then items[1] = typed.sort end
	else
		state.group = nil
		if typed.group then items[1] = typed.group end
	end
	if #items > 0 then B.DropTyped(items) end
	B.Changed()
end

--- Something picked or dropped: the search again (its filters, sort and summing), the bar redrawn.
--- The "then by" only after a sort of the bar's own that isn't it, nor distance (which sorts its own way): else gone.
local function TidyThen()
	if not state.thenBy then return end
	local nb = SortParts(state.sort)
	if not state.sort or nb == "distance" or SortParts(state.thenBy) == nb then state.thenBy = nil end
end
B.TidyThen = TidyThen

function B.Changed()
	TidyThen()
	UI.lastScan, UI.lastExtra = nil, nil -- (another filter: not a narrowing of the last keystroke's matches)
	if UI.frame and UI:IsShown() then UI:Research() end
	B.Update()
end

-- (BarMenu.lua's: the strip and its menu draw what these hold)
B._ = { state = state, ById = ById, SortParts = SortParts, Real = Real }

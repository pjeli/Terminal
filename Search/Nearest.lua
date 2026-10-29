local ns = select(2, ...)
local L = ns.L

-- "nearest", "farthest", sort:distance: where you are, the rows by how far they are (a heap of the closest), a view
-- saying how far each is, NPC lists nearest first by default. Moved out of Search.lua as it was.

local UI = ns.UI
local Scan = UI._Scan
local Score = ns.Score
local MAX_RESULTS = Score.MAX_RESULTS
local EASY_NONE, PseudoEntries = Scan.EASY_NONE, Scan.PseudoEntries
local EASY_NO_NPCS = L["\"nearest\" needs Questie (or QuestieDB): it knows where NPCs stand."]
local EASY_NOWHERE = L["Can't tell where you are here (in a dungeon?)."]
local EASY_NONE_NEAR = L["None of those on this continent that Questie knows of."]
local EASY_TRAINERS_ONLY = L["None of those near you. Without Questie, Terminal knows only trainers (TrainerSpells'): install Questie for every other NPC."]
local EASY_NO_FLIGHTS = L["No flight path like that on this continent."]
local EASY_ALL_FLIGHTS = L["You know every flight path on this continent."]
local EASY_FLIGHTS_UNCHECKED = L["Terminal doesn't know your flight paths here yet: open any flight master's map on this continent."]

--- Simple mode's "nearest ...": a game object asked for ("nearest mailbox": QuestieDB's objects; an entrance) or flight
--- paths ("nearest unlearned flight master": Flights.lua) give their rows at once; else where you are, for the NPCs that
--- match. Returns the rows to list now (rows, or a line saying why not), or nil, your position and the faction filter to
--- add ("nearest repair": someone who'll serve you, so only NPCs friendly to your faction; "nearest hogger": a name,
--- anyone).
--- Simple mode's role words typed (trainer, vendor, innkeeper... soft or strict): the faction:friendly filter, else nil.
function Scan.RoleFriendly(softWords, strictWords)
	for _, list in ipairs({ softWords or false, strictWords or false }) do
		for _, w in ipairs(list or {}) do
			if ns.Easy.ROLE_WORDS[w] then return ns.Filters and ns.Filters.Parse("faction:friendly") end
		end
	end
	return nil
end

--- "nearest mailbox in moonglade" with none there: the line naming the place (0.68.16: it said "Nothing has that. Check
--- the spelling", as for a word nothing has). Nil when no place was said.
function Scan.NoneThere()
	local place = UI.place
	local name = place and (place.name or place.key)
	return type(name) == "string" and L["None of those in %s that Questie knows of."]:format(name) or nil
end

function Scan.NearestStart(tokens, filters, softWords, strictWords, far)
	local I = ns.Integrations
	local okind = I and I.ObjectKind and I.ObjectKind(tokens)
	-- (the flight paths' words left to be in their names or zones, and "unlearned"/"learned" when said)
	local rest, state
	if not okind and I and I.FlightAsked and ns.providers.flight then
		rest, state = I.FlightAsked(tokens, softWords, not ns.providers.npc)
		if rest then okind = "flight" end
	end
	if okind then
		local spot = I.Here()
		if not spot then return PseudoEntries({ EASY_NOWHERE }) end
		local keep
		if filters or (rest and #rest > 0) then
			keep = function(e)
				if filters and not ns.Filters.Pass(e, filters) then return false end
				for k = 1, rest and #rest or 0 do if not ns.Filters.RowHas(e, rest[k]) then return false end end
				return true
			end
		end
		local rows = I.NearestObjectRows(okind, spot, keep, far)
		local unchecked = okind == "flight" and I.Flights and not I.Flights.Checked(spot.cont)
		if rows and #rows > 0 then
			if unchecked then UI.flightNote = I.Flights.UNCHECKED_NOTE end -- (the footer: each row says "not checked yet")
			return rows
		end
		if rows and okind == "flight" then
			-- no flight master's map read on this continent yet: nothing to say of what you know here (the footer says
			-- so when there are rows); else, nothing narrowed it but the everyday words: every one here is known
			if unchecked then return PseudoEntries({ EASY_FLIGHTS_UNCHECKED }) end
			local only = #rest == 0 and (filters and #filters or 0) == (softWords and #softWords or 0)
			return PseudoEntries({ (state == "unlearned" and only) and EASY_ALL_FLIGHTS or EASY_NO_FLIGHTS })
		end
		if rows then return PseudoEntries({ Scan.NoneThere() or EASY_NONE }) end
	end
	if not ns.providers.npc then return PseudoEntries({ EASY_NO_NPCS }) end
	local here = ns.Integrations and ns.Integrations.Here()
	if not here then return PseudoEntries({ EASY_NOWHERE }) end
	return nil, here, Scan.RoleFriendly(softWords, strictWords)
end

--- A row with a distance, as a view saying how far and what it is ("120 yd  Mining Trainer", a spot row its zone:
--- "120 yd  The Barrens", or what it says after a distance: `distNote`; `nearRest`, which the arrow's live text keeps),
--- scored closest first.
local function NearView(e, d, far)
	local rest = rawget(e, "distNote") or (rawget(e, "wcont") and e.zone) or e.sub
	-- (an NPC in a dungeon: how far its entrance is, and which dungeon; 0.51.18)
	local inside = e.kind == "npc" and e.inDungeon
	if inside then rest = (rest and (rest .. ns.DETAIL_SEP) or "") .. L["in %s"]:format(inside) end
	return ns.Integrations.NearView(e, d, rest, far)
end
Scan.NearView = NearView -- (tests)

--- Would row a's view (da yards away) sort before row b's (db)? Better (Score.lua) on the views NearView makes: the
--- score, then the name, then the key, read through to the rows as the views would.
local function Closer(da, a, db, b)
	local sa, sb = 1e6 - da, 1e6 - db
	if sa ~= sb then return sa > sb end
	local an, bn = a._lname or "", b._lname or ""
	if an ~= bn then return an < bn end
	return Score.KeyLess(a.key, b.key)
end

-- The closest rows so far, a heap of parallel lists (yards, row, place in the matches, its view once made) with the
-- farthest of them on top. A new one at the bottom (k) goes up past the closer ones; one put on top goes down.
local function HeapSwap(hd, he, hi, hv, a, b)
	hd[a], hd[b] = hd[b], hd[a]
	he[a], he[b] = he[b], he[a]
	hi[a], hi[b] = hi[b], hi[a]
	hv[a], hv[b] = hv[b], hv[a]
end
local function HeapUp(hd, he, hi, hv, k)
	while k > 1 do
		local p = math.floor(k / 2)
		if not Closer(hd[p], he[p], hd[k], he[k]) then return end
		HeapSwap(hd, he, hi, hv, p, k)
		k = p
	end
end
local function HeapDown(hd, he, hi, hv, size)
	local k = 1
	while true do
		local l, r, w = k * 2, k * 2 + 1, k
		if l <= size and Closer(hd[w], he[w], hd[l], he[l]) then w = l end
		if r <= size and Closer(hd[w], he[w], hd[r], he[r]) then w = r end
		if w == k then return end
		HeapSwap(hd, he, hi, hv, w, k)
		k = w
	end
end

--- The matched rows that have a distance (Questie's NPCs, rows with a place of their own: @mailbox), each as a view
--- saying how far (NearView) and scored closest first; sort:distance keeps every other row too, after them; in the
--- order they came. Every row's distance is measured (I.RowYards: no table made), but only the MAX_RESULTS closest get
--- a view: a search keeps no more (SortAndTrim), and none of these rows brings a quest along (LinkQuests: NPCs and
--- spots carry none). Pauses with the search, showing the closest so far.
-- (far: sort:-distance, the farthest first (0.65.7, the player): the heap keeps the farthest, by their yards turned
-- negative; the rows with no distance are as if infinitely far, so before them: the views are scored under every row's
-- own score (I.NearView), not those rows made views of their own (0.65.x review: a table per unknown row, thousands)
-- (all: every row with a distance a view, none trimmed: distance only breaks another field's ties, sort:level,distance,
-- and the rows that field puts first can be far; review: the level-10 innkeepers 2000 yards off were dropped)
function Scan.NearestViews(out, here, sortNear, overBudget, far, all)
	local yards, max = ns.Integrations.RowYards, all and math.huge or MAX_RESULTS
	local function Key(d) return far and -d or d end
	local function View(e, key) return NearView(e, far and -key or key, far) end
	local hd, he, hi, hv, size = {}, {}, {}, {}, 0
	local others, at = {}, {} -- (sort:distance: the rows with no distance, as they are, and where they came)
	for i = 1, #out do
		local e = out[i]
		local d = yards(e, here)
		if d then
			d = Key(d)
			if size < max then
				size = size + 1
				hd[size], he[size], hi[size], hv[size] = d, e, i, nil
				HeapUp(hd, he, hi, hv, size)
			elseif Closer(d, e, hd[1], he[1]) then
				hd[1], he[1], hi[1], hv[1] = d, e, i, nil
				HeapDown(hd, he, hi, hv, size)
			end
		elseif sortNear then
			others[#others + 1] = e
			at[#at + 1] = i
		end
		if i % 32 == 0 and overBudget() then
			-- (this frame's look: the rows so far, the closest as views, each made once: the final list keeps it; the
			-- list handed over is copied at once, so the views come off it again)
			local n = #others
			for k = 1, size do
				local v = hv[k]
				if not v then v = View(he[k], hd[k]); hv[k] = v end
				others[n + k] = v
			end
			coroutine.yield(others)
			for k = n + size, n + 1, -1 do others[k] = nil end
		end
	end
	-- the closest in the order they came (at most max: an insertion sort), each among the others where it came
	local order = {}
	for k = 1, size do
		local p, j = hi[k], #order
		while j > 0 and hi[order[j]] > p do order[j + 1] = order[j]; j = j - 1 end
		order[j + 1] = k
	end
	local kept, o, n = {}, 1, #others
	for j = 1, #order do
		local k = order[j]
		while o <= n and at[o] < hi[k] do kept[#kept + 1] = others[o]; o = o + 1 end
		kept[#kept + 1] = hv[k] or View(he[k], hd[k])
	end
	for q = o, n do kept[#kept + 1] = others[q] end
	return kept
end

--- "nearest" / sort:distance: the rows with a distance, closest first (Scan.NearestViews). The rows, and the rows to
--- stop with instead (none near), if any.
--- Does the search look at the NPCs alone (@npc, Simple mode's NPCs)?
function Scan.NpcOnly(kinds)
	if type(kinds) ~= "table" then return false end
	local any = false
	for k, v in pairs(kinds) do
		if v then
			if k ~= "npc" then return false end
			any = true
		end
	end
	return any
end

--- A list of NPCs alone, sorted nearest first by default (0.56.10, the player: "all NPC lists should be sorted by
--- nearest by default", trainers, merchants, reagent vendors). What was typed still counts first (release review: 120
--- nearer NPCs whose names had hogger's letters left Hogger out): an NPC named it, then those whose names have every
--- word, then the rest (a title's word, "reagent"); within each, the closest first, those with no place known last.
--- Only the best `limit` are kept (as many as the search keeps), each a view saying how far.
local function NearBand(e, tokens, n, joined)
	if n == 0 then return 0 end
	local ln = rawget(e, "_lname") or (type(e.name) == "string" and ns.Lower(e.name)) or ""
	if ln == joined then return 2 end
	for k = 1, n do if not ln:find(tokens[k], 1, true) then return 0 end end
	return 1
end
function Scan.NearDefault(out, here, tokens, limit, overBudget)
	local yards, n = ns.Integrations.RowYards, #tokens
	local joined = n > 0 and table.concat(tokens, " ") or nil
	local hc, he, hd, size = {}, {}, {}, 0 -- (a heap, the lowest on top: the best `limit` so far)
	local function Swap(a, b) hc[a], hc[b], he[a], he[b], hd[a], hd[b] = hc[b], hc[a], he[b], he[a], hd[b], hd[a] end
	local function Up(i)
		while i > 1 do
			local p = math.floor(i / 2)
			if hc[i] < hc[p] then Swap(i, p); i = p else return end
		end
	end
	local function Down(i)
		while true do
			local l, r, w = i * 2, i * 2 + 1, i
			if l <= size and hc[l] < hc[w] then w = l end
			if r <= size and hc[r] < hc[w] then w = r end
			if w == i then return end
			Swap(i, w); i = w
		end
	end
	for i = 1, #out do
		local e = out[i]
		local d = yards(e, here)
		local c = NearBand(e, tokens, n, joined) * 2e6 + (d and (1e6 - math.min(d, 999999)) or 0)
		if size < limit then
			size = size + 1
			hc[size], he[size], hd[size] = c, e, d
			Up(size)
		elseif c > hc[1] then
			hc[1], he[1], hd[1] = c, e, d
			Down(1)
		end
		if overBudget and i % 32 == 0 and overBudget() then
			local snap = {}
			for k = 1, size do snap[k] = he[k] end
			coroutine.yield(snap)
		end
	end
	local kept = {}
	for k = 1, size do
		local v = hd[k] and NearView(he[k], hd[k]) or setmetatable({}, { __index = he[k] })
		v._score = hc[k]
		kept[k] = v
	end
	return kept
end

function Scan.Nearest(self, q, out)
	local sortNear, here, overBudget = q.sortNear, q.here, q.overBudget
	-- ("farthest innkeeper", sort:-distance: the farthest first, those with no distance known before them; 0.65.7)
	-- (a word said, "nearest" or "farthest", decides over the bar's: 0.65.x review)
	-- (implied, a role alone: "innkeeper" is the nearest innkeeper unless the bar turns it round)
	local far
	if q.act and q.act.nearest and q.actWord then far = q.act.far or nil else far = q.sortFar end
	-- a list of NPCs alone, no sort asked for: the nearest first (Scan.NearDefault); not where nothing's known of where
	-- you are, nor summed up ("@npc trainer | count": every match counted; release review)
	if not sortNear and not here and not q.sortField and not q.act and Scan.NpcOnly(q.kinds)
		and not (ns.Aggregate and ns.Aggregate.Summing(self.aggregate)) then
		local I = ns.Integrations
		here = I and I.Here and I.Here() or nil
		if here then
			q.here, q.nearDefault = here, true
			return Scan.NearDefault(out, here, q.tokens or {}, q.easyCat and Score.LIST_MAX or MAX_RESULTS, overBudget)
		end
	end
	-- "sort:distance" (Advanced): where you are, once (an instance or no map: no sorting, the footer says so)
	if sortNear and not here then
		here = ns.Integrations and ns.Integrations.Here and ns.Integrations.Here()
		if not here then self.noPosition = true end
	end
	-- "nearest": the NPCs that matched, closest first, how far in the detail column (none known: left out;
	-- sort:distance keeps every other row, after the NPCs, as a weapon's trainers do: q.keepFar, Scan.TrainerWords)
	if here then
		local keep = sortNear or q.keepFar or far
		local matched = out
		out = Scan.NearestViews(out, here, keep, overBudget, far, sortNear and q.sortField ~= nil)
		-- (a place said on another continent, "bank in the barrens" from Ironforge: its own, no distance; 0.68.16)
		if #out == 0 and not keep and self.place and #matched > 0 then
			q.here = here
			return matched
		end
		if #out == 0 and not keep then
			-- (TrainerSpells' trainers as @npc, no Questie: only trainers are known; 0.57.1)
			local p = ns.providers.npc
			return out, PseudoEntries({ (p and p.trainersOnly) and EASY_TRAINERS_ONLY or Scan.NoneThere() or EASY_NONE_NEAR })
		end
	end
	q.here = here
	return out
end

local ns = select(2, ...)
local L = ns.L

-- The steps after a "|" standing alone: sums, counts, groups, first N, comparing two searches (ns.Aggregate). Split
-- out of Pipes.lua (now Steps/Chains.lua, the ">" chains) as it was.

----------------------------------------------------------------------
-- Summing up (0.52.13, the player's ask): Advanced mode's "|" standing alone ends the search; what follows works on
-- every row it found (not only the 100 a list shows), as a shell's pipe:
--
--   in:bags | sum value             what all of it would sell for at a vendor: one row
--   @quest | group zone             a row per zone with how many are there, the most first ("group by zone" too)
--   @item | count                   how many were found; "count by quality": a row per quality, as group
--   in:bags | sum value by quality  a total per quality (and all of them on top); "| avg ilvl by slot"
--   @quest | zone:"Elwynn Forest"   only the rows with that (a group's Enter writes it: Shift+Left goes back)
--
-- Steps chain: "in:bags | q:rare | sum value". The words are fields (ns.Aggregate.FIELDS); a row without one is
-- left out of a sum, and of the groups (0.53.4: no "no zone" group).
----------------------------------------------------------------------

local A = {}
ns.Aggregate = A

local FP = ns.Filters and ns.Filters._ or {}
local function Info(e)
	local id = ns.Filters and ns.Filters.ItemOf and ns.Filters.ItemOf(e)
	return id and FP.ItemInfo and FP.ItemInfo(id) or nil
end
local function Num(n) return type(n) == "number" and n or nil end
local function Count(e) return FP.Count and FP.Count(e) or Num(e.total) or Num(e.count) end
local function Str(s) return type(s) == "string" and s ~= "" and s or nil end

--- A loot row's boss, place and the place's kind ("dungeon", "raid", "world": AtlasLoot's World Bosses; nil: not
--- known, an index from before 0.51.9)
--- ("Edwin VanCleef  The Deadmines": two spaces between them, Loot.lua's GroupText). Only a dungeon's or a raid's:
--- AtlasLoot's other tables (battlegrounds, professions, factions, PvP...) are no instance and their pages no boss
--- (0.53.1, the player: "count by dungeon" listed Arathi Basin and Leatherworking).
local function LootParts(e)
	if e.kind ~= "loot" then return nil end
	local I = ns.Integrations
	local where = I and I.LootPlace and I.LootPlace(e)
	local kind = where and where.kind
	if where and kind ~= "dungeon" and kind ~= "raid" and kind ~= "world" then return nil end
	local d = Str(e.detail)
	if not d then return nil end
	local boss, place = d:match("^(.-)  (.+)$")
	return Str(boss), Str(place), kind
end

--- A loot row's place when it's of this kind (0.53.3, the player: "by raid" listed dungeons, "by dungeon" raids;
--- "by instance" is either).
local function PlaceOfKind(want)
	return function(e)
		local _, place, kind = LootParts(e)
		if want and kind ~= want then return nil end
		if kind == "world" then return nil end -- (World Bosses: a boss's, out in the world, no instance)
		return place
	end
end

local InstanceOf = PlaceOfKind(nil)
local areaNames = {} -- (an area's name, asked once: it doesn't change)
local function ZoneOf(e)
	local z = Str(e.zone)
	if z then return z end
	if FP.NpcID and FP.NpcID(e) then
		local area = FP.NpcField(e, "zoneID")
		if type(area) ~= "number" or area <= 0 then return nil end
		local got = areaNames[area]
		if got == nil then
			got = C_Map and C_Map.GetAreaInfo and Str(C_Map.GetAreaInfo(area)) or false
			areaNames[area] = got
		end
		return got or nil
	end
	return InstanceOf(e)
end

local function QualityName(q)
	local s = type(q) == "number" and _G["ITEM_QUALITY" .. q .. "_DESC"]
	local name = Str(s) or (type(q) == "number" and ns.Filters and ns.Filters.QUALITIES and ns.Filters.QUALITIES[q + 1])
	if not name then return nil end
	return name, ns.QualityHex and ns.QualityHex(q) -- (the whole code, "|cff0070dd")
end

--- The fields: text (what a row is grouped by) and/or num (what's summed); money: a num that's copper. order: groups by
--- this number, not by size (qualities: the best first). label: how a row says it.
A.FIELDS = {
	kind = { label = L["kind"], text = function(e)
		local p = e.kind and ns.providers[e.kind]
		return p and Str(p.label) or nil
	end },
	zone = { label = L["zone"], text = ZoneOf },
	dungeon = { label = L["dungeon"], text = PlaceOfKind("dungeon") },
	raid = { label = L["raid"], text = PlaceOfKind("raid") },
	instance = { label = L["instance"], text = InstanceOf },
	boss = { label = L["boss"], text = function(e) return (LootParts(e)) end },
	quality = { label = L["quality"], num = function(e)
		local q = Num(e.quality)
		if q then return q end
		local info = Info(e)
		return info and Num(info.quality)
	end, text = function(e, f) return (QualityName(f.num(e))) end, order = true },
	type = { label = L["type"], text = function(e) local i = Info(e); return i and Str(i.type) end },
	subtype = { label = L["subtype"], text = function(e) local i = Info(e); return i and Str(i.subType) end },
	slot = { label = L["slot"], text = function(e)
		local i = Info(e)
		local loc = i and Str(i.equipLoc)
		return loc and Str(_G[loc]) or nil
	end },
	level = { label = L["level"], num = function(e) return FP.Levels and (FP.Levels(e)) or nil end, order = true },
	ilvl = { label = L["item level"], num = function(e) local i = Info(e); return i and Num(i.ilvl) end, order = true },
	count = { label = L["count"], num = function(e) return Count(e) or 1 end },
	-- (how far, where it was worked out: the rows of a search sorted by distance; sort:level,distance. 0.66.16)
	distance = { label = L["distance"], num = function(e) return Num(rawget(e, "_dist")) end },
	-- (an attunement's steps, line by line as Attune's tree reads them: sort:line; 0.55.21)
	line = { label = L["line"], num = function(e) return e.stepRec and e.stepIndex or nil end },
	-- (who has it: a friend's, Terminal: Share's @shared rows; the bar's Group and Sort, sort:owner; 0.58.6)
	owner = { label = L["owner"], text = function(e) return Str(rawget(e, "owner")) end },
	-- (the combat log's hits: sort:damage; 0.55.7)
	damage = { label = L["damage"], num = function(e) return e.kind == "combatlog" and Num(e.amount) or nil end },
	price = { label = L["price"], money = true, num = function(e) local i = Info(e); return i and Num(i.sell) end },
	value = { label = L["value"], money = true, num = function(e)
		local i = Info(e)
		local sell = i and Num(i.sell)
		return sell and sell * (Count(e) or 1) or nil
	end },
}
A.ALIASES = { q = "quality", lvl = "level", itemlevel = "ilvl", ["in"] = "zone", where = "zone", place = "zone",
	area = "zone", dungeons = "dungeon", raids = "raid", instances = "instance", bosses = "boss", from = "boss", qty = "count", amount = "count", number = "count",
	worth = "value", gold = "value", money = "value", vendor = "value", sell = "value", list = "kind", kinds = "kind",
	sub = "subtype", subtypes = "subtype", types = "type", slots = "slot", zones = "zone", qualities = "quality",
	owners = "owner", friend = "owner", friends = "owner" }
A.ORDER = { "value", "price", "count", "kind", "owner", "zone", "instance", "dungeon", "raid", "boss", "quality", "type", "subtype", "slot", "level", "ilvl" }
A.OPS = { count = "count", group = "group", sum = "sum", total = "sum", avg = "avg", average = "avg", mean = "avg" }
A.FIRST_WORDS = { first = true, top = true, head = true }
-- Comparing two searches (0.66.10, the player): "| except @bank" leaves out what the other search finds, "| also
-- @stored" adds it. "Recipes my alts know that I don't", "mats on my alts but not on me".
A.EXCEPT_WORDS = { except = true, minus = true, without = true }
A.ALSO_WORDS = { also = true, plus = true, union = true }
A.FIRST_MAX = 100 -- (a search lists 100 at most)

local function FieldOf(word)
	word = ns.Lower(word or "")
	local name = A.FIELDS[word] and word or A.ALIASES[word]
	return name and A.FIELDS[name] and name or nil
end
A.FieldOf = FieldOf

--- The search and its steps: "in:bags | sum value" -> "in:bags", { "sum value" }. A "|" counts only standing alone,
--- outside quotes ("sword|axe" is either); nil steps when there's none.
--- (Read by the line's pipe recognizer below: the reading's steps, Phrase.lua)
function A.Split(text)
	if type(text) ~= "string" or not text:find("|", 1, true) then return text, nil end
	local steps = ns.Phrase.ReadLine(text, { simple = false, noSend = true }).steps
	if not steps then return text, nil end
	local list = {}
	for k, s in ipairs(steps.list) do list[k] = s end -- (a list of its own: who reads it may change it)
	return steps.query, list
end

-- the steps: a "|" standing alone (not inside a "quoted phrase"), and everything after it up to a send, each "|" the
-- start of the next step. The search is the line before the first one. In either mode.
ns.Phrase.Register({ id = "pipe", stage = "steps", priority = 30, classes = { op = true, syntax = true, word = true, quoted = true },
	modes = { simple = true, advanced = true },
	at = function(r, i)
		local toks, line = r.toks, r.line
		if toks[i].class ~= "op" or toks[i].text ~= "|" then return nil end
		local last = r.sendEnd - 1
		local list, from, bars = {}, toks[i].e + 1, { i }
		for k = i + 1, last do
			if toks[k].class == "op" and toks[k].text == "|" then
				list[#list + 1] = (line:sub(from, toks[k].s - 1):gsub("^%s+", ""):gsub("%s+$", ""))
				from = toks[k].e + 1
				bars[#bars + 1] = k
			end
		end
		list[#list + 1] = (r.base:sub(from):gsub("^%s+", ""):gsub("%s+$", ""))
		-- (bars: each step's "|", its token: the bar takes a typed group out from its "|" to the end, Phrase.Span)
		return { from = i, to = last, kind = "steps", list = list, query = (line:sub(1, toks[i].s - 1):gsub("%s+$", "")),
			spec = "| " .. table.concat(list, " | "), bars = bars }
	end })

--- One step read: { op = "sum", field = "value", by = "zone" }, { where = field, value = "elwynn forest", exact = true },
--- or { bad = what to say } (still being typed, or a word it doesn't know).
local function ParseStep(step)
	local field, value = step:match("^(%a+):(.*)$")
	if field then
		local f = FieldOf(field)
		if not f then return { bad = L["no field called %s"]:format(field) } end
		local exact = value:match('^"(.*)"?$')
		value = (exact or value):gsub('"', ""):gsub("^%s+", ""):gsub("%s+$", "")
		if value == "" then return { bad = L["say what %s to keep: %s:\"...\""]:format(field, field) } end
		-- (a number: kept by its range, as the filters read one; review, 0.53.6: "| lvl:20-30" kept nothing, "| lvl:2"
		-- kept level 25 as "2" is in "25")
		local fd = A.FIELDS[f]
		if fd.num and not fd.text then
			local test = ns.Filters and ns.Filters.Range and ns.Filters.Range(value)
			if not test then return { bad = L["a number or a range: %s:20-30"]:format(field) } end
			return { where = f, value = ns.Lower(value), test = test }
		end
		return { where = f, value = ns.Lower(value), exact = exact ~= nil }
	end
	local ws = {}
	for w in step:gmatch("%S+") do ws[#ws + 1] = ns.Lower(w) end
	-- "| except @bank", "| also @stored": another search, its rows left out or added (0.66.10)
	if A.EXCEPT_WORDS[ws[1] or ""] or A.ALSO_WORDS[ws[1] or ""] then
		local other = step:match("^%S+%s+(.-)%s*$")
		if not other or other == "" then return { bad = L["what to compare with: | except @bank, | also @stored"] } end
		return { other = other, except = A.EXCEPT_WORDS[ws[1]] and true or nil }
	end
	-- "| first 3": the first three, in the search's order (0.66.7, the player: "the 3 nearest mailboxes")
	if A.FIRST_WORDS[ws[1] or ""] then
		local n = tonumber(ws[2] or "")
		if not ws[2] then return { bad = "" } end
		if not n or n < 1 or n ~= math.floor(n) or ws[3] then return { bad = L["how many: | first 3"] } end
		return { first = math.min(n, A.FIRST_MAX) }
	end
	local op = A.OPS[ws[1] or ""]
	if not op then
		-- (a step's start, "| co": still being typed, the line on top says what goes there)
		for name in pairs(A.OPS) do if ws[1] and #ws == 1 and name:sub(1, #ws[1]) == ws[1] then return { bad = "" } end end
		return { bad = ws[1] and L["no step called %s"]:format(ws[1]) or "" }
	end
	-- the words after it: "[by] field [by field]" ("sum value", "sum by value", "sum value by zone", "group by zone")
	local k = 2
	local function Next()
		if ws[k] == "by" or ws[k] == "of" then k = k + 1 end
		local w = ws[k]
		k = k + 1
		return w
	end
	local first, second = Next(), Next()
	if ws[k] then return { bad = L["one field to sum, one to group by: sum value by zone"] } end
	if op == "count" or op == "group" then
		if second then return { bad = L["group by one field: group by zone"] } end
		if not first then
			if op == "group" then return { bad = L["group by what: zone, kind, quality..."] } end
			return { op = "count" }
		end
		local by = FieldOf(first)
		if not by then return { bad = L["no field called %s"]:format(first) } end
		if A.FIELDS[by].money then return { bad = L["group by what: zone, kind, quality..."] } end -- (copper amounts)
		return { op = "group", by = by }
	end
	if not first then return { bad = L["%s of what: value, count, level..."]:format(ws[1]) } end
	local field = FieldOf(first)
	if not field or not A.FIELDS[field].num then return { bad = L["no number called %s"]:format(first) } end
	local by
	if second then
		by = FieldOf(second)
		if not by then return { bad = L["no field called %s"]:format(second) } end
		if A.FIELDS[by].money then return { bad = L["group by what: zone, kind, quality..."] } end
	end
	return { op = op, field = field, by = by }
end
A.ParseStep = ParseStep

--- The steps typed after the search, read: { wheres = { ... }, last = the summing step or nil, bad = what to say, base =
--- the search with its keeping steps }.
function A.Parse(steps, query)
	local spec = { wheres = {} }
	local base = { query or "" }
	for k, step in ipairs(steps) do
		local s = ParseStep(step)
		if s.bad then spec.bad = s.bad; spec.badStep = step; return spec end
		if s.other then
			-- (another search compared: a keeping step, as a where is)
			if spec.last then spec.bad = L["a sum, count or group is the last step"] return spec end
			spec.wheres[#spec.wheres + 1] = s
			base[#base + 1] = step
		elseif s.first then
			-- (a keeping step: the first N, before a sum or count; the last one typed counts)
			if spec.last then spec.bad = L["a sum, count or group is the last step"] return spec end
			spec.first = s.first
			base[#base + 1] = step
		elseif s.where then
			spec.wheres[#spec.wheres + 1] = s
			base[#base + 1] = step
		elseif k < #steps then
			spec.bad = L["a sum, count or group is the last step"]
			return spec
		else
			spec.last = s
		end
	end
	spec.text = table.concat(steps, " | ")
	spec.base = table.concat(base, " | ") -- (a group's Enter: this, then its own "| zone:...")
	spec.query = query or ""
	table.remove(base, 1)
	spec.keepSteps = base -- (the keeping steps typed, each as typed: a group's Enter puts its filter before them)
	return spec
end

local function Real(e) return not (e.raw or e.noActivate or e.completion or e.lead or e.kind == "calc") end
-- "1 result", "3 results" (the footer's words: 0.55.10, the player's screenshot said "1 results")
local function ResultsN(n) return (n == 1 and L["%s result"] or L["%s results"]):format(n) end

local function TextOf(name, e)
	local f = A.FIELDS[name]
	if f.text then return f.text(e, f) end
	local n = f.num(e)
	return n and tostring(n) or nil
end

local function KeepsRow(w, e)
	if w.test then return w.test(A.FIELDS[w.where].num(e)) end -- (a number's step: by its range, "lvl:20-30")
	local t = TextOf(w.where, e)
	if not t then return false end
	-- (quote marks aren't compared: a step's value has none, "Captain" Cookie's group neither; release review)
	local lt = ns.Lower(ns.Plain(t)):gsub('"', "")
	if lt == w.value then return true end
	return not w.exact and lt:find(w.value, 1, true) ~= nil
end

--- What a row is, to compare across lists: the same item (whoever holds it), quest, spell or NPC; else its name.
function A.Identity(e)
	if type(e) ~= "table" then return nil end
	local F = ns.Filters
	local item = F and F.ItemOf and F.ItemOf(e)
	if item then return "i:" .. tostring(item) end
	local QR = ns.QuestRewards
	local q = QR and QR.QuestIdOf and QR.QuestIdOf(e)
	if q then return "q:" .. tostring(q) end
	local spell = rawget(e, "spellID")
	if type(spell) == "number" then return "s:" .. spell end
	local npc = FP.NpcID and FP.NpcID(e)
	if npc then return "n:" .. tostring(npc) end
	local name = e.name
	return type(name) == "string" and ("t:" .. ns.Lower(ns.Plain(name))) or nil
end

--- The other search's rows (| except, | also): its @kinds (none: the lists the rows come from), filters and words
--- (each in a row's name or words), every row of them, not the best few. Kept for the search's length: a key per text.
local otherKept = { gen = nil, rows = {} }
A.OTHER_KEEP = 5 -- (seconds: "| except @loot since:30m" moves with the clock; review)
function A.OtherRows(text, fromKinds)
	local kinds, filters, words = {}, {}, {}
	local all = ns.Words(text)
	for _, w in ipairs(all) do
		if w:sub(1, 1) == "@" and #w > 1 then
			local p = ns:ResolveProvider(w:sub(2))
			if p then kinds[#kinds + 1] = p.id end
		end
	end
	if #kinds == 0 then kinds = fromKinds or {} end
	-- (a list changed since, the bank's or mail's: made again first, so what's kept of it goes; review: a sword put in
	-- the bank was still listed by "| except @bank" until another list changed)
	for _, id in ipairs(kinds) do
		local p = ns.providers[id]
		if p and p._dirty then ns:GetEntries(p) end
	end
	local gen, now = ns.entriesGen, GetTime and GetTime() or 0
	-- (a few texts kept: every keystroke of "| except @stored lin..." is another; review)
	if otherKept.gen ~= gen or (otherKept.n or 0) >= 8 or now - (otherKept.at or now) > A.OTHER_KEEP then
		otherKept = { gen = gen, rows = {}, n = 0, at = now }
	end
	local key = text .. "\001" .. table.concat(fromKinds or {}, ",")
	if otherKept.rows[key] then return otherKept.rows[key] end
	local F = ns.Filters
	for _, w in ipairs(all) do
		if not (w:sub(1, 1) == "@" and #w > 1) then
			local f = (w:find("[:|]") or w:find("^[-!][%a\128-\255]")) and F and F.Parse(w)
			if f then filters[#filters + 1] = f else words[#words + 1] = ns.Lower(w) end
		end
	end
	local out = {}
	for _, id in ipairs(kinds) do
		local p = ns.providers[id]
		for _, e in ipairs(p and ns:GetEntries(p) or {}) do
			if Real(e) then
				local ok = true
				for _, f in ipairs(filters) do
					local okF, yes = pcall(f, e)
					if not (okF and yes) then ok = false break end
				end
				if ok and #words > 0 then
					local hay = ns.Lower(ns.Plain(tostring(e.name or ""))) .. " " .. (rawget(e, "_ltext") or ns.Lower(tostring(e.text or "")))
					for _, w in ipairs(words) do if not hay:find(w, 1, true) then ok = false break end end
				end
				if ok then out[#out + 1] = e end
			end
		end
	end
	otherKept.rows[key] = out
	otherKept.n = (otherKept.n or 0) + 1
	return out
end

--- The rows with the other search's left out (| except), or added (| also: each once).
function A.Compare(rows, w)
	local kinds, seenKind = {}, {}
	for _, e in ipairs(rows) do
		local k = e.kind
		if type(k) == "string" and not seenKind[k] then seenKind[k] = true; kinds[#kinds + 1] = k end
	end
	local other = A.OtherRows(w.other, kinds)
	local ids = {}
	if w.except then
		-- (what the other search holds, worked out once for its rows)
		local held = rawget(other, "_ids")
		if not held then
			held = {}
			for _, e in ipairs(other) do local id = A.Identity(e) if id then held[id] = true end end
			other._ids = held
		end
		local kept = {}
		for _, e in ipairs(rows) do
			local id = A.Identity(e)
			if not (id and held[id]) then kept[#kept + 1] = e end
		end
		return kept
	end
	local out, low = {}, math.huge
	for _, e in ipairs(rows) do
		out[#out + 1] = e
		local s = tonumber(rawget(e, "_score"))
		if s and s < low then low = s end
		local id = A.Identity(e)
		if id then ids[id] = true end
	end
	if low == math.huge then low = 0 end
	-- (added: after what the search found itself, in their list's order; as views, the shared rows' own scores (an
	-- earlier search's) left alone; review)
	local k = 0
	for _, e in ipairs(other) do
		local id = A.Identity(e)
		if not (id and ids[id]) then
			if id then ids[id] = true end
			k = k + 1
			-- (_also: added by this step, for "Why is this here?"; review)
			out[#out + 1] = setmetatable({ _score = low - k, _also = w.other }, { __index = e })
		end
	end
	return out
end

--- A number as a row says it (copper as gold, silver and copper), and as plain text (copied: no coin icons).
local function Shown(field, n)
	local f = A.FIELDS[field]
	if f.money then
		if not ns.Gold then return tostring(n) .. "c", tostring(n) .. "c" end
		return ns.Money(n), ns.Money(n, true)
	end
	local t = math.floor(n) == n and tostring(n) or ("%.1f"):format(n)
	return t, t
end

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local function Row(name, detail, key, label)
	return { kind = "aggregate", kindLabel = "|cff33ff99" .. label .. "|r", icon = ICON, raw = true, _score = 0,
		_pos = ns.UI and ns.UI.NO_POS, name = name, detail = detail, key = key, noActivate = true }
end

--- A total's Enter: it's said in the chat window (only to you), the search kept in the history (release review: Enter
--- did nothing, and Up never brought a summed-up search back).
local function SayTotal(e)
	ns:Print(ns.Share and ns.Share.Clean(e.copyName or e.name) .. (e.detail ~= "" and ("  (" .. ns.Share.Clean(e.copyDetail or e.detail) .. ")") or "")
		or tostring(e.name))
end
local function Said(r)
	r.noActivate, r.activate, r.actionVerb = nil, SayTotal, L["show in chat"]
	return r
end

--- What a group's Enter writes: the search with the group's own filter added, as you'd type it (0.53.1, the player: the
--- filters work without a "|", so "@loot q:rare", not "@loot | quality:\"Rare\""); a field no filter says the same of
--- (kind, slot, a name with quote marks in it) keeps its rows by a step, "| slot:\"Finger\"".
local DrillTo
local FILTER_OF = {
	quality = function(g, f) local q = f.num(g.sample) return q and ns.Filters.QUALITIES and ns.Filters.QUALITIES[q + 1] and ("q:" .. ns.Filters.QUALITIES[q + 1]) end,
	level = function(g) return "lvl:" .. g.text end,
	ilvl = function(g) return "ilvl:" .. g.text end,
	count = function(g) return "count:" .. g.text end,
	zone = function(g) return 'in:"' .. g.text .. '"' end,
	dungeon = function(g) return 'in:"' .. g.text .. '"' end,
	raid = function(g) return 'in:"' .. g.text .. '"' end,
	instance = function(g) return 'in:"' .. g.text .. '"' end,
	boss = function(g) return 'in:"' .. g.text .. '"' end,
	type = function(g) return 'type:"' .. g.text .. '"' end,
	subtype = function(g) return 'type:"' .. g.text .. '"' end,
}
DrillTo = function(spec, by, g)
	local text = ns.Plain(g.text)
	local make = not text:find('"', 1, true) and FILTER_OF[by]
	local word = make and make({ text = text, sample = g.sample }, A.FIELDS[by])
	local steps = {}
	for _, st in ipairs(spec.keepSteps or {}) do steps[#steps + 1] = " | " .. st end
	-- (a space after the filter: the caret right after a key:value would list its values to pick, not the rows)
	-- (after the steps too: the caret after "| q:rare" listed q:'s values; review, 0.53.6)
	-- (the line has it already: not written twice; 0.55.10, the player's screenshot had in:"Winterspring" seven times)
	local q = spec.query:gsub("%s+$", "")
	-- (0.61.5, the player: "@questie Death", grouped by zone, Enter on Deathknell left "Death" in the line beside
	-- in:"Deathknell": typed to find the group, not to narrow its rows) the plain words the group's name has go
	if word then q = A.DropNamed(q, text) end
	if word and (" " .. q .. " "):find(" " .. word .. " ", 1, true) then return q .. table.concat(steps) .. " " end
	if word then return q .. " " .. word .. table.concat(steps) .. " " end
	return spec.base .. " | " .. by .. ':"' .. (text:gsub('"', "")) .. '" '
end

--- The line without its plain words that are part of `name` ("@questie death" for the group Deathknell: "@questie"):
--- not @kinds, key:value filters, quoted phrases, -words or a word after "not"; an "or" before a word taken goes too.
function A.DropNamed(line, name)
	-- (a word starts the group's name, or one of its words: "death" Deathknell, "glades" Tirisfal Glades; not "ring" in
	-- Winterspring: the search matches at word starts too; release review, 0.63.0)
	local lname = " " .. ns.Lower(ns.Plain(tostring(name or ""))):gsub("[%s%p]+", " ")
	local E = ns.Easy
	local OR = (E and E.OR_WORDS) or { ["or"] = true }
	local NOT = (E and E.NOT_WORDS) or { ["not"] = true }
	local toks = {}
	-- (quoted phrases kept whole)
	local rest = line
	while rest ~= "" do
		local sp, tok = rest:match("^(%s*)(%b\"\")")
		if not tok then sp, tok = rest:match("^(%s*)(%S+)") end
		if not tok then break end
		toks[#toks + 1] = tok
		rest = rest:sub(#sp + #tok + 1)
	end
	-- words joined by "or" go together ("sword or axe": every row of an Axes group passes it; one side alone would
	-- keep none of them); a word after a "not" word ("not", "no", "without", "except") is the search's own
	local function Named(tok, prev)
		local lw = ns.Lower(tok)
		if #lw < 2 or OR[lw] or NOT[lw] or lw == "and" or (prev and NOT[prev]) then return false end
		if tok:find("^[@%-!\"]") or tok:find("[:|>]") then return false end
		-- (its punctuation as the name's: "zul'gurub" is Zul'Gurub)
		lw = lw:gsub("[%s%p]+", " "):gsub("^ ", ""):gsub(" $", "")
		return lw ~= "" and lname:find(" " .. lw, 1, true) ~= nil
	end
	local out, dropped, k = {}, false, 1
	while k <= #toks do
		-- a run: a word, then ("or" word)*
		local run, drop = { k }, false
		local prev = toks[k - 1] and ns.Lower(toks[k - 1])
		if Named(toks[k], prev) then drop = true end
		local m = k
		while toks[m + 2] and OR[ns.Lower(toks[m + 1])] do
			run[#run + 1] = m + 1
			run[#run + 1] = m + 2
			-- ("death or not kobold": the not-word and its word are one side, never left alone)
			if NOT[ns.Lower(toks[m + 2])] and toks[m + 3] then
				run[#run + 1] = m + 3
				m = m + 3
			else
				if Named(toks[m + 2], ns.Lower(toks[m + 1])) then drop = true end
				m = m + 2
			end
		end
		if drop and not (prev and NOT[prev]) then
			dropped = true
		else
			for _, idx in ipairs(run) do out[#out + 1] = toks[idx] end
		end
		k = m + 1
	end
	if not dropped then return line end
	-- (a "not" word or "or" left at the end with nothing after it)
	while #out > 0 and (OR[ns.Lower(out[#out])] or NOT[ns.Lower(out[#out])] or ns.Lower(out[#out]) == "and") do table.remove(out) end
	return table.concat(out, " ")
end

--- A group's Enter: the same search, keeping that group's rows (Shift+Left goes back).
local function Drill(e)
	local UI = ns.UI
	if not (UI and e.drillTo) then return end
	-- (the bar's Group made these groups: its rows aren't grouped again; Shift+Left brings the Group back with the step)
	local B = ns.Bar
	local saved = B and B.Save()
	if e.drillFromBar and B then B.state.group = nil end
	UI:WalkTo(e.drillTo, e, saved)
end

--- The rows the search found, put through the steps: the kept rows (only "where" steps), or the summed-up rows. Rows
--- whose item data isn't in yet ask for it and the search runs again (Filters.loading: UI:RetryWhenLoaded).
--- `base`: the text before the summing step (a group's Enter keeps its rows: base | field:"value").
--- Do the steps change what the search gives (sum it up, or keep some of its rows)? Then the search hands over every
--- match, untrimmed and with no close spellings, and A.Apply sorts and trims what's kept (review, 0.53.6: a keeping
--- step alone ran over the best 100: "| zone:\"Cap Cove\"" listed 9 of a group's 30).
function A.Summing(spec)
	return spec ~= nil and not spec.bad and (spec.last ~= nil or #(spec.wheres or {}) > 0)
end

function A.Apply(spec, res, base)
	local rows = {}
	for _, e in ipairs(res or {}) do if Real(e) then rows[#rows + 1] = e end end
	if spec.bad then
		-- (still being typed, or a word it doesn't know: the rows as they are, with a line saying what goes there)
		local fields = {}
		for _, name in ipairs(A.ORDER) do fields[#fields + 1] = name end
		local hint = Row(spec.bad ~= "" and spec.bad or L["| count, | sum value, | group by zone, | avg level, | first 3, | except @bank, | also @stored"],
			L["fields: %s"]:format(table.concat(fields, ", ")), "aggregate:hint", L["sum up"])
		local out = { hint }
		for _, e in ipairs(res or {}) do out[#out + 1] = e end
		return out
	end
	for _, w in ipairs(spec.wheres) do
		if w.other then
			rows = A.Compare(rows, w)
		else
			local kept = {}
			for _, e in ipairs(rows) do if KeepsRow(w, e) then kept[#kept + 1] = e end end
			rows = kept
		end
	end
	local s = spec.last
	-- "| first 3": the first three in the search's order (summed up after: the search's rows came unsorted, sorted
	-- here); how many there were, for the footer ("3 of 41")
	if spec.first then
		-- (how many there were: the search's own count, from before it kept the best 100, when nothing was taken out
		-- since; review: "3 of 100" for 250)
		spec.firstOf = (#spec.wheres == 0 and spec.matched) or #rows
		if A.Summing(spec) then rows = ns.UI.SortAndTrim(rows, spec.first) end
		if #rows > spec.first then
			local kept = {}
			for i = 1, spec.first do kept[i] = rows[i] end
			rows = kept
		end
		if not s then
			-- (the search's own order kept, its lines (a heading, a note) dropped; none kept: its note saying why stays,
			-- "3 nearest mailboxes in moonglade" listed nothing at all; 0.68.16)
			if #rows == 0 then
				local notes = {}
				for _, e in ipairs(res or {}) do if e.noActivate and not e.lead then notes[#notes + 1] = e end end
				return notes
			end
			return #spec.wheres > 0 and ns.UI.SortAndTrim(rows) or rows
		end
	end
	if not s then return ns.UI.SortAndTrim(rows) end
	local n = #rows
	if s.op == "count" then
		local r = Row(ResultsN(n), base or "", "aggregate:count:" .. n, L["count"])
		Said(r)
		return { r }
	end
	local f = s.field and A.FIELDS[s.field]
	-- one total ("sum value") or one per group ("group zone", "sum value by zone")
	local groups, order = {}, {}
	local total, have = 0, 0
	local texts -- (each row's group, read once: a zone is a Questie lookup per NPC row; review, 0.53.6)
	if s.by then -- (by raid: the raids' rows alone, no "no raid" group; by slot: what has one; 0.53.4, the player)
		local kept = {}
		texts = {}
		for _, e in ipairs(rows) do
			local t = TextOf(s.by, e)
			if t then kept[#kept + 1] = e; texts[#kept] = t end
		end
		rows, n = kept, #kept
	end
	for i, e in ipairs(rows) do
		local v = f and f.num(e)
		if v then total, have = total + v, have + 1 end
		if s.by then
			local t = texts[i]
			local g = groups[t]
			if not g then
				g = { text = t, n = 0, sum = 0, have = 0, sample = e }
				groups[t] = g
				order[#order + 1] = g
			end
			g.n = g.n + 1
			if v then g.sum, g.have = g.sum + v, g.have + 1 end
		end
	end
	local function Value(sum, got)
		if s.op == "avg" then return got > 0 and sum / got or nil end
		return sum
	end
	local function Detail(cnt, got)
		local parts = { ResultsN(cnt) }
		if f and got < cnt then parts[#parts + 1] = L["%d with no %s"]:format(cnt - got, f.label) end
		return table.concat(parts, ns.DETAIL_SEP)
	end
	local loading = ns.Filters and ns.Filters.loading
	local opLabel = s.op == "avg" and L["average"] or s.op == "sum" and L["sum"] or L["group"]
	if not s.by then
		local v = Value(total, have)
		local name, plain = L["nothing to %s"]:format(opLabel), nil
		if v then name, plain = Shown(s.field, v) end
		local detail = (s.op == "avg" and L["average %s of %s"] or L["%s of %s"]):format(f.label, Detail(n, have))
		if loading then detail = detail .. ns.DETAIL_SEP .. L["item data still coming in"] end
		local r = Row(name, detail, "aggregate:" .. s.op .. ":" .. tostring(v) .. ":" .. n, opLabel)
		r.copyName = plain
		Said(r)
		return { r }
	end
	local byField = A.FIELDS[s.by]
	for _, g in ipairs(order) do
		if f then g.value = Value(g.sum, g.have) else g.value = g.n end -- (an average of none: none, not the count)
		if byField.order and byField.num then g.rank = byField.num(g.sample) end
	end
	table.sort(order, function(a, b)
		if byField.order and a.rank and b.rank and a.rank ~= b.rank then return a.rank > b.rank end
		local va, vb = a.value or -math.huge, b.value or -math.huge
		if va ~= vb then return va > vb end
		return tostring(a.text) < tostring(b.text)
	end)
	local out = {}
	if f and s.op == "sum" then -- (all of them on top)
		local shown, plain = Shown(s.field, total)
		out[1] = Row(L["All: %s"]:format(shown), L["%s of %s"]:format(f.label, Detail(n, have)),
			"aggregate:all:" .. total .. ":" .. n, opLabel)
		out[1].copyName = L["All: %s"]:format(plain)
		Said(out[1])
	end
	for _, g in ipairs(order) do
		local name = g.text
		if s.by == "quality" and g.text then
			local _, hex = QualityName(byField.num(g.sample))
			if hex then name = hex .. g.text .. "|r" end -- (0.52.14, the player's screenshot: "|c" put before it showed)
		end
		local detail, copyDetail = ResultsN(g.n), nil
		if f then
			local shown, plain = "-", "-"
			if g.value then shown, plain = Shown(s.field, g.value) end
			detail, copyDetail = shown .. ns.DETAIL_SEP .. Detail(g.n, g.have), plain .. ns.DETAIL_SEP .. Detail(g.n, g.have)
		end
		local r = Row(name, detail, "aggregate:" .. s.by .. ":" .. tostring(g.text) .. ":" .. g.n .. ":" .. tostring(g.value), opLabel)
		r.copyDetail = copyDetail
		r.groupN = g.n -- (how many rows it holds: the footer counts them, "14 groups · 34 results"; List.lua)
		if g.text and base then
			r.noActivate, r.activate, r.staysOpen = nil, Drill, true
			r.drillTo = DrillTo(spec, s.by, g)
			r.drillFromBar = spec.fromBar -- (Simple mode's bar's Group: let go on the way in, Drill)
			r.actionVerb = L["list them"]
		end
		out[#out + 1] = r
	end
	if loading and out[1] then out[1].detail = out[1].detail .. ns.DETAIL_SEP .. L["item data still coming in"] end
	return out
end

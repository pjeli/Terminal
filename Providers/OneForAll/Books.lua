local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- @book: WoW Forever's Library Books (1.0.1, the player's ask), OneForAll's list of them: the tomes found in the world
-- and turned in to the library for its rewards (not the lore books on the shelves). Each book is a quest (turning it
-- in) and an item (the book you carry), in a zone at a spot: a row each, with where it is and how far along you are
-- ("in your bags", "turned in"), on the map with Enter as a mailbox is. "library books", "books i still need",
-- "nearest library book", "library book rewards" ask for them (Simple mode; Search/Questions/Questions.lua).
--
-- How far along: OneForAll's own judgement when it gives one (FLT:GetBookState: a turn-in it saw, a book you marked,
-- one in your bags or bank, the quest flag), else the game's (the quest done, the book in your bags or bank).

local B = {}
OA.Books = B
ns.LibraryBooks = B
local Safe, Lower, Num = ns.Safe, ns.Lower, ns.Num
local SEP = ns.DETAIL_SEP
B.ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- OneForAll's states -> what a row says, and whether the book is done with
B.STATES = {
	done = { L["turned in"], true }, questflag = { L["turned in"], true }, manual = { L["marked done"], true },
	bag = { L["in your bags"], false }, bank = { L["in your bank"], false }, missing = { L["still to find"], false },
}
-- its notes on where a book is: what a row says of a spot not sure yet
B.UNSURE = { unknown = L["spot not confirmed"], reported = L["spot reported by players"],
	["not-in-forever"] = L["not in WoW Forever yet"] }

--- Its books, checked: { { name, quest, item, zone, subzone, x, y, set, container, note, status, raw }, ... }, or nil.
function B.Data()
	return OA.Part("books", "BOOKS", L["@book (its Library Books) is unavailable."], function(raw, lib)
		local maps = type(lib.MAP_IDS) == "table" and lib.MAP_IDS or {}
		local sets = type(lib.SETS) == "table" and lib.SETS or {}
		local out, bad = {}, 0
		for i, b in ipairs(raw) do
			local name, quest, item = type(b) == "table" and OA.Text(b.name), type(b) == "table" and Num(b.questId),
				type(b) == "table" and Num(b.itemId)
			if name and quest and item then
				local zone = OA.Text(b.zone)
				local x, y = Num(b.x), Num(b.y)
				local ui = zone and x and y and Num(maps[zone]) or nil -- (a spot only with its map known)
				out[#out + 1] = { name = name, quest = quest, item = item, zone = zone, subzone = OA.Text(b.subzone),
					x = ui and x or nil, y = ui and y or nil, ui = ui, order = i,
					set = OA.Text(sets[b.set]) or OA.Text(b.set), container = OA.Text(b.container), note = OA.Text(b.note),
					status = OA.Text(b.status), raw = b }
			else
				bad = bad + 1
			end
		end
		if #out == 0 then return nil, "OneForAll.BOOKS: no book in the shape expected (" .. bad .. " entries not)" end
		if bad > 0 then ns:Trace(("oneforall: %d Library Books not in the shape expected, left out"):format(bad)) end
		return out
	end)
end

--- Its reward tiers: { { label ("10 books"), need (a number of books), quest, items = { { id, name, desc } } } }, or nil.
function B.Rewards()
	return OA.Part("bookrewards", "BOOK_REWARD_TIERS", L["The Library Books' rewards are unavailable."], function(raw)
		local out = {}
		for _, t in ipairs(raw) do
			local need = type(t) == "table" and Num(t.req)
			if need then
				local items = {}
				for _, it in ipairs(type(t.items) == "table" and t.items or {}) do
					if type(it) == "table" and Num(it[1]) then items[#items + 1] = { id = it[1], name = OA.Text(it[2]), desc = OA.Text(it[4]) } end
				end
				out[#out + 1] = { label = OA.Text(t.books), need = need, quest = OA.Text(t.quest), questID = Num(t.questID), items = items }
			end
		end
		if #out == 0 then return nil, "OneForAll.BOOK_REWARD_TIERS: no tier in the shape expected" end
		table.sort(out, function(a, b) return a.need < b.need end)
		return out
	end, true)
end

local function QuestDone(id)
	local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or _G.IsQuestFlaggedCompleted
	return f and Safe(f, id) == true or false
end
local function Count(id, bank)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	return f and Num(Safe(f, id, bank)) or 0
end

--- Where you are with a book: OneForAll's state ("done", "bag", ...), else the game's.
function B.State(b)
	local lib = OA.Lib()
	local s = lib and OA.Call(lib.GetBookState, lib, b.raw)
	if type(s) == "string" and B.STATES[s] then return s end
	if QuestDone(b.quest) then return "done" end
	local bags = Count(b.item)
	if bags > 0 then return "bag" end
	if Count(b.item, true) > bags then return "bank" end
	return "missing"
end

--- How many books are turned in (or marked done), of how many.
function B.Progress(rows)
	local done = 0
	for _, e in ipairs(rows) do if e.isDone then done = done + 1 end end
	return done, #rows
end

--- The next reward tier and how many books it takes; nil when every tier is reached (or none known).
function B.NextReward(done)
	for _, t in ipairs(B.Rewards() or {}) do if done < t.need then return t end end
	return nil
end

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	local st = B.STATES[e.state]
	t:AddLine(st and st[1] or "", st and st[2] and 0.4 or 1, 1, st and st[2] and 0.4 or 1)
	local where = e.zone and (e.subzone and (e.subzone .. ", " .. e.zone) or e.zone)
	if where then t:AddLine(where .. (e.px and ("  " .. ("%.1f, %.1f"):format(e.px, e.py)) or ""), 1, 1, 1, true) end
	if e.note then t:AddLine(e.note, 0.8, 0.8, 0.8, true) end
	if e.unsure then t:AddLine(e.unsure, 1, 0.5, 0.3, true) end
	if e.set then t:AddLine(e.set .. (e.container and (SEP .. e.container) or ""), 0.62, 0.62, 0.62) end
	local p = ns.providers.book
	local done, all = B.Progress(p and ns:GetEntries(p) or {})
	t:AddLine(" ")
	t:AddLine(L["%d of %d Library Books turned in"]:format(done, all), 1, 0.82, 0)
	local nxt = B.NextReward(done)
	if nxt then
		local names = {}
		for _, it in ipairs(nxt.items) do names[#names + 1] = it.name or L["item %s"]:format(it.id) end
		t:AddLine(L["Next reward at %d books: %s"]:format(nxt.need, nxt.quest or "") .. (#names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""),
			0.8, 0.8, 0.8, true)
	end
	t:AddLine(L["Library Books from OneForAll"], 0.5, 0.5, 0.5)
end

-- a book with no spot known: Enter says so, nothing pressed
local function NoSpot(e) ns:Print(L["OneForAll has no spot for %s yet."]:format(e.name)) end

--- The rows: one a book, in OneForAll's order (its sets, levels 20 to 60).
function B.Rows()
	local out = {}
	for _, b in ipairs(B.Data() or {}) do
		local state = B.State(b)
		local st = B.STATES[state]
		local zone = b.zone and (b.subzone and (b.zone .. ", " .. b.subzone) or b.zone) or nil
		local unsure = b.status and B.UNSURE[b.status] or nil
		local row = {
			key = b.quest, kind = "book", name = b.name, _lname = Lower(b.name), itemID = b.item, icon = B.ICON,
			state = state, isDone = st[2], zone = b.zone, subzone = b.subzone, note = b.note, set = b.set, container = b.container,
			unsure = unsure, order = b.order, tooltip = Tooltip, generic = false, pinName = b.name,
			detail = st[1] .. (zone and (SEP .. zone) or "") .. (unsure and (SEP .. unsure) or ""),
			text = Lower(table.concat({ L["library book"], "library book", st[1], b.zone or "", b.subzone or "", b.set or "",
				b.container or "", st[2] and "done" or "todo" }, " ")),
		}
		if b.ui then
			row.ui, row.px, row.py = b.ui, b.x, b.y
			if I.SpotXY then row.wcont, row.wx, row.wy = I.SpotXY(b.ui, { b.x, b.y }) end
			out[#out + 1] = I.SpotRow(row)
		else
			row.activate, row.secondary = NoSpot, NoSpot
			out[#out + 1] = row
		end
	end
	return out
end

OA.AddSetup(function()
	if not B.Data() then return end
	B.Rewards()
	ns:RegisterProvider("book", {
		label = L["Library Book"], color = "ffd8b070", aliases = { "book", "books", "librarybook", "librarybooks", "library" },
		lazy = true,
		-- (a book picked up, put in the bank, turned in)
		events = { "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "BANKFRAME_CLOSED" }, guard = 1,
		collect = B.Rows,
	})
end)
OA.AddStatus(function()
	local d = B.Data()
	return d and L["%d Library Books (@book)"]:format(#d) or nil
end)

----------------------------------------------------------------------
-- "library books", "books i still need", "nearest library book", "library book rewards"
----------------------------------------------------------------------

-- the words: what it's about (a book word: "library", or "book(s)"/"tome(s)" with one of the cues), what it asks
local BOOK = { book = true, books = true, tome = true, tomes = true }
local CUE = { need = "todo", needed = "todo", missing = "todo", left = "todo", still = "todo", find = "todo", todo = "todo",
	remaining = "todo", unfound = "todo", done = "done", turned = "done", collected = "done", found = "done", have = "have",
	got = "have", rewards = "rewards", reward = "rewards", nearest = "near", closest = "near", nearby = "near", near = "near",
	my = "mine", all = "all", every = "all" }
local ASK = { i = true, im = true, ["do"] = true, dont = true, the = true, a = true, to = true, where = true, are = true,
	is = true, what = true, which = true, show = true, list = true, me = true, of = true, ["for"] = true, ["in"] = true,
	at = true, yet = true, ["not"] = true, havent = true, ive = true, already = true, many = true, how = true, can = true }

--- The question: { todo, done, near, rewards, words (narrowing: a zone, a name) }, or nil when the line isn't about them.
function B.Question(text)
	if not ns.providers.book then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local library, book, cues, rest = false, false, {}, {}
	for w in t:gmatch("%S+") do
		if w == "library" then library = true
		elseif BOOK[w] then book = true
		elseif CUE[w] then cues[CUE[w]] = true
		elseif not ASK[w] then rest[#rest + 1] = w end
	end
	if not book then return nil end
	if not library and not next(cues) then return nil end -- ("book", "spell book": not these)
	-- other words: only those naming a book or its place ("library books in the barrens"), else not this question
	if #rest > 0 and not B.AnyFor(rest) then return nil end
	return { todo = cues.todo or cues.near or nil, done = (cues.done or cues.have) and not cues.todo or nil, near = cues.near,
		rewards = cues.rewards and not cues.near or nil, words = rest }
end

local function Has(e, words)
	local hay = (rawget(e, "_lname") or "") .. " " .. (rawget(e, "_ltext") or rawget(e, "text") or "") -- (Core.lua keeps text as _ltext)
	for _, w in ipairs(words or {}) do if not hay:find(w, 1, true) then return false end end
	return true
end
function B.AnyFor(words)
	local p = ns.providers.book
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if Has(e, words) then return true end end
	return false
end

--- The reward tiers as rows: "Friend of the Library: 10 books (turned in 4)", reached or not.
local function RewardRows(done)
	local out = {}
	for _, t in ipairs(B.Rewards() or {}) do
		local names = {}
		for _, it in ipairs(t.items) do names[#names + 1] = it.name or L["item %s"]:format(it.id) end
		local reached = done >= t.need
		out[#out + 1] = ns.NoteRow((t.quest or t.label or "") .. ": " .. L["%d books"]:format(t.need) .. (reached and ("  " .. L["(reached)"]) or ""),
			table.concat(names, ", "))
		out[#out].icon = B.ICON
	end
	return out
end

function B.Answer(q)
	q = q or {}
	local p = ns.providers.book
	local all = p and ns:GetEntries(p) or {}
	local done = B.Progress(all)
	local progress = L["%d of %d turned in"]:format(done, #all)
	if q.rewards then
		local rows = RewardRows(done)
		if #rows == 0 then return { ns.NoteRow(L["OneForAll lists no rewards for the Library Books"]) }, L["Library Book rewards"] end
		return rows, L["Library Book rewards"] .. SEP .. progress
	end
	local rows = {}
	for _, e in ipairs(all) do
		local ok = Has(e, q.words) and not (q.todo and e.isDone) and not (q.done and not e.isDone)
		if ok then rows[#rows + 1] = e end
	end
	local note = (q.todo and L["Library Books still to turn in"]) or (q.done and L["Library Books turned in"]) or L["Library Books"]
	if q.near then
		local here = I.Here and I.Here()
		if not here then
			ns.ScoreInOrder(rows)
			return rows, note .. SEP .. L["where you are isn't known here"]
		end
		local near, far = {}, {}
		for _, e in ipairs(rows) do
			local d = I.RowYards(e, here)
			if d then near[#near + 1] = { e = e, d = d } else far[#far + 1] = e end
		end
		table.sort(near, function(a, b) return a.d < b.d end)
		rows = {}
		for i, n in ipairs(near) do
			rows[i] = setmetatable({ _score = 1e6 - n.d, _dist = n.d, detail = L["%.0f yd"]:format(n.d) .. SEP .. (rawget(n.e, "detail") or "") },
				{ __index = n.e })
		end
		for _, e in ipairs(far) do rows[#rows + 1] = e end
		if #rows == 0 then return { ns.NoteRow(L["Every Library Book is turned in"]) }, note end
		return rows, L["Nearest Library Books still to turn in"] .. SEP .. progress
	end
	ns.ScoreInOrder(rows)
	if #rows == 0 then
		return { ns.NoteRow(q.todo and L["Every Library Book is turned in"] or L["No Library Book has that"]) }, note
	end
	local nxt = B.NextReward(done)
	return rows, note .. SEP .. progress .. (nxt and (SEP .. L["next reward at %d"]:format(nxt.need)) or "")
end

function B.ToAdvanced(q)
	q = q or {}
	local w = q.words and #q.words > 0 and (table.concat(q.words, " ") .. " ") or ""
	if q.rewards then return "@book " end
	return "@book " .. (q.todo and "is:todo " or q.done and "is:done " or "") .. (q.near and "sort:distance " or "") .. w
end

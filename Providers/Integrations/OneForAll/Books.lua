local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll

-- @book: WoW Forever's Library Books, OneForAll's list of them: the tomes found in the world and turned in to the
-- library for its rewards (not the lore books on the shelves). Each book is a quest (turning it in) and an item (the
-- book you carry), in a zone at a spot: a row each, with where it is and how far along you are ("in your bags", "turned
-- in"), on the map with Enter as a mailbox is. "library books", "books i still need", "nearest library book", "library
-- book rewards" ask for them (Simple mode; Search/Questions/Questions.lua).
--
-- How far along: OneForAll's own judgement when it gives one (FLT:GetBookState: a turn-in it saw, a book you marked,
-- one in your bags or bank, the quest flag), else the game's (the quest done, the book in your bags or bank).
--
-- Without OneForAll (1.4.7, the player's ask): QuestieDB's own data has the books too, read while it's installed: each
-- book's quest (its name), the item, and the world object it lies in with its spot. Fewer words than OneForAll's
-- (no notes on a spot, no sets, no reward tiers); OneForAll's list comes first whenever it's there. See "The books
-- from QuestieDB" below.

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

--- OneForAll's books, checked: { { name, quest, item, zone, subzone, x, y, set, container, note, status, raw }, ... }, or
--- nil.
function B.OFAData()
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
			-- (the books it needs are in its label, "10 books", "30 books (?)"; its req is a level: review)
			local need = type(t) == "table" and Num(tonumber((OA.Text(t.books) or ""):match("%d+") or ""))
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

local QuestDone = OA.QuestDone
local function Count(id, bank)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	return f and Num(Safe(f, id, bank)) or 0
end

--- Where you are with a book: OneForAll's state ("done", "bag", ...) for one of its own, else the game's.
function B.State(b)
	local lib = b.raw and OA.Lib()
	local s = lib and OA.Call(lib.GetBookState, lib, b.raw)
	if type(s) == "string" and B.STATES[s] then return s end
	if QuestDone(b.quest) then return "done" end
	if not b.item then return "missing" end
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

----------------------------------------------------------------------
-- The books from QuestieDB (without OneForAll). No list of them is kept: a book is told by its shape in QuestieDB's
-- quests (checked against QuestieDB_Forever's data, November 2026: 40 quests, every one of OneForAll's 39 among them
-- and no other quest):
--   * a quest started by a world object (the book lying there) and by an NPC (who takes it),
--   * and either that NPC's title is "Librarian" (32 of them: Stormwind's and Undercity's), or the quest is of the
--     "Special" sort (QuestSort 284, QuestieDB's zoneOrSort -284) and the item it asks for lies in that object (the
--     other eight, taken by a mage trainer and her Horde counterpart).
-- Every quest is looked at once, a slice a frame, after Questie's own indexing; @book is registered when books come
-- of it (a QuestieDB of another game version has none: no empty @book).
----------------------------------------------------------------------

local QD = ns.QuestieData
B.LIBRARIAN = "Librarian" -- (the title in English: QuestieDB's untranslated one is asked on another client)
B.SPECIAL_SORT = -284
local qd = { list = nil, rewards = nil, building = false }

local function IsLibrarian(id)
	local t = I.NpcField and (I.NpcField(id, "subNameEn") or I.NpcField(id, "subName"))
	return t == B.LIBRARIAN
end
local function Among(list, v)
	for _, x in ipairs(type(list) == "table" and list or {}) do if x == v then return true end end
	return false
end

--- One of QuestieDB's quests as a book ({ name, quest, item, zone, x, y, ui, container, note, level }), or nil: not one.
function B.FromQuest(DB, id)
	local starts = Safe(DB.QueryQuestSingle, id, "startedBy")
	if type(starts) ~= "table" then return nil end
	local npcs, objs = starts[1], starts[2]
	if type(npcs) ~= "table" or #npcs == 0 or type(objs) ~= "table" or #objs == 0 then return nil end
	local objv = Safe(DB.QueryQuestSingle, id, "objectives")
	local items = type(objv) == "table" and objv[3]
	local item = type(items) == "table" and type(items[1]) == "table" and Num(items[1][1]) or nil
	local librarian = false
	for _, n in ipairs(npcs) do if IsLibrarian(n) then librarian = true break end end
	if not librarian then
		if Num(Safe(DB.QueryQuestSingle, id, "zoneOrSort")) ~= B.SPECIAL_SORT or not item then return nil end
		local drops, inIt = DB.QueryItemSingle and Safe(DB.QueryItemSingle, item, "objectDrops"), false
		for _, o in ipairs(objs) do if Among(drops, o) then inIt = true break end end
		if not inIt then return nil end
	end
	local name = ns.Str(Safe(DB.QueryQuestSingle, id, "name"))
	if not name then return nil end
	-- where it lies: the object's spots, the one in the object's own zone first (a second zone's is an alternative)
	local spots, container = {}, nil
	for _, o in ipairs(objs) do
		container = container or (I.ObjectName and I.ObjectName(o))
		local home = Num(Safe(DB.QueryObjectSingle, o, "zoneID"))
		I._.EachSpot(Safe(DB.QueryObjectSingle, o, "spawns"), function(_, _, _, ui, c, _, area)
			spots[#spots + 1] = { ui = ui, x = c[1], y = c[2], zone = I.ZoneName(ui), home = area == home }
		end, true)
	end
	table.sort(spots, function(a, b)
		if a.home ~= b.home then return a.home end
		if a.ui ~= b.ui then return a.ui < b.ui end
		if a.x ~= b.x then return a.x < b.x end
		return a.y < b.y
	end)
	local at, note = spots[1], nil
	-- (another zone's spot: said; two spots a step apart in one zone are one place)
	for i = 2, #spots do
		local sp = spots[i]
		if sp.ui ~= at.ui and sp.zone then note = L["Also found at: %s"]:format(("%s %.1f, %.1f"):format(sp.zone, sp.x, sp.y)) break end
	end
	return { name = name, quest = id, item = item, zone = at and at.zone or nil, x = at and at.x or nil, y = at and at.y or nil,
		ui = at and at.ui or nil, container = container, note = note, level = Num(Safe(DB.QueryQuestSingle, id, "questLevel")) or 0 }
end

--- One of QuestieDB's quests as a reward for books turned in ({ quest (its name), questID, level }), or nil: a quest a
--- Librarian gives that starts at no object ("Friend of the Library", "Greater Friend of the Library").
function B.RewardQuest(DB, id)
	local starts = Safe(DB.QueryQuestSingle, id, "startedBy")
	if type(starts) ~= "table" then return nil end
	local npcs, objs = starts[1], starts[2]
	if type(npcs) ~= "table" or #npcs == 0 or (type(objs) == "table" and #objs > 0) then return nil end
	local librarian = false
	for _, n in ipairs(npcs) do if IsLibrarian(n) then librarian = true break end end
	local name = librarian and ns.Str(Safe(DB.QueryQuestSingle, id, "name"))
	if not name then return nil end
	return { quest = name, questID = id, level = Num(Safe(DB.QueryQuestSingle, id, "questLevel")) or 0 }
end

local RegisterBooks -- (below: the list itself)
--- Reads them, a slice a frame (every quest once: a few thousand). Nothing while Questie's own lists are being indexed.
function B.BuildQuestie()
	if qd.list or qd.building then return end
	local DB = QD and QD.Ready() and QD.DB()
	if not (DB and DB.QueryQuestSingle and DB.QuestIds and DB.QueryObjectSingle and I.RunSliced and I._.EachSpot) then return end
	local ids = DB.QuestIds() or {}
	if #ids == 0 then return end -- (not there yet: asked again)
	qd.building = true
	local out, rewards = {}, {}
	I.RunSliced("books: QuestieDB's quests", #ids, function(i)
		local b = B.FromQuest(DB, ids[i])
		if b then
			out[#out + 1] = b
		else
			local r = B.RewardQuest(DB, ids[i])
			if r then rewards[#rewards + 1] = r end
		end
	end, function()
		table.sort(rewards, function(a, b)
			if a.level ~= b.level then return a.level < b.level end
			return a.questID < b.questID
		end)
		-- (the order: by the level they're for, then by name, as OneForAll's sets go from 20 to 60)
		table.sort(out, function(a, b)
			if a.level ~= b.level then return a.level < b.level end
			return a.name < b.name
		end)
		for i, b in ipairs(out) do b.order = i end
		qd.list, qd.rewards, qd.building = out, rewards, false
		ns:Trace(("books: %d Library Books among QuestieDB's %d quests"):format(#out, #ids))
		if #out > 0 then
			RegisterBooks()
			ns:Changed("book")
		end
	end)
end
local function BuildWhenQuiet()
	if qd.list or qd.building then return end
	if (ns.background or 0) > 0 then return C_Timer.After(B.QUIET_WAIT, BuildWhenQuiet) end -- (Questie's lists first)
	B.BuildQuestie()
end
B.QUIET_WAIT = 2
function B.ForgetQuestie() qd.list, qd.rewards, qd.building = nil, nil, false end -- (tests)

--- The rewards as QuestieDB has them, without OneForAll: the Librarians' reward quests, lowest level first, each with the
--- items it gives (Questie's questRewards, Rewards.lua's index; none yet while that's being read: asked again). How
--- many books each takes isn't in QuestieDB: its level stands for it. { { quest, questID, level, items = { { id, name } } } }
function B.QuestieRewards()
	local QR = ns.QuestRewards
	local out = {}
	for _, r in ipairs(qd.rewards or {}) do
		local items = {}
		local list = QR and QR.RewardsOf and QR.RewardsOf(r.questID)
		if list == nil and QR and QR.Index and not QR.Index() then
			if ns.Filters then ns.Filters.loading = true end -- (the items quests reward are still being read)
		end
		for _, it in ipairs(list or {}) do items[#items + 1] = { id = it.id, name = it.name } end
		out[#out + 1] = { quest = r.quest, questID = r.questID, level = r.level, items = items }
	end
	return out
end

--- The books and whose list they are: OneForAll's when it has one, else QuestieDB's (nil: neither, or not read yet).
function B.Data()
	local ofa = OA.Loaded() and B.OFAData() or nil
	if ofa then return ofa, "OneForAll" end
	if qd.list and #qd.list > 0 then return qd.list, "QuestieDB" end
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
	if e.set or e.container then t:AddLine(ns.Join(SEP, e.set, e.container), 0.62, 0.62, 0.62) end
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
	t:AddLine(e.source == "QuestieDB" and L["Library Books from QuestieDB"] or L["Library Books from OneForAll"], 0.5, 0.5, 0.5)
end

-- a book with no spot known: Enter says so, nothing pressed
local function NoSpot(e)
	ns:Print((e.source == "QuestieDB" and L["QuestieDB has no spot for %s."] or L["OneForAll has no spot for %s yet."]):format(e.name))
end

--- The rows: one a book, in its list's order (OneForAll's: its sets, levels 20 to 60; QuestieDB's: by level, by name).
function B.Rows()
	local out = {}
	local data, source = B.Data()
	for _, b in ipairs(data or {}) do
		local state = B.State(b)
		local st = B.STATES[state]
		local zone = b.zone and (b.subzone and (b.zone .. ", " .. b.subzone) or b.zone) or nil
		local unsure = b.status and B.UNSURE[b.status] or nil
		local row = {
			key = b.quest, kind = "book", name = b.name, _lname = Lower(b.name), itemID = b.item, icon = B.ICON,
			state = state, isDone = st[2], zone = b.zone, subzone = b.subzone, note = b.note, set = b.set, container = b.container,
			unsure = unsure, order = b.order, tooltip = Tooltip, generic = false, pinName = b.name, source = source,
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

function RegisterBooks()
	if ns.providers.book then return end
	ns:RegisterProvider("book", {
		label = L["Library Book"], color = "ffd8b070", aliases = { "book", "books", "librarybook", "librarybooks", "library" },
		namesOnly = true, -- (a search that doesn't name it: by the books' names only, Scan.NameMode)
		lazy = true,
		-- (a book picked up, put in the bank, turned in)
		events = { "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "BANKFRAME_CLOSED" }, guard = 1,
		collect = B.Rows,
	})
end
--- @book: OneForAll's books at once when it has them (its own setup runs this too); else QuestieDB's, read once its data
--- can be (Setup.lua's "Books", after OneForAll's and Questie's).
function B.Setup()
	if ns.providers.book then return end
	if OA.Loaded() and B.OFAData() then
		B.Rewards()
		RegisterBooks()
		return
	end
	if QD and (QD.HasQuestie() or QD.Lib()) then QD.OnReady(BuildWhenQuiet) end
end
OA.AddSetup(B.Setup)
if I._ then I._.SetupBooks = B.Setup end
OA.AddStatus(function()
	local d = B.OFAData()
	return d and L["%d Library Books (@book)"]:format(#d) or nil
end)
--- .integrations' line when the books are QuestieDB's (OneForAll's are counted on its own line); nil otherwise.
function B.Status()
	local d, source = B.Data()
	if source ~= "QuestieDB" then return nil end
	return L["%d from QuestieDB (@book). OneForAll adds notes on each spot and the rewards."]:format(#d)
end

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
	local library, book, plural, cues, rest = false, false, false, {}, {}
	for w in t:gmatch("%S+") do
		if w == "library" then library = true
		elseif BOOK[w] then book = true; plural = plural or w == "books" or w == "tomes"
		elseif CUE[w] then cues[CUE[w]] = true
		elseif not ASK[w] then rest[#rest + 1] = w end
	end
	if not book then return nil end
	-- ("book", "my spell book", "where do i find the book": not these. Without "library", books asked about as a list:
	-- "books i still need", "missing books")
	if not library and not (plural and (cues.todo or cues.done or cues.have or cues.near or cues.rewards)) then return nil end
	-- other words: only those naming a book or its place ("library books in the barrens"), else not this question
	if #rest > 0 and not B.AnyFor(rest) then return nil end
	return { todo = cues.todo or cues.near or nil, done = (cues.done or cues.have) and not cues.todo or nil, near = cues.near,
		rewards = cues.rewards and not cues.near or nil, words = rest }
end

local Has = OA.Has
function B.AnyFor(words)
	local p = ns.providers.book
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do if Has(e, words) then return true end end
	return false
end

--- The rewards as rows: a line a tier ("Friend of the Library: 10 books", reached or not), then each item it gives as
--- an item's own row: its tooltip the item's, Enter as any item (1.4.8, the player: the rows named the rewards but
--- showed nothing of them). OneForAll's tiers when it has them (how many books each takes); else QuestieDB's reward
--- quests and the items Questie says they give.
local function RewardRows(done)
	local out = {}
	local P = ns.Pipes
	local function Items(t)
		local names = {}
		for _, it in ipairs(t.items) do names[#names + 1] = it.name or L["item %s"]:format(it.id) end
		return names
	end
	local function Add(t, head, said)
		out[#out + 1] = ns.NoteRow(head, table.concat(Items(t), ", "))
		out[#out].icon = B.ICON
		for _, it in ipairs(t.items) do
			local r = P and P.ItemRow and P.ItemRow(it.id, ns.Detail(said, it.desc), L["Rewards"], it.name)
			if r then out[#out + 1] = r end
		end
	end
	local tiers = B.Rewards()
	if tiers then
		for _, t in ipairs(tiers) do
			local title = t.quest or t.label or ""
			local books = L["%d books"]:format(t.need)
			Add(t, title .. ": " .. books .. (done >= t.need and ("  " .. L["(reached)"]) or ""), ns.Detail(title, books))
		end
	elseif not OA.Loaded() then
		for _, t in ipairs(B.QuestieRewards()) do
			local level = L["level %d"]:format(t.level)
			Add(t, t.quest .. ": " .. level .. (QuestDone(t.questID) and ("  " .. L["(claimed)"]) or ""), ns.Detail(t.quest, level))
		end
	end
	return ns.ScoreInOrder(out)
end

function B.Answer(q)
	q = q or {}
	local p = ns.providers.book
	local all = p and ns:GetEntries(p) or {}
	local done = B.Progress(all)
	local progress = L["%d of %d turned in"]:format(done, #all)
	if q.rewards then
		local rows = RewardRows(done)
		if #rows == 0 then
			return { ns.NoteRow(OA.Loaded() and L["OneForAll lists no rewards for the Library Books"]
				or L["The Library Books' rewards aren't known without OneForAll"]) }, L["Library Book rewards"]
		end
		return rows, L["Library Book rewards"] .. SEP .. progress
	end
	local rows = {}
	for _, e in ipairs(all) do
		local ok = Has(e, q.words) and not (q.todo and e.isDone) and not (q.done and not e.isDone)
		if ok then rows[#rows + 1] = e end
	end
	local note = (q.todo and L["Library Books still to turn in"]) or (q.done and L["Library Books turned in"]) or L["Library Books"]
	if q.near then
		local near = OA.Nearest(rows)
		if not near then
			ns.ScoreInOrder(rows)
			return rows, note .. SEP .. L["where you are isn't known here"]
		end
		rows = near
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

--- The books asked for as Advanced syntax: its answer and its Alt+` (docs/QUESTIONS.md 4.1), in OneForAll's order; nil
--- for the reward tiers (rows of no list) and the nearest (OneForAll's nearest spot of each: B.Answer's own).
function B.Line(q)
	q = q or {}
	if q.rewards or q.near then return nil end
	local parts = { "@book" }
	if q.todo then parts[#parts + 1] = "is:todo" elseif q.done then parts[#parts + 1] = "is:done" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	parts[#parts + 1] = "sort:list"
	return table.concat(parts, " ") .. " "
end
function B.Footer(q, rows)
	local p = ns.providers.book
	local all = p and ns:GetEntries(p) or {}
	local done = B.Progress(all)
	local note = (q.todo and L["Library Books still to turn in"]) or (q.done and L["Library Books turned in"]) or L["Library Books"]
	if #rows == 0 then return note end
	local nxt = B.NextReward(done)
	return note .. SEP .. L["%d of %d turned in"]:format(done, #all) .. (nxt and (SEP .. L["next reward at %d"]:format(nxt.need)) or "")
end
function B.None(q) return { ns.NoteRow(q.todo and L["Every Library Book is turned in"] or L["No Library Book has that"]) } end

function B.ToAdvanced(q)
	q = q or {}
	local w = q.words and #q.words > 0 and (table.concat(q.words, " ") .. " ") or ""
	-- (the reward tiers are the question's own rows, no list's: the question itself, which Advanced answers the same)
	if q.rewards then return nil end
	return "@book " .. (q.todo and "is:todo " or q.done and "is:done " or "") .. (q.near and "sort:distance " or "") .. w
end

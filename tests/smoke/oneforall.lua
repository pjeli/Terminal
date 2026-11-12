-- OneForAll - Forever (1.0.1, the player's ask; Providers/Integrations/OneForAll/OneForAll.lua): its tables read while it's
-- installed. @book: WoW Forever's Library Books (Providers/Integrations/OneForAll/Books.lua), each where it is and how far along you
-- are (OneForAll's judgement, else the game's); "library books", "books i still need", "nearest library book",
-- "library book rewards" in Simple mode; a table not in the shape expected said once with what's unavailable; without
-- OneForAll: no @book, no question.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, OA, L = ns.Integrations, ns.OneForAll, ns.L
local B = OA.Books

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[oneforall: its Library Books, checked and read]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"),
		here = I.Here, spot = I.SpotXY, dist = I.RowDistance, failed = I.failed, on = OA.on, easy = ns.db.easyMode,
		flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, count = _G.GetItemCount, citem = C_Item and C_Item.GetItemCount }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Said(s) for _, m in ipairs(said) do if m:find(s, 1, true) then return m end end end
	local function Fresh()
		ns.providers.book = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "book" then table.remove(ns.providerOrder, i) end end
		I.failed, OA.on = {}, nil
		OA.Forget()
		I._.SetupOneForAll()
		ns:AliasesChanged()
	end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "book" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		-- the game: one quest turned in, one book in your bags, one in the bank
		local DONE, BAGS, BANK = { [9102] = true }, { [8103] = 1 }, { [8104] = 1 }
		if C_QuestLog then C_QuestLog.IsQuestFlaggedCompleted = function(id) return DONE[id] == true end end
		local function Count(id, bank) return (BAGS[id] or 0) + (bank and (BANK[id] or 0) or 0) end
		_G.GetItemCount = Count
		if C_Item then C_Item.GetItemCount = Count end
		-- its tables (Data.lua's shape), a few books
		local state = {}
		_G.OneForAll = {
			MAP_IDS = { ["The Barrens"] = 1413, ["Duskwood"] = 1431 },
			SETS = { arcane = "Arcane Studies" },
			BOOKS = {
				{ name = "Tome of Frost", questId = 9101, itemId = 8101, zone = "The Barrens", subzone = "The Crossroads", x = 50.1, y = 30.2, set = "arcane" },
				{ name = "Ledger of Ash", questId = 9102, itemId = 8102, zone = "Duskwood", x = 20, y = 40 },
				{ name = "Codex of Tides", questId = 9103, itemId = 8103, zone = "The Barrens", x = 60, y = 60, status = "reported" },
				{ name = "Folio of Stars", questId = 9104, itemId = 8104, zone = "Moonglade" }, -- (no spot)
				{ name = "Broken Entry" }, -- (not in the shape expected: left out)
			},
			BOOK_REWARD_TIERS = {
				{ books = "4 books (?)", req = 1, quest = "Keeper of Tomes", items = { { 7002, "Scholar's Robe" } } },
				{ books = "2 books", req = 1, quest = "Friend of the Library", items = { { 7001, "Library Card", nil, "a card" } } },
			},
		}
		function OneForAll:GetBookState(b) return state[b.questId] end
		I.SpotXY = function(ui, c) return ui == 1413 and 1 or 2, c[1] * 10, c[2] * 10 end
		Fresh()
		local p = ns.providers.book
		check(p and ns:ResolveProvider("books") == p and ns:ResolveProvider("library") == p, "@book, @books, @library")
		check(not Said(L["@book (its Library Books) is unavailable."]) and not Said(L["The Library Books' rewards are unavailable."]), "its tables as expected: nothing said of the books: " .. tostring(said[1]))
		local rows = ns:GetEntries(p)
		local by = {}
		for _, e in ipairs(rows) do by[e.name] = e end
		check(#rows == 4 and not by["Broken Entry"], "the four books in the shape expected: " .. Names(rows))
		-- how far along: the game's (OneForAll says nothing of these yet)
		check(by["Tome of Frost"].state == "missing" and by["Ledger of Ash"].state == "done" and by["Codex of Tides"].state == "bag"
			and by["Folio of Stars"].state == "bank", "the game's: to find, turned in, in your bags, in your bank")
		check(by["Ledger of Ash"].isDone and not by["Codex of Tides"].isDone, "turned in: done; in your bags: not yet")
		check(by["Tome of Frost"].ui == 1413 and by["Tome of Frost"].px == 50.1 and by["Tome of Frost"].wcont == 1, "a spot: its map and place")
		check(by["Folio of Stars"].ui == nil and by["Folio of Stars"].activate, "no spot: no map, Enter says so")
		said = {}
		by["Folio of Stars"].activate(by["Folio of Stars"])
		check(Said(L["OneForAll has no spot for %s yet."]:format("Folio of Stars")), "Enter on a book with no spot: said")
		check((by["Codex of Tides"].detail or ""):find(L["spot reported by players"], 1, true), "a spot not confirmed: said")
		check(by["Tome of Frost"].set == "Arcane Studies", "its set's name")
		-- the filters
		local res = UI:Search("@book is:todo")
		check(#res == 3, "@book is:todo: the three not turned in: " .. Names(res))
		res = UI:Search("@book is:done")
		check(#res == 1 and res[1].name == "Ledger of Ash", "@book is:done: " .. Names(res))
		res = UI:Search("@book barrens")
		check(#res == 2, "@book barrens: by zone: " .. Names(res))
		-- OneForAll's own judgement first: a book you marked done
		state[9101] = "manual"
		p._dirty = true
		local frost
		for _, e in ipairs(ns:GetEntries(p)) do if e.name == "Tome of Frost" then frost = e end end
		check(frost and frost.state == "manual" and frost.isDone, "OneForAll's state: marked done")
		state[9101] = "nonsense" -- (one it doesn't say: the game's)
		p._dirty = true
		for _, e in ipairs(ns:GetEntries(p)) do if e.name == "Tome of Frost" then frost = e end end
		check(frost and frost.state == "missing", "a state not known: the game's")
		-- its rewards
		check(B.NextReward(1).need == 2 and B.NextReward(2).need == 4 and B.NextReward(4) == nil,
			"the next reward: by books turned in (its label's number, not its req, a level)")
		-- the questions
		for _, s in ipairs({ "library books", "books i still need", "nearest library book", "library book rewards", "which library books have i turned in",
			"library books in the barrens", "missing books" }) do
			check(B.Question(s) ~= nil, s .. ": the books question")
		end
		for _, s in ipairs({ "book", "spell book", "books of the dead", "library books in stormwind", "the tome of frost recipe", "my spell book",
			"where do i find the book", "find a book" }) do
			check(B.Question(s) == nil, s .. ": not it")
		end
		check(B.Question("books i still need").todo and B.Question("library books turned in").done, "todo, done")
		ns.db.easyMode = true; UI:EasyChanged()
		UI:Open("books i still need"); FlushAll()
		local r = UI.Results()
		check(#r == 3 and not r[1].isDone, "books i still need: the three to turn in: " .. Names(r))
		UI:Hide(); FlushAll()
		UI:Open("library books in the barrens"); FlushAll()
		r = UI.Results()
		check(#r == 2, "library books in the barrens: " .. Names(r))
		UI:Hide(); FlushAll()
		-- nearest: by how far each is (the Barrens' on your continent)
		I.Here = function() return { cont = 1, x = 600, y = 600 } end
		UI:Open("nearest library book"); FlushAll()
		r = UI.Results()
		check(r[1] and r[1].name == "Codex of Tides" and (r[1].detail or ""):find("yd", 1, true), "nearest library book: the Codex, how far: " .. Names(r))
		check(not (r[2] and r[2].name == "Ledger of Ash"), "nearest: not one turned in")
		UI:Hide(); FlushAll()
		UI:Open("library book rewards"); FlushAll()
		r = UI.Results()
		check(r[1] and r[1].name:find("Friend of the Library", 1, true) and (r[1].detail or ""):find("Library Card", 1, true)
			and r[1].name:find(L["(reached)"], 1, true) == nil, "library book rewards: each tier, its items, not reached yet: " .. Names(r))
		-- (1.4.8, the player: "I can see the rows but how come I cannot see the reward loot") each reward under its tier
		-- as an item's own row: the item's tooltip, a row to act on, not a line of names
		check(#r == 4 and r[2].itemID == 7001 and r[2].name == "Library Card" and r[2].link == "item:7001" and not r[2].noActivate and not r[2].raw,
			"under a tier, each item it gives as an item's row (named by the list until the game names it): " .. Names(r))
		check(tostring(r[2].detail):find("Friend of the Library", 1, true) and tostring(r[2].detail):find(L["%d books"]:format(2), 1, true)
			and tostring(r[2].detail):find("a card", 1, true), "which tier it's of, and OneForAll's words on it: " .. tostring(r[2].detail))
		check(r[3].raw and r[3].name:find("Keeper of Tomes", 1, true) and r[4].itemID == 7002 and r[4].name == "Scholar's Robe",
			"the next tier and its item after: " .. Names(r))
		UI:Hide(); FlushAll()
		check(B.ToAdvanced(B.Question("nearest library book")) == "@book is:todo sort:distance ", "to Advanced: " .. B.ToAdvanced(B.Question("nearest library book")))
		-- (review, 1.0.42) the reward tiers: the question itself in Advanced, which lists the same tiers (not every book)
		local line = ns.QuestionToAdvanced("library book rewards")
		local tiers = UI:Search(line)
		check(line:find("library book rewards", 1, true) and tiers[1] and tiers[1].name:find("Friend of the Library", 1, true),
			"library book rewards to Advanced: the tiers again: " .. tostring(line))
		ns.db.easyMode = false; UI:EasyChanged()
		-- .integrations: found, how many books
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find("OneForAll", 1, true) and lines:find(L["%d Library Books (@book)"]:format(4), 1, true), ".integrations: " .. lines)

		-- not in the shape expected: said once, with what's unavailable
		said = {}
		OneForAll.BOOKS = "moved"
		Fresh()
		check(not ns.providers.book, "BOOKS changed: no @book")
		local m = Said(L["@book (its Library Books) is unavailable."])
		check(m and m:find("OneForAll", 1, true), "said in chat, with what's unavailable: " .. tostring(said[1]))
		local n = #said
		OA.Forget(); B.Data()
		check(#said == n, "said once a session")
		OneForAll.BOOKS = { { name = "Only", questId = 1, itemId = 2 } }
		OneForAll.BOOK_REWARD_TIERS = nil -- (some versions have none: quiet)
		said = {}
		Fresh()
		check(ns.providers.book and not Said(L["The Library Books' rewards are unavailable."]), "no reward tiers: @book still, nothing said: " .. tostring(said[1]))
		-- without OneForAll: no @book, no question
		_G.OneForAll = nil
		Fresh()
		check(not ns.providers.book and B.Question("library books") == nil, "without OneForAll: no @book, no question")
		lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find("OneForAll: " .. L["not found"], 1, true), ".integrations: not found")
	end)
	_G.OneForAll = save.lib
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, I.Here, I.SpotXY, I.RowDistance = save.print, save.here, save.spot, save.dist
	I.failed, OA.on = save.failed, save.on
	if C_QuestLog then C_QuestLog.IsQuestFlaggedCompleted = save.flagged end
	_G.GetItemCount = save.count
	if C_Item then C_Item.GetItemCount = save.citem end
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget()
	UI:Hide(); FlushAll()
	if not ok then check(false, "oneforall: " .. tostring(err)) end
end

-- Spoken's lore (Providers/Integrations/Spoken.lua), read from its data globals at run time (stand-ins here): @lore (boss
-- stories, zones' and subzones' lore; Enter reads the whole text), every readable in @book (read or not by db.lore),
-- "who is edwin vancleef", "lore of duskwood", "tell me about goldshire", "books in duskwood", "books that mention
-- stalvan"; Simple mode's Lore category; beside OneForAll's Library Books, which keep their own counts and questions.
-- Without Spoken: none of it.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local I, L, E = ns.Integrations, ns.L, ns.Easy
local SL = ns.Spoken

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end
local function Has(rows, name) for _, e in ipairs(rows) do if e.name == name then return e end end end

io.write("[spoken: lore and books]\n")
do
	local GLOBALS = { "SpokenBosses", "SpokenBossStories", "SpokenDungeons", "SpokenPlaces", "SpokenReadablesData",
		"SpokenReadablesPlaces", "OneForAll" }
	local save = { providers = ns.providers, order = ns.providerOrder, show = ns.ShowText, print = ns.Print,
		lore = ns.db.lore, easy = ns.db.easyMode, map = rawget(_G, "C_Map"), g = {}, failed = I.failed,
		on = ns.OneForAll and ns.OneForAll.on, verbs = E.VERBS.lore }
	for _, g in ipairs(GLOBALS) do save.g[g] = rawget(_G, g) end
	local shown, said = {}, {}
	ns.ShowText = function(_, title, text) shown[#shown + 1] = { title = title, text = text } end
	ns.Print = function(_, m) said[#said + 1] = m end
	local function Fresh()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "book" and id ~= "lore" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		SL.Forget()
		ns:AliasesChanged()
	end
	local ok, err = pcall(function()
		-- without Spoken: no @lore, @book as it was (none here, OneForAll isn't either), no question
		for _, g in ipairs(GLOBALS) do _G[g] = nil end
		Fresh()
		I._.SetupSpoken()
		check(not ns.providers.lore and not ns.providers.book and ns.LoreQ.Question("who is edwin vancleef") == nil
			and ns.LoreBooks.Question("books that mention stalvan") == nil and SL.Status() == nil,
			"without Spoken: no @lore, no @book, no questions, no .integrations line")

		-- its data, as its files shape it (a few of each)
		local MAPS = { [91431] = { name = "Duskwood" }, [91429] = { name = "Elwynn Forest" } }
		_G.C_Map = setmetatable({ GetMapInfo = function(id) return MAPS[id] end }, { __index = save.map })
		_G.SpokenBosses = { version = 1, maps = {
			[36] = {
				{ id = 2747, ids = { 2747 }, key = "edwin vancleef", "Edwin VanCleef", deDE = "Edwin van Cleef" },
				{ id = 2746, ids = { 2746 }, key = "cookie", "Cookie" }, -- (no story: no row)
				{ id = 1, key = 5 }, -- (not in the shape expected: left out)
			},
		} }
		_G.SpokenBossStories = { [36] = {
			["edwin vancleef"] = { "Edwin VanCleef led the stonemasons of Stormwind. When the nobles would not pay, he took the Defias Brotherhood underground. A second sentence follows here.\n\nMore of his story.", deDE = "Auf Deutsch." },
		} }
		_G.SpokenDungeons = { dungeons = { [36] = { zone = 1436, "Deadmines", deDE = "Todesminen" } } }
		_G.SpokenPlaces = {
			Zones = { [91431] = { name = "Duskwood", short = "A dark forest.", full = "A dark forest, cursed long ago.", source = "https://warcraft.wiki.gg/wiki/Duskwood" } },
			Subzones = { [91429] = {
				["goldshire"] = { name = "Goldshire", short = "A small town.", full = "A small town with an inn.", source = "" },
				["empty place"] = { pending = true, name = "Empty Place", short = "", full = "" }, -- (not written yet: no row)
			} },
		}
		function SpokenPlaces:GetLore(id) return self.Zones[id] end
		_G.SpokenReadablesData = { version = 1,
			books = { [10] = { title = "Stalvan's Letter", pages = { 100, 101 } }, [11] = { title = "A Torn Note", pages = { 110 } },
				[12] = { title = "Broken" } }, -- (no pages: left out)
			pages = { [100] = { book = 10, number = 1, text = "My dearest, I write in haste." },
				[101] = { book = 10, number = 2, text = "Stalvan Mistmantle will not stop. Tell no one." },
				[110] = { book = 11, number = 1, text = "Meet me by the mill at dusk." } },
			owners = { item = { [5001] = 10 }, object = { [6001] = 11 } },
		}
		_G.SpokenReadablesPlaces = { books = { [10] = { kind = "carried", type = "letter", zones = { 91431 } },
			[11] = { kind = "world", type = "note", zones = { 91429 } } } }
		ns.db.lore = { ["stalvan's letter"] = { title = "Stalvan's Letter", pages = {} } } -- (read in the game)
		said = {}
		Fresh()
		I._.SetupSpoken()

		-- @lore: the boss with a story, the zone, the subzone written
		local p = ns.providers.lore
		check(p and p.explicit and p.idleDrop and ns:ResolveProvider("story") == p, "@lore, @story: explicit, freed when idle")
		local rows = p and ns:GetEntries(p) or {}
		check(#rows == 3 and Has(rows, "Edwin VanCleef") and Has(rows, "Duskwood") and Has(rows, "Goldshire"),
			"@lore: the boss with a story, the zone, the subzone written (none for Cookie, Empty Place): " .. Names(rows))
		local boss, zone, sub = Has(rows, "Edwin VanCleef"), Has(rows, "Duskwood"), Has(rows, "Goldshire")
		check(boss and rawget(boss, "_compact") and boss.kind == "lore" and boss.detail == L["Boss"] .. ns.DETAIL_SEP .. "Deadmines"
			and sub.detail == "Elwynn Forest" and zone.detail == L["Zone"], "details: the boss's instance, a subzone's zone: "
			.. tostring(boss and boss.detail) .. " / " .. tostring(sub and sub.detail))
		check(E.Verbs(boss) == L["read"] and E.CategoryOf(boss) == "lore" and E.CategoryOf(zone) == "lore", "read; Simple mode's Lore")
		-- the tooltip: the place's short text; a story's first sentences
		local lines = {}
		local tip = { SetText = function(_, s) lines[#lines + 1] = s end, AddLine = function(_, s) lines[#lines + 1] = s end }
		boss.tooltip(boss, tip)
		local all = table.concat(lines, "\n")
		check(all:find("led the stonemasons", 1, true) and not all:find("More of his story", 1, true) and all:find("Spoken", 1, true),
			"a story's tooltip: its first words, from Spoken: " .. all)
		lines = {}
		zone.tooltip(zone, tip)
		check(table.concat(lines, "\n"):find("A dark forest.", 1, true), "a zone's tooltip: its short text")
		-- Enter: the whole text in the text window, with where it's from
		boss.activate(boss)
		zone.activate(zone)
		check(#shown == 2 and shown[1].text:find("More of his story", 1, true) and shown[1].title:find("Deadmines", 1, true)
			and shown[2].text:find("cursed long ago", 1, true) and shown[2].text:find("warcraft.wiki.gg", 1, true),
			"Enter: the whole story, the zone's whole lore and its page: " .. tostring(shown[1] and shown[1].title))
		local res = UI:Search("@lore vancleef")
		check(res[1] and res[1].name == "Edwin VanCleef", "@lore vancleef: " .. Names(res))

		-- @book: the readables (no OneForAll: they alone), read or not
		local b = ns.providers.book
		check(b and b.readablesOnly and ns:ResolveProvider("readables") == b, "@book, @readables: Spoken's books alone without OneForAll")
		local books = b and ns:GetEntries(b) or {}
		local letter, note = Has(books, "Stalvan's Letter"), Has(books, "A Torn Note")
		check(#books == 2 and letter and note, "a row per book in the shape expected: " .. Names(books))
		check(letter and letter.detail == L["read"] .. ns.DETAIL_SEP .. "Duskwood" and note.detail == L["unread"] .. ns.DETAIL_SEP .. "Elwynn Forest"
			and letter.kind == "book" and letter.kindLabel:find(L["Book"], 1, true), "read (db.lore) or not, and where: " .. tostring(letter and letter.detail))
		check(E.CategoryOf(letter) == "lore" and E.Verbs(letter) == L["read"], "a readable: Simple mode's Lore, Enter reads it")
		letter.activate(letter)
		check(shown[3] and shown[3].text:find("I write in haste", 1, true) and shown[3].text:find("will not stop", 1, true), "Enter: its pages")
		res = UI:Search("@book is:unread")
		check(#res == 1 and res[1].name == "A Torn Note", "@book is:unread: " .. Names(res))
		-- read one in the game: read at once (the rows stay the same)
		ns.db.lore["a torn note"] = { title = "A Torn Note", pages = {} }
		check(note.detail:find(L["read"], 1, true) == 1, "read since: read")
		ns.db.lore["a torn note"] = nil

		-- the questions
		ns.db.easyMode = true; UI:EasyChanged()
		local function Top(line) local c = ns.Questions.Ranked(line)[1] return c and c.a.id end
		check(Top("who is edwin vancleef") == "LoreQ" and Top("lore of duskwood") == "LoreQ" and Top("tell me about goldshire") == "LoreQ",
			"the lore questions: " .. tostring(Top("who is edwin vancleef")) .. " " .. tostring(Top("lore of duskwood")))
		check(ns.LoreQ.Question("who is hogger") == nil and ns.LoreQ.Question("duskwood") == nil, "not a lore question: no row by that name, no cue")
		rows = ns.Questions.Answer("who is edwin vancleef")
		check(rows[1] and rows[1].name == "Edwin VanCleef", "who is edwin vancleef: " .. Names(rows))
		rows = ns.Questions.Answer("tell me about goldshire")
		check(rows[1] and rows[1].name == "Goldshire", "tell me about goldshire: " .. Names(rows))
		check(Top("books in duskwood") == "LoreBooks" and Top("books that mention stalvan") == "LoreBooks", "the books' questions")
		rows = ns.Questions.Answer("books in duskwood")
		check(#rows == 1 and rows[1].name == "Stalvan's Letter", "books in duskwood: " .. Names(rows))
		local note2
		rows, note2 = ns.Questions.Answer("books that mention stalvan")
		check(#rows == 1 and rows[1].name == "Stalvan's Letter" and rows[1].detail:find("Stalvan Mistmantle", 1, true)
			and note2 == L["Books that mention %s"]:format("stalvan"), "books that mention stalvan: the pages searched, the words around: "
			.. Names(rows) .. " / " .. tostring(rows[1] and rows[1].detail))
		rows = ns.Questions.Answer("books that mention murloc")
		check(#rows == 1 and rows[1].name == L["No book mentions %s"]:format("murloc"), "none: said")
		ns.db.easyMode = false; UI:EasyChanged()

		-- .integrations
		local out = table.concat(ns.commands.integrations.run(""), "\n")
		check(out:find("Spoken: " .. L["%d boss stories and %d places (@lore), %d books (@book)"]:format(1, 2, 2), 1, true), ".integrations: " .. out)

		-- beside OneForAll's Library Books: one @book, its counts and questions its own books'
		local OA, B = ns.OneForAll, ns.OneForAll.Books
		_G.OneForAll = { MAP_IDS = { ["Duskwood"] = 91431 }, BOOKS = {
			{ name = "Ledger of Ash", questId = 9102, itemId = 8102, zone = "Duskwood" },
			{ name = "Tome of Frost", questId = 9101, itemId = 8101, zone = "Duskwood" } } }
		Fresh()
		I.failed, OA.on = {}, nil
		OA.Forget()
		I._.SetupOneForAll()
		I._.SetupSpoken()
		b = ns.providers.book
		books = b and ns:GetEntries(b) or {}
		check(b and not b.readablesOnly and #books == 4 and ns:ResolveProvider("readables") == b, "@book: the Library Books and the readables: " .. Names(books))
		local done, of = B.Progress(books)
		check(of == 2, "the Library Books' count leaves the readables out: " .. tostring(of))
		local ledger = Has(books, "Ledger of Ash")
		check(ledger and E.CategoryOf(ledger) == "quests" and E.CategoryOf(Has(books, "A Torn Note")) == "lore",
			"a Library Book under Quests, a readable under Lore")
		check(B.Line(B.Question("library books")):find("is:library", 1, true), "library books: is:library (not the readables)")
		res = UI:Search("@book is:library")
		check(#res == 2 and not Has(res, "A Torn Note"), "@book is:library: " .. Names(res))
	end)
	for _, g in ipairs(GLOBALS) do _G[g] = save.g[g] end
	_G.C_Map = save.map
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns:ResolveProvider("item") -- (the @kind words made again now, from the real lists: a later file swaps in stand-ins)
	ns.ShowText, ns.Print, ns.db.lore = save.show, save.print, save.lore
	E.VERBS.lore = save.verbs
	I.failed = save.failed
	if ns.OneForAll then ns.OneForAll.on = save.on; ns.OneForAll.Forget() end
	SL.Forget()
	ns.db.easyMode = save.easy; UI:EasyChanged()
	UI:Hide(); FlushAll()
	if not ok then check(false, "spoken: " .. tostring(err)) end
end

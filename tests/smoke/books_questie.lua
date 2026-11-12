-- @book without OneForAll (1.4.7, Providers/Integrations/OneForAll/Books.lua): QuestieDB's own data has WoW Forever's
-- Library Books, read while it's installed. A book is told by its shape among QuestieDB's quests, no list kept: started
-- by a world object and an NPC, that NPC titled "Librarian", or the quest of the Special sort with the item it asks for
-- lying in that object. OneForAll's list comes first whenever it's there; a QuestieDB with no such quest: no @book.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L, I, OA, QD = ns.L, ns.Integrations, ns.OneForAll, ns.QuestieData
local B = ns.LibraryBooks

local function Names(rows)
	local t = {}
	for i, e in ipairs(rows or {}) do t[i] = tostring(e.name) end
	return table.concat(t, " | ")
end

io.write("[library books from QuestieDB, without OneForAll]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, print = ns.Print, lib = rawget(_G, "OneForAll"), on = OA.on,
		failed = I.failed, easy = ns.db.easyMode, bg = ns.background, db = QD.DB, ready = QD.Ready, qlib = QD.Lib, has = QD.HasQuestie,
		onReady = QD.OnReady, uiOf = QD.UiMapOfArea, field = I.NpcField, objName = I.ObjectName, zoneName = I.ZoneName, spot = I.SpotXY,
		here = I.Here, flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, count = _G.GetItemCount,
		citem = C_Item and C_Item.GetItemCount, loaded = OA.Loaded, rewardsOf = ns.QuestRewards.RewardsOf, index = ns.QuestRewards.Index }
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	local ok, err = pcall(function()
		ns.providers, ns.providerOrder = {}, {}
		for _, id in ipairs(save.order) do
			if id ~= "book" then ns.providers[id] = save.providers[id]; ns.providerOrder[#ns.providerOrder + 1] = id end
		end
		_G.OneForAll = nil
		OA.Loaded = function() return type(rawget(_G, "OneForAll")) == "table" end
		-- the game: one quest turned in, one book in your bags
		local DONE, BAGS = { [502] = true }, { [7003] = 1 }
		if C_QuestLog then C_QuestLog.IsQuestFlaggedCompleted = function(id) return DONE[id] == true end end
		local function Count(id) return BAGS[id] or 0 end
		_G.GetItemCount = Count
		if C_Item then C_Item.GetItemCount = Count end
		-- QuestieDB: three books (two a Librarian's, one a mage trainer's of the Special sort), one with no spot, and
		-- quests that aren't books
		local QUESTS = {
			[501] = { name = "Tome of Winds", startedBy = { { 211, 212 }, { 9001 } }, objectives = { [3] = { { 7001 } } }, questLevel = 20, zoneOrSort = -284 },
			[502] = { name = "Atlas of Ash", startedBy = { { 211 }, { 9002 } }, questLevel = 35 }, -- (no item, no sort: a Librarian's all the same)
			[503] = { name = "Magma Notes", startedBy = { { 300 }, { 9003 } }, objectives = { [3] = { { 7003 } } }, questLevel = 60, zoneOrSort = -284 },
			[508] = { name = "Folio of Stars", startedBy = { { 211 }, { 9008 } }, objectives = { [3] = { { 7008 } } }, questLevel = 20 },
			[504] = { name = "Morganth", startedBy = { { 313 }, { 31 } }, objectives = { [3] = { { 3617 } } }, questLevel = 30, zoneOrSort = 44 },
			[505] = { name = "A Special Errand", startedBy = { { 300 }, { 9005 } }, objectives = { [3] = { { 7005 } } }, questLevel = 60, zoneOrSort = -284 },
			[506] = { name = "Friend of the Library", startedBy = { { 211, 212 } }, questLevel = 20, zoneOrSort = -284 },
			[507] = { name = "Children's Week", startedBy = { { 14451 } }, questLevel = 60, zoneOrSort = -284 },
			[509] = { name = "The Ancient Leaf", startedBy = { nil, { 9009 } }, questLevel = 60 },
		}
		local OBJECTS = {
			[9001] = { name = "Gnomish Tome", zoneID = 38, spawns = { [40] = { { 52.7, 53.8 } }, [38] = { { 35.6, 48.9 } } } },
			[9002] = { name = "Scrolls", zoneID = 10, spawns = { [10] = { { 16.7, 28.4 }, { 16.8, 28.4 } } } },
			[9003] = { name = "Book", zoneID = 46, spawns = { [46] = { { 26.4, 24.5 } } } },
			[9005] = { name = "Crate", zoneID = 46, spawns = { [46] = { { 50, 50 } } } },
			[9008] = { name = "Book", zoneID = 493 }, -- (no spawn known)
			[31] = { name = "Old Lion Statue", zoneID = 44, spawns = { [44] = { { 79.4, 46.8 } } } },
		}
		local ITEMS = { [7003] = { objectDrops = { 9003 } }, [7005] = { objectDrops = { 1 } }, [3617] = { objectDrops = { 31 } } }
		local TITLE = { [211] = "Librarian", [212] = "Librarian", [300] = "Mage Trainer" }
		local asked = 0
		-- (QuestieDB's WoW Forever corrections, as in game: the Library quests' sort becomes your capital; the base data
		-- keeps the Special sort, Quest.GetRaw: 1.4.12, seen in game, 32 books of 40 without it)
		local CORRECTED = { [503] = { zoneOrSort = 1497 }, [505] = { zoneOrSort = 1497 } }
		local db = {
			QueryQuestSingle = function(id, f)
				local c = CORRECTED[id]
				if c and c[f] ~= nil then return c[f] end
				return QUESTS[id] and QUESTS[id][f]
			end,
			RawQuestSingle = function(id, f) return QUESTS[id] and QUESTS[id][f] end,
			QueryObjectSingle = function(id, f) return OBJECTS[id] and OBJECTS[id][f] end,
			QueryItemSingle = function(id, f) return ITEMS[id] and ITEMS[id][f] end,
			QuestIds = function() asked = asked + 1 return { 501, 502, 503, 504, 505, 506, 507, 508, 509 } end,
		}
		local ready = true
		QD.DB = function() return ready and db or nil end
		QD.Ready = function() return ready end
		QD.Lib = function() return {} end
		QD.HasQuestie = function() return false end
		local waiting
		QD.OnReady = function(fn) if ready then return fn() end waiting = fn end
		local UI_OF = { [38] = 1432, [40] = 1436, [10] = 1431, [46] = 1428 }
		QD.UiMapOfArea = function(area) return UI_OF[area] end
		I.ZoneName = function(ui) return ({ [1432] = "Loch Modan", [1436] = "Westfall", [1431] = "Duskwood", [1428] = "Burning Steppes" })[ui] end
		local english = true
		I.NpcField = function(id, f)
			if f == "subName" then return english and TITLE[id] or (TITLE[id] and "Bibliothekar") end
			if f == "subNameEn" then return (not english) and TITLE[id] or nil end
		end
		I.ObjectName = function(id) return OBJECTS[id] and OBJECTS[id].name end
		I.SpotXY = function(ui, c) return 1, c[1] * 10, c[2] * 10 end
		local function Fresh()
			ns.providers.book = nil
			for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "book" then table.remove(ns.providerOrder, i) end end
			I.failed, OA.on = {}, nil
			OA.Forget(); B.ForgetQuestie()
			ns.background = 0
			I._.SetupOneForAll(); I._.SetupBooks()
			FlushAll()
			ns:AliasesChanged()
		end

		-- no OneForAll: QuestieDB's quests read, @book made of the books among them
		Fresh()
		local p = ns.providers.book
		check(p ~= nil and ns:ResolveProvider("books") == p and ns:ResolveProvider("library") == p, "without OneForAll: @book from QuestieDB")
		local rows = p and ns:GetEntries(p) or {}
		check(Names(rows) == "Folio of Stars | Tome of Winds | Atlas of Ash | Magma Notes",
			"the books among its quests, by the level they're for, then by name; nothing else: " .. Names(rows))
		local by = {}
		for _, e in ipairs(rows) do by[e.name] = e end
		local tome, atlas, magma, folio = by["Tome of Winds"], by["Atlas of Ash"], by["Magma Notes"], by["Folio of Stars"]
		check(tome and tome.zone == "Loch Modan" and tome.ui == 1432 and tome.px == 35.6 and tome.py == 48.9 and tome.itemID == 7001,
			"a book: where its object lies, in the object's own zone first: " .. tostring(tome and tome.zone) .. " " .. tostring(tome and tome.px))
		check(tome and tome.note == L["Also found at: %s"]:format("Westfall 52.7, 53.8") and tome.container == "Gnomish Tome",
			"a second zone's spot is said, and what it lies in: " .. tostring(tome and tome.note))
		check(atlas and atlas.note == nil and atlas.px == 16.7, "two spots a step apart in one zone: one place, the first: " .. tostring(atlas and atlas.note))
		check(tome and tome.state == "missing" and tostring(tome.detail):find(L["still to find"], 1, true)
			and tostring(tome.detail):find("Loch Modan", 1, true), "still to find, its zone: " .. tostring(tome and tome.detail))
		check(atlas and atlas.isDone == true and atlas.itemID == nil, "the game's own answers: a quest turned in (a book with no item known: no error)")
		check(magma and magma.state == "bag", "a book in your bags: " .. tostring(magma and magma.state))
		check(magma and magma.zone == "Burning Steppes", "the other books: the Special sort's, their item lying in the object they start at")
		check(folio and folio.ui == nil and folio.px == nil, "a book whose object has no spot: listed all the same")
		said = {}
		if folio then folio.activate(folio) end
		check(said[1] == L["QuestieDB has no spot for %s."]:format("Folio of Stars"), "Enter on it: said, in QuestieDB's name: " .. tostring(said[1]))
		local tip = { lines = {}, SetText = function(self, t) self.lines[#self.lines + 1] = t end, AddLine = function(self, t) self.lines[#self.lines + 1] = t end }
		if tome then tome.tooltip(tome, tip) end
		local all = table.concat(tip.lines, "\n")
		check(all:find(L["Library Books from QuestieDB"], 1, true) and not all:find("OneForAll", 1, true) and all:find("Gnomish Tome", 1, true)
			and all:find(L["%d of %d Library Books turned in"]:format(1, 4), 1, true), "its tooltip: whose list it is, what it lies in, how many are in: " .. all)

		-- searched and asked as OneForAll's are
		local res = UI:Search("@book is:todo")
		check(#res == 3, "@book is:todo: the three not turned in: " .. Names(res))
		res = UI:Search("@book duskwood")
		check(#res == 1 and res[1].name == "Atlas of Ash", "@book duskwood: by zone: " .. Names(res))
		check(B.Question("library books") ~= nil and B.Question("books i still need") ~= nil and B.Question("book") == nil, "the questions, as with OneForAll")
		local r, note = B.Answer(B.Question("books i still need"))
		check(#r == 3 and tostring(note):find(L["%d of %d turned in"]:format(1, 4), 1, true), "books i still need: " .. Names(r) .. " / " .. tostring(note))
		I.Here = function() return { cont = 1, x = 264, y = 245 } end
		r = B.Answer(B.Question("nearest library book"))
		check(r[1] and r[1].name == "Magma Notes" and r[#r].name == "Folio of Stars", "nearest library book: by how far, one with no spot last: " .. Names(r))
		-- (1.4.8) the rewards without OneForAll: the Librarians' reward quests (started by a Librarian, at no object), each
		-- with the items Questie says it gives, as items' own rows
		local QR = ns.QuestRewards
		local rewardsOf, indexWas = QR.RewardsOf, QR.Index
		local indexed = true
		QR.Index = function() return indexed and {} or nil end
		QR.RewardsOf = function(q) if indexed and q == 506 then return { { id = 7101, name = "Scholarly Pendant" }, { id = 7102, name = "Erudite's Amulet" } } end end
		r = B.Answer(B.Question("library book rewards"))
		check(#r == 3 and r[1].raw and r[1].name == "Friend of the Library: " .. L["level %d"]:format(20)
			and tostring(r[1].detail) == "Scholarly Pendant, Erudite's Amulet", "the rewards from QuestieDB: a Librarian's reward quest, what it gives: "
				.. Names(r) .. " / " .. tostring(r[1] and r[1].detail))
		check(r[2] and r[2].itemID == 7101 and r[2].link == "item:7101" and not r[2].raw and r[3] and r[3].itemID == 7102
			and tostring(r[2].detail):find("Friend of the Library", 1, true), "each item it gives as an item's row: " .. Names(r))
		DONE[506] = true
		r = B.Answer(B.Question("library book rewards"))
		check(r[1] and r[1].name:find(L["(claimed)"], 1, true), "a reward quest turned in: claimed: " .. tostring(r[1] and r[1].name))
		DONE[506] = nil
		indexed = false
		ns.Filters.loading = false
		r = B.Answer(B.Question("library book rewards"))
		check(#r == 1 and r[1].raw and ns.Filters.loading == true, "the items quests reward still being read: the tier alone, asked again once they're in: " .. Names(r))
		ns.Filters.loading = false
		indexed = true
		local q506 = QUESTS[506]
		QUESTS[506] = nil
		Fresh()
		r = B.Answer(B.Question("library book rewards"))
		check(r[1] and r[1].name == L["The Library Books' rewards aren't known without OneForAll"], "no reward quest in QuestieDB: said: " .. Names(r))
		QUESTS[506] = q506
		Fresh()
		QR.RewardsOf, QR.Index = rewardsOf, indexWas
		local lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(lines:find("  " .. L["Library Books:"] .. " " .. L["%d from QuestieDB (@book). OneForAll adds notes on each spot and the rewards."]:format(4), 1, true),
			".integrations says whose they are: " .. lines)

		-- a QuestieDB without base-data reads (older): the corrected sort only, the mage trainer's books not told apart
		local rawWas = db.RawQuestSingle
		db.RawQuestSingle = nil
		Fresh()
		local names0 = Names(ns:GetEntries(ns.providers.book))
		check(not names0:find("Magma Notes", 1, true) and names0:find("Tome of Winds", 1, true), "(without GetRaw: the corrected sort, as 1.4.11 read it: " .. names0 .. ")")
		db.RawQuestSingle = rawWas
		Fresh()

		-- a client in another language: the title QuestieDB translated, its untranslated one asked
		english = false
		Fresh()
		check(ns.providers.book and #ns:GetEntries(ns.providers.book) == 4, "another language (the title translated): the Librarians' books still found")
		english = true

		-- not on top of Questie's own indexing; not before its data can be read
		ns.providers.book = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "book" then table.remove(ns.providerOrder, i) end end
		B.ForgetQuestie(); OA.on = nil
		asked = 0
		ns.background = 1
		I._.SetupBooks()
		check(asked == 0 and not ns.providers.book, "while Questie's lists are indexed: not read yet")
		ns.background = 0
		FlushAll()
		check(asked == 1 and ns.providers.book ~= nil, "once that's done: read, @book there: " .. asked)
		ns.providers.book = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "book" then table.remove(ns.providerOrder, i) end end
		B.ForgetQuestie(); OA.on = nil
		ready, waiting, asked = false, nil, 0
		I._.SetupBooks(); FlushAll()
		check(asked == 0 and type(waiting) == "function" and not ns.providers.book, "QuestieDB not ready: waits for it")
		ready = true
		waiting(); FlushAll()
		check(asked == 1 and ns.providers.book ~= nil, "ready: read then")
		-- (1.4.15, the release review) QuestieDB's quests not there yet: asked again, not given up for the session; reaching
		-- for @book meanwhile isn't told to install anything
		ns.providers.book = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "book" then table.remove(ns.providerOrder, i) end end
		B.ForgetQuestie(); OA.on = nil
		local idsWas, none = db.QuestIds, true
		db.QuestIds = function() asked = asked + 1 if none then return {} end return idsWas() end
		asked = 0
		I._.SetupBooks()
		check(not ns.providers.book and B.Pending() and asked == 1, "no quests yet: waiting, asked again later")
		if I.ForgetHint then I.ForgetHint() end
		check(I.MissingFor("@book") == nil, "reaching for @book meanwhile: no install hint")
		none = false
		FlushAll()
		check(ns.providers.book ~= nil and not B.Pending() and asked >= 2, "the quests in: read then, @book there: " .. asked)
		db.QuestIds = idsWas

		-- OneForAll's list comes first, and QuestieDB isn't read for it
		_G.OneForAll = { BOOKS = { { name = "Its Own Tome", questId = 1, itemId = 2 } } }
		asked = 0
		Fresh()
		local d, source = B.Data()
		check(source == "OneForAll" and d and d[1].name == "Its Own Tome" and asked == 0, "with OneForAll: its books, QuestieDB's quests not read: " .. tostring(source) .. " / " .. asked)
		lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(not lines:find(L["Library Books:"], 1, true) and lines:find(L["%d Library Books (@book)"]:format(1), 1, true), ".integrations: on OneForAll's line then")
		_G.OneForAll = nil

		-- a QuestieDB with no such quest (another game version's): no empty @book; neither addon: none either
		QUESTS[501], QUESTS[502], QUESTS[503], QUESTS[508] = nil, nil, nil, nil
		Fresh()
		check(not ns.providers.book and B.Question("library books") == nil and B.Data() == nil, "no book among its quests: no @book, no question")
		lines = table.concat(ns.commands.integrations.run(""), "\n")
		check(not lines:find(L["Library Books:"], 1, true), "and .integrations says nothing of them")
		local miss = I.MissingFor and I.MissingFor("@book")
		check(miss and (miss.label or miss.name) == "OneForAll" and miss.also == "Questie", "reaching for @book then: OneForAll or Questie named")
		QD.Lib = function() return nil end
		asked = 0
		Fresh()
		check(not ns.providers.book and asked == 0, "no QuestieDB either: nothing read, no @book")
	end)
	_G.OneForAll = save.lib
	OA.Loaded = save.loaded
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	ns.Print, ns.background = save.print, save.bg
	QD.DB, QD.Ready, QD.Lib, QD.HasQuestie, QD.OnReady, QD.UiMapOfArea = save.db, save.ready, save.qlib, save.has, save.onReady, save.uiOf
	I.NpcField, I.ObjectName, I.ZoneName, I.SpotXY, I.Here = save.field, save.objName, save.zoneName, save.spot, save.here
	I.failed, OA.on = save.failed, save.on
	if C_QuestLog then C_QuestLog.IsQuestFlaggedCompleted = save.flagged end
	_G.GetItemCount = save.count
	if C_Item then C_Item.GetItemCount = save.citem end
	ns.db.easyMode = save.easy; UI:EasyChanged()
	OA.Forget(); B.ForgetQuestie()
	ns.QuestRewards.RewardsOf, ns.QuestRewards.Index = save.rewardsOf, save.index
	if I.ForgetHint then I.ForgetHint() end
	check(ok, "library books from QuestieDB: " .. tostring(err))
end

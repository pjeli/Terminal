-- .typing (Typing.lua, 0.47.4, an easter egg): a typing speed test; words per minute, accuracy, the best per length;
-- Enter afterwards tells the guild with a [Terminal] banner.
local T = ...
local ns, check = T.ns, T.check

io.write("[typing test]\n")
do
	local TY = ns.Typing
	check(TY and ns:FindCommand("typing") and ns:FindCommand("wpm"), ".typing (and .wpm) is there")
	if not TY then return end
	local save = { rand = TY.rand, clock = TY.clock, mode = ns.db.typingMode, best = ns.db.typingBest, chat = _G.C_ChatInfo,
		guild = _G.IsInGuild, print = ns.Print }
	local clock = 100
	TY.clock = function() return clock end
	local pick = { 1, 2, 3, 4, 5 } -- (the words, in order: the first ones on the list)
	local n = 0
	TY.rand = function(max) n = n + 1 return ((pick[(n - 1) % #pick + 1] - 1) % max) + 1 end
	ns.db.typingMode, ns.db.typingBest = 15, nil
	check(TY.Open() and TY.IsShown(), "it opens where the terminal was")
	local g = TY.game
	check(g.duration == 15 and #g.words >= TY.WORD_BATCH and g.words[1] == "the" and g.words[2] == "be" and not g.start,
		"15 s, the words ready, the clock not running yet")
	local function Type(s) for c in s:gmatch(".") do TY.Char(c) end end
	-- "the be of and a": four right, one wrong ("adn"), Backspace back into it and fixed
	Type("the be ")
	check(g.start == 100 and g.cur == 3, "the clock starts with the first letter; Space goes to the next word")
	Type("of adn ")
	check(g.typed[4] == "adn" and g.cur == 5, "a wrong word is kept as typed")
	TY.Back()
	check(g.cur == 4 and g.input == "adn", "Backspace on an empty word goes back into the wrong one before")
	TY.Back(); TY.Back()
	Type("nd a")
	check(g.input == "a" and g.cur == 5, "fixed, and on to the next")
	TY.Back(true)
	check(g.input == "", "Ctrl+Backspace clears the word")
	Type("a")
	-- a correct word isn't gone back into
	TY.Char(" ")
	TY.Back()
	check(g.cur == 6, "no going back into a word typed right")
	-- time's up: 15 s
	clock = 115
	TY.Tick()
	local r = g.result
	check(g.over and r, "time's up: the result")
	-- right words: the(3) be(2) of(2) and(3) a(1) = 11 letters + 5 spaces = 16 -> 16 / 5 / 0.25 = 12.8 -> 13 wpm
	check(r.wpm == 13 and r.correct == 11 and r.incorrect == 0, "13 wpm (right words' letters and spaces / 5 a minute): " .. r.wpm)
	check(r.acc < 100 and r.acc > 70, "accuracy counts the mistakes made, even fixed ones: " .. r.acc)
	check(ns.db.typingBest[15] and ns.db.typingBest[15].wpm == 13 and g.newBest, "the best for 15 s kept")
	-- Enter: the guild is told, once, with the banner (not in the first moment: a key still held)
	local sent = {}
	_G.C_ChatInfo = setmetatable({ SendChatMessage = function(text, chan) sent[#sent + 1] = { text, chan } end,
		InChatMessagingLockdown = function() return false end }, { __index = save.chat })
	_G.IsInGuild = function() return true end
	local printed
	ns.Print = function(_, s) printed = s end
	check(not TY.TellGuild() and #sent == 0, "Enter at once: nothing (a key still held from typing)")
	clock = clock + 1
	check(TY.TellGuild() and #sent == 1 and sent[1][2] == "GUILD" and sent[1][1]:find("^%[Terminal%] 13 wpm")
		and sent[1][1]:find("15 s typing test (a new best)", 1, true) and not sent[1][1]:find("CurseForge", 1, true) and not sent[1][1]:find("?", 1, true), "Enter: the guild told: " .. tostring(sent[1] and sent[1][1]))
	check(#sent[1][1] <= 255, "within a chat line")
	check(not TY.TellGuild() and #sent == 1 and printed:find("heard", 1, true), "only once")
	-- (0.50.7, review) the game's own chords (Ctrl+R: the frame rate) go on to the game, as .atop and the terminal let them
	do
		local gk = ns.UI.GameKey
		ns.UI.GameKey = function(k) return k == "R", "TOGGLEFPS" end
		TY.KeyDown(TY.frame, "R")
		check(TY.frame.propagate == true, "Ctrl+R (the game's): passed on")
		TY.KeyDown(TY.frame, "Q")
		check(TY.frame.propagate == false, "another key: the test's")
		ns.UI.GameKey = gk
	end
	-- Tab: another test; before the first letter Tab picks the length
	TY.KeyDown(TY.frame, "TAB")
	check(not g.over and g.cur == 1 and not g.start and ns.db.typingMode == 15, "Tab after a test: another (the same length)")
	TY.KeyDown(TY.frame, "TAB")
	check(ns.db.typingMode == 30 and g.duration == 30, "Tab before the first letter: 30 s")
	TY.KeyDown(TY.frame, "TAB"); TY.KeyDown(TY.frame, "TAB")
	check(ns.db.typingMode == 15, "and round: 60, then 15")
	-- not in a guild: said, nothing sent
	Type("the ")
	clock = clock + 20
	TY.Tick()
	clock = clock + 1
	_G.IsInGuild = function() return false end
	check(not TY.TellGuild() and #sent == 1 and printed:find("not in a guild", 1, true), "not in a guild: said")
	-- (review, 0.49.17) 0 wpm: nothing to tell, and the footer doesn't offer it
	_G.IsInGuild = function() return true end
	local wpm = g.result.wpm
	g.result.wpm = 0
	TY.Draw()
	check(not TY.CanTell(), "0 wpm: nothing to tell")
	g.result.wpm = wpm
	-- Enter (the key): told, and the test closes, so the chat shows it (.zen's interface back; the player's ask)
	_G.IsInGuild = function() return true end
	TY.KeyDown(TY.frame, "ENTER")
	check(#sent == 2 and not TY.IsShown(), "Enter on the result: the guild told, and the test closes")
	TY.Open()
	-- the drawing: three lines, the caret placed (no error with the mock's fonts)
	TY.KeyDown(TY.frame, "TAB")
	Type("th")
	local ok = pcall(TY.Draw)
	check(ok, "drawn while typing")
	-- (review, 0.53.6) letters of two bytes: an accented one as the words have it, another alphabet's a wrong key; never
	-- half a letter
	TY.Back(true)
	TY.Char("\195\169") -- (e acute)
	check(g.input == "e", "e acute typed as e: " .. g.input)
	TY.Char("\208\182") -- (a Cyrillic letter)
	check(g.input == "e?", "another alphabet's letter: one wrong key: " .. g.input)
	TY.Back()
	check(g.input == "e", "Backspace takes it whole")
	-- the clock alone drawn while it runs: the words aren't laid out again ten times a second
	local draws, draw = 0, TY.Draw
	TY.Draw = function(...) draws = draws + 1 return draw(...) end
	TY.Tick(); TY.Tick()
	TY.Draw = draw
	check(draws == 0, "a tick draws only the seconds left: " .. draws)
	-- a long book: only the start of it read for its words
	local long = ("word "):rep(TY.BOOK_WORDS * 4)
	check(#TY.LoreWords(long) == TY.BOOK_WORDS, "a long book's words: as many as are kept")
	-- Esc quits
	TY.KeyDown(TY.frame, "ESCAPE")
	check(not TY.IsShown(), "Esc quits")

	TY.rand, TY.clock, ns.db.typingMode, ns.db.typingBest = save.rand, save.clock, save.mode, save.best
	_G.C_ChatInfo, _G.IsInGuild, ns.Print = save.chat, save.guild, save.print
end

-- lore books (0.48.2, the player's ask): the pages of books read in the game are kept (Apps/Extras.lua), and the test's
-- words are runs from one of them, in no order; the result names the book
io.write("[typing test: lore books]\n")
do
	local TY, X = ns.Typing, ns.Extras
	local save = { rand = TY.rand, lore = ns.db.lore, item = _G.ItemTextGetItem, text = _G.ItemTextGetText,
		page = _G.ItemTextGetPage, creator = _G.ItemTextGetCreator, last = TY.lastBook }
	ns.db.lore = nil
	-- cleaning: the window's HTML, colour codes, links and the game's $-codes out
	check(X.CleanLore("<HTML><BODY><P>The |cffff0000Lich King|r rose in $B Northrend. &lt;Arthas&gt; |Hitem:1|h[Frostmourne]|h</P></BODY></HTML>")
		== "The Lich King rose in Northrend. <Arthas> [Frostmourne]", "cleaned: " .. tostring(X.CleanLore("<P>a $B b c d e f g h i j k l m</P>")))
	check(X.CleanLore("<P>Hi</P>") == nil, "too short: nothing")
	-- words to type: lowercase, inner apostrophes, accents dropped, anything else out
	local w = TY.LoreWords("Kel'Thuzad's \195\137lite -- 1234 caf\195\169 \208\191\209\128\208\184 well-known.")
	check(table.concat(w, " ") == "kel'thuzad's elite cafe well known", "words: " .. table.concat(w, " "))

	-- reading a book in the game: each page kept as you turn it; a player's letter isn't
	local BOOK = "The Founding of Quel'Thalas"
	local title, page, text, creator = BOOK, 1, nil, nil
	_G.ItemTextGetItem = function() return title end
	_G.ItemTextGetPage = function() return page end
	_G.ItemTextGetText = function() return text end
	_G.ItemTextGetCreator = function() return creator end
	local OnEvent = X.loreFrame.scripts.OnEvent
	local long = {}
	for i = 1, 40 do long[#long + 1] = "word" .. string.char(96 + (i % 26) + 1) end
	text = "<P>The high elves sailed east from Kalimdor and founded a kingdom of their own in the forests of the north. "
		.. table.concat(long, " ") .. "</P>"
	OnEvent(X.loreFrame, "ITEM_TEXT_BEGIN")
	OnEvent(X.loreFrame, "ITEM_TEXT_READY")
	page, text = 2, "<P>The trolls of Zul'Aman fought them for many years, until the humans of Arathor came to their aid.</P>"
	OnEvent(X.loreFrame, "ITEM_TEXT_READY")
	OnEvent(X.loreFrame, "ITEM_TEXT_CLOSED")
	local b = ns.db.lore and ns.db.lore["the founding of quel'thalas"]
	check(b and b.title == title and b.pages[1] and b.pages[2] and b.pages[2]:find("Zul'Aman", 1, true), "both pages kept")
	-- (review, 0.53.6) a page past those kept isn't kept: it wrote over the last one
	page, text = X.LORE_PAGES, "<P>The last page that is kept, of a very long book indeed, about the elves.</P>"
	OnEvent(X.loreFrame, "ITEM_TEXT_BEGIN")
	OnEvent(X.loreFrame, "ITEM_TEXT_READY")
	page, text = X.LORE_PAGES + 1, "<P>A page past those kept, which must not take the last one's place.</P>"
	OnEvent(X.loreFrame, "ITEM_TEXT_READY")
	check(b.pages[X.LORE_PAGES]:find("last page", 1, true) and not b.pages[X.LORE_PAGES + 1], "a page past those kept: the last kept stays")
	b.pages[X.LORE_PAGES] = nil
	page = 1
	title, creator, page, text = "A letter", "Bob", 1, "<P>Hey, could you send me twenty linen cloth for my tailoring please?</P>"
	OnEvent(X.loreFrame, "ITEM_TEXT_BEGIN")
	OnEvent(X.loreFrame, "ITEM_TEXT_READY")
	check(not ns.db.lore["a letter"], "a letter a player wrote isn't kept")
	creator = nil

	-- the test: runs of the book's words, and the book named at the end
	local n = 0
	TY.rand = function(max) n = n + 1 return ((n * 7) % max) + 1 end
	TY.lastBook = nil
	check(TY.Open(), "opens")
	local g = TY.game
	local words = TY.Books()[1].words
	local in_book = {}
	for _, x in ipairs(words) do in_book[x] = true end
	local all = true
	for _, x in ipairs(g.words) do if not in_book[x] then all = false end end
	check(g.book and g.book.title == BOOK and all and #g.words >= TY.WORD_BATCH, "the words are the book's")
	-- (a run is consecutive in the book; where one run ends and the next starts, the two words aren't neighbours there)
	local follows = {}
	for k = 1, #words - 1 do follows[words[k] .. " " .. words[k + 1]] = true end
	local breaks = 0
	for i = 2, #g.words do if not follows[g.words[i - 1] .. " " .. g.words[i]] then breaks = breaks + 1 end end
	check(breaks >= 8, "in runs from all over the book, not read in order: " .. breaks)
	TY.Finish()
	TY.Draw()
	local said = TY.loreText:GetText()
	check(said and said:find(ns.L["Words from the book: %s"]:format(BOOK), 1, true), "the result names the book: " .. tostring(said))
	check(TY.BookLines()[2]:find(BOOK, 1, true) and ns:FindCommand("typing").run("books")[1]:find("(1)", 1, true), ".typing books lists it")
	TY.Close()

	-- no books: Terminal's own words, and the result says where book words come from
	ns.db.lore = {}
	TY.Reset()
	check(not TY.game.book and TY.game.words[1] ~= nil, "no books: Terminal's words")
	check(TY.BookLines()[1]:find("No books read yet", 1, true), ".typing books: none yet")

	TY.rand, ns.db.lore, TY.lastBook = save.rand, save.lore, save.last
	_G.ItemTextGetItem, _G.ItemTextGetText, _G.ItemTextGetPage, _G.ItemTextGetCreator = save.item, save.text, save.page, save.creator
end

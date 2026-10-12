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
		and sent[1][1]:find("15 s typing test (a new best)", 1, true), "Enter: the guild told: " .. tostring(sent[1] and sent[1][1]))
	check(#sent[1][1] <= 255, "within a chat line")
	check(not TY.TellGuild() and #sent == 1 and printed:find("heard", 1, true), "only once")
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
	-- the drawing: three lines, the caret placed (no error with the mock's fonts)
	TY.KeyDown(TY.frame, "TAB")
	Type("th")
	local ok = pcall(TY.Draw)
	check(ok, "drawn while typing")
	-- Esc quits
	TY.KeyDown(TY.frame, "ESCAPE")
	check(not TY.IsShown(), "Esc quits")

	TY.rand, TY.clock, ns.db.typingMode, ns.db.typingBest = save.rand, save.clock, save.mode, save.best
	_G.C_ChatInfo, _G.IsInGuild, ns.Print = save.chat, save.guild, save.print
end

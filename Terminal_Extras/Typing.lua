-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- .typing (also .wpm, .typetest): a typing speed test, an easter egg (not in the changelog, as .tetris and .lootrun),
-- in a window where the terminal sits. Words come in lines; the clock starts with the first letter; Space goes to the
-- next word; Backspace corrects (back into the word before too, when it was typed wrong); Ctrl+Backspace clears the
-- word. When the time is up: words per minute (correct words' letters and spaces / 5 a minute), accuracy (the keys
-- typed right), raw speed (every key), and the best per length kept. Enter then tells your guild, with a [Terminal]
-- banner (from Terminal's code inside your key press: guild chat isn't held back for addons, as Share's party and guild
-- lines aren't), and closes the test, so the chat shows it (the interface back: .zen ends; the player's ask). Tab: another test (before the first letter: 15, 30 or 60 seconds); Esc or ` quits.
--
-- Every key is the test's while it shows (letters must not walk you around), except the F-keys and Print Screen; it
-- doesn't open in combat and closes when combat starts. The words are Terminal's own list: everyday English and a few
-- of Azeroth's; or, once you've read books in the game (a shelf's book, a plaque, a note you find: Apps/Extras.lua keeps
-- their pages in db.lore), runs of a few words from one of them, in no order, so typing is reading lore too: which book
-- it was is said with the result (0.48.2, the player's ask). Only letters (accents dropped) and apostrophes are typed: a
-- book in Russian or Chinese leaves too few words, and Terminal's list is used.

local TY = {}
ns.Typing = TY

local Theme = ns.Theme
local Panel = ns.Panel

TY.MODES = { 15, 30, 60 } -- (seconds)
TY.LINES = 3 -- (lines of words shown)
TY.ENTER_WAIT = 0.6 -- (s after the result shows before Enter tells the guild: a key still held from typing)
TY.WORD_BATCH = 60 -- (words made at a time; more come as you type)
local W, H = 560, 210
local BOX_W, LINE_H = W - 40, 24

TY.WORDS = {}
for w in ([[the be of and a to in he have it that for they with as not on she at by this we you do but from or which
	one would all will there say who make when can more if no man out other so what time up go about than into could
	state only new year some take come these know see use get like then first any work now may such give over think most
	even find day also after way many must look before great back through long where much should well people down own
	just because good each those feel seem how high too place little world very still nation hand old life tell write
	become here show house both between need mean call develop under last right move thing general school never same
	another begin while number part turn real leave might want point form off child few small since against ask late
	home interest large person end open public follow during present without again hold around possible head consider
	word problem however lead system set order eye plan run keep face fact group play stand increase early course change
	help line city put close case force meet once water upon war build hear light unite live every country bring center
	let side try provide continue name certain power pay result question study woman member until far night always
	service away report something company week church toward start social room figure nature though young less enough
	almost read include president nothing yet better big boy cost business value second why clear expect family complete
	act sense mind experience art next near direct car law industry important girl god several matter usual rather
	quest raid tank healer mana rage loot gold dungeon dragon orc elf dwarf gnome troll horde alliance murloc gryphon
	hearthstone innkeeper vendor guild party spell rune totem blade shield helm cloak potion elixir flask herb ore anvil
	forge trainer mount wyvern kodo raptor wolf boar bear spider ogre kobold gnoll centaur harpy naga temple crypt tavern
	tabard silver copper thorium mithril linen wool silk mageweave runecloth bandage fishing cooking mining skinning]]
	):gmatch("%a+") do TY.WORDS[#TY.WORDS + 1] = w end

TY.PHRASE_MIN, TY.PHRASE_MAX = 3, 8 -- (words in a run taken from a book)
TY.BOOK_MIN = 30 -- (words a book needs to be used)
TY.BOOK_WORDS = 1500 -- (words of a book used at most)

TY.rand = function(n) return math.random(n) end -- (tests replace it)
TY.clock = function() return GetTime() end -- (tests replace it)

local frame, title, timeText, lines, caret, measure, result, resultSub, loreText, footer
local game = {}
TY.game = game

----------------------------------------------------------------------
-- The test
----------------------------------------------------------------------

-- accented Latin letters as plain ones (e acute -> e, sharp s -> ss): U+00C0..U+00FF, two bytes, the second 0x80..0xBF
local FOLD = {}
do
	local plain = { "a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i", "d", "n", "o", "o", "o",
		"o", "o", "", "o", "u", "u", "u", "u", "y", "th", "ss" }
	for i, v in ipairs(plain) do
		FOLD[string.char(195, 127 + i)] = v -- (capitals, and sharp s)
		FOLD[string.char(195, 159 + i)] = v -- (small letters)
	end
	FOLD[string.char(195, 191)] = "y" -- (y with diaeresis)
end

--- A book's text as words to type: lowercase letters and inner apostrophes ("kel'thuzad"), accents dropped; a word
--- with anything else in it (digits, another alphabet) is left out.
function TY.LoreWords(text)
	local out = {}
	if type(text) ~= "string" then return out end
	-- (only as much as the words kept can come from: a long book's every page was folded and lowercased for its first
	-- BOOK_WORDS words; review, 0.53.6)
	text = text:sub(1, TY.BOOK_WORDS * 12)
	local s = text:gsub("\195[\128-\191]", function(c) return FOLD[c] or c end):gsub("\197[\146\147]", "oe")
	s = s:gsub("[%-/]", " "):lower()
	for tok in s:gmatch("%S+") do
		tok = tok:gsub("^[^a-z]+", ""):gsub("[^a-z]+$", "")
		if tok ~= "" and tok:find("^[a-z']+$") then
			out[#out + 1] = tok
			if #out >= TY.BOOK_WORDS then break end
		end
	end
	return out
end

local bookWords = {} -- title -> { t = when read, words } (worked out once per book as it was read)

--- A kept book's words (worked out once, again when it was read since), or nil for one not kept as a book.
local function WordsOf(b)
	if not (type(b) == "table" and type(b.title) == "string" and type(b.pages) == "table") then return nil end
	local c = bookWords[b.title]
	if not c or c.t ~= b.t then
		local pages, n = {}, 0
		for i = 1, ns.Extras.LORE_PAGES do
			if type(b.pages[i]) == "string" then
				pages[#pages + 1] = b.pages[i]
				n = n + #b.pages[i]
				if n >= TY.BOOK_WORDS * 12 then break end -- (LoreWords reads no more than that)
			end
		end
		c = { t = b.t, words = TY.LoreWords(table.concat(pages, " ")) }
		bookWords[b.title] = c
	end
	return c.words
end

--- The books read that have enough words to type: { { title, words } }, by title.
function TY.Books()
	local out = {}
	local lore = ns.db and type(ns.db.lore) == "table" and ns.db.lore or {}
	for _, b in pairs(lore) do
		local words = WordsOf(b)
		if words and #words >= TY.BOOK_MIN then out[#out + 1] = { title = b.title, words = words } end
	end
	table.sort(out, function(a, b) return a.title < b.title end)
	return out
end

--- A book for this test (another than the last when there are two or more), or nil when none has enough words. Only
--- the book picked is read for its words (review, 0.57.7: every book read was, the first test of a session, a freeze
--- with hundreds of them): picked among those with letters enough for them, until one has.
function TY.PickBook()
	local lore = ns.db and type(ns.db.lore) == "table" and ns.db.lore or {}
	local list = {}
	for _, b in pairs(lore) do
		if type(b) == "table" and type(b.title) == "string" and type(b.pages) == "table" then
			local n = 0
			for i = 1, ns.Extras.LORE_PAGES do if type(b.pages[i]) == "string" then n = n + #b.pages[i] end end
			if n >= TY.BOOK_MIN * 2 then list[#list + 1] = b end -- (fewer letters than that: not words enough)
		end
	end
	table.sort(list, function(a, b) return a.title < b.title end)
	while #list > 0 do
		local i = TY.rand(#list)
		if #list > 1 and list[i].title == TY.lastBook then i = i % #list + 1 end
		local b = list[i]
		local words = WordsOf(b)
		if words and #words >= TY.BOOK_MIN then
			TY.lastBook = b.title
			return { title = b.title, words = words }
		end
		table.remove(list, i)
	end
	return nil
end

local function MoreWords(n)
	local book = game.book
	if book then
		-- runs of a few words from anywhere in the book, one after another (never the same word twice running)
		local words, added, tries = book.words, 0, 0
		while added < n and tries < n * 4 do -- (a book of one word over and over adds nothing: not for ever)
			tries = tries + 1
			local len = math.min(#words, TY.PHRASE_MIN + TY.rand(TY.PHRASE_MAX - TY.PHRASE_MIN + 1) - 1)
			local from = TY.rand(#words - len + 1)
			for k = from, from + len - 1 do
				if words[k] ~= game.words[#game.words] then
					game.words[#game.words + 1] = words[k]
					added = added + 1
				end
			end
		end
		if added >= n then return end
		n = n - added
	end
	for _ = 1, n do
		local w
		repeat w = TY.WORDS[TY.rand(#TY.WORDS)] until w ~= game.words[#game.words] -- (never the same word twice running)
		game.words[#game.words + 1] = w
	end
end

local function Mode()
	local m = ns.db and tonumber(ns.db.typingMode)
	for _, s in ipairs(TY.MODES) do if s == m then return m end end
	return 30
end

--- A new test: new words, the clock stopped until the first letter.
function TY.Reset()
	game.words, game.typed, game.widths, game.space = {}, {}, {}, nil
	game.cur, game.input = 1, ""
	game.start, game.over, game.sent, game.newBest = nil, false, false, false
	game.keys, game.right = 0, 0
	game.duration = Mode()
	game.result, game.overAt = nil, nil
	game.book = TY.PickBook() -- (a book read in the game: its words; said with the result)
	MoreWords(TY.WORD_BATCH)
	if frame then frame:SetScript("OnUpdate", nil) end
end

local function OnUpdate(_, elapsed)
	game.tick = (game.tick or 0) + (elapsed or 0)
	if game.tick < 0.1 then return end
	game.tick = 0
	TY.Tick()
end

--- A character typed: a letter goes into the word (the clock starts with the first), a space to the next word.
function TY.Char(c)
	if game.over or type(c) ~= "string" or c == "" or c == "`" then return end
	if c == " " then
		if game.input == "" then return end -- (a space before anything typed: nothing)
		local word = game.words[game.cur]
		game.keys = game.keys + 1
		if game.input == word then game.right = game.right + 1 end
		game.typed[game.cur] = game.input
		game.cur, game.input = game.cur + 1, ""
		if game.cur + 20 > #game.words then MoreWords(TY.WORD_BATCH) end
		return
	end
	if not game.start then
		game.start = TY.clock()
		if frame then frame:SetScript("OnUpdate", OnUpdate) end
	end
	-- a letter with an accent as the words have it (é -> e, ß -> ss); any other letter not in the words (another
	-- alphabet) a wrong key, shown as "?": the typed text was byte by byte, a letter of two bytes counted twice and
	-- Backspace left half of one (review, 0.53.6)
	if #c > 1 then c = FOLD[c] or "?" end
	for k = 1, #c do
		local ch = c:sub(k, k)
		game.input = game.input .. ch
		game.keys = game.keys + 1
		local want = game.words[game.cur]
		if want:sub(#game.input, #game.input) == ch and #game.input <= #want then game.right = game.right + 1 end
	end
end

--- Backspace: a letter off the word; on an empty word, back into the one before when it was typed wrong. With Ctrl:
--- the whole word.
function TY.Back(whole)
	if game.over then return end
	if game.input == "" then
		local prev = game.cur - 1
		if prev >= 1 and game.typed[prev] ~= game.words[prev] then
			game.cur, game.input = prev, game.typed[prev] or ""
			game.typed[prev] = nil
			if whole then game.input = "" end
		end
		return
	end
	game.input = whole and "" or game.input:sub(1, -2)
end

--- The result: { wpm, raw, acc, correct, incorrect, extra, missed, seconds } of what's been typed.
function TY.Score(seconds)
	seconds = seconds or game.duration
	local good, all = 0, 0
	local correct, incorrect, extra, missed = 0, 0, 0, 0
	local function Count(word, typed, done)
		for j = 1, math.max(#word, #typed) do
			local w, t = word:sub(j, j), typed:sub(j, j)
			if t == "" then if done then missed = missed + 1 end
			elseif w == "" then extra = extra + 1
			elseif w == t then correct = correct + 1
			else incorrect = incorrect + 1 end
		end
	end
	for i = 1, game.cur - 1 do
		local word, typed = game.words[i], game.typed[i] or ""
		Count(word, typed, true)
		all = all + #typed + 1
		if typed == word then good = good + #word + 1 end
	end
	local word, typed = game.words[game.cur] or "", game.input
	Count(word, typed, false)
	all = all + #typed
	if typed ~= "" and word:sub(1, #typed) == typed then good = good + #typed end -- (the last word, right so far)
	local minutes = math.max(seconds, 1) / 60
	return {
		wpm = math.floor(good / 5 / minutes + 0.5), raw = math.floor(all / 5 / minutes + 0.5),
		acc = game.keys > 0 and math.floor(game.right / game.keys * 100 + 0.5) or 0,
		correct = correct, incorrect = incorrect, extra = extra, missed = missed, seconds = seconds,
	}
end

--- Time's up: the result, and the best for this length kept.
function TY.Finish()
	if game.over then return end
	game.over, game.overAt = true, TY.clock()
	if frame then frame:SetScript("OnUpdate", nil) end
	local r = TY.Score(game.duration)
	game.result = r
	if ns.db then
		ns.db.typingBest = type(ns.db.typingBest) == "table" and ns.db.typingBest or {}
		local best = ns.db.typingBest[game.duration]
		if r.wpm > 0 and (type(best) ~= "table" or r.wpm > (best.wpm or 0)) then
			ns.db.typingBest[game.duration] = { wpm = r.wpm, acc = r.acc, t = (_G.time and _G.time()) or 0 }
			game.newBest = true
		end
	end
end

--- Ten times a second while the clock runs: only the seconds left drawn, when they change (the whole test was laid out
--- and painted again each time; review, 0.53.6); everything at the end.
local shownLeft
function TY.Tick()
	if not game.start or game.over then return end
	local left = game.duration - (TY.clock() - game.start)
	if left <= 0 then TY.Finish() TY.Draw() return end
	local secs = math.ceil(left)
	if secs ~= shownLeft and timeText then
		shownLeft = secs
		timeText:SetText("|cff" .. Theme.Get().accent .. secs .. "|r")
	end
end

--- What the guild is told: "[Terminal] 72 wpm, 96% accuracy on a 30 s typing test." (the [Terminal]
--- banner is the memo: no CurseForge line, 0.49.5, nor a question, 0.49.6: the player's ask)
function TY.Brag(r)
	r = r or game.result
	if not r then return nil end
	return L["[Terminal] %d wpm, %d%% accuracy on a %d s typing test%s."]
		:format(r.wpm, r.acc, r.seconds, game.newBest and (" " .. L["(a new best)"]) or "")
end

--- Is there a result to tell, and is Enter past the wait (not a key still held from typing)?
function TY.CanTell()
	if not game.over or not game.result or (game.result.wpm or 0) <= 0 then return false end -- (0 wpm: nothing to tell)
	return not (game.overAt and TY.clock() - game.overAt < TY.ENTER_WAIT)
end

--- Enter on the result: the guild is told, once (from Terminal's code, inside the key press); KeyDown then closes.
function TY.TellGuild()
	if not TY.CanTell() then return false end
	return ns.Extras.TellGuildOnce(game, TY.Brag()) -- (Apps/Extras.lua: the games' too)
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Hex(c) return "|cff" .. c end

local function Width(s)
	measure:SetText(s ~= "" and s or " ")
	local w = measure:GetStringWidth() or 0
	return s ~= "" and w or 0
end

-- what a word shows: the word's own letters (wrong ones red), letters typed past its end after it
local function Shown(word, typed)
	if #typed <= #word then return word end
	return word .. typed:sub(#word + 1)
end

-- each word's width as it shows, kept while what's typed of it stays the same (a redraw measures only what changed)
local function WordWidth(i, typed)
	local c = game.widths[i]
	if c and c[1] == typed then return c[2] end
	local w = Width(Shown(game.words[i], typed))
	game.widths[i] = { typed, w }
	return w
end

-- the words in lines that fit the box: { { first, last }, ... } up to a few lines past the current word
local function Layout()
	local out, line, x = {}, nil, 0
	local space = game.space or (Width("a a") - Width("aa"))
	game.space = space
	for i = 1, #game.words do
		local typed = (i < game.cur and game.typed[i]) or (i == game.cur and game.input) or ""
		local w = WordWidth(i, typed)
		if line and x + space + w > BOX_W then out[#out + 1] = line; line = nil end
		if not line then line, x = { i, i }, w else line[2], x = i, x + space + w end
		if #out > 0 and out[#out][1] > game.cur and #out >= TY.LINES + 2 then break end
	end
	if line then out[#out + 1] = line end
	return out
end

local function Paint(i, t)
	local word = game.words[i]
	local typed = (i < game.cur and game.typed[i]) or (i == game.cur and game.input) or ""
	local text, dim, bad, extra = Hex(t.text), Hex(t.dim), "|cffff5050", "|cff9a2a2a"
	local s = {}
	for j = 1, math.max(#word, #typed) do
		local w, c = word:sub(j, j), typed:sub(j, j)
		if c == "" then s[#s + 1] = ((i < game.cur) and bad or dim) .. w .. "|r" -- (missed: red; not yet typed: dim)
		elseif w == "" then s[#s + 1] = extra .. c .. "|r"
		elseif w == c then s[#s + 1] = text .. w .. "|r"
		else s[#s + 1] = bad .. w .. "|r" end
	end
	return table.concat(s)
end

function TY.Draw()
	if not frame then return end
	local t = Theme.Get()
	local laid = Layout()
	local curLine = 1
	for k, l in ipairs(laid) do if game.cur >= l[1] and game.cur <= l[2] then curLine = k end end
	local top = math.max(1, curLine - 1) -- (the line you're on is the second once the first is done)
	for k = 1, TY.LINES do
		local l = laid[top + k - 1]
		local fs = lines[k]
		if l and not game.over then
			local parts = {}
			for i = l[1], l[2] do parts[#parts + 1] = Paint(i, t) end
			fs:SetText(table.concat(parts, " "))
			fs:Show()
		else
			fs:Hide()
		end
	end
	-- the caret: after what's typed of the current word, on its line
	local l = laid[curLine]
	if l and not game.over then
		local before = {}
		for i = l[1], game.cur - 1 do before[#before + 1] = Shown(game.words[i], game.typed[i] or "") end
		local typedShown = Shown(game.words[game.cur], game.input):sub(1, math.max(#game.input, 0))
		local prefix = table.concat(before, " ") .. (#before > 0 and " " or "") .. typedShown
		caret:ClearAllPoints()
		caret:SetPoint("TOPLEFT", lines[curLine - top + 1], "TOPLEFT", Width(prefix), 1)
		caret:Show()
	else
		caret:Hide()
	end
	local best = ns.db and type(ns.db.typingBest) == "table" and ns.db.typingBest[game.duration]
	title:SetText(("%s%s|r   %s"):format(Hex(t.accent), L["typing"], L["%d s"]:format(game.duration))
		.. (type(best) == "table" and ("   " .. L["best %d wpm"]:format(best.wpm or 0)) or ""))
	if game.over then
		timeText:SetText("")
		local r = game.result
		result:SetText(("%s%s|r"):format(Hex(t.accent), L["%d wpm"]:format(r.wpm)) .. (game.newBest and ("   " .. L["new best!"]) or ""))
		resultSub:SetText(L["accuracy %d%%   raw %d   letters %d / %d / %d / %d (right, wrong, extra, missed)"]
			:format(r.acc, r.raw, r.correct, r.incorrect, r.extra, r.missed))
		-- the book the words came from, now that the test is over (none read yet: where they come from)
		local any = false
		for _ in pairs(ns.db and type(ns.db.lore) == "table" and ns.db.lore or {}) do any = true break end
		loreText:SetText(game.book and L["Words from the book: %s"]:format((game.book.title:gsub("|", "||")))
			or (not any and L["Read a book in the game (on a shelf, a plaque, a note you find) and its words turn up here"]) or "")
		result:Show(); resultSub:Show(); loreText:Show()
		footer:SetText(ns.Game.OverKeys(r.wpm, game.sent)) -- (the games' own: 0 wpm offers no telling; review, 0.49.17)
	else
		local left = game.start and math.max(0, game.duration - (TY.clock() - game.start)) or game.duration
		shownLeft = math.ceil(left)
		timeText:SetText(Hex(t.accent) .. shownLeft .. "|r")
		result:Hide(); resultSub:Hide(); loreText:Hide()
		footer:SetText((game.start and (L["Space next word"] .. "  ·  " .. L["Tab again"])
			or (L["Start typing"] .. "  ·  " .. L["Tab 15 / 30 / 60 s"])) .. "  ·  " .. Panel.QUIT)
	end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local Text = Panel.Text

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalTyping", TY)
	frame:SetSize(W, H)
	frame:SetScript("OnKeyDown", function(self, key) TY.KeyDown(self, key) end)
	frame:SetScript("OnChar", function(_, c) TY.Char(c); TY.Draw() end)
	title, timeText = Panel.Header(frame)
	lines = {}
	for k = 1, TY.LINES do
		local fs = Text(frame, 18)
		fs:SetPoint("TOPLEFT", 20, -44 - (k - 1) * LINE_H * 1.4)
		fs:SetWidth(BOX_W + 40)
		lines[k] = fs
	end
	measure = Text(frame, 18)
	measure:SetPoint("TOPLEFT", 0, 0)
	measure:SetAlpha(0)
	caret = frame:CreateTexture(nil, "OVERLAY")
	caret:SetSize(2, 20)
	result = Text(frame, 28, "CENTER")
	result:SetPoint("TOP", 0, -56)
	resultSub = Text(frame, 12, "CENTER")
	resultSub:SetPoint("TOP", result, "BOTTOM", 0, -12)
	loreText = Text(frame, 12, "CENTER")
	loreText:SetPoint("TOP", resultSub, "BOTTOM", 0, -12)
	loreText:SetWidth(BOX_W)
	footer = Panel.Footer(frame, 9, "")
	TY.frame, TY.loreText = frame, loreText -- (tests)
end

local function Style()
	local t = Panel.Layout(frame, W, H)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	local ar, ag, ab = Theme.RGB(t.accent)
	title:SetTextColor(tr, tg, tb)
	timeText:SetTextColor(tr, tg, tb)
	result:SetTextColor(tr, tg, tb)
	resultSub:SetTextColor(dr, dg, db)
	loreText:SetTextColor(ar, ag, ab)
	footer:SetTextColor(dr, dg, db)
	caret:SetColorTexture(ar, ag, ab, 1)
end

-- keys the game keeps even here (a screenshot of your score, the F-keys)
-- (and the game's own chords, Ctrl+R, Ctrl+S, Ctrl+M..., as .atop and the terminal pass them: UI.GameKey. 0.50.7,
-- review: swallowed here)
local function GameKey(key)
	if key == "PRINTSCREEN" or (type(key) == "string" and key:find("^F%d+$") ~= nil) then return true end
	local UI = ns.UI
	return UI and UI.GameKey and UI.GameKey(key) and true or false
end

--- Every key is the test's (letters come through OnChar), but the F-keys and Print Screen.
function TY.KeyDown(self, key)
	local mine = not GameKey(key)
	if key == "ESCAPE" or key == "`" then
		TY.Close()
	elseif key == "TAB" then
		if not game.start and not game.over and ns.db then -- (before the first letter: the next length)
			local m, nextOne = Mode(), TY.MODES[1]
			for i, s in ipairs(TY.MODES) do if s == m then nextOne = TY.MODES[i % #TY.MODES + 1] end end
			ns.db.typingMode = nextOne
		end
		TY.Reset()
		TY.Draw()
	elseif key == "BACKSPACE" then
		TY.Back(IsControlKeyDown and IsControlKeyDown() or false)
		TY.Draw()
	elseif key == "ENTER" or key == "NUMPADENTER" then
		if TY.CanTell() then TY.TellGuild(); TY.Close() end -- (closed: the chat shows it, .zen's faded interface back)
	end
	Panel.Propagate(self, mine)
end

function TY.IsShown() return Panel.Shown(frame) end

function TY.Open() return ns.Game.Open(TY, L["The typing test"], Build, Style) end

function TY.Close(why)
	if frame then frame:SetScript("OnUpdate", nil) end
	Panel.Close(frame, why, L["The typing test"])
end

--- .typing books: the books read so far whose words the test can use.
function TY.BookLines()
	local books = TY.Books()
	if #books == 0 then return { L["No books read yet: read one in the game (on a shelf, a plaque, a note you find) and the typing test uses its words."] } end
	local out = { L["Books the typing test can use (%d):"]:format(#books) }
	for i, b in ipairs(books) do
		if i > 25 then out[#out + 1] = "  " .. L["+%d more"]:format(#books - 25) break end
		out[#out + 1] = "  " .. b.title:gsub("|", "||") .. "  |cff9d9d9d" .. L["%d words"]:format(#b.words) .. "|r"
	end
	return out
end

ns.Game.Command("typing", function(args)
	local a = strtrim(args or ""):lower()
	if a == "books" or a == "book" or a == "lore" then return TY.BookLines() end
	TY.Open()
end)

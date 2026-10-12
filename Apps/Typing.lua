local ns = select(2, ...)

-- .typing (also .wpm, .typetest): a typing speed test, an easter egg (not in the changelog, as .tetris and .lootrun),
-- in a window where the terminal sits. Words come in lines; the clock starts with the first letter; Space goes to the
-- next word; Backspace corrects (back into the word before too, when it was typed wrong); Ctrl+Backspace clears the
-- word. When the time is up: words per minute (correct words' letters and spaces / 5 a minute), accuracy (the keys
-- typed right), raw speed (every key), and the best per length kept. Enter then tells your guild, with a [Terminal]
-- banner (from Terminal's code inside your key press: guild chat isn't held back for addons, as Share's party and guild
-- lines aren't). Tab: another test (before the first letter: 15, 30 or 60 seconds); Esc or ` quits.
--
-- Every key is the test's while it shows (letters must not walk you around), except the F-keys and Print Screen; it
-- doesn't open in combat and closes when combat starts. The words are Terminal's own list: everyday English and a few
-- of Azeroth's.

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

TY.rand = function(n) return math.random(n) end -- (tests replace it)
TY.clock = function() return GetTime() end -- (tests replace it)

local frame, title, timeText, lines, caret, measure, result, resultSub, footer
local game = {}
TY.game = game

----------------------------------------------------------------------
-- The test
----------------------------------------------------------------------

local function MoreWords(n)
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
TY.Mode = Mode

--- A new test: new words, the clock stopped until the first letter.
function TY.Reset()
	game.words, game.typed, game.widths, game.space = {}, {}, {}, nil
	game.cur, game.input = 1, ""
	game.start, game.over, game.sent, game.newBest = nil, false, false, false
	game.keys, game.right = 0, 0
	game.duration = Mode()
	game.result, game.overAt = nil, nil
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
	game.input = game.input .. c
	game.keys = game.keys + 1
	local want = game.words[game.cur]
	if want:sub(#game.input, #game.input) == c and #game.input <= #want then game.right = game.right + 1 end
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

function TY.Tick()
	if not game.start or game.over then return end
	if TY.clock() - game.start >= game.duration then TY.Finish() end
	TY.Draw()
end

--- What the guild is told: "[Terminal] 72 wpm, 96% accuracy on a 30 s typing test. Think you're faster? Terminal is on
--- CurseForge."
function TY.Brag(r)
	r = r or game.result
	if not r then return nil end
	return ("[Terminal] %d wpm, %d%% accuracy on a %d s typing test%s. Think you're faster? Terminal is on CurseForge.")
		:format(r.wpm, r.acc, r.seconds, game.newBest and " (a new best)" or "")
end

--- Enter on the result: the guild is told, once (from Terminal's code, inside the key press).
function TY.TellGuild()
	if not game.over or not game.result then return false end
	if game.overAt and TY.clock() - game.overAt < TY.ENTER_WAIT then return false end -- (a key still held from typing)
	if game.sent then ns:Print("Your guild has heard this one.") return false end
	if _G.IsInGuild and not _G.IsInGuild() then ns:Print("You're not in a guild: nobody to tell.") return false end
	local lock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	if lock and lock() then ns:Print("Chat is held back right now: tell your guild later.") return false end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
	if not send then return false end
	local ok = pcall(send, TY.Brag(), "GUILD")
	game.sent = ok
	ns:Trace("typing: told the guild: " .. tostring(ok))
	return ok
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
	title:SetText(("%styping|r   %d s"):format(Hex(t.accent), game.duration)
		.. (type(best) == "table" and ("   best %d wpm"):format(best.wpm or 0) or ""))
	if game.over then
		timeText:SetText("")
		local r = game.result
		result:SetText(("%s%d wpm|r"):format(Hex(t.accent), r.wpm) .. (game.newBest and "   new best!" or ""))
		resultSub:SetText(("accuracy %d%%   raw %d   letters %d / %d / %d / %d (right, wrong, extra, missed)")
			:format(r.acc, r.raw, r.correct, r.incorrect, r.extra, r.missed))
		result:Show(); resultSub:Show()
		footer:SetText(game.sent and "Your guild heard it  ·  Tab: again  ·  Esc quits"
			or "Enter: tell your guild  ·  Tab: again  ·  Esc quits")
	else
		local left = game.start and math.max(0, game.duration - (TY.clock() - game.start)) or game.duration
		timeText:SetText(Hex(t.accent) .. math.ceil(left) .. "|r")
		result:Hide(); resultSub:Hide()
		footer:SetText(game.start and "Space: next word  ·  Tab: start again  ·  Esc quits"
			or "Start typing  ·  Tab: 15 / 30 / 60 s  ·  Esc quits")
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
	footer = Panel.Footer(frame, 9, "")
	TY.frame = frame
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
	footer:SetTextColor(dr, dg, db)
	caret:SetColorTexture(ar, ag, ab, 1)
end

-- keys the game keeps even here (a screenshot of your score, the F-keys)
local function GameKey(key) return key == "PRINTSCREEN" or (type(key) == "string" and key:find("^F%d+$") ~= nil) end

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
		if game.over then TY.TellGuild(); TY.Draw() end
	end
	Panel.Propagate(self, mine)
end

function TY.IsShown() return Panel.Shown(frame) end

function TY.Open()
	if not Panel.CanOpen("The typing test takes over the keyboard, which the game doesn't allow in combat.") then return false end
	Build()
	Style()
	Panel.Opening(TY)
	TY.Reset()
	frame:Show()
	TY.Draw()
	return true
end

function TY.Close(why)
	if frame then frame:SetScript("OnUpdate", nil) end
	Panel.Close(frame, why, "The typing test")
end

ns:RegisterCommand("typing", {
	desc = "A typing speed test (Tab: 15 / 30 / 60 s; Enter afterwards tells your guild; Esc quits)",
	aliases = { "wpm", "typetest" },
	run = function() TY.Open() end,
})

local ns = select(2, ...)
local L = ns.L

-- "How do I...": Terminal's own help as search results (1.7.7, the player's pick from the suggestions; first of the
-- usability ideas tabled in October). "how do i send to party", "what does shift enter do", "how do i make my own
-- command": the topics whose words the question has, best first, each a row with what to do in one line. Enter writes
-- its example into the prompt (Shift+Left comes back), as "what should i do"'s rows do. Only for a line no other question
-- takes ("how many linen do i have" stays the item count's, "how do i get into scholomance" the attunements'), and only
-- when every word it says fits a topic (release review: "how do i get the scarlet key" took the keys' topic from the
-- chains; "what does fade do" the priest's spell, .zen's): else the line is searched as words, or another question's.
-- Simple mode: the topics that teach Advanced syntax (>>, q:rare+, sort:, | count, > mats) say it its way instead.

local HT = {}
ns.HowTo = HT

local SEP = ns.DETAIL_SEP
HT.MAX = 5 -- (rows at most)
HT.ICON = "Interface\\Icons\\INV_Misc_Book_09"
HT.COLOR = "ff9fd8c8"

-- the topics: what it is (the row), how (its detail and tooltip), an example the prompt takes (nil: keys to press), and
-- the words that name it (English, as Simple mode's question cues are)
HT.TOPICS = {
	{ id = "send", title = L["Send a result to chat"],
		how = L["Type >> and a channel after a search: >> party, >> guild, >> say. >>> sends every result; a row's right-click menu does it too."],
		example = "hearthstone >> party", words = "send share post chat party raid guild say whisper tell link announce channel",
		simpleHow = L["Right-click a row to send it to party, guild or say; the speaker button under the prompt sends every result at once."] },
	{ id = "copy", title = L["Copy results as text"],
		how = L["Type to text or to csv after a search: a window opens with the results to copy (Ctrl+C)."],
		example = "linen to csv", words = "copy text csv clipboard export paste spreadsheet list" },
	{ id = "other", title = L["Do more with a result"],
		how = L["Shift+Enter does a row's other action (the footer says which); right-click a row for everything it can do."],
		example = nil, words = "shift enter second other action right click menu more options row" },
	{ id = "keys", title = L["See every key"],
		how = L["F1 lists every key Terminal uses, for the mode you're in (.keybinds too)."],
		example = ".keybinds", words = "keys key keyboard shortcut shortcuts hotkey hotkeys f1 press ctrl alt shift" },
	{ id = "bind", title = L["Change the key that opens Terminal"],
		how = L[".bind and a key sets it (.bind CTRL-SPACE), or the game's Key Bindings, under AddOns. In combat only Ctrl+` opens it."],
		example = ".bind", words = "bind open opens opening toggle key keybind keybinding" },
	{ id = "advanced", title = L["Use Advanced syntax"],
		how = L["Type it straight into the prompt (@npc, key:value filters, >, >>, |): it's searched as typed. Alt+` shows any line you typed as Advanced syntax."],
		example = "@npc is:vendor sort:distance", words = "advanced syntax mode simple switch alt code power",
		simpleHow = L["Alt+` turns what you typed into Advanced mode's command line; turn Simple mode off in terminal settings to type it yourself."],
		simpleExample = "terminal settings" },
	{ id = "filters", title = L["Narrow down the results"],
		how = L["Say it (\"rare swords under level 30\") or add filters: q:rare+, lvl:20-30, is:boe. .filters lists them all; the bar's Filter menu too."],
		example = "rare swords under level 30", words = "filter filters narrow fewer quality rare epic level only usable boe",
		simpleHow = L["Say it: \"rare swords under level 30\", \"boe cloth\", \"stamina food\"; the bar's Filter menu too."],
		simpleExample = "rare swords under level 30" },
	{ id = "sort", title = L["Sort the results"],
		how = L["Say it (\"sorted by level\", \"nearest\") or add sort:name, sort:level, sort:distance (sort:-level the other way); the bar's Sort menu too."],
		example = "swords sorted by level", words = "sort sorted order sorting cheapest highest lowest first",
		simpleHow = L["Say it: \"swords sorted by level\", \"nearest innkeeper\"; the bar's Sort menu too."],
		simpleExample = "swords sorted by level" },
	{ id = "group", title = L["Count or group the results"],
		how = L["Say it (\"quests per zone\") or add | count, | group by zone, | sum value, | first 5 after a search; the bar's Group menu too."],
		example = "quests per zone", words = "count group grouped total sum per tally add average",
		simpleHow = L["Say it: \"quests per zone\", \"how many linen do i have\"; the bar's Group menu too."],
		simpleExample = "quests per zone" },
	{ id = "chains", title = L["Go from one thing to another"],
		how = L["Ask \"where to get linen cloth\", \"mats for thorium belt\", \"what uses copper bar\", or add > sources, > mats, > uses after a name. .chains lists them."],
		example = "mats for thorium belt", words = "chain chains sources source mats materials reagents uses craft get learn recipe",
		simpleHow = L["Ask \"where to get linen cloth\", \"mats for thorium belt\" or \"what uses copper bar\"."],
		simpleExample = "mats for thorium belt" },
	{ id = "nearest", title = L["Find the nearest NPC or place"],
		how = L["Say nearest and what (nearest innkeeper, nearest mailbox; with Questie): Enter shows it on the map, and TomTom's arrow when you have it."],
		example = "nearest innkeeper", words = "nearest closest npc vendor trainer innkeeper mailbox map waypoint arrow tomtom" },
	{ id = "upgrades", title = L["Find gear upgrades"],
		how = L["Ask \"upgrades\", \"quest upgrades\" or \"vendor upgrades\". .weights says how they're judged: your talents, a tree you pick, your own weights or Pawn's scales."],
		example = "upgrades", words = "upgrade upgrades gear better weights pawn stats equipment" },
	{ id = "alias", title = L["Make your own command"],
		how = L[".alias, a name, then what it runs (a search, a /slash or a .command): .alias rep durability makes .rep. .alias alone lists yours."],
		example = ".alias", words = "alias own command commands shortcut custom macro" },
	{ id = "look", title = L["Change how Terminal looks"],
		how = L[".theme lists the themes (.theme dracula applies one); \"terminal settings\" has the font, size and colours."],
		example = ".theme", words = "theme look colour color colours colors font size bigger smaller appearance style dark" },
	{ id = "settings", title = L["Change a setting"],
		how = L["\"terminal settings\" lists every setting as a row: Enter turns it on or off, or writes .set for its values."],
		example = "terminal settings", words = "setting settings option options configure disable enable" },
	{ id = "zen", title = L["Dim the game while you search"],
		how = L[".zen fades the rest of the interface while Terminal is open; .zen again turns it off."],
		example = ".zen", words = "zen dim fade hide interface darken screen" },
	{ id = "history", title = L["Find what you ran before"],
		how = L["Up on an empty prompt brings back the line you ran last; Ctrl+R searches everything you ran."],
		example = nil, words = "history again before previous last ran recent repeat earlier" },
	{ id = "fuzzy", title = L["Fuzzy-find in every list"],
		how = L["Hold Tab and press ` (or .fuzzy): every list at once, by name only; Enter takes the result back to the search."],
		example = ".fuzzy", words = "fuzzy fzf everything every all lists anything" },
	{ id = "ask", title = L["Let your guild ask Terminal"],
		how = L[".ask guild on: a guildie typing !t and a question (!t nearest innkeeper) gets Terminal's answer from you. .ask off stops it."],
		example = ".ask", words = "guild ask asks questions answer answers group others bot" },
	{ id = "share", title = L["Share your bags with friends"],
		how = L["With Terminal: Share, .share invite and a name starts a group: your bags in their searches, theirs in yours."],
		example = ".share", words = "share sharing bags friends friend invite trade alts" },
	{ id = "report", title = L["Report a problem"],
		how = L[".report and what happened: what Terminal knows that helps comes with it, to paste on CurseForge."],
		example = ".report", words = "report bug problem issue error broken feedback wrong" },
	{ id = "why", title = L["See why a result is there"],
		how = L["Right-click a row: Why is this here? says what in your search let it in. .explain reads an Advanced line in plain words."],
		example = ".explain", words = "why explain understand reason here result shown listed" },
	{ id = "tabs", title = L["Keep several searches open"],
		how = L["Ctrl+T opens a new tab (four at most), each kept up to date; Ctrl+1-4 or Ctrl+Tab switches between them."],
		example = nil, words = "tab tabs several multiple searches open keep" },
	{ id = "help", title = L["See every command"],
		how = L[".help says how to use Terminal; .help advanced lists every command. Type a dot to pick one."],
		example = ".help", words = "commands command list help dot all" },
	{ id = "tour", title = L["Learn Terminal in a few steps"],
		how = L[".tour shows the basics in a few short steps."],
		example = ".tour", words = "tour learn start begin basics tutorial new started" },
}

-- how a how-to question starts (English, as Simple mode's cues are), and the little words that say nothing of a topic
-- ("where do i", "can i" left out: "where do i turn in the defias brotherhood", "can i take <quest>" are other questions';
-- "what does" only as "what does ___ do": "what does innkeeper farley sell", "what does <quest> unlock" are theirs too)
local CUES = { "how do i ", "how can i ", "how do you ", "how to ", "how does ", "how should i ", "is there a way to " }
local STOP = { a = true, an = true, the = true, i = true, my = true, me = true, to = true, of = true, it = true, is = true,
	["in"] = true, on = true, off = true, turn = true, with = true, ["do"] = true, does = true, can = true, ["for"] = true,
	this = true, that = true, terminal = true, use = true, using = true, get = true, make = true, see = true, what = true,
	how = true, find = true, change = true, set = true, up = true, some = true, any = true, by = true, from = true,
	at = true, into = true, out = true, so = true, just = true, will = true, should = true, you = true, your = true }
-- "what does ___ do": keys and Terminal's own commands only ("what does shift enter do", "what does .zen do"); a spell's
-- or an item's name is no topic ("what does fade do": the priest's spell, not .zen; release review)
local KEY_TOPICS = { other = true, keys = true, bind = true, advanced = true, fuzzy = true, history = true, tabs = true, why = true }
-- Terminal's commands the topics' examples run ("zen", "fuzzy", "alias"): named as they are, any topic's
local COMMANDS = {}
for _, t in ipairs(HT.TOPICS) do
	local c = t.example and t.example:match("^%.(%a+)")
	if c then COMMANDS[c] = true end
end

-- each topic's words, made once: word -> true
local wordsOf = {}
local function WordsOf(t)
	local w = wordsOf[t]
	if not w then
		w = {}
		for x in t.words:gmatch("%S+") do w[x] = true end
		wordsOf[t] = w
	end
	return w
end

--- How well one of a topic's words fits a typed word: 2 the word itself, 1 one starts the other (four letters and up), 0.
local function WordFit(own, w)
	if own[w] then return 2 end
	if #w < 4 then return 0 end
	for x in pairs(own) do
		if #x >= 4 and (x:find(w, 1, true) == 1 or w:find(x, 1, true) == 1) then return 1 end
	end
	return 0
end

--- How well a topic fits the question's words.
local function Fit(t, words)
	local own, n = WordsOf(t), 0
	for _, w in ipairs(words) do n = n + WordFit(own, w) end
	return n
end

-- whether a typed word fits any topic (`only`: KEY_TOPICS), kept: asked per keystroke, a few words each
local known, knownCount = {}, 0
local function Known(w, only)
	local k = only and ("!" .. w) or w
	local got = known[k]
	if got == nil then
		got = false
		for _, t in ipairs(HT.TOPICS) do
			if (not only or only[t.id]) and WordFit(WordsOf(t), w) > 0 then got = true break end
		end
		if knownCount >= 500 then known, knownCount = {}, 0 end
		known[k], knownCount = got, knownCount + 1
	end
	return got
end

--- The topics for these words, best first (ties in the list's order), at most HT.MAX (`only`: those topics alone).
function HT.Topics(words, only)
	local found = {}
	for i, t in ipairs(HT.TOPICS) do
		if not only or only[t.id] then
			local n = Fit(t, words)
			if n > 0 then found[#found + 1] = { t = t, n = n, i = i } end
		end
	end
	table.sort(found, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.i < b.i end)
	local out = {}
	for i = 1, math.min(#found, HT.MAX) do out[i] = found[i].t end
	return out
end

--- "how do i send to party" -> { words = { "send", "party" } }, or nil: not a how-to question, or a word it says fits no
--- topic ("how do i get the scarlet key": a key to a dungeon, the chains'). Its words: not the little ones, nor keys'
--- signs (`, +); a command's dot dropped (".zen": zen).
function HT.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") .. " "
	local rest = t:match("^what does (.+) do $")
	local only
	if rest then only = KEY_TOPICS end
	for _, c in ipairs(rest and {} or CUES) do
		if t:sub(1, #c) == c then rest = t:sub(#c + 1) break end
	end
	if not rest then return nil end
	local words = {}
	for w in rest:gmatch("%S+") do
		local dot = w:sub(1, 1) == "."
		if dot then w = w:sub(2) end
		if not STOP[w] and #w > 1 and w:find("%a") then
			-- (a command named after "what does": any topic's; else the keys' topics only)
			if not Known(w, (not (dot or COMMANDS[w])) and only or nil) then return nil end
			words[#words + 1] = w
		end
	end
	if #words == 0 then return nil end
	return { words = words }
end

-- a row's Enter: its example in the prompt, searched (Shift+Left comes back)
local function Activate(e)
	local UI = ns.UI
	if e.example and UI and UI.WalkTo then UI:WalkTo(e.example) end
end
local function Tooltip(e, tip)
	tip:AddLine(e.name, 1, 0.82, 0)
	tip:AddLine(e.how, 0.85, 0.85, 0.85, true)
	if e.example then
		tip:AddLine(" ")
		tip:AddDoubleLine(L["Enter writes"], e.example, 0.6, 0.6, 0.6, 1, 1, 1)
	end
end

function HT.Answer(q)
	local rows = {}
	local simple = ns.Easy and ns.Easy.On and ns.Easy.On()
	for i, t in ipairs(HT.Topics(q.words)) do
		local how, example = t.how, t.example
		if simple and t.simpleHow then how, example = t.simpleHow, t.simpleExample end -- (Simple mode: no Advanced syntax)
		rows[i] = { kind = "howto", kindLabel = "|c" .. HT.COLOR .. L["How to"] .. "|r", name = t.title, raw = true,
			key = "howto:" .. t.id, icon = HT.ICON, how = how, example = example, staysOpen = true,
			detail = example and (how .. SEP .. example) or how,
			actionVerb = example and L["write it"] or nil, noActivate = not example or nil,
			activate = Activate, tooltip = Tooltip, _score = 100 - i }
	end
	return rows, L["How to"] .. (rows[1] and rows[1].example and (SEP .. L["Enter writes the example"]) or "")
end

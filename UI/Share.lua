local ns = select(2, ...)
local L = ns.L

-- ">> channel": whatever result is selected goes to a chat channel instead of being opened.
--
--   copper bar >> party        the item's link to your party
--   @npc hogger >> guild       a map pin where Hogger stands
--   >> whisper Plamen          the selected recent pick, whispered
--
-- A ">>" standing on its own (or starting a word: ">>party") ends the search; the word after it is the
-- channel. With two, the last one counts. Enter (or a click)
-- has the game press the chat line (/p, /g...) from the secure macro button, as it runs your macros:
-- Terminal's own code never sends chat. What goes out: the row's link (items, spells, achievements,
-- recipes, quests), a map pin for NPCs, else its name. The game runs at most 255 characters of a macro.
--
-- ">>> channel" (0.44.2) sends every result at once instead: "mats for thorium belt >>> party",
-- "@loot lorgus jett >>> guild". One line says what they are ("Mats for Thorium Belt (3): 12x [Thorium Bar], ..."),
-- as many lines as it takes (SH.GROUP_LINES at most). A macro the game presses runs only 255 characters in all, so
-- these lines are sent by Terminal itself, inside the key press or click that asked (SH.SendAll). The right-click
-- menu has the same as "All N to party" (Simple mode too).

-- ">> text" and ">> csv" (0.52.10, the player's ask: "simple copy pasting of outputs") aren't chat: the selected result
-- (">>> text": every result) opens in a box to copy (Ctrl+C), as plain lines or as CSV (name,detail,kind,id). In Simple
-- mode too.

local SH = {}
ns.Share = SH

local CHANNELS = {
	party = "party", p = "party", group = "party",
	guild = "guild", g = "guild",
	raid = "raid", r = "raid",
	officer = "officer", o = "officer",
	say = "say", s = "say",
	yell = "yell", y = "yell",
	instance = "instance", i = "instance", bg = "instance",
}
local COMMAND = { party = "/p", guild = "/g", raid = "/raid", officer = "/o", say = "/s", yell = "/y", instance = "/i" }
local WHISPER = { w = true, whisper = true, tell = true, t = true }
-- (the game's chat types, for the lines Terminal sends itself: ">>>")
local CHAT_TYPE = { party = "PARTY", guild = "GUILD", raid = "RAID", officer = "OFFICER", say = "SAY", yell = "YELL",
	instance = "INSTANCE_CHAT" }
SH.NAMES = { "party", "guild", "raid", "say", "yell", "officer", "instance", "whisper", "drop", "track", "untrack", "text", "csv" }
local COPY = { text = "text", txt = "text", copy = "text", csv = "csv" }
-- (how a channel is named where it's shown: the footer, the ">>>" row)
local LABEL = { party = L["party"], guild = L["guild"], raid = L["raid"], officer = L["officer"], say = L["say"],
	yell = L["yell"], instance = L["instance"] }

--- Does some channel name start with this word? (While it's being typed: not wrong yet.) A number
--- only when it can still become a channel number (1-20, as Channel takes them).
function SH.IsStart(word)
	local w = ns.Lower(word or "")
	-- (every word Channel takes, its other names too: "gro" for group, "tel" for tell, "cop" for copy; review, 0.53.6)
	for _, names in ipairs({ CHANNELS, WHISPER, COPY, { drop = true, track = true, untrack = true } }) do
		for n in pairs(names) do if n:sub(1, #w) == w then return true end end
	end
	return w:match("^[1-9]%d?$") ~= nil and tonumber(w) <= 20
end

--- The search text and what follows a ">>" standing alone or starting a word (nil when there's none):
--- "copper >> party" -> "copper ", "party"; "copper >>party" the same. The last ">>" is the one (a ">>" in
--- the search part before it stays a word of the search). "lvl:>>20" has none: it's inside a word.
--- A third result is true for ">>>" (every result, not only the selected one).
--- (Read by the line's send recognizer below: the reading's send, Phrase.lua)
function SH.Split(text)
	if type(text) ~= "string" or not text:find(">>", 1, true) then return text, nil end
	local send = ns.Phrase.ReadLine(text, { simple = false }).send
	if not send then return text, nil end
	return text:sub(1, send.at - 1), send.channel, send.all or nil
end

-- the send: a word starting with ">>", the last one in the line (not inside a "quoted phrase"), and every word after
-- it: where to send. "copper >> party", "copper >>party"; "lvl:>>20" has none (it's inside a word). In either mode.
ns.Phrase.Register({ id = "send", stage = "send", priority = 20, classes = { op = true, syntax = true, word = true, quoted = true },
	modes = { simple = true, advanced = true },
	at = function(r, i)
		local toks = r.toks
		local t = toks[i]
		if t.class == "quoted" or t.text:sub(1, 2) ~= ">>" then return nil end
		for k = i + 1, #toks do -- (the last one)
			if toks[k].class ~= "quoted" and toks[k].text:sub(1, 2) == ">>" then return nil end
		end
		local all = t.text:sub(3, 3) == ">"
		return { from = i, to = #toks, kind = "send", at = t.s, all = all or nil,
			channel = (r.line:sub(t.s + (all and 3 or 2)):gsub("^%s+", ""):gsub("%s+$", "")) }
	end })

--- Simple mode's way to copy (0.52.12, the player's call: ">>" is Advanced mode's): "linen to csv", "linen as text"
--- at the end of a search copies every result. Gives the search and "csv" / "text", or nil.
--- (Read by the line's copy recognizer below: the reading's copy, Phrase.lua)
function SH.PlainCopy(text)
	if type(text) ~= "string" then return nil end
	local copy = ns.Phrase.ReadLine(text, { simple = true }).copy
	if not copy then return nil end
	return copy.query, copy.how
end

-- the copy: the line's last two words, "to"/"as" and "csv"/"text", after a search (Simple mode)
ns.Phrase.Register({ id = "copy", stage = "send", priority = 10,
	at = function(r, i)
		local toks = r.toks
		local n = #toks
		if i ~= n - 1 or i < 2 then return nil end
		local pre, how = toks[i], toks[n]
		if not (pre.text:find("^%a%a$") and how.text:find("^%a+$")) then return nil end
		if (pre.low ~= "to" and pre.low ~= "as") or (how.low ~= "csv" and how.low ~= "text") then return nil end
		return { from = i, to = n, kind = "copy", how = how.low, query = (r.line:sub(1, pre.s - 1):gsub("%s+$", "")) }
	end })

--- A whisper's target as typed ("Plamen Warr"): a first name and surname joined the way the game joins them
--- (ns.CharacterName); one word as it is.
function SH.WhisperTarget(who)
	local first, rest = who:match("^(%S+)%s+(.-)$")
	if not first then return who end
	return first .. (ns.SurnameSeparator() or " ") .. rest
end

--- Where to send: { cmd = "/p", label = "party" }; { pending = true } while the channel is still to be
--- typed; { bad = word } for a word that isn't one. "drop" isn't chat: quests in your log dropped instead (">> drop"
--- the selected one, ">>> drop" every one listed; Terminal asks first either way: QuestDrop.lua).
function SH.Channel(rest)
	local w, more = (rest or ""):match("^(%S*)%s*(.-)%s*$")
	local lw = ns.Lower(w or "")
	if lw == "" then return { pending = true } end
	if lw == "drop" then return { drop = true, label = "drop" } end
	-- ("track", "untrack", "track only": quests in your log tracked or untracked instead: QuestTrack.lua, 0.63.3)
	if lw == "track" or lw == "untrack" then
		local how = lw == "untrack" and "untrack" or (ns.Lower(more or "") == "only" and "only" or "track")
		return { quests = how, label = how == "only" and "track only" or lw }
	end
	if COPY[lw] then return { copy = COPY[lw], label = COPY[lw] == "csv" and "CSV" or L["text"] } end
	local ch = CHANNELS[lw]
	if ch then return { cmd = COMMAND[ch], label = LABEL[ch], chat = CHAT_TYPE[ch] } end
	if WHISPER[lw] then
		-- (the whole name: characters here have a surname, "w Plamen Warr")
		local who = more or ""
		if who == "" then return { pending = true, label = L["whisper"] } end
		local target = SH.WhisperTarget(who)
		return { cmd = "/w " .. target, label = L["whisper %s"]:format(who), chat = "WHISPER", target = target }
	end
	local n = tonumber(lw)
	if n and n >= 1 and n <= 20 then return { cmd = "/" .. n, label = L["channel %s"]:format(n), chat = "CHANNEL", target = n } end
	return { bad = w }
end

----------------------------------------------------------------------
-- ">> text", ">> csv": results to copy
----------------------------------------------------------------------

--- A row's text as pasted elsewhere: no colour codes, icons or link markup ("|Hitem:..|h[Linen Cloth]|h" -> "[Linen
--- Cloth]"), one line.
local function Clean(s)
	if s == nil or ns.Secret(s) then return "" end
	-- (coins drawn as icons keep their units: "12g 3s", not "12 3"; and the game's named colours go, |cnIQ4:; release
	-- review)
	s = tostring(s):gsub("|T[^|]-GoldIcon[^|]-|t", "g"):gsub("|T[^|]-SilverIcon[^|]-|t", "s"):gsub("|T[^|]-CopperIcon[^|]-|t", "c")
		:gsub("|cn[^:|]*:", "")
	s = ns.Plain(s):gsub("|H.-|h(.-)|h", "%1"):gsub("|A.-|a", ""):gsub("|n", " "):gsub("[\r\n]+", " ")
	return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end
SH.Clean = Clean
local function KindOf(e)
	local p = e.kind and ns.providers[e.kind]
	return Clean((p and p.label) or e.kindLabel or e.kind or "") -- (its label, "Item": not its @kind)
end
local function IdOf(e)
	local id = e.itemID or e.spellID or e.questID or e.npcID or e.achievementID or e.mountID
	return type(id) == "number" and tostring(id) or ""
end
local function Field(s)
	if s:find('[",]') then s = '"' .. s:gsub('"', '""') .. '"' end
	return s
end
SH.CSV_HEAD = "name,detail,kind,id"
--- The rows as text to copy ("text": a line each, its name and what the row says; "csv": a header and a line each),
--- and how many rows went in (rows that are only notes left out).
function SH.CopyText(rows, how)
	local out, n = {}, 0
	if how == "csv" then out[1] = SH.CSV_HEAD end
	for _, e in ipairs(rows or {}) do
		-- (a summed-up row goes too, totals and all, its money as plain text: "| sum value >> text", 0.52.13)
		if type(e) == "table" and (not e.noActivate or (e.kind == "aggregate" and e.key ~= "aggregate:hint")) then
			local name, detail = Clean(e.copyName or e.name), Clean(e.copyDetail or e.detail)
			if name ~= "" then
				n = n + 1
				if how == "csv" then
					out[#out + 1] = table.concat({ Field(name), Field(detail), Field(KindOf(e)), IdOf(e) }, ",")
				else
					out[#out + 1] = detail ~= "" and (name .. " - " .. detail) or name
				end
			end
		end
	end
	return table.concat(out, "\n"), n
end

local Call = ns.Safe -- (every use keeps only the first result)

local function IsLink(l) return type(l) == "string" and l:find("|H", 1, true) ~= nil end

local ItemLink = ns.ItemLink

--- Where a loot row's item drops, from its detail ("Garr  Molten Core"): "dropped by Garr in Molten Core", "from
--- trash in Stratholme", "from Molten Core" (no boss named); nil for other rows.
--- A loot row's boss and instance, from its detail ("Garr  Molten Core"): "Garr", "Molten Core"; "" for one not
--- named ("?"); nil for other rows.
function SH.LootWhere(e)
	if not e or e.kind ~= "loot" or type(e.detail) ~= "string" then return nil end
	local d = ns.Plain(e.detail)
	local boss, inst = d:match("^(.-)%s%s+(.-)%s*$")
	if not boss then boss, inst = d:match("^%s*(.-)%s*$"), "" end
	if boss == "?" or boss == inst then boss = "" end
	return boss, inst
end

function SH.LootSource(e)
	local boss, inst = SH.LootWhere(e)
	if not boss or (boss == "" and inst == "") then return nil end
	if boss == "" then return L["from %s"]:format(inst) end
	if ns.Lower(boss):find("trash", 1, true) then return inst ~= "" and L["from trash in %s"]:format(inst) or L["from trash"] end
	return inst ~= "" and L["dropped by %s in %s"]:format(boss, inst) or L["dropped by %s"]:format(boss)
end

-- the base text with where a loot row's item drops after it, and what the row adds of its own (`shareExtra`: a
-- stored item's holders) within `room` characters when given
local function WithSource(e, text, room)
	if type(text) ~= "string" or text == "" then return text end
	local from = SH.LootSource(e)
	if from then text = text .. " " .. from end
	local f = e.shareExtra
	if type(f) == "function" then
		local ok, x = pcall(f, e, room and (room - #text) or nil)
		if ok and type(x) == "string" and x ~= "" then text = text .. x end
	end
	return text
end

--- What a row sends: its link (a loot row's says where it drops, unless `bare`), a map pin for an NPC, else its name.
function SH.Text(e, bare)
	local text = SH.BaseText(e)
	if bare then return text end
	return WithSource(e, text)
end

function SH.BaseText(e)
	-- an NPC: a map pin where it stands (the waypoint Shift+Enter drops; a C API, fine from here)
	if e.npcID and ns.Integrations and ns.Integrations.NpcPinLink then
		local pin = ns.Integrations.NpcPinLink(e)
		if pin then return e.name .. " " .. pin end
	end
	-- a spot of its own (an instance entrance, a mailbox): its name and a map pin there
	if e.ui and e.px and ns.Integrations and ns.Integrations.SpotPinLink then
		local pin = ns.Integrations.SpotPinLink(e)
		-- (a row named only for what it is, "Mailbox": the context says it, "Nearby mailbox: [pin]")
		if pin then return e.generic and pin or ((e.pinName or e.name) .. " " .. pin) end
	end
	-- (shareLink: a link only for sending, never shown in a tooltip: a profession's opens its window)
	local shared = Call(e.shareLink, e)
	-- (a shareLink may be text another addon reads as a link: Questie's "[Name (id)]")
	if type(shared) == "string" and shared ~= "" then return shared end
	local link = Call(e.getLink, e) or e.link
	if not IsLink(link) then
		local id = e.itemID or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
		link = id and ItemLink(id) or nil
	end
	if not IsLink(link) then
		local q = e.questID or e.qid
		local get = _G.GetQuestLink or (C_QuestLog and C_QuestLog.GetQuestLink)
		if q and get then
			local l = Call(get, q)
			if IsLink(l) then link = l end
		end
		-- the game links only quests in your log here: Questie's link otherwise
		if not IsLink(link) and q and ns.Integrations and ns.Integrations.QuestieQuestLink then
			local l = ns.Integrations.QuestieQuestLink(q)
			if type(l) == "string" and l ~= "" then return l end
		end
	end
	if IsLink(link) then return link end -- (a link carries its own name)
	return e.name
end

-- What an NPC search's filters say the NPC is ("@npc reagent is:vendor sort:distance" -> "Nearby reagent vendor").
SH.ROLES = {
	vendor = L["vendor"], repair = L["repair vendor"], inn = L["innkeeper"], innkeeper = L["innkeeper"], bank = L["banker"],
	banker = L["banker"], flight = L["flight master"], flightmaster = L["flight master"], auctioneer = L["auctioneer"],
	stable = L["stable master"], stablemaster = L["stable master"], trainer = L["trainer"],
	questgiver = L["quest giver"], classtrainer = L["class trainer"], proftrainer = L["profession trainer"],
	battlemaster = L["battlemaster"], pvpvendor = L["PvP vendor"], pvp = L["PvP NPC"],
}
local MY_CLASS = { class = true, my = true, me = true, myclass = true }

local Titled = ns.Titled

--- Is the word a shorthand whose full name is in the name ("rfk" for Razorfen Kraul)? Then it says nothing more.
function SH.ShortIn(word, lname)
	local xs = ns.Shorthand and ns.Shorthand[word]
	if not xs then return false end
	for _, x in ipairs(xs) do if lname:find(x, 1, true) then return true end end
	return false
end

--- Words saying what an NPC sent to chat is, from what was searched: "Nearby reagent vendor", "Mining trainer in
--- Orgrimmar". The search's own words (those not in the NPC's name), its role and trainer filters, "Nearby" for
--- sort:distance / near:, "in <place>" for in:. nil when the search says nothing more than the name.
--- A search's words as the search reads them: a "quoted phrase" one word, quote marks off (in:"elwynn forest" is
--- in:elwynn forest: review, 0.53.6, it was said as "Elwynn and forest"). Phrases after the words.
local function QueryWords(query)
	local words, phrases = ns.Words(query)
	for _, p in ipairs(phrases) do words[#words + 1] = p end
	return ipairs(words)
end

function SH.Context(query, e)
	if type(query) ~= "string" or not (e and (e.npcID or (e.ui and e.px))) then return nil end
	local lname = ns.Lower(tostring(e.name or ""))
	local F = ns.Filters
	local nearby, words, roles, place = false, {}, {}, nil
	for _, w in QueryWords(query) do
		local lw = ns.Lower(w)
		local key, val = lw:match("^(%a+):(.*)$")
		if lw:sub(1, 1) == "@" then
			-- (the kind: an NPC already)
		elseif lw:find("^[-!]") or lw:find("[|&]") then
			-- (a word left out, or either of several: not what it is, as SH.Describe reads them; a "|" in a chat line is an
			-- escape the game refuses. 0.50.7, review: "Nearby hogger|vancleef: Hogger")
		elseif F and F.SortOf and F.SortOf(lw) then
			nearby = F.SortOf(lw) == "distance" -- (sort:plan: recipes, nothing to say of them; sort:-distance: nor the farthest)
		elseif key and F and F.IsKey and F.IsKey(key) then
			val = val:gsub("_", " ")
			if key == "near" or key == "within" or key == "dist" then
				nearby = true
			elseif key == "is" and SH.ROLES[val] then
				roles[#roles + 1] = SH.ROLES[val]
			elseif key == "trainer" then
				if MY_CLASS[val] then
					local cls = UnitClass and UnitClass("player")
					val = type(cls) == "string" and ns.Lower(cls) or L["class"]
				elseif val == "mine" then
					val = L["mining"]
				end
				roles[#roles + 1] = L["%s trainer"]:format(val)
			elseif key == "in" or key == "zone" or key == "from" or key == "where" then
				place = Titled(val)
			end
		elseif not lname:find(lw, 1, true) and not SH.ShortIn(lw, lname) then
			words[#words + 1] = lw
		end
	end
	local parts = {}
	if nearby then parts[#parts + 1] = L["nearby"] end
	if e.generic then parts[#parts + 1] = lname end -- (what it is: the line then carries only its pin)
	if nearby and e.what then parts[#parts + 1] = e.what end -- ("Nearby dungeon: Razorfen Kraul entrance [pin]")
	for _, w in ipairs(words) do parts[#parts + 1] = w end
	for _, r in ipairs(roles) do parts[#parts + 1] = r end
	if #parts == 0 and not place then return nil end
	local text = table.concat(parts, " ")
	if place then text = text ~= "" and L["%s in %s"]:format(text, place) or L["in %s"]:format(place) end
	return ns.UpperFirst(text)
end

--- The channels a row can go to from its right-click menu, those you're in: { cmd, label } (say always; party or
--- raid, instance, guild when you're in one; your target when it's another player: "/w Name").
function SH.MenuChannels()
	local out = { { cmd = "/s", label = L["Say in chat"], chat = "SAY", short = L["say"] } }
	-- (a secret answer, UnitIsUnit's where unit comparison is restricted, is never tested: false; 0.50.7, review)
	local function Is(fn, ...)
		if type(fn) ~= "function" then return false end
		local v = Call(fn, ...)
		if ns.Secret(v) then return false end
		return v and true or false
	end
	local instance = _G.LE_PARTY_CATEGORY_INSTANCE
	local inInstance = instance and Is(_G.IsInGroup, instance)
	-- (your own raid: one only the instance made (a battleground, the raid finder) takes instance chat, not /raid; 0.49.2,
	-- review: "All N to raid" was offered there and the game refused it)
	if Is(_G.IsInRaid, _G.LE_PARTY_CATEGORY_HOME) then
		out[#out + 1] = { cmd = "/raid", label = L["Send to raid"], chat = "RAID", short = L["raid"] }
	elseif Is(_G.IsInGroup) and not (inInstance and not Is(_G.IsInGroup, _G.LE_PARTY_CATEGORY_HOME)) then
		out[#out + 1] = { cmd = "/p", label = L["Send to party"], chat = "PARTY", short = L["party"] }
	end
	if inInstance then out[#out + 1] = { cmd = "/i", label = L["Send to instance"], chat = "INSTANCE_CHAT", short = L["instance"] } end
	if Is(_G.IsInGuild) then out[#out + 1] = { cmd = "/g", label = L["Send to guild"], chat = "GUILD", short = L["guild"] } end
	if Is(_G.UnitIsPlayer, "target") and not Is(_G.UnitIsUnit, "target", "player") then
		-- (by name, its realm too when another's: "/w %t" reached WoW Forever as a whisper to "%t", 0.56.3, the player;
		-- "to target", or the name read as a friend of the row's: the player again. A name the game keeps secret: none)
		-- (UnitName's second answer: the surname where characters have one, "Fatherless Behavior", joined the game's way;
		-- else the realm, "-Realm": as a group member's name, Group.lua's NameOf)
		local name, second = Call(_G.UnitName, "target")
		name, second = ns.Str(name), ns.Str(second)
		if name then
			local sep = ns.SurnameSeparator()
			local target = (second and second ~= "") and (name .. (sep or "-") .. (sep and second or second:gsub("%s", ""))) or name
			local shown = (second and sep) and (name .. " " .. second) or name
			-- (short: "All 8 to Bob", the bar's speaker button; release review: without it that menu errored with a player targeted)
			out[#out + 1] = { cmd = "/w " .. target, label = L["Whisper to target (%s)"]:format(shown), chat = "WHISPER", target = target,
				short = shown }
		end
	end
	return out
end

--- What a chain's row is, said before it in chat ("mats for thorium belt": "Mats for Thorium Belt"), and its text
--- as the chain sees it: a reagent's count ("8x [Thorium Bar]"), a source's way ("sold by Name [pin]"). nil, text
--- for rows not from a chain.
SH.CHAIN = {
	mats = L["Mats for %s"], uses = L["%s is used in"], sources = L["Where to get %s"], -- (alts: the holders say it)
	learn = L["Where to learn %s"],
}
function SH.ChainText(e, text)
	local rel = e.pipeRel
	if not rel or type(text) ~= "string" or text == "" then return nil, text end
	if rel == "mats" and tonumber(e.need) then
		text = ("%dx %s"):format(e.need, text)
	elseif (rel == "sources" or rel == "learn") and type(e.pipeHow) == "string" then
		text = e.pipeHow .. " " .. text
	end
	local from, fmt = e.pipeFrom, SH.CHAIN[rel]
	return (fmt and from) and fmt:format(from) or nil, text
end

--- What goes into the chat box for a row: "<context>: <text>" (a chain's, else Context), else the text.
function SH.Line(e, query)
	-- ("used in" rows from AtlasLoot are its crafting pages: no "dropped by Blacksmithing in Crafting")
	local ctx, text = SH.ChainText(e, SH.Text(e, e.pipeRel == "uses"))
	if type(text) ~= "string" or text == "" then return nil end
	ctx = ctx or SH.Context(query, e)
	return ctx and (ctx .. ": " .. text) or text
end

--- The chat line for a row, or nil. Kept within what a macro runs (255 characters): what the search said it is
--- comes first ("Nearby reagent vendor: Name [pin]"), dropped when the line would be too long.
function SH.Macro(e, to)
	if not (to and to.cmd and e) then return nil end
	local base = SH.BaseText(e) -- (worked out once: an NPC's sets your map pin to link it)
	local max = ns.Secure and ns.Secure.MACRO_MAX or 255
	local ctx, text = SH.ChainText(e, e.pipeRel == "uses" and base or WithSource(e, base, max - #to.cmd - 1))
	if type(text) ~= "string" or text == "" then return nil end
	ctx = ctx or SH.Context(to.query, e)
	local line = to.cmd .. " " .. (ctx and (ctx .. ": ") or "") .. text
	if #line > max then line = to.cmd .. " " .. (e.generic and (tostring(e.name) .. " ") or "") .. text end
	if #line > max then line = to.cmd .. " " .. tostring(base) end -- (a loot row: without where it drops)
	if #line > max then line = to.cmd .. " " .. tostring(e.name) end
	return line
end

----------------------------------------------------------------------
-- Every result at once (">>> party", the menu's "All N to party")
----------------------------------------------------------------------

SH.GROUP_LINES = 6 -- (chat lines at most; what doesn't fit is counted: "+5 more")
SH.LINE_MAX = 255

--- The rows worth sending: real results (no hint, help, category or completion rows, no row that asks something,
--- @who's "Ask the server", nor the calculator's answer), each once.
function SH.GroupRows(list)
	local out, seen = {}, {}
	for _, e in ipairs(list or {}) do
		if type(e) == "table" and not (e.noActivate or e.raw or e.completion or e.catId or e.syntaxRow or e.lead or e.kind == "calc") then
			local o = rawget(e, "pipeOf") or e
			local id = tostring(o.kind) .. ":" .. tostring(o.key or o.itemID or o.name)
			if not seen[id] then seen[id] = true; out[#out + 1] = e end
		end
	end
	return out
end

-- What a search's filters say the rows are ("@loot rfk type:weapon q:rare" -> "Rare weapons"): the noun from type: or
-- slot:, words before it from q: and is:boe, "upgrades" for is:upgrade, "with <stat>" and the levels after. A "|" list
-- names each ("type:sword|axe": "Swords and axes", "q:rare|epic": "Rare or epic", each part of an & its own:
-- "q:rare&type:sword|q:epic&type:axe" -> "Rare swords and epic axes"). nil when the filters say nothing, or the rows
-- aren't items (`rows` given: lvl: on @who or @npc says nothing of items).
local MASS = { armor = true, cloth = true, leather = true, mail = true, plate = true, food = true, gear = true,
	ammo = true, jewelry = true, ["trade goods"] = true, junk = true, miscellaneous = true, ammunition = true }
local PLURAL = { staff = "staves", stave = "staves", knife = "knives", ["fist weapon"] = "fist weapons" }
local SLOT_NOUN = {
	head = { L["helm"], L["helms"] }, neck = { L["necklace"], L["necklaces"] }, shoulder = { L["shoulder"], L["shoulders"] },
	back = { L["cloak"], L["cloaks"] }, chest = { L["chest piece"], L["chest pieces"] }, wrist = { L["bracer"], L["bracers"] },
	hands = { L["glove"], L["gloves"] }, waist = { L["belt"], L["belts"] }, legs = { L["legging"], L["leggings"] },
	feet = { L["boot"], L["boots"] }, finger = { L["ring"], L["rings"] }, trinket = { L["trinket"], L["trinkets"] },
	["two-hand"] = { L["two-hander"], L["two-handers"] }, ["one-hand"] = { L["one-hander"], L["one-handers"] },
	["off hand"] = { L["off-hand"], L["off-hands"] }, ["main hand"] = { L["main-hand weapon"], L["main-hand weapons"] },
	shield = { L["shield"], L["shields"] }, ranged = { L["ranged weapon"], L["ranged weapons"] }, tabard = { L["tabard"], L["tabards"] },
	shirt = { L["shirt"], L["shirts"] }, weapon = { L["weapon"], L["weapons"] },
}
local ARMOUR = { cloth = true, leather = true, mail = true, plate = true }
SH.QUALITY_WORDS = { [0] = L["poor"], L["common"], L["uncommon"], L["rare"], L["epic"], L["legendary"], L["artifact"], L["heirloom"] }

local function Plural(w)
	if MASS[w] then return w end
	if PLURAL[w] then return PLURAL[w] end
	if w:match("[^s]s$") then return w end -- (plural already, as the game's own type names are: daggers, bows, staves)
	if w:match("[sxz]$") or w:match("[cs]h$") then return w .. "es" end
	if w:match("[^aeiou]y$") then return w:sub(1, -2) .. "ies" end
	return w .. "s"
end

local function Value(v) return (v:gsub("_", " ")) end

-- "rare", "rare or better" (q:rare+, q:3+, q:blue: the q: filter's own words), nil for a word that isn't a quality
local function QualityWord(val)
	local word, plus = val:match("^(%w+)(%+?)$")
	if not word then return nil end
	local Q = ns.Filters and ns.Filters.QUALITY
	local n = tonumber(word) or (Q and Q[word])
	local q = n and SH.QUALITY_WORDS[n]
	return q and (plus == "+" and L["%s or better"]:format(q) or q) or nil
end

-- the game's slot word for an everyday one (slot:boots is the feet: Filters' own aliases)
local function SlotName(v)
	local alias = ns.Filters and ns.Filters.SLOT_ALIAS
	return alias and alias[v] or v
end

-- can Describe say this key:value? (other keys, and is: values other than boe/upgrade, it can't)
local function Says(key, val)
	if key == "type" or key == "slot" or key == "lvl" or key == "level" or key == "ilvl" or key == "itemlevel" then return val ~= "" end
	if key == "q" or key == "quality" then return QualityWord(val) ~= nil end
	if key == "stat" or key == "stats" then return val:match("^[%a_]+") ~= nil end
	if key == "is" then return val == "boe" or val == "upgrade" or val == "upgrades" end
	return false
end

local function NewSpec() return { types = {}, slots = {}, quals = {}, stats = {} } end

local function Add(spec, key, val)
	if key == "type" then spec.types[#spec.types + 1] = Value(val)
	elseif key == "slot" then spec.slots[#spec.slots + 1] = SlotName(Value(val))
	elseif key == "q" or key == "quality" then spec.quals[#spec.quals + 1] = QualityWord(val)
	elseif key == "stat" or key == "stats" then spec.stats[#spec.stats + 1] = Value(val:match("^([%a_]+)"))
	elseif key == "is" and val == "boe" then spec.boe = true
	elseif key == "is" then spec.upgrade = true
	elseif key == "lvl" or key == "level" then spec.lvl = val
	elseif key == "ilvl" or key == "itemlevel" then spec.ilvl = val
	end
end

local function SlotNoun(s, one)
	local sn = SLOT_NOUN[s]
	if sn then return one and sn[1] or sn[2] end
	return one and s or L["%s gear"]:format(s)
end

local function Joined(list, f, sep)
	local out = {}
	for i, v in ipairs(list) do out[i] = f(v) end
	return table.concat(out, sep)
end

-- the noun a spec says ("swords and axes", "plate boots", "helm upgrades"), or nil
local function Noun(spec)
	local types, slots, up = spec.types, spec.slots, spec.upgrade
	local sep = up and "/" or (" " .. L["and"] .. " ")
	local noun
	if #types == 1 and ARMOUR[types[1]] and #slots > 0 then
		noun = types[1] .. " " .. Joined(slots, function(s) return SlotNoun(s, up) end, sep)
	elseif #types > 0 then
		noun = Joined(types, function(t) return up and t or Plural(t) end, sep)
	elseif #slots > 0 then
		noun = Joined(slots, function(s) return SlotNoun(s, up) end, sep)
	end
	if up then noun = noun and L["%s upgrades"]:format(noun) or L["upgrades"] end
	return noun
end

-- the words before the noun: "rare or epic", "BoE"
local function Before(spec)
	local before = {}
	if #spec.quals > 0 then before[#before + 1] = table.concat(spec.quals, (" " .. L["or"] .. " ")) end
	if spec.boe then before[#before + 1] = L["BoE"] end
	return table.concat(before, " ")
end

-- a word's | parts, each a list of { key, value } (a part with no key takes the word's: "type:sword|axe"); nil for a
-- "not" (-x, !x: not said)
local function Alternatives(lw)
	if lw:find("^[-!]") then return nil end
	local key = lw:match("^(%a+):")
	local alts = {}
	for part in lw:gmatch("[^|]+") do
		local pieces = {}
		for atom in part:gmatch("[^&]+") do
			if atom:find("^[-!]") then
				pieces.skip = true -- (a "not" inside a part: that part isn't said)
			else
				local k, v = atom:match("^(%a+):(.*)$")
				if not k then k, v = key, atom end
				pieces[#pieces + 1] = { k or "", v }
			end
		end
		alts[#alts + 1] = pieces
	end
	return alts
end

-- are these rows items (their own, or what a recipe makes)?
local ITEM_KINDS = { items = true, loot = true, stored = true, reagent = true, gear = true, consumables = true, mats = true,
	lootlog = true, recipes = true }
local function AllItems(rows)
	local F = ns.Filters
	for _, e in ipairs(rows) do
		local o = rawget(e, "pipeOf") or e
		if not (ITEM_KINDS[o.kind] or o.itemID or (F and F.ItemOf and F.ItemOf(o))) then return false end
	end
	return true
end

function SH.Describe(query, rows)
	if type(query) ~= "string" then return nil end
	if rows and not AllItems(rows) then return nil end
	local spec, phrases = NewSpec(), nil
	for _, w in QueryWords(query) do
		local alts = Alternatives(ns.Lower(w))
		if alts and #alts == 1 then
			-- (one part: what it can say of it; other filters say nothing)
			for _, pc in ipairs(alts[1]) do if Says(pc[1], pc[2]) then Add(spec, pc[1], pc[2]) end end
		elseif alts and #alts > 1 then
			local same, every = alts[1][1] and alts[1][1][1], true
			for _, alt in ipairs(alts) do
				if alt.skip or #alt == 0 then every = false end
				for _, pc in ipairs(alt) do
					if not Says(pc[1], pc[2]) then every = false end
					if #alt ~= 1 or pc[1] ~= same then same = nil end
				end
			end
			if every and (same == "type" or same == "slot" or same == "q" or same == "quality") then
				for _, alt in ipairs(alts) do Add(spec, alt[1][1], alt[1][2]) end
			elseif every and not phrases then
				-- (each part its own: "rare swords and epic axes")
				phrases = {}
				for i, alt in ipairs(alts) do
					local sub = NewSpec()
					for _, pc in ipairs(alt) do Add(sub, pc[1], pc[2]) end
					local b, n = Before(sub), Noun(sub) or L["items"]
					phrases[i] = (b ~= "" and (b .. " ") or "") .. n
				end
			end
		end
	end
	local noun = phrases and table.concat(phrases, (" " .. L["and"] .. " ")) or Noun(spec)
	local before = Before(spec)
	if not noun and before == "" and #spec.stats == 0 and not spec.lvl and not spec.ilvl then return nil end
	noun = noun or L["items"]
	local text = before .. (before ~= "" and " " or "") .. noun
	if #spec.stats > 0 then text = L["%s with %s"]:format(text, table.concat(spec.stats, (" " .. L["and"] .. " "))) end
	if spec.lvl then text = text .. " " .. L["(level %s)"]:format(spec.lvl) end
	if spec.ilvl then text = text .. " " .. L["(item level %s)"]:format(spec.ilvl) end
	return ns.UpperFirst(text)
end

-- (rows whose list says itself all at once, `shareGroup(rows, query, maxLines, lineMax)` -> lines, the same function
-- on every row: your group's "Missing buffs: Fortitude (Cid), ...": that function, or nil)
local function OwnGroup(rows)
	local own = rows[1] and rows[1].shareGroup
	if type(own) ~= "function" then return nil end
	for _, e in ipairs(rows) do if e.shareGroup ~= own then return nil end end
	return own
end

--- What the rows are, said once before them: a chain's ("Mats for Thorium Belt"), the boss and place every loot row
--- shares ("Dropped by Lorgus Jett in Blackfathom Deeps"), the instance they all share ("Loot from Razorfen Kraul":
--- each then says only its boss), what the filters say they are ("Weapons from Razorfen Kraul"), else what the search
--- says of its NPCs ("Nearby innkeeper").
--- Second result: "source" when it's the whole loot source (each row's own then isn't repeated), "instance" when
--- only the instance. Rows whose list says it itself (`shareHeader(rows, what)` -> header, state, the same function on
--- every row: the loot log) get theirs, and the state goes to each row's `shareMember(e, state, base)`.
function SH.GroupHeader(rows, query)
	local first = rows[1]
	if not first then return nil end
	local group = OwnGroup(rows)
	if group then -- (its first line says what goes)
		local ok, lines = pcall(group, rows, query, 1, SH.LINE_MAX)
		if ok and type(lines) == "table" and type(lines[1]) == "string" then return lines[1] end
	end
	local ctx = SH.ChainText(first, "x")
	if ctx then
		for _, e in ipairs(rows) do if e.pipeRel ~= first.pipeRel or e.pipeFrom ~= first.pipeFrom then ctx = nil break end end
		if ctx then return ctx end
	end
	local what = SH.Describe(query, rows)
	-- (rows of one list that says it itself: the loot log's "Drops in Razorfen Downs", each row then the rest)
	local own = first.shareHeader
	if type(own) == "function" then
		for _, e in ipairs(rows) do if e.shareHeader ~= own then own = nil break end end
		if own then
			local ok, h, state = pcall(own, rows, what)
			if ok and type(h) == "string" and h ~= "" then return h, type(state) == "table" and state or {} end
		end
	end
	local src = SH.LootSource(first)
	if src then
		for _, e in ipairs(rows) do if SH.LootSource(e) ~= src then src = nil break end end
		if src then return what and (what .. " " .. src) or ns.UpperFirst(src), "source" end
		local _, inst = SH.LootWhere(first)
		for _, e in ipairs(rows) do
			local _, i = SH.LootWhere(e)
			if i ~= inst then inst = nil break end
		end
		if inst and inst ~= "" then return L["%s from %s"]:format(what or L["Loot"], inst), "instance" end
	end
	return SH.Context(query, first) or what
end

--- The chat lines for every row: "<header> (N): a, b, c" packed into lines of at most LINE_MAX characters (lineMax),
--- GROUP_LINES at most (maxLines); the rest counted on the last ("+5 more"). Each row as the chain or list says it:
--- "12x [Thorium Bar]".
function SH.GroupLines(rows, query, maxLines, lineMax)
	local ML, LM = maxLines or SH.GROUP_LINES, lineMax or SH.LINE_MAX -- (one line the game presses: SH.PressLine)
	rows = SH.GroupRows(rows)
	if #rows == 0 then return {} end
	local group = OwnGroup(rows)
	if group then
		local ok, lines, total = pcall(group, rows, query, ML, LM)
		if ok and type(lines) == "table" then return lines, total or #rows end
	end
	local header, lootHeader = SH.GroupHeader(rows, query)
	-- a row's text, worked out only when its turn comes: the rows only counted in "+N more" never are (an NPC's text
	-- sets the map pin it links: 100 of them moved your waypoint 100 times, to one that wasn't even sent)
	local function TextOf(e)
		local base = SH.BaseText(e)
		local t = (lootHeader or e.pipeRel == "uses") and base or WithSource(e, base, LM - 8)
		if type(lootHeader) == "table" and type(e.shareMember) == "function" and type(base) == "string" then
			local ok, x = pcall(e.shareMember, e, lootHeader, base)
			if ok and type(x) == "string" and x ~= "" then t = x end
		elseif lootHeader == "instance" and type(base) == "string" then
			-- (the instance is in the header: each says only who drops it)
			local boss = SH.LootWhere(e)
			if boss and boss ~= "" then
				t = base .. " (" .. (ns.Lower(boss):find("trash", 1, true) and L["trash"] or boss) .. ")"
			end
		end
		local _, chained = SH.ChainText(e, t)
		t = chained or t
		if type(t) == "string" and t ~= "" then
			if #t > LM then t = tostring(base) end
			if #t <= LM then return t end
		end
		return nil
	end
	-- (review, 0.53.6: a long search's header made a line the game refuses; cut, room left for the count and a row)
	if header then header = ns.Cut(header, LM - 20) end
	local head = header and (header .. " (" .. #rows .. "):") or nil
	local lines, line = {}, head
	local sent, skipped = 0, 0
	-- (the last line keeps room for "+N more", as long as the client's language says it)
	local moreRoom = #L["+%s more"]:format(#rows) + 1
	local function Room() return LM - (#lines == ML - 1 and moreRoom or 0) end
	for _, e in ipairs(rows) do
		local t = TextOf(e)
		if not t then
			skipped = skipped + 1 -- (nothing to say for it: not sent, not counted)
		else
			local joined = line and (line .. (line:sub(-1) == ":" and " " or ", ") .. t) or t
			if #joined <= Room() then
				line = joined
			else
				if line then lines[#lines + 1] = line end
				line = nil
				if #lines >= ML or #t > Room() then break end -- (a long one can't start the last line: counted)
				line = t
			end
			sent = sent + 1
		end
	end
	if line and #lines < ML then lines[#lines + 1] = line end
	local total = #rows - skipped
	-- (the header's count: the rows that went or are counted, not those with nothing to say; review, 0.53.6)
	if head and skipped > 0 and lines[1] and lines[1]:sub(1, #head) == head then
		lines[1] = header .. " (" .. total .. "):" .. lines[1]:sub(#head + 1)
	end
	local left = total - sent
	if left > 0 and #lines > 0 then
		local more = L["+%s more"]:format(left)
		if #lines[#lines] + #more + 1 <= LM then lines[#lines] = lines[#lines] .. " " .. more
		elseif #lines < ML then lines[#lines + 1] = more end
	end
	return lines, total
end

--- The items among the rows the client hasn't loaded yet: sent now, they'd go as plain names (no link). Item ids.
function SH.Unloaded(rows)
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local out = {}
	if not cached then return out end
	for _, e in ipairs(rows) do
		local o = rawget(e, "pipeOf") or e
		local id = tonumber(o.itemID or e.itemID)
		if id and Call(cached, id) == false then out[#out + 1] = id end
	end
	return out
end

-- (asked once each: the server answers in its own time; a fresh ask a minute later. Past PREFETCH_KEEP ids kept, the
-- ones asked over a minute ago are forgotten, as asking again is what they'd get anyway; then again once it doubles)
local asked, askedN, pruneAt = {}, 0, nil
SH.PREFETCH_MAX = 200
SH.PREFETCH_KEEP = 1000
function SH.AskedCount() return askedN end -- (tests: how many item ids are kept as asked)

--- Has the client load every item among the rows (">>>" typed, the menu's "All" lines shown), so their links are
--- there by the time they're sent. `grouped`: the rows are SH.GroupRows' already (the footer's, grouped once a list).
function SH.Prefetch(rows, grouped)
	local req = C_Item and C_Item.RequestLoadItemDataByID
	if not req then return 0 end
	local now, n = GetTime and GetTime() or 0, 0
	for _, id in ipairs(SH.Unloaded(grouped and rows or SH.GroupRows(rows))) do
		if n >= SH.PREFETCH_MAX then break end
		if not asked[id] or now - asked[id] > 60 then
			if not asked[id] then askedN = askedN + 1 end
			asked[id] = now
			Call(req, id)
			n = n + 1
		end
	end
	if askedN > (pruneAt or SH.PREFETCH_KEEP) then
		for id, at in pairs(asked) do
			if now - at > 60 then asked[id] = nil; askedN = askedN - 1 end
		end
		pruneAt = math.max(SH.PREFETCH_KEEP, askedN * 2)
	end
	return n
end

-- say, yell and numbered channels want a key press or click to send (outside instances): never sent later.
-- 0.45.16 (the player's .debug log: "All 37 to say" from the row menu, 6 lines, the game blocked all 6): not from
-- Terminal's code at all, even inside the press: only a line the game presses itself (SH.PressLine, one per press)
local NEEDS_PRESS = { SAY = true, YELL = true, CHANNEL = true }
SH.ONE_LINE = L["Say, yell and channels take one line per key press: Enter sends the first line, the rest counted."]

--- Is this a channel Terminal's code can't send to (say, yell, a numbered channel)?
function SH.Restricted(to) return type(to) == "table" and NEEDS_PRESS[to.chat or ""] == true end

--- Every row at once as ONE chat line the game presses ("/s Mats for Thorium Belt (12): a, b, +9 more"), within what
--- a macro runs (255 characters with the command), or nil.
function SH.PressLine(rows, to, query)
	if not (type(to) == "table" and to.cmd and SH.Searched(query)) then return nil end
	local max = (ns.Secure and ns.Secure.MACRO_MAX or 255) - #to.cmd - 1
	local lines = SH.GroupLines(rows, query, 1, max)
	return lines[1] and (to.cmd .. " " .. lines[1]) or nil
end

--- A menu chat line's macro: the row's line (SH.Macro), or every result's in one (`to.all`: say, yell, a channel).
function SH.ChatLine(e, to)
	if type(to) == "table" and to.all then return SH.PressLine(ns.UI and ns.UI.results or {}, to, to.query) end
	return SH.Macro(e, to)
end
SH.LINK_WAIT, SH.LINK_STEP = 3, 0.25 -- (seconds waited for items to load before sending without their links)

local function SendLines(rows, to, query, send)
	local lines = SH.GroupLines(rows, query)
	if #lines == 0 then return nil, L["Nothing to send."] end
	local n = 0
	for _, l in ipairs(lines) do
		local ok = pcall(send, l, to.chat, nil, to.target)
		if not ok then break end
		n = n + 1
	end
	ns:Trace(("share: sent %d of %d lines to %s"):format(n, #lines, tostring(to.label or to.chat)))
	if n == 0 then return nil, L["Couldn't send to %s."]:format(tostring(to.label or to.chat)) end
	return n
end

--- Sends every row's line to the channel `to` ({ chat, target, label }): from Terminal's own code, inside the key
--- press or click that asked (say and yell want one). Items the client hasn't loaded would go without their links
--- (a whole instance's loot): they're asked for, and party, raid, guild, instance and whispers wait for them (up to
--- LINK_WAIT s) before sending. Returns how many lines went (true when they'll go in a moment), or nil and why not.
local LOCKED = L["The game doesn't let addons send chat right now (in combat in an instance)."]
local Locked = ns.ChatLocked
local waiting -- (a send waiting for its items to load: another Enter meanwhile doesn't send them twice)

-- (0.45.16, the player: ">>> party" with nothing searched sent every recent pick, with no word of what they were)
SH.NO_SEARCH = L["Search for something first: with nothing searched there's nothing to say what they are."]
--- Was something searched (the words before ">>", or the menu's query)? Every result at once needs it.
function SH.Searched(query) return type(query) == "string" and query:find("%S") ~= nil end

--- The chat type the game takes for `chat` now: party or raid when your only group is one an instance made (a
--- battleground, the dungeon or raid finder) is instance chat, as the game's chat box switches it itself
--- (ChatFrameEditBox's UpdateHeader). (0.49.2, review: ">>> raid" there was refused while the trace said sent.)
function SH.ChatType(chat)
	local home, inst = _G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE
	if not (home and inst) or (chat ~= "PARTY" and chat ~= "RAID") then return chat end
	local test = chat == "RAID" and _G.IsInRaid or _G.IsInGroup
	if type(test) ~= "function" then return chat end
	if not Call(test, home) and Call(test, inst) then return "INSTANCE_CHAT" end
	return chat
end

function SH.SendAll(rows, to, query)
	local send = ns.ChatSender()
	if not SH.Searched(query) then return nil, SH.NO_SEARCH end
	if SH.Restricted(to) then return nil, SH.ONE_LINE end -- (the game blocks them from addon code: SH.PressLine)
	if not (to and to.chat and send) then -- (as the prompt says it: Activate's NoChannel)
		return nil, L["Say where to send them: %s party, guild, raid, say, yell, officer, instance, whisper <name>"]:format(">>>")
	end
	local chat = SH.ChatType(to.chat)
	if chat ~= to.chat then
		ns:Trace(("share: %s goes to instance chat (your only group is the instance's)"):format(to.chat))
		local copy = {}
		for k, v in pairs(to) do copy[k] = v end
		copy.chat = chat
		to = copy
	end
	if Locked() then return nil, LOCKED end
	if waiting then return nil, L["Still sending the last ones: a moment."] end
	rows = SH.GroupRows(rows) -- (kept: the list on screen changes while waiting)
	if #rows == 0 then return nil, L["Nothing to send."] end
	local missing = SH.Unloaded(rows)
	-- (say, yell and channels never get here: SH.Restricted above)
	if #missing == 0 or not (C_Timer and C_Timer.After) then
		if #missing > 0 then ns:Trace("share: " .. #missing .. " items not loaded yet go without links") end
		return SendLines(rows, to, query, send)
	end
	local req = C_Item and C_Item.RequestLoadItemDataByID
	for _, id in ipairs(missing) do if req then Call(req, id) end end
	ns:Trace("share: waiting for " .. #missing .. " items to load before sending")
	local waited, mine = 0, {}
	waiting = mine
	local function Try()
		if waiting ~= mine then return end
		waited = waited + SH.LINK_STEP
		local left = #SH.Unloaded(rows)
		if left > 0 and waited < SH.LINK_WAIT then C_Timer.After(SH.LINK_STEP, Try) return end
		waiting = nil
		-- (the lockdown may have begun while waiting: an encounter pulled)
		if Locked() then ns:Print(LOCKED) return end
		if left > 0 then ns:Trace("share: " .. left .. " items still not loaded: sent without links") end
		local n, why = SendLines(rows, to, query, send)
		if not n then ns:Print(why) end
	end
	C_Timer.After(SH.LINK_STEP, Try)
	return true
end
SH.StopWaiting = function() waiting = nil end -- (tests)

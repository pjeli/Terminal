local ns = select(2, ...)

-- @drop (@dropped, @drops, @lootlog): a running list of what dropped and who got it, kept across sessions (the game's own loot
-- history forgets). Only what's worth rolling for: green and better (LL.MIN_QUALITY). Fed by:
--   - the loot lines in chat (CHAT_MSG_LOOT): "You receive loot: [x]", "Bob receives loot: [x]x2", "Bob won: [x]",
--     matched with the game's own format strings (LOOT_ITEM..., LOOT_ROLL_WON...), so any language works;
--   - the game's loot history when it has one (C_LootHistory: retail's per-encounter drops with their winner), for the
--     boss a drop came from.
-- Newest first. Enter shows the item in your bags (when you have it), Shift+Enter puts its link in the chat box.

local LL = {}
ns.LootLog = LL

LL.MAX = 500 -- (entries kept: the oldest go)
LL.SAME = 10 -- seconds: the same item to the same player twice in this time is one drop (a roll's win, then its loot line)

local Safe = ns.Safe

local function Now() return (_G.time and _G.time()) or 0 end
local function Log()
	if not ns.db then return nil end
	if type(ns.db.lootLog) ~= "table" then ns.db.lootLog = {} end
	return ns.db.lootLog
end

-- a format string of the game's ("%s receives loot: %sx%d.") as an anchored pattern, and for each capture the format
-- argument it is ("%2$s" in some languages swaps them)
local MAGIC = { ["("] = true, [")"] = true, ["."] = true, ["+"] = true, ["-"] = true, ["*"] = true, ["?"] = true,
	["["] = true, ["]"] = true, ["^"] = true, ["$"] = true, ["%"] = true }
local function Pattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local out, args, i, nextArg = { "^" }, {}, 1, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local num, kind, len = fmt:match("^%%(%d)%$([sd])()", i)
			if not num then kind, len = fmt:match("^%%([sd])()", i) end
			if kind then
				out[#out + 1] = kind == "s" and "(.-)" or "(%d+)"
				args[#args + 1] = tonumber(num) or nextArg
				nextArg = nextArg + 1
				i = len
			else
				out[#out + 1] = "%%"
				i = i + ((fmt:sub(i + 1, i + 1) == "%") and 2 or 1)
			end
		else
			out[#out + 1] = MAGIC[c] and ("%" .. c) or c
			i = i + 1
		end
	end
	out[#out + 1] = "$"
	return table.concat(out), args
end
LL.Pattern = Pattern -- (tests)

-- { global string, who (1: the first %s; "me": you), link capture, count capture } in the order they're tried
-- (the "multiple" forms first: "x%d" would otherwise be part of the link)
LL.FORMS = {
	{ "LOOT_ITEM_SELF_MULTIPLE", "me", 1, 2 }, { "LOOT_ITEM_SELF", "me", 1 },
	{ "LOOT_ITEM_MULTIPLE", 1, 2, 3 }, { "LOOT_ITEM", 1, 2 },
	{ "LOOT_ROLL_YOU_WON", "me", 1 }, { "LOOT_ROLL_WON", 1, 2 },
}
local patterns
local function Patterns()
	if patterns then return patterns end
	patterns = {}
	for _, f in ipairs(LL.FORMS) do
		local p, args = Pattern(_G[f[1]])
		if p then patterns[#patterns + 1] = { p = p, args = args, who = f[2], link = f[3], count = f[4], roll = f[1]:find("ROLL") ~= nil } end
	end
	return patterns
end
LL.ResetPatterns = function() patterns = nil end -- (tests)

local function Me() return ns.CharacterName and ns.CharacterName() or (UnitName and UnitName("player")) or "you" end

--- A chat loot line read: link, who, count; nil when it isn't one.
function LL.Parse(msg)
	if type(msg) ~= "string" or (ns.Secret and ns.Secret(msg)) then return nil end
	for _, f in ipairs(Patterns()) do
		local got = { msg:match(f.p) }
		if #got > 0 then
			local caps = {} -- (by format argument)
			for k, v in ipairs(got) do caps[f.args[k] or k] = v end
			local link = caps[f.link]
			if type(link) == "string" and link:find("|Hitem:", 1, true) then
				local who = f.who == "me" and Me() or caps[f.who]
				return link, who, tonumber(f.count and caps[f.count]) or 1, f.roll and "roll" or "loot"
			end
		end
	end
end

-- Only what's worth rolling for is kept (the player's call, 0.43.26): uncommon (green) and better. Grey junk and
-- white trade goods, cloth and quest items aren't logged.
LL.MIN_QUALITY = 2
local LINK_COLOURS = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5,
	e6cc80 = 6, ["00ccff"] = 7 }

--- An item's quality from its link (the colour it's drawn in: "|cff1eff00" or the newer "|cnIQ2:"), else the game's.
function LL.Quality(link, id)
	if type(link) == "string" then
		local q = link:match("|cnIQ(%d+):")
		if q then return tonumber(q) end
		local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
		if hex and LINK_COLOURS[hex:lower()] then return LINK_COLOURS[hex:lower()] end
	end
	local get = C_Item and C_Item.GetItemQualityByID
	local q = id and get and Safe(get, id)
	return type(q) == "number" and q or nil
end

--- Worth keeping: green or better (an item whose quality can't be told is kept).
function LL.Worth(link, id)
	local q = LL.Quality(link, id)
	return q == nil or q >= LL.MIN_QUALITY
end

--- Adds a drop (or fills in one just added: the same item to the same player a moment ago).
-- has this drop been told this way already? (src: the ways it was told, "roll+loot"; "both" from before 0.44.10)
local function Told(e, src)
	local s = e.src
	return s == "both" or s == src or (type(s) == "string" and s:find(src, 1, true) ~= nil)
end

--- Logs a drop: its link, who got it, how many, the boss (if known) and how it was told ("loot" line, "roll" win,
--- "history"). `drop`: the loot history's own key for it (encounter:list), told again on every update.
function LL.Add(link, who, count, from, src, drop)
	local log = Log()
	if not log or type(link) ~= "string" then return nil end
	local id = tonumber(link:match("item:(%d+)"))
	if not id or not LL.Worth(link, id) then return nil end
	local t = Now()
	who = type(who) == "string" and who ~= "" and who or "?"
	src = src or "loot"
	for i = 1, math.min(#log, 20) do
		local e = log[i]
		if drop and e.drop == drop then return e end -- (the loot history updated again for a drop logged already)
		-- (one drop told two ways: a roll's win or the loot history, then its loot line; told the same way twice, it's
		-- two drops: two loot lines, two wins)
		if e.id == id and e.who == who and t - (e.t or 0) <= LL.SAME and not Told(e, src) then
			if from and not e.from then e.from = from end
			if drop and not e.drop then e.drop = drop end
			e.src = (e.src or "loot") .. "+" .. src
			return e
		end
	end
	local zone = _G.GetRealZoneText and Safe(_G.GetRealZoneText)
	local e = { t = t, id = id, link = link, who = who, n = count and count > 1 and count or nil,
		zone = type(zone) == "string" and zone ~= "" and zone or nil, from = from, src = src, drop = drop }
	table.insert(log, 1, e)
	for i = #log, LL.MAX + 1, -1 do log[i] = nil end
	local p = ns.providers.lootlog
	if p then p._dirty = true end
	return e
end

-- the game's loot history (retail): a drop and its winner, with the boss it came from
local function FromHistory(encounterID, lootListID)
	local H = _G.C_LootHistory
	if not (H and H.GetSortedInfoForDrop) then return end
	local drop = Safe(H.GetSortedInfoForDrop, encounterID, lootListID)
	if type(drop) ~= "table" or type(drop.itemHyperlink) ~= "string" then return end
	local winner = type(drop.winner) == "table" and drop.winner.playerName or nil
	if winner and drop.winner.isSelf then winner = Me() end -- (the chat's line for it names you with your surname)
	if not winner then return end -- (still being rolled for: the win comes in a later update)
	local enc = H.GetInfoForEncounter and Safe(H.GetInfoForEncounter, encounterID)
	local from = type(enc) == "table" and type(enc.encounterName) == "string" and enc.encounterName or nil
	if ns.Secret and (ns.Secret(winner) or ns.Secret(drop.itemHyperlink)) then return end
	LL.Add(drop.itemHyperlink, winner, 1, from, "history", tostring(encounterID) .. ":" .. tostring(lootListID))
end
LL.FromHistory = FromHistory

function LL.OnEvent(event, ...)
	if event == "CHAT_MSG_LOOT" then
		local link, who, n, src = LL.Parse((...))
		if link then LL.Add(link, who, n, nil, src) end
	elseif event == "LOOT_HISTORY_UPDATE_DROP" then
		FromHistory(...)
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_LOOT")
pcall(ev.RegisterEvent, ev, "LOOT_HISTORY_UPDATE_DROP")
ev:SetScript("OnEvent", function(_, event, ...) pcall(LL.OnEvent, event, ...) end)

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------

--- "just now", "5 min ago", "3 h ago", "2 d ago"
function LL.Ago(t)
	local d = math.max(0, Now() - (t or 0))
	if d < 60 then return "just now" end
	if d < 3600 then return math.floor(d / 60) .. " min ago" end
	if d < 86400 then return math.floor(d / 3600) .. " h ago" end
	return math.floor(d / 86400) .. " d ago"
end

local function NameOf(link) return link:match("%[(.-)%]") or link end
local function Show(e)
	if ns.Bags and ns.Bags.ShowItem and ns.Bags.ShowItem(e.itemID, e.link, e.name) then return end
	ns:Output({ e.link .. ": " .. e.detail }) -- (not carried: where it dropped and who got it, in your chat window)
end
local function LinkOf(e) return e.link end
local NeverOpen = ns.Never
local CHATBOX = ns.ChatBoxSpec(LinkOf) -- (shared by every row: entry functions are never made per row)
local function ToChat(e) ns.LinkInChat(e.link) end
local function Who(who)
	local me = Me()
	return (who == me or who == (UnitName and UnitName("player"))) and "you" or who
end

ns:RegisterProvider("lootlog", {
	label = "Loot log",
	color = "ffe6b85c",
	aliases = { "drop", "dropped", "drops", "lootlog", "looted", "loothistory" },
	explicit = true, -- (only with @drop, or Simple mode's Loot log)
	refreshOnOpen = 60, -- (the "5 min ago" moves on: rebuilt on open when a minute old; new entries mark it dirty)
	collect = function()
		local out, log = {}, Log() or {}
		-- (drops kept before 0.43.26 that aren't worth rolling for go now)
		for i = #log, 1, -1 do
			local d = log[i]
			if type(d) ~= "table" or not LL.Worth(d.link, d.id) then table.remove(log, i) end
		end
		local n = #log
		local getIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
		for i, d in ipairs(log) do
			if type(d) == "table" and type(d.link) == "string" and d.id then
				local who = Who(d.who or "?")
				local parts = { who, LL.Ago(d.t) }
				if d.from then parts[#parts + 1] = d.from end
				if d.zone then parts[#parts + 1] = d.zone end
				out[#out + 1] = {
					looter = d.who, mine = who == "you" or nil,
					key = (d.t or 0) .. ":" .. d.id .. ":" .. tostring(d.who),
					name = NameOf(d.link) .. (d.n and (" x" .. d.n) or ""),
					itemID = d.id, link = d.link,
					icon = getIcon and Safe(getIcon, d.id) or nil,
					color = ns.QualityHex(LL.Quality(d.link, d.id)), -- (its quality's colour, as items show)
					detail = table.concat(parts, "  ·  "),
					text = table.concat({ who, d.who or "", d.from or "", d.zone or "", "loot drop looted" }, " "),
					_rank = (n - i + 1) / (n + 1) * 0.99, -- (newest first among equal matches)
					activate = Show,
					secondarySecure = CHATBOX, secondaryIsOpen = NeverOpen, secondary = ToChat,
				}
			end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- In plain words: "what dropped", "what drops did we get", "what did i loot", "what did bob get"
----------------------------------------------------------------------

local ASKS = {}
for w in ([[what which did do we i me my our us get got gotten have has had drop dropped drops loot looted loots
	lootlog log won win recent recently last latest lately today tonight so far any anything anyone items item show list
	the from that this run boss bosses all see were was been is are new]]):gmatch("%S+") do ASKS[w] = true end
local CUES = { drop = true, dropped = true, drops = true, loot = true, looted = true, loots = true, lootlog = true }
-- (besides a loot word, one of these must be there: "boss loot", "the loot", "item drops" stay searches)
local ASKING = { what = true, which = true, did = true, my = true, our = true, we = true, i = true, me = true, us = true,
	recent = true, recently = true, last = true, latest = true, lately = true, today = true, tonight = true, lootlog = true,
	got = true, won = true, new = true, log = true }

-- every looter's name in the log, lowercased, without punctuation, whole and without its realm ("bob-stormrage" ->
-- "bob stormrage" and "bob"); rebuilt only when the log changed
local names, namesFor
local function Plainish(s) return (ns.Lower(s):gsub("[%p]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function LooterNames(log)
	local mark = #log .. ":" .. tostring(log[1] and log[1].t)
	if namesFor == mark then return names end
	names, namesFor = {}, mark
	for _, d in ipairs(log) do
		local who = type(d.who) == "string" and d.who
		if who and not names[who] then
			local whole = Plainish(who)
			local short = Plainish((who:match("^([^%-]+)%-") or who))
			if not names[whole] then names[whole] = who end
			if not names[short] then names[short] = who end
			local first = short:match("^(%S+)")
			if first and not names[first] then names[first] = who end
		end
	end
	return names
end
local GOT = { get = true, got = true, gotten = true, won = true, win = true }

--- A loot question in plain words: { who = "me" / a looter's name / nil (everyone) }, else nil. The whole line must be
--- question words, with a word about loot ("dropped", "loot") or "what did <someone> get"; one name from the log may
--- stand in it ("what did bob get").
function LL.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./!%-]") then return nil end
	local has, n, other = {}, 0, {}
	for w in ns.Lower(text):gsub("[%p]", " "):gmatch("%S+") do
		if ASKS[w] then has[w] = true else other[#other + 1] = w end
		n = n + 1
	end
	if n < 2 then return nil end
	local cue = false
	for w in pairs(CUES) do if has[w] then cue = true end end
	local got = false
	for w in pairs(GOT) do if has[w] then got = true end end
	if not cue and not (got and (has.what or has.did)) then return nil end
	local asking = false
	for w in pairs(ASKING) do if has[w] then asking = true break end end
	if not asking and #other == 0 then return nil end
	local who
	if #other > 0 then
		-- (the other words must be someone in the log: "what did plamen warr get", "what did bob stormrage get")
		who = LooterNames(Log() or {})[table.concat(other, " ")]
		if not who then return nil end
	elseif (has.i or has.me or has.my) and not (has.we or has.our or has.us) then
		who = "me"
	end
	return { who = who }
end

--- The loot log's rows a question wants, newest first, and the footer's note.
function LL.Answer(q)
	local p = ns.providers.lootlog
	local rows = {}
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if not q.who or (q.who == "me" and e.mine) or (q.who ~= "me" and e.looter == q.who) then rows[#rows + 1] = e end
	end
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local note = (q.who == "me" and "Your drops, newest first") or (q.who and (q.who .. "'s drops, newest first"))
		or "Drops, newest first"
	if #rows == 0 then
		note = (#(Log() or {}) == 0) and "Nothing looted yet" or (q.who == "me" and "Nothing looted by you yet")
			or "Nothing looted by them yet"
	end
	return rows, note
end

ns:RegisterCommand("lootlog", {
	desc = "The loot log: what dropped and who got it; .lootlog clear forgets it",
	complete = function() return { { "clear", "forget every drop" } } end,
	run = function(args)
		if strtrim(args or ""):lower() == "clear" then
			if ns.db then ns.db.lootLog = {} end
			local p = ns.providers.lootlog
			if p then p._dirty = true end
			return { "Loot log cleared." }
		end
		local log = Log() or {}
		local lines = { ("Loot log: %d drops kept (the newest %d). %s"):format(#log, LL.MAX,
			ns.Said("Ask \"what dropped\", or type an item's name.", "Search it: @drop <words>")) }
		for i = 1, math.min(10, #log) do
			local d = log[i]
			lines[#lines + 1] = ("  %s%s  %s  %s"):format(d.link, d.n and (" x" .. d.n) or "", Who(d.who or "?"), LL.Ago(d.t))
		end
		return lines
	end,
})

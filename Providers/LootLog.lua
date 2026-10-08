local ns = select(2, ...)

-- @drop (@dropped, @drops, @lootlog): a running list of what dropped and who got it, kept across sessions (the game's own loot
-- history forgets). Fed by:
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

--- Adds a drop (or fills in one just added: the same item to the same player a moment ago).
function LL.Add(link, who, count, from, src)
	local log = Log()
	if not log or type(link) ~= "string" then return nil end
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return nil end
	local t = Now()
	who = type(who) == "string" and who ~= "" and who or "?"
	for i = 1, math.min(#log, 20) do
		local e = log[i]
		-- (one drop told twice: a roll's win or the loot history, then its loot line; two loot lines are two drops)
		if e.id == id and e.who == who and t - (e.t or 0) <= LL.SAME and e.src ~= (src or "loot") then
			if from and not e.from then e.from = from end
			e.src = "both"
			return e
		end
	end
	local zone = _G.GetRealZoneText and Safe(_G.GetRealZoneText)
	local e = { t = t, id = id, link = link, who = who, n = count and count > 1 and count or nil,
		zone = type(zone) == "string" and zone ~= "" and zone or nil, from = from, src = src or "loot" }
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
	LL.Add(drop.itemHyperlink, winner, 1, from, "history")
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
	ns:Print(e.link .. ": " .. e.detail)
end
local function LinkOf(e) return e.link end
local function NeverOpen() return false end
local function Who(who)
	local me = Me()
	return (who == me or who == (UnitName and UnitName("player"))) and "you" or who
end

ns:RegisterProvider("lootlog", {
	label = "Loot log",
	color = "ffe6b85c",
	aliases = { "drop", "dropped", "drops", "lootlog", "looted", "loothistory" },
	explicit = true, -- (only with @drop, or Simple mode's Loot log)
	refreshOnOpen = true, -- (the "5 min ago" moves on)
	collect = function()
		local out, log = {}, Log() or {}
		local n = #log
		local getIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
		for i, d in ipairs(log) do
			if type(d) == "table" and type(d.link) == "string" and d.id then
				local who = Who(d.who or "?")
				local parts = { who, LL.Ago(d.t) }
				if d.from then parts[#parts + 1] = d.from end
				if d.zone then parts[#parts + 1] = d.zone end
				out[#out + 1] = {
					key = (d.t or 0) .. ":" .. d.id .. ":" .. tostring(d.who),
					name = NameOf(d.link) .. (d.n and (" x" .. d.n) or ""),
					itemID = d.id, link = d.link,
					icon = getIcon and Safe(getIcon, d.id) or nil,
					detail = table.concat(parts, "  ·  "),
					text = table.concat({ who, d.who or "", d.from or "", d.zone or "", "loot drop looted" }, " "),
					_rank = (n - i + 1) / (n + 1) * 0.99, -- (newest first among equal matches)
					activate = Show,
					secondarySecure = ns.ChatBoxSpec(LinkOf), secondaryIsOpen = NeverOpen,
					secondary = function(e) ns.LinkInChat(e.link) end,
				}
			end
		end
		return out
	end,
})

ns:RegisterCommand("lootlog", {
	desc = "The loot log: what dropped and who got it (search it with @drop); .lootlog clear forgets it",
	complete = function() return { { "clear", "forget every drop" } } end,
	run = function(args)
		if strtrim(args or ""):lower() == "clear" then
			if ns.db then ns.db.lootLog = {} end
			local p = ns.providers.lootlog
			if p then p._dirty = true end
			return { "Loot log cleared." }
		end
		local log = Log() or {}
		local lines = { ("Loot log: %d drops kept (the newest %d). Search it: @drop <words>"):format(#log, LL.MAX) }
		for i = 1, math.min(10, #log) do
			local d = log[i]
			lines[#lines + 1] = ("  %s%s  %s  %s"):format(d.link, d.n and (" x" .. d.n) or "", Who(d.who or "?"), LL.Ago(d.t))
		end
		return lines
	end,
})

local ns = select(2, ...)
local L = ns.L

-- Lockouts (@lockout, @lockouts, @saved; Simple mode: "my lockouts", "raid lockouts", "am i saved", "raid id", under
-- Character): the raids and dungeons each of your characters is saved to, with how many bosses are down and when each
-- resets. Yours are read from the game (GetSavedInstanceInfo, as the Raid Info window reads them, and the world bosses);
-- your alts' are as Terminal last saw them (db.lockouts, by GUID): an alt shows up once you've logged in on it with
-- Terminal, and a lockout that has reset since is dropped (its reset time is kept as a time of day, not a countdown).
--
--   Enter        the lockout in chat (only you see it), with its bosses when the game names them
--   Shift+Enter  into the chat box: your own as the game's lockout link (as Shift-click in the Raid Info window), an
--                alt's as words ("Plamen Pally: Molten Core 6/10, resets in 3 d 4 h")

local LK = {}
ns.Lockouts = LK

local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower

LK.ASK_AGAIN = 60 -- (s: the game is asked again for your lockouts at most this often when the list is opened)
LK.BOSS_WAIT = 3 -- (s after a boss dies before asking: the save comes a moment later)

local Now = ns.Now
local MyKey = ns.PlayerGUID

local function Chars()
	if not ns.db then return nil end
	if type(ns.db.lockouts) ~= "table" then ns.db.lockouts = {} end
	return ns.db.lockouts
end

local function Dirty() ns:Changed("lockouts") end

--- Asks the game for your lockouts (it answers with UPDATE_INSTANCE_INFO); at most every `again` seconds when given.
function LK.Ask(again)
	local t = GetTime and GetTime() or 0
	if again and LK.askedAt and t - LK.askedAt < again then return false end
	LK.askedAt = t
	if _G.RequestRaidInfo then pcall(_G.RequestRaidInfo) end
	return true
end

--- The bosses of a saved instance, as the game names them ({ { name, killed } }), or nil when it doesn't.
local function Bosses(i, total)
	local get = _G.GetSavedInstanceEncounterInfo
	if not get or not total or total <= 0 then return nil end
	local out = {}
	for j = 1, math.min(total, 40) do
		local name, _, killed = Safe(get, i, j)
		name = Str(name)
		if name then out[#out + 1] = { name, killed == true } end
	end
	return #out > 0 and out or nil
end

--- Your character's lockouts as the game says them now: { { name, id, reset (a time), diff, isRaid, players, done,
--- total, extended, bosses, world, index } }. Expired ones (shown greyed in the Raid Info window) are left out.
function LK.ReadMine(now)
	now = now or Now()
	local out = {}
	local n = Num(Safe(_G.GetNumSavedInstances)) or 0
	for i = 1, n do
		local name, id, reset, _, locked, extended, _, isRaid, players, diffName, total, done = Safe(_G.GetSavedInstanceInfo, i)
		name, reset = Str(name), Num(reset)
		if name and reset and (locked == true or extended == true) then
			total, done = Num(total), Num(done)
			out[#out + 1] = {
				name = name, id = Num(id) or Str(id), reset = now + reset, diff = Str(diffName), isRaid = isRaid == true,
				players = Num(players), done = done, total = (total and total > 0) and total or nil,
				extended = extended == true or nil, bosses = Bosses(i, total), index = i,
			}
		end
	end
	local w = Num(Safe(_G.GetNumSavedWorldBosses)) or 0
	for i = 1, w do
		local name, id, reset = Safe(_G.GetSavedWorldBossInfo, i)
		name, reset = Str(name), Num(reset)
		if name and reset then
			out[#out + 1] = { name = name, id = Num(id), reset = now + reset, isRaid = true, world = true, index = i }
		end
	end
	return out
end

--- Writes down your character's lockouts (on the game's every answer).
--- `quiet`: from the list's own read (no change to tell: review, 0.53.6, every read marked the list changed again,
--- dotting other tabs and searching an open list again).
function LK.Record(quiet)
	local key, chars = MyKey(), Chars()
	if not (key and chars) then return nil end
	local list = LK.ReadMine()
	local realm = Str(Safe(GetRealmName))
	chars[key] = {
		name = ns.CharacterName() or Str(Safe(UnitName, "player")) or L["You"], realm = realm,
		class = Str(select(2, Safe(UnitClass, "player"))), t = Now(), list = list,
	}
	-- (the index is the game's for this session only: not kept for later)
	for _, l in ipairs(list) do l.index = nil end
	if not quiet then Dirty() end
	return chars[key]
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

--- Seconds left said with two parts: "3 d 4 h", "5 h 20 min", "12 min".
function LK.Left(s)
	s = math.max(0, math.floor(tonumber(s) or 0))
	if s >= 86400 then return L["%d d %d h"]:format(math.floor(s / 86400), math.floor((s % 86400) / 3600)) end
	if s >= 3600 then return L["%d h %d min"]:format(math.floor(s / 3600), math.floor((s % 3600) / 60)) end
	return L["%d min"]:format(math.max(1, math.floor(s / 60)))
end

local GREY = "|cff9d9d9d"

-- "6/10 bosses", "world boss", "saved" (no count known)
local function Progress(e)
	if e.world then return L["world boss"] end
	if e.total then return L["%d/%d bosses"]:format(e.done or 0, e.total) end
	return L["saved"]
end

local function Summary(e, now)
	return L["%s, resets in %s"]:format(Progress(e), LK.Left((e.resetAt or 0) - (now or Now())))
end

-- your own lockout's index in the game's list now (the list moves as lockouts come and go): by its id and name
local function IndexNow(e)
	local n = Num(Safe(_G.GetNumSavedInstances)) or 0
	for i = 1, n do
		local name, id = Safe(_G.GetSavedInstanceInfo, i)
		if Str(name) == e.name and (e.lockID == nil or (Num(id) or Str(id)) == e.lockID) then return i end
	end
end

--- What's sent: your own lockout as the game's link (Shift-click in the Raid Info window gives the same), else words.
local function ShareText(e)
	if e.mine and not e.world and _G.GetSavedInstanceChatLink then
		local i = IndexNow(e)
		local link = i and Str(Safe(_G.GetSavedInstanceChatLink, i))
		if link then return link end
	end
	return e.who .. ": " .. e.name .. (e.diff and (" (" .. e.diff .. ")") or "") .. " " .. Summary(e)
end

local list -- (the last collect's rows)

local function Line(e, now)
	return "  " .. (e.color or "") .. e.who .. (e.color and "|r" or "") .. ":  " .. e.name
		.. (e.diff and (" " .. GREY .. "(" .. e.diff .. ")|r") or "") .. "  " .. Summary(e, now)
end

--- Every lockout of every character, for chat (.lockouts).
function LK.Lines()
	local out, now = {}, Now()
	for _, e in ipairs(list or {}) do out[#out + 1] = Line(e, now) end
	return out
end

local function Show(e)
	local now = Now()
	local lines = { Line(e, now) }
	if e.bosses then
		local down, up = {}, {}
		for _, b in ipairs(e.bosses) do if b[2] then down[#down + 1] = b[1] else up[#up + 1] = b[1] end end
		if #down > 0 then lines[#lines + 1] = "    " .. L["Down: %s"]:format(table.concat(down, ", ")) end
		if #up > 0 then lines[#lines + 1] = "    " .. L["Still up: %s"]:format(table.concat(up, ", ")) end
	end
	ns:Output(lines)
end
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end
local CHATBOX = ns.ChatBoxSpec(ShareText)

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(e.who .. (e.mine and (" " .. L["(you)"]) or ""), 1, 1, 1)
	if e.diff then t:AddLine(e.diff .. (e.players and (ns.DETAIL_SEP .. L["%d players"]:format(e.players)) or ""), 0.8, 0.8, 0.8) end
	t:AddDoubleLine(L["Bosses"], Progress(e), 1, 1, 1, 1, 1, 1)
	t:AddDoubleLine(L["Resets in"], LK.Left((e.resetAt or 0) - Now()), 1, 1, 1, 1, 1, 1)
	if e.extended then t:AddLine(L["Extended"], 0.4, 0.8, 1) end
	for _, b in ipairs(e.bosses or {}) do
		if b[2] then t:AddDoubleLine(b[1], L["defeated"], 0.6, 0.6, 0.6, 1, 0.3, 0.3)
		else t:AddDoubleLine(b[1], L["still up"], 1, 1, 1, 0.3, 1, 0.3) end
	end
	if not e.mine then t:AddLine(L["As of %s"]:format(ns.Ago(Now() - (e.seen or 0))), 0.6, 0.6, 0.6) end
	-- (your world boss has no link: words, as ShareText sends; 0.49.2, review)
	t:AddLine((e.mine and not e.world) and L["Enter: in chat    Shift+Enter: its link in the chat box"]
		or L["Enter: in chat    Shift+Enter: put it in the chat box"], 0.6, 0.6, 0.6, true)
end

local ICON, ICON_WORLD = "Interface\\Icons\\INV_Misc_Key_14", "Interface\\Icons\\INV_Misc_Head_Dragon_01"

local function Row(key, c, l, mine, who, now)
	local e = {
		key = key .. ":" .. tostring(l.id or l.name) .. ":" .. tostring(l.diff or ""), name = l.name, who = who, mine = mine or nil,
		lockID = l.id, resetAt = l.reset, diff = l.diff, isRaid = l.isRaid, players = l.players, done = l.done,
		total = l.total, extended = l.extended, bosses = l.bosses, world = l.world, seen = c.t,
		holders = { { who = who, mine = mine or nil } }, -- (on:/who: name the character)
		icon = l.world and ICON_WORLD or ICON, color = l.done and l.total and l.done >= l.total and "|cff9d9d9d" or nil,
		tooltip = Tooltip, activate = Show,
		secondary = ToChatBox, secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = ShareText,
	}
	local words = { "lockout saved instance", l.isRaid and "raid" or "dungeon", l.world and "world boss" or "",
		Lower(l.diff or ""), Lower(who), mine and "you me mine" or "alt alts" }
	for _, b in ipairs(l.bosses or {}) do words[#words + 1] = Lower(b[1]) end
	e.text = table.concat(words, " ")
	local d = { Progress(e), L["resets in %s"]:format(LK.Left(l.reset - now)) }
	if l.diff then d[#d + 1] = l.diff end
	if not mine then d[#d + 1] = (ns.ClassHex(c.class) or "") .. who .. "|r" end
	e.detail = table.concat(d, ns.DETAIL_SEP)
	return e
end

function LK.Collect()
	local chars, myKey, now = Chars() or {}, MyKey(), Now()
	local myRealm = Str(Safe(GetRealmName))
	-- (yours afresh, as the game says them now: only once it has answered this session, else an empty list read before its
	-- answer came would replace what was kept)
	if myKey and LK.answered then LK.Record(true) end
	local rows = {}
	local function Add(key, c, mine)
		if type(c) ~= "table" or type(c.list) ~= "table" then return end
		local who = c.name or "?"
		if c.realm and myRealm and c.realm ~= myRealm then who = who .. "-" .. c.realm end
		local kept = {}
		for _, l in ipairs(c.list) do
			if type(l) == "table" and type(l.reset) == "number" and l.reset > now then kept[#kept + 1] = l end -- (reset since: gone)
		end
		c.list = kept
		table.sort(kept, function(a, b)
			if (a.isRaid and true or false) ~= (b.isRaid and true or false) then return a.isRaid == true end
			if a.reset ~= b.reset then return a.reset < b.reset end
			return a.name < b.name
		end)
		for _, l in ipairs(kept) do rows[#rows + 1] = Row(key, c, l, mine, who, now) end
	end
	if myKey then Add(myKey, chars[myKey], true) end
	local alts = {}
	for key, c in pairs(chars) do
		if key ~= myKey and type(c) == "table" then alts[#alts + 1] = { key, c } end
	end
	table.sort(alts, function(a, b) return tostring(a[2].name) < tostring(b[2].name) end)
	for _, a in ipairs(alts) do Add(a[1], a[2], false) end
	ns.RankInOrder(rows) -- (this order among equal matches)
	list = rows
	LK.Ask(LK.ASK_AGAIN) -- (the game's answer, UPDATE_INSTANCE_INFO, marks the list changed)
	return rows
end

LK.NONE = L["No lockouts: none of your characters is saved to a raid or dungeon (an alt shows up once you've logged in on it with Terminal)"]

local NoteRow = ns.NoteRow

ns:RegisterProvider("lockouts", {
	label = L["Lockout"],
	color = "ffd8b070", -- (an old key's brass)
	aliases = { "lockout", "lockouts", "saved", "raidinfo" },
	refreshOnOpen = 60, -- (the time left moves on)
	events = { "UPDATE_INSTANCE_INFO" },
	guard = 1,
	-- nothing saved anywhere: a line saying so (the list asked for by name: @lockout, the Character category)
	leadRow = ns.EmptyLead(function() return LK.NONE end, function() return not (list and #list > 0) end),
	collect = function() return LK.Collect() end,
})

----------------------------------------------------------------------
-- The question: "my lockouts", "raid lockouts", "am i saved", "what am i saved to", "raid id", "when does mc reset"
----------------------------------------------------------------------

local ASK = {}
-- (time words too: "what resets this week", "raid lockouts this week" said "No lockout has that"; 0.49.2, review)
for w in ([[my me i am im the in a an of is are do does did have has any what whats which how show list check see all
	for on to still this that it its there theres when where will be been got get our we were was at with currently
	now week today tomorrow tonight next weekly daily time]]):gmatch("%a+") do ASK[w] = true end
local KIND = { raid = "raid", raids = "raid", dungeon = "dungeon", dungeons = "dungeon", heroic = "dungeon",
	heroics = "dungeon", instance = "any", instances = "any" }
-- what makes it about lockouts: these alone ("lockouts", "my lockouts"), or with a raid/dungeon word or a question word
local STRONG = { lockout = true, lockouts = true, raidinfo = true }
local WITH_KIND = { saved = true, save = true, id = true, ids = true, reset = true, resets = true, locked = true, lock = true,
	locks = true }
local WITH_ASK = { saved = true, reset = true, resets = true }

-- a word found in the row: its name or text, or a shorthand's full name ("mc" = molten core)
local function Has(e, w)
	local hay = Lower(e.name) .. " " .. (e._ltext or Lower(e.text or ""))
	if hay:find(w, 1, true) then return true end
	for _, full in ipairs(ns.Shorthand and ns.Shorthand[w] or {}) do
		if hay:find(full, 1, true) then return true end
	end
	return false
end

-- Do these words name a lockout listed (all of them in one row), or an instance (each a word of a dungeon's or raid's
-- name, the start of one, or its shorthand: "mc", "molten core", "strat")? "reset my keybinds", "when does my
-- hearthstone reset" aren't about lockouts (0.49.2, review)
local function NamesLockout(words)
	local p = ns.providers.lockouts
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		local all = true
		for _, w in ipairs(words) do if not Has(e, w) then all = false break end end
		if all then return true end
	end
	local I = ns.Integrations
	for _, w in ipairs(words) do
		local found = false
		for _, d in ipairs(I and I.ENTRANCES or {}) do
			local n = " " .. Lower(d[1]):gsub("'", ""):gsub("[%p]", " ") .. " "
			if n:find(" " .. w .. (#w >= 4 and "" or " "), 1, true) then found = true break end
			for _, full in ipairs(ns.Shorthand and ns.Shorthand[w] or {}) do
				if n:find(" " .. full:gsub("'", "") .. " ", 1, true) then found = true break end
			end
			if found then break end
		end
		if not found then return false end
	end
	return true
end

--- The question: { words = what narrows it (an instance, a character), raid, dungeon }, or nil when the line isn't
--- asking about lockouts.
function LK.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("locked out", "lockouts"):gsub("lock out", "lockouts"):gsub("raid id", "lockouts raid")
	local strong, cue, asked, kinds, rest = false, false, false, {}, {}
	for w in t:gmatch("%S+") do
		if STRONG[w] then strong = true
		elseif KIND[w] then kinds[KIND[w]] = true
		elseif WITH_KIND[w] then cue = w
		elseif ASK[w] then asked = true
		else rest[#rest + 1] = w end
	end
	if not strong then
		-- "saved", "id", "reset", "locked": with a raid/dungeon/instance word ("raid reset", "instance id", "dungeons
		-- saved"), or "saved"/"reset" asked ("am i saved", "when does mc reset"); never alone (".nav reset", "locked chest")
		if not cue then return nil end
		local kinded = next(kinds) ~= nil
		if not kinded and not (asked and WITH_ASK[cue]) then return nil end
		if not kinded and #rest > 0 and cue ~= "reset" and cue ~= "resets" then return nil end
		-- (other words with "reset": only a lockout's or an instance's name, "when does mc reset")
		if not kinded and #rest > 0 and not NamesLockout(rest) then return nil end
	end
	return { words = rest, raid = kinds.raid and not kinds.dungeon or nil, dungeon = kinds.dungeon and not kinds.raid or nil }
end

LK.NOTE, LK.NOTE_RAID, LK.NOTE_DUNGEON = L["Lockouts"], L["Raid lockouts"], L["Dungeon lockouts"]

function LK.Answer(q)
	q = q or {}
	local p = ns.providers.lockouts
	local all = p and ns:GetEntries(p) or {}
	local rows = {}
	for _, e in ipairs(all) do
		local ok = not (q.raid and not e.isRaid) and not (q.dungeon and e.isRaid)
		for _, w in ipairs(q.words or {}) do if ok and not Has(e, w) then ok = false end end
		if ok then rows[#rows + 1] = e end
	end
	ns.ScoreInOrder(rows)
	local note = (q.raid and LK.NOTE_RAID) or (q.dungeon and LK.NOTE_DUNGEON) or LK.NOTE
	if #rows == 0 then
		if #all == 0 then return { NoteRow(LK.NONE) }, note end
		local none = (#(q.words or {}) > 0 and L["No lockout has that"]) or (q.raid and L["No raid lockouts"])
			or (q.dungeon and L["No dungeon lockouts"]) or LK.NONE
		return { NoteRow(none) }, note
	end
	local mine = 0
	for _, e in ipairs(rows) do if e.mine then mine = mine + 1 end end
	return rows, note .. ns.DETAIL_SEP .. (#rows == mine and L["%d yours"]:format(mine) or L["%d yours, %d on alts"]:format(mine, #rows - mine))
end

--- The question as Advanced syntax (Alt+`): "@lockout is:raid mc".
function LK.ToAdvanced(q)
	local parts = { "@lockout" }
	if q.raid then parts[#parts + 1] = "is:raid" end
	if q.dungeon then parts[#parts + 1] = "is:dungeon" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

ns:RegisterCommand("lockouts", {
	desc = L["Your characters' raid and dungeon lockouts; .lockouts forget <name> drops an alt"],
	aliases = { "saved", "raidid" },
	complete = function()
		local out = {}
		for key, c in pairs(Chars() or {}) do
			if key ~= MyKey() and type(c) == "table" and c.name then out[#out + 1] = { "forget " .. c.name, L["drop it from the list"] } end
		end
		return out
	end,
	run = function(args)
		local a = strtrim(args or "")
		local who = a:match("^[Ff]orget%s+(.+)$")
		if who then
			local lw, chars, myKey, n = Lower(who), Chars() or {}, MyKey(), 0
			for key, c in pairs(chars) do
				if key ~= myKey and type(c) == "table" and c.name and (Lower(c.name) == lw
					or Lower(c.name .. "-" .. tostring(c.realm)) == lw) then
					chars[key] = nil
					n = n + 1
				end
			end
			Dirty()
			return { n > 0 and L["Forgot %s."]:format(who) or L["No alt called %s (you can't forget the character you're on)."]:format(who) }
		end
		LK.Collect()
		local lines = LK.Lines()
		if #lines == 0 then return { LK.NONE } end
		table.insert(lines, 1, L["Lockouts:"])
		return lines
	end,
})

-- yours on every answer from the game; asked at login and after a boss dies
local ev = CreateFrame("Frame")
for _, e in ipairs({ "UPDATE_INSTANCE_INFO", "PLAYER_ENTERING_WORLD", "BOSS_KILL", "ENCOUNTER_END" }) do
	pcall(ev.RegisterEvent, ev, e)
end
function LK.OnEvent(event, a1, a2, a3, a4, success)
	if event == "UPDATE_INSTANCE_INFO" then
		LK.answered = true
		pcall(LK.Record)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(2, function() LK.Ask() end)
	elseif event == "BOSS_KILL" or (event == "ENCOUNTER_END" and success == 1) then
		C_Timer.After(LK.BOSS_WAIT, function() LK.Ask() end)
	end
end
ev:SetScript("OnEvent", function(_, ...) LK.OnEvent(...) end)
LK.frame = ev -- (tests)

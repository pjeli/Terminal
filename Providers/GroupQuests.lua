local ns = select(2, ...)
local L = ns.L

-- Quests with your party (Simple mode: "party quests", "quests to share", "same quests as my group"; Advanced:
-- "@group quests", "@group quests is:shareable"): each quest in your log with who in your party is on it too, as the
-- game's own quest log tells it (C_QuestLog.IsUnitOnQuest: Forever's QuestUtils_GetNumPartyMembersOnQuest; the classic
-- logs' IsUnitOnQuest(index, unit)), and whether you can share it (C_QuestLog.IsPushableQuest, as the quest map's Share
-- button asks).
--
--   Enter        shares it with your party (QuestLogPushQuest, the quest log's own Share; from Terminal's code: a C
--                call, not protected: Leatrix Plus's "/ltp quest clone" calls it from a timer on this client), or, for a
--                quest the game won't let you share, opens your quest log at it
--   Shift+Enter  your quest log at it (the quest log row's own Enter)
--
-- ">>> party" says it in as few words as it takes: "On the same quests: Wolves Across the Border, The Fargodeep Mine
-- (Ann). I can share: Princess Must Die!." (a name is said only when not the whole party is on it).
-- A party member who's offline can't be asked (and can't be shared with): counted as unknown, never as lacking it. In a
-- raid, your own party (subgroup) is who's asked: sharing goes to them.
--
-- 0.47.2 (the player: Steelsnap shared, "is already on that quest", yet not shown; the game's own quest log showed no
-- "[1]" either): on Forever the game may never say a party member is on a quest. So its "no" counts only once it has
-- said "yes" for someone this session (PQ.trusted); until then who has a quest is unknown, and the game's replies to a
-- share teach it (PQ.learned: "X is already on that quest", "X has accepted your quest" = on it; "has completed that
-- quest" = done; "is not eligible", "quest log is full" = can't take it; "declined" = lacks it), whichever way the
-- quest was shared (QuestLogPushQuest hooked: the quest log's own Share button too).

local PQ = {}
ns.GroupQuests = PQ

local Safe, Str, Num, Lower, Secret = ns.Safe, ns.Str, ns.Num, ns.Lower, ns.Secret

PQ.REACH = "@group quests" -- (how a search names this list: .mem, Alt+`, Shift+Right; ns:KindName)
PQ.NONE = L["You're not in a party: party quests need one"]
PQ.UNKNOWN_NOTE = L["who has them isn't known: the game doesn't say here, sharing tells"]
PQ.RESULT_WAIT = 15 -- (s: "already on that quest" and the like come at once, for the quest shared last)
PQ.ANSWER_WAIT = 120 -- (s: "has accepted / declined your quest" come when they click)

PQ.trusted = false -- (the game has said "yes" for someone this session: its "no" counts too)
PQ.learned = {} -- [member key][questID] = { said = "on" | "done" | "cant" | "declined", at } (this session)

local GREEN, YELLOW, GREY = "|cff7fe07f", "|cffffd200", "|cff9d9d9d"

----------------------------------------------------------------------
-- Your party, and who is on a quest
----------------------------------------------------------------------

--- Your party now, you left out: { unit, name, online } (in a raid: your own party of it).
function PQ.Members()
	local n = Num(Safe(_G.GetNumSubgroupMembers))
	if not n then
		local all = Num(Safe(_G.GetNumGroupMembers)) or 0
		n = Safe(_G.IsInRaid) == true and 0 or math.max(all - 1, 0)
	end
	local out = {}
	for i = 1, math.min(n, 4) do
		local unit = "party" .. i
		if Safe(_G.UnitExists, unit) == true then
			local name = ns.Group and ns.Group.NameOf(unit) or Str(Safe(_G.UnitName, unit))
			local connected = Safe(_G.UnitIsConnected, unit)
			local guid = Str(Safe(_G.UnitGUID, unit))
			out[#out + 1] = { unit = unit, name = name or L["party member %s"]:format(i), hidden = name == nil or nil,
				online = Secret(connected) and true or connected ~= false, guid = guid,
				key = guid or (name and PQ.NameKey(name)) or unit }
		end
	end
	return out
end

--- Whether the game says this member is on the quest: true, false, or nil (it can't say: no call, a secret answer).
function PQ.OnQuest(unit, questID, index)
	local f = C_QuestLog and C_QuestLog.IsUnitOnQuest
	if f then
		local v = Safe(f, unit, questID)
		if Secret(v) or v == nil then return nil end
		return v == true
	end
	if _G.IsUnitOnQuest and index then -- (classic logs: by the log's index, 1 or nil)
		local v = Safe(_G.IsUnitOnQuest, index, unit)
		if Secret(v) then return nil end
		return v == true or v == 1
	end
	return nil
end

-- a name as compared: lowercase, no realm, no spaces ("Plamen Pally-Forever" = "plamenpally")
function PQ.NameKey(n)
	n = Lower(tostring(n or "")):gsub("%-.*$", "")
	return (n:gsub("[%s']", ""))
end

--- What's known of a member and a quest: "on", "done" (completed it), "cant" (can't take it), "lacks", or nil (not
--- known). The game's answer first ("yes" always; "no" only once it has said "yes" for someone), then what a share
--- taught.
function PQ.Status(m, said, questID)
	if said == true then return "on" end
	local l = PQ.learned[m.key]
	l = l and l[questID]
	if l then return l.said == "declined" and "lacks" or l.said end
	if said == false and PQ.trusted then return "lacks" end
	return nil
end

--- Whether the game lets you share the quest: true, false, or nil (it can't say).
function PQ.Pushable(questID)
	local f = C_QuestLog and C_QuestLog.IsPushableQuest
	if not f then return nil end
	local v = Safe(f, questID)
	if Secret(v) or v == nil then return nil end
	return v == true
end

local function LogIndex(questID)
	local f = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
	local i = f and Safe(f, questID)
	if Secret(i) then return nil end
	return Num(i)
end

-- first names, unless two share one
local function ShortNames(members)
	if ns.Group and ns.Group.ShortNames then return ns.Group.ShortNames(members) end
	local out = {}
	for _, m in ipairs(members) do out[m] = m.name end
	return out
end

----------------------------------------------------------------------
-- Sharing
----------------------------------------------------------------------

--- Shares the row's quest with your party: the quest log's own Share (QuestLogPushQuest by the log's index; the quest
--- selected around it for clients whose Share pushes the selected one, then put back). The game says the rest in chat
--- ("Sharing quest with Ann...", "Bob is already on that quest").
function PQ.Share(e)
	if Safe(_G.IsInGroup) ~= true then ns:Print(L["You're not in a party: nobody to share %s with."]:format(tostring(e.name))) return end
	if e.pushable == false then ns:Print(L["%s can't be shared."]:format(tostring(e.name))) return end
	local index = LogIndex(e.questID)
	if not index or not _G.QuestLogPushQuest then
		ns:Print(L["%s isn't in your quest log any more."]:format(tostring(e.name)))
		return
	end
	local ok = ns.Guarded("sharequest", function()
		local get, set = C_QuestLog.GetSelectedQuest, C_QuestLog.SetSelectedQuest
		local was = get and get() or nil
		if set then set(e.questID) end
		PQ.lastShare = { id = e.questID, at = (_G.time and _G.time()) or 0 }
		_G.QuestLogPushQuest(index)
		if set and was and was ~= e.questID then set(was) end
	end)
	ns:Trace(("party quests: shared %s (log index %d)%s"):format(tostring(e.name), index, ok and "" or ": failed or blocked"))
	if not ok then ns:Print(L["Couldn't share %s from here: use the quest log's Share button."]:format(tostring(e.name))) end
end

local function NotInLog(e) ns:Print(L["%s: open your quest log to see it."]:format(tostring(e.name))) end

--- The quest log's own Share too (QuestLogPushQuest hooked, after it runs): which quest was shared last.
function PQ.HookPush()
	if PQ.pushHooked then return true end
	if type(_G.hooksecurefunc) ~= "function" or type(_G.QuestLogPushQuest) ~= "function" then return false end
	_G.hooksecurefunc("QuestLogPushQuest", function(index)
		pcall(function()
			local id
			local info = index and C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
			if type(info) == "table" then id = Num(info.questID) end
			if not id and C_QuestLog.GetSelectedQuest then id = Num(C_QuestLog.GetSelectedQuest()) end
			if id then PQ.lastShare = { id = id, at = (_G.time and _G.time()) or 0 } end
		end)
	end)
	PQ.pushHooked = true
	return true
end

-- the game's replies to a share, by its own strings (English where a client lacks one)
local REPLIES = {
	{ "ERR_QUEST_PUSH_ONQUEST_S", "%s is already on that quest", "on" },
	{ "ERR_QUEST_PUSH_ACCEPTED_S", "%s has accepted your quest", "on", true },
	{ "ERR_QUEST_PUSH_ALREADY_DONE_S", "%s has completed that quest", "done" },
	{ "ERR_QUEST_PUSH_INVALID_S", "%s is not eligible for that quest", "cant" },
	{ "ERR_QUEST_PUSH_LOG_FULL_S", "%s's quest log is full", "cant" },
	{ "ERR_QUEST_PUSH_DECLINED_S", "%s has declined your quest", "declined", true },
}
local replyPatterns
local function Pattern(t)
	local p = t:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
	return "^" .. p
end

--- A line the game said: the member's name and what it means ("on", "done", "cant", "declined") and whether it's an
--- answer they clicked (accepted, declined); nil for any other line.
function PQ.Reply(text)
	if type(text) ~= "string" or Secret(text) then return nil end
	if not replyPatterns then
		replyPatterns = {}
		for _, r in ipairs(REPLIES) do
			local g = Str(_G[r[1]]) or r[2]
			if g:find("%s", 1, true) then replyPatterns[#replyPatterns + 1] = { Pattern(g), r[3], r[4] } end
		end
	end
	for _, r in ipairs(replyPatterns) do
		local who = text:match(r[1])
		if who then return who, r[2], r[3] end
	end
	return nil
end
PQ.ResetRepliesForTests = function() replyPatterns = nil end

--- What a reply teaches: for the quest shared last (within PQ.RESULT_WAIT, or PQ.ANSWER_WAIT for a clicked answer),
--- the party member it names. True when it was kept.
function PQ.Learn(text, now)
	local who, said, clicked = PQ.Reply(text)
	if not who then return false end
	local share = PQ.lastShare
	now = now or (_G.time and _G.time()) or 0
	if not share or now - share.at > (clicked and PQ.ANSWER_WAIT or PQ.RESULT_WAIT) then
		ns:Trace("party quests: \"" .. text .. "\": no share of yours just before it")
		return false
	end
	local want = PQ.NameKey(who)
	for _, m in ipairs(PQ.Members()) do
		local full, first = PQ.NameKey(m.name), PQ.NameKey(tostring(m.name):match("^(%S+)") or m.name)
		if want == full or want == first then
			PQ.learned[m.key] = PQ.learned[m.key] or {}
			PQ.learned[m.key][share.id] = { said = said, at = now }
			local p = ns.providers.groupquests
			if p then p._dirty = true end
			ns:Trace(("party quests: %s for quest %d, from the game's reply"):format(said, share.id))
			return true
		end
	end
	ns:Trace("party quests: \"" .. text .. "\": nobody in your party by that name")
	return false
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function Names(list) return table.concat(list, ", ") end

local function Tooltip(e, t)
	local QT = ns.QuestTip
	if QT and QT.LogTooltip and e.quest then QT.LogTooltip(e.quest, t) else t:SetText(e.name, 1, 0.82, 0) end
	t:AddLine(" ")
	t:AddLine(L["Your party"], 1, 0.82, 0)
	for _, m in ipairs(e.party or {}) do
		local said, r, g, b
		if m.status == "on" then said, r, g, b = L["on it"], 0.5, 0.88, 0.5
		elseif m.status == "lacks" then said, r, g, b = L["doesn't have it"], 1, 0.82, 0
		elseif m.status == "done" then said, r, g, b = L["has done it"], 0.6, 0.6, 0.6
		elseif m.status == "cant" then said, r, g, b = L["can't take it"], 0.6, 0.6, 0.6
		else said, r, g, b = m.online and L["not known"] or L["offline"], 0.6, 0.6, 0.6 end
		t:AddDoubleLine(m.name, said, 1, 1, 1, r, g, b)
	end
	if e.unknown and #e.unknown > 0 then
		t:AddLine(L["The game doesn't say who's on your quests here: sharing tells (\"is already on that quest\")."], 0.6, 0.8, 1, true)
	end
	if e.pushable == false then t:AddLine(L["The game won't let you share this quest"], 0.6, 0.6, 0.6, true) end
	t:AddLine(e.pushable ~= false and L["Enter: share with your party    Shift+Enter: show in your quest log"]
		or L["Enter: show in your quest log"], 0.6, 0.6, 0.6, true)
end

-- one row sent to chat: "[Wolves Across the Border] (also on it: Ann, Bob; I can share it)"
local function ShareExtra(e, room)
	local parts = {}
	if #e.on > 0 then parts[#parts + 1] = (e.everyone and L["the whole party is on it"]) or L["also on it: %s"]:format(Names(e.on)) end
	if e.canShare then parts[#parts + 1] = L["I can share it"] end
	if #parts == 0 then return nil end
	local s = " (" .. table.concat(parts, "; ") .. ")"
	if room and #s > room then return nil end
	return s
end

local list -- (the last collect's rows)

-- `said`: the game's answers, [member][questID] = true / false / nil, asked once per collect (Collect)
local function Row(q, members, short, said)
	local id = q.questID
	local on, lacks, unknown, done, cant, party, online = {}, {}, {}, {}, {}, {}, 0
	for _, m in ipairs(members) do
		local st
		if m.online then st = PQ.Status(m, said[m][id], id) end
		party[#party + 1] = { name = short[m], status = st, online = m.online }
		if m.online then
			online = online + 1
			local n = short[m]
			if st == "on" then on[#on + 1] = n elseif st == "lacks" then lacks[#lacks + 1] = n
			elseif st == "done" then done[#done + 1] = n elseif st == "cant" then cant[#cant + 1] = n
			else unknown[#unknown + 1] = n end
		end
	end
	local pushable = PQ.Pushable(id)
	-- (someone lacks it, or isn't known to have it: the game says "already on that quest" otherwise)
	local canShare = pushable ~= false and (#lacks + #unknown) > 0
	local everyone = #on > 0 and #on == online and online > 0
	local d = { ((q.level and (L["Lv %d"]:format(q.level) .. "  ")) or "") .. (q.zone or "") }
	if everyone and #on > 1 then d[#d + 1] = GREEN .. L["the whole party"] .. "|r"
	elseif #on > 0 then d[#d + 1] = GREEN .. L["%s too"]:format(Names(on)) .. "|r"
	elseif #unknown > 0 and #unknown == online then d[#d + 1] = GREY .. L["who has it isn't known"] .. "|r"
	else d[#d + 1] = GREY .. L["only you"] .. "|r" end
	if #done > 0 then d[#d + 1] = GREY .. L["%s did it"]:format(Names(done)) .. "|r" end
	if #cant > 0 then d[#d + 1] = GREY .. L["%s can't take it"]:format(Names(cant)) .. "|r" end
	local offer = {}
	for _, n in ipairs(lacks) do offer[#offer + 1] = n end
	for _, n in ipairs(unknown) do offer[#offer + 1] = n end
	if canShare then d[#d + 1] = YELLOW .. ((#offer == online and #offer > 1) and L["can share"] or L["share with %s"]:format(Names(offer))) .. "|r"
	elseif pushable == false and #offer > 0 then d[#d + 1] = GREY .. L["can't be shared"] .. "|r" end
	local words = { rawget(q, "_ltext") or "", "party quest" }
	for _, n in ipairs(on) do words[#words + 1] = Lower(n) end
	if canShare then words[#words + 1] = "share shareable" end
	local shareIt = pushable ~= false
	return {
		key = id, name = q.name, icon = q.icon, questID = id, level = q.level, zone = q.zone, complete = q.complete,
		quest = q, party = party, on = on, lacks = lacks, unknown = unknown, done = done, cant = cant,
		pushable = pushable, canShare = canShare, everyone = everyone,
		together = #on > 0,
		detail = table.concat(d, "  ·  "), text = table.concat(words, " "),
		tooltip = Tooltip, getLink = q.getLink, shareExtra = ShareExtra, shareGroup = PQ.ShareGroupOf,
		-- Enter: share; a quest the game won't let you share: the quest log at it (the log row's own Enter)
		activate = shareIt and PQ.Share or (q.activate or NotInLog),
		secure = not shareIt and q.secure or nil, isOpen = not shareIt and q.isOpen or nil, after = not shareIt and q.after or nil,
		secondary = shareIt and (q.activate or NotInLog) or nil,
		secondarySecure = shareIt and q.secure or nil, secondaryIsOpen = shareIt and q.isOpen or nil,
		secondaryAfter = shareIt and q.after or nil,
	}
end

function PQ.Collect()
	local members = PQ.Members()
	PQ.solo = #members == 0
	if PQ.solo then list = {} return list end
	local short = ShortNames(members)
	local qp = ns.providers.quests
	local quests = {}
	for _, q in ipairs(qp and ns:GetEntries(qp) or {}) do if q.questID then quests[#quests + 1] = q end end
	-- the game's answers first (a "yes" anywhere makes its "no" count: PQ.trusted), then the rows
	local said, yes = {}, 0
	for _, m in ipairs(members) do
		said[m] = {}
		if m.online then
			for _, q in ipairs(quests) do
				local v = PQ.OnQuest(m.unit, q.questID, LogIndex(q.questID))
				said[m][q.questID] = v
				if v == true then yes = yes + 1 end
			end
		end
	end
	if yes > 0 and not PQ.trusted then
		PQ.trusted = true
		ns:Trace("party quests: the game says who's on your quests here (its \"no\" counts from now on)")
	end
	local rows = {}
	for _, q in ipairs(quests) do rows[#rows + 1] = Row(q, members, short, said) end
	-- (the quest log's own order among equal matches)
	local n = #rows
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * 0.5 end
	local offline = 0
	for _, m in ipairs(members) do if not m.online then offline = offline + 1 end end
	PQ.offline = offline
	local together, share, unknown = 0, 0, 0
	for _, e in ipairs(rows) do
		if e.together then together = together + 1 end
		if e.canShare then share = share + 1 end
		if #e.unknown > 0 then unknown = unknown + 1 end
	end
	PQ.unknownRows = unknown
	ns:Trace(("party quests: %d quests, %d party members (%d offline), %d with someone else on them, %d to share, %d with"
		.. " someone not known (the game said yes %d times%s)"):format(#rows, #members, offline, together, share, unknown, yes,
		PQ.trusted and "; trusted" or "; its no isn't trusted yet"))
	list = rows
	return rows
end

local NoteRow = ns.NoteRow

local function Verbs(e)
	if e.pushable ~= false then return L["share with party"], L["show in quest log"] end
	return L["show in quest log"]
end

ns:RegisterProvider("groupquests", {
	label = L["Party quest"],
	color = "ffa8d86a", -- (between the quest log's yellow and the group's green)
	-- (no @word of its own: "@group quests" reaches it, Search.lua's Scan.Parse)
	noKind = true, reach = PQ.REACH, resultText = function(e) return PQ.REACH .. " " .. tostring(e.name) end,
	explicit = true,
	follows = "quests", -- (made again whenever your quest log's list is)
	-- (a party member's quest log changing: UNIT_QUEST_LOG_CHANGED fires for the party's units, not for everyone around)
	events = { "GROUP_ROSTER_UPDATE", "UNIT_QUEST_LOG_CHANGED", "UNIT_CONNECTION" },
	guard = 1,
	refreshOnOpen = true,
	verbs = Verbs,
	leadRow = function(p)
		ns:GetEntries(p)
		if PQ.solo then return NoteRow(PQ.NONE) end
		return nil
	end,
	collect = function() return PQ.Collect() end,
})

----------------------------------------------------------------------
-- The question: "party quests", "quests to share", "same quests as my group", "who is on my quests"
----------------------------------------------------------------------

local QUEST = { quest = true, quests = true, questing = true }
local GROUP = { party = true, group = true, groupmates = true, team = true, raid = true, members = true, member = true,
	partys = true, groups = true }
-- share words: these alone ask it ("quests to share", "shareable quests"); the weak ones only with the party named
local SHARE = { share = true, shareable = true, sharable = true, sharing = true }
local SHARE_WEAK = { lack = true, lacks = true, lacking = true, missing = true, need = true, needs = true, dont = true,
	doesnt = true, havent = true, hasnt = true, without = true }
local TOGETHER = { same = true, common = true, together = true, shared = true }
local TOGETHER_WEAK = { also = true, too = true, both = true }
local ASK = {}
for w in ([[who whos is are on the my our we us i me with in of a an to can could that which what all any anyone someone
	everyone has have do does show list get find for at please them they their its it im ive as do can want]]):gmatch("%a+") do ASK[w] = true end

--- The question: { mode = "all" | "together" | "share", words }, or nil when the line isn't about quests with your party.
function PQ.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " ")
	local quest, group, share, weakShare, together, weakTogether, who, onHas = false, false, false, false, false, false, false, false
	local rest = {}
	for w in t:gmatch("%S+") do
		if QUEST[w] then quest = true
		elseif GROUP[w] then group = true
		elseif SHARE[w] then share = true
		elseif SHARE_WEAK[w] then weakShare = true
		elseif TOGETHER[w] then together = true
		elseif TOGETHER_WEAK[w] then weakTogether = true
		else
			if w == "who" or w == "whos" then who = true end
			if w == "on" or w == "has" or w == "have" then onHas = true end
			if not ASK[w] then rest[#rest + 1] = w end
		end
	end
	if not quest then return nil end
	-- ("who is on my quests", "who has my quests": not "who gives the quest x", a quest giver searched for)
	local partyNamed = group or (who and onHas)
	if share or (weakShare and partyNamed) then return { mode = "share", words = rest } end
	if together or (weakTogether and partyNamed) then return { mode = "together", words = rest } end
	if partyNamed then return { mode = "all", words = rest } end
	return nil
end

local function Wanted(e, q)
	if q.mode == "share" and not e.canShare then return false end
	if q.mode == "together" and not e.together then return false end
	for _, w in ipairs(q.words or {}) do
		local l = rawget(e, "_lname") or Lower(e.name)
		local tx = rawget(e, "_ltext") or ""
		if not (l:find(w, 1, true) or tx:find(w, 1, true)) then return false end
	end
	return true
end

PQ.NOTES = { all = L["Party quests"], together = L["On the same quests as your party"], share = L["Quests you can share"] }

--- The rows a question asks for, and the footer's note.
function PQ.Answer(q)
	q = q or { mode = "all" }
	local p = ns.providers.groupquests
	local all = p and ns:GetEntries(p) or {}
	if PQ.solo then return { NoteRow(PQ.NONE) }, PQ.NOTES[q.mode] or PQ.NOTES.all end
	local rows = {}
	for _, e in ipairs(all) do if Wanted(e, q) then rows[#rows + 1] = e end end
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local note = (PQ.NOTES[q.mode] or PQ.NOTES.all) .. "  ·  " .. L["%d of %d"]:format(#rows, #all)
	if #rows == 0 then
		if q.mode == "share" then note = L["Nobody in your party lacks a quest you can share"]
		elseif q.mode == "together" then note = L["Nobody in your party is on your quests"] end
	end
	if (PQ.offline or 0) > 0 then note = note .. "  ·  " .. L["%d offline, not asked"]:format(PQ.offline) end
	if (PQ.unknownRows or 0) > 0 then note = note .. "  ·  " .. PQ.UNKNOWN_NOTE end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@group quests is:shareable hogger".
function PQ.ToAdvanced(q)
	local parts = { PQ.REACH }
	if q.mode == "share" then parts[#parts + 1] = "is:shareable" elseif q.mode == "together" then parts[#parts + 1] = "is:together" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

----------------------------------------------------------------------
-- Every result at once (">>> party", the menu's "All N to party")
----------------------------------------------------------------------

--- What a search asked of them: "share", "together" or "all" (Advanced is:shareable / is:together, else the question's).
function PQ.AskOf(query)
	local q = PQ.Question(query or "")
	if q then return q.mode end
	local mode = "all"
	for w in Lower(query or ""):gmatch("%S+") do
		local k, v = w:match("^(%a+):(.+)$")
		if k == "is" then
			for part in v:gmatch("[^|&]+") do
				if part == "shareable" or part == "sharable" or part == "toshare" then mode = "share"
				elseif part == "together" or part == "common" or part == "same" then mode = mode == "share" and mode or "together" end
			end
		end
	end
	return mode
end

--- The rows as chat lines: "On the same quests: Wolves Across the Border, The Fargodeep Mine (Ann). I can share:
--- Princess Must Die!." (who's on a quest said only when not the whole party is). Every row carries this (`shareGroup`),
--- Share's GroupLines uses it.
function PQ.ShareGroupOf(rows, query, ML, LM)
	ML, LM = ML or 6, LM or 255
	local mode = PQ.AskOf(query)
	local same, share = {}, {}
	for _, e in ipairs(rows) do
		if e.together then
			if e.everyone then same[#same + 1] = e.name
			else
				local s = e.name .. " (" .. Names(e.on) .. ")"
				same[#same + 1] = { text = s, fit = function(room) return #s <= room and s or e.name end }
			end
		end
		if e.canShare then share[#share + 1] = e.name end
	end
	local sections = {}
	if mode ~= "share" then
		if #same > 0 then sections[#sections + 1] = { label = L["On the same quests"], items = same } end
	end
	if mode ~= "together" then
		if #share > 0 then sections[#sections + 1] = { label = L["I can share"], items = share } end
	end
	if #sections == 0 then
		local none = (mode == "share" and L["No quests to share"]) or (mode == "together" and L["No quests in common"])
			or L["No quests in common, none to share"]
		sections[1] = { text = none }
	end
	local pack = ns.Group and ns.Group.Pack
	local lines = pack and pack(sections, ML, LM, ". ") or {}
	local last = lines[#lines]
	if last and not last:find("[%.!?]$") and #last < LM then lines[#lines] = last .. "." end
	return lines, #rows
end

----------------------------------------------------------------------
-- The game's replies to a share; the quest log's own Share
----------------------------------------------------------------------

local ev = CreateFrame("Frame")
PQ.frame = ev
for _, e in ipairs({ "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "PLAYER_ENTERING_WORLD" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a, b)
	if event == "PLAYER_ENTERING_WORLD" then PQ.HookPush() return end
	-- (CHAT_MSG_SYSTEM: the text first; UI_INFO_MESSAGE / UI_ERROR_MESSAGE: a message type, then the text)
	local text = event == "CHAT_MSG_SYSTEM" and a or b
	if type(text) == "string" and PQ.lastShare then pcall(PQ.Learn, text) end
end)
PQ.HookPush()

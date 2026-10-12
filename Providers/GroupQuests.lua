local ns = select(2, ...)

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

local PQ = {}
ns.GroupQuests = PQ

local Safe, Str, Num, Lower, Secret = ns.Safe, ns.Str, ns.Num, ns.Lower, ns.Secret

PQ.REACH = "@group quests" -- (how a search names this list: .mem, Alt+`, Shift+Right; ns:KindName)
PQ.NONE = "You're not in a party: party quests need one"

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
			out[#out + 1] = { unit = unit, name = name or ("party member " .. i), hidden = name == nil or nil,
				online = Secret(connected) and true or connected ~= false }
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
	if Safe(_G.IsInGroup) ~= true then ns:Print("You're not in a party: nobody to share " .. tostring(e.name) .. " with.") return end
	if e.pushable == false then ns:Print(tostring(e.name) .. " can't be shared.") return end
	local index = LogIndex(e.questID)
	if not index or not _G.QuestLogPushQuest then
		ns:Print(tostring(e.name) .. " isn't in your quest log any more.")
		return
	end
	local ok = ns.Guarded("sharequest", function()
		local get, set = C_QuestLog.GetSelectedQuest, C_QuestLog.SetSelectedQuest
		local was = get and get() or nil
		if set then set(e.questID) end
		_G.QuestLogPushQuest(index)
		if set and was and was ~= e.questID then set(was) end
	end)
	ns:Trace(("party quests: shared %s (log index %d)%s"):format(tostring(e.name), index, ok and "" or ": failed or blocked"))
	if not ok then ns:Print("Couldn't share " .. tostring(e.name) .. " from here: use the quest log's Share button.") end
end

local function NotInLog(e) ns:Print(tostring(e.name) .. ": open your quest log to see it.") end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function Names(list) return table.concat(list, ", ") end

local function Tooltip(e, t)
	local QT = ns.QuestTip
	if QT and QT.LogTooltip and e.quest then QT.LogTooltip(e.quest, t) else t:SetText(e.name, 1, 0.82, 0) end
	t:AddLine(" ")
	t:AddLine("Your party", 1, 0.82, 0)
	for _, m in ipairs(e.party or {}) do
		local said, r, g, b
		if m.on == true then said, r, g, b = "on it", 0.5, 0.88, 0.5
		elseif m.on == false then said, r, g, b = "doesn't have it", 1, 0.82, 0
		else said, r, g, b = m.online and "can't be asked" or "offline", 0.6, 0.6, 0.6 end
		t:AddDoubleLine(m.name, said, 1, 1, 1, r, g, b)
	end
	if e.pushable == false then t:AddLine("The game won't let you share this quest", 0.6, 0.6, 0.6, true) end
	t:AddLine(e.pushable ~= false and "Enter: share with your party    Shift+Enter: show in your quest log"
		or "Enter: show in your quest log", 0.6, 0.6, 0.6, true)
end

-- one row sent to chat: "[Wolves Across the Border] (also on it: Ann, Bob; I can share it)"
local function ShareExtra(e, room)
	local parts = {}
	if #e.on > 0 then parts[#parts + 1] = (e.everyone and "the whole party is on it") or ("also on it: " .. Names(e.on)) end
	if e.canShare then parts[#parts + 1] = "I can share it" end
	if #parts == 0 then return nil end
	local s = " (" .. table.concat(parts, "; ") .. ")"
	if room and #s > room then return nil end
	return s
end

local list -- (the last collect's rows)

local function Row(q, members, short)
	local id = q.questID
	local index = LogIndex(id)
	local on, lacks, party, online = {}, {}, {}, 0
	for _, m in ipairs(members) do
		local is -- (nil: not asked or it can't say; never `x and false or nil`, which is always nil)
		if m.online then is = PQ.OnQuest(m.unit, id, index) end
		party[#party + 1] = { name = short[m], on = is, online = m.online }
		if m.online then online = online + 1 end
		if is == true then on[#on + 1] = short[m] elseif is == false then lacks[#lacks + 1] = short[m] end
	end
	local pushable = PQ.Pushable(id)
	local canShare = pushable ~= false and #lacks > 0
	local everyone = #on > 0 and #on == online and online > 0
	local d = { ((q.level and ("Lv " .. q.level .. "  ")) or "") .. (q.zone or "") }
	if everyone and #on > 1 then d[#d + 1] = GREEN .. "the whole party|r"
	elseif #on > 0 then d[#d + 1] = GREEN .. Names(on) .. " too|r"
	else d[#d + 1] = GREY .. "only you|r" end
	if canShare then d[#d + 1] = YELLOW .. ((#lacks == online and #lacks > 1) and "can share" or ("share with " .. Names(lacks))) .. "|r"
	elseif pushable == false and #lacks > 0 then d[#d + 1] = GREY .. "can't be shared|r" end
	local words = { rawget(q, "_ltext") or "", "party quest" }
	for _, n in ipairs(on) do words[#words + 1] = Lower(n) end
	if canShare then words[#words + 1] = "share shareable" end
	local shareIt = pushable ~= false
	return {
		key = id, name = q.name, icon = q.icon, questID = id, level = q.level, zone = q.zone, complete = q.complete,
		quest = q, party = party, on = on, lacks = lacks, pushable = pushable, canShare = canShare, everyone = everyone,
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
	local rows = {}
	for _, q in ipairs(qp and ns:GetEntries(qp) or {}) do
		if q.questID then rows[#rows + 1] = Row(q, members, short) end
	end
	-- (the quest log's own order among equal matches)
	local n = #rows
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * 0.5 end
	local offline = 0
	for _, m in ipairs(members) do if not m.online then offline = offline + 1 end end
	PQ.offline = offline
	ns:Trace(("party quests: %d quests, %d party members (%d offline), %d with someone else on them, %d to share")
		:format(#rows, #members, offline, (function() local c = 0 for _, e in ipairs(rows) do if e.together then c = c + 1 end end return c end)(),
			(function() local c = 0 for _, e in ipairs(rows) do if e.canShare then c = c + 1 end end return c end)()))
	list = rows
	return rows
end

local function NoteRow(text)
	return { name = text, raw = true, icon = false, noActivate = true, kindLabel = "", detail = "" }
end

local function Verbs(e)
	if e.pushable ~= false then return "share with party", "show in quest log" end
	return "show in quest log"
end

ns:RegisterProvider("groupquests", {
	label = "Party quest",
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

PQ.NOTES = { all = "Party quests", together = "On the same quests as your party", share = "Quests you can share" }

--- The rows a question asks for, and the footer's note.
function PQ.Answer(q)
	q = q or { mode = "all" }
	local p = ns.providers.groupquests
	local all = p and ns:GetEntries(p) or {}
	if PQ.solo then return { NoteRow(PQ.NONE) }, PQ.NOTES[q.mode] or PQ.NOTES.all end
	local rows = {}
	for _, e in ipairs(all) do if Wanted(e, q) then rows[#rows + 1] = e end end
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local note = (PQ.NOTES[q.mode] or PQ.NOTES.all) .. ("  ·  %d of %d"):format(#rows, #all)
	if #rows == 0 then
		if q.mode == "share" then note = "Nobody in your party lacks a quest you can share"
		elseif q.mode == "together" then note = "Nobody in your party is on your quests" end
	end
	if (PQ.offline or 0) > 0 then note = note .. ("  ·  %d offline, not asked"):format(PQ.offline) end
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
		if #same > 0 then sections[#sections + 1] = { label = "On the same quests", items = same } end
	end
	if mode ~= "together" then
		if #share > 0 then sections[#sections + 1] = { label = "I can share", items = share } end
	end
	if #sections == 0 then
		local none = (mode == "share" and "No quests to share") or (mode == "together" and "No quests in common")
			or "No quests in common, none to share"
		sections[1] = { text = none }
	end
	local pack = ns.Group and ns.Group.Pack
	local lines = pack and pack(sections, ML, LM, ". ") or {}
	local last = lines[#lines]
	if last and not last:find("[%.!?]$") and #last < LM then lines[#lines] = last .. "." end
	return lines, #rows
end

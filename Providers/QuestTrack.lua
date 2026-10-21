local ns = select(2, ...)
local L = ns.L

-- Tracking quests in bulk (0.63.3, a player on CurseForge): "untrack quests", "track completed quests", "untrack dungeon
-- quests", "track class quest", "track rfc quests only" (those, and nothing else), "untrack red quests", "track nearby
-- quests". The answer lists the quests that would change, with "Track 4 quests" (or untrack, or both) on top: Enter
-- does it. Advanced: any quest search, then ">>> track", ">>> untrack" or ">>> track only" (">> track": the selected one).
--
-- Tracking is the game's own (C_QuestLog.AddQuestWatch / RemoveQuestWatch: C calls, not protected). Questie, on
-- WoW Forever, hooks those two and keeps its tracker in step (its QuestieTracker:HookBaseTracker), so its tracker
-- follows too. In Questie's auto-track mode a quest can be on its tracker without the game's watch: whether a quest is
-- tracked asks Questie too (QuestieTracker.IsTrackedByQuestie, read defensively), and untracking calls RemoveQuestWatch
-- even then, which Questie's hook turns into its own untrack.

local QK = {}
ns.QuestTrack = QK

local Lower, Call, Secret = ns.Lower, ns.Safe, ns.Secret

----------------------------------------------------------------------
-- Tracked or not, and tracking
----------------------------------------------------------------------

--- Questie's tracker module when Questie is loaded and its tracker is on, else nil.
function QK.Questie()
	local Q = rawget(_G, "Questie")
	local QL = rawget(_G, "QuestieLoader")
	if type(Q) ~= "table" or type(QL) ~= "table" or type(QL.ImportModule) ~= "function" then return nil end
	local ok, on = pcall(function() return Q.db.profile.trackerEnabled end)
	if not ok or not on then return nil end
	local ok2, T = pcall(QL.ImportModule, QL, "QuestieTracker")
	if ok2 and type(T) == "table" and type(T.IsTrackedByQuestie) == "function" then return T end
	return nil
end

local function LogIndex(id)
	local f = C_QuestLog.GetLogIndexForQuestID
	local i = f and Call(f, id)
	return type(i) == "number" and i or nil
end

--- Whether the game watches the quest (its tracker), or Questie's tracker shows it.
function QK.Tracked(id, questie)
	local f = C_QuestLog.GetQuestWatchType
	if f then
		local w = Call(f, id)
		if w ~= nil and not Secret(w) then return true end
	elseif _G.IsQuestWatched then
		local i = LogIndex(id)
		if i and Call(_G.IsQuestWatched, i) then return true end
	end
	if questie == nil then questie = QK.Questie() end
	if questie then
		local ok, yes = pcall(questie.IsTrackedByQuestie, id)
		if ok and yes then return true end
	end
	return false
end

--- How many quests the game's tracker holds at most (nil: no limit told), and how many it holds now.
function QK.Room()
	local Q = C_QuestLog
	local max = Q.GetMaxNumQuestsCanWatch and Call(Q.GetMaxNumQuestsCanWatch)
	local now = Q.GetNumQuestWatches and Call(Q.GetNumQuestWatches)
	return type(max) == "number" and max > 0 and max or nil, type(now) == "number" and now or nil
end

function QK.TrackOne(id)
	local Q = C_QuestLog
	if Q.AddQuestWatch then pcall(Q.AddQuestWatch, id)
	elseif _G.AddQuestWatch then local i = LogIndex(id) if i then pcall(_G.AddQuestWatch, i) end end
	return QK.Tracked(id)
end

function QK.UntrackOne(id)
	local Q = C_QuestLog
	if Q.RemoveQuestWatch then pcall(Q.RemoveQuestWatch, id)
	elseif _G.RemoveQuestWatch then local i = LogIndex(id) if i then pcall(_G.RemoveQuestWatch, i) end end
	return not QK.Tracked(id)
end

--- Untracks `plan.untrack`, then tracks `plan.track` (rows with questID and name), and says in chat what changed.
function QK.Apply(plan)
	local tracked, untracked, failed = {}, {}, {}
	for _, e in ipairs(plan.untrack or {}) do
		if QK.UntrackOne(e.questID) then untracked[#untracked + 1] = e.name else failed[#failed + 1] = e.name end
	end
	for _, e in ipairs(plan.track or {}) do
		if QK.TrackOne(e.questID) then tracked[#tracked + 1] = e.name else failed[#failed + 1] = e.name end
	end
	local lines = {}
	if #tracked > 0 then lines[#lines + 1] = (#tracked == 1 and L["Tracking %d quest: %s"] or L["Tracking %d quests: %s"]):format(#tracked, table.concat(tracked, ", ")) end
	if #untracked > 0 then lines[#lines + 1] = (#untracked == 1 and L["Stopped tracking %d quest: %s"] or L["Stopped tracking %d quests: %s"]):format(#untracked, table.concat(untracked, ", ")) end
	if #failed > 0 then
		local max = QK.Room()
		lines[#lines + 1] = (max and L["Not changed (the tracker holds %d at most): %s"]:format(max, table.concat(failed, ", ")))
			or L["Not changed (the game refused): %s"]:format(table.concat(failed, ", "))
	end
	if #lines == 0 then lines[1] = L["Nothing to change."] end
	ns:Trace(("quests: tracked %d, untracked %d, %d not changed"):format(#tracked, #untracked, #failed))
	ns:Output(lines)
	ns:Changed("quests")
	return #tracked, #untracked, #failed
end

----------------------------------------------------------------------
-- Which quests: nearby, by name or place
----------------------------------------------------------------------

--- Whether the quest is where you are: under your zone's (or subzone's) name in the log, or its map is yours.
function QK.Here(e)
	local names = {}
	for _, f in ipairs({ _G.GetRealZoneText, _G.GetZoneText, _G.GetSubZoneText, _G.GetMinimapZoneText }) do
		local n = f and Call(f)
		if type(n) == "string" and n ~= "" and not Secret(n) then names[Lower(n)] = true end
	end
	if e.zone and names[Lower(e.zone)] then return true end
	local best = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local ui = _G.GetQuestUiMapID and Call(_G.GetQuestUiMapID, e.questID)
	return type(best) == "number" and type(ui) == "number" and ui > 0 and ui == best
end

--- Whether every word names the quest: its title or its log header, or a place it's short for ("rfc": Ragefire Chasm).
--- A name typed as one word is found too ("thunderbluff": Thunder Bluff; "zulfarrak": Zul'Farrak; 0.63.4, the player).
local function Named(e, words, zoneOnly)
	if #words == 0 then return true end
	local name = zoneOnly and "" or tostring(e.name or "")
	local hay = Lower(name) .. " \1 " .. Lower(tostring(e.zone or ""))
	local flat = ns.Norm(name) .. "\1" .. ns.Norm(tostring(e.zone or ""))
	local S = ns.Shorthand or {}
	for _, w in ipairs(words) do
		local ok = hay:find(w, 1, true) ~= nil or flat:find(ns.Norm(w), 1, true) ~= nil
		if not ok and S[w] then
			for _, full in ipairs(S[w]) do if hay:find(full, 1, true) or flat:find(ns.Norm(full), 1, true) then ok = true break end end
		end
		if not ok then return false end
	end
	return true
end

--- The log's headings the words name together ("thunder bluff", "rfc": { ["Thunder Bluff"] = true }), or nil when they
--- name none: then they're a quest's name. A place named finds the quests listed under it, not every quest whose
--- title says it, as its Advanced form (in:"Thunder Bluff") does (0.63.5).
function QK.Places(words, groups)
	if not words or #words == 0 then return nil end
	local p = ns.providers.quests
	local all = p and ns:GetEntries(p) or {}
	-- each part ("mulgore", "thunder bluff") must name a heading of its own
	local parts, from = {}, 1
	for _, upto in ipairs(groups or {}) do
		parts[#parts + 1] = { unpack(words, from, upto) }
		from = upto + 1
	end
	parts[#parts + 1] = { unpack(words, from, #words) }
	local out = {}
	for _, part in ipairs(parts) do
		local found = false
		for _, e in ipairs(all) do
			if e.zone and #part > 0 and Named({ zone = e.zone }, part, true) then out[e.zone], found = true, true end
		end
		if #part > 0 and not found then return nil end
	end
	return next(out) and out or nil
end

--- Whether the quest is one the question asks for (`places`: QK.Places of its words, worked out once).
function QK.Fits(e, q, places)
	if q.complete and not e.complete then return false end
	if q.incomplete and e.complete then return false end
	if q.raid and e.instance ~= "raid" then return false end
	if q.dungeon and not (e.instance == "dungeon" or e.instance == "raid") then return false end
	if q.class and not e.classQuest then return false end
	if q.diffs and next(q.diffs) and not q.diffs[e.diffName or ""] then return false end
	if q.here and not QK.Here(e) then return false end
	if places then return places[e.zone or ""] == true end
	return Named(e, q.words or {})
end

----------------------------------------------------------------------
-- The question
----------------------------------------------------------------------

local VERB = { track = "track", watch = "track", untrack = "untrack", unwatch = "untrack" }
local SUBJECT = { quest = true, quests = true }
local ALL = { all = true, everything = true, every = true }
local FILL = {}
for w in ([[my the of in for from that are which i have please now me some any log questlog these those to and or
	with at level levels lvl ones one them current currently tracked tracker on ive im is a an each can could]]):gmatch("%a+") do FILL[w] = true end
local JOIN = { ["and"] = true, ["or"] = true, also = true, plus = true }
local QUAL = { complete = "complete", completed = "complete", done = "complete", finished = "complete", ready = "complete",
	incomplete = "incomplete", unfinished = "incomplete", dungeon = "dungeon", dungeons = "dungeon", instance = "dungeon",
	instances = "dungeon", raid = "raid", raids = "raid", class = "class", nearby = "here", near = "here", here = "here",
	close = "here", around = "here", ["local"] = "here" }
local DIFF = { red = "red", orange = "orange", yellow = "yellow", green = "green", grey = "grey", gray = "grey", trivial = "grey" }

--- The question: { verb = "track"|"untrack", only, complete, incomplete, dungeon, raid, class, here, diffs = { red = true },
--- words = the words that name quests or places }, or nil when the line isn't one. It starts with what to do: "track",
--- "untrack", "stop tracking" ("only"/"just" before it, or after); "quest(s)" said, or "all"/"everything".
function QK.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = " " .. t .. " "
	t = t:gsub(" stop tracking ", " untrack "):gsub(" stop watching ", " untrack ")
	-- ("quests to turn in", "i can turn in": the complete ones; 0.63.7, review: "turn" was read as a quest's name)
	t = t:gsub(" turn in ", " complete "):gsub(" turnin ", " complete "):gsub(" hand in ", " complete ")
	t = t:gsub(" this zone ", " here "):gsub(" this area ", " here "):gsub(" my zone ", " here "):gsub(" current zone ", " here ")
	local list = {}
	for w in t:gmatch("%S+") do list[#list + 1] = w end
	local q = { diffs = {}, words = {}, groups = {} } -- (groups: where "and"/"or" split the words: "mulgore and thunder bluff")
	local i = 1
	while list[i] == "only" or list[i] == "just" or list[i] == "please" do
		if list[i] ~= "please" then q.only = true end
		i = i + 1
	end
	q.verb = VERB[list[i] or ""]
	if not q.verb then return nil end
	local subject, all = false, false
	for k = i + 1, #list do
		local w = list[k]
		if SUBJECT[w] then subject = true
		elseif ALL[w] then all = true
		elseif w == "only" or w == "just" then q.only = true
		elseif QUAL[w] then q[QUAL[w]] = true
		elseif DIFF[w] then q.diffs[DIFF[w]] = true
		elseif JOIN[w] then
			if #q.words > 0 and q.groups[#q.groups] ~= #q.words then q.groups[#q.groups + 1] = #q.words end
		elseif not FILL[w] then q.words[#q.words + 1] = w end
	end
	if not subject and not (all and #q.words == 0) then return nil end
	if q.verb == "untrack" then q.only = nil end -- ("untrack ... only": the same as untracking them)
	return q
end

--- The question's quests in Advanced syntax (Alt+`): "@quest is:complete >>> track".
function QK.ToAdvanced(q)
	local parts = { "@quest" }
	if q.complete then parts[#parts + 1] = "is:complete" end
	if q.incomplete then parts[#parts + 1] = "-is:complete" end
	if q.raid then parts[#parts + 1] = "is:raid" elseif q.dungeon then parts[#parts + 1] = "is:dungeon|raid" end
	if q.class then parts[#parts + 1] = "is:class" end
	local d = {}
	for _, c in ipairs({ "red", "orange", "yellow", "green", "grey" }) do if q.diffs and q.diffs[c] then d[#d + 1] = c end end
	if #d > 0 then parts[#parts + 1] = "is:" .. table.concat(d, "|") end
	if q.here then parts[#parts + 1] = "is:here" end
	-- a place: the heading itself (in:"Thunder Bluff"); else the words, together as the quest's name
	local places = QK.Places(q.words, q.groups)
	local list = {}
	for zone in pairs(places or {}) do list[#list + 1] = zone end
	table.sort(list)
	if #list > 0 then
		local quoted = {}
		for i, zone in ipairs(list) do quoted[i] = zone:find("%s") and ('"' .. zone .. '"') or zone end
		parts[#parts + 1] = "in:" .. table.concat(quoted, "|")
	elseif q.words and #q.words > 0 then
		-- a quest's name: the one it names, in quotes, as the log has it; else the words
		local p = ns.providers.quests
		local title
		for _, e in ipairs(p and ns:GetEntries(p) or {}) do
			if Named({ name = e.name }, q.words) then
				if title and title ~= e.name then title = false break end
				title = title == nil and e.name or title
			end
		end
		if title then parts[#parts + 1] = '"' .. Lower(title) .. '"'
		else for _, w in ipairs(q.words) do parts[#parts + 1] = w end end
	end
	parts[#parts + 1] = (q.verb == "untrack" and ">>> untrack") or (q.only and ">>> track only") or ">>> track"
	return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- The answer, and ">>> track"
----------------------------------------------------------------------

local function ByLevel(a, b)
	local la, lb = a.level or 0, b.level or 0
	if la ~= lb then return la < lb end
	return tostring(a.name) < tostring(b.name)
end

--- What to change: { track = rows, untrack = rows, matched = how many fit }, for the quests in `rows` (quest log
--- rows; nil: the whole log) and what to do (`how`: "track", "untrack" or "only": track these, untrack every other).
function QK.Plan(rows, how)
	local p = ns.providers.quests
	local all = p and ns:GetEntries(p) or {}
	local questie = QK.Questie() or false
	local plan, seen = { track = {}, untrack = {}, matched = 0 }, {}
	for _, e in ipairs(rows or all) do
		local o = type(e) == "table" and (rawget(e, "pipeOf") or e) or nil
		if o and o.kind == "quests" and type(o.questID) == "number" and not seen[o.questID] then
			seen[o.questID] = true
			plan.matched = plan.matched + 1
			local on = QK.Tracked(o.questID, questie)
			if how == "untrack" then
				if on then plan.untrack[#plan.untrack + 1] = o end
			elseif not on then
				plan.track[#plan.track + 1] = o
			end
		end
	end
	-- ("only" with nothing it names: nothing untracked either; 0.63.7, review: "track rcf quests only", a typo,
	-- emptied the tracker)
	if how == "only" and plan.matched > 0 then
		for _, o in ipairs(all) do
			if type(o.questID) == "number" and not seen[o.questID] and QK.Tracked(o.questID, questie) then
				plan.untrack[#plan.untrack + 1] = o
			end
		end
	end
	table.sort(plan.track, ByLevel)
	table.sort(plan.untrack, ByLevel)
	return plan
end

--- The top row's name for a plan: "Track 4 quests", "Untrack 7 quests", "Track 3, untrack 5".
function QK.PlanName(plan)
	local t, u = #plan.track, #plan.untrack
	if t > 0 and u > 0 then return L["Track %d, untrack %d"]:format(t, u) end
	if t > 0 then return (t == 1 and L["Track %d quest"] or L["Track %d quests"]):format(t) end
	if u > 0 then return (u == 1 and L["Untrack %d quest"] or L["Untrack %d quests"]):format(u) end
	return L["Nothing to change"]
end

--- What the top row says under its name: Questie's tracker follows; the tracker's room when it's short.
function QK.PlanDetail(plan)
	local bits = {}
	local max, now = QK.Room()
	if max and now and #plan.track > 0 then
		local room = max - now + #plan.untrack
		if #plan.track > room then bits[#bits + 1] = L["the tracker holds %d: %d fit"]:format(max, math.max(0, room)) end
	end
	bits[#bits + 1] = QK.Questie() and L["the game's tracker and Questie's"] or L["the quest tracker"]
	return table.concat(bits, ns.DETAIL_SEP)
end

local function Marked(o, track)
	local mark = track and ("|cff33ff99" .. L["to track"] .. "|r") or ("|cffff8040" .. L["to untrack"] .. "|r")
	return setmetatable({ pipeOf = o, detail = ns.Detail(mark, o.detail) }, { __index = o })
end

local DoRow

--- The plan for only these of its quests (a filter after the question kept them: Search.lua's AnswerView).
function QK.PlanOf(plan, rows)
	local ids = {}
	for _, e in ipairs(rows or {}) do
		local o = type(e) == "table" and (rawget(e, "pipeOf") or e) or nil
		if o and o.questID then ids[o.questID] = true end
	end
	local out = { track = {}, untrack = {}, matched = plan.matched }
	for _, o in ipairs(plan.track) do if ids[o.questID] then out.track[#out.track + 1] = o end end
	for _, o in ipairs(plan.untrack) do if ids[o.questID] then out.untrack[#out.untrack + 1] = o end end
	return out
end

DoRow = function(plan)
	return {
		name = QK.PlanName(plan), kind = "questtrack", kindLabel = "|cffffd200" .. L["quests"] .. "|r", raw = true, lead = true,
		icon = "Interface\\Icons\\INV_Misc_Map_01", detail = QK.PlanDetail(plan),
		actionVerb = L["do it"], activate = function() QK.Apply(plan) end, _pos = ns.UI and ns.UI.NO_POS or {},
		-- (the rows a filter left: the plan for those alone, or no row when it leaves none to change)
		replan = function(rows)
			local p = QK.PlanOf(plan, rows)
			return #p.track + #p.untrack > 0 and DoRow(p) or nil
		end,
	}
end

--- The answer: the quests that would change (marked "to track" or "to untrack"), the row that does it on top. The note.
function QK.Answer(q)
	q = q or {}
	local p = ns.providers.quests
	local fit = {}
	local places = QK.Places(q.words, q.groups)
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if QK.Fits(e, q, places) then fit[#fit + 1] = e end
	end
	local how = (q.verb == "untrack" and "untrack") or (q.only and "only") or "track"
	local plan = QK.Plan(fit, how)
	local rows = {}
	for _, o in ipairs(plan.track) do rows[#rows + 1] = Marked(o, true) end
	for _, o in ipairs(plan.untrack) do rows[#rows + 1] = Marked(o, false) end
	ns.ScoreInOrder(rows)
	local note
	if #rows == 0 then
		note = (#fit == 0 and L["No such quests in your log"])
			or (how == "untrack" and L["None of them is tracked"])
			or L["Already tracked, all of them"]
	else
		local top = DoRow(plan)
		top._score = 2e6
		table.insert(rows, 1, top)
		note = how == "untrack" and L["Quests to untrack"] or L["Quests to track"]
	end
	return rows, note
end

--- ">>> track": the one row a list collapses into (`how`: "track", "untrack", "only"), and the plan it does.
function QK.GroupRow(list, how)
	local plan = QK.Plan(QK.QuestRows(list), how)
	local row = DoRow(plan)
	row.sendAll, row.lead, row._score = true, nil, 0
	if #plan.track + #plan.untrack == 0 then
		row.noActivate, row.activate = true, nil
		row.detail = plan.matched == 0 and L["no quest in your log among the results"]
			or (how == "untrack" and L["none of them is tracked"] or L["all of them are tracked already"])
	end
	return row, plan
end

--- The quest log rows among a list (a chain's rows: what they stand for).
function QK.QuestRows(list)
	local out = {}
	for _, e in ipairs(list or {}) do
		local o = type(e) == "table" and (rawget(e, "pipeOf") or e) or nil
		if o and o.kind == "quests" and type(o.questID) == "number" then out[#out + 1] = o end
	end
	return out
end

local ns = select(2, ...)
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local RunSliced = I.RunSliced
local npc, qdb = I.npc, I.qdb
local QD = ns.QuestieData
local QuestieReady = QD.Ready -- (the data can be read: QuestieDB loaded, and Questie ready if installed)
local function QDB() return QD.DB() end
local IP = I._
local HintFind, NpcHintRow, QuestHintRow, IndexNPCs, NpcLocation = IP.HintFind, IP.NpcHintRow, IP.QuestHintRow, IP.IndexNPCs, IP.NpcLocation
local ShowNpc, OpenNpcDirect = IP.ShowNpc, IP.OpenNpcDirect
local NPC_TARGET, NeverTargeted, TargetFallback, ClearNpcFields = IP.NPC_TARGET, IP.NeverTargeted, IP.TargetFallback, IP.ClearNpcFields

----------------------------------------------------------------------
-- Questie's quests (@questie), and the Questie providers (@npc, @mailbox, @questie)
----------------------------------------------------------------------

--- A quest's objectives ("Bring Sharptalon's Claw to Senani Thunderheart...") from Questie's
--- database, lowercased for the search, or nil. Questie keeps them as a list of lines.
local function ObjectivesText(DB, id)
	local t = Safe(DB.QueryQuestSingle, id, "objectivesText")
	if type(t) == "table" then
		local parts = {}
		for _, line in ipairs(t) do
			if type(line) == "string" and not (issecretvalue and issecretvalue(line)) then parts[#parts + 1] = line end
		end
		t = table.concat(parts, " ")
	end
	if ns.Str(t) then return ns.Lower(t) end
end

--- Quest names, levels, zones and objectives from Questie's database, a slice at a time.
local function IndexQuests()
	if qdb.list or qdb.busy or not QuestieReady() then return end
	local DB = QDB()
	if not (DB and DB.QueryQuestSingle) then return end
	qdb.busy = true
	local ids = DB.QuestIds()
	local out = {}
	local zones = {} -- zoneOrSort -> { name, searchable text }: thousands of quests share a few hundred zones
	local function Zone(zone)
		local z = zones[zone]
		if not z then
			local zname = type(zone) == "number" and zone > 0 and C_Map and C_Map.GetAreaInfo and Safe(C_Map.GetAreaInfo, zone) or nil
			zname = type(zname) == "string" and zname or nil
			z = { zname, ns.Lower("quest questie " .. (zname or "")) }
			zones[zone] = z
		end
		return z
	end
	local names = not qdb.names and {} or nil
	RunSliced("questie: quests", #ids, function(i)
		local id = ids[i]
		local name = Safe(DB.QueryQuestSingle, id, "name")
		if ns.Str(name) then
			local z = Zone(Safe(DB.QueryQuestSingle, id, "zoneOrSort") or 0)
			-- searched too: who to talk to, what to kill or bring, where
			local obj = ObjectivesText(DB, id)
			local lname = ns.Lower(name)
			out[#out + 1] = setmetatable({
				_compact = true, key = id, name = name, _lname = lname,
				level = Safe(DB.QueryQuestSingle, id, "questLevel"),
				zone = z[1],
				_ltext = obj and (z[2] .. " " .. obj) or z[2],
			}, qdb.meta)
			if names then names[#names + 1] = "\n" .. lname .. "\t" .. id end
		end
	end, function()
		qdb.list, qdb.busy = out, false
		if names then qdb.names, qdb.nameQuery = table.concat(names) .. "\n", "QueryQuestSingle" end
		if ns.providers.questie then ns.providers.questie._dirty = true end
		-- the towns' middles from the quests' words, for "vendor goldshire" (a few a frame, a little later)
		C_Timer.After(2, function() if not InCombatLockdown() then I.BuildTowns() end end)
		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
	end)
end

--- Who starts a quest: an NPC id, or a word for what else does ("an object", "an item").
local function QuestGiver(id)
	local DB = QDB()
	local by = DB and Safe(DB.QueryQuestSingle, id, "startedBy")
	if type(by) ~= "table" then return nil end
	if type(by[1]) == "table" and by[1][1] then
		local name = Safe(DB.QueryNPCSingle, by[1][1], "name")
		return by[1][1], type(name) == "string" and name or nil
	end
	if type(by[2]) == "table" and by[2][1] then return nil, nil, "an object" end
	if type(by[3]) == "table" and by[3][1] then return nil, nil, "an item" end
end

local function InLog(id)
	return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) and true or false
end

local function Done(id)
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and Safe(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false
end

--- A quest from Questie's database. Enter (or a click) shows its Wowhead link, selected in a small
--- window: Ctrl+C copies it (addons can't put text on the clipboard themselves) and the window
--- closes. Shift+Enter opens it in the game: the quest log for a quest you're on (as @questlog
--- does), otherwise its quest giver on the map. Entries are compact: these are shared, and
--- worked out when read (the quest's state can change).
local function LogEntry(id)
	local p = ns.providers.quests
	if not p then return nil end
	for _, l in ipairs(ns:GetEntries(p)) do
		if l.questID == id then return l end
	end
end

-- Wowhead has a WoW Forever section (/forever), with pages in the same form as its others.
I.WOWHEAD_QUEST = "https://www.wowhead.com/forever/quest=%d"

local function CopyQuestLink(t)
	local url = I.WOWHEAD_QUEST:format(t.qid)
	ns:ShowText("Wowhead: " .. tostring(t.name), url, { compact = true })
end

--- What a quest is sent to chat as, the way Questie links one: the game's own quest link when there is one
--- (anyone can click it; Questie turns it into its own link for players who have Questie), else Questie's
--- "[[level] Name (id)]", which Questie's chat filter makes a clickable link with its tooltip. (Questie's own
--- "|Hquestie:" links are only made on the receiving end: chat doesn't carry links it doesn't know.) Nil without Questie.
function I.QuestieQuestLink(id)
	id = tonumber(id)
	if not id then return nil end
	local L = QD.AnyModule("QuestieLink")
	if L then
		local s = Safe(L.GetNativeQuestLinkStringById, id) or Safe(L.GetQuestLinkStringById, id)
		if type(s) == "string" and s ~= "" then return s end
	end
	-- (an older Questie without those: the same bracket text, which its chat filter reads)
	local DB = QDB() or QD.AnyModule("QuestieDB")
	local name = DB and Safe(DB.QueryQuestSingle, id, "name")
	if not ns.Str(name) then return nil end
	return "[" .. name .. " (" .. id .. ")]"
end
local function QuestieShareLink(t) return I.QuestieQuestLink(t.qid) end

local function Status(id)
	return InLog(id) and "in log" or (Done(id) and "done" or nil)
end

local function Giver(fn)
	return function(entry)
		local npcID, npcName, other = QuestGiver(entry.qid)
		if not npcID then
			ns:Print(entry.name .. (other and (" is started by " .. other .. ".") or ": Questie doesn't know who starts it."))
			return
		end
		fn({ name = entry.name, npcID = npcID, npcName = (npcName or "quest giver") .. " (" .. entry.name .. ")" })
	end
end
local GIVER_AFTER, GIVER_OPEN = Giver(ShowNpc), Giver(OpenNpcDirect)

-- a field that comes from the quest log entry while the quest is in the log
local function FromLog(field, otherwise)
	return function(t)
		local l = InLog(t.qid) and LogEntry(t.qid)
		if l then return l[field] end
		return otherwise
	end
end

--- A Questie quest's tooltip (0.45.10): the log's own when you're on it (progress and all), else Questie's: level,
--- zone, the level it needs, its objectives, who starts it, then its rewards (ns.QuestTip, Quests.lua: the game's
--- numbers where it has them, QuestieDB's experience otherwise).
local function QuestieTooltip(e, t)
	local QT = ns.QuestTip
	local id = e.qid
	local l = InLog(id) and LogEntry(id)
	if l and l.tooltip then return l.tooltip(l, t) end
	local DB = QDB()
	local lines = {}
	local objs = DB and Safe(DB.QueryQuestSingle, id, "objectivesText")
	for _, s in ipairs(type(objs) == "table" and objs or {}) do
		if ns.Str(s) then lines[#lines + 1] = s end
	end
	local needs = DB and ns.Num(Safe(DB.QueryQuestSingle, id, "requiredLevel"))
	local npcID, npcName, other = QuestGiver(id)
	local done = Done(id)
	QT.Draw(t, { id = id, name = e.name, level = e.level, zone = e.zone, needs = needs, lines = lines,
		giver = npcName or other, status = done and "Done" or nil, statusColour = done and QT.COLOURS[1] or nil })
end

-- (qid is the row's key, read through here: a row of 8 raw fields grew to a 16-slot table the first time a search
-- wrote its score on it, ~1.6 MB over 5000 quests; 7 leave room)
local QUESTIE_LAZY = {
	qid = function(t) return rawget(t, "key") end,
	detail = function(t)
		local parts = {}
		if t.level and t.level > 0 then parts[#parts + 1] = "Lv " .. t.level end
		if t.zone then parts[#parts + 1] = t.zone end
		local st = Status(t.qid)
		if st then parts[#parts + 1] = st end
		return table.concat(parts, "  ")
	end,
	icon = function(t)
		return Done(t.qid) and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\GossipFrame\\AvailableQuestIcon"
	end,
	-- Shift+Enter: the quest in the game (log, or the giver on the map), through the game's own key
	-- (Maps.lua loads before this file, so its specs are there to read; made once, not per lazy read)
	secondarySecure = FromLog("secure", ns.Maps.SECURE),
	secondaryIsOpen = FromLog("isOpen", ns.Maps.IsOpenFor),
	-- the zone the map switches to for a quest you don't have: its giver's
	mapTarget = function(t)
		local npcID = QuestGiver(t.qid)
		return npcID and (NpcLocation(npcID)) or nil
	end,
	secondaryAfter = FromLog("after", GIVER_AFTER),
	secondary = FromLog("activate", GIVER_OPEN),
}

local function SetupQuestie()
	-- Questie, or the QuestieDB addon alone (a Blizzard-like UI with Questie's data)
	if npc.on or not (QD.HasQuestie() or QD.Lib()) then return end
	npc.on = true
	ns:RegisterProvider("npc", {
		busy = function() return npc.busy and "Indexing Questie's NPCs" or nil end,
		hintFind = function(_, tokens, tick) return HintFind(npc, tokens, tick) end,
		hintRow = NpcHintRow,
		label = "NPC",
		color = "ffe0a060",
		aliases = { "npc", "npcs", "n", "mob", "vendor" },
		hintLabel = "Questie's NPCs",
		explicit = true, -- tens of thousands of names: only searched with @npc
		noCombat = true,
		idleDrop = 600, -- freed after 10 minutes without an @npc search; re-read when next wanted
		held = function() return npc.list ~= nil end,
		onDrop = function() npc.list = nil; ClearNpcFields() end, -- (and the NPCs' small fields the filters read)
		collect = function()
			if not npc.list then IndexNPCs() end
			return npc.list or {}
		end,
	})
	-- @mailbox: every mailbox QuestieDB knows (its objects), one row per spot; sort:nearest, near:, in: work on it
	if QD.Lib() and type(QD.Lib().Object) == "table" or (QDB() and QDB().QueryObjectSingle) then
		ns:RegisterProvider("mailbox", {
			label = "Mailbox",
			color = "ffc9a0dc",
			aliases = { "mailbox", "mailboxes", "mail" },
			explicit = true, -- (only with @mailbox, or "nearest mailbox" in Simple mode)
			lazy = true,
			collect = function() return I.ObjectRows("mailbox") end,
		})
	end
	npc.meta = ns:CompactMeta(ns.providers.npc, {
		icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
		secure = ns.Maps.SECURE,
		isOpen = ns.Maps.IsOpenFor,
		after = ShowNpc,
		activate = OpenNpcDirect,
		secondarySecure = NPC_TARGET,
		secondaryIsOpen = NeverTargeted,
		secondary = TargetFallback,
	}, {
		npcID = function(t) return rawget(t, "key") end,
		detail = function(t) return rawget(t, "sub") or ("NPC  #" .. t.npcID) end,
		mapTarget = function(t) return (NpcLocation(t.npcID)) end, -- the zone the map switches to
	})
	ns:RegisterProvider("questie", {
		label = "Questie",
		color = "ffb48cff",
		aliases = { "questie", "questdb", "allquests" },
		hintLabel = "Questie's quests",
		explicit = true, -- every quest in the game: only searched with @questie
		busy = function() return qdb.busy and "Indexing Questie's quests" or nil end,
		hintFind = function(_, tokens, tick) return HintFind(qdb, tokens, tick) end,
		hintRow = QuestHintRow,
		-- Enter only shows a link (fine in combat); Shift+Enter opens windows (not in combat).
		-- No quest events: a quest's state (in log, done) is read when its row is drawn.
		-- (kept: a few thousand quests, and their objectives are the slow part to read again)
		collect = function()
			if not qdb.list then IndexQuests() end
			return qdb.list or {}
		end,
	})
	qdb.meta = ns:CompactMeta(ns.providers.questie, { activate = CopyQuestLink, shareLink = QuestieShareLink, noCombatSecondary = true,
		tooltip = QuestieTooltip }, QUESTIE_LAZY)
	-- built in the background after login (with their names text); the NPC list is freed when
	-- unused and built again for the next @npc search, the quest list (a few thousand) is kept
	-- one after the other (both at once doubled the work per frame right after login)
	local function index()
		C_Timer.After(2, function() IndexNPCs(IndexQuests) end)
	end
	QD.OnReady(index)
end

I._.ObjectivesText, I._.SetupQuestie = ObjectivesText, SetupQuestie

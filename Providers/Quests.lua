local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight

-- Quests are searched by title AND by their description, objectives and zone,
-- so "kill 10 boars" or a snippet of flavour text finds the quest.
--
-- Opening one: the map's quest panel is opened and turned to the quest's details by the game's own clicks (0.46.18:
-- its micro button, then the quest's row: QUEST_NAV below), and Terminal points at them. Until 0.46.2 a game-pressed
-- /run QuestMapFrame_OpenToQuestDetails did it, but a /run line runs tainted too (0.46.1: the game blames it as
-- "*** ForceTaint_Strong ***"), and that call wrote the map's focused quest and its details' quest: the map's quest
-- pins, rebuilt from them later (often in combat), then failed (blocked SetPassThroughButtons). A click the game makes
-- on the row writes them clean. Without that route the log is opened with your quest key and the row pointed at (when
-- it scrolls into view, too). Nothing in the map's list is scrolled from here (Blizzard's ScrollBox, written by
-- Terminal's code). In a classic-style log (ClassicUIForever's, its own frames) the quest is selected and scrolled to.

-- quest windows, first visible wins; any other visible "...Quest..." window is tried after
local LOGS = { "ForeverClassicUIQuestLog", "QuestLogFrame", "QuestLogDetailFrame", "QuestLogExFrame", "ClassicQuestLog" }
-- the map's quest list: protected surroundings, so only point at it, never click in it
local MAP_LOGS = { "QuestMapFrame" }

local Visible = ns.Usable

-- Frames with "Quest" in their name that are not quest log windows: our own, Questie's
-- (its tracker is always on screen), and the game's watch/tracker/timer/pin pieces.
-- (0.49.2, review: QuestFrame, the game's quest dialog with an NPC, is no log: its greeting's title buttons hold quest
-- titles, and one was clicked from Terminal's code, which chose that quest in the dialog, tainted)
local function NotAWindow(name)
	return name:find("^Terminal") or name:find("^Questie") or name:find("Tracker") or name:find("Watch")
		or name:find("Timer") or name:find("POI") or name:find("Tooltip") or name:find("Banner") or name == "QuestFrame"
end

--- Did an addon make the frame named `name` (its global written by an addon, not by the game's own code)? Read only;
--- no way to tell: no. (0.49.2, review: a row in a window the game owns is only pointed at, never clicked from here)
local function AddonMade(name)
	local check = _G.issecurevariable
	if type(check) ~= "function" then return false end
	local ok, secure = pcall(check, name)
	return ok and secure == false
end

--- Visible quest windows: { frame, clickable }
local function QuestWindows()
	local out, seen = {}, {}
	for _, name in ipairs(LOGS) do
		local f = _G[name]
		if Visible(f) then out[#out + 1] = { f, true }; seen[f] = true end
	end
	local function Skip(name) return NotAWindow(name) or name == "QuestMapFrame" or name == "WorldMapFrame" end
	for _, w in ipairs(ns.VisibleWindows("Quest", Skip)) do
		local f, name = w[1], w[2]
		if not seen[f] then
			out[#out + 1] = { f, AddonMade(name) } -- (any other window: an addon's is clicked, the game's only pointed at)
			seen[f] = true
		end
	end
	for _, name in ipairs(MAP_LOGS) do
		local f = _G[name]
		if Visible(f) then out[#out + 1] = { f, false } end
	end
	return out
end

--- Is a quest log window showing (a classic log, or the map's quest panel)? Only the real quest
--- log windows count, not any other frame that happens to have "Quest" in its name: one of those
--- being on screen made Terminal skip opening the log. Also the Quest Log panel row's check, which
--- must not toggle an open log closed.
local function LogShown()
	for _, name in ipairs(LOGS) do
		if Visible(_G[name]) then return true end
	end
	return Visible(_G.QuestMapFrame) and Visible(_G.WorldMapFrame) and true or false
end

local Plain = ns.Plain -- (Locale.lua)

-- a row label that is the title, or ends with it ("[5] Title", "[2] Title" for party)
local function TitleMatch(f, title)
	local texts = ns.FrameTexts(f)
	for _, t in ipairs(texts) do
		t = Plain(t)
		if t == title or (#t > #title and t:sub(-#title) == title and t:sub(-#title - 1, -#title - 1) == " ") then
			return true
		end
	end
	return false
end

-- Runs once the quest log is open: select the quest and point at it.
local function WindowNames()
	local names = {}
	for _, w in ipairs(QuestWindows()) do
		names[#names + 1] = (ns.FrameName(w[1]) or "?") .. (w[2] and "" or " (point only)")
	end
	return #names > 0 and table.concat(names, ", ") or "none"
end

--- A classic-style quest log window: scroll its list to the quest (as Questie does).
local function ScrollClassicList(idx)
	local sf = _G.QuestLogListScrollFrame
	local bar = (sf and sf.ScrollBar) or _G.QuestLogListScrollFrameScrollBar
	if not (bar and bar.SetValue and bar.GetValueStep) then return false end
	local step = bar:GetValueStep() or 0
	if step <= 0 then step = 16 end
	pcall(bar.SetValue, bar, math.max(0, idx * step - step * 3))
	ns:Trace("quests: scrolled the quest log list to entry " .. idx)
	return true
end

-- looks (a tenth of a second apart) for the quest's row: it's pointed at whenever it scrolls into view in that time
local Q_WATCH = 150

--- A row's quest: a quest log row's questID, or a Questie row's qid (its Shift+Enter is the log row's press when the quest
--- is in your log: QuestieQuests.lua's FromLog hands it this file's secure/isOpen/after, with the Questie row as `e`).
local function QuestID(e)
	if type(e) ~= "table" then return nil end
	local id = e.questID or e.qid
	return type(id) == "number" and id or nil
end

local function ShowQuestAfter(e)
	local qid = QuestID(e)
	if not qid then return end
	if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, qid) end
	local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid)
	-- a classic-style quest log (a classic client's, or ClassicUIForever's): select the quest the way clicking
	-- it does, and scroll to it. (This client's own log is the map's panel, only pointed at below.)
	if idx and (Visible(_G.QuestLogFrame) or Visible(_G.ForeverClassicUIQuestLog)
		or (_G.QuestLog_SetSelection and not Visible(_G.QuestMapFrame))) then
		ScrollClassicList(idx)
		if _G.QuestLog_SetSelection then
			ns:Trace("quests: QuestLog_SetSelection(" .. idx .. ")")
			pcall(_G.QuestLog_SetSelection, idx)
		elseif _G.SelectQuestLogEntry then
			ns:Trace("quests: SelectQuestLogEntry(" .. idx .. ")")
			pcall(_G.SelectQuestLogEntry, idx)
		end
		if _G.QuestLog_UpdateQuestDetails then pcall(_G.QuestLog_UpdateQuestDetails) end
		if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end
	end
	-- the map's quest panel: its details already on this quest are pointed at; else the quest's row in the list, as it
	-- shows (never scrolled or opened from here: see the top of this file)
	if Visible(_G.QuestMapFrame) and not InCombatLockdown() then
		local details = _G.QuestMapFrame.DetailsFrame
		if Visible(details) and rawget(details, "questID") == qid then
			ns:Trace("quests: the quest's details are showing in the map's quest panel; pointing at them")
			H:Show(details)
			return
		end
	end
	ns:Trace("quests: looking for '" .. tostring(e.name) .. "' in " .. WindowNames())
	local seen = false
	H:When(function()
		local wins = QuestWindows()
		if #wins == 0 then if seen then return false end return nil end -- (closed again after it showed: nothing more to look for)
		seen = true
		for _, w in ipairs(wins) do
			local row = ns.FindFrame(w[1], function(f) return f.Click and TitleMatch(f, e.name) end, 14)
			if row then return { row = row, click = w[2], window = w[1] } end
		end
	end, function(hit)
		ns:Trace("quests: found the row in " .. (ns.FrameName(hit.window) or "?") .. (hit.click and ", clicking it" or ", pointing only"))
		if hit.click then pcall(hit.row.Click, hit.row) end -- selects it in that log
		H:Show(hit.row)
	end, Q_WATCH, function()
		ns:Trace("quests: no row titled '" .. tostring(e.name) .. "' found; quest windows: " .. WindowNames())
	end)
end

-- Fallback when the secure path isn't available: the quest log showing, the quest is pointed at there; else said. Never
-- in combat (review, 0.48.6). (0.49.2, review: no ToggleQuestLog / ToggleWorldMap from Terminal's code here any more:
-- the map then held what it wrote. Said instead, as Spells' and Currency's fallbacks do)
local function ShowQuest(e)
	if InCombatLockdown() then ns:Print(L["In combat: can't open %s now."]:format(tostring(e.name))) return end
	if LogShown() then return ShowQuestAfter(e) end
	ns:Print(L["Open your quest log to see %s (opening it from Terminal's own code would taint it)."]:format(tostring(e.name)))
end

local function TrackQuest(e)
	C_SuperTrack.SetSuperTrackedQuestID(e.questID)
	ns:Print(L["Tracking: %s"]:format(e.name))
end

local QUEST_SECURE = { binding = "TOGGLEQUESTLOG", buttons = { "QuestLogMicroButton" } }

-- The map's quest panel (this client's own quest log) goes on to the quest's details by the game's own clicks (0.46.18,
-- Secure.lua's "Turning a window"): the press opens the log with its micro button when it's closed, then each step
-- clicks the details' back button (another quest's details showing), the quest's header (folded: it's unfolded, and
-- its row comes on the next look), or the quest's own row, which the log answers by showing its details (its own
-- code, untainted: the focused quest it writes is clean). Read only: the panel's pools of rows. A classic-style log
-- (ClassicUIForever's), your quest key taken by another addon, or the route turned off (.nav): as before.
local function QuestPanel() return _G.QuestMapFrame end
local function DetailsOf(qm)
	if not qm then return nil end
	local d = rawget(qm, "DetailsFrame")
	if d then return d end
	local qf = rawget(qm, "QuestsFrame")
	return qf and rawget(qf, "DetailsFrame") or nil
end

--- The first of the pool's active buttons whose `key` is `value` (read only; the caller checks it shows), else nil.
local function PoolButton(pool, key, value)
	if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return nil end
	local ok, it, st, k = pcall(pool.EnumerateActive, pool)
	if not ok or type(it) ~= "function" then return nil end
	for f in it, st, k do
		if type(f) == "table" and rawget(f, key) == value then return f end
	end
end

--- The header the quest sits under in your log (its log index) and whether it's folded; nil without one.
local function HeaderOf(questID)
	local idx = C_QuestLog.GetLogIndexForQuestID and ns.Safe(C_QuestLog.GetLogIndexForQuestID, questID)
	if type(idx) ~= "number" or not C_QuestLog.GetInfo then return nil end
	for i = idx - 1, 1, -1 do
		local info = ns.Safe(C_QuestLog.GetInfo, i)
		if type(info) == "table" and info.isHeader then return i, info.isCollapsed == true end
	end
end
-- the panel's pools of header buttons (campaigns and callings have their own)
local HEADER_POOLS = { "headerFramePool", "campaignHeaderFramePool", "campaignHeaderMinimalFramePool", "covenantCallingsHeaderFramePool" }

--- One step toward the quest's details in the map's quest panel: the button to click, and why; nil when they show.
local function QuestNavStep(e)
	local qid = QuestID(e)
	if not qid then return nil, "no quest" end
	local qm = QuestPanel()
	if not Visible(qm) then return nil, "the quest log isn't showing" end
	-- (a click with Shift held tracks the quest instead; the chat box open: it would link it)
	if IsShiftKeyDown and IsShiftKeyDown() then return nil, "Shift is held" end
	local det = DetailsOf(qm)
	if Visible(det) then
		if rawget(det, "questID") == qid then return nil, "its details show" end
		local back = rawget(det, "BackFrame")
		return back and rawget(back, "BackButton") or nil, "another quest's details: back to the list"
	end
	local sf = _G.QuestScrollFrame
	local row = sf and PoolButton(rawget(sf, "titleFramePool"), "questID", qid)
	if row and Visible(row) then return row, "the quest's row" end
	local hdr, folded = HeaderOf(qid)
	if hdr and folded and sf then
		for _, key in ipairs(HEADER_POOLS) do
			local h = PoolButton(rawget(sf, key), "questLogIndex", hdr)
			if h and Visible(h) then return h, "unfold its header" end
		end
	end
	return nil, "its row isn't in the list"
end

local QUEST_NAV = {
	route = "questlog", step = QuestNavStep,
	-- what the clicks write, read after the press: the quest the details show
	watch = { function() return DetailsOf(QuestPanel()), "questID" end },
	watchName = function() return L["the quest log's details"] end,
}

--- Whether the press opens the quest's details by clicks (else the key, and the row pointed at).
local function QuestTurns(e)
	if not QuestID(e) or not ns.Secure.NavOn("questlog") then return false end
	for _, name in ipairs(LOGS) do if Visible(_G[name]) then return false end end -- (a classic-style log)
	if ns.Secure.EffectiveAction("TOGGLEQUESTLOG") ~= "TOGGLEQUESTLOG" then return false end -- (your key opens another addon's)
	return QuestPanel() ~= nil
end

local function QuestNavMacro(e)
	if not QuestTurns(e) then return nil end
	local open
	if not Visible(QuestPanel()) then
		open = ns.Secure.ClickLine("QuestLogMicroButton")
		if not open then return nil end
	end
	return (ns.Secure.NavMacro(QUEST_NAV, e, open))
end
local QUEST_NAV_SECURE = { macro = QuestNavMacro, binding = "TOGGLEQUESTLOG", buttons = { "QuestLogMicroButton" } }
-- open = nothing to press (the quest key would toggle an open log shut); the map's panel turned to the quest is always
-- pressed (its macro opens it only when it's closed)
local function QuestIsOpen(e) return LogShown() and not QuestTurns(e) end

local Str, Num = ns.Str, ns.Num -- (quest text can be a secret value on this client)
local Secret, Call = ns.Secret, ns.Safe
local Lower = ns.Lower

----------------------------------------------------------------------
-- Quests to drop (the question and the group drop: QuestDrop.lua)
--
-- Only the game's own judgement, nothing copied from another addon: a quest is grey when the quest log colours it grey
-- for your level (Forever's QuestMapFrame colours titles by C_PlayerInfo.GetContentDifficultyQuestForPlayer: Trivial;
-- C_QuestLog.IsQuestTrivial where that's missing), and in a zone left behind when that zone's levels (C_Map.GetMapLevels
-- of GetQuestUiMapID: the range the world map shows by the zone's name) top out below your level. A complete quest is
-- never one to drop: it's to be turned in. Shift+Enter on one to drop opens Terminal's own confirmation (DropAsk ->
-- QuestDrop.lua's QD.Confirm), since 0.46.2: the game's Abandon (QuestMapQuestOptions_AbandonQuest) is Blizzard Lua, and a
-- /run line calling it ran tainted.
----------------------------------------------------------------------


-- (0.63.7, review: one answer for how hard a quest is, where three disagreed when the game gave none)
local RCD = (Enum and Enum.RelativeContentDifficulty) or {}
-- the game's difficulty -> 0 grey, 1 green, 2 yellow, 3 orange, 4 red (QT.COLOURS' and DIFF_NAME's order)
local DIFF_STEP = { [RCD.Trivial or 0] = 0, [RCD.Easy or 1] = 1, [RCD.Fair or 2] = 2, [RCD.Difficult or 3] = 3, [RCD.Impossible or 4] = 4 }
local DIFF_NAME = { [0] = "grey", "green", "yellow", "orange", "red" }

--- How hard the quest is for you: 0 grey, 1 green, 2 yellow, 3 orange, 4 red; nil when nothing says. The game's own
--- judgement (as the quest log colours it), else whether it's trivial, else by levels as the classic log did (5+ above
--- red, 3-4 orange, within 2 yellow, green to GetQuestGreenRange below, then grey). `me`: your level, when known.
local function Difficulty(id, level, me)
	local f = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
	local d = f and id and Call(f, id)
	if not Secret(d) and type(d) == "number" and DIFF_STEP[d] then return DIFF_STEP[d] end
	f = C_QuestLog.IsQuestTrivial
	local t = f and id and Call(f, id)
	if not Secret(t) and t == true then return 0 end
	me = me or (_G.UnitLevel and Num(Call(_G.UnitLevel, "player")))
	if not (me and me > 0 and level and level > 0) then return nil end
	local x = level - me
	if x >= 5 then return 4 elseif x >= 3 then return 3 elseif x >= -2 then return 2 end
	local green = (_G.GetQuestGreenRange and Num(Call(_G.GetQuestGreenRange))) or 8
	return (-x > green) and 0 or 1
end

--- Whether the game shows this quest grey for your level.
local function Grey(id, level, me) return Difficulty(id, level, me) == 0 end

--- Ready to turn in (or complete): never one to drop.
local function Complete(id)
	local f = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
	local c = f and Call(f, id)
	return not Secret(c) and c == true
end

--- The quest's zone and its levels as the world map says them: { lo, hi, name }, or nil (no zone, no levels: a city).
--- `cache` keeps each zone's answer for one rebuild.
local function ZoneLevels(id, cache)
	local ui = _G.GetQuestUiMapID and Call(_G.GetQuestUiMapID, id)
	if Secret(ui) or type(ui) ~= "number" or ui <= 0 or not (C_Map and C_Map.GetMapLevels) then return nil end
	local z = cache[ui]
	if z == nil then
		z = false
		local lo, hi = Call(C_Map.GetMapLevels, ui)
		if not Secret(lo) and not Secret(hi) and type(hi) == "number" and hi > 0 then
			local info = C_Map.GetMapInfo and Call(C_Map.GetMapInfo, ui)
			z = { lo = type(lo) == "number" and lo > 0 and lo or hi, hi = hi, name = type(info) == "table" and Str(info.name) or nil }
		end
		cache[ui] = z
	end
	return z or nil
end

----------------------------------------------------------------------
-- What a quest is, for bulk tracking (QuestTrack.lua, 0.63.3) and its filters (is:red, is:dungeon, is:class...)
----------------------------------------------------------------------

-- the quest log's colour for your level, as words: is:red, is:orange... (Difficulty)
local function DiffName(id, level, me)
	local d = Difficulty(id, level, me)
	return d and DIFF_NAME[d] or nil
end

-- the quest's tag, as the log says it ("Dungeon", "Raid": C_QuestLog.GetQuestTagInfo's tagID, Enum.QuestTag)
local QTAG = (Enum and Enum.QuestTag) or {}
local TAG_KIND = { [QTAG.Dungeon or 81] = "dungeon", [QTAG.Heroic or 85] = "dungeon", [QTAG.Raid or 62] = "raid",
	[QTAG.Raid10 or 88] = "raid", [QTAG.Raid25 or 89] = "raid" }
local function TagKind(id)
	local f = C_QuestLog.GetQuestTagInfo
	local t = f and Call(f, id)
	if Secret(t) or type(t) ~= "table" then return nil end
	return TAG_KIND[t.tagID]
end

-- an instance's name as the log's headers say it ("The Deadmines", "Dire Maul"): Terminal's entrances list
-- (Integrations/Entrances.lua), read once it's there: "dungeon" or "raid". (The list's names are English: on another
-- client a header names its instance in that language, and only the quest's tag, TagKind, says dungeon or raid.)
local instances
local function InstanceOf(header)
	if not header then return nil end
	if not instances then
		local I = ns.Integrations
		if not (I and I.ENTRANCES) then return nil end
		instances = {}
		for _, d in ipairs(I.ENTRANCES) do
			local n = Lower(d[1]):gsub("%s*%(.-%)", ""):gsub("^the ", "")
			instances[n] = d[5] and "raid" or (instances[n] or "dungeon")
		end
	end
	return instances[(Lower(header):gsub("^the ", ""))]
end

-- class quests sit under their class's name in the log ("Warrior"): every class's name, both forms, and in English
local classNames
local function IsClassHeader(header)
	if not header then return false end
	if not classNames then
		classNames = {}
		for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
			for token, name in pairs(t) do
				if type(name) == "string" then classNames[Lower(name)] = true end
				if type(token) == "string" then classNames[Lower(token)] = true end
			end
		end
		for w in ("warrior paladin hunter rogue priest shaman mage warlock druid"):gmatch("%a+") do classNames[w] = true end
	end
	return classNames[Lower(header)] == true
end

--- Shift+Enter on a quest to drop: Terminal's own confirmation for that one quest (QuestDrop.lua), then the C calls
--- that drop it (C_QuestLog.SetSelectedQuest / SetAbandonQuest / AbandonQuest, from Terminal's code: not protected).
--- Before 0.46.2 the game pressed /run QuestMapQuestOptions_AbandonQuest, the quest log's own Abandon; but a /run line
--- runs tainted, and that shows the game's StaticPopup dialog from it: a popup shown tainted can get later popups
--- (the protected ones too) blocked. The game's dialog is never shown from here.
local function DropAsk(e)
	local QD = ns.QuestDrop
	if QD and QD.Confirm then QD.Confirm({ e }) else ns:Print(L["Couldn't drop %s from here."]:format(tostring(e.name))) end
end

ns.Quests = { SECURE = QUEST_SECURE, LogShown = LogShown,
	NavStep = QuestNavStep, NAV_SECURE = QUEST_NAV_SECURE } -- (the turning: tests)
local function QuestLink(e) return GetQuestLink and GetQuestLink(e.questID) or nil end

--- The quest's objectives, as { { text, type }, ... }: the retail list, else a classic log's leader boards.
local function Objectives(i, questID)
	local out = {}
	local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
	for _, o in ipairs(ok and type(objs) == "table" and objs or {}) do
		local t = type(o) == "table" and Str(o.text)
		if t then out[#out + 1] = { t, o.type } end
	end
	if #out == 0 and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		for j = 1, (Num(GetNumQuestLeaderBoards(i)) or 0) do
			local okb, t, typ = pcall(GetQuestLogLeaderBoard, j, i)
			t = okb and Str(t)
			if t then out[#out + 1] = { t, typ } end
		end
	end
	return out
end

----------------------------------------------------------------------
-- A quest's tooltip (0.45.10, the log's rows and Questie's): its name in the colour the game gives it for your level,
-- level and zone, its objectives, then what it rewards: the experience, the money and (when the game has them) the
-- items. The game's numbers come first (GetQuestLogRewardXP / GetQuestLogRewardMoney / GetQuestLogRewardInfo: a quest
-- in your log, or one whose data the client has loaded); a quest the game gives no experience number for gets
-- QuestieDB's (its Support "QuestXP" table: the quest's level and base experience; through Questie's own QuestXP when
-- Questie is there), scaled to your level by the game's rules and marked as Questie's.
----------------------------------------------------------------------

local QT = {}
ns.QuestTip = QT

-- the game's colours for how hard a quest is for you (C_PlayerInfo.GetContentDifficultyQuestForPlayer)
QT.COLOURS = { [0] = { 0.53, 0.53, 0.53 }, { 0.25, 0.75, 0.25 }, { 1, 1, 0 }, { 1, 0.5, 0.25 }, { 1, 0.1, 0.1 } }
local GOLD, WHITE, DIM = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.62, 0.62, 0.62 }

local function Colour(id, level)
	local d = Difficulty(id, level)
	return d and QT.COLOURS[d] or GOLD
end

local function MaxLevel()
	local f = _G.GetMaxLevelForPlayerExpansion or _G.GetMaxPlayerLevel
	return f and Num(Call(f)) or nil
end

--- What a quest of level `q` worth `xp` gives at level `me`, by the game's rules (classic): all of it up to five levels
--- above the quest, a fifth less for each level past that, never under a tenth; rounded to the game's steps.
function QT.Scale(xp, q, me)
	if not (me and q and q > 0) then return xp end
	local m = math.max(1, math.min(10, 2 * (q - me) + 20))
	xp = xp * m / 10
	if xp <= 100 then xp = 5 * math.floor((xp + 2) / 5)
	elseif xp <= 500 then xp = 10 * math.floor((xp + 5) / 10)
	elseif xp <= 1000 then xp = 25 * math.floor((xp + 12) / 25)
	else xp = 50 * math.floor((xp + 25) / 50) end
	return xp
end

--- QuestieDB's figure for a quest at your level, or nil when it has none.
function QT.QuestieXP(id)
	local QD = ns.QuestieData
	if not QD then return nil end
	-- Questie's own answer (it knows its bonuses: Joyous Journeys, the Darkmoon Faire...)
	local M = QD.Module("QuestXP")
	if M and type(M.db) == "table" and M.db[id] and M.GetQuestLogRewardXP then
		local x = Num(Call(M.GetQuestLogRewardXP, M, id))
		if x then return x end
	end
	local L = QD.Lib()
	local S = L and L.Support
	local X = S and S.Get and Call(S.Get, "QuestXP")
	local row = type(X) == "table" and type(X.db) == "table" and X.db[id]
	local level, xp = type(row) == "table" and tonumber(row[1]), type(row) == "table" and tonumber(row[2])
	if not (level and xp and level > 0 and xp > 0) then return nil end
	local me = _G.UnitLevel and Num(Call(_G.UnitLevel, "player"))
	local cap = MaxLevel()
	if me and cap and me >= cap then return 0 end
	return QT.Scale(xp, level, me)
end

--- The experience a quest gives you, and where the number comes from ("game" / "Questie"); 0 at the level cap; nil when
--- nobody says.
function QT.Experience(id)
	local f = _G.GetQuestLogRewardXP
	if f then
		local total, base = Call(f, id)
		total, base = Num(total), Num(base)
		local x = (total and total > 0 and total) or (base and base > 0 and base) or nil
		if x then return x, "game" end
	end
	local q = QT.QuestieXP(id)
	if q then return q, "Questie" end
	return nil
end

--- The money a quest gives (copper), or nil.
function QT.Money(id)
	local f = _G.GetQuestLogRewardMoney
	local m = f and Num(Call(f, id))
	return m and m > 0 and m or nil
end

-- the items: { { name, texture, count, quality } } given, and those to choose one of
local function Items(id)
	local given, choose = {}, {}
	local function Read(n, info, into)
		for i = 1, math.min(n or 0, 10) do
			local name, tex, count, quality = Call(info, i, id)
			name = Str(name)
			if name then into[#into + 1] = { name, tex, Num(count), Num(quality) } end
		end
	end
	if _G.GetNumQuestLogRewards and _G.GetQuestLogRewardInfo then
		Read(Num(Call(_G.GetNumQuestLogRewards, id)), _G.GetQuestLogRewardInfo, given)
	end
	if _G.GetNumQuestLogChoices and _G.GetQuestLogChoiceInfo then
		Read(Num(Call(_G.GetNumQuestLogChoices, id, true)), _G.GetQuestLogChoiceInfo, choose)
	end
	return given, choose
end

-- asking the game for a quest's data (one asked at a time; the tooltip is drawn again when it comes)
QT.ASK_AGAIN = 30 -- (s before a quest is asked for again)
local waitFor, asked = nil, {}
local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(_, _, id)
	if id ~= waitFor then return end
	waitFor = nil
	waiter:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
	local t = _G.TerminalTooltip
	local e = t and t.IsShown and t:IsShown() and t.entry
	if e and (rawget(e, "questID") or e.questID or e.qid) == id and ns.UI and ns.UI.UpdateTooltip then
		t.entry = nil -- (the same-row shortcut would skip it)
		ns.UI:UpdateTooltip()
	end
end)
QT.waiter = waiter -- (tests)

--- Asks the game for a quest's data when it doesn't have its rewards yet; true while that answer is awaited.
function QT.Ask(id)
	local have = _G.HaveQuestRewardData
	if not have or Call(have, id) ~= false then return false end
	if waitFor == id then return true end
	local R = C_QuestLog and C_QuestLog.RequestLoadQuestByID
	local now = GetTime and GetTime() or 0
	if not R or (asked[id] and now - asked[id] < QT.ASK_AGAIN) then return false end
	asked[id] = now
	waitFor = id
	pcall(waiter.RegisterEvent, waiter, "QUEST_DATA_LOAD_RESULT")
	Call(R, id)
	return true
end
function QT.ForgetAsks() waitFor, asked = nil, {} end -- (tests)

local XP_FORMAT
local function XpText(x)
	if not XP_FORMAT then
		-- the game's words ("%d experience"), taking the number with its thousands marked
		local f = _G.BONUS_OBJECTIVE_EXPERIENCE_FORMAT
		f = type(f) == "string" and f:gsub("%%d", "%%s") or nil
		local _, n = (f or ""):gsub("%%s", "")
		XP_FORMAT = (n == 1 and not f:find("%%[^s%%]")) and f or L["%s experience"]
	end
	return XP_FORMAT:format(ns.Thousands(x))
end

local function Line(t, text, c, wrap) t:AddLine(text, c[1], c[2], c[3], wrap) end

--- Draws a quest on the tooltip `t`. `q`: { id, name, level, zone, needs (required level), lines (objectives, as
--- text), status (a line under them: "Ready to turn in"), statusColour, giver }.
function QT.Draw(t, q)
	local c = Colour(q.id, q.level)
	t:SetText(tostring(q.name), c[1], c[2], c[3], 1, true)
	local head = {}
	if q.level and q.level > 0 then head[#head + 1] = L["Level %d"]:format(q.level) end
	if q.zone and q.zone ~= "" then head[#head + 1] = q.zone end
	if #head > 0 then Line(t, table.concat(head, ns.DETAIL_SEP), DIM) end
	local me = _G.UnitLevel and Num(Call(_G.UnitLevel, "player"))
	if q.needs and me and q.needs > me then Line(t, L["Requires level %d"]:format(q.needs), QT.COLOURS[4]) end
	if q.lines and #q.lines > 0 then
		t:AddLine(" ")
		for i = 1, math.min(#q.lines, 8) do Line(t, q.lines[i], WHITE, true) end
	end
	if q.giver then Line(t, L["Started by %s"]:format(q.giver), DIM, true) end
	if q.status then Line(t, q.status, q.statusColour or DIM) end
	-- what it rewards
	local id = q.id
	local loading = id and QT.Ask(id)
	local xp, from = nil, nil
	if id then xp, from = QT.Experience(id) end
	local money = id and QT.Money(id)
	local given, choose = {}, {}
	if id then given, choose = Items(id) end
	if (xp and xp > 0) or money or #given > 0 or #choose > 0 or loading then
		t:AddLine(" ")
		Line(t, ns.GameText and ns.GameText("QUEST_REWARDS", L["Rewards"]) or L["Rewards"], GOLD)
		if xp and xp > 0 then
			if from == "Questie" then
				t:AddDoubleLine(XpText(xp), L["Questie's figure"], 1, 1, 1, DIM[1], DIM[2], DIM[3])
			else
				Line(t, XpText(xp), WHITE)
			end
		end
		if money then Line(t, ns.Money(money), WHITE) end
		local function Item(it)
			local qc = it[4] and ns.QualityHex and ns.QualityHex(it[4])
			local icon = it[2] and ("|T" .. tostring(it[2]) .. ":0|t ") or ""
			local name = (type(qc) == "string" and qc:find("^|c")) and (qc .. it[1] .. "|r") or it[1] -- (hex: "|cff1eff00")
			Line(t, icon .. name .. ((it[3] and it[3] > 1) and (" x" .. it[3]) or ""), WHITE)
		end
		for _, it in ipairs(given) do Item(it) end
		if #choose > 0 then
			Line(t, ns.GameText and ns.GameText("REWARD_CHOICES", L["Choose one:"]) or L["Choose one:"], DIM, true)
			for _, it in ipairs(choose) do Item(it) end
		end
		if loading then Line(t, ns.GameText and ns.GameText("RETRIEVING_DATA", L["Retrieving data"]) or L["Retrieving data"], DIM) end
	elseif xp == 0 then
		t:AddLine(" ")
		Line(t, L["No experience at your level"], DIM)
	end
end

-- a quest log row's tooltip
local function LogTooltip(e, t)
	local lines = {}
	for _, o in ipairs(e.objectives or {}) do lines[#lines + 1] = o[1] end
	if #lines == 0 and e.objText then lines[1] = e.objText end
	local status, sc
	if e.complete then status, sc = L["Ready to turn in"], QT.COLOURS[1]
	elseif e.drop then status = e.grey and L["Grey for your level: one to drop"] or L["In a zone you've left behind: one to drop"] end
	QT.Draw(t, { id = e.questID, name = e.name, level = e.level, zone = e.zone, lines = lines, status = status, statusColour = sc })
end
QT.LogTooltip = LogTooltip

ns:RegisterProvider("quests", {
	label = L["Quest log"],
	color = "ffffd200",
	aliases = { "questlog", "log", "quest", "quests", "q" },
	-- (a level gained can turn quests grey and leave zones behind)
	events = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" },
	guard = 1,
	refreshOnOpen = true,
	collect = function()
		local out = {}
		local zone
		local me = _G.UnitLevel and Num(Call(_G.UnitLevel, "player"))
		local zones = {} -- (each zone's levels, asked once)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info then
				local title = Str(info.title)
				if info.isHeader then
					zone = title
				elseif info.questID and not info.isHidden and title then -- (a secret title: the quest is left out)
					local parts = { zone or "" }
					local ok, desc, obj = pcall(GetQuestLogQuestText, i)
					desc, obj = ok and Str(desc) or nil, ok and Str(obj) or nil
					parts[#parts + 1] = desc or ""
					parts[#parts + 1] = obj or ""
					local objectives = Objectives(i, info.questID)
					for _, o in ipairs(objectives) do parts[#parts + 1] = o[1] end
					local level = Num(info.level)
					-- one to drop: grey, or in a zone you've left behind; never one ready to turn in
					local diff = Difficulty(info.questID, level, me) -- (once: grey, and is:red...'s colour)
					local grey = diff == 0
					local z = ZoneLevels(info.questID, zones)
					local behind = (z and me and me > 0 and z.hi < me) and z or nil
					local complete = Complete(info.questID)
					local drop = not complete and (grey or behind ~= nil)
					local why = drop and (grey and L["grey"] or L["zone left behind (Lv %d-%d)"]:format(behind.lo, behind.hi)) or nil
					-- (bulk tracking and its filters: the log's colour, a dungeon's or raid's, a class quest)
					local instance = TagKind(info.questID) or InstanceOf(zone)
					out[#out + 1] = {
						key = info.questID,
						name = title,
						icon = "Interface\\GossipFrame\\AvailableQuestIcon",
						detail = ns.Detail((level and level > 0) and L["Lv %d"]:format(level) or nil, zone, why),
						text = table.concat(parts, " "),
						questID = info.questID,
						level = (level and level > 0) and level or nil, zone = zone, -- (lvl: and zone: filters)
						-- the pieces, for the quest items index (Items.lua reads them, not the log again)
						desc = desc, objText = obj, objectives = objectives,
						getLink = QuestLink,
						tooltip = LogTooltip, -- (Terminal draws it: the rewards; the link stays for chat)
						activate = ShowQuest,
						secure = QUEST_NAV_SECURE,
						isOpen = QuestIsOpen,
						after = ShowQuestAfter,
						-- (quests to drop: QuestDrop.lua, the is:grey / is:leftbehind / is:drop filters)
						grey = grey, behind = behind, complete = complete, drop = drop,
						diffName = diff and DIFF_NAME[diff] or nil, instance = instance,
						classQuest = IsClassHeader(zone) or nil,
						-- Shift+Enter: one to drop, Terminal asks and drops it; any other, super-track it (the waypoint arrow)
						secondary = drop and DropAsk or TrackQuest,
					}
				end
			end
		end
		return out
	end,
})

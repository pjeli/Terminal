local ns = select(2, ...)
local H = ns.Highlight

-- Quests are searched by title AND by their description, objectives and zone,
-- so "kill 10 boars" or a snippet of flavour text finds the quest.
--
-- Opening one: the quest log is opened the way your own quest log key opens it (see
-- Secure.lua). When that log is the map's quest panel (this client's own quest log), Enter
-- (or a click) runs a macro instead, pressed by the game: QuestMapFrame_OpenToQuestDetails,
-- which opens the map on the quest's details. Terminal must never call that itself: it
-- writes the map's focused quest, and the map's quest pins, rebuilt from it later (often in
-- combat), then fail as Terminal's (hundreds of blocked SetPassThroughButtons). Afterwards
-- Terminal only points at the details. In a classic-style log the quest is selected and
-- scrolled to.

-- quest windows, first visible wins; any other visible "...Quest..." window is tried after
local LOGS = { "ForeverClassicUIQuestLog", "QuestLogFrame", "QuestLogDetailFrame", "QuestLogExFrame", "ClassicQuestLog" }
-- the map's quest list: protected surroundings, so only point at it, never click in it
local MAP_LOGS = { "QuestMapFrame" }

local function Visible(f)
	return type(f) == "table" and not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible()
end

-- Frames with "Quest" in their name that are not quest log windows: our own, Questie's
-- (its tracker is always on screen), and the game's watch/tracker/timer/pin pieces.
local function NotAWindow(name)
	return name:find("^Terminal") or name:find("^Questie") or name:find("Tracker") or name:find("Watch")
		or name:find("Timer") or name:find("POI") or name:find("Tooltip") or name:find("Banner")
end

--- Visible quest windows: { frame, clickable }
local function QuestWindows()
	local out, seen = {}, {}
	for _, name in ipairs(LOGS) do
		local f = _G[name]
		if Visible(f) then out[#out + 1] = { f, true }; seen[f] = true end
	end
	for _, f in ipairs({ UIParent:GetChildren() }) do
		local name = ns.FrameName(f)
		if name and name:find("Quest") and not NotAWindow(name)
			and not seen[f] and Visible(f) and name ~= "QuestMapFrame" and name ~= "WorldMapFrame" then
			out[#out + 1] = { f, true }
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

--- Does the quest key open the map's quest panel (no classic log in its place)? Then Enter
--- runs the quest-details macro, whether the log is open or not.
local function MapRoute()
	if type(_G.QuestMapFrame_OpenToQuestDetails) ~= "function" then return false end
	for _, name in ipairs(LOGS) do
		if _G[name] then return false end
	end
	return ns.Secure.EffectiveAction("TOGGLEQUESTLOG") == "TOGGLEQUESTLOG"
end

--- The macro the game runs for a quest (log entries have questID, Questie's have qid).
local function QuestMacro(e)
	local id = type(e) == "table" and (e.questID or e.qid) or nil
	if type(id) ~= "number" or not MapRoute() then return nil end
	return ("/run QuestMapFrame_OpenToQuestDetails(%d)"):format(id)
end

local function IsOpen()
	if MapRoute() then return false end -- the macro switches the details even when it's open
	return LogShown()
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

--- The map's quest list (the game's own quest log on this client): scroll it to the quest so
--- its row exists. Only scrolls; nothing in the map is clicked.
local function ScrollMapList(questID)
	local sf = _G.QuestScrollFrame
	local box = sf and sf.ScrollBox
	if not (box and box.ScrollToElementDataByPredicate) then return false end
	local ok = ns.ScrollBoxTo(box, function(d)
		return d.questID == questID or (type(d.info) == "table" and d.info.questID == questID)
	end)
	ns:Trace("quests: scrolled the map's quest list" .. (ok and "" or " (failed)"))
	return ok
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

local function ShowQuestAfter(e)
	if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, e.questID) end
	local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(e.questID)
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
	-- the map's quest panel: the game's macro opened the quest's details; only point at them
	-- (never open them from here: see the top of this file)
	if Visible(_G.QuestMapFrame) and not InCombatLockdown() then
		local details = _G.QuestMapFrame.DetailsFrame
		if Visible(details) then
			ns:Trace("quests: the quest's details are showing in the map's quest panel; pointing at them")
			H:Show(details)
			return
		end
		ScrollMapList(e.questID)
	end
	ns:Trace("quests: looking for '" .. tostring(e.name) .. "' in " .. WindowNames())
	H:When(function()
		for _, w in ipairs(QuestWindows()) do
			local row = ns.FindFrame(w[1], function(f) return f.Click and TitleMatch(f, e.name) end, 14)
			if row then return { row = row, click = w[2], window = w[1] } end
		end
	end, function(hit)
		ns:Trace("quests: found the row in " .. (ns.FrameName(hit.window) or "?") .. (hit.click and ", clicking it" or ", pointing only"))
		if hit.click then pcall(hit.row.Click, hit.row) end -- selects it in that log
		H:Show(hit.row)
	end, 30, function()
		ns:Trace("quests: no row titled '" .. tostring(e.name) .. "' found; quest windows: " .. WindowNames())
	end)
end

-- Fallback when the secure path isn't available (combat): open the quest log directly.
local function ShowQuest(e)
	ns:Trace("DIRECT ToggleQuestLog (addon code, may be blocked)")
	if ToggleQuestLog then
		pcall(ToggleQuestLog)
	elseif ToggleWorldMap then
		pcall(ToggleWorldMap)
	end
	C_Timer.After(0.05, function() ShowQuestAfter(e) end)
end

local function TrackQuest(e)
	C_SuperTrack.SetSuperTrackedQuestID(e.questID)
	ns:Print("Tracking: " .. e.name)
end

local QUEST_SECURE = { macro = QuestMacro, binding = "TOGGLEQUESTLOG", buttons = { "QuestLogMicroButton" } }

local Str, Num = ns.Str, ns.Num -- (quest text can be a secret value on this client)
local Secret, Call = ns.Secret, ns.Safe

----------------------------------------------------------------------
-- Quests to drop (the question and the group drop: QuestDrop.lua)
--
-- Only the game's own judgement, nothing copied from another addon: a quest is grey when the quest log colours it grey
-- for your level (Forever's QuestMapFrame colours titles by C_PlayerInfo.GetContentDifficultyQuestForPlayer: Trivial;
-- C_QuestLog.IsQuestTrivial where that's missing), and in a zone left behind when that zone's levels (C_Map.GetMapLevels
-- of GetQuestUiMapID: the range the world map shows by the zone's name) top out below your level. A complete quest is
-- never one to drop: it's to be turned in. Shift+Enter on one to drop has the game ask, as the quest log's own Abandon
-- does: the press runs QuestMapQuestOptions_AbandonQuest (it picks the dialog that also names the quest's items).
----------------------------------------------------------------------

local TRIVIAL = (Enum and Enum.RelativeContentDifficulty and Enum.RelativeContentDifficulty.Trivial) or 0

--- Whether the game shows this quest grey for your level.
local function Grey(id)
	local f = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
	if f then
		local d = Call(f, id)
		if not Secret(d) and type(d) == "number" then return d == TRIVIAL end
	end
	f = C_QuestLog.IsQuestTrivial
	local t = f and Call(f, id)
	return not Secret(t) and t == true
end

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

--- The press that has the game ask before dropping the quest (its own Abandon, with its own dialog).
local function DropMacro(e)
	local id = type(e) == "table" and e.questID
	if type(id) ~= "number" then return nil end
	if type(_G.QuestMapQuestOptions_AbandonQuest) == "function" then
		return ("/run QuestMapQuestOptions_AbandonQuest(%d)"):format(id)
	end
	return ('/run local q=%d C_QuestLog.SetSelectedQuest(q) C_QuestLog.SetAbandonQuest() StaticPopup_Show("ABANDON_QUEST",C_QuestLog.GetTitleForQuestID(q))'):format(id)
end
local DROP_SPEC = { macro = DropMacro }
local function DropAsked(e) ns:Trace("quests: the game asks before dropping " .. tostring(e.name)) end
-- (only when the game couldn't be handed the press: Terminal never shows that dialog itself)
local function DropFallback(e)
	ns:Print(InCombatLockdown() and ("In combat: drop " .. tostring(e.name) .. " once the fight is over.")
		or ("Couldn't ask the game to drop " .. tostring(e.name) .. ": the quest log's own Abandon does."))
end

ns.Quests = { SECURE = QUEST_SECURE, LogShown = LogShown, DROP_SPEC = DROP_SPEC, DropMacro = DropMacro,
	Grey = Grey, ZoneLevels = ZoneLevels }
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
	local f = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
	local d = f and id and Call(f, id)
	if not Secret(d) and type(d) == "number" and QT.COLOURS[d] then return QT.COLOURS[d] end
	-- (no answer: by level, as the classic log did: 5+ above red, 3-4 orange, within 2 yellow, then green, then grey)
	local me = _G.UnitLevel and Num(Call(_G.UnitLevel, "player"))
	if not (me and level and level > 0) then return GOLD end
	local diff = level - me
	if diff >= 5 then return QT.COLOURS[4] elseif diff >= 3 then return QT.COLOURS[3] elseif diff >= -2 then return QT.COLOURS[2] end
	local grey = (_G.GetQuestGreenRange and Num(Call(_G.GetQuestGreenRange))) or 8
	return (-diff > grey) and QT.COLOURS[0] or QT.COLOURS[1]
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
		XP_FORMAT = (n == 1 and not f:find("%%[^s%%]")) and f or "%s experience"
	end
	local T = ns.Gold and ns.Gold.Thousands
	return XP_FORMAT:format(T and T(x) or tostring(x))
end

local function Line(t, text, c, wrap) t:AddLine(text, c[1], c[2], c[3], wrap) end

--- Draws a quest on the tooltip `t`. `q`: { id, name, level, zone, needs (required level), lines (objectives, as
--- text), status (a line under them: "Ready to turn in"), statusColour, giver }.
function QT.Draw(t, q)
	local c = Colour(q.id, q.level)
	t:SetText(tostring(q.name), c[1], c[2], c[3], 1, true)
	local head = {}
	if q.level and q.level > 0 then head[#head + 1] = "Level " .. q.level end
	if q.zone and q.zone ~= "" then head[#head + 1] = q.zone end
	if #head > 0 then Line(t, table.concat(head, "  ·  "), DIM) end
	local me = _G.UnitLevel and Num(Call(_G.UnitLevel, "player"))
	if q.needs and me and q.needs > me then Line(t, "Requires level " .. q.needs, QT.COLOURS[4]) end
	if q.lines and #q.lines > 0 then
		t:AddLine(" ")
		for i = 1, math.min(#q.lines, 8) do Line(t, q.lines[i], WHITE, true) end
	end
	if q.giver then Line(t, "Started by " .. q.giver, DIM, true) end
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
		Line(t, ns.GameText and ns.GameText("QUEST_REWARDS", "Rewards") or "Rewards", GOLD)
		if xp and xp > 0 then
			if from == "Questie" then
				t:AddDoubleLine(XpText(xp), "Questie's figure", 1, 1, 1, DIM[1], DIM[2], DIM[3])
			else
				Line(t, XpText(xp), WHITE)
			end
		end
		if money then Line(t, ns.Gold and ns.Gold.Text and ns.Gold.Text(money) or (money .. "c"), WHITE) end
		local function Item(it)
			local qc = it[4] and ns.QualityHex and ns.QualityHex(it[4])
			local icon = it[2] and ("|T" .. tostring(it[2]) .. ":0|t ") or ""
			local name = (type(qc) == "string" and qc:find("^|c")) and (qc .. it[1] .. "|r") or it[1] -- (hex: "|cff1eff00")
			Line(t, icon .. name .. ((it[3] and it[3] > 1) and (" x" .. it[3]) or ""), WHITE)
		end
		for _, it in ipairs(given) do Item(it) end
		if #choose > 0 then
			Line(t, ns.GameText and ns.GameText("REWARD_CHOICES", "Choose one:") or "Choose one:", DIM, true)
			for _, it in ipairs(choose) do Item(it) end
		end
		if loading then Line(t, ns.GameText and ns.GameText("RETRIEVING_DATA", "Retrieving data") or "Retrieving data", DIM) end
	elseif xp == 0 then
		t:AddLine(" ")
		Line(t, "No experience at your level", DIM)
	end
end

-- a quest log row's tooltip
local function LogTooltip(e, t)
	local lines = {}
	for _, o in ipairs(e.objectives or {}) do lines[#lines + 1] = o[1] end
	if #lines == 0 and e.objText then lines[1] = e.objText end
	local status, sc
	if e.complete then status, sc = "Ready to turn in", QT.COLOURS[1]
	elseif e.drop then status = e.grey and "Grey for your level: one to drop" or "In a zone you've left behind: one to drop" end
	QT.Draw(t, { id = e.questID, name = e.name, level = e.level, zone = e.zone, lines = lines, status = status, statusColour = sc })
end
QT.LogTooltip = LogTooltip

ns:RegisterProvider("quests", {
	label = "Quest log",
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
					local grey = Grey(info.questID)
					local z = ZoneLevels(info.questID, zones)
					local behind = (z and me and me > 0 and z.hi < me) and z or nil
					local complete = Complete(info.questID)
					local drop = not complete and (grey or behind ~= nil)
					local why = drop and (grey and "grey" or ("zone left behind (Lv " .. behind.lo .. "-" .. behind.hi .. ")")) or nil
					out[#out + 1] = {
						key = info.questID,
						name = title,
						icon = "Interface\\GossipFrame\\AvailableQuestIcon",
						detail = ((level and level > 0) and ("Lv " .. level .. "  ") or "") .. (zone or "") .. (why and ("  ·  " .. why) or ""),
						text = table.concat(parts, " "),
						questID = info.questID,
						level = (level and level > 0) and level or nil, zone = zone, -- (lvl: and zone: filters)
						-- the pieces, for the quest items index (Items.lua reads them, not the log again)
						desc = desc, objText = obj, objectives = objectives,
						getLink = QuestLink,
						tooltip = LogTooltip, -- (Terminal draws it: the rewards; the link stays for chat)
						activate = ShowQuest,
						secure = QUEST_SECURE,
						isOpen = IsOpen,
						after = ShowQuestAfter,
						-- (quests to drop: QuestDrop.lua, the is:grey / is:leftbehind / is:drop filters)
						grey = grey, behind = behind, complete = complete, drop = drop,
						-- Shift+Enter: one to drop, the game asks to drop it; any other, super-track it (the waypoint arrow)
						secondary = drop and DropFallback or TrackQuest,
						secondarySecure = drop and DROP_SPEC or nil,
						secondaryIsOpen = drop and ns.Never or nil, -- (always pressed: the game's dialog asks)
						secondaryAfter = drop and DropAsked or nil,
					}
				end
			end
		end
		return out
	end,
})

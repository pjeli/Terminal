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
		local ok, name = pcall(function() return f:GetName() end)
		if ok and type(name) == "string" and name:find("Quest") and not NotAWindow(name)
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

--- Is a quest log open? Only the real quest log windows count (a classic log, or the map
--- showing its quest panel), not any other frame that happens to have "Quest" in its name:
--- one of those being on screen made Terminal skip opening the log.
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
	for _, name in ipairs(LOGS) do
		if Visible(_G[name]) then return true end
	end
	return Visible(_G.QuestMapFrame) and Visible(_G.WorldMapFrame) and true or false
end

local function Plain(t)
	return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- a row label that is the title, or ends with it ("[5] Title", "[2] Title" for party)
local function TitleMatch(f, title)
	local texts = {}
	if f.GetText then
		local ok, t = pcall(f.GetText, f)
		if ok and type(t) == "string" then texts[#texts + 1] = t end
	end
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" then texts[#texts + 1] = r:GetText() end
	end
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
		local ok, n = pcall(function() return w[1]:GetName() end)
		names[#names + 1] = tostring(ok and n or "?") .. (w[2] and "" or " (point only)")
	end
	return #names > 0 and table.concat(names, ", ") or "none"
end

--- The map's quest list (the game's own quest log on this client): scroll it to the quest so
--- its row exists. Only scrolls; nothing in the map is clicked.
local function ScrollMapList(questID)
	local sf = _G.QuestScrollFrame
	local box = sf and sf.ScrollBox
	if not (box and box.ScrollToElementDataByPredicate) then return false end
	local ok = pcall(box.ScrollToElementDataByPredicate, box, function(node)
		local d = type(node) == "table" and (node.GetData and node:GetData() or node)
		if type(d) ~= "table" then return false end
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
	-- a classic-style quest log: select the quest the way clicking it does, and scroll to it
	if idx and Visible(_G.QuestLogFrame) or (idx and _G.QuestLog_SetSelection and not Visible(_G.QuestMapFrame)) then
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
		local ok, n = pcall(function() return hit.window:GetName() end)
		ns:Trace("quests: found the row in " .. tostring(ok and n or "?") .. (hit.click and ", clicking it" or ", pointing only"))
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

ns:RegisterProvider("quests", {
	label = "Quest Log",
	color = "ffffd200",
	aliases = { "questlog", "log", "quest", "quests", "q" },
	events = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" },
	guard = 1,
	refreshOnOpen = true,
	collect = function()
		local out = {}
		local zone
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info then
				if info.isHeader then
					zone = info.title
				elseif info.questID and not info.isHidden then
					local parts = { zone or "" }
					local ok, desc, obj = pcall(GetQuestLogQuestText, i)
					if ok then
						parts[#parts + 1] = desc or ""
						parts[#parts + 1] = obj or ""
					end
					for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
						parts[#parts + 1] = o.text or ""
					end
					out[#out + 1] = {
						key = info.questID,
						name = info.title,
						icon = "Interface\\GossipFrame\\AvailableQuestIcon",
						detail = ((info.level and info.level > 0) and ("[" .. info.level .. "] ") or "") .. (zone or ""),
						text = table.concat(parts, " "),
						questID = info.questID,
						link = GetQuestLink and GetQuestLink(info.questID) or nil,
						activate = ShowQuest,
						secure = QUEST_SECURE,
						isOpen = IsOpen,
						after = ShowQuestAfter,
						-- Shift+Enter: super-track the quest (waypoint arrow)
						secondary = TrackQuest,
					}
				end
			end
		end
		return out
	end,
})

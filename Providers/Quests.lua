local ns = select(2, ...)
local H = ns.Highlight

-- Quests are searched by title AND by their description, objectives and zone,
-- so "kill 10 boars" or a snippet of flavour text finds the quest.
--
-- Opening one: the quest log is opened the way your own quest log key opens it (see
-- Secure.lua), then the quest is selected by clicking its row and highlighted. Terminal
-- never calls the map's own "open quest details" function: on Forever that runs through
-- the protected world map and ends in "Interface action failed because of an AddOn".

-- quest windows, first visible wins; any other visible "...Quest..." window is tried after
local LOGS = { "ForeverClassicUIQuestLog", "QuestLogFrame", "QuestLogDetailFrame" }
-- the map's quest list: protected surroundings, so only point at it, never click in it
local MAP_LOGS = { "QuestMapFrame" }

local function Visible(f)
	return f and not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible()
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

local function IsOpen()
	return #QuestWindows() > 0
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
local function ShowQuestAfter(e)
	if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, e.questID) end
	H:When(function()
		for _, w in ipairs(QuestWindows()) do
			local row = ns.FindFrame(w[1], function(f) return f.Click and TitleMatch(f, e.name) end, 14)
			if row then return { row = row, click = w[2] } end
		end
	end, function(hit)
		if hit.click then pcall(hit.row.Click, hit.row) end -- selects it in that log
		H:Show(hit.row, 6)
	end, 30)
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

ns:RegisterProvider("quests", {
	label = "Quest",
	color = "ffffd200",
	aliases = { "quest", "q", "questlog" },
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
						secure = { binding = "TOGGLEQUESTLOG", buttons = { "QuestLogMicroButton" } },
						isOpen = IsOpen,
						after = ShowQuestAfter,
						-- Shift+Enter: super-track the quest (waypoint arrow)
						secondary = function(e)
							C_SuperTrack.SetSuperTrackedQuestID(e.questID)
							ns:Print("Tracking: " .. e.name)
						end,
					}
				end
			end
		end
		return out
	end,
})

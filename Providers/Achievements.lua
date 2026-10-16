local ns = select(2, ...)
local L = ns.L

-- Enter: a /run line on the secure button opens the window on it (OpenAchievementFrameToAchievement, what an
-- achievement link runs). A /run line runs tainted too: it's kept because no clean route exists (no C call, binding or
-- named button turns the window to an achievement) and nothing protected sits behind it (tests/smoke/macros.lua ALLOW).
local function AchievementMacro(e)
	if type(e.key) ~= "number" then return nil end
	return ("/run if OpenAchievementFrameToAchievement then OpenAchievementFrameToAchievement(%d) else ToggleAchievementFrame() end"):format(e.key)
end
local ACH_SECURE = { macro = AchievementMacro, binding = "TOGGLEACHIEVEMENT", opensWindow = true }
local function OpenAchievement(e) -- (no press possible: say so, nothing opened from here)
	ns:Print(L["Couldn't open %s from here: the Achievements key opens the window."]:format(tostring(e.name)))
end
local function AchievementLink(e) return GetAchievementLink and GetAchievementLink(e.key) or nil end

-- Shift+Enter: link it in chat
local function LinkAchievement(e)
	if not ns.LinkInChat(AchievementLink(e)) then ns:Print(L["Couldn't link %s in chat."]:format(tostring(e.name))) end
end

----------------------------------------------------------------------
-- Achievements (heavy: indexed once, only when you actually search)
--
-- Every achievement is indexed, earned or not, into one list of compact rows: what @achievement (and Simple
-- mode's Collections) searches. A plain search reads only its earned rows (the list's `plain` view, made
-- once per list): thousands of unearned ones would flood every plain search. Unearned rows are greyed,
-- with their progress ("3/10") in the detail, worked out only when a row is read (shown, or judged by a
-- filter). (Until 0.44.15 the earned rows were a second list of their own.)
----------------------------------------------------------------------

local ACH_COLOR = "ffff6fae" -- (rose: the oranges are Camp's and its neighbours')
local NOT_EARNED = "|cff8a8a8a"
local achMeta -- shared fields of every achievement row (made once the list is registered)
local progCache = {} -- achievement id -> its progress text (false: none), emptied when criteria move
local earned, earnedOf -- the earned rows (plain searches' view), and the list they were picked from

--- "3/10": the completed criteria of an unearned achievement, or a lone criterion's quantity
--- (kill 50 of them: "12/50"). Nil when earned or without criteria. Cached per achievement until progress moves (in a
--- table of its own: written onto the rows, it took them past the compact rows' eight fields; review, 0.48.6).
local function Progress(t)
	if rawget(t, "completed") then return nil end
	local id, prog = rawget(t, "key"), nil
	local kept = progCache[id]
	if kept ~= nil then return kept or nil end
	local n = ns.Num(ns.Safe(GetAchievementNumCriteria, id)) or 0
	if n == 1 then
		local _, _, _, q, req = ns.Safe(GetAchievementCriteriaInfo, id, 1)
		q, req = ns.Num(q), ns.Num(req)
		if q and req and req > 1 then prog = math.min(q, req) .. "/" .. req end
	end
	if not prog and n > 0 then
		local done = 0
		for i = 1, n do
			local _, _, ok = ns.Safe(GetAchievementCriteriaInfo, id, i)
			if ok == true then done = done + 1 end
		end
		prog = done .. "/" .. n
	end
	progCache[id] = prog or false
	return prog
end

--- What the row shows besides its name, read from the game when a row is drawn (icon, points, description): kept on
--- the rows they made them 9-12 fields (16 slots each) where 6 do.
local function Info(t, n) return (select(n, ns.Safe(GetAchievementInfo, rawget(t, "key")))) end
local function AchIcon(t) return Info(t, 10) end
local function AchPoints(t) return ns.Num(Info(t, 3)) end
local function AchTip(t) return ns.Str(Info(t, 8)) end
local function AchColor(t) return not rawget(t, "completed") and NOT_EARNED or nil end

local function AchDetail(t)
	local pts = AchPoints(t)
	pts = pts and pts > 0 and L["%s pts"]:format(pts) or ""
	if rawget(t, "completed") then return ns.Detail(L["Done"], pts) end
	return ns.Detail(Progress(t), pts)
end

-- criteria move all the time (every kill): only a number is bumped here
local critWatch = CreateFrame("Frame")
pcall(critWatch.RegisterEvent, critWatch, "CRITERIA_UPDATE")
critWatch:SetScript("OnEvent", function() if next(progCache) then progCache = {} end end)

local function CollectAchievements()
	local out = {}
	if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return out end
	for _, cat in ipairs(ns.Safe(GetCategoryList) or {}) do
		local num = ns.Safe(GetCategoryNumAchievements, cat, true) or 0
		for i = 1, num do
			local id, name, _, completed, _, _, _, description = ns.Safe(GetAchievementInfo, cat, i)
			if id and ns.Str(name) then
				-- (six fields once GetEntries has made _lname and _ltext from name and text; icon, points, the description
				-- shown and the colour are lazy)
				out[#out + 1] = setmetatable({
					_compact = true,
					key = id,
					name = name,
					text = ns.Str(description),
					completed = completed and true or false,
				}, achMeta)
			end
		end
	end
	return out
end

--- Plain searches' view: the earned rows of the list, picked out once per list (a rebuilt list, a new pick).
local function Earned(_, list)
	if earnedOf ~= list then
		earned, earnedOf = {}, list
		for _, e in ipairs(list) do
			if rawget(e, "completed") then earned[#earned + 1] = e end
		end
	end
	return earned
end

ns:RegisterProvider("achievements", {
	label = L["Achievement"],
	color = ACH_COLOR,
	aliases = { "achievement", "achievements", "ach", "achieve" },
	plain = Earned, -- (plain searches: the earned ones only)
	lazy = true,
	events = { "ACHIEVEMENT_EARNED" }, -- earned this session: listed without a /reload
	-- (no idleDrop: every plain search reads its earned rows, and a list freed was read again inside a keystroke's frame,
	-- the prewarm leaving freed lists alone; review, 0.48.6)
	collect = CollectAchievements,
})

achMeta = ns:CompactMeta(ns.providers.achievements, {
	getLink = AchievementLink, -- (made when selected, not per achievement up front)
	secure = ACH_SECURE, isOpen = ns.Never, -- (always pressed: it turns the open window to this one)
	activate = OpenAchievement,
	secondary = LinkAchievement, -- Shift+Enter: link it in chat (the game opens the box; combat: Terminal's own)
	secondarySecure = ns.ChatBoxSpec(AchievementLink), secondaryIsOpen = ns.ChatBoxNeverOpen,
	-- (its detail is progress and points, never a place: in: doesn't work it out per row, a GetAchievementInfo and
	-- the criteria each; review, 0.53.6)
	noPlace = true,
}, { detail = AchDetail, progress = Progress, icon = AchIcon, points = AchPoints, tip = AchTip, color = AchColor })

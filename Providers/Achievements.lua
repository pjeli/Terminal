local ns = select(2, ...)

-- Enter: the game opens the window on it (a /run line on the secure button, what an achievement link runs:
-- OpenAchievementFrameToAchievement), never Terminal's code (the window's Lua would run tainted)
local function AchievementMacro(e)
	if type(e.key) ~= "number" then return nil end
	return ("/run if OpenAchievementFrameToAchievement then OpenAchievementFrameToAchievement(%d) else ToggleAchievementFrame() end"):format(e.key)
end
local ACH_SECURE = { macro = AchievementMacro, binding = "TOGGLEACHIEVEMENT", opensWindow = true }
local function OpenAchievement(e) -- (no press possible: say so, nothing opened from here)
	ns:Print("Couldn't open " .. tostring(e.name) .. " from here: the Achievements key opens the window.")
end
local function AchievementLink(e) return GetAchievementLink and GetAchievementLink(e.key) or nil end

-- Shift+Enter: link it in chat
local function LinkAchievement(e)
	if not ns.LinkInChat(AchievementLink(e)) then ns:Print("Couldn't link " .. tostring(e.name) .. " in chat.") end
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
local critGen = 0 -- bumped when criteria progress: a row's cached progress is read again then
local earned, earnedOf -- the earned rows (plain searches' view), and the list they were picked from

--- "3/10": the completed criteria of an unearned achievement, or a lone criterion's quantity
--- (kill 50 of them: "12/50"). Nil when earned or without criteria. Cached per row until progress moves.
local function Progress(t)
	if rawget(t, "completed") then return nil end
	if rawget(t, "_progGen") == critGen then return rawget(t, "_prog") or nil end
	local id, prog = rawget(t, "key"), nil
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
	rawset(t, "_prog", prog or false)
	rawset(t, "_progGen", critGen)
	return prog
end

local function AchDetail(t)
	local pts = rawget(t, "points")
	pts = pts and pts > 0 and (pts .. " pts") or ""
	if rawget(t, "completed") then return "Done  " .. pts end
	local prog = Progress(t)
	return prog and (prog .. "  " .. pts) or pts
end

-- criteria move all the time (every kill): only a number is bumped here
local critWatch = CreateFrame("Frame")
pcall(critWatch.RegisterEvent, critWatch, "CRITERIA_UPDATE")
critWatch:SetScript("OnEvent", function() critGen = critGen + 1 end)

local function CollectAchievements()
	local out = {}
	if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return out end
	for _, cat in ipairs(ns.Safe(GetCategoryList) or {}) do
		local num = ns.Safe(GetCategoryNumAchievements, cat, true) or 0
		for i = 1, num do
			local id, name, points, completed, _, _, _, description, _, icon = ns.Safe(GetAchievementInfo, cat, i)
			if id and ns.Str(name) then
				description = ns.Str(description)
				out[#out + 1] = setmetatable({
					_compact = true,
					key = id,
					name = name,
					icon = icon,
					text = description,
					tip = description,
					points = ns.Num(points),
					completed = completed and true or false,
					color = not completed and NOT_EARNED or nil,
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
	label = "Achievement",
	color = ACH_COLOR,
	aliases = { "achievement", "achievements", "ach", "achieve" },
	plain = Earned, -- (plain searches: the earned ones only)
	lazy = true,
	events = { "ACHIEVEMENT_EARNED" }, -- earned this session: listed without a /reload
	idleDrop = 600,
	onDrop = function() earned, earnedOf = nil, nil end, -- (its rows go with the list)
	collect = CollectAchievements,
})

achMeta = ns:CompactMeta(ns.providers.achievements, {
	getLink = AchievementLink, -- (made when selected, not per achievement up front)
	secure = ACH_SECURE, isOpen = ns.Never, -- (always pressed: it turns the open window to this one)
	activate = OpenAchievement,
	secondary = LinkAchievement, -- Shift+Enter: link it in chat (the game opens the box; combat: Terminal's own)
	secondarySecure = ns.ChatBoxSpec(AchievementLink), secondaryIsOpen = ns.ChatBoxNeverOpen,
}, { detail = AchDetail, progress = Progress })

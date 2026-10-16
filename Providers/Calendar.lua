local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight

-- Calendar (@calendar, @event, @holiday; Simple mode: "holidays", "what's on this week", "next darkmoon faire", "my
-- invites", "guild events", "today", in its own Calendar category): what's on the game's calendar from today to the end
-- of next month: holidays (the Darkmoon Faire, ...), your, your guild's and your communities' events with how you
-- answered, invitations you haven't answered yet, raid resets. Read from the game (C_Calendar, as the calendar window
-- reads it) and never written: Terminal never turns the calendar's month itself (C_Calendar.SetMonth), so the window
-- stays as you left it. Asked from the server at login and at most every CA.ASK_AGAIN s after (C_Calendar.OpenCalendar).
--
--   Enter        the calendar, opened by the game (the minimap's calendar button, as the Calendar window row does),
--                turned to the event's month by its own next-month button and the event clicked open: every step a
--                /click the game runs (nothing in the window runs tainted); then the event is pointed at. An event the
--                calendar shows on no day (a holiday's middle days) has its day pointed at.
--   Shift+Enter  into the chat box: the game's link to the event where it gives one, else in words

local CA = {}
ns.Calendar = CA

local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower

CA.ASK_AGAIN = 300 -- (s: the server is asked for the calendar again at most this often)
CA.MONTHS = 2 -- (this month and the next are read)
CA.GRACE = 120 -- (min: an event that started this long ago still shows, a raid under way say)
CA.MAX_PER_DAY = 40
CA.MAX_TURNS = 6 -- (the calendar's next/previous month clicks one press makes at most)

local function Api()
	local C = _G.C_Calendar
	return type(C) == "table" and C or nil
end

--- The server has the calendar switched off (a game rule; the minimap's button is disabled then).
function CA.Disabled()
	local R, E = _G.C_GameRules, _G.Enum
	local rule = E and E.GameRule and E.GameRule.IngameCalendarDisabled
	if type(R) ~= "table" or rule == nil then return false end
	return Safe(R.IsGameRuleActive, rule) == true
end

----------------------------------------------------------------------
-- Dates
----------------------------------------------------------------------

--- Days since 1 January 1970 for a date (any year, month and day), to compare and count days.
local function DayNum(y, m, d)
	if m <= 2 then y, m = y - 1, m + 12 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m - 3) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
CA.DayNum = DayNum

--- 1 = Sunday ... 7 = Saturday, as the game counts weekdays.
local function Weekday(dn) return (dn + 4) % 7 + 1 end
CA.Weekday = Weekday

--- Days in a month.
local function MonthDays(y, m)
	local ny, nm = y, m + 1
	if nm > 12 then ny, nm = y + 1, 1 end
	return DayNum(ny, nm, 1) - DayNum(y, m, 1)
end

--- The game's time now (the realm's, as the calendar shows it): { year, month, monthDay, weekday, hour, minute }.
local function NowTime()
	local D = _G.C_DateAndTime
	local t = type(D) == "table" and Safe(D.GetCurrentCalendarTime)
	if type(t) == "table" and Num(t.year) and Num(t.month) and Num(t.monthDay) then
		return { year = t.year, month = t.month, monthDay = t.monthDay, weekday = Num(t.weekday),
			hour = Num(t.hour) or 0, minute = Num(t.minute) or 0 }
	end
end
CA.NowTime = NowTime

--- Today as a day number, and now in minutes (day * 1440 + minutes), or nil when the game doesn't say.
local function Today()
	local t = NowTime()
	if not t then return nil end
	local dn = DayNum(t.year, t.month, t.monthDay)
	return dn, dn * 1440 + t.hour * 60 + t.minute, t
end
CA.Today = Today

-- a calendar time as plain numbers ({ year, month, monthDay, weekday, hour, minute }), or nil
local function TimeOf(t)
	if type(t) ~= "table" then return nil end
	local y, m, d = Num(t.year), Num(t.month), Num(t.monthDay)
	if not (y and m and d) or m < 1 or m > 12 or d < 1 then return nil end
	return { year = y, month = m, monthDay = d, weekday = Num(t.weekday), hour = Num(t.hour) or 0, minute = Num(t.minute) or 0 }
end
local function Mins(t) return DayNum(t.year, t.month, t.monthDay) * 1440 + t.hour * 60 + t.minute end

local EN_WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local EN_MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
	"November", "December" }

-- the game's own names (the client's language), else English
local function WeekdayName(w)
	local t = _G.CALENDAR_WEEKDAY_NAMES
	return (type(t) == "table" and Str(t[w])) or EN_WEEKDAYS[w] or "?"
end
local function MonthName(m)
	local t = _G.CALENDAR_FULLDATE_MONTH_NAMES
	return (type(t) == "table" and Str(t[m])) or EN_MONTHS[m] or tostring(m)
end

--- "Friday, October 31", as the game writes a date without its year (FULLDATE_NO_YEAR), else in English.
local function DateText(t)
	local w = WeekdayName(t.weekday or Weekday(DayNum(t.year, t.month, t.monthDay)))
	local fmt = _G.FULLDATE_NO_YEAR
	if type(fmt) == "string" then
		local ok, s = pcall(string.format, fmt, w, MonthName(t.month), t.monthDay)
		if ok and Str(s) then return s end
	end
	return w .. ", " .. MonthName(t.month) .. " " .. t.monthDay
end
CA.DateText = DateText

--- "20:00" / "8:00 PM", as the game's clock is set to show it.
local function Clock(t)
	local s = Str(Safe(_G.GameTime_GetFormattedTime, t.hour or 0, t.minute or 0, true))
	return s or ("%d:%02d"):format(t.hour or 0, t.minute or 0)
end

-- "today", "tomorrow", "Friday" (within the week), else "Friday, October 31"
local function DayWord(t, today)
	local dn = DayNum(t.year, t.month, t.monthDay)
	if dn == today then return L["today"] end
	if dn == today + 1 then return L["tomorrow"] end
	if dn > today and dn - today < 7 then return WeekdayName(t.weekday or Weekday(dn)) end
	return DateText(t)
end

--- Does it end later than it starts (a holiday's hours, the fishing tournament's 2 to 4 PM), not just start?
local function Lasts(e) return e.finish ~= nil and Mins(e.finish) > Mins(e.start) end
CA.Lasts = Lasts

--- When it is, in a few words, with the times the calendar's own tooltip gives (0.49.14, the player's ask: a holiday
--- said only its day, the Stranglethorn fishing tournament not its hours): "today 20:00", "Sunday 14:00 - 16:00",
--- "until Sunday 23:59", "Sunday 10:00 - Sunday, November 1".
function CA.When(e, today)
	local td, nowMin = Today()
	today = today or td or 0
	if e.multi then
		-- (under way: started by now, not just today; review, 0.49.17: one starting tonight said "until" all day)
		if Mins(e.start) <= (nowMin or today * 1440) then return L["until %s"]:format(DayWord(e.finish, today) .. " " .. Clock(e.finish)) end
		return DayWord(e.start, today) .. " " .. Clock(e.start) .. " - " .. DayWord(e.finish, today)
	end
	if Lasts(e) then return DayWord(e.start, today) .. " " .. Clock(e.start) .. " - " .. Clock(e.finish) end
	return DayWord(e.start, today) .. " " .. Clock(e.start)
end

----------------------------------------------------------------------
-- Reading the calendar
----------------------------------------------------------------------

-- what each kind of entry is called
local TYPES = {
	HOLIDAY = L["Holiday"], PLAYER = L["Event"], GUILD_EVENT = L["Guild event"], GUILD_ANNOUNCEMENT = L["Guild announcement"],
	COMMUNITY_EVENT = L["Community event"], SYSTEM = L["Game event"], RAID_LOCKOUT = L["Lockout ends"],
	RAID_RESET = L["Raid reset"],
}
-- and the English words that find them (Simple mode understands English in every language)
local TYPE_WORDS = {
	HOLIDAY = "holiday holidays festival", PLAYER = "event", GUILD_EVENT = "guild event", GUILD_ANNOUNCEMENT = "guild announcement",
	COMMUNITY_EVENT = "community event", SYSTEM = "event", RAID_LOCKOUT = "raid lockout unlocks", RAID_RESET = "raid reset resets",
}
-- the kinds you're invited to, with an answer
local RSVP = { PLAYER = true, GUILD_EVENT = true, COMMUNITY_EVENT = true }
local GUILD = { GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true }

local ICONS = {
	HOLIDAY = "Interface\\Icons\\INV_Misc_Note_06", RAID_LOCKOUT = "Interface\\Icons\\INV_Misc_Key_14",
	RAID_RESET = "Interface\\Icons\\INV_Misc_Key_14", GUILD_EVENT = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
	GUILD_ANNOUNCEMENT = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
}
local ICON = "Interface\\Icons\\INV_Letter_15"
CA.ICON = "Interface\\Icons\\INV_Misc_Note_06"
-- a holiday's own picture fills only the top left of its texture (the calendar window's own crop)
local HOLIDAY_COORDS = { 0, 0.7109375, 0, 0.7109375 }

local function StatusEnum(name, fallback)
	local E = _G.Enum
	return (E and E.CalendarStatus and Num(E.CalendarStatus[name])) or fallback
end
local INVITED = StatusEnum("Invited", 0)
local DECLINED, OUT = StatusEnum("Declined", 2), StatusEnum("Out", 4)
-- the answers as the game says them (CALENDAR_INVITESTATUS_INFO: the client's language and colour), else English
local STATUS_EN = { [0] = "Invited", [1] = "Accepted", [2] = "Declined", [3] = "Confirmed", [4] = "Out", [5] = "Standby",
	[6] = "Signed up", [7] = "Not signed up", [8] = "Tentative" }
local function StatusText(s)
	local info = _G.CALENDAR_INVITESTATUS_INFO
	local i = type(info) == "table" and info[s]
	local name = type(i) == "table" and Str(i.name) or STATUS_EN[s]
	if not name then return nil end
	local c = type(i) == "table" and i.color
	local hex = type(c) == "table" and c.GenerateHexColor and Safe(c.GenerateHexColor, c)
	return name, Str(hex) and ("|c" .. hex) or nil
end

local function Bool(v) return not ns.Secret(v) and v == true end

-- the calendar shows the event on this day (not a holiday's middle days, nor an end it hides)
local function Displayed(ev)
	local seq = Str(ev.sequenceType)
	if seq == "ONGOING" then return false end
	if seq == "END" and Bool(ev.dontDisplayEnd) then return false end
	return true
end

-- its name as the calendar shows it: a few events give a string key; lockouts and resets with their difficulty
local function Title(ev, ctype)
	local t = Str(ev.title)
	if not t then return nil end
	if not Bool(ev.isCustomTitle) then
		local g = rawget(_G, t)
		if type(g) == "string" and g ~= "" then t = g end
	end
	if ctype == "RAID_LOCKOUT" or ctype == "RAID_RESET" then
		local d = Str(ev.difficultyName)
		if d then t = Str(Safe(_G.GetDungeonNameWithDifficulty, t, d)) or (t .. " (" .. d .. ")") end
	end
	return t
end

-- one event across the days it spans: its type, id, name and start
local function KeyOf(ev)
	local ctype = Str(ev.calendarType)
	local title = ctype and Title(ev, ctype)
	local st = TimeOf(ev.startTime)
	if not (title and st) then return nil end
	return ctype .. ":" .. tostring(Num(ev.eventID) or "") .. ":" .. title .. ":" .. Mins(st), ctype, title, st
end

--- The month offset the game counts from (the month the calendar is turned to) of a year and month.
local function OffsetOf(C, year, month)
	local base = Safe(C.GetMonthInfo, 0)
	local by, bm = type(base) == "table" and Num(base.year), type(base) == "table" and Num(base.month)
	if not (by and bm) then return nil end
	return (year - by) * 12 + (month - bm)
end

--- Asks the server for the calendar (it answers with CALENDAR_UPDATE_EVENT_LIST); at most every `again` s when given.
function CA.Ask(again)
	local C = Api()
	if not (C and C.OpenCalendar) or CA.Disabled() then return false end
	local t = GetTime and GetTime() or 0
	if again and CA.askedAt and t - CA.askedAt < again then return false end
	CA.askedAt = t
	pcall(C.OpenCalendar)
	return true
end

--- What's on from today to the end of next month: { event }, sorted by when it starts (what's under way first).
function CA.Read()
	local C = Api()
	local today, nowMin, now = Today()
	if not (C and today) or CA.Disabled() then return {} end
	local first = OffsetOf(C, now.year, now.month)
	if not first then return {} end
	local groups, list = {}, {}
	for off = first, first + CA.MONTHS - 1 do
		local mi = Safe(C.GetMonthInfo, off)
		local y, m, nd = type(mi) == "table" and Num(mi.year), type(mi) == "table" and Num(mi.month), type(mi) == "table" and Num(mi.numDays)
		if y and m and nd then
			for day = 1, math.min(nd, 31) do
				if DayNum(y, m, day) >= today then
					local n = Num(Safe(C.GetNumDayEvents, off, day)) or 0
					for i = 1, math.min(n, CA.MAX_PER_DAY) do
						local ev = Safe(C.GetDayEvent, off, day, i)
						local key, ctype, title, st
						if type(ev) == "table" then key, ctype, title, st = KeyOf(ev) end
						if key then
							local g = groups[key]
							if not g then
								local fin = TimeOf(ev.endTime)
								g = { groupKey = key, type = ctype, name = title, start = st, finish = fin,
									eventID = Num(ev.eventID), status = Num(ev.inviteStatus), invitedBy = Str(ev.invitedBy),
									iconTexture = Num(ev.iconTexture) or Str(ev.iconTexture),
									seen = { year = y, month = m, day = day } }
								if ctype == "HOLIDAY" then
									local info = Safe(C.GetHolidayInfo, off, day, i)
									g.desc = type(info) == "table" and Str(info.description) or nil
								end
								groups[key] = g
								list[#list + 1] = g
							end
							-- where it's clicked open: the first day the calendar shows it (its start, or its end)
							if not g.at and Displayed(ev) then g.at = { year = y, month = m, day = day } end
						end
					end
				end
			end
		end
	end
	local out = {}
	for _, g in ipairs(list) do
		g.startDN = DayNum(g.start.year, g.start.month, g.start.monthDay)
		local fin = g.finish
		g.multi = fin and DayNum(fin.year, fin.month, fin.monthDay) > g.startDN or nil
		g.endDN = g.multi and DayNum(fin.year, fin.month, fin.monthDay) or g.startDN
		local startMin = Mins(g.start)
		local over
		if g.multi or g.type == "HOLIDAY" then
			over = fin and Mins(fin) < nowMin
		else
			over = startMin < nowMin - (RSVP[g.type] and CA.GRACE or 0)
		end
		if not over then
			g.startMin = startMin
			out[#out + 1] = g
		end
	end
	table.sort(out, function(a, b)
		if a.startMin ~= b.startMin then return a.startMin < b.startMin end
		return a.name < b.name
	end)
	return out
end

--- Where the event is now in the game's calendar: its month offset, day and index in that day, and which of the day's
--- event buttons shows it (1-4; nil when it shows on no button there). Nil when it's gone.
function CA.Locate(e)
	local C, at = Api(), e and (e.at or e.seen)
	if not (C and at) then return nil end
	local off = OffsetOf(C, at.year, at.month)
	if not off then return nil end
	local n = Num(Safe(C.GetNumDayEvents, off, at.day)) or 0
	local shown = 0
	for i = 1, math.min(n, CA.MAX_PER_DAY) do
		local ev = Safe(C.GetDayEvent, off, at.day, i)
		if type(ev) == "table" then
			local disp = Displayed(ev)
			if disp then shown = shown + 1 end
			if KeyOf(ev) == e.groupKey then return off, at.day, i, (disp and e.at and shown <= 4) and shown or nil end
		end
	end
end

----------------------------------------------------------------------
-- Opening it in the calendar (the game's own clicks)
----------------------------------------------------------------------

-- the languages whose calendar starts its weeks on Monday (Blizzard_Calendar's Localization.lua)
local MONDAY_FIRST = { deDE = true, enGB = true, esES = true, frFR = true, itIT = true, ruRU = true }

--- The calendar's first column: CALENDAR_FIRST_WEEKDAY once the calendar has loaded (it sets it for the client's
--- language), else what it will set it to.
function CA.FirstWeekday()
	local fw = Num(rawget(_G, "CALENDAR_FIRST_WEEKDAY"))
	if rawget(_G, "CalendarFrame") then return fw or 1 end
	local loc = Str(Safe(_G.GetLocale))
	if loc == "esMX" then return 1 end
	if loc and MONDAY_FIRST[loc] then return 2 end
	return fw or 1
end

--- The calendar's day button (CalendarDayButton<n>) of a day, with the month turned to it.
function CA.DayButtonIndex(y, m, d)
	local first = Weekday(DayNum(y, m, 1))
	return d + (first - CA.FirstWeekday()) % 7
end

local function CalendarShown()
	local f = rawget(_G, "CalendarFrame")
	return type(f) == "table" and f.IsShown and f:IsShown() and true or false
end

--- The /click lines the game runs: the minimap's calendar button (when the calendar isn't open), its next/previous
--- month button to the event's month, then the event's button. Nil when there's nothing to press.
function CA.OpenMacro(e)
	local at = e and (e.at or e.seen)
	if not at then return nil end
	local open = CalendarShown()
	local lines = {}
	if not open then
		if not rawget(_G, "GameTimeFrame") then return nil end
		lines[1] = "/click GameTimeFrame"
	end
	-- the month showing once it's open: the one it's turned to, else this one (it opens on this month)
	local vm, vy
	if open then
		local f = _G.CalendarFrame
		vm, vy = Num(rawget(f, "viewedMonth")), Num(rawget(f, "viewedYear"))
	end
	if not (vm and vy) then
		local now = NowTime()
		if now then vm, vy = now.month, now.year end
	end
	-- (turned months away by hand: up to CA.MAX_TURNS clicks back, the macro's 255 characters allowing)
	local delta = (vm and vy) and ((at.year * 12 + at.month) - (vy * 12 + vm)) or nil
	if delta and math.abs(delta) <= CA.MAX_TURNS then
		local b = delta > 0 and "/click CalendarNextMonthButton" or "/click CalendarPrevMonthButton"
		for _ = 1, math.abs(delta) do lines[#lines + 1] = b end
		local _, _, _, button = CA.Locate(e)
		if button then
			lines[#lines + 1] = ("/click CalendarDayButton%dEventButton%d"):format(CA.DayButtonIndex(at.year, at.month, at.day), button)
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or nil
end

local OPEN_SPEC = { macro = function(e) return CA.OpenMacro(e) end, opensWindow = true }
-- open with nothing to press (turned to its month already, the event on no button): only pointed at
local function OpenAlready(e) return CalendarShown() and CA.OpenMacro(e) == nil end

-- afterwards: point at the event's button, else its day
local function PointAt(e)
	local at = e.at or e.seen
	if not (at and H) then return end
	H:Find(function()
		local f = rawget(_G, "CalendarFrame")
		if not (type(f) == "table" and f:IsVisible()) then return nil end
		if Num(rawget(f, "viewedMonth")) ~= at.month or Num(rawget(f, "viewedYear")) ~= at.year then return nil end
		local idx = CA.DayButtonIndex(at.year, at.month, at.day)
		local b = _G["CalendarDayButton" .. idx]
		if type(b) ~= "table" then return nil end
		local _, _, _, button = CA.Locate(e)
		local ev = button and _G["CalendarDayButton" .. idx .. "EventButton" .. button]
		if type(ev) == "table" and ev:IsVisible() then return ev end
		return b
	end)
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function Line(e)
	return "  " .. e.name .. "  " .. ns.Detail(CA.When(e), e.typeLabel, e.statusText)
end

-- (Enter with no press set up: no calendar button, the press not armed; in combat Enter stops before this) the event in chat
local function Show(e)
	local lines = { Line(e) }
	if e.desc then lines[#lines + 1] = "    " .. e.desc end
	ns:Output(lines)
end

--- What's sent: the game's link to the event where it gives one (your and your guild's events), else in words.
local function ShareText(e)
	if e.type ~= "HOLIDAY" and _G.GetCalendarEventLink then
		local off, day, i = CA.Locate(e)
		local link = off and Str(Safe(_G.GetCalendarEventLink, off, day, i))
		if link then return link .. " " .. CA.When(e) end
	end
	return e.name .. ": " .. CA.When(e)
end
CA.ShareText = ShareText
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end
local CHATBOX = ns.ChatBoxSpec(ShareText)

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(e.typeLabel, 1, 1, 1)
	-- when it starts and ends, to the minute, as the calendar's own tooltip says (an ending the same day: its time)
	if CA.Lasts(e) then
		t:AddDoubleLine(L["Starts"], DateText(e.start) .. " " .. Clock(e.start), 1, 1, 1, 1, 1, 1)
		t:AddDoubleLine(L["Ends"], (e.multi and (DateText(e.finish) .. " ") or "") .. Clock(e.finish), 1, 1, 1, 1, 1, 1)
	else
		t:AddDoubleLine(L["When"], DateText(e.start) .. " " .. Clock(e.start), 1, 1, 1, 1, 1, 1)
	end
	if e.statusText then t:AddLine((e.statusColor or "") .. e.statusText .. (e.statusColor and "|r" or ""), 1, 1, 1) end
	if e.invitedBy then t:AddLine(L["Invited by %s"]:format(e.invitedBy), 0.8, 0.8, 0.8) end
	if e.desc then t:AddLine(e.desc, 0.8, 0.8, 0.8, true) end
	ns.KeyHints(t, L["Enter: open it in the calendar    Shift+Enter: put it in the chat box"], 0.6, 0.6, 0.6, true)
end

local GOLD, GREY = "|cffffd200", "|cff9d9d9d"

local function Row(g, today)
	local e = g
	e.key = g.groupKey
	e.typeLabel = TYPES[g.type] or L["Event"]
	e.pending = RSVP[g.type] and g.status == INVITED or nil
	if RSVP[g.type] and g.status then e.statusText, e.statusColor = StatusText(g.status) end
	e.icon = g.iconTexture or ICONS[g.type] or ICON
	if g.iconTexture and g.type == "HOLIDAY" then e.iconCoords = HOLIDAY_COORDS end
	e.color = (e.pending and GOLD) or ((g.status == DECLINED or g.status == OUT) and RSVP[g.type] and GREY) or nil
	e.detail = ns.Detail(CA.When(e, today), e.typeLabel, e.statusText)
	e.tooltip, e.activate = Tooltip, Show
	e.secure, e.isOpen, e.after = OPEN_SPEC, OpenAlready, PointAt
	e.secondary, e.secondarySecure, e.secondaryIsOpen, e.shareLink = ToChatBox, CHATBOX, ns.ChatBoxNeverOpen, ShareText
	local s, f = g.start, g.finish or g.start
	local words = { Lower(g.name), Lower(e.typeLabel), TYPE_WORDS[g.type] or "event", "calendar",
		Lower(WeekdayName(s.weekday or Weekday(g.startDN))), Lower(MonthName(s.month)),
		Lower(EN_WEEKDAYS[s.weekday or Weekday(g.startDN)] or ""), Lower(EN_MONTHS[s.month] or "") }
	if g.multi then words[#words + 1] = Lower(MonthName(f.month)) end
	if e.pending then words[#words + 1] = "invite invites invitation pending" end
	if e.statusText then words[#words + 1] = Lower(e.statusText) end
	if g.invitedBy then words[#words + 1] = Lower(g.invitedBy) end
	e.text = table.concat(words, " ")
	return e
end

local list -- (the last collect's rows)

function CA.Collect()
	local rows = {}
	local today = Today()
	for _, g in ipairs(CA.Read()) do rows[#rows + 1] = Row(g, today) end
	ns.RankInOrder(rows) -- (this order among equal matches)
	list = rows
	CA.Ask(CA.ASK_AGAIN) -- (the answer, CALENDAR_UPDATE_EVENT_LIST, marks the list changed)
	return rows
end

CA.NONE = L["Nothing on the calendar this month or next"]
CA.OFF = L["The calendar is switched off on this server"]

local NoteRow = ns.NoteRow

ns:RegisterProvider("calendar", {
	label = L["Calendar"],
	color = "ffa0c8ff",
	aliases = { "calendar", "event", "events", "holiday", "holidays" },
	refreshOnOpen = 120, -- ("today", "tomorrow" and what's over move on)
	events = { "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_PENDING_INVITES", "CALENDAR_UPDATE_GUILD_EVENTS",
		"CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_EVENT", "CALENDAR_UPDATE_INVITE_LIST" },
	guard = 1,
	-- nothing on: a line saying so (the list asked for by name: @calendar, the Calendar category)
	leadRow = ns.EmptyLead(function() return CA.Disabled() and CA.OFF or CA.NONE end, function() return not (list and #list > 0) end),
	collect = function() return CA.Collect() end,
})

----------------------------------------------------------------------
-- The question: "holidays", "what's on this week", "today", "next darkmoon faire", "my invites", "guild events"
----------------------------------------------------------------------

local FILLER = {}
for w in ([[my me i im the a an of is are do does did have has got any anything whats what which when how show list
	check see all for on in to at from about there theres this it its we our us up coming upcoming soon next will be
	start starts begin begins end ends happening going planned scheduled schedule please]]):gmatch("%a+") do FILLER[w] = true end
local SPAN = { today = "today", tonight = "today", tomorrow = "tomorrow", week = "week", weekend = "weekend",
	month = "month" }
local HOLIDAY = { holiday = true, holidays = true, festival = true, festivals = true }
local INVITES = { invites = true, invitations = true, invitation = true }
local EVENTS = { events = true, event = true }
-- what asks "what's on" by itself: these with nothing else ("what's on", "what's happening", "anything coming up")
local WHATS = { whats = true, what = true, anything = true, any = true }
local ON = { on = true, happening = true, coming = true, upcoming = true, planned = true }
-- what asks about one by name: "when is the darkmoon faire", "next darkmoon faire", "upcoming holidays"
local CUE = { when = true, next = true, upcoming = true }

-- every word is in one row (its name or words): "hallows" finds Hallow's End. (0.49.2, review: the words are in
-- `_ltext` once the list is made, ns:GetEntries moving `text` there; only the names were searched)
local function Has(e, w)
	local hay = rawget(e, "_calHay")
	if not hay then
		hay = (Lower(e.name) .. " " .. (rawget(e, "_ltext") or Lower(e.text or ""))):gsub("'", "")
		e._calHay = hay
	end
	return hay:find(w, 1, true) ~= nil
end
local function AnyHas(rows, words)
	if #words == 0 then return true end
	for _, e in ipairs(rows) do
		local all = true
		for _, w in ipairs(words) do if not Has(e, w) then all = false break end end
		if all then return true end
	end
	return false
end

local function Rows()
	local p = ns.providers.calendar
	return p and ns:GetEntries(p) or {}
end

--- The question: { words = what narrows it (in a row's name or words), span = "today" | "tomorrow" | "week" |
--- "nextweek" | "weekend" | "month" | "nextmonth", holiday, invite, guild }, or nil when the line isn't asking about
--- the calendar. "calendar" alone stays a search (the Calendar window first, then what's on).
function CA.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local q = { words = {} }
	local strong, calendar, cue, whats, on, nextWord, n = false, false, false, false, false, false, 0
	for w in t:gmatch("%S+") do
		n = n + 1
		if SPAN[w] then q.span = SPAN[w]; strong = true
		elseif HOLIDAY[w] then q.holiday = true; strong = true
		elseif INVITES[w] then q.invite = true; strong = true
		elseif EVENTS[w] then strong = true
		elseif w == "calendar" then calendar = true
		elseif w == "guild" then q.guild = true
		else
			if WHATS[w] then whats = true end
			if ON[w] then on = true end
			if CUE[w] then cue = true end
			if w == "next" then nextWord = true end
			if not FILLER[w] then q.words[#q.words + 1] = w end
		end
	end
	if q.span == "week" and nextWord then q.span = "nextweek" end
	if q.span == "month" and nextWord then q.span = "nextmonth" end
	-- "calendar" with anything more ("calendar this week", "guild calendar"); "guild" only with a calendar word
	if calendar and n > 1 then strong = true end
	if q.guild and not (strong or calendar) then return nil end
	if not strong and not (whats and on) and not (cue and #q.words > 0) then return nil end
	-- the other words must name something on the calendar, else it's a search ("holiday cheer", "next quest")
	if #q.words > 0 and not AnyHas(Rows(), q.words) then return nil end
	return q
end

-- the days asked about, from today: first and last (nil: any)
local function SpanDays(span, today, now)
	if span == "today" then return 0, 0 end
	if span == "tomorrow" then return 1, 1 end
	if span == "week" then return 0, 6 end
	if span == "nextweek" then return 7, 13 end
	if span == "weekend" then
		local wd = now.weekday or Weekday(today)
		if wd == 1 then return 0, 0 end -- (Sunday: today)
		local toSat = 7 - wd
		return toSat, toSat + 1
	end
	if span == "month" then return 0, MonthDays(now.year, now.month) - now.monthDay end
	if span == "nextmonth" then
		local left = MonthDays(now.year, now.month) - now.monthDay
		local ny, nm = now.year, now.month + 1
		if nm > 12 then ny, nm = ny + 1, 1 end
		return left + 1, left + MonthDays(ny, nm)
	end
end

--- Whether an event is on during a span ("today", "tomorrow", "week", "weekend", "nextweek", "month", "nextmonth"):
--- the question's span, and when:<span> in Advanced mode (Filters/Others.lua).
CA.SPANS = { "today", "tomorrow", "week", "weekend", "nextweek", "month", "nextmonth" }
CA.SPAN_OK = {}
for _, s in ipairs(CA.SPANS) do CA.SPAN_OK[s] = true end
function CA.InSpan(e, span)
	local today, _, now = Today()
	if not (today and e.startDN) then return false end
	local from, to = SpanDays(span, today, now)
	if not from then return false end
	return (e.endDN or e.startDN) >= today + from and e.startDN <= today + to
end

local SPAN_SAID = { today = L["today"], tomorrow = L["tomorrow"], week = L["this week"], nextweek = L["next week"],
	weekend = L["this weekend"], month = L["this month"], nextmonth = L["next month"] }

function CA.Answer(q)
	q = q or {}
	local all = Rows()
	local rows = {}
	for _, e in ipairs(all) do
		local ok = true
		if q.span and not CA.InSpan(e, q.span) then ok = false end
		if ok and q.holiday and e.type ~= "HOLIDAY" then ok = false end
		if ok and q.invite and not e.pending then ok = false end
		if ok and q.guild and not GUILD[e.type] then ok = false end
		for _, w in ipairs(q.words or {}) do if ok and not Has(e, w) then ok = false end end
		if ok then rows[#rows + 1] = e end
	end
	ns.ScoreInOrder(rows)
	local note = (q.holiday and L["Holidays"]) or (q.invite and L["Your invites"]) or (q.guild and L["Guild events"])
		or L["Calendar"]
	if q.span then note = note .. ns.DETAIL_SEP .. SPAN_SAID[q.span] end
	if #rows == 0 then
		if #all == 0 then return { NoteRow(CA.Disabled() and CA.OFF or CA.NONE) }, note end
		local none = (#(q.words or {}) > 0 and L["Nothing on the calendar has that"])
			or (q.invite and L["No invitations waiting for an answer"]) or L["Nothing on the calendar then"]
		return { NoteRow(none) }, note
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@calendar is:holiday when:week darkmoon". (0.49.2, review: every span is
--- kept, not only today's)
function CA.ToAdvanced(q)
	local parts = { "@calendar" }
	if q.holiday then parts[#parts + 1] = "is:holiday" end
	if q.invite then parts[#parts + 1] = "is:invite" end
	if q.span then parts[#parts + 1] = "when:" .. q.span end
	if q.guild then parts[#parts + 1] = "guild" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

-- asked at login (a moment after: the server's calendar comes with CALENDAR_UPDATE_EVENT_LIST)
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
function CA.OnEvent(event, isLogin, isReload)
	if event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) then
		C_Timer.After(5, function() CA.Ask() end)
	end
end
ev:SetScript("OnEvent", function(_, ...) CA.OnEvent(...) end)
CA.frame = ev -- (tests)

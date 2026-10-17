-- Calendar (Calendar.lua, 0.49.1, the player's ask): @calendar / @event / @holiday: what's on the game's calendar from
-- today to the end of next month; Enter has the game open the calendar, turn to the month and click the event open.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[calendar]\n")
do
	local CA, P, E = ns.Calendar, ns.providers.calendar, ns.Easy
	local save = { cal = _G.C_Calendar, dt = _G.C_DateAndTime, loc = _G.GetLocale, gtf = _G.GameTimeFrame,
		cf = _G.CalendarFrame, fw = _G.CALENDAR_FIRST_WEEKDAY, link = _G.GetCalendarEventLink, rules = _G.C_GameRules,
		easy = ns.db.easyMode, out = ns.Output, show = ns.Highlight.Show }
	check(P and ns:ResolveProvider("calendar") == P and ns:ResolveProvider("holiday") == P and ns:ResolveProvider("events") == P,
		"@calendar, @holiday and @events")
	ns.db.easyMode = false

	-- today: Tuesday 13 October 2026, noon
	_G.C_DateAndTime = { GetCurrentCalendarTime = function()
		return { year = 2026, month = 10, monthDay = 13, weekday = 3, hour = 12, minute = 0 }
	end }
	check(CA.DayNum(1970, 1, 1) == 0 and CA.DayNum(2026, 10, 13) == 20739 and CA.Weekday(20739) == 3
		and CA.Weekday(CA.DayNum(2026, 11, 1)) == 1, "day numbers and weekdays (13 October 2026 is a Tuesday)")

	local function At(y, m, d, wd, h, mi) return { year = y, month = m, monthDay = d, weekday = wd, hour = h or 0, minute = mi or 0 } end
	local DMF = { eventID = 1, title = "Darkmoon Faire", isCustomTitle = true, calendarType = "HOLIDAY",
		startTime = At(2026, 10, 12, 2, 0, 1), endTime = At(2026, 10, 18, 1, 23, 59), iconTexture = 235448 }
	local HE = { eventID = 2, title = "Hallow's End", isCustomTitle = true, calendarType = "HOLIDAY",
		startTime = At(2026, 10, 18, 1, 10, 0), endTime = At(2026, 11, 1, 1, 10, 0), iconTexture = 235450 }
	local FISH = { eventID = 3, title = "Stranglethorn Fishing Extravaganza", isCustomTitle = true, calendarType = "HOLIDAY",
		sequenceType = "", startTime = At(2026, 11, 2, 2, 14, 0), endTime = At(2026, 11, 2, 2, 16, 0) }
	local EARLY = { eventID = 10, title = "Morning run", isCustomTitle = true, calendarType = "PLAYER", sequenceType = "",
		startTime = At(2026, 10, 13, 3, 8, 0), endTime = At(2026, 10, 13, 3, 8, 0), inviteStatus = 1 }
	local LATE = { eventID = 11, title = "Gnomeregan run", isCustomTitle = true, calendarType = "PLAYER", sequenceType = "",
		startTime = At(2026, 10, 13, 3, 11, 0), endTime = At(2026, 10, 13, 3, 11, 0), inviteStatus = 1 }
	local RESET = { eventID = 20, title = "Molten Core", isCustomTitle = false, difficultyName = "40 Player",
		calendarType = "RAID_RESET", sequenceType = "", startTime = At(2026, 10, 14, 4, 8, 0), endTime = At(2026, 10, 14, 4, 8, 0) }
	local GRAID = { eventID = 30, title = "Onyxia", isCustomTitle = true, calendarType = "GUILD_EVENT", sequenceType = "",
		startTime = At(2026, 10, 15, 5, 20, 0), endTime = At(2026, 10, 15, 5, 20, 0), inviteStatus = 0, invitedBy = "Bob" }
	local function Seq(ev, seq, extra)
		local c = {}
		for k, v in pairs(ev) do c[k] = v end
		c.sequenceType = seq
		for k, v in pairs(extra or {}) do c[k] = v end
		return c
	end
	local days = {}
	local function Add(m, d, ev)
		local k = m .. "-" .. d
		days[k] = days[k] or {}
		table.insert(days[k], ev)
	end
	local function Fill(dmfEnd)
		days = {}
		Add(10, 12, Seq(DMF, "START"))
		for d = 13, 17 do Add(10, d, Seq(DMF, "ONGOING")) end
		Add(10, 18, Seq(DMF, "END", dmfEnd))
		Add(10, 13, EARLY); Add(10, 13, LATE)
		Add(10, 14, RESET)
		Add(10, 15, GRAID)
		Add(10, 18, Seq(HE, "START"))
		for d = 19, 31 do Add(10, d, Seq(HE, "ONGOING")) end
		Add(11, 1, Seq(HE, "END"))
		Add(11, 2, FISH)
	end
	Fill()
	-- the month the calendar is turned to (offsets count from it)
	local base = { year = 2026, month = 10 }
	local function Abs(off)
		local i = base.year * 12 + (base.month - 1) + off
		return math.floor(i / 12), i % 12 + 1
	end
	local FIRST = { [10] = 5, [11] = 1, [12] = 3 }
	local NDAYS = { [10] = 31, [11] = 30, [12] = 31 }
	local asked = 0
	_G.C_Calendar = {
		GetMonthInfo = function(off)
			local y, m = Abs(off or 0)
			return { year = y, month = m, numDays = NDAYS[m] or 30, firstWeekday = FIRST[m] or 1 }
		end,
		GetNumDayEvents = function(off, day) local _, m = Abs(off) return #(days[m .. "-" .. day] or {}) end,
		GetDayEvent = function(off, day, i) local _, m = Abs(off) return (days[m .. "-" .. day] or {})[i] end,
		GetHolidayInfo = function(off, day, i)
			local _, m = Abs(off)
			local ev = (days[m .. "-" .. day] or {})[i]
			return ev and ev.calendarType == "HOLIDAY" and { name = ev.title, description = "About " .. ev.title } or nil
		end,
		OpenCalendar = function() asked = asked + 1 end,
	}
	_G.GetLocale = function() return "enUS" end
	_G.CalendarFrame, _G.CALENDAR_FIRST_WEEKDAY = nil, 1
	_G.GameTimeFrame = T.Obj("Button")

	P._dirty = true
	local res = UI:Search("@calendar")
	local names = {}
	for i, e in ipairs(res) do names[i] = e.name end
	check(#res == 6 and res[1].name == "Darkmoon Faire" and res[2].name == "Gnomeregan run" and res[3].name == "Molten Core (40 Player)"
		and res[4].name == "Onyxia" and res[5].name == "Hallow's End" and res[6].name == "Stranglethorn Fishing Extravaganza",
		"what's on, soonest first; this morning's event is over: " .. table.concat(names, ", "))
	local by = {}
	for _, e in ipairs(res) do by[e.name] = e end
	local dmf, run, mc, ony, he, fish = by["Darkmoon Faire"], by["Gnomeregan run"], by["Molten Core (40 Player)"], by["Onyxia"],
		by["Hallow's End"], by["Stranglethorn Fishing Extravaganza"]
	check(dmf.detail == "until Sunday 23:59  ·  Holiday", "a holiday under way: until when, to the minute: " .. tostring(dmf.detail))
	check(run.detail == "today 11:00  ·  Event  ·  Accepted", "an event that started an hour ago still shows: " .. tostring(run.detail))
	check(mc.detail == "tomorrow 8:00  ·  Raid reset", "tomorrow, with its time: " .. tostring(mc.detail))
	check(ony.detail == "Thursday 20:00  ·  Guild event  ·  Invited" and ony.pending and ony.color == "|cffffd200",
		"an invitation not answered yet: " .. tostring(ony.detail))
	check(he.detail == "Sunday 10:00 - Sunday, November 1  ·  Holiday", "one to come over several days: when it starts: " .. tostring(he.detail))
	check(fish.detail == "Monday, November 2 14:00 - 16:00  ·  Holiday", "next month's, its hours (0.49.14): " .. tostring(fish.detail))
	-- (0.49.14, the player's ask) the tooltip says when it starts and ends, as the calendar's own does: the fishing
	-- tournament's hours were only there
	local function Tip(e)
		local lines = {}
		local t = { SetText = function(_, a) lines[#lines + 1] = a end, AddLine = function(_, a) lines[#lines + 1] = a end,
			AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. ": " .. b end }
		e.tooltip(e, t)
		return table.concat(lines, "\n")
	end
	local ft = Tip(fish)
	check(ft:find("Starts: Monday, November 2 14:00", 1, true) and ft:find("Ends: 16:00", 1, true), "the fishing tournament's hours: " .. ft)
	local ht = Tip(he)
	check(ht:find("Starts: Sunday, October 18 10:00", 1, true) and ht:find("Ends: Sunday, November 1 10:00", 1, true),
		"several days: when it starts and ends, to the minute: " .. ht)
	-- (review, 0.49.17) one over several days starting later today: when it starts, not "until"
	local tonight = { multi = true, start = At(2026, 10, 13, 3, 18, 0), finish = At(2026, 10, 16, 6, 18, 0), startDN = CA.DayNum(2026, 10, 13) }
	check(CA.When(tonight) == "today 18:00 - Friday", "starting tonight: from when: " .. CA.When(tonight))
	local ot = Tip(ony)
	check(ot:find("When: Thursday, October 15 20:00", 1, true) and not ot:find("Ends", 1, true), "an event with no end: when: " .. ot)
	check(dmf.desc == "About Darkmoon Faire" and dmf.iconCoords and dmf.icon == 235448, "a holiday's text and its picture, cropped")
	check(asked >= 1, "the server is asked for the calendar")
	local enter, shift = E.Verbs(ony)
	check(enter == ns.L["show in calendar"] and shift == ns.L["put in the chat box"], "verbs: show in calendar / put in the chat box")
	check(E.CategoryOf(ony) == "calendar", "its own Simple mode category: " .. tostring(E.CategoryOf(ony)))

	-- Enter: the game opens the calendar (the minimap's button), turns the month and clicks the event's button
	local S = ns.Secure
	local function Macro(e) local r = S.Resolve(e.secure, e) return r and r.macro end
	check(Macro(dmf) == "/click GameTimeFrame\n/click CalendarDayButton22EventButton1",
		"a holiday under way: clicked on its last day (the calendar shows it there): " .. tostring(Macro(dmf)))
	check(Macro(he) == "/click GameTimeFrame\n/click CalendarDayButton22EventButton2", "the second event that day: " .. tostring(Macro(he)))
	check(Macro(ony) == "/click GameTimeFrame\n/click CalendarDayButton19EventButton1",
		"a holiday's middle day has no button: the raid is the first: " .. tostring(Macro(ony)))
	check(Macro(fish) == "/click GameTimeFrame\n/click CalendarNextMonthButton\n/click CalendarDayButton2EventButton1",
		"next month: turned there first: " .. tostring(Macro(fish)))
	_G.GetLocale = function() return "deDE" end
	check(Macro(dmf) == "/click GameTimeFrame\n/click CalendarDayButton21EventButton1",
		"a calendar whose weeks start on Monday (German), not loaded yet: " .. tostring(Macro(dmf)))
	_G.GetLocale = function() return "enUS" end
	-- open already, turned to November: no minimap click, back a month
	_G.CalendarFrame = T.Obj("Frame")
	_G.CalendarFrame.shown = true
	_G.CalendarFrame.viewedMonth, _G.CalendarFrame.viewedYear = 11, 2026
	check(Macro(dmf) == "/click CalendarPrevMonthButton\n/click CalendarDayButton22EventButton1", "open on another month: " .. tostring(Macro(dmf)))
	check(not dmf.isOpen(dmf), "something to press: pressed")
	-- left turned months away by hand: clicked back (no more than the macro's 255 characters hold)
	_G.CalendarFrame.viewedMonth, _G.CalendarFrame.viewedYear = 4, 2027
	local far = Macro(dmf)
	local _, backs = far:gsub("CalendarPrevMonthButton", "")
	check(backs == 6 and #far <= 255 and far:find("CalendarDayButton22EventButton1", 1, true), "six months back: " .. backs)
	_G.CalendarFrame.viewedMonth, _G.CalendarFrame.viewedYear = 11, 2026
	-- the calendar left turned to December: the game's offsets count from there, the same events and clicks
	base = { year = 2026, month = 12 }
	P._dirty = true
	res = UI:Search("@calendar")
	check(#res == 6 and Macro(res[1]) == "/click CalendarPrevMonthButton\n/click CalendarDayButton22EventButton1",
		"offsets from the month the calendar is turned to: " .. #res)
	base = { year = 2026, month = 10 }
	-- a holiday whose end the calendar doesn't show, open on this month: nothing to press, only pointed at (its day today)
	Fill({ dontDisplayEnd = true })
	_G.CalendarFrame.viewedMonth = 10
	P._dirty = true
	res = UI:Search("@calendar is:holiday")
	dmf = res[1]
	check(dmf.name == "Darkmoon Faire" and not dmf.at and Macro(dmf) == nil and dmf.isOpen(dmf),
		"shown on no day: nothing to press, the calendar open: only pointed at")
	-- afterwards: its event button pointed at (else its day)
	local shown
	ns.Highlight.Show = function(_, f) shown = f end
	_G.CalendarDayButton17 = T.Obj("Button")
	_G.CalendarDayButton17.shown = true
	dmf.after(dmf)
	T.FlushAll()
	check(shown == _G.CalendarDayButton17, "its day pointed at (13 October: the month starts on the 5th column, button 17)")
	Fill()
	P._dirty = true
	res = UI:Search("@calendar")
	dmf = res[1]
	_G.CalendarDayButton22, _G.CalendarDayButton22EventButton1 = T.Obj("Button"), T.Obj("Button")
	_G.CalendarDayButton22.shown, _G.CalendarDayButton22EventButton1.shown = true, true
	shown = nil
	dmf.after(dmf)
	T.FlushAll()
	check(shown == _G.CalendarDayButton22EventButton1, "the event's button pointed at")
	ns.Highlight.Show = save.show
	_G.CalendarFrame = nil

	-- Shift+Enter: in words, or the game's link to the event
	ony = nil
	for _, e in ipairs(res) do if e.name == "Onyxia" then ony = e end end
	check(ns.Share.Text(res[1]) == "Darkmoon Faire: until Sunday 23:59", "a holiday in words: " .. tostring(ns.Share.Text(res[1])))
	_G.GetCalendarEventLink = function(off, day, i) return "|Hcalendarevent:" .. off .. ":" .. day .. ":" .. i .. "|h[Onyxia]|h" end
	check(ns.Share.Text(ony) == "|Hcalendarevent:0:15:2|h[Onyxia]|h Thursday 20:00", "an event as its link: " .. tostring(ns.Share.Text(ony)))
	_G.GetCalendarEventLink = save.link

	-- filters
	check(#UI:Search("@calendar is:holiday") == 3 and #UI:Search("@calendar is:invite") == 1 and #UI:Search("@calendar is:today") == 2,
		"is:holiday, is:invite, is:today")

	-- the question, in plain words, and what stays a search
	local Q = CA.Question
	local function N(s) local rows = CA.Answer(Q(s)) return #rows, rows end
	check(Q("holidays") and Q("today") and Q("what's on") and Q("whats on this week") and Q("my invites") and Q("guild events")
		and Q("next darkmoon faire") and Q("when is hallow's end") and Q("calendar this week") and Q("upcoming events")
		and Q("anything coming up") and Q("next week") and Q("this weekend"), "questions")
	check(not Q("calendar") and not Q("darkmoon faire") and not Q("holiday cheer") and not Q("next quest") and not Q("invite bob")
		and not Q("guild") and not Q("guild blacksmith") and not Q("@calendar") and not Q("food today") and not Q("whats on my bars"),
		"searches stay searches")
	check(N("holidays") == 3 and N("today") == 2 and N("tomorrow") == 2 and N("this weekend") == 2 and N("my invites") == 1
		and N("guild events") == 1 and N("whats on this week") == 5 and N("next week") == 1 and N("next month") == 2,
		"what each asks: " .. table.concat({ N("holidays"), N("today"), N("tomorrow"), N("this weekend"), N("my invites"),
			N("guild events"), N("whats on this week"), N("next week"), (N("next month")) }, " "))
	-- (0.49.2, review) the words a row holds besides its name: its day, month, kind and who invited you
	check(Q("events on thursday") and N("events on thursday") == 1 and Q("invites from bob") and N("invites from bob") == 1
		and N("events in november") == 2, "a row's other words: " .. tostring((N("events in november"))))
	-- (0.49.2, review) the span kept in Advanced mode, and is:pending still @auction's
	check(E.ToAdvanced("whats on this week") == "@calendar when:week " and E.ToAdvanced("holidays next month")
		== "@calendar is:holiday when:nextmonth ", "Alt+` keeps the span: " .. E.ToAdvanced("whats on this week"))
	check(#UI:Search("@calendar when:week") == 5 and #UI:Search("@calendar when:nextmonth") == 2
		and #UI:Search("@calendar is:holiday when:weekend") == 2, "when:<span>")
	check(ns.Filters._.IS.pending == ns.Filters._.IS.incoming, "is:pending stays the auction house's news")
	local n, rows = N("when is hallows end")
	check(n == 1 and rows[1].name == "Hallow's End", "by name, its ' left out")
	local _, note = CA.Answer(Q("holidays this week"))
	check(note == ns.L["Holidays"] .. "  ·  " .. ns.L["this week"], "the footer: " .. tostring(note))
	check(E.ToAdvanced("holidays") == "@calendar is:holiday " and E.ToAdvanced("next darkmoon faire") == "@calendar darkmoon faire "
		and E.ToAdvanced("my invites") == "@calendar is:invite ", "Alt+`: " .. E.ToAdvanced("holidays"))
	-- (0.55.7) "guild events" as is:guild ("guild" was a word searched), and each finds what the question does
	check(E.ToAdvanced("guild events") == "@calendar is:guild ", "Alt+`: " .. E.ToAdvanced("guild events"))
	for _, q in ipairs({ "guild events", "holidays", "my invites", "whats on this week" }) do check(T.SameAsAdvanced(q)) end
	ns.db.easyMode = true
	res = UI:Search("holidays")
	check(#res == 3 and UI.answerNote and UI.answerNote:find(ns.L["Holidays"], 1, true), "Simple mode asks it too")
	ns.db.easyMode = false

	-- the server's calendar switched off: a line says so
	local hadEnum = _G.Enum and _G.Enum.GameRule
	_G.Enum = _G.Enum or {}
	_G.Enum.GameRule = { IngameCalendarDisabled = 99 }
	_G.C_GameRules = { IsGameRuleActive = function(r) return r == 99 end }
	P._dirty = true
	res = UI:Search("@calendar")
	check(#res == 1 and res[1].noActivate and res[1].name == CA.OFF, "switched off: " .. tostring(res[1] and res[1].name))
	_G.Enum.GameRule, _G.C_GameRules = hadEnum, save.rules

	-- asked at login, and at most every few minutes from the list
	local before = asked
	CA.askedAt = nil
	CA.OnEvent("PLAYER_ENTERING_WORLD", true, false)
	T.FlushAll()
	check(asked == before + 1 and not CA.Ask(CA.ASK_AGAIN), "asked at login, then not again so soon")

	_G.C_Calendar, _G.C_DateAndTime, _G.GetLocale, _G.GameTimeFrame = save.cal, save.dt, save.loc, save.gtf
	_G.CalendarFrame, _G.CALENDAR_FIRST_WEEKDAY = save.cf, save.fw
	_G.CalendarDayButton17, _G.CalendarDayButton22, _G.CalendarDayButton22EventButton1 = nil, nil, nil
	ns.db.easyMode = save.easy
	P._dirty = true
end

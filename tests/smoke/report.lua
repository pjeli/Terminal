-- (0.67.11, the player's call) .report: a problem report to copy and paste on CurseForge, your names left out, and
-- where it's pointed to (a search that found nothing, a blocked action, the row menu)
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local R = ns.Report

io.write("[report: .report, its text and where it's offered]\n")
local was = { show = ns.ShowText, char = ns.CharacterName, uname = _G.UnitName, guild = _G.GetGuildInfo, bg = _G.BugGrabber,
	mail = ns.Mail and ns.Mail.AltNames, missed = ns.db.missed, last = UI.lastQuery, print = ns.Print, easy = ns.db.easyMode,
	nudged = R.nudged }
local ok, err = pcall(function()
	local shown
	ns.ShowText = function(_, title, text) shown = { title = title, text = type(text) == "table" and table.concat(text, "\n") or text } end
	ns.CharacterName = function() return "Plamen Warr" end
	_G.UnitName = function() return "Plamen", "Warr" end
	_G.GetGuildInfo = function() return "Knights of Elwynn" end
	ns.Mail.AltNames = function() return { "Bobalt" } end
	ns.db.missed = { { t = "stinging vipr" }, { t = "rumsy rum" } }
	UI.lastQuery = "stinging vipr"
	ns:Trace("mail: Plamen Warr sent Bobalt 5g; Plamenx stays; Knights of Elwynn read")

	check(ns:FindCommand("bug") == ns.commands.report, ".bug is .report too")
	local said = ns.commands.report.run("  the search can't see my viper  ")
	local text = shown and shown.text or ""
	check(shown and shown.title:find("CurseForge", 1, true), "in the copy window, pointing to CurseForge: " .. tostring(shown and shown.title))
	check(said and said[1]:find("CurseForge", 1, true) and said[1]:find("GitHub", 1, true), "chat says where to paste it: " .. tostring(said and said[1]))
	check(text:find("What happened: the search can't see my viper\n", 1, true), "what you said happened, trimmed")
	check(text:find("Last search: stinging vipr", 1, true) and text:find("stinging vipr; rumsy rum", 1, true),
		"the last search and the searches that found nothing")
	check(text:find("Terminal " .. tostring(ns.version), 1, true) and text:find("mode", 1, true), "Terminal's version and the mode")
	check(text:find("you sent alt 1 5g", 1, true) and text:find("Plamenx stays", 1, true) and text:find("your guild read", 1, true)
		and not text:find("Plamen Warr", 1, true) and not text:find("Bobalt", 1, true) and not text:find("Knights", 1, true),
		"your names, your alts' and your guild's left out (whole names only): " .. text)
	check(not text:find("|c", 1, true), "no colour codes in it")

	-- nothing said: a place to say it
	text = (function() ns.commands.report.run(""); return shown.text end)()
	check(text:find("What happened: (say what happened here)", 1, true), "nothing said: a place to say it")

	-- a password typed is never the last search
	UI.lastQuery = ".share join raid hunter2"
	ns.commands.report.run("x")
	check(not shown.text:find("hunter2", 1, true), "a password line isn't the last search")
	UI.lastQuery = "stinging vipr"

	-- the result it's about: an item by its name and key; a person never by name
	R.Open({ row = { kind = "items", name = "|cff1eff00Stinging Viper|r", key = 3336, detail = "x2  Backpack" } })
	check(shown.text:find('About this result: items "Stinging Viper" (key 3336) · x2  Backpack', 1, true), "the row it's about: " .. shown.text)
	R.Open({ row = { kind = "guild", name = "Fatherless Behavior", key = "Fatherless Behavior", detail = "Orgrimmar" } })
	check(shown.text:find('About this result: guild "(a player)"', 1, true) and not shown.text:find("Fatherless", 1, true),
		"a guildie's row: never their name")

	-- Terminal's errors BugSack caught, newest first, only Terminal's
	_G.BugGrabber = { GetDB = function() return {
		{ message = "Interface/AddOns/Other/x.lua:1: not ours" },
		{ message = "Interface\\AddOns\\Terminal\\UI\\UI.lua:10: oops\nstack line", counter = 3 },
	} end }
	R.Open({})
	check(shown.text:find("Errors (BugSack), newest first:\n  Interface\\AddOns\\Terminal\\UI\\UI.lua:10: oops (x3)", 1, true)
		and not shown.text:find("not ours", 1, true), "Terminal's errors from BugSack, one line each: " .. shown.text)
	_G.BugGrabber = { GetDB = function() error("changed") end }
	R.Open({})
	check(not shown.text:find("Errors", 1, true), "BugSack's API failing: no error lines, no error")
	_G.BugGrabber = nil

	-- once a session: a blocked action points to .report
	local printed = 0
	ns.Print = function(_, s) if tostring(s):find(".report", 1, true) then printed = printed + 1 end end
	R.nudged = nil
	R.Nudge(); R.Nudge()
	check(printed == 1, "pointed to .report once a session: " .. printed)

	-- Simple mode's "Nothing has that": .report in its detail
	ns.db.easyMode = true
	UI:Open("zzqqxxww"); FlushAll()
	local row = UI.Results()[1]
	check(row and row.noActivate and row.detail == R.HINT, "Simple mode's nothing-found row says .report: " .. tostring(row and row.detail))
	UI:Hide(); FlushAll()
end)
ns.ShowText, ns.CharacterName, _G.UnitName, _G.GetGuildInfo, _G.BugGrabber = was.show, was.char, was.uname, was.guild, was.bg
ns.Mail.AltNames, ns.db.missed, UI.lastQuery, ns.Print, R.nudged = was.mail, was.missed, was.last, was.print, was.nudged
ns.db.easyMode = was.easy
UI:EasyChanged(); UI:Hide(); FlushAll()
check(ok, "report: " .. tostring(err))

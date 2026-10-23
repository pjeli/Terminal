-- Lockouts (Lockouts.lua, 0.48.2, the player's ask): @lockout / @lockouts / @saved: the raids and dungeons each of your
-- characters is saved to, bosses down and when each resets; yours from the game, your alts' from Terminal's own note.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[lockouts]\n")
do
	local LK, P, E = ns.Lockouts, ns.providers.lockouts, ns.Easy
	local save = { n = _G.GetNumSavedInstances, info = _G.GetSavedInstanceInfo, enc = _G.GetSavedInstanceEncounterInfo,
		wn = _G.GetNumSavedWorldBosses, winfo = _G.GetSavedWorldBossInfo, link = _G.GetSavedInstanceChatLink,
		ask = _G.RequestRaidInfo, guid = _G.UnitGUID, cls = _G.UnitClass, realm = _G.GetRealmName, time = _G.time,
		db = ns.db.lockouts, easy = ns.db.easyMode, answered = LK.answered, out = ns.Output }
	check(P and ns:ResolveProvider("lockout") == P and ns:ResolveProvider("lockouts") == P and ns:ResolveProvider("saved") == P,
		"@lockout, @lockouts and @saved")
	local now = 2000000
	_G.time = function() return now end
	_G.UnitGUID = function() return "Player-1-AAA" end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.GetRealmName = function() return "Forever" end
	local asked = 0
	_G.RequestRaidInfo = function() asked = asked + 1 end
	ns.db.lockouts = {}
	ns.db.easyMode = false
	local saved = {}
	_G.GetNumSavedInstances = function() return #saved end
	_G.GetSavedInstanceInfo = function(i)
		local s = saved[i]
		if not s then return nil end
		-- name, id, reset, difficulty, locked, extended, mostSig, isRaid, maxPlayers, difficultyName, total, done, extendDisabled, mapID
		return s[1], s[2], s[3], 1, s[4], s[5], false, s[6], s[7], s[8], s[9], s[10], false, 409
	end
	_G.GetSavedInstanceEncounterInfo = function(i, j)
		if saved[i] and saved[i][1] == "Molten Core" and j <= 3 then
			return ({ "Lucifron", "Magmadar", "Gehennas" })[j], 0, j <= 2
		end
	end
	_G.GetNumSavedWorldBosses = function() return 0 end
	_G.GetSavedWorldBossInfo = function() return nil end
	_G.GetSavedInstanceChatLink = function(i) return saved[i] and ("|Hinstancelock:x:" .. i .. "|h[" .. saved[i][1] .. "]|h") end

	-- nothing saved anywhere: a line says so
	LK.answered = nil
	P._dirty = true
	local res = UI:Search("@lockout")
	check(#res == 1 and res[1].noActivate and res[1].name == LK.NONE, "nothing saved: a line says so: " .. tostring(res[1] and res[1].name))

	-- the game answers: yours, raids first, then the soonest reset; one the game shows expired is left out
	saved = {
		{ "Wailing Caverns", 77, 3600 * 5 + 600, true, false, false, 5, "Heroic", 8, 3 },
		{ "Molten Core", 1234, 86400 * 3 + 3600 * 4 + 30, true, false, true, 40, "40 Player", 10, 6 },
		{ "Onyxia's Lair", 99, 86400, false, false, true, 40, "40 Player", 1, 1 }, -- (expired: greyed in the game's window)
	}
	LK.OnEvent("UPDATE_INSTANCE_INFO")
	check(LK.answered and #ns.db.lockouts["Player-1-AAA"].list == 2, "the game's answer is kept: " .. #ns.db.lockouts["Player-1-AAA"].list)
	P._dirty = true
	res = UI:Search("@lockout")
	check(#res == 2 and res[1].name == "Molten Core" and res[2].name == "Wailing Caverns", "raids first: " .. tostring(res[1] and res[1].name))
	check(res[1].detail:find("6/10 bosses", 1, true) and res[1].detail:find("resets in 3 d 4 h", 1, true)
		and res[1].detail:find("40 Player", 1, true), "bosses down and when it resets: " .. tostring(res[1].detail))
	check(res[2].detail:find("resets in 5 h 10 min", 1, true), "hours and minutes: " .. tostring(res[2].detail))
	check(res[1].bosses and #res[1].bosses == 3 and res[1].bosses[3][2] == false, "the bosses the game names")
	check(ns.Share.Text(res[1]):find("|Hinstancelock:", 1, true), "Shift+Enter / sending: your own lockout's link")
	local lines
	ns.Output = function(_, l) lines = l end
	res[1].activate(res[1])
	ns.Output = save.out
	check(lines and lines[2] and lines[2]:find("Down: Lucifron, Magmadar", 1, true) and lines[3]:find("Still up: Gehennas", 1, true),
		"Enter: in chat with the bosses: " .. tostring(lines and lines[2]))
	local enter, shift = E.Verbs(res[1])
	check(enter == ns.L["show in chat"] and shift == ns.L["link in chat"], "verbs: show in chat / link in chat")

	-- before the game has answered this session (a login), an empty reading doesn't replace what was kept
	LK.answered = nil
	saved = {}
	P._dirty = true
	res = UI:Search("@lockout")
	check(#res == 2, "the game not answered yet: the kept lockouts stay: " .. #res)
	-- (without the wait: mutation check)
	LK.answered = true
	saved = {
		{ "Molten Core", 1234, 86400 * 3 + 3600 * 4, true, false, true, 40, "40 Player", 10, 6 },
		{ "Wailing Caverns", 77, 3600 * 5 + 600, true, false, false, 5, "Heroic", 8, 3 },
	}
	LK.OnEvent("UPDATE_INSTANCE_INFO")

	-- an alt, as last seen: a lockout that has reset since is gone; the alt's name in the row; on: names it
	ns.db.lockouts["Player-1-BBB"] = { name = "Alt Pally", realm = "Forever", class = "PALADIN", t = now - 3600, list = {
		{ name = "Zul'Gurub", id = 5, reset = now + 86400 * 2, isRaid = true, done = 4, total = 10, diff = "20 Player" },
		{ name = "Blackwing Lair", id = 6, reset = now - 60, isRaid = true, done = 8, total = 8 },
	} }
	P._dirty = true
	res = UI:Search("@lockout")
	local zg
	for _, e in ipairs(res) do if e.name == "Zul'Gurub" then zg = e end end
	check(#res == 3 and zg and not zg.mine and zg.detail:find("Alt Pally", 1, true), "an alt's lockout, named: " .. #res)
	check(#ns.db.lockouts["Player-1-BBB"].list == 1, "one that has reset since is dropped")
	check(ns.Share.Text(zg) == "Alt Pally: Zul'Gurub (20 Player) 4/10 bosses, resets in 2 d 0 h", "an alt's in words: " .. ns.Share.Text(zg))
	check(#UI:Search("@lockout on:pally") == 1 and #UI:Search("@lockout is:raid") == 2 and #UI:Search("@lockout is:dungeon") == 1,
		"on:, is:raid, is:dungeon")
	enter, shift = E.Verbs(zg)
	check(shift == ns.L["put in the chat box"], "an alt's Shift+Enter: put in the chat box")

	-- the question, in plain words (both modes), and what stays a search
	local function Q(s) return LK.Question(s) end
	check(Q("my lockouts") and Q("lockouts") and Q("am i saved") and Q("raid id") and Q("what raids am i saved to")
		and Q("dungeon lockouts") and Q("when does mc reset") and Q("raid reset"), "questions")
	check(not Q("locked chest") and not Q("reset") and not Q("saved") and not Q("dungeon") and not Q("raid")
		and not Q("@lockout") and not Q(".nav reset") and not Q("saved potion recipes"), "searches stay searches")
	check(Q("raid lockouts").raid and not Q("raid lockouts").dungeon and Q("heroic lockouts").dungeon, "raid / dungeon asked")
	local rows, note = LK.Answer(Q("raid lockouts"))
	check(#rows == 2 and note:find(ns.L["Raid lockouts"], 1, true) and note:find("1 yours, 1 on alts", 1, true), "raid lockouts: " .. tostring(note))
	rows = LK.Answer(Q("when does mc reset"))
	check(#rows == 1 and rows[1].name == "Molten Core", "a shorthand narrows it (mc = Molten Core)")
	rows = LK.Answer(Q("lockouts naxxramas"))
	check(#rows == 1 and rows[1].noActivate, "nothing has that: a line")
	check(E.ToAdvanced("raid lockouts") == "@lockout is:raid " and E.ToAdvanced("when does mc reset") == "@lockout mc ",
		"Alt+`: " .. E.ToAdvanced("raid lockouts"))
	ns.db.easyMode = true
	res = UI:Search("my lockouts")
	check(#res == 3 and UI.answerNote and UI.answerNote:find(ns.L["Lockouts"], 1, true), "Simple mode asks it too")
	check(E.CategoryOf(res[1]) == "character", "under Character: " .. tostring(E.CategoryOf(res[1])))
	ns.db.easyMode = false

	-- asked at login and after a boss dies (C_Timer.After runs at once in the harness or later: count either way)
	local before = asked
	LK.askedAt = nil
	check(LK.Ask(60) and not LK.Ask(60) and asked == before + 1, "asked at most once a minute from the list")
	check(ns:FindCommand("forget").run("alt pally")[1]:find("Forgot", 1, true) and not ns.db.lockouts["Player-1-BBB"],
		".forget <alt>: its lockouts")

	-- (0.49.2, review) your world boss has no link: its tooltip says Shift+Enter puts it in words
	do
		local function TipLines(e)
		local lines = {}
		local t = { SetText = function(_, s) lines[#lines + 1] = tostring(s) end,
			AddLine = function(_, s) lines[#lines + 1] = tostring(s) end,
			AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " " .. tostring(b) end }
		e.tooltip(e, t)
		return table.concat(lines, "\n")
	end
		saved = {}
		_G.GetNumSavedWorldBosses = function() return 1 end
		_G.GetSavedWorldBossInfo = function() return "Azuregos", 9, 3600 end
		LK.OnEvent("UPDATE_INSTANCE_INFO")
		P._dirty = true
		local wb
		for _, e in ipairs(UI:Search("@lockout")) do if e.world then wb = e end end
		local tl = wb and TipLines(wb) or ""
		check(wb and wb.mine and tl:find("Enter: show in chat\nShift+Enter: put it in the chat box", 1, true)
			and not tl:find("its link", 1, true), "your world boss: no link promised")
	end
	_G.GetNumSavedInstances, _G.GetSavedInstanceInfo, _G.GetSavedInstanceEncounterInfo = save.n, save.info, save.enc
	_G.GetNumSavedWorldBosses, _G.GetSavedWorldBossInfo, _G.GetSavedInstanceChatLink = save.wn, save.winfo, save.link
	_G.RequestRaidInfo, _G.UnitGUID, _G.UnitClass, _G.GetRealmName, _G.time = save.ask, save.guid, save.cls, save.realm, save.time
	ns.db.lockouts, ns.db.easyMode, LK.answered = save.db, save.easy, save.answered
	P._dirty = true
end

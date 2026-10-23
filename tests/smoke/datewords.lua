-- Dates in plain words (0.66.8, the player): "loot from yesterday", "mail older than 20 days", "auctions sold this week",
-- "what killed me today"; since: and older: in Advanced. Search/Filters/Others.lua (TimeStart, RowTime), Easy.lua
-- (DateAt), Search.lua (a question's dates after it).
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local E, F = ns.Easy, ns.Filters

io.write("[datewords: since: and older:, in words too]\n")
do
	local function Read(text)
		local words = {}
		for w in text:gmatch("%S+") do words[#words + 1] = w end
		return table.concat((E.PlainNumbers(words)), " ")
	end
	local CASES = {
		{ "loot from yesterday", "loot since:yesterday older:today" },
		{ "loot today", "loot since:today" },
		{ "mail older than 20 days", "mail older:20d" },
		{ "mail more than 2 weeks old", "mail older:2w" },
		{ "auctions sold this week", "auctions sold since:week" },
		{ "what killed me today", "what killed me since:today" },
		{ "loot in the last 3 days", "loot since:3d" },
		{ "loot last hour", "loot since:1h" },
		{ "loot past 10 minutes", "loot since:10m" },
		{ "loot since login", "loot since:login" },
		{ "loot this session", "loot since:login" },
		{ "loot since yesterday", "loot since:yesterday" },
		-- words of their own
		{ "last stand", "last stand" },
		{ "this", "this" },
		{ "older than dirt", "older than dirt" },
	}
	for _, c in ipairs(CASES) do
		local got = Read(c[1])
		check(got == c[2], ("%q -> %q: %s"):format(c[1], c[2], got))
	end

	local save = { time = _G.time, date = _G.date }
	-- a day: October 22, 2026, 15:00 local (the test's own clock)
	local now = os.time({ year = 2026, month = 10, day = 22, hour = 15, min = 0, sec = 0 })
	_G.time = function(t) if t then return os.time(t) end return now end
	_G.date = function(f, t) return os.date(f, t or now) end
	local midnight = os.time({ year = 2026, month = 10, day = 22, hour = 0 })
	check(F.TimeStart("today") == midnight and F.TimeStart("yesterday") == midnight - 86400, "today and yesterday: from midnight")
	-- (review) the day after the clocks went forward: yesterday was 23 hours long, its midnight by the calendar
	local realT = _G.time
	_G.time = function(t)
		if not t then return now end
		if t.day == 22 then return midnight end
		if t.day == 21 then return midnight - 23 * 3600 end
		return realT(t)
	end
	check(F.TimeStart("yesterday") == midnight - 23 * 3600, "yesterday on a 23-hour day: its own midnight: " .. tostring(midnight - F.TimeStart("yesterday")))
	_G.time = realT
	check(F.TimeStart("3d") == now - 3 * 86400 and F.TimeStart("2h") == now - 7200 and F.TimeStart("30m") == now - 1800
		and F.TimeStart("week") == now - 7 * 86400, "a time ago")
	check(F.TimeStart("bogus") == nil and F.Parse("since:bogus") == nil, "since:bogus isn't one")
	-- the rows' times
	local loot = { kind = "lootlog", entry = { t = now - 3600 } }
	local oldLoot = { kind = "lootlog", entry = { t = midnight - 3600 } }
	local mail = { kind = "mail", mail = { expires = now + 5 * 86400 } } -- (arrived 25 days ago)
	local cod = { kind = "mail", mail = { expires = now + 2 * 86400, cod = 100 } } -- (a day ago)
	local sold = { kind = "auctions", auction = { at = now - 2 * 86400 } }
	local bb = { kind = "buyback", t = now - 60 }
	local hit = { kind = "combatlog", at = now - 600 }
	local item = { kind = "items", name = "Linen Cloth" }
	check(F.RowTime(mail) == now - 25 * 86400 and F.RowTime(cod) == now - 86400 and F.RowTime(item) == nil, "a mail's arrival; an item has no time")
	local today, yesterday, notToday = F.Parse("since:today"), F.Parse("since:yesterday"), F.Parse("older:today")
	check(today(loot) and not today(oldLoot) and yesterday(oldLoot) and notToday(oldLoot) and not notToday(loot), "today, yesterday")
	check(F.Parse("older:20d")(mail) and not F.Parse("older:20d")(cod), "mail older than 20 days")
	check(F.Parse("since:week")(sold) and today(bb) and today(hit) and not today(item), "this week's sale; today's buyback and hit; not an item")
	-- a question with its dates after it: "what killed me today"
	local CB = ns.CombatLog
	local realNow = ns.Now
	ns.db.combatLog = {
		{ what = "killed", who = "Hogger", spell = "Mortal Strike", amount = 300, t = now - 600, guid = "Player-1" },
		{ what = "killed", who = "Kobold", spell = "Bite", amount = 20, t = now - 3 * 86400, guid = "Player-1" },
	}
	CB.SetMe("Player-1")
	ns.providers.combatlog._dirty = true
	local res = UI:SearchText("what killed me")
	local n = 0
	for _, e in ipairs(res) do if e.what == "killed" then n = n + 1 end end
	check(n == 2, "what killed me: both deaths: " .. n)
	local easy = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	res = UI:SearchText("what killed me today")
	n = 0
	local who
	for _, e in ipairs(res) do if e.what == "killed" then n, who = n + 1, e.name end end
	check(n == 1 and tostring(who):find("Hogger", 1, true), "what killed me today: today's only: " .. n .. " " .. tostring(who))
	local adv = ns.Easy.ToAdvanced("what killed me today")
	check(adv:find("@combatlog", 1, true) and adv:find("since:today", 1, true), "Alt+`: the question's form, since:today after it: " .. adv)
	ns.db.easyMode = easy; UI:EasyChanged()
	ns.db.combatLog = {}
	ns.providers.combatlog._dirty = true
	_G.time, _G.date, ns.Now = save.time, save.date, realNow
end

io.write("[datewords: a name with a date's or a level's words in it (review)]\n")
do
	local B = ns.Bar
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local NAMES = { "Tonight We Dine", "Last Day of Summer", "Next Level Thinking", "Copper Bar" }
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for i, n in ipairs(NAMES) do out[i] = { name = n, key = i, itemID = 9900 + i } end
		return out
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = true; UI:EasyChanged()
	local function Has(q)
		local res = UI:Search(q)
		for _, e in ipairs(res) do
			local n = tostring((e.catId and e.detail) or e.name)
			if ns.Lower(n):find(q, 1, true) then return true end
		end
		return false, #res
	end
	for _, q in ipairs({ "tonight we dine", "last day of summer", "next level thinking" }) do
		check(Has(q), q .. ": the name found, not a date or level that nothing has")
	end
	check(ns.Easy.PlainNumbers({ "loot", "today" })[2] == "since:today", "a date alone is still one")
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

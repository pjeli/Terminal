-- (0.68.4, the player's design: docs/ASK.md) !t: guildies and group members ask Terminal a question and one Terminal
-- user's client answers. Several clients over a pretend guild channel (A.New with a test env), then the answer's
-- search itself: only the world's lists, from the asker's side, the terminal's own search untouched.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check
local A = ns.Ask

io.write("[ask: reading !t questions]\n")
check(A.Question("!t nearest inn") == "nearest inn" and A.Question("  !T Where Is Hogger  ") == "Where Is Hogger"
	and A.Question("!terminal what drops x") == "what drops x", "!t and !terminal, any case, at the start")
check(A.Question("!t") == "help" and A.Question("!terminal") == "help" and A.Question("!t   ") == "help", "!t alone: help")
check(A.Question("!tea time") == nil and A.Question("hi !t x") == nil and A.Question("!keys") == nil
	and A.Question("?t x") == nil and A.Question("t x") == nil, "anything else isn't a question")
check(A.Question("!t " .. ("x"):rep(A.QUESTION_MAX + 1)) == nil, "a very long line isn't answered")

io.write("[ask: a question in another language is left unanswered]\n")
check(A.InLocale("where is hogger?!", "enUS") and not A.InLocale("n\195\164chster gastwirt", "enUS"),
	"an English client reads a-z only")
check(A.InLocale("n\195\164chster gastwirt", "deDE") and A.InLocale("o\195\185 est l'aubergiste", "frFR"), "German, French: their letters")
check(A.InLocale("\208\177\208\187\208\184\208\182\208\176\208\185\209\136\208\184\208\185", "ruRU")
	and not A.InLocale("\208\177\208\187\208\184\208\182\208\176\208\185\209\136\208\184\208\185", "enUS"), "Russian on a Russian client only")
check(A.InLocale("\230\156\128\232\191\145\231\154\132\230\151\133\229\186\151", "zhCN")
	and not A.InLocale("\230\156\128\232\191\145\231\154\132\230\151\133\229\186\151", "deDE"), "Chinese on a Chinese client only")
check(A.InLocale("hogger\239\188\159", "zhCN") and not A.InLocale("hi \240\159\152\128", "enUS"),
	"full-width marks are marks; an emoji isn't a letter any client reads")

-- a pretend guild: a clock, timers, what was said, and the clients hearing each other's hidden claims
local function Net()
	local net = { t = 100, timers = {}, said = {}, clients = {} }
	function net.after(s, f) net.timers[#net.timers + 1] = { at = net.t + s, f = f, n = #net.timers } end
	function net.run(secs)
		local stop = net.t + secs
		while true do
			table.sort(net.timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.n < b.n end)
			local x = net.timers[1]
			if not x or x.at > stop then break end
			table.remove(net.timers, 1)
			net.t = x.at
			x.f()
		end
		net.t = stop
	end
	return net
end
local function Client(net, guid, opts)
	opts = opts or {}
	local c = { guid = guid, printed = {}, rand = opts.rand or 0.5, asked = 0,
		settings = opts.settings or { guild = true, group = true, whisper = true } }
	c.inst = A.New({
		me = function() return guid end,
		now = function() return net.t end,
		after = net.after,
		random = function() return c.rand end,
		send = function(text, chat, target) net.said[#net.said + 1] = { from = guid, text = text, chat = chat, target = target, t = net.t } end,
		addon = function(msg)
			for _, o in ipairs(net.clients) do
				if o ~= c then net.after(net.lag or 0.05, function() o.inst:OnAddon(A.PREFIX, msg) end) end
			end
		end,
		print = function(line) c.printed[#c.printed + 1] = line end,
		locked = function() return net.locked == true end,
		combat = function() return c.combat == true end,
		setting = function(n) return c.settings[n] == true end,
		asker = function(sender)
			c.askerCalls = (c.askerCalls or 0) + 1
			return { name = sender, trusted = not (net.strangers and net.strangers[sender]) }
		end,
		answer = function(q, who)
			c.asked = c.asked + 1
			if opts.answer then return opts.answer(q, who, c.asked) end
			return "Terminal (" .. who.name .. "): about " .. q
		end,
		locale = function() return opts.locale or "enUS" end,
		battleground = function() return net.bg == true end,
	})
	net.clients[#net.clients + 1] = c
	return c
end
local function Say(net, event, text, sender, guid)
	for _, c in ipairs(net.clients) do c.inst:OnChat(event, text, sender, guid) end
end
local BOB = "Player-1-0000B0B0"

io.write("[ask: off until switched on, said once]\n")
do
	local net = Net()
	local c = Client(net, "Player-1-00000001", { settings = {} })
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(5)
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Ann", "Player-1-00000A00")
	net.run(5)
	check(#net.said == 0 and c.asked == 0, "nothing answered, nothing searched")
	check(#c.printed == 1 and c.printed[1]:find(".ask guild on", 1, true) and c.printed[1]:find("Bob", 1, true),
		"you're told once how to switch it on: " .. tostring(c.printed[1]))
	check(c.inst.log[1].why == "off", ".ask lists it as not switched on")
	check(not A.On("guild") and not A.On("group") and not A.On("whisper"), "the game's client: off everywhere at first")
end

io.write("[ask: several Terminals, one answer]\n")
do
	local net = Net()
	local a = Client(net, "Player-1-00000003", { rand = 0.9 })
	local b = Client(net, "Player-1-00000002", { rand = 0.1 })
	local c = Client(net, "Player-1-00000001", { rand = 0.5 })
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].from == b.guid and net.said[1].chat == "GUILD"
		and net.said[1].text == "Terminal (Bob): about nearest innkeeper", "one answer, from the first to claim, in guild chat: "
		.. #net.said .. " " .. tostring(net.said[1] and net.said[1].from))
	check(a.asked == 0 and c.asked == 0 and a.inst.log[1].why == "claimed" and c.inst.log[1].why == "claimed",
		"the others didn't even search")
	-- two claiming at the same moment: the lower GUID answers
	net = Net()
	local hi = Client(net, "Player-1-00000009", { rand = 0.5 })
	local lo = Client(net, "Player-1-00000004", { rand = 0.5 })
	Say(net, "CHAT_MSG_PARTY", "!t nearest mailbox", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].from == lo.guid and net.said[1].chat == "PARTY" and hi.asked == 0,
		"a tie: the lower GUID answers, in party chat: " .. #net.said)
end

io.write("[ask: your own question, answered for you]\n")
do
	local net = Net()
	local bob = Client(net, BOB, { rand = 0.1 })
	local other = Client(net, "Player-1-00000001", { rand = 0.1 })
	Say(net, "CHAT_MSG_GUILD", "!t where is hogger", "Bob", BOB)
	net.run(5)
	check(#net.said == 0, "nothing sent: " .. #net.said)
	check(bob.printed[1] == "Terminal (Bob): about where is hogger" and other.asked == 0,
		"you see the answer in your chat; the others saw your claim and stayed quiet")
	-- (off everywhere, your own question is still answered for you)
	net = Net()
	local solo = Client(net, BOB, { settings = {} })
	Say(net, "CHAT_MSG_GUILD", "!t where is hogger", "Bob", BOB)
	check(solo.printed[1] == "Terminal (Bob): about where is hogger", "switched off: still answered for you")
end

io.write("[ask: whispers from friends, guildies and your group only]\n")
do
	local net = Net()
	net.strangers = { Zed = true }
	local c = Client(net, "Player-1-00000001")
	c.inst:OnChat("CHAT_MSG_WHISPER", "!t nearest innkeeper", "Zed", "Player-1-0000ZED0")
	net.run(5)
	check(#net.said == 0 and c.inst.log[1].why == "stranger", "a stranger's whisper: unanswered")
	c.inst:OnChat("CHAT_MSG_WHISPER", "!t nearest innkeeper", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].chat == "WHISPER" and net.said[1].target == "Bob", "a guildie's: whispered back")
end

io.write("[ask: lockdown, combat, language: quiet]\n")
do
	local net = Net()
	local c = Client(net, "Player-1-00000001")
	net.locked = true
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(5)
	net.locked = nil
	c.combat = true
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Ann", "Player-1-00000A00")
	net.run(5)
	c.combat = nil
	Say(net, "CHAT_MSG_GUILD", "!t n\195\164chster gastwirt", "Cid", "Player-1-00000C1D")
	net.run(5)
	check(#net.said == 0 and c.asked == 0, "nothing sent or searched: " .. #net.said)
	check(c.inst.log[3].why == "lockdown" and c.inst.log[2].why == "combat" and c.inst.log[1].why == "language",
		"each said why in .ask")
	-- (combat begun between claiming and answering: still nothing)
	Say(net, "CHAT_MSG_GUILD", "!t nearest anvil", "Dan", "Player-1-00000DA0")
	net.run(0.5)
	c.combat = true
	net.run(5)
	check(#net.said == 0, "combat after the claim: nothing sent")
end

io.write("[ask: how often]\n")
do
	local net = Net()
	local c = Client(net, "Player-1-00000001")
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(3)
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Bob", BOB)
	net.run(3)
	check(#net.said == 1 and c.inst.log[1].why == "soon", "one asker: not again within " .. A.ASKER_GAP .. " s")
	net.run(10)
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(3)
	check(#net.said == 1 and c.inst.log[1].why == "again", "the same question: not again within a minute")
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Bob", BOB)
	net.run(3)
	check(#net.said == 2, "another question later: answered")
	for i = 1, A.CHANNEL_MAX + 2 do
		Say(net, "CHAT_MSG_GUILD", "!t where is hogger", "Asker" .. i, "Player-1-0000F00" .. i)
	end
	net.run(30)
	check(#net.said == A.CHANNEL_MAX, "at most " .. A.CHANNEL_MAX .. " answers a minute in a channel: " .. #net.said)
	local gaps = true
	for i = 2, #net.said do if net.said[i].t - net.said[i - 1].t < A.SEND_GAP - 0.001 then gaps = false end end
	check(gaps, "one line at a time, " .. A.SEND_GAP .. " s apart")
end

io.write("[ask: nothing found, still loading]\n")
do
	local net = Net()
	Client(net, "Player-1-00000001", { answer = function() return nil, false end })
	Say(net, "CHAT_MSG_GUILD", "!t the meaning of life", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].text:find("nothing found for \"the meaning of life\"", 1, true)
		and net.said[1].text:find("!t help", 1, true), "nothing found: one short line saying so: " .. tostring(net.said[1] and net.said[1].text))
	net = Net()
	local c = Client(net, "Player-1-00000001", { answer = function(q, who, n)
		if n < 3 then return nil, true end
		return "Terminal (" .. who.name .. "): found it"
	end })
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(15)
	check(#net.said == 1 and net.said[1].text == "Terminal (Bob): found it" and c.asked == 3,
		"a list still loading: searched again until it's in: " .. c.asked)
end

io.write("[ask: the answer: the world's lists, from the asker's side, your search untouched]\n")
do
	local I, F = ns.Integrations, ns.Filters
	local function drop(id)
		ns.providers[id] = nil
		for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == id then table.remove(ns.providerOrder, i) end end
		ns:AliasesChanged()
	end
	local seen = {}
	local E = ns.Easy
	local catsWere = #E.CATEGORIES
	-- (two lists in two Simple-mode categories, yours shown first: "hogger" lists the categories to pick from)
	ns:RegisterProvider("askmine", { label = "Mine", aliases = { "askmine" }, simpleCategory = { id = "askmine", label = "Mine" },
		collect = function() return { { name = "Hogger's Hat", key = 2 }, { name = "Hogger's Hood", key = 3 } } end })
	ns:RegisterProvider("asktest", { label = "Ask test", aliases = { "asktest" }, simpleCategory = { id = "asktest", label = "World" },
		collect = function()
			seen.here, seen.class, seen.level = I.Here(), ns.Asker and ns.Asker.class, ns.Asker and ns.Asker.level
			return { { name = "Hogger", key = 1 } }
		end })
	A.ALLOW.asktest = true
	local was = { scan = UI.lastScan, cat = UI.category, easy = ns.db.easyMode }
	local sentinel = { "the terminal's own last scan" }
	UI.lastScan = sentinel
	ns.db.easyMode = false -- (Advanced in the terminal: the question is still read as Simple mode reads it)
	local spot = { cont = 1, x = 10, y = 20 }
	local ok, err = pcall(function()
		local rows = A.Rows("hogger", { name = "Bob", here = spot, class = "MAGE", level = 23 })
		local names = {}
		for _, e in ipairs(rows) do names[#names + 1] = tostring(e.name) end
		check(#rows == 1 and rows[1].name == "Hogger", "only the world's lists: never your own: " .. table.concat(names, ", "))
		check(seen.here == spot and seen.class == "MAGE" and seen.level == 23, "searched from the asker's side: where they stand, class, level")
		check(ns.Asker == nil and I.Here() ~= spot, "...and yours again after")
		check(UI.lastScan == sentinel and ns.db.easyMode == false, "the terminal's own search and mode untouched")
		ns.providers.asktest._dirty = true
		A.Rows("hogger", { name = "Ann" })
		check(seen.here == nil, "an asker with no place known: no place, not yours")
		-- the class trainer filter reads the asker's class
		local meta = ns:CompactMeta({ id = "npc", label = "NPC" }, {}, {})
		local mage = setmetatable({ _compact = true, key = 71001, name = "Jennea", sub = "Mage Trainer" }, meta)
		local war = setmetatable({ _compact = true, key = 71002, name = "Bolar", sub = "Warrior Trainer" }, meta)
		ns.Asker = { class = "MAGE" }
		local f = F.Parse("trainer:class")
		local yes, no = f(mage), f(war)
		ns.Asker = nil
		check(yes == true and no == false, "trainer:class: the asker's class trainers")
		check(A.AnswerLine("help", { name = "Bob" }):find("^Terminal %(Bob%): ") ~= nil, "help: examples, to Bob")
		ns.providers.asktest._dirty = true
		local line = A.AnswerLine("hogger", { name = "Bob" })
		check(type(line) == "string" and line:find("^Terminal %(Bob%): ") and line:find("Hogger", 1, true)
			and #line <= A.LINE_MAX, "the line: who it's for, then what was found: " .. tostring(line))
		check(A.AnswerLine("zzqqxx nothing", { name = "Bob" }) == nil, "nothing found: no line (the client says so)")
	end)
	ns.Asker = nil
	A.ALLOW.asktest = nil
	drop("asktest"); drop("askmine")
	for i = #E.CATEGORIES, catsWere + 1, -1 do E.BY_ID[E.CATEGORIES[i].id] = nil; E.CATEGORIES[i] = nil end
	E.Reindex()
	UI.lastScan, UI.category, ns.db.easyMode = was.scan, was.cat, was.easy
	check(ok, "the answer's search ran: " .. tostring(err))
end

io.write("[ask: .ask]\n")
do
	local run = ns.commands.ask.run
	local had = rawget(ns.db, "ask")
	run("guild on")
	check(A.On("guild") and not A.On("group"), ".ask guild on")
	run("whisper on")
	run("guild off")
	check(not A.On("guild") and A.On("whisper"), ".ask guild off leaves the others")
	run("off")
	check(rawget(ns.db, "ask") == nil, ".ask off: nothing answered, nothing kept")
	local status = table.concat(run(""), "\n")
	check(status:find("guild off", 1, true) and status:find(".ask test", 1, true), ".ask says what's on: " .. status)
	local said = table.concat(run("test n\195\164chster gastwirt"), "\n")
	check(said:find("quiet", 1, true), ".ask test in another language: it'd stay quiet: " .. said)
	local offered = {}
	for _, c in ipairs(ns.commands.ask.complete()) do offered[c[1]] = true end
	check(offered["guild on"] and offered["group off"] and offered["whisper on"] and offered["test"], "Tab offers each switch")
	rawset(ns.db, "ask", had)
end

io.write("[ask: 0.68.5 review: links, ids, limits shared, claims only when able]\n")
do
	local link = "|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
	check(A.Question("!t what drops " .. link) == "what drops Thunderfury, Blessed Blade of the Windseeker",
		"a linked item: read as its name: " .. tostring(A.Question("!t what drops " .. link)))
	local q = A.Question("!t " .. link .. " " .. link)
	check(q and not A.NothingLine(q, { name = "Bob" }):find("|", 1, true), "nothing found: the line never carries half a link")
	-- the same question seen as Bob by one client and Bob-Realm by another: one question (its GUID)
	local net = Net()
	local a = Client(net, "Player-1-00000002", { rand = 0.1 })
	local b = Client(net, "Player-1-00000003", { rand = 0.9 })
	a.inst:OnChat("CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	b.inst:OnChat("CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob-Realm", BOB)
	net.run(5)
	check(#net.said == 1, "one question whatever name each client sees: " .. #net.said)
	-- another Terminal answered Bob: this one waits his turn too
	net = Net()
	a = Client(net, "Player-1-00000002", { rand = 0.1 })
	b = Client(net, "Player-1-00000003", { rand = 0.9 })
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(3)
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Bob", BOB)
	net.run(3)
	check(#net.said == 1 and b.inst.log[1].why == "soon", "one asker: not again soon, whichever Terminal answered: " .. #net.said)
	-- two questions at once from one asker: the second waits
	Say(net, "CHAT_MSG_GUILD", "!t nearest anvil", "Cid", "Player-1-00000C1D")
	Say(net, "CHAT_MSG_GUILD", "!t nearest forge", "Cid", "Player-1-00000C1D")
	net.run(5)
	check(#net.said == 2, "two at once from one asker: one answered: " .. #net.said)
	-- answers a minute in a channel: counted by every Terminal
	net = Net()
	a = Client(net, "Player-1-00000002", { rand = 0.1 })
	b = Client(net, "Player-1-00000003", { rand = 0.9 })
	for i = 1, A.CHANNEL_MAX + 1 do
		Say(net, "CHAT_MSG_GUILD", "!t where is hogger", "Asker" .. i, "Player-1-0000E0" .. i)
		net.run(3)
	end
	check(#net.said == A.CHANNEL_MAX, "at most " .. A.CHANNEL_MAX .. " a minute, whichever Terminal answered: " .. #net.said)
	-- in combat before claiming: it doesn't claim, another answers
	net = Net()
	local first = Client(net, "Player-1-00000002", { rand = 0 })
	local second = Client(net, "Player-1-00000003", { rand = 1 })
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(0.1)
	first.combat = true
	net.run(5)
	check(#net.said == 1 and net.said[1].from == second.guid, "in combat before claiming: another Terminal answers: " .. #net.said)
	-- switched off between hearing and claiming: nothing
	net = Net()
	local c = Client(net, "Player-1-00000001")
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(0.1)
	c.settings.guild = nil
	net.run(5)
	check(#net.said == 0 and c.inst.log[1].why == "off", ".ask guild off meanwhile: not answered")
	-- claims a moment apart, slower than that to arrive: still one answer
	net = Net()
	net.lag = 0.5
	local hi = Client(net, "Player-1-00000009", { rand = 0.1 })
	local lo = Client(net, "Player-1-00000004", { rand = 0.2 })
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].from == lo.guid and hi.asked == 0, "half a second to arrive: one answer: " .. #net.said)
	-- your own question while a list is loading: said so, not "nothing found"
	net = Net()
	local me = Client(net, BOB, { answer = function() return nil, true end })
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	check(me.printed[1] and me.printed[1]:find("loading", 1, true), "your own, still loading: " .. tostring(me.printed[1]))
	-- askers and questions forgotten once past their gaps; the roster looked in only for a question that may be answered
	net = Net()
	c = Client(net, "Player-1-00000001")
	Say(net, "CHAT_MSG_GUILD", "!t nearest innkeeper", "Bob", BOB)
	net.run(5)
	local calls = c.askerCalls
	Say(net, "CHAT_MSG_GUILD", "!t nearest mailbox", "Bob", BOB)
	Say(net, "CHAT_MSG_GUILD", "!t n\195\164chster gastwirt", "Ann", "Player-1-00000A00")
	check(c.askerCalls == calls, "too soon, another language: the asker not looked for")
	net.run(120)
	Say(net, "CHAT_MSG_GUILD", "!t nearest anvil", "Dan", "Player-1-00000DA0")
	check(c.inst.lastAsker.bob == nil and c.inst.lastSame[A.Id(BOB, "nearest innkeeper")] == nil, "old askers and questions forgotten")
end

io.write("[ask: 0.68.5 review: the answer's search, apart from the terminal's]\n")
do
	-- every flag a search clears as it starts is the view's own (else the terminal's was read through it)
	local cleared = {}
	UI._Scan.ResetFlags(setmetatable({}, { __newindex = function(_, k) cleared[#cleared + 1] = k end }))
	local fresh, missing = {}, {}
	for _, k in ipairs(A.FRESH) do fresh[k] = true end
	for _, k in ipairs(cleared) do if not fresh[k] then missing[#missing + 1] = k end end
	check(#cleared > 0 and #missing == 0, "a search's flags read as the answer's own: " .. table.concat(missing, ", "))
	local F = ns.Filters
	F.loading = "the terminal's"
	A.Rows("zzqq nothing", { name = "Bob" })
	check(F.loading == "the terminal's", "the terminal's search waiting on items: still waiting")
	F.loading = nil
	-- an asker whose class isn't known: no class trainer, not yours
	local meta = ns:CompactMeta({ id = "npc", label = "NPC" }, {}, {})
	local mage = setmetatable({ _compact = true, key = 71001, name = "Jennea", sub = "Mage Trainer" }, meta)
	local classWas = _G.UnitClass
	_G.UnitClass = function() return "Mage", "MAGE" end
	ns.Asker = { here = false }
	local ok, yes = pcall(function() return F.Parse("trainer:class")(mage) end)
	ns.Asker = nil
	local _, mine = pcall(function() return F.Parse("trainer:class")(mage) end)
	_G.UnitClass = classWas
	check(ok and not yes and mine == true, "class unknown: not your class's trainer (yours still yours): " .. tostring(yes))
end

io.write("[ask: 0.68.5 review: other addons' hidden messages left at once]\n")
do
	local onAddon, n = A.live.OnAddon, 0
	A.live.OnAddon = function() n = n + 1 end
	A.frame:GetScript("OnEvent")(A.frame, "CHAT_MSG_ADDON", "DBM-Core", "timer", "RAID", "Someone")
	A.frame:GetScript("OnEvent")(A.frame, "CHAT_MSG_ADDON", A.PREFIX, "c:1:x", "GUILD", "Someone")
	A.live.OnAddon = onAddon
	check(n == 1, "only Terminal's own claims read: " .. n)
	-- the guild roster: the whole name test only for members whose name starts the same
	local was = { rawget(_G, "IsInGuild"), rawget(_G, "GetNumGuildMembers"), rawget(_G, "GetGuildRosterInfo"), rawget(_G, "Ambiguate") }
	local amb = 0
	_G.IsInGuild = function() return true end
	_G.GetNumGuildMembers = function() return 300 end
	_G.GetGuildRosterInfo = function(i)
		if i == 300 then return "Bob-Realm", "", 0, 23, "Mage", "Elwynn Forest", "", "", true, 0, "MAGE" end
		return "Member" .. i .. "-Realm", "", 0, 60, "Warrior", "Orgrimmar", "", "", true, 0, "WARRIOR"
	end
	_G.Ambiguate = function(name) amb = amb + 1 return (tostring(name):gsub("%-.*$", "")) end
	local who = A.Asker("Bob-Realm", nil)
	_G.IsInGuild, _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.Ambiguate = was[1], was[2], was[3], was[4]
	check(who and who.level == 23 and who.class == "MAGE", "Bob found in the roster")
	check(amb < 10, "the whole name test for a few members, not all 300: " .. amb)
end

io.write("[ask: 0.68.6, the player's call: never in a battleground's chat]\n")
do
	local net = Net()
	net.bg = true
	local c = Client(net, "Player-1-00000001")
	Say(net, "CHAT_MSG_INSTANCE_CHAT", "!t nearest innkeeper", "Zed", "Player-1-0000ZED0")
	net.run(5)
	check(#net.said == 0 and c.asked == 0 and #c.printed == 0 and c.inst.log[1].why == "battleground",
		"battleground chat: not answered, nothing told: " .. #net.said)
	Say(net, "CHAT_MSG_PARTY", "!t nearest mailbox", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].chat == "PARTY", "your premade party in it: still answered")
	net = Net()
	Client(net, "Player-1-00000001")
	Say(net, "CHAT_MSG_INSTANCE_CHAT", "!t nearest innkeeper", "Bob", BOB)
	net.run(5)
	check(#net.said == 1 and net.said[1].chat == "INSTANCE_CHAT", "a dungeon's instance chat: answered")
end

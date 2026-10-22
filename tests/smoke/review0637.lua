-- The 0.63.7 review's fixes (a pass over the whole codebase: bugs, quality, speed), one block each; every check here
-- failed before its fix.
local T = ...
local ns, UI, check, key, FlushAll = T.ns, T.UI, T.check, T.key, T.FlushAll

io.write("[review 0.63.7: mail]\n")
do
	local MA = ns.Mail
	local save = { guid = _G.UnitGUID, sold = ns.db.auctionsSold, time = _G.time }
	_G.UnitGUID = function() return "Player-1-AAA" end
	local now = 5000000
	local function Sale(player, exp, first)
		return { invoice = { kind = "seller", item = "Copper Bar", player = player, bid = 1000, count = 1 },
			first = first or (exp - 30 * 86400), expires = exp }
	end
	local function Sold() return ns.db.auctionsSold["Player-1-AAA"] end

	-- a sale's mail is its own by when it runs out, not by its buyer nor its place among alike mails
	ns.db.auctionsSold = {}
	local expA, expB = now + 29 * 86400, now + 29 * 86400 + 600
	MA.SalesFromMail({ mails = { Sale("Bob", expA), Sale(nil, expB) } }, now) -- (B's buyer not loaded yet)
	MA.SalesFromMail({ mails = { Sale("Bob", expA) } }, now + 10) -- (B's gold taken)
	check(#Sold() == 2, "two alike sales, one's gold taken: still two: " .. #Sold())
	ns.db.auctionsSold = {}
	local A, B, C = Sale(nil, now + 29 * 86400), Sale(nil, now + 29 * 86400 + 600), Sale(nil, now + 29 * 86400 + 7200)
	MA.SalesFromMail({ mails = { B, A } }, now)
	MA.SalesFromMail({ mails = { B } }, now + 100)
	MA.SalesFromMail({ mails = { C, B } }, now + 7300) -- (a third alike sale's mail, sold while away)
	check(#Sold() == 3, "three alike sales, three kept: " .. #Sold())
	ns.db.auctionsSold = {}
	MA.SalesFromMail({ mails = { Sale("Bob", expA, now - 100) } }, now)
	MA.SalesFromMail({ mails = { Sale(nil, expA, now - 100) } }, now + 60) -- (next login: the buyer not loaded yet)
	check(#Sold() == 1 and Sold()[1].buyer == "Bob", "re-read without its buyer: one sale, the buyer kept: " .. #Sold())

	-- a new mail alike an older one doesn't take the older one's time (an auction's items back a second time)
	local inbox
	local saveIn = { num = _G.GetInboxNumItems, head = _G.GetInboxHeaderInfo, item = _G.GetInboxItem, link = _G.GetInboxItemLink,
		inv = _G.GetInboxInvoiceInfo, del = _G.InboxItemCanDelete, subj = _G.AUCTION_EXPIRED_MAIL_SUBJECT, open = MA.open,
		boxes = ns.db.mailboxes, posted = ns.db.auctionsPosted, ended = ns.db.auctionsEnded }
	local clock = 6000000
	_G.time = function() return clock end
	_G.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
	if MA.ResetSubjectsForTests then MA.ResetSubjectsForTests() end
	ns.db.mailboxes, ns.db.auctionsPosted, ns.db.auctionsEnded = {}, {}, {}
	local function Back(expires) return { exp = expires } end
	_G.GetInboxNumItems = function() return #inbox, #inbox end
	_G.GetInboxHeaderInfo = function(i)
		local m = inbox[i]
		if not m then return nil end
		-- (days left: from when it runs out, as the game counts it down)
		return "pkg", "stat", "Auction House", "Auction expired: Jagged Arrow", 0, 0, (m.exp - clock) / 86400, 1, false, false, true, false, false
	end
	_G.GetInboxItem = function(i, a) if inbox[i] and a == 1 then return "Jagged Arrow", 3030, "icon", 200, 1 end end
	_G.GetInboxItemLink = function(i, a) return inbox[i] and a == 1 and "|cffffffff|Hitem:3030|h[Jagged Arrow]|h|r" or nil end
	_G.GetInboxInvoiceInfo = function() return nil end
	_G.InboxItemCanDelete = function() return true end
	MA.open = true
	local first = Back(clock + 29 * 86400)
	inbox = { first }
	MA.ReadInbox() -- (an auction's arrows back, left in the mailbox)
	clock = clock + 86400
	ns.db.auctionsPosted["Player-1-AAA"] = { [77] = { link = "|cffffffff|Hitem:3030|h[Jagged Arrow]|h|r", name = "Jagged Arrow", count = 200, t = clock } }
	clock = clock + 13 * 3600
	inbox = { Back(clock + 30 * 86400), first } -- (the same arrows posted again, back again)
	MA.ReadInbox()
	local ended = ns.db.auctionsEnded["Player-1-AAA"]
	check(ended and ended[77], "the second auction's arrows came back: it's over")
	_G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxItem, _G.GetInboxItemLink = saveIn.num, saveIn.head, saveIn.item, saveIn.link
	_G.GetInboxInvoiceInfo, _G.InboxItemCanDelete, _G.AUCTION_EXPIRED_MAIL_SUBJECT, MA.open = saveIn.inv, saveIn.del, saveIn.subj, saveIn.open
	ns.db.mailboxes, ns.db.auctionsPosted, ns.db.auctionsEnded = saveIn.boxes, saveIn.posted, saveIn.ended
	if MA.ResetSubjectsForTests then MA.ResetSubjectsForTests() end

	_G.UnitGUID, ns.db.auctionsSold, _G.time = save.guid, save.sold, save.time
end

io.write("[review 0.63.7: Ctrl+R's history search]\n")
do
	local save = { h = ns.db.history, at = ns.db.historyAt, easy = ns.db.easyMode, ctrl = _G.IsControlKeyDown }
	ns.db.history = { "@npc is:repair sort:distance", "thorium belt > mats", "linen cloth", ".mail" }
	ns.db.historyAt = {}
	ns.providers.history._dirty = true
	local function CtrlR()
		_G.IsControlKeyDown = function() return true end
		key("R")
		_G.IsControlKeyDown = save.ctrl
		FlushAll()
	end
	ns.db.easyMode = false; UI:EasyChanged()

	-- closed by the game (not UI:Hide): it ends; the next open searches as usual
	UI:Open("lin"); FlushAll()
	CtrlR()
	UI.frame:Hide(); UI.frame.scripts.OnHide(UI.frame); FlushAll()
	UI:Open("linen"); FlushAll()
	check(not UI.histSearch and UI.Results()[1] and UI.Results()[1].name == "Linen Cloth", "closed by the game: over, the next open searches as usual")
	UI:Hide(); FlushAll()

	-- closed in it: what was typed before it is kept (the last search, the text closed on, a tab's, F1's)
	UI.lastQuery = nil
	UI:Open("lin"); FlushAll()
	CtrlR()
	T.typeText("thor"); FlushAll()
	local st = UI:SaveState()
	check(st.text == "lin", "SaveState in it: what was typed before: " .. tostring(st.text))
	UI:Hide(); FlushAll()
	check(UI.lastQuery == "lin" and UI.closedText and UI.closedText.text == "lin" and UI.closedText.cursor == 3,
		"closed in it: the last search and the text closed on are what was typed: " .. tostring(UI.lastQuery))
	UI.closedText = nil

	-- nothing in it is syntax: no completion, no command colours
	UI:Open(""); FlushAll()
	CtrlR()
	T.typeText(".th"); FlushAll()
	check(UI:Completion() == nil, "\".th\" in it: nothing completed: " .. tostring(UI:Completion()))
	local segs = UI:SyntaxSegments(".th")
	check(#segs == 1, "\".th\" in it: one colour, the text's")
	UI:Hide(); FlushAll()

	-- Tab+` from it: fuzzy finding, the history search over
	UI:Open("lin"); FlushAll()
	CtrlR()
	UI:FuzzyOnce(); FlushAll()
	check(UI.fzf and not UI.histSearch, "Tab+` in it: fuzzy finding alone")
	UI:Hide(); FlushAll()

	-- Enter with nothing matching (the game's text box path too): over, what was typed searched
	UI:Open(""); FlushAll()
	CtrlR()
	T.typeText("zzzz"); FlushAll()
	UI:Activate(); FlushAll()
	check(not UI.histSearch and T.query() == "zzzz", "Enter with nothing matching: over, the text searched")
	UI:Hide(); FlushAll()

	-- Enter searches once
	UI:Open("lin"); FlushAll()
	CtrlR()
	UI:SetQuery("thor", 4); FlushAll()
	local before = UI.refreshCount or 0
	key("ENTER"); FlushAll()
	check((UI.refreshCount or 0) - before == 1 and T.query() == "thorium belt > mats", "Enter: searched once: " .. tostring((UI.refreshCount or 0) - before))
	UI:Hide(); FlushAll()

	-- Esc: the category picked comes back too (Simple mode)
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("linen"); FlushAll()
	local cat
	for i, e in ipairs(UI.Results()) do if e.catId == "items" then cat = i end end
	if cat then UI:SetCategory("items"); FlushAll() end
	CtrlR()
	key("ESCAPE"); FlushAll()
	check(not cat or (UI.category == "items" and T.query() == "linen"), "Esc: the category picked back: " .. tostring(UI.category))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()

	-- a better older match above a newer one
	ns.db.history = { "thorium belt", "thorium bel" }
	ns.providers.history._dirty = true
	local rows = UI:HistorySearch("thor")
	check(rows[1] and rows[1].name == "thorium bel", "the better match first, though older: " .. tostring(rows[1] and rows[1].name))
	local eq = UI:HistorySearch("")
	check(eq[1].name == "thorium belt", "nothing typed: the newest first")

	-- Ctrl+R closes a row menu opened from the keys first
	ns.db.history = { "linen cloth" }
	ns.providers.history._dirty = true
	UI:Open("linen"); FlushAll()
	UI:ShowRowMenu(1, true); FlushAll()
	CtrlR()
	local m = _G.TerminalRowMenu
	check(UI.histSearch and not (m and m:IsShown()), "Ctrl+R: the row menu goes")
	UI.histSearch = nil
	UI:Hide(); FlushAll()

	ns.db.history, ns.db.historyAt, ns.db.easyMode, _G.IsControlKeyDown = save.h, save.at, save.easy, save.ctrl
	UI:EasyChanged()
	ns.providers.history._dirty = true
end

io.write("[review 0.63.7: the drawn prompt's caret back from the game's text box]\n")
do
	local edit = UI.edit
	UI:Open("abc def"); FlushAll()
	UI:EnterEdit()
	local hf, gcp = edit.HasFocus, edit.GetCursorPosition
	edit.HasFocus = function() return true end
	edit.GetCursorPosition = function() return 2 end
	UI:EnterKeys()
	edit.HasFocus, edit.GetCursorPosition = hf, gcp
	check(UI.cursor == 2, "back to the drawn prompt: the caret where the box had it: " .. tostring(UI.cursor))
	UI:Hide(); FlushAll()
end

io.write("[review 0.63.7: \">>\" on Simple mode's category rows]\n")
do
	local saveEasy, saveShow = ns.db.easyMode, ns.ShowText
	ns.db.easyMode = true; UI:EasyChanged()
	local copied
	ns.ShowText = function() copied = true end
	UI:Open("linen >> party"); FlushAll()
	local e = UI.Results()[UI.sel]
	check(e and e.catId, "linen >> party: a category row selected")
	check(UI.SecureView(e, false) == nil, ">> party on a category row: nothing to send pressed")
	local status = UI.status:GetText() or ""
	check(not status:find(ns.L["Enter sends it to %s"]:format(UI.sendTo.label), 1, true), "the footer doesn't say it sends the category: " .. status)
	local cat = e.catId
	UI:Activate(); FlushAll()
	check(UI.category == cat and UI:IsShown(), "Enter on it: the category picked: " .. tostring(UI.category))
	-- in it, the hints say where Enter sends the row (Simple mode as Advanced)
	-- (the key the hints were fitted for: the footer's text in the mock is too wide to leave them room)
	local hints = UI.hintsKey or ""
	check(hints:find(ns.L["send it to %s"]:format(UI.sendTo.label), 1, true), "Simple mode's hints: Enter sends it: " .. hints)
	UI:Hide(); FlushAll()
	UI:Open("linen >> text"); FlushAll()
	UI:Activate(); FlushAll()
	check(not copied, ">> text on a category row: nothing copied")
	UI:Hide(); FlushAll()
	ns.ShowText = saveShow
	ns.db.easyMode = saveEasy; UI:EasyChanged()
end

io.write("[review 0.63.7: Ctrl+R: no bar, nothing to send]\n")
do
	local save = { h = ns.db.history, at = ns.db.historyAt, easy = ns.db.easyMode, ctrl = _G.IsControlKeyDown }
	ns.db.history, ns.db.historyAt = { "linen cloth", "thorium bar" }, {}
	ns.providers.history._dirty = true
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("lin"); FlushAll()
	_G.IsControlKeyDown = function() return true end
	key("R")
	_G.IsControlKeyDown = save.ctrl
	FlushAll()
	check(UI.histSearch and not ns.Bar.On() and ns.Bar.Active() == nil, "Ctrl+R in Simple mode: the bar's away")
	UI:ShowRowMenu(UI.sel, true)
	local m, chat = _G.TerminalRowMenu, {}
	for _, b in ipairs(m.lines) do
		local l = b:IsShown() and b.fs:GetText() or ""
		if l:find("Party", 1, true) or l:find("chat box", 1, true) or l:find("Copy", 1, true) then chat[#chat + 1] = l end
	end
	UI:HideRowMenu()
	check(#chat == 0, "Ctrl+R's row menu: nothing to send or copy: " .. table.concat(chat, ", "))
	UI.histSearch = nil
	UI:Hide(); FlushAll()
	ns.db.history, ns.db.historyAt, ns.db.easyMode = save.h, save.at, save.easy
	UI:EasyChanged()
	ns.providers.history._dirty = true
end

io.write("[review 0.63.7: the options' example in the player's language]\n")
do
	local O = ns.Options
	local set = O.SampleLetters()
	check(set[1] and set[4] and set[5] and set[13] and set[14] and set[15] and not set[2], "its letters worked out from its words")
	check(O.SAMPLE_NAME == ns.L["Heavy Linen Bandage"] and O.SAMPLE_QUERY == ns.L["hvy ban"], "through L[]")
end

io.write("[review 0.63.7: the search engine's small ones]\n")
do
	-- @history matches the lines, not a word every row had
	local save = { h = ns.db.history, at = ns.db.historyAt, easy = ns.db.easyMode }
	ns.db.easyMode = false; UI:EasyChanged()
	ns.db.history, ns.db.historyAt = { "linen cloth", "thorium bar", "3*4 stuff" }, {}
	ns.providers.history._dirty = true
	UI.lastScan = nil
	local r = UI:Search("@history earl")
	check(#r == 0, "@history earl: no line has it: " .. #r)
	-- Ctrl+R: a sum is a line to find, not one to work out
	UI.histSearch = { saved = "", cursor = 0 }
	local rows = UI:Search("3*4")
	UI.histSearch = nil
	check(rows[1] and rows[1].name == "3*4 stuff", "Ctrl+R \"3*4\": the line, no sum on top: " .. tostring(rows[1] and rows[1].name))
	ns.db.history, ns.db.historyAt, ns.db.easyMode = save.h, save.at, save.easy
	UI:EasyChanged()
	ns.providers.history._dirty = true

	-- is:here (where you are), is:tracked change by themselves: never narrowed from the last search
	local Q = C_QuestLog
	local sq = { num = Q.GetNumQuestLogEntries, info = Q.GetInfo, obj = Q.GetQuestObjectives, zone = _G.GetRealZoneText,
		z = _G.GetZoneText, sub = _G.GetSubZoneText, mini = _G.GetMinimapZoneText, map = _G.GetQuestUiMapID }
	local quests = {
		{ title = "Durotar", isHeader = true }, { title = "Raider Peons", questID = 201, level = 4 },
		{ title = "The Barrens", isHeader = true }, { title = "Raptor Thieves", questID = 203, level = 15 },
	}
	Q.GetNumQuestLogEntries = function() return #quests end
	Q.GetInfo = function(i) return quests[i] end
	Q.GetQuestObjectives = function() return {} end
	local zone = "Durotar"
	_G.GetRealZoneText = function() return zone end
	_G.GetZoneText, _G.GetSubZoneText, _G.GetMinimapZoneText = _G.GetRealZoneText, function() return "" end, function() return "" end
	_G.GetQuestUiMapID = function() return 0 end
	ns.db.easyMode = false; UI:EasyChanged()
	ns.providers.quests._dirty = true
	UI.lastScan = nil
	UI:Search("@quest is:here r")
	zone = "The Barrens"
	local after = UI:Search("@quest is:here ra")
	check(after[1] and after[1].name == "Raptor Thieves", "is:here, walked on: the new zone's quests: " .. tostring(after[1] and after[1].name))
	Q.GetNumQuestLogEntries, Q.GetInfo, Q.GetQuestObjectives = sq.num, sq.info, sq.obj
	_G.GetRealZoneText, _G.GetZoneText, _G.GetSubZoneText, _G.GetMinimapZoneText, _G.GetQuestUiMapID = sq.zone, sq.z, sq.sub, sq.mini, sq.map
	ns.providers.quests._dirty = true
	ns.db.easyMode = save.easy; UI:EasyChanged()
	UI.lastScan = nil
end

io.write("[review 0.63.7: \"track quests to turn in\"]\n")
do
	local QK = ns.QuestTrack
	for _, l in ipairs({ "track quests to turn in", "track quests i can turn in", "track turnin quests" }) do
		local q = QK.Question(l)
		check(q and q.complete and #q.words == 0, l .. ": the complete ones, no name: " .. tostring(q and q.words[1]))
	end
end

io.write("[review 0.63.7: in: on quests, by the place's name]\n")
do
	local Q = C_QuestLog
	local sq = { num = Q.GetNumQuestLogEntries, info = Q.GetInfo, obj = Q.GetQuestObjectives, find = ns.Integrations.FindPlace, easy = ns.db.easyMode }
	local quests = {
		{ title = "Ragefire Chasm", isHeader = true }, { title = "Searching for the Lost Satchel", questID = 205, level = 15 },
		{ title = "Thunder Bluff", isHeader = true }, { title = "The Hunter's Way", questID = 210, level = 10 },
		{ title = "Swamp of Sorrows", isHeader = true }, { title = "Swampy", questID = 207, level = 15 },
		{ title = "Stormwind City", isHeader = true }, { title = "Stormy", questID = 208, level = 15 },
	}
	Q.GetNumQuestLogEntries = function() return #quests end
	Q.GetInfo = function(i) return quests[i] end
	Q.GetQuestObjectives = function() return {} end
	ns.providers.quests._dirty = true
	ns.db.easyMode = false; UI:EasyChanged()
	local function Ids(line)
		UI.lastScan = nil
		local t = {}
		for _, e in ipairs(UI:Search(line)) do t[#t + 1] = tostring(e.questID) end
		table.sort(t)
		return table.concat(t, ",")
	end
	for pass = 1, 2 do
		if pass == 2 then
			-- (in the game QuestieDB's zones give Terminal its places: stood in for)
			local SH = { rfc = "Ragefire Chasm", tb = "Thunder Bluff", sw = "Stormwind City" }
			ns.Integrations.FindPlace = function(tokens)
				local name = SH[table.concat(tokens, " ")]
				if name then return { key = name:lower(), name = name, area = 1 }, {} end
			end
		end
		check(Ids("@quest in:rfc") == "205" and Ids("@quest in:tb") == "210" and Ids("@quest in:sw") == "208",
			"in:rfc, in:tb, in:sw (pass " .. pass .. "): " .. Ids("@quest in:rfc") .. " / " .. Ids("@quest in:tb") .. " / " .. Ids("@quest in:sw"))
		check(Ids("@quest in:thunderbluff") == "210", "in:thunderbluff (pass " .. pass .. ")")
	end
	Q.GetNumQuestLogEntries, Q.GetInfo, Q.GetQuestObjectives, ns.Integrations.FindPlace = sq.num, sq.info, sq.obj, sq.find
	ns.providers.quests._dirty = true
	ns.db.easyMode = sq.easy; UI:EasyChanged()
	UI.lastScan = nil
end


io.write("[review 0.63.7: the overview looks a kind's category up once]\n")
do
	local Ez, easy = ns.Easy, ns.db.easyMode
	local real, wasted, asked = Ez.CategoryOf, 0, 0
	Ez.CategoryOf = function(e)
		asked = asked + 1
		if Ez.FixedCategory(e.kind) then wasted = wasted + 1 end
		return real(e)
	end
	ns.db.easyMode = true; UI:EasyChanged()
	UI.lastScan = nil
	UI:Search("a")
	Ez.CategoryOf = real
	ns.db.easyMode = easy; UI:EasyChanged()
	UI.lastScan = nil
	check(wasted == 0, "no row of a kind with one category asked for its category: " .. wasted .. " of " .. asked)
end

io.write("[review 0.63.7: a friend's share read safely]\n")
do
	local SSH = ns.Ssh
	local long = string.rep("a", 47) .. "\195\169\195\169" -- (47 letters, then two é: the 48th byte starts one)
	local d = SSH.Decode("Bob|TInterface\\Icons\\x:64|t\1/b," .. long .. "/k!1:0.3,1.2!!evil")
	check(d.places[1] and d.places[1].who == "BobTInterface\\Icons\\x:64t", "no escapes nor control characters: " .. tostring(d.places[1] and d.places[1].who))
	check(d.places[2] and #d.places[2].who == 47, "a long name cut between two letters: " .. tostring(d.places[2] and #d.places[2].who))
	check(d.mode == nil, "a mode Terminal doesn't know: none")
	check(SSH.Decode("Bob/b!1:0.3!2s!limited").mode == "limited", "a known one: kept")
end

io.write("[review 0.63.7: a town with no centre]\n")
do
	local I, QD = ns.Integrations, ns.QuestieData
	local saveQ, saveL, saveLib = rawget(_G, "Questie"), rawget(_G, "QuestieLoader"), rawget(_G, "LibQuestieDB")
	local function Entity(rows)
		local ids = {}
		for id in pairs(rows) do ids[#ids + 1] = id end
		table.sort(ids)
		return { Get = function(id, field) return rows[id] and rows[id][field] end, GetAllIds = function() return ids end }
	end
	_G.Questie, _G.QuestieLoader = nil, nil
	_G.LibQuestieDB = {
		Quest = Entity({}), Npc = Entity({}),
		Support = { Get = function(name)
			if name ~= "ZoneDB" then return nil end
			return { private = { areaIdToUiMapId = "return { [12] = 1429 }", subZoneToParentZone = "return { [87] = 12 }" } }
		end },
	}
	QD.ResetForTests()
	local cm = _G.C_Map
	_G.C_Map = { GetAreaInfo = function(a) return ({ [12] = "Elwynn Forest", [87] = "Nowhere Town" })[a] end, GetMapInfo = function() return nil end }
	I.ResetPlacesForTests()
	I.qdb.list = {}
	local trace = (ns.Debug and ns.Debug.trace)
	local place = { area = 87, parent = 12, name = "Nowhere Town", key = "nowhere town" }
	local before = trace and #trace or 0
	local lastMsg
	local was = ns.Trace
	local n = 0
	ns.Trace = function(self, m) if tostring(m):find("^places: Nowhere") then n = n + 1 end; lastMsg = m; return was(self, m) end
	for i = 1, 50 do I.RowInPlace({ area = 12, ui = 1429, px = 40, py = 60 }, place) end
	ns.Trace = was
	check(n <= 1, "a town with no centre: worked out once, not per row: " .. n)
	I.qdb.list = nil
	_G.C_Map = cm
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = saveQ, saveL, saveLib
	QD.ResetForTests()
	I.ResetPlacesForTests()
end

io.write("[review 0.63.7: integrations whose data changed shape say so]\n")
do
	local I, AT, WT = ns.Integrations, ns.Attune, ns.WhatsTraining
	local saveFailed = I.failed
	I.failed = {}
	-- What's Training: GetSpells keyed by spell id instead of a list
	local saveApi = _G.WT_API
	_G.WT_API = { version = 1, Status = { AVAILABLE = "available" }, IsReady = function() return true end,
		GetSpells = function() return { [133] = { id = 133, name = "Fireball", status = "available", level = 1 } } end,
		GetSource = function() return nil end }
	WT.ForgetStates()
	local rows = WT.Collect()
	check(I.failed["What's Training"] ~= nil, "What's Training, its spells keyed by id: said it's unavailable")
	-- GetSource giving a quests field that isn't a list
	_G.WT_API.GetSource = function() return { kind = "quest", quests = 7 } end
	local ok, err = pcall(WT.SourceLines, { wtId = 133, name = "x" })
	check(ok, "a source whose quests aren't a list: no error: " .. tostring(err))
	_G.WT_API.GetSource = function() return { kind = "weaponMaster", trainers = { "Bob" } } end
	ok, err = pcall(WT.SourceLines, { wtId = 133, name = "x" })
	check(ok and type(err) == "table" and tostring(err[1]):find("Bob", 1, true) ~= nil, "weapon masters by name alone: named: " .. tostring(ok and err[1]))
	_G.WT_API = saveApi; WT.ForgetStates()
	-- Attune: attunes keyed by id
	local saveD = _G.Attune_Data
	_G.Attune_Data = { attunes = { ["170"] = { ID = "170", NAME = "Deadmines", FACTION = "Both", GROUP = "DUNGEONS" } },
		steps = { { ID_ATTUNE = "170", ID = "1", TYPE = "Quest", ID_WOWHEAD = "65", STAGE = 1 } } }
	AT.Forget()
	local idx = AT.Index()
	check(I.failed.Attune ~= nil, "Attune, its attunements keyed by id: said it's unavailable")
	_G.Attune_Data = saveD; AT.Forget()
	I.failed = saveFailed
end

io.write("[review 0.63.7: Questie's NPCs with no names: said]\n")
do
	local I, QD = ns.Integrations, ns.QuestieData
	local npc = I.npc
	local save = { list = npc.list, busy = npc.busy, names = npc.names, count = npc.count, ready = QD.Ready, db = QD.DB, failed = I.failed }
	npc.list, npc.busy = nil, false
	I.failed = {}
	QD.Ready = function() return true end
	QD.DB = function() return { NpcIds = function() return { 1, 2, 3 } end, QueryNPCSingle = function() return nil end } end
	I._.IndexNPCs(); FlushAll()
	check(I.failed.Questie ~= nil, "NPC ids but no names: @npc said to be unavailable")
	npc.list, npc.busy, npc.names, npc.count = save.list, save.busy, save.names, save.count
	QD.Ready, QD.DB, I.failed = save.ready, save.db, save.failed
end

io.write("[review 0.63.7: the loot log's alike drops and new looters]\n")
do
	local LL = ns.LootLog
	local was, tWas = ns.db.lootLog, _G.time
	ns.db.lootLog = {}
	local fixed = os.time()
	_G.time = function() return fixed end
	local link = "|cff1eff00|Hitem:1234::::::::|h[Green Thing]|h|r"
	LL.Add(link, "Bob", 1, nil, "loot")
	LL.Add(link, "Bob", 1, nil, "loot")
	local p = ns.providers.lootlog
	p._dirty = true
	local rows = ns:GetEntries(p)
	check(#rows == 2 and rows[1].key ~= rows[2].key and rows[2].key == fixed .. ":1234:Bob", "two alike drops in a second: a key each, the older's as before: "
		.. tostring(rows[1] and rows[1].key) .. " / " .. tostring(rows[2] and rows[2].key))
	ns.db.lootLog = {}
	for i = 1, LL.MAX do LL.Add("|cff1eff00|Hitem:" .. (2000 + i) .. "::::::::|h[G" .. i .. "]|h|r", "Bob", 1, nil, "loot") end
	LL.Question("what did bob get")
	LL.Add("|cff1eff00|Hitem:9999::::::::|h[Zed's]|h|r", "Zed", 1, nil, "loot")
	local q = LL.Question("what did zed get")
	check(q and q.who == "Zed", "at the log's cap, a new looter in the same second: known: " .. tostring(q and q.who))
	_G.time = tWas
	ns.db.lootLog = was
	p._dirty = true
end

io.write("[review 0.63.7: a corpse's healers don't keep a freed NPC list]\n")
do
	local C, I = ns.Corpse, ns.Integrations
	local save = { dead = _G.UnitIsDeadOrGhost, DI = _G.C_DeathInfo, here = I.Here, ry = I.RowYards, providers = ns.providers, order = ns.providerOrder }
	_G.UnitIsDeadOrGhost = function() return true end
	_G.C_DeathInfo = { GetCorpseMapPosition = function() return nil end }
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.RowYards = function() return 10 end
	local corpse = ns.providers.corpse
	ns.providers, ns.providerOrder = { corpse = corpse }, { "corpse" }
	ns:RegisterProvider("npc", { label = "NPC", aliases = { "npc" }, explicit = true, idleDrop = 600, collect = function()
		local out = {}
		for i = 1, 2000 do out[i] = { key = i, npcID = i, name = "Npc " .. i } end
		return out
	end })
	local p = ns.providers.npc
	local IS = ns.Filters._.IS
	local real = IS.spirithealer
	IS.spirithealer = function(e) return e.key == 7 end
	local weak = setmetatable({}, { __mode = "v" })
	C.Answer({})
	weak[1] = p._entries
	IS.spirithealer = real
	p._usedAt = -1e9
	ns:DropIdle(GetTime())
	collectgarbage("collect"); collectgarbage("collect")
	check(p._entries == nil and weak[1] == nil, "@npc freed as unused: gone, not held by the corpse's healers")
	_G.UnitIsDeadOrGhost, _G.C_DeathInfo, I.Here, I.RowYards = save.dead, save.DI, save.here, save.ry
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
end

io.write("[review 0.63.7: one addon's options changed: only its read again]\n")
do
	local AO, P = ns.AddonOptions, ns.providers.addonoptions
	local saveLS, saveRoot = _G.LibStub, AO.Root
	local db = { on = false }
	local function Opts(name) return { type = "group", name = name, args = {
		on = { type = "toggle", name = name .. " switch", get = function() return db.on end, set = function(_, v) db.on = v end } } } end
	local callbacks = {}
	local reg = { tables = { Foo = function() return Opts("Foo") end, Bar = function() return Opts("Bar") end } }
	function reg.RegisterCallback(_, event, fn) callbacks[event] = fn end
	function reg.GetOptionsTable(_, app, uiType) local f = reg.tables[app]; if f and uiType then return f(uiType) end return f end
	function reg.NotifyChange(_, app) if callbacks.ConfigTableChange then callbacks.ConfigTableChange("ConfigTableChange", app) end end
	_G.LibStub = function(name) if name == "AceConfigRegistry-3.0" then return reg end end
	AO.watching, AO.perApp, AO.stale = nil, {}, {}
	local read = {}
	AO.Root = function(r, app) read[app] = (read[app] or 0) + 1 return saveRoot(r, app) end
	P._dirty = true
	local row
	for _, e in ipairs(ns:GetEntries(P)) do if e.name == "Foo switch" then row = e end end
	read = {}
	local printWas = ns.Print
	ns.Print = function() end
	if row then AO.Flip(row) end
	ns.Print = printWas
	ns:GetEntries(P)
	check(row and db.on and read.Foo == 1 and not read.Bar, "Foo's switch flipped: Foo read again, not Bar: " .. tostring(read.Foo) .. "/" .. tostring(read.Bar))
	AO.Root, _G.LibStub = saveRoot, saveLS
	AO.watching, AO.perApp, AO.stale = nil, {}, {}
	P._dirty = true
end

io.write("[review 0.63.7: the addon list isn't read on every open]\n")
do
	local save = _G.C_AddOns
	local N = 50
	_G.C_AddOns = setmetatable({ GetNumAddOns = function() return N end,
		GetAddOnInfo = function(i) return "Addon" .. i, "Cool Addon " .. i, "notes " .. i, true, nil end,
		IsAddOnLoaded = function() return true end, GetAddOnEnableState = function() return 2 end }, { __index = save })
	local p = ns.providers.addons
	local collects, real = 0, p.collect
	p.collect = function(...) collects = collects + 1 return real(...) end
	UI:Hide(); FlushAll()
	for _ = 1, 5 do UI:Open("hearth"); FlushAll(); UI:Hide(); FlushAll() end
	check(collects <= 1, "five opens: the addon list read once at most: " .. collects)
	p.collect = real
	_G.C_AddOns = save
	p._dirty = true
end

io.write("[review 0.63.7: \"spellid\" asks the game little per keystroke]\n")
do
	local CS, SI = ns.ClassSpells, ns.SpellIds
	local saveSpells, saveSub = CS.Spells, C_Spell.GetSpellSubtext
	local calls = 0
	C_Spell.GetSpellSubtext = function() calls = calls + 1 return "Rank 1" end
	local cache = {}
	CS.Spells = function(cls)
		if cache[cls] then return cache[cls] end
		local out = {}
		for sp = 1, 30 do
			local ranks = {}
			for r = 1, 4 do ranks[r] = { sp * 100 + r + #cls * 10000, r * 8 } end
			out[sp] = { name = cls:lower() .. " spell " .. sp, ranks = ranks }
		end
		cache[cls] = out
		return out
	end
	if SI.ForgetCandidates then SI.ForgetCandidates() end
	local line, asked = "spellid fireball", 0
	for k = 8, #line do
		local q = SI.Question(line:sub(1, k))
		if q then asked = asked + 1; SI.Answer(q) end
	end
	check(asked > 3 and calls < 20, "typing \"spellid fireball\": few calls to the game: " .. calls .. " over " .. asked .. " keys")
	if SI.ForgetCandidates then SI.ForgetCandidates() end
	CS.Spells, C_Spell.GetSpellSubtext = saveSpells, saveSub
end

io.write("[review 0.63.7: talents by what they do: their words kept]\n")
do
	local TQ = ns.TalentsQ
	local fake, rows = { id = "talents" }, {}
	for c, cls in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
		for t = 1, 3 do for k = 1, 20 do
			rows[#rows + 1] = { name = cls .. " talent " .. t .. "-" .. k, tab = "Tree " .. t, classFile = cls, spellID = c * 1000 + t * 100 + k, tabIndex = t }
		end end
	end
	local saveP, saveGE, saveDesc = ns.providers.talents, ns.GetEntries, ns.Talents and ns.Talents.Desc
	ns.providers.talents = fake
	ns.GetEntries = function(self, p) if p == fake then return rows end return saveGE(self, p) end
	ns.Talents = ns.Talents or {}
	ns.Talents.Desc = function(id) return "Increases the critical strike chance of your Healing Wave spell by " .. id .. "% and reduces its mana cost by 5%." end
	local q = TQ.Question("healing talents")
	if TQ.ForgetWhere then TQ.ForgetWhere() end
	TQ.Answer(q)
	local before = TQ.made or 0
	TQ.Answer(TQ.Question("healing crit talents"))
	check(TQ.made and TQ.made == before, "540 talents, a word more: none of their words made again: " .. tostring(TQ.made and TQ.made - before))
	ns.providers.talents, ns.GetEntries = saveP, saveGE
	if saveDesc then ns.Talents.Desc = saveDesc end
end

io.write("[review 0.63.7: a quest reward's name typed on: looked for among the last matches]\n")
do
	local QR = ns.QuestRewards
	local reads = 0
	local idx = {}
	local meta = { __index = function(t, k) if k == "m" then reads = reads + 1 return rawget(t, "_m") end end }
	for i = 1, 3000 do
		local n = (i % 10 == 0 and "linen " or "wool ") .. "thing " .. i
		idx[i] = setmetatable({ _m = n, ln = n, name = n, id = i, quests = { i } }, meta)
	end
	local real, saveQ = QR.Index, ns.Integrations.qdb
	QR.Index = function() return idx end
	ns.Integrations.qdb = { list = {} }
	QR.lastKey, QR.lastPool = nil, nil
	QR.Question("quests lin")
	reads = 0
	QR.Question("quests line")
	check(reads > 0 and reads <= 700, "\"lin\" typed on to \"line\": only the last matches looked at: " .. reads)
	local q = QR.Question("quests linen thi")
	check(q and #q.items == 300, "and the same found: " .. tostring(q and #q.items))
	QR.Index, ns.Integrations.qdb = real, saveQ
	QR.lastKey, QR.lastItems, QR.lastPool = nil, nil, nil
end

io.write("[review 0.63.7: pointing at a window's text; the first keys bound after a fight]\n")
do
	local Obj = T.Obj
	local function FS(text)
		return { GetObjectType = function() return "FontString" end, GetText = function() return text end }
	end
	local function Btn(text)
		local b = Obj("Button"); b.shown = true; b.label = text
		local fs = FS(text)
		b.GetRegions = function() return fs end
		return b
	end
	local root = Obj("Frame"); root.shown = true
	root.GetRegions = function() return FS("Healing spells") end
	local a, b = Btn("Flash Heal"), Btn("Heal")
	root.GetChildren = function() return a, b end
	check(ns.FindByText(root, "Heal") == b, "\"Heal\": the Heal button, not Flash Heal's nor the window's title")
	check(ns.FindByText(root, "Flash") == a, "a part of one's text: still found")
	check(ns.FindByText(root, "spells") == root, "only the window says it: the window")

	local ef = T.ef
	local saved = { InCombatLockdown, SetBinding, GetBindingKey, GetBindingAction, SaveBindings, ns.db.bindingTerminal, ns.db.bindingAdvancedOnce, ns.Print }
	local calls, combat = {}, true
	_G.InCombatLockdown = function() return combat end
	_G.GetBindingKey = function() return nil end
	_G.GetBindingAction = function() return "" end
	_G.SetBinding = function(k, act) if combat then return false end calls[#calls + 1] = k .. "=" .. act; return true end
	_G.SaveBindings = function() end
	ns.Print = function() end
	ns.db.bindingTerminal, ns.db.bindingAdvancedOnce = nil, nil
	local made, cf = {}, _G.CreateFrame
	_G.CreateFrame = function(...) local f = cf(...); made[#made + 1] = f; return f end
	ef.scripts.OnEvent(ef, "PLAYER_LOGIN")
	_G.CreateFrame = cf
	check(#calls == 0 and not ns.db.bindingTerminal, "logged in in combat: nothing bound yet, the first run still to do")
	combat = false
	for _, f in ipairs(made) do
		if f.scripts and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED") end
	end
	check(calls[1] == "`=TERMINAL_TOGGLE" and ns.db.bindingTerminal, "out of combat: ` bound: " .. table.concat(calls, ", "))
	_G.InCombatLockdown, _G.SetBinding, _G.GetBindingKey, _G.GetBindingAction, _G.SaveBindings = saved[1], saved[2], saved[3], saved[4], saved[5]
	ns.db.bindingTerminal, ns.db.bindingAdvancedOnce, ns.Print = saved[6], saved[7], saved[8]
end

io.write("[review 0.63.7: a line read once for every question]\n")
do
	local real, n = ns.Lower, 0
	ns.Lower = function(...) n = n + 1 return real(...) end
	local a = ns.QuestionText("where is the nearest innkeeper zzq")
	local b = ns.QuestionText("where is the nearest innkeeper zzq")
	local c = ns.QuestionText("where is the nearest innkeeper zzq", { zzq = true })
	ns.Lower = real
	check(a == "where is the nearest innkeeper zzq" and a == b and b == c and n == 2, "asked again of the same line: read once (per allow list): " .. n)
	check(ns.QuestionText("@item x") == nil and ns.QuestionText("@item x") == nil, "a line refused: refused again")
end

io.write("[review 0.63.7: an older Questie's database: found at once]\n")
do
	local QD = ns.QuestieData
	local savedQ, savedL, savedLib = rawget(_G, "Questie"), rawget(_G, "QuestieLoader"), rawget(_G, "LibQuestieDB")
	local calls = 0
	local M = { QueryQuestSingle = function() end, QueryNPCSingle = function() end, QuestPointers = {}, NPCPointers = {} }
	_G.LibQuestieDB = nil
	_G.Questie = { API = { isReady = true } }
	_G.QuestieLoader = { ImportModule = function(_, n) calls = calls + 1; if n == "QuestieDB" then return M end end }
	QD.ResetForTests()
	local first = QD.DB()
	calls = 0
	for _ = 1, 100 do QD.DB() end
	check(first and first.QueryNPCSingle == M.QueryNPCSingle and calls == 0, "asked again: no module looked up: " .. calls)
	_G.Questie, _G.QuestieLoader, _G.LibQuestieDB = savedQ, savedL, savedLib
	QD.ResetForTests()
end

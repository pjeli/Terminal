-- Your mail (Mail.lua, 0.46.3): @mail / @inbox, kept by Terminal every time a mailbox shows: who sent it, gold, COD, what's
-- attached, when it runs out (deleted, or sent back); "my mail", "mail running out"; the login warning.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[mail]\n")
do
	local MA, P = ns.Mail, ns.providers.mail
	local save = { guid = _G.UnitGUID, cls = _G.UnitClass, realm = _G.GetRealmName, time = _G.time, boxes = ns.db.mailboxes,
		warn = ns.db.mailWarn, out = ns.Output, print = ns.Print, easy = ns.db.easyMode, n = _G.GetInboxNumItems,
		head = _G.GetInboxHeaderInfo, item = _G.GetInboxItem, ilink = _G.GetInboxItemLink, inv = _G.GetInboxInvoiceInfo,
		del = _G.InboxItemCanDelete, text = _G.GetInboxText, new = _G.HasNewMail, senders = _G.GetLatestThreeSenders,
		sold = _G.AUCTION_SOLD_MAIL_SUBJECT, inbox = _G.InboxFrame, hl = ns.Highlight.Show, open = MA.open, cname = ns.CharacterName,
		warned = MA.warned }
	check(P and ns:ResolveProvider("mail") == P and ns:ResolveProvider("inbox") == P, "@mail and @inbox are your mail")
	local box = ns.providers.mailbox
	check(not box or (ns:ResolveProvider("mailbox") == box and ns:ResolveProvider("mailb") == box), "@mailbox is still the mailboxes")
	local DAY = 86400
	local now = 5000000
	_G.time = function() return now end
	_G.UnitGUID = function() return "Player-1-AAA" end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.GetRealmName = function() return "Forever" end
	ns.CharacterName = function() return "Plamen Warr" end
	_G.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
	MA.ResetSubjectsForTests()
	ns.db.mailboxes, ns.db.mailWarn = {}, nil
	ns.db.easyMode = false
	MA.open = false

	-- the inbox: Bob's gold (6 days), an auction sale (2 days, deleted, gold), a COD from Ann (12 h, items), one sent back
	local inbox = {
		{ "Bob", "Here you go", 500000, 0, 6, 0, true, false, true },
		{ "Stormwind Auction House", "Auction successful: Copper Bar", 450000, 0, 2, 0, false, false, true,
			invoice = { "seller", "Copper Bar", "Zed", 460000, 460000, 1000, 11000, 0, 0, 0, 20 } },
		{ "Ann", "Linen for you", 0, 30000, 0.5, 2, false, false, false,
			items = { { "Linen Cloth", 2589, 1, 20, 1 }, { "Wool Cloth", 2592, 2, 5, 1 } } },
		{ "Cid", "Your boots", 0, 0, 20, 1, true, true, false, items = { { "Cracked Leather Boots", 2385, 3, 1, 0 } } },
	}
	local textCalls = 0
	_G.GetInboxText = function() textCalls = textCalls + 1 end -- (marks a mail read: never called)
	_G.GetInboxNumItems = function() return #inbox, #inbox + 3 end
	_G.GetInboxHeaderInfo = function(i)
		local m = inbox[i]
		if not m then return nil end
		local first = m.items and m.items[1]
		return "pkg", "stat", m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], nil, true, false, first and first[4], nil
	end
	_G.GetInboxItem = function(i, a)
		local it = inbox[i] and inbox[i].items and inbox[i].items[a]
		if not it then return nil end
		return it[1], it[2], it[3], it[4], it[5], true
	end
	_G.GetInboxItemLink = function(i, a)
		local it = inbox[i] and inbox[i].items and inbox[i].items[a]
		return it and ("|cffffffff|Hitem:" .. it[2] .. "|h[" .. it[1] .. "]|h|r") or nil
	end
	_G.GetInboxInvoiceInfo = function(i)
		local v = inbox[i] and inbox[i].invoice
		if v then return unpack(v) end
		return nil
	end
	_G.InboxItemCanDelete = function(i) return inbox[i] and inbox[i][9] or false end
	_G.HasNewMail = function() return false end

	-- read only while a mailbox shows (elsewhere the game may say nothing, and the note would lose every mail)
	MA.OnEvent("MAIL_INBOX_UPDATE")
	FlushAll()
	check(next(ns.db.mailboxes) == nil, "no mailbox open: the inbox isn't read")
	MA.OnEvent("MAIL_SHOW")
	MA.OnEvent("MAIL_INBOX_UPDATE")
	MA.OnEvent("MAIL_INBOX_UPDATE") -- (a burst: read once)
	FlushAll()
	local note = ns.db.mailboxes["Player-1-AAA"]
	check(note and #note.mails == 4 and note.name == "Plamen Warr" and note.more == 3, "the inbox kept as your note, 3 more on the server: "
		.. tostring(note and #note.mails))
	check(textCalls == 0, "a mail's text is never read (that marks it read)")
	local sale = note.mails[2]
	check(sale.auction == "sold" and sale.invoice and sale.invoice.bid == 460000 and sale.deletes and sale.expires == now + 2 * DAY,
		"the sale: an auction, its invoice, deleted when it runs out, in 2 days")
	check(note.mails[4].returned and not note.mails[4].deletes and note.mails[3].cod == 30000 and #note.mails[3].items == 2,
		"sent back, COD and attachments kept")
	check(MA.AuctionSubject("Auction successful: Copper Bar") == "sold" and MA.AuctionSubject("Linen for you") == nil,
		"the auction house's subjects, from the game's own strings")

	-- the rows: your mailbox, then what runs out first
	P._dirty = true
	local res = UI:Search("@mail")
	check(res[1] and res[1].mailKind == "box" and res[1].who == "Plamen Warr" and res[1].detail:find("4 mails", 1, true)
		and res[1].detail:find("+3 on the server", 1, true), "your mailbox first: " .. tostring(res[1] and res[1].detail))
	check(res[2] and res[2].name == "Linen for you" and res[2].detail:find("from Ann", 1, true) and res[2].detail:find("COD", 1, true)
		and res[2].detail:find("2 items", 1, true) and res[2].detail:find("12 h left", 1, true),
		"the mail running out first next: " .. tostring(res[2] and res[2].detail))
	check(res[3] and res[3].name == "Auction successful: Copper Bar" and res[3].detail:find("2 days left", 1, true), "then the sale")
	local tip = {}
	local fake = { SetText = function(_, s) tip[#tip + 1] = s end, AddLine = function(_, s) tip[#tip + 1] = s end,
		AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. " = " .. tostring(b) end }
	res[3].tooltip(res[3], fake)
	local tipText = table.concat(tip, "\n")
	check(tipText:find("Sold Copper Bar x20 to Zed: 45g", 1, true) and tipText:find("then it's deleted with what's in it", 1, true),
		"the sale's tooltip: what came in (bid + deposit - cut) and what running out does:\n" .. tipText)
	local boots
	for _, e in ipairs(res) do if e.name == "Your boots" then boots = e end end
	tip = {}
	boots.tooltip(boots, fake)
	check(table.concat(tip, "\n"):find("goes back to Cid", 1, true), "a player's mail goes back to its sender")
	check(#UI:Search("@mail is:cod") == 1 and #UI:Search("@mail is:returned") == 1 and #UI:Search("@mail is:auction") == 1
		and #UI:Search("@mail is:money") == 2 and #UI:Search("@mail is:unread") == 2 and #UI:Search("@mail is:expiring") == 2,
		"is:cod / returned / auction / money / unread / expiring")
	check(#UI:Search("@mail linen cloth") >= 1 and UI:Search("@mail wool")[1].name == "Linen for you", "found by what's attached")
	check(#UI:Search("linen for you") == 0, "only with @mail (every mail of every character)")

	-- an alt's mailbox, as it was: mail that ran out since is left out (counted)
	ns.db.mailboxes["Player-1-BBB"] = { name = "Alt Pally", realm = "Forever", class = "PALADIN", t = now - 10 * DAY, mails = {
		{ from = "Dee", subject = "Old", expires = now - DAY, money = 100 },
		{ from = "Eve", subject = "Gold for you", expires = now + 1.5 * DAY, money = 20000, deletes = true },
	} }
	P._dirty = true
	res = UI:Search("@mail")
	local alt, altMail
	for _, e in ipairs(res) do
		if e.mailKind == "box" and e.who == "Alt Pally" then alt = e end
		if e.name == "Gold for you" then altMail = e end
	end
	check(res[1].mine and alt and alt.gone == 1 and alt.detail:find("1 mail", 1, true), "your box first; the alt's, its run-out mail counted")
	local oldOne
	for _, e in ipairs(res) do if e.name == "Old" then oldOne = e end end
	check(altMail and altMail.detail:find("Alt Pally", 1, true) and not oldOne, "an alt's mail says whose; run-out mail is gone")
	check(#UI:Search("@mail on:pally") == 2 and #UI:Search("@mail on:me") >= 5, "on: picks a character's mail")

	-- the question
	local Q = MA.Question
	check(Q("my mail") and Q("whats in my mail") and Q("inbox") and Q("check mailbox") and Q("mail running out").soon
		and Q("cod mail").cod and Q("gold in my mail").money and Q("unread mail").unread, "ways to ask")
	local q = Q("mail from bob")
	check(q and q.words[1] == "bob", "mail from bob: narrowed by the sender")
	check(Q("mail gloves") == nil and Q("my mail gloves") == nil and Q("mailbox") == nil and Q("nearest mailbox") == nil
		and Q("mailbox in ratchet") == nil and Q("@mail") == nil and Q("mail") == nil, "other searches stay searches")
	local rows, said = MA.Answer(Q("my mail"))
	check(rows[1].mailKind == "box" and rows[2].mailKind == "box" and said:find("Your mail", 1, true) and said:find("5 mails", 1, true),
		"my mail: the mailboxes, then the mail: " .. tostring(said))
	rows, said = MA.Answer(Q("mail running out"))
	check(#rows == 3 and rows[1].name == "Linen for you" and said:find("within 3 days", 1, true), "running out: within 3 days, soonest first")
	rows = MA.Answer(Q("mail from bob"))
	check(#rows == 1 and rows[1].name == "Here you go", "mail from bob: Bob's")
	res = UI:Search("cod mail")
	check(#res == 1 and res[1].name == "Linen for you" and UI.answerNote, "asked in the prompt: answered, with a note")
	check(ns.Easy.QuestionToAdvanced("mail running out") == "@mail is:expiring " and ns.Easy.QuestionToAdvanced("mail from bob")
		== "@mail bob ", "Alt+` writes it as @mail")
	check(table.concat({ ns.Easy.Verbs(res[1]) }, "/") == "show in chat/nearest mailbox" or not ns.providers.mailbox,
		"verbs: in chat, the nearest mailbox")

	-- Enter at the open mailbox: your own mail pointed at in the inbox, or its page said
	local lit, printed
	ns.Highlight.Show = function(_, f) lit = f end
	ns.Print = function(_, s) printed = s end
	_G.MailItem3Button = { name = "MailItem3Button" }
	_G.InboxFrame = { pageNum = 1 }
	local linen = UI:Search("@mail linen for you")[1]
	check(table.concat({ ns.Easy.Verbs(linen) }, "/"):find("^show in inbox"), "at the mailbox: show in inbox")
	linen.activate(linen)
	check(lit == _G.MailItem3Button, "at the mailbox: the mail's row in the inbox pointed at")
	_G.InboxFrame.pageNum = 2
	lit = nil
	linen.activate(linen)
	check(not lit and printed and printed:find("page 1", 1, true), "on another page: the page said: " .. tostring(printed))
	local said2
	ns.Output = function(_, l) said2 = l end
	altMail.activate(altMail)
	check(said2 and said2[1]:find("Gold for you", 1, true) and said2[1]:find("Alt Pally", 1, true), "an alt's mail: in chat")
	-- an alt's mail just like one in your inbox: still in chat (the open inbox is yours)
	local altBox = ns.db.mailboxes["Player-1-BBB"]
	altBox.mails[3] = { from = "Bob", subject = "Here you go", money = 500000, expires = now + 6 * DAY, read = true }
	P._dirty = true
	local copy
	for _, e in ipairs(UI:Search("@mail here you go")) do if e.who == "Alt Pally" then copy = e end end
	_G.InboxFrame.pageNum, lit, said2 = 1, nil, nil
	_G.MailItem1Button = { name = "MailItem1Button" }
	copy.activate(copy)
	check(not lit and said2 and said2[1]:find("Here you go", 1, true), "an alt's copy of a mail in your inbox: in chat, not pointed at")
	altBox.mails[3] = nil
	_G.MailItem1Button = nil
	P._dirty = true
	local kept = inbox
	MA.OnEvent("MAIL_INBOX_UPDATE") -- (an update just before the mailbox closes: read only if it still shows)
	MA.OnEvent("MAIL_CLOSED")
	check(not MA.open, "the mailbox closed")
	inbox = {} -- (the game may say nothing once it's closed)
	FlushAll()
	check(#ns.db.mailboxes["Player-1-AAA"].mails == 4, "closed before the read: the note isn't overwritten")
	MA.OnEvent("MAIL_INBOX_UPDATE")
	FlushAll()
	check(#ns.db.mailboxes["Player-1-AAA"].mails == 4, "closed: the note isn't overwritten")
	inbox = kept

	-- the login warning: gold and items in mail running out soon, per character
	local lines = MA.Warnings(now)
	local w = table.concat(lines or {}, "\n")
	local G = ns.Gold.Text
	check(lines and w:find("Plamen Warr (you): " .. G(450000) .. " and 2 items in 2 mails, the first in 12 h (back to Ann)", 1, true)
		and w:find("Alt Pally: " .. G(20000) .. " in 1 mail, the first in 1 day (deleted)", 1, true), "the warning:\n" .. w)
	check(MA.Warnings(now + 30 * DAY) == nil, "nothing running out: no warning")
	local warnings = 0
	ns.Output = function(_, l) said2 = l; warnings = warnings + 1 end
	said2 = nil
	MA.warned = nil
	MA.OnEvent("PLAYER_ENTERING_WORLD", false, true) -- (a /reload: no warning)
	FlushAll()
	check(said2 == nil, "a /reload: no warning")
	MA.OnEvent("PLAYER_ENTERING_WORLD", true, false)
	MA.OnEvent("PLAYER_ENTERING_WORLD", true, false)
	FlushAll()
	check(said2 and said2[1]:find("Mail running out", 1, true) and warnings == 1, "at login: the warning, once: " .. warnings)
	check(ns:FindCommand("mail").run("warn off")[1]:find("no login warning", 1, true) and ns.db.mailWarn == false and MA.Warn() == false,
		".mail warn off")
	ns:FindCommand("mail").run("warn on")
	local all = ns:FindCommand("mail").run("")
	check(all[1] == "Mail:" and table.concat(all, "\n"):find("From Ann: Linen for you", 1, true), ".mail lists every mailbox")
	check(ns:FindCommand("mail").run("forget alt pally")[1]:find("Forgot", 1, true) and ns.db.mailboxes["Player-1-BBB"] == nil,
		".mail forget <name>")

	-- new mail the game says is waiting, before any mailbox was opened on this character
	ns.db.mailboxes = {}
	_G.HasNewMail = function() return true end
	_G.GetLatestThreeSenders = function() return "Bob", "Ann" end
	P._dirty = true
	res = UI:Search("@mail")
	check(#res == 1 and res[1].detail:find("new mail", 1, true) and res[1].newFrom == "Bob, Ann", "new mail waiting: said, with whom from")
	rows, said = MA.Answer(Q("my mail"))
	check(#rows == 1 and said, "my mail with only new mail: the mailbox row")
	_G.HasNewMail = function() return false end
	P._dirty = true
	rows, said = MA.Answer(Q("my mail"))
	check(#rows == 0 and said == MA.NONE, "nothing kept yet: says how it comes")

	_G.UnitGUID, _G.UnitClass, _G.GetRealmName, _G.time = save.guid, save.cls, save.realm, save.time
	ns.db.mailboxes, ns.db.mailWarn, ns.Output, ns.Print, ns.db.easyMode = save.boxes, save.warn, save.out, save.print, save.easy
	_G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxItem, _G.GetInboxItemLink = save.n, save.head, save.item, save.ilink
	_G.GetInboxInvoiceInfo, _G.InboxItemCanDelete, _G.GetInboxText, _G.HasNewMail = save.inv, save.del, save.text, save.new
	_G.GetLatestThreeSenders, _G.AUCTION_SOLD_MAIL_SUBJECT, _G.InboxFrame = save.senders, save.sold, save.inbox
	ns.Highlight.Show, MA.open, ns.CharacterName, MA.warned = save.hl, save.open, save.cname, save.warned
	_G.MailItem3Button = nil
	MA.ResetSubjectsForTests()
	P._dirty = true
end

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
		return "pkg", "stat", m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], nil, m.noReply ~= true, false, first and first[4], nil
	end
	local itemCalls = 0
	_G.GetInboxItem = function(i, a)
		itemCalls = itemCalls + 1
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
	check(itemCalls == 3, "attachments asked for until all are found (2 + 1), not all 16 slots of each: " .. itemCalls)
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
	-- (0.47.0 review) the armour: "mail" with words besides needs a cue only mail has, or "from" before the other words
	check(Q("mail boots from wailing caverns") == nil and Q("new mail gloves") == nil and Q("mail armor sold by vendors") == nil,
		"mail armour searches stay searches")
	check(Q("new mail") and Q("new mail").unread and Q("my mail from bob") and Q("mail from bob") and Q("mailbox from bob")
		and Q("unread mail from bob") and Q("cod mail gloves").cod, "still asked: new mail, mail from bob, unread / cod mail with words")
	local rows, said = MA.Answer(Q("my mail"))
	check(rows[1].mailKind == "box" and rows[2].mailKind == "box" and said:find("Your mail", 1, true) and said:find("5 mails", 1, true),
		"my mail: the mailboxes, then the mail: " .. tostring(said))
	rows, said = MA.Answer(Q("mail running out"))
	check(#rows == 3 and rows[1].name == "Linen for you" and said:find("within 3 days", 1, true), "running out: within 3 days, soonest first")
	rows = MA.Answer(Q("mail from bob"))
	check(#rows == 1 and rows[1].name == "Here you go", "mail from bob: Bob's")
	res = UI:Search("cod mail")
	check(#res == 1 and res[1].name == "Linen for you" and UI.answerNote, "asked in the prompt: answered, with a note")
	-- (0.55.7: "mail from bob" lists the auction house's news too, which @mail doesn't: kept as said, and still answered)
	check(ns.Easy.QuestionToAdvanced("mail running out") == "@mail is:expiring " and ns.Easy.QuestionToAdvanced("mail from bob")
		== "mail from bob ", "Alt+` writes it as @mail, or as said: " .. tostring(ns.Easy.QuestionToAdvanced("mail from bob")))
	check(T.SameAsAdvanced("mail running out"))
	check(T.SameAsAdvanced("mail from bob"))
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

	-- mail you send to one of your own characters: in its list at once, contents and all (the player's report on 0.46.3:
	-- mail from Warr to Pally showed only "new mail from Plamen Warr" on Pally, its contents unknown)
	local xpWas = ns.db.xpChars
	ns.db.xpChars = { ["Player-1-CCC"] = { name = "Plamen Pally", realm = "Forever", class = "PALADIN", level = 20 },
		["Player-1-AAA"] = { name = "Plamen Warr", realm = "Forever", class = "WARRIOR", level = 23 } }
	local attached = { [1] = { "Linen Cloth", 2589, 1, 20, 1 }, [3] = { "Copper Bar", 2840, 2, 10, 1 } }
	local sendWas = { has = _G.HasSendMailItem, get = _G.GetSendMailItem, link = _G.GetSendMailItemLink,
		money = _G.GetSendMailMoney, cod = _G.GetSendMailCOD, send = _G.SendMail, hook = _G.hooksecurefunc, hooked = MA.hooked }
	_G.HasSendMailItem = function(a) return attached[a] ~= nil end
	_G.GetSendMailItem = function(a) local it = attached[a] if it then return it[1], it[2], it[3], it[4], it[5] end end
	_G.GetSendMailItemLink = function(a) local it = attached[a] return it and ("|Hitem:" .. it[2] .. "|h[" .. it[1] .. "]|h") or nil end
	local sendMoney, sendCod = 10000, 0
	_G.GetSendMailMoney = function() return sendMoney end
	_G.GetSendMailCOD = function() return sendCod end
	-- the game's own SendMail, hooked after it runs
	local sent = 0
	_G.SendMail = function() sent = sent + 1 end
	_G.hooksecurefunc = function(name, fn)
		local orig = _G[name]
		_G[name] = function(...) orig(...); fn(...) end
	end
	MA.hooked = nil
	check(MA.HookSend() and MA.HookSend(), "SendMail hooked, once")
	check(MA.OwnKey("Plamen Pally") == "Player-1-CCC" and MA.OwnKey("plamen pally-Forever") == "Player-1-CCC" and MA.OwnKey("Bob") == nil
		and MA.OwnKey("Plamen Warr") == nil, "your characters by name (with or without the realm); not you, not others")
	local onSendWas, onSends = MA.OnSend, 0
	MA.OnSend = function(...) onSends = onSends + 1; return onSendWas(...) end
	_G.SendMail("Plamen Pally", "", "")
	MA.OnSend = onSendWas
	check(sent == 1 and onSends == 1, "the game's send still runs; Terminal notes it once: " .. onSends)
	check(next(ns.db.mailboxes) == nil, "nothing kept before the game says it went")
	MA.OnEvent("MAIL_SEND_SUCCESS")
	local pally = ns.db.mailboxes["Player-1-CCC"]
	local m = pally and pally.mails[1]
	check(m and m.from == "Plamen Warr" and m.subject == "Linen Cloth (20)" and m.money == 10000 and #m.items == 2 and m.sent == now
		and m.expires == now + 30 * DAY and not m.deletes and pally.t == nil,
		"sent to Pally: its list has it, from you, titled after the first item, gold and both items, 30 days")
	P._dirty = true
	res = UI:Search("@mail pally")
	local box2, row2
	for _, e in ipairs(res) do if e.mailKind == "box" then box2 = e elseif e.mailKind == "mail" then row2 = e end end
	check(box2 and box2.detail:find("no mailbox opened with Terminal yet", 1, true) and row2 and row2.detail:find("you sent it", 1, true)
		and row2.detail:find("2 items", 1, true), "Pally's mailbox and the mail sent: " .. tostring(row2 and row2.detail))
	-- COD: 3 days; a failed send isn't kept; mail to someone else isn't kept
	sendMoney, sendCod = 0, 5000
	MA.OnSend("Plamen Pally", "Pay up")
	MA.OnEvent("MAIL_SEND_SUCCESS")
	check(pally.mails[1].subject == "Pay up" and pally.mails[1].cod == 5000 and pally.mails[1].expires == now + 3 * DAY, "COD mail: 3 days")
	MA.OnSend("Plamen Pally", "Lost")
	MA.OnEvent("MAIL_FAILED")
	MA.OnEvent("MAIL_SEND_SUCCESS")
	local traceWas, traced = ns.Trace, {}
	ns.Trace = function(self, t) traced[#traced + 1] = t; return traceWas(self, t) end
	MA.OnSend("Bob", "For Bob")
	MA.OnEvent("MAIL_SEND_SUCCESS")
	ns.Trace = traceWas
	check(traced[#traced] == "mail: sent to Bob (not one of your characters): kept an hour as on its way", "mail to someone else: kept an hour (traced)")
	check(#pally.mails == 2 and ns.db.mailboxes["Player-1-BBB"] == nil, "a failed send isn't kept; mail to others isn't in a mailbox")
	-- Pally opens a mailbox: the real inbox replaces what was sent
	_G.UnitGUID = function() return "Player-1-CCC" end
	ns.CharacterName = function() return "Plamen Pally" end
	inbox = { { "Plamen Warr", "Linen Cloth (20)", 10000, 0, 30, 2, false, false, false, items = { { "Linen Cloth", 2589, 1, 20, 1 } } } }
	MA.OnEvent("MAIL_SHOW")
	MA.OnEvent("MAIL_INBOX_UPDATE")
	FlushAll()
	MA.OnEvent("MAIL_CLOSED")
	check(#ns.db.mailboxes["Player-1-CCC"].mails == 1 and not ns.db.mailboxes["Player-1-CCC"].mails[1].sent
		and ns.db.mailboxes["Player-1-CCC"].t == now,
		"Pally's mailbox read: the inbox as it is replaces the sent copies")
	-- 0.47.2 (the player's ask): mail to anyone not one of your characters is kept an hour (what mail with items or gold
	-- takes between accounts), and the auction house's news (sold, won, outbid, expired), a sale with its price
	_G.UnitGUID = function() return "Player-1-AAA" end
	ns.CharacterName = function() return "Plamen Warr" end
	-- 0.47.5 (the player: mail to "Cai Te" not kept, no trace): gold or items to someone not your own wait on the game's
	-- confirmation (SECURE_TRANSFER_CONFIRM_SEND_MAIL); a MAIL_FAILED before or after it doesn't drop the send
	MA.OnSend("Cai Te", "Gift")
	MA.OnEvent("MAIL_FAILED")
	MA.OnEvent("SECURE_TRANSFER_CONFIRM_SEND_MAIL")
	now = now + 30
	MA.OnEvent("MAIL_SEND_SUCCESS")
	local cai = ns.db.mailSent and ns.db.mailSent["Player-1-AAA"] and ns.db.mailSent["Player-1-AAA"][1]
	check(cai and cai.to == "Cai Te" and cai.mail.subject == "Gift", "confirmed after MAIL_FAILED, sent 30 s later: kept")
	MA.OnSend("Cai Te", "Second")
	MA.OnEvent("SECURE_TRANSFER_CONFIRM_SEND_MAIL")
	MA.OnEvent("MAIL_FAILED")
	now = now + 100
	MA.OnEvent("MAIL_SEND_SUCCESS")
	check(ns.db.mailSent["Player-1-AAA"][1].mail.subject == "Second", "confirm, MAIL_FAILED, then sent 100 s later: kept")
	-- 0.47.6 (the player's log: an item to Cai Te went through 101 s after SendMail, no confirmation, no failure)
	MA.OnSend("Cai Te", "Slow")
	now = now + 101
	MA.OnEvent("MAIL_SEND_SUCCESS")
	check(ns.db.mailSent["Player-1-AAA"][1].mail.subject == "Slow", "sent 101 s after SendMail: kept")
	table.remove(ns.db.mailSent["Player-1-AAA"], 1)
	now = now - 101
	MA.OnSend("Cai Te", "Third")
	MA.OnEvent("SECURE_TRANSFER_CONFIRM_SEND_MAIL")
	MA.OnEvent("SECURE_TRANSFER_CANCEL")
	MA.OnEvent("MAIL_SEND_SUCCESS")
	check(ns.db.mailSent["Player-1-AAA"][1].mail.subject == "Second", "cancelled: not kept")
	local traceWas2, traced2 = ns.Trace, {}
	ns.Trace = function(self, t) traced2[#traced2 + 1] = t; return traceWas2(self, t) end
	MA.OnEvent("MAIL_SEND_SUCCESS")
	ns.Trace = traceWas2
	check(traced2[#traced2] and traced2[#traced2]:find("none was noted", 1, true), "a send with nothing noted before it: traced")
	table.remove(ns.db.mailSent["Player-1-AAA"], 1)
	table.remove(ns.db.mailSent["Player-1-AAA"], 1)
	now = now - 130
	local sentList = ns.db.mailSent and ns.db.mailSent["Player-1-AAA"]
	check(sentList and sentList[1] and sentList[1].to == "Bob" and sentList[1].mail.subject == "For Bob" and sentList[1].at == now,
		"mail to Bob: kept on your list")
	P._dirty = true
	local function Kinds(q)
		local out = {}
		for _, e in ipairs(UI:Search(q)) do if e.mailKind then out[#out + 1] = e.mailKind .. ":" .. e.name end end
		return table.concat(out, " | ")
	end
	local found = Kinds("@mail bob")
	check(found:find("sent:To Bob: For Bob", 1, true), "@mail bob: the mail sent to Bob: " .. found)
	-- the auction house's news: a sale not seen posted (no price), a sale seen posted (its price), a win told by chat
	_G.ERR_AUCTION_SOLD_S, _G.ERR_AUCTION_WON_S = "A buyer has been found for your auction of %s.", "You won an auction for %s"
	MA.ResetChatForTests()
	MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Copper Bar", 77)
	MA.OnEvent("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Copper Bar.") -- (the same news twice: once)
	local AHwas, Itemwas = _G.C_AuctionHouse, _G.C_Item
	_G.C_Item = setmetatable({ GetItemLink = function() return "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r" end,
		GetItemName = function() return "Linen Cloth" end }, { __index = Itemwas })
	local posts = 0
	_G.C_AuctionHouse = { PostItem = function() posts = posts + 1 end, PostCommodity = function() end,
		GetNumOwnedAuctions = function() return 2 end,
		-- (the Auctions tab's list: every auction of yours, the one just posted too)
		GetOwnedAuctionInfo = function(i)
			if i == 1 then return { auctionID = 90, itemLink = "|Hitem:2592|h[Wool Cloth]|h", quantity = 5, buyoutAmount = 12000, timeLeftSeconds = 7200 } end
			return { auctionID = 78, itemLink = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", quantity = 20, buyoutAmount = 450000 }
		end }
	_G.hooksecurefunc = function(t, name, fn)
		if type(t) == "string" then t, name, fn = _G, t, name end
		local orig = t[name]
		t[name] = function(...) orig(...); fn(...) end
	end
	MA.postHooked = nil
	check(MA.HookPost(), "the auction house's posting is hooked")
	_G.AUCTION_DURATION_ONE, _G.AUCTION_DURATION_TWO = "12 Hours", "24 Hours" -- (the game's own: how long each runs)
	_G.C_AuctionHouse.PostItem({ bag = 0, slot = 1 }, 1, 20, nil, 450000)
	MA.OnEvent("AUCTION_HOUSE_AUCTION_CREATED", 78)
	local posted = ns.db.auctionsPosted["Player-1-AAA"]
	check(posted[78] and posted[78].ends == now + 12 * 3600, "posted for 12 hours (the game's own words for it): runs out then: "
		.. tostring(posted[78] and posted[78].ends and (posted[78].ends - now)))
	MA.OnEvent("OWNED_AUCTIONS_UPDATED")
	check(posts == 1 and posted[78] and posted[78].price == 450000 and posted[78].name == "Linen Cloth" and posted[78].seen == "posted"
		and posted[90] and posted[90].price == 12000 and posted[90].seen == "listed" and posted[90].ends == now + 7200,
		"its price kept: posted (hooked) and listed (the Auctions tab, with its time left)")
	-- (0.48.10, the player's call) @auction: every character's auctions up now, what runs out first first, its price and
	-- time left; @stored keeps counting them, from the bag addon's record
	local A = ns.providers.auctions
	A._dirty = true
	local up = {}
	for _, e in ipairs(UI:Search("@auction")) do if e.ahKind == "up" then up[#up + 1] = e end end
	check(#up == 2 and up[1].name == "Wool Cloth x5" and up[1].detail:find("2 h left", 1, true) and up[2].name == "Linen Cloth x20"
		and up[2].detail:find("45g", 1, true) and up[2].detail:find("12 h left", 1, true),
		"@auction: both up now, the soonest first, with price and time left: " .. tostring(up[1] and up[1].detail) .. " / " .. tostring(up[2] and up[2].detail))
	check(MA.Question("my auctions") == nil and ns.Auctions.Question("my auctions") and ns.Auctions.Question("what am i selling")
		and not ns.Auctions.Question("auction house") and not ns.Auctions.Question("ah") and not ns.Auctions.Question("auction") and ns.Auctions.Question("auction sold") and not ns.Auctions.Question("my auction mail")
		and MA.Question("auction mail"), "\"my auctions\" / \"what am i selling\" are @auction's; \"auction house\", \"ah\" stay searches, \"auction mail\" is the mail's")
	local ans = ns.Auctions.Answer(ns.Auctions.Question("what am i selling"))
	check(#ans == 2 and ans[1].ahKind == "up", "\"what am i selling\": the auctions up now")
	check(ns.Auctions.ToAdvanced(ns.Auctions.Question("my auctions sold linen")) == "@auction is:sold linen ", "Alt+`: @auction is:sold linen")
	-- (0.55.7) and it finds what the question does ("sold", "listed" were words searched)
	check(T.SameAsAdvanced("what am i selling"))
	check(MA.ToAdvanced(MA.Question("incoming mail")) == "@auction is:incoming ", "Alt+` on \"incoming mail\": @auction's news: "
		.. MA.ToAdvanced(MA.Question("incoming mail")))
	-- the Auctions tab's list without one kept as posted: it's over (paid out, expired or cancelled)
	posted[77] = { name = "Copper Bar", count = 10, t = now - 600, seen = "posted" }
	MA.OnEvent("OWNED_AUCTIONS_UPDATED")
	check(posted[77] == nil and MA.EndedAuctions()[77] and posted[78] and posted[90], "not on the Auctions tab any more: over")
	MA.OnEvent("AUCTION_CANCELED", 90)
	check(posted[90] == nil and MA.EndedAuctions()[90], "cancelled: over")
	posted[90] = { link = "|Hitem:2592|h[Wool Cloth]|h", name = "Wool Cloth", count = 5, price = 12000, t = now, seen = "listed", ends = now + 7200 }
	MA.Store("auctionsEnded")["Player-1-AAA"][90] = nil
	-- one whose time ran out with no other news: after those up now, greyed, saying so
	posted[91] = { name = "Silk Cloth", count = 2, price = 900, t = now - 9 * 3600, seen = "posted", ends = now - 7200 }
	A._dirty = true
	local res, last = UI:Search("@auction"), nil
	for _, e in ipairs(res) do if e.ahKind then last = e end end
	check(last and last.name == "Silk Cloth x2" and last.ahKind == "over" and last.detail:find("time ran out 2 h ago", 1, true)
		and last.color == "|cff9d9d9d", "its time ran out: last, greyed, saying so: " .. tostring(last and last.detail))
	posted[91] = nil
	-- (0.50.7, review) several alike, one come back by mail: the one whose time ran out is over, not one still up
	do
		local LINK = "|Hitem:4306|h[Silk Cloth]|h"
		for id = 201, 206 do posted[id] = { link = LINK, name = "Silk Cloth", count = 20, t = now - 3600 - id, seen = "posted", ends = now + 7200 } end
		posted[207] = { link = LINK, name = "Silk Cloth", count = 20, t = now - 100, seen = "posted", ends = now - 60 }
		local box = { mails = { { items = { { id = 4306, count = 20 } }, auction = "expired", first = now } } }
		local n = MA.EndedFromMail(box, now)
		local left = 0
		for id = 201, 206 do if posted[id] then left = left + 1 end end
		check(n == 1 and posted[207] == nil and left == 6, "the one that ran out came back, the six still up stay: " .. n .. ", " .. left .. " left")
		for id = 201, 207 do posted[id] = nil; MA.Store("auctionsEnded")["Player-1-AAA"][id] = nil end
	end
	now = now + 60
	MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Linen Cloth", 78)
	MA.OnEvent("CHAT_MSG_SYSTEM", "You won an auction for Wool Cloth")
	local news = ns.db.mailAuctions["Player-1-AAA"]
	check(#news == 3 and news[1].kind == "won" and news[2].kind == "sold" and news[2].price == 450000 and news[3].price == nil,
		"three pieces of news (the doubled sale once), the posted one with its price")
	now = now + 60
	P._dirty, ns.providers.auctions._dirty = true, true
	found = Kinds("@auction is:incoming")
	check(found == "auction:Won: Wool Cloth | auction:Sold: Linen Cloth x20 | auction:Sold: Copper Bar", "@auction is:incoming (how many sold): " .. found)
	check(not Kinds("@mail"):find("auction:", 1, true), "the auction house's news is @auction's, not @mail's")
	check(posted[78] == nil and MA.EndedAuctions()[78], "sold: off the auction house")
	local soldRow
	for _, e in ipairs(UI:Search("@auction is:incoming linen")) do if e.mailKind == "auction" then soldRow = e end end
	check(soldRow and soldRow.detail:find("45g", 1, true) and soldRow.detail:find("gold due in about 59 min", 1, true),
		"the sale: its price, the gold due in about an hour: " .. tostring(soldRow and soldRow.detail))
	MA.OnSend("Plamen Pally", "Hi Pally")
	MA.OnEvent("MAIL_SEND_SUCCESS")
	P._dirty, ns.providers.auctions._dirty = true, true
	found = Kinds("@mail is:sent")
	check(found:find("sent:To Bob: For Bob", 1, true) and found:find("mail:Hi Pally", 1, true),
		"@mail is:sent: to others and to your alts: " .. found)
	-- in words: "sent mail", "auctions on their way"
	ns.db.easyMode = true
	local q = MA.Question("sent mail")
	check(q and q.sent and MA.ToAdvanced(q) == "@mail is:sent " and MA.Question("incoming mail").incoming, "sent mail / incoming mail")
	local sentNames = {}
	for _, e in ipairs((MA.Answer(q))) do sentNames[#sentNames + 1] = e.name end
	sentNames = table.concat(sentNames, " | ")
	check(sentNames:find("To Bob: For Bob", 1, true) and sentNames:find("Hi Pally", 1, true) and not sentNames:find("Sold", 1, true),
		"\"sent mail\": to others and to your alts, not the auction house's news: " .. sentNames)
	-- (review, 0.48.6) drawn too, not just answered: the rows on their way kept their order in _pos (the letters a search
	-- marks), and drawing them errored; letters an earlier search marked are forgotten by an answer
	ns.db.easyMode = false
	UI:Open("@mail bob"); FlushAll()
	local bobRow
	for _, e in ipairs(UI.Results()) do if e.mailKind == "sent" then bobRow = e end end
	local function Marks(e)
		local n = 0
		for _ in pairs(type(rawget(e, "_pos")) == "table" and rawget(e, "_pos") or {}) do n = n + 1 end
		return n
	end
	local marked = bobRow and Marks(bobRow) > 0
	UI:Hide(); FlushAll()
	ns.db.easyMode = true
	local okDraw, errDraw = pcall(function() UI:Open("sent mail"); FlushAll() end)
	local drawn = false
	for i = 1, #UI.rows do
		local r = UI.rows[i]
		if r:IsShown() and (r.label:GetText() or ""):find("To Bob", 1, true) then drawn = true end
	end
	check(okDraw and drawn, "\"sent mail\" drawn: " .. tostring(errDraw))
	check(marked and bobRow and Marks(bobRow) == 0, "the letters \"@mail bob\" marked are gone in the answer: " .. tostring(marked))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
	local lines = table.concat(MA.AllLines(), "\n")
	check(lines:find("On its way:", 1, true) and lines:find("To Bob: For Bob", 1, true), ".mail lists what's on its way")
	-- a mailbox read: the win's mail is in it (gone from the news); the sale's isn't yet (kept)
	inbox = { { "Stormwind Auction House", "Auction won: Wool Cloth", 0, 0, 30, 1, false, false, true,
		items = { { "Wool Cloth", 2592, 1, 5, 1 } } } }
	MA.OnEvent("MAIL_SHOW")
	MA.OnEvent("MAIL_INBOX_UPDATE")
	FlushAll()
	MA.OnEvent("MAIL_CLOSED")
	check(#news == 2 and news[1].kind == "sold", "a mailbox read: the win's mail came (dropped); the sales still on their way")
	-- an hour on: all of it gone (the gold and the mail have arrived)
	now = now + 3600
	P._dirty, ns.providers.auctions._dirty = true, true
	found = Kinds("@mail")
	check(not found:find("auction:", 1, true) and not found:find("sent:", 1, true), "an hour later: gone: " .. found)
	-- 0.48.4 (the player: what you bought should show its own icon and quality): a buyout placed (hooked), then the news
	-- that you won it: its item's icon and quality, and what you paid
	local icons, quals = { [4500] = 133633, [2589] = 132889, [3576] = 133219 }, { [4500] = 4, [2589] = 1 }
	_G.C_Item = setmetatable({ GetItemIconByID = function(id) return icons[id] end, GetItemQualityByID = function(id) return quals[id] end,
		GetItemInfo = function(n) if n == "Tin Bar" then return "Tin Bar", "|cnIQ1:|Hitem:3576::|h[Tin Bar]|h|r" end end,
		GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth" })[id] end }, { __index = Itemwas })
	_G.C_AuctionHouse.PlaceBid = function() end
	_G.C_AuctionHouse.GetAuctionInfoByID = function(id)
		if id == 501 then return { itemKey = { itemID = 4500 }, itemLink = "|cnIQ4:|Hitem:4500::|h[Traveler's Backpack]|h|r", buyoutAmount = 90000 } end
	end
	MA.postHooked = nil
	MA.HookPost()
	_G.C_AuctionHouse.PlaceBid(501, 90000)
	MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 2, "Traveler's Backpack", 501)
	-- a commodity bought (no auction id), and the game's own notification of it too: one piece of news
	MA.OnEvent("COMMODITY_PURCHASED", 2589, 20)
	MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 2, "Linen Cloth", nil)
	-- won, no bid seen (bought before Terminal watched): known by its name
	MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 2, "Tin Bar", 502)
	local wonCloth = 0
	for _, a in ipairs(ns.db.mailAuctions["Player-1-AAA"]) do if a.kind == "won" and a.item == "Linen Cloth" then wonCloth = wonCloth + 1 end end
	P._dirty, ns.providers.auctions._dirty = true, true
	local byItem = {}
	for _, e in ipairs(UI:Search("@auction is:incoming")) do if e.mailKind == "auction" then byItem[e.auction.item] = e end end
	local bag, cloth, tin = byItem["Traveler's Backpack"], byItem["Linen Cloth"], byItem["Tin Bar"]
	check(bag and bag.icon == 133633 and bag.color == "|cffa335ee" and bag.price == 90000 and bag.seen == "bid",
		"won at a buyout you placed: its icon, its quality, what you paid: " .. tostring(bag and bag.icon) .. " " .. tostring(bag and bag.color))
	check(cloth and cloth.icon == 132889 and cloth.name == "Won: Linen Cloth x20" and wonCloth == 1,
		"a commodity bought: its icon and how many, once though the game told it too: " .. tostring(cloth and cloth.name) .. " " .. wonCloth)
	check(tin and tin.icon == 133219 and tin.color == "|cffffffff", "no bid seen: known by its name: " .. tostring(tin and tin.icon))
	-- news kept before (no icon on it): asked again when listed
	table.insert(ns.db.mailAuctions["Player-1-AAA"], { kind = "won", item = "Tin Bar", at = now - 5 })
	P._dirty, ns.providers.auctions._dirty = true, true
	local old
	for _, e in ipairs(UI:Search("@auction is:incoming tin")) do if e.mailKind == "auction" and e.at == now - 5 then old = e end end
	check(old and old.icon == 133219, "news kept before 0.48.4: its icon looked up: " .. tostring(old and old.icon))
	-- the mail itself: drawn as what it carries (an item the inbox gave no icon for: asked by id); running out stays red in
	-- its time left; a mail with nothing in it keeps its red name
	inbox = { { "Stormwind Auction House", "Auction won: Traveler's Backpack", 0, 0, 0.5, 1, false, false, true,
		items = { { "Traveler's Backpack", 4500, nil, 1, 4 } } }, { "Bob", "Hello", 0, 0, 0.5, 0, false, false, false } }
	MA.OnEvent("MAIL_SHOW")
	MA.OnEvent("MAIL_INBOX_UPDATE")
	FlushAll()
	MA.OnEvent("MAIL_CLOSED")
	P._dirty, ns.providers.auctions._dirty = true, true
	local won, hello
	for _, e in ipairs(UI:Search("@mail")) do
		if e.mailKind == "mail" and e.name == "Auction won: Traveler's Backpack" then won = e end
		if e.mailKind == "mail" and e.name == "Hello" then hello = e end
	end
	check(won and won.icon == 133633 and won.color == "|cffa335ee" and won.detail:find("|cffff4040", 1, true),
		"a mail with an epic in it: its icon and colour, red in its time left: " .. tostring(won and won.color))
	check(hello and hello.color == "|cffff4040", "a mail with nothing in it, running out: its name red")
	-- what's past its time goes on every write, @mail looked at or not
	ns.db.auctionsPosted["Player-1-AAA"][1] = { price = 1, t = now - MA.POSTED_KEEP - 10 }
	ns.db.auctionBids = { ["Player-1-AAA"] = { [2] = { price = 1, t = now - MA.POSTED_KEEP - 10 } } }
	MA.OnEvent("OWNED_AUCTIONS_UPDATED")
	check(ns.db.auctionsPosted["Player-1-AAA"][1] == nil and ns.db.auctionBids["Player-1-AAA"][2] == nil and ns.db.auctionsPosted["Player-1-AAA"][90],
		"an old posted price and bid pruned when the Auctions tab is read")
	-- 0.48.9 (the player: 200 arrows from a failed auction, mailed back and taken, still counted in @stored as on the
	-- auction house): the game's own mail bringing an auction's items back ends that auction; a player's mail with the
	-- same items doesn't, nor the game's mail that was in the inbox before the auction was made
	do
		local mine = ns.db.auctionsPosted["Player-1-AAA"]
		local inboxWas = {}
		for i, m in ipairs(inbox) do inboxWas[i] = m end
		local function Inbox(list) for i = #inbox, 1, -1 do inbox[i] = nil end for i, m in ipairs(list) do inbox[i] = m end end
		local LINEN = { "Postmaster", "Recovered items", 0, 0, 30, 1, false, false, false, noReply = true,
			items = { { "Light Leather", 2318, 1, 20, 1 } } }
		local nowWas = now
		now = nowWas - 120
		Inbox({ LINEN })
		MA.ReadInbox() -- (the game's mail with 20 Light Leather, read before the auctions below were made)
		now = nowWas
		mine[300] = { link = "|cff1eff00|Hitem:3464::::::::30:1491:::::::::|h[Feathered Arrow]|h|r", name = "Feathered Arrow", count = 200,
			t = now - 60, seen = "posted" }
		mine[301] = { link = "|cffffffff|Hitem:2318|h[Light Leather]|h|r", name = "Light Leather", count = 20, t = now - 60, seen = "posted" }
		local changed = 0
		local changedWas = ns.Changed
		ns.Changed = function(self, id) if id == "stored" then changed = changed + 1 end return changedWas(self, id) end
		Inbox({ LINEN, { "Bob", "Arrows for you", 0, 0, 30, 1, false, false, false, items = { { "Feathered Arrow", 3464, 1, 200, 2 } } } })
		MA.ReadInbox()
		check(mine[300] and not MA.EndedAuctions()[300] and changed == 0, "a player's mail with the same items: the auction stays")
		Inbox({ LINEN, { "Auction House", "Auction cancelled: Feathered Arrow", 0, 0, 30, 1, false, false, false, noReply = true,
			items = { { "Feathered Arrow", 3464, 1, 200, 2 } } } })
		MA.ReadInbox()
		local ended = MA.EndedAuctions()
		check(ended[300] and mine[300] == nil and changed == 1, "the game's mail bringing the 200 arrows back: that auction is over")
		check(not ended[301] and mine[301], "the game's mail already there before the auction: not its return")
		-- the subject alone says it too (a reply-able mail), and @stored hears of it; .mail forget clears what's noted
		_G.AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
		MA.ResetSubjectsForTests()
		mine[302] = { link = "|cffffffff|Hitem:4306|h[Silk Cloth]|h|r", name = "Silk Cloth", count = 5, t = now - 30, seen = "posted" }
		Inbox({ { "Auction House", "Auction cancelled: Silk Cloth", 0, 0, 30, 1, false, false, false, items = { { "Silk Cloth", 4306, 1, 5, 1 } } } })
		MA.ReadInbox()
		check(MA.EndedAuctions()[302], "an auction cancelled (its subject): over")
		ns.Changed = changedWas
		_G.AUCTION_REMOVED_MAIL_SUBJECT = nil
		MA.ResetSubjectsForTests()
		Inbox(inboxWas)
		now = now + MA.POSTED_KEEP + 1
		check(not next(MA.EndedAuctions()), "noted as over for as long as an auction is kept, then forgotten")
		now = nowWas
	end
	-- (0.49.2, review) a sale's news goes once its own mail is in, not for an older sale's mail of the same item
	do
		local had = ns.db.mailAuctions
		ns.db.mailAuctions = { ["Player-1-AAA"] = { { kind = "sold", item = "Copper Bar", at = 1000 } } }
		local box = { mails = { { auction = "sold", subject = "Auction successful: Copper Bar", first = 500 } } }
		MA.SettleAuctions(box, 1100)
		check(#ns.db.mailAuctions["Player-1-AAA"] == 1, "an older sale's mail doesn't settle a new sale's news")
		box.mails[2] = { auction = "sold", subject = "Auction successful: Copper Bar", first = 1050 }
		MA.SettleAuctions(box, 1100)
		check(#ns.db.mailAuctions["Player-1-AAA"] == 0, "its own mail does")
		ns.db.mailAuctions = had
	end
	-- (0.49.2, review) the tooltip's Shift+Enter only where there is one (the nearest mailbox is Questie's)
	do
		local function TipLines(e)
		local lines = {}
		local t = { SetText = function(_, s) lines[#lines + 1] = tostring(s) end,
			AddLine = function(_, s) lines[#lines + 1] = tostring(s) end,
			AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " " .. tostring(b) end }
		e.tooltip(e, t)
		return table.concat(lines, "\n")
	end
		P._dirty = true
		local rows = UI:Search("@mail")
		local mailRow
		for _, e in ipairs(rows) do if e.mailKind == "mail" then mailRow = e break end end
		local hadBox = ns.providers.mailbox
		ns.providers.mailbox = nil
		check(mailRow and not TipLines(mailRow):find("waypoint", 1, true), "no mailboxes: no Shift+Enter promised")
		ns.providers.mailbox = hadBox or { id = "mailbox" }
		check(mailRow and TipLines(mailRow):find("waypoint to the nearest mailbox", 1, true), "with them: said")
		ns.providers.mailbox = hadBox
		-- nothing kept anywhere: a line says how to fill it
		local boxesWas, sentWas = ns.db.mailboxes, ns.db.mailSent
		ns.db.mailboxes, ns.db.mailSent = {}, nil
		P._dirty = true
		rows = UI:Search("@mail")
		check(#rows == 1 and rows[1].noActivate and rows[1].name == MA.NONE, "an empty @mail says why: " .. tostring(rows[1] and rows[1].name))
		ns.db.mailboxes, ns.db.mailSent = boxesWas, sentWas
		P._dirty = true
	end
	-- .mail forget: that character's news, sent mail and kept prices go with its mailbox
	ns.db.mailboxes["Player-1-AAA"] = { name = "Zz Main", realm = "R", mails = {} }
	ns:FindCommand("mail").run("forget zz main")
	check(ns.db.auctionsPosted["Player-1-AAA"] == nil and ns.db.mailAuctions["Player-1-AAA"] == nil and ns.db.auctionBids["Player-1-AAA"] == nil,
		".mail forget: every store of that character")
	_G.C_AuctionHouse, _G.C_Item, MA.postHooked = AHwas, Itemwas, nil
	_G.ERR_AUCTION_SOLD_S, _G.ERR_AUCTION_WON_S = nil, nil
	MA.ResetChatForTests()
	ns.db.mailSent, ns.db.mailAuctions, ns.db.auctionsPosted, ns.db.auctionBids = nil, nil, nil, nil

	_G.HasSendMailItem, _G.GetSendMailItem, _G.GetSendMailItemLink = sendWas.has, sendWas.get, sendWas.link
	_G.GetSendMailMoney, _G.GetSendMailCOD, _G.SendMail, _G.hooksecurefunc, MA.hooked = sendWas.money, sendWas.cod, sendWas.send, sendWas.hook, sendWas.hooked
	ns.db.xpChars = xpWas

	_G.UnitGUID, _G.UnitClass, _G.GetRealmName, _G.time = save.guid, save.cls, save.realm, save.time
	ns.db.mailboxes, ns.db.mailWarn, ns.Output, ns.Print, ns.db.easyMode = save.boxes, save.warn, save.out, save.print, save.easy
	_G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxItem, _G.GetInboxItemLink = save.n, save.head, save.item, save.ilink
	_G.GetInboxInvoiceInfo, _G.InboxItemCanDelete, _G.GetInboxText, _G.HasNewMail = save.inv, save.del, save.text, save.new
	_G.GetLatestThreeSenders, _G.AUCTION_SOLD_MAIL_SUBJECT, _G.InboxFrame = save.senders, save.sold, save.inbox
	ns.Highlight.Show, MA.open, ns.CharacterName, MA.warned = save.hl, save.open, save.cname, save.warned
	_G.MailItem3Button = nil
	MA.ResetSubjectsForTests()
	P._dirty, ns.providers.auctions._dirty = true, true
end

-- (review, 0.53.6) new mail waiting: the mail list's own event; @auction isn't marked changed for it
do
	local ns = T.ns
	local changed = {}
	local real = ns.Changed
	ns.Changed = function(self, id) changed[id] = true return real(self, id) end
	ns.Mail.OnEvent("UPDATE_PENDING_MAIL")
	ns.Changed = real
	T.check(not changed.auctions, "UPDATE_PENDING_MAIL: @auction left alone (it doesn't show pending mail)")
end

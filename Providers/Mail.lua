local ns = select(2, ...)
local L = ns.L

-- Your mail (@mail, @inbox; Simple mode: "my mail", "mail running out", "cod mail", under Character): what's in
-- each of your characters' mailboxes, kept by Terminal itself every time a mailbox shows (no bag addon needed): who
-- sent each mail, its gold, its COD, what's attached, and when it runs out. Running out means deleted (with what's in
-- it: the auction house's gold, the game's own mail) or sent back to whoever sent it (a player's mail); the inbox says
-- which, and so does Terminal. A note of each mailbox, per character (db.mailboxes, by GUID): an alt's mail shows up once
-- you've opened a mailbox on it with Terminal, as it was then (mail that ran out since is left out).
--
-- At login (not a /reload) a chat line names the gold and items in mail that runs out within MA.SOON, per character
-- (".set mailWarn off" stops it).
--
--   Enter        at an open mailbox, on your own mail: points at it in the inbox (or says the page); else the mail
--                (or a whole mailbox) in chat, only you see it
--   Shift+Enter  a waypoint to the nearest mailbox (QuestieDB's mailboxes)
--
-- Read with the inbox's own calls only (GetInboxHeaderInfo, GetInboxItem, GetInboxInvoiceInfo, InboxItemCanDelete:
-- what Forever's MailFrame.lua reads); never GetInboxText, which marks a mail read.
--
-- Mail on its way: mail you send to anyone who isn't one of your characters is kept for an hour (MA.SENT_KEEP: what
-- mail with items or gold takes between accounts), and the auction house's news as the game tells it
-- (AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION: sold, won, outbid, expired; the classic chat lines too): a sold auction's
-- gold due about an hour later, with its price when Terminal saw the auction posted (C_AuctionHouse.PostItem /
-- PostCommodity hooked, then AUCTION_HOUSE_AUCTION_CREATED; or the Auctions tab's list, OWNED_AUCTIONS_UPDATED).

local MA = {}
ns.Mail = MA

local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower

MA.SOON = 3 * 86400 -- (s: "running out soon", and the login warning's reach)
MA.MAX_MAILS = 100 -- (kept per character; the inbox shows 50 at most)
MA.WARN_DELAY = 10 -- (s after login before the warning, once the chat is up)
MA.WARN_MAX = 4 -- (characters named; the rest counted)
MA.PER_PAGE = 7 -- (INBOXITEMS_TO_DISPLAY in Forever's MailFrame.lua)
MA.READ_DELAY = 0.3 -- (s: an inbox update burst read once)

local Now = ns.Now
local MyKey = ns.PlayerGUID

local function Boxes() return ns.DbTable("mailboxes") end

local function Dirty() ns:Changed("mail"); ns:Changed("auctions") end -- (@auction lists the news too: Auctions.lua)

local Money = ns.Money

--- Seconds left as the inbox says it: "3 days", "1 day", "5 h", "20 min" (under a minute: "1 min", as the inbox does).
function MA.Left(s) return ns.Left(math.max(60, tonumber(s) or 0)) end

----------------------------------------------------------------------
-- Reading the inbox (only while a mailbox shows)
----------------------------------------------------------------------

-- the auction house's subjects ("Auction successful: %s"...), as the game's own strings say them: what each mail is
local AUCTION_SUBJECTS = { sold = "AUCTION_SOLD_MAIL_SUBJECT", won = "AUCTION_WON_MAIL_SUBJECT",
	expired = "AUCTION_EXPIRED_MAIL_SUBJECT", outbid = "AUCTION_OUTBID_MAIL_SUBJECT", cancelled = "AUCTION_REMOVED_MAIL_SUBJECT" }
local subjectPatterns

local function Pattern(s) return (ns.FormatPattern(s)) end

--- What an auction house mail is ("sold", "won", "expired", "outbid", "cancelled"), from its subject; nil for others.
function MA.AuctionSubject(subject)
	if type(subject) ~= "string" then return nil end
	if not subjectPatterns then
		subjectPatterns = {}
		for kind, global in pairs(AUCTION_SUBJECTS) do
			local s = Str(_G[global])
			if s and s:find("%%%d*%$?s") then subjectPatterns[kind] = Pattern(s) end
		end
	end
	for kind, p in pairs(subjectPatterns) do
		if subject:find(p) then return kind end
	end
	return nil
end
MA.ResetSubjectsForTests = function() subjectPatterns = nil end

--- One mail, as the inbox shows it now (index i), or nil when the game won't say.
function MA.ReadMail(i, now)
	local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, _, canReply, isGM = Safe(GetInboxHeaderInfo, i)
	daysLeft = Num(daysLeft)
	if not daysLeft then return nil end
	money, cod, itemCount = Num(money) or 0, Num(cod) or 0, Num(itemCount) or 0
	local m = {
		from = Str(sender), subject = Str(subject), money = money > 0 and money or nil, cod = cod > 0 and cod or nil,
		expires = math.floor(now + daysLeft * 86400), read = wasRead == true or nil, returned = wasReturned == true or nil,
		gm = isGM == true or nil,
		-- the game's own mail (the auction house's, the system's): no one to reply to, as the inbox's Reply button says
		game = (canReply == false and isGM ~= true) or nil,
		-- running out: deleted (with what's attached) or sent back to the sender, as the inbox's own tooltip tells them
		deletes = Safe(InboxItemCanDelete, i) == true or nil,
	}
	if itemCount > 0 then
		local items = {}
		for a = 1, (Num(_G.ATTACHMENTS_MAX_RECEIVE) or 16) do
			local name, id, icon, count, quality = Safe(GetInboxItem, i, a)
			name, id = Str(name), Num(id)
			if name or id then
				items[#items + 1] = { id = id, name = name, count = Num(count) or 1, q = Num(quality),
					link = Str(Safe(GetInboxItemLink, i, a)), icon = icon }
				if #items >= itemCount then break end -- (all of them found: the rest of the 16 slots aren't asked)
			end
		end
		if #items > 0 then m.items = items end
	end
	local kind, item, player, bid, _, deposit, cut, _, etaH, etaM, count = Safe(GetInboxInvoiceInfo, i)
	kind = Str(kind)
	if kind then
		m.invoice = { kind = kind, item = Str(item), player = Str(player), bid = Num(bid), deposit = Num(deposit),
			cut = Num(cut), etaH = Num(etaH), etaM = Num(etaM), count = Num(count) }
	end
	m.auction = (kind and (kind == "seller" and "sold" or kind == "buyer" and "won" or "pending")) or MA.AuctionSubject(m.subject)
	return m
end

--- A mail's signature: the same mail read again (the inbox's order moves as mail is taken).
function MA.Sig(m)
	local first = m.items and m.items[1]
	return table.concat({ m.from or "", m.subject or "", m.money or 0, m.cod or 0, first and (first.id or first.name) or "",
		first and first.count or 0 }, "|")
end

--- The inbox as it shows now, kept as your character's note. Only while a mailbox shows (MA.open): read elsewhere, the
--- game may answer with nothing, and the note would lose every mail.
function MA.ReadInbox()
	local key, boxes = MyKey(), Boxes()
	if not (key and boxes) then return nil end
	local n, total = Safe(GetInboxNumItems)
	n, total = Num(n), Num(total)
	if not n then return nil end
	local now = Now()
	local mails = {}
	for i = 1, math.min(n, MA.MAX_MAILS) do
		local m = MA.ReadMail(i, now)
		if m then mails[#mails + 1] = m end
	end
	local box = {
		name = ns.CharacterName() or Str(Safe(UnitName, "player")) or L["You"], realm = Str(Safe(GetRealmName)),
		class = Str(select(2, Safe(UnitClass, "player"))), t = now, mails = mails,
		more = (total and total > n) and (total - n) or nil,
	}
	-- when each mail was first seen here (carried over from the reads before): an auction's return is mail that came
	-- after it was made (MA.EndedFromMail) (the same mail: alike and running out when this one does, each read mail
	-- matched once. a new mail alike an older one, an auction's arrows back a second time, took the older one's time,
	-- and the auction it ended was never seen as over)
	local before, old = boxes[key], {}
	if type(before) == "table" and type(before.mails) == "table" then
		for _, m in ipairs(before.mails) do
			if type(m) == "table" then old[#old + 1] = { sig = MA.Sig(m), exp = m.expires, first = m.first or before.t } end
		end
	end
	for _, m in ipairs(mails) do
		local sig, best, bestD = MA.Sig(m), nil, nil
		for _, o in ipairs(old) do
			if not o.used and o.sig == sig then
				local d = (o.exp and m.expires) and math.abs(o.exp - m.expires) or 0
				if d <= MA.MAIL_KEEP_SAME and (not bestD or d < bestD) then best, bestD = o, d end
			end
		end
		if best then best.used = true end
		m.first = best and best.first or now
	end
	boxes[key] = box
	MA.SettleAuctions(box, now)
	Dirty()
	local money, items = 0, 0
	for _, m in ipairs(mails) do
		money = money + (m.money or 0)
		items = items + (m.items and #m.items or 0)
	end
	ns:Trace(("mail: the inbox read: %d mails (%s on the server), %d with items attached, %s in gold"):format(#mails,
		tostring(total), items, Money(money, true)))
	return box
end

----------------------------------------------------------------------
-- Mail you send to your own characters: in their list at once (until they open a mailbox, which reads the real one)
----------------------------------------------------------------------

MA.KEEP_DAYS, MA.COD_DAYS = 30, 3 -- (a player's mail lasts 30 days; COD mail 3)
-- (s a send is waited on for MAIL_SEND_SUCCESS: 0.47.6, the player's log: mail with an item to "Cai Te" went through
-- 101 s after the game's SendMail, with no confirmation and no failure between; 60 s dropped it. A new send replaces the
-- one waited on, so a long wait takes nothing else for it)
MA.SEND_WAIT = 900
MA.CONFIRM_WAIT = 900 -- (s when the game asks you to confirm sending gold or items to someone not your own)

local pendingSend

-- a name as compared: lowercase, no spaces or hyphens ("Plamen Pally-Forever" = "plamenpallyforever")
local function NameKey(s) return (Lower(s):gsub("[%s%-]", "")) end

--- The note key (GUID) of your character called `name` (as typed in the To box: "Plamen Pally", "Plamen Pally-Forever"),
--- from Terminal's own notes of your characters (their mailboxes, their experience); nil for anyone else.
function MA.OwnKey(name)
	local want = Str(name) and NameKey(name)
	if not want then return nil end
	local myKey = MyKey()
	for _, notes in ipairs({ Boxes() or {}, ns.db and type(ns.db.xpChars) == "table" and ns.db.xpChars or {} }) do
		for key, c in pairs(notes) do
			if key ~= myKey and type(c) == "table" and Str(c.name) then
				if NameKey(c.name) == want or (c.realm and NameKey(c.name .. c.realm) == want) then return key, c end
			end
		end
	end
	return nil
end

--- The mail being sent, as the send window holds it when the game's own SendMail runs (hooked): kept until the game
--- says it went (MAIL_SEND_SUCCESS) or failed.
function MA.OnSend(to, subject)
	to = Str(to)
	if not to then return nil end
	local items = {}
	for a = 1, (Num(_G.ATTACHMENTS_MAX_SEND) or 12) do
		if Safe(_G.HasSendMailItem, a) == true then
			local name, id, icon, count, quality = Safe(_G.GetSendMailItem, a)
			if Str(name) or Num(id) then
				items[#items + 1] = { id = Num(id), name = Str(name), count = Num(count) or 1, q = Num(quality),
					link = Str(Safe(_G.GetSendMailItemLink, a)), icon = icon }
			end
		end
	end
	local money, cod = Num(Safe(_G.GetSendMailMoney)) or 0, Num(Safe(_G.GetSendMailCOD)) or 0
	subject = Str(subject)
	if not subject and items[1] then -- (the game titles an empty subject after the first item)
		subject = (items[1].name or "?") .. ((items[1].count or 1) > 1 and (" (" .. items[1].count .. ")") or "")
	end
	pendingSend = { to = to, at = Now(), mail = { from = ns.CharacterName() or Str(Safe(UnitName, "player")), subject = subject,
		money = money > 0 and money or nil, cod = cod > 0 and cod or nil, items = #items > 0 and items or nil } }
	ns:Trace(("mail: sending to %s (%d items, %s): waiting for the game to say it went"):format(to, #items, Money(money, true)))
	return pendingSend
end

--- The game asks you to confirm gold or items going to someone not your own (SECURE_TRANSFER_CONFIRM_SEND_MAIL: its
--- secure dialog sends it when you accept): the send waits longer, and a MAIL_FAILED meanwhile doesn't drop it.
function MA.SendConfirming()
	if not pendingSend then return end
	pendingSend.confirm, pendingSend.failed = true, nil
	ns:Trace("mail: the game asks you to confirm sending to " .. pendingSend.to .. " (gold or items to someone not your own)")
end

--- MAIL_FAILED: the send didn't go, unless a confirmation comes or came.
function MA.SendFailed()
	if not pendingSend then return end
	pendingSend.failed = true
	ns:Trace("mail: the game said the send failed" .. (pendingSend.confirm and " (a confirmation is open: kept)" or ""))
end

--- The confirmation was closed without sending: the send noted for it is forgotten.
function MA.SendCancelled()
	if pendingSend and pendingSend.confirm then
		ns:Trace("mail: the send to " .. pendingSend.to .. " was cancelled")
		pendingSend = nil
	end
end

--- The game sent it: into the recipient's list when it's one of your characters (a note made for one that has none yet).
function MA.SendDone()
	local s = pendingSend
	pendingSend = nil
	if not s then ns:Trace("mail: a send went through, but none was noted before it (the game's SendMail wasn't seen)") return nil end
	local age = Now() - s.at
	if age > (s.confirm and MA.CONFIRM_WAIT or MA.SEND_WAIT) then
		ns:Trace(("mail: a send went through %d s after the one noted (to %s): not taken for it"):format(age, s.to))
		return nil
	end
	if s.failed and not s.confirm then ns:Trace("mail: the send noted had failed: not kept") return nil end
	local key, c = MA.OwnKey(s.to)
	if not key then return MA.KeepSent(s) end -- (anyone else: kept an hour, as on its way)
	local boxes = Boxes()
	local box = boxes[key]
	if type(box) ~= "table" or type(box.mails) ~= "table" then
		box = { name = c.name, realm = c.realm, class = c.class, mails = {} } -- (no t: never opened with Terminal)
		boxes[key] = box
	end
	local m = s.mail
	m.sent = s.at
	m.expires = s.at + (m.cod and MA.COD_DAYS or MA.KEEP_DAYS) * 86400
	table.insert(box.mails, 1, m)
	while #box.mails > MA.MAX_MAILS do table.remove(box.mails) end
	Dirty()
	ns:Trace("mail: sent to your " .. tostring(c.name) .. ": kept in its list until it opens a mailbox")
	return box
end

--- Hooks the game's SendMail (after it runs; the send itself stays the game's). True once hooked.
function MA.HookSend()
	if MA.hooked then return true end
	if type(_G.hooksecurefunc) ~= "function" or type(_G.SendMail) ~= "function" then return false end
	_G.hooksecurefunc("SendMail", function(to, subject) pcall(MA.OnSend, to, subject) end)
	MA.hooked = true
	ns:Trace("mail: the game's SendMail hooked (mail you send is noted)")
	return true
end

----------------------------------------------------------------------
-- Mail on its way: sent to others (an hour), the auction house's news (sold, won, outbid, expired)
----------------------------------------------------------------------

MA.SENT_KEEP = 3600 -- (s: mail with items or gold to another account arrives within the hour)
MA.AUCTION_KEEP = 3600 -- (s: a sold auction's gold comes about an hour later; won, outbid and expired mail at once)
MA.POSTED_KEEP = 3 * 86400 -- (s: an auction posted is kept this long for its price: the longest auction is 48 h)
MA.MAIL_KEEP_SAME = 600 -- (s: two reads of one inbox mail say when it runs out this close (its days left))
MA.MAIL_SAME = 120 -- (s: two reads of one mail say when it runs out this close)
MA.SAME = 10 -- (s: the same news told twice, the notification and a chat line, is one)
MA.POST_WAIT = 30 -- (s a post is waited on for AUCTION_HOUSE_AUCTION_CREATED)
MA.SOLD_KEEP = 30 * 86400 -- (s: your sales kept for @auction: as long as a sale's gold waits in the mailbox)
MA.MAX_SOLD = 200 -- (sales kept per character)

-- db.mailSent / db.mailAuctions / db.auctionsPosted, by your character's GUID
local function Store(name) return ns.DbTable(name) or {} end
local function Mine(name)
	local key = MyKey()
	if not key then return nil end
	local all = Store(name)
	if type(all[key]) ~= "table" then all[key] = {} end
	return all[key], key
end

--- Drops what's past its time: sent mail and auction news after their hour, posted auctions after MA.POSTED_KEEP.
function MA.Prune(now)
	now = now or Now()
	for _, list in pairs(Store("mailSent")) do
		for i = #list, 1, -1 do if type(list[i]) ~= "table" or now - (list[i].at or 0) >= MA.SENT_KEEP then table.remove(list, i) end end
	end
	for _, list in pairs(Store("mailAuctions")) do
		for i = #list, 1, -1 do if type(list[i]) ~= "table" or now - (list[i].at or 0) >= MA.AUCTION_KEEP then table.remove(list, i) end end
	end
	for _, name in ipairs({ "auctionsPosted", "auctionBids" }) do
		for _, kept in pairs(Store(name)) do
			for id, a in pairs(kept) do if type(a) ~= "table" or now - (a.t or 0) >= MA.POSTED_KEEP then kept[id] = nil end end
		end
	end
	for _, kept in pairs(Store("auctionsEnded")) do
		for id, t in pairs(kept) do if type(t) ~= "number" or now - t >= MA.POSTED_KEEP then kept[id] = nil end end
	end
	for _, list in pairs(Store("auctionsSold")) do
		for i = #list, 1, -1 do if type(list[i]) ~= "table" or now - (list[i].at or 0) >= MA.SOLD_KEEP then table.remove(list, i) end end
	end
end
MA.Store = Store
local function ItemIDOf(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end
local NameOfLink = ns.LinkName

--- An auction of yours sold: kept MA.SOLD_KEEP on your character's list of sales (db.auctionsSold), newest first, each
--- auction once. `a`: what was kept of it posted (its price, its count); `item`: its name when nothing was (the news
--- names it). The sale's mail tells the buyer and what you got (MA.SalesFromMail).
function MA.KeepSale(id, a, now, item)
	local list = Mine("auctionsSold")
	if not list then return nil end
	now, id = now or Now(), Num(id)
	local name = (type(a) == "table" and (Str(a.name) or NameOfLink(a.link))) or Str(item)
	if not name then return nil end
	for _, s in ipairs(list) do
		if id and s.auctionID == id then return s end
		-- (news told twice, the notification and a chat line, is one sale: the chat line's, with no id, takes the
		-- notification's id when it comes second; release review)
		if not s.auctionID and s.item == name and math.abs(now - (s.at or 0)) < MA.SAME then
			s.auctionID = id
			-- (and what was kept of it posted, which the chat line didn't have)
			if type(a) == "table" then
				s.link, s.price, s.each, s.count = s.link or a.link, s.price or a.price, s.each or a.each, s.count or a.count
			end
			return s
		end
	end
	local s = { item = name, at = now, auctionID = id }
	if type(a) == "table" then s.link, s.price, s.each, s.count = a.link, a.price, a.each, a.count end
	table.insert(list, 1, s)
	while #list > MA.MAX_SOLD do table.remove(list) end
	Dirty()
	return s
end

--- Your characters' sales kept: { { key = character's GUID, sale } }, any order.
function MA.Sales()
	local out = {}
	for key, list in pairs(Store("auctionsSold")) do
		for i, s in ipairs(list) do if type(s) == "table" then out[#out + 1] = { key = key, sale = s, i = i } end end
	end
	return out
end

--- The sales the inbox's mail tells (the auction house's invoice: who bought it, for how much, the deposit back and the
--- cut): written on the sale kept of it (the oldest of that item not told yet: sales are mailed in order), or kept as a
--- sale when Terminal didn't see it sell (sold while the game was closed). How many were new.
function MA.SalesFromMail(box, now)
	local list = Mine("auctionsSold")
	if not (list and box) then return 0 end
	now = now or Now()
	local n, changed, used = 0, false, {}
	-- a sale's mail is told apart by its item, count and price and by when it runs out (the mail's own, steady to the
	-- second whatever is read when): not by its buyer (the game can give it a moment after the mail) nor by where alike
	-- mails sit in the inbox (one taken moves the others). alike sales lost, doubled, or one not kept
	local function Same(x, v, count)
		return x.item == v.item and (x.count or 1) == count and (not v.bid or x.price == nil or x.price == v.bid)
	end
	for _, m in ipairs(box.mails or {}) do
		local v = m.invoice
		if type(v) == "table" and (v.kind == "seller" or v.kind == "seller_temp_invoice") and v.item then
			local count = v.count or 1
			-- (a mail with no time left told: when it was first seen, carried from read to read, stands in)
			local exp = (type(m.expires) == "number" and m.expires) or (type(m.first) == "number" and m.first + MA.KEEP_DAYS * 86400) or nil
			local s, best
			-- this mail's sale, kept before: the one whose mail runs out when this one does (the nearest, each once)
			if exp then
				for _, x in ipairs(list) do
					if not used[x] and x.mailExp and Same(x, v, count) then
						local d = math.abs(x.mailExp - exp)
						if d <= MA.MAIL_SAME and (not best or d < best) then s, best = x, d end
					end
				end
			end
			-- (its "Sale Pending" mail read before this one, an hour earlier: that sale, moving to this mail's time)
			if not s and v.kind == "seller" then
				for i = #list, 1, -1 do
					local x = list[i]
					if not used[x] and x.invKind == "seller_temp_invoice" and Same(x, v, count) then
						s = x
						-- (what you got: the real mail's, the pending one has no cut yet)
						if v.bid then s.price, s.net = v.bid, v.bid + (v.deposit or 0) - (v.cut or 0) end
						changed = true
						break
					end
				end
			end
			-- (kept before 0.63.7: named by item, count, price and buyer; it takes this mail's time once)
			if not s then
				for i = #list, 1, -1 do
					local x = list[i]
					if not used[x] and not x.mailExp and type(x.inv) == "string" and Same(x, v, count) then s = x break end
				end
			end
			if not s then
				-- a sale kept from the news, not matched to its mail yet: the same item and count first, else the same item
				-- (a stack bought in part); the oldest first (sales are mailed in order)
				for pass = 1, 2 do
					for i = #list, 1, -1 do
						local x = list[i]
						if not used[x] and not x.inv and x.item == v.item and (pass == 2 or (x.count or 1) == count)
							and (x.at or 0) <= (m.first or now) + 60 then s = x break end
					end
					if s then break end
				end
				if not s then
					-- when it sold: the sale's mail lasts MA.KEEP_DAYS from when it came, an hour after the sale
					local at = m.first or now
					if v.kind == "seller" and m.expires then at = m.expires - MA.KEEP_DAYS * 86400 - MA.AUCTION_KEEP end
					at = math.min(at, now)
					if now - at < MA.SOLD_KEEP then
						s = { item = v.item, at = at, seen = "mail" }
						local pos = #list + 1 -- (newest first)
						for i, x in ipairs(list) do if (x.at or 0) < at then pos = i break end end
						table.insert(list, pos, s)
						while #list > MA.MAX_SOLD do table.remove(list) end
						n = n + 1
					end
				end
				if s then
					s.count = count
					if v.bid then s.price, s.each = v.bid, nil end
					if v.bid then s.net = v.bid + (v.deposit or 0) - (v.cut or 0) end
					s.link = s.link or (m.items and m.items[1] and m.items[1].link) or nil
					changed = true
				end
			end
			if s then
				used[s] = true
				-- (its buyer when the game has the name: filled in, never taken away)
				if v.player and s.buyer ~= v.player then s.buyer, changed = v.player, true end
				if exp and s.mailExp ~= exp then s.mailExp, changed = exp, true end
				s.inv = s.inv or true
				if s.invKind ~= v.kind then s.invKind, changed = v.kind, true end
			end
		end
	end
	-- (kept twice between 0.63.0 and 0.63.2: once without its buyer, "item|count|price|#n", beside the one with it; the
	-- copy goes once its sale is matched to its mail)
	for i = #list, 1, -1 do
		local x = list[i]
		if not used[x] and not x.mailExp and type(x.inv) == "string" and x.inv:find("|#%d+$") then
			for y in pairs(used) do
				if y ~= x and y.buyer and y.item == x.item and (y.count or 1) == (x.count or 1) and y.price == x.price then
					table.remove(list, i)
					changed = true
					break
				end
			end
		end
	end
	if n > 0 or changed then Dirty() end
	return n
end

--- An auction of yours is no longer on the auction house (sold, expired, cancelled, gone from the Auctions tab's list,
--- mailed back: `why`; sold: kept as a sale, MA.KeepSale): noted (db.auctionsEnded, kept MA.POSTED_KEEP) and no longer kept as posted; @stored and @auction
--- hear of it. True when it wasn't noted before.
function MA.Over(id, why, now, item)
	id = Num(id)
	local posted, ended = Mine("auctionsPosted"), Mine("auctionsEnded")
	if not (id and ended) then return false end
	local a = posted and posted[id]
	if posted then posted[id] = nil end
	if ended[id] then return false end
	ended[id] = now or Now()
	if why == "sold" then MA.KeepSale(id, a, ended[id], item) end -- (`item`: the news's name for it)
	ns:Trace(("mail: auction %s%s is over (%s)"):format(tostring(id), a and (" (" .. tostring(a.name) .. " x" .. tostring(a.count or 1) .. ")") or "",
		tostring(why)))
	ns:Changed("stored")
	Dirty()
	return true
end

--- Mail sent to someone not one of your characters: kept an hour on your character's list.
function MA.KeepSent(s)
	MA.Prune() -- (on every write: what's past its time goes even when @mail is never looked at)
	local list = Mine("mailSent")
	if not list then return nil end
	table.insert(list, 1, { to = s.to, at = s.at, mail = s.mail })
	while #list > MA.MAX_MAILS do table.remove(list) end
	Dirty()
	ns:Trace("mail: sent to " .. s.to .. " (not one of your characters): kept an hour as on its way")
	return list[1]
end

-- the news, as Enum.AuctionHouseNotification numbers it (Forever's AuctionHouseEnumsDocumentation)
local NOTIFIED = { [2] = "won", [3] = "outbid", [4] = "sold", [5] = "expired" }
local function NotificationKind(n)
	local E = _G.Enum and _G.Enum.AuctionHouseNotification
	if E then
		return (n == E.AuctionWon and "won") or (n == E.AuctionOutbid and "outbid") or (n == E.AuctionSold and "sold")
			or (n == E.AuctionExpired and "expired") or nil
	end
	return NOTIFIED[n]
end

--- What an auction's item is: its id, link, quality and icon, from an id or link known, else from its name (the client
--- knows an item by name once the auction house has shown it). Each nil when not known.
function MA.ItemFacts(id, link, name)
	local CI = C_Item
	id, link = Num(id), Str(link)
	if not (id or link) and Str(name) and CI and CI.GetItemInfo then
		local _, l = Safe(CI.GetItemInfo, name)
		link = Str(l)
	end
	if not id and link then id = tonumber(link:match("item:(%d+)")) end
	if not id then return nil, link end
	local icon = CI and CI.GetItemIconByID and Safe(CI.GetItemIconByID, id)
	local q = CI and CI.GetItemQualityByID and Num(Safe(CI.GetItemQualityByID, id))
	if not q and link then q = tonumber(link:match("|cnIQ(%d+):")) end
	if type(icon) ~= "number" and type(icon) ~= "string" then icon = nil end
	return id, link, q, icon
end

-- what a piece of news is about, written on it: its item's facts once known
local function Learn(a)
	local id, link, q, icon = MA.ItemFacts(a.id, a.link, a.item)
	a.id, a.link = id or a.id, link or a.link
	a.q, a.icon = q or a.q, icon or a.icon
end

--- A bid or buyout placed (C_AuctionHouse.PlaceBid, hooked after it runs): the auction's item and what you offered, kept
--- for the news that you won it (whose notification names only the item).
function MA.OnBid(auctionID, amount)
	auctionID = Num(auctionID)
	local AH = C_AuctionHouse
	if not (auctionID and AH and AH.GetAuctionInfoByID) then return nil end
	local info = Safe(AH.GetAuctionInfoByID, auctionID)
	if type(info) ~= "table" then return nil end
	local link = Str(info.itemLink)
	local key = type(info.itemKey) == "table" and info.itemKey or nil
	MA.Prune()
	local bids = Mine("auctionBids")
	if not bids then return nil end
	local b = { id = key and Num(key.itemID), link = link, price = Num(amount) or Num(info.buyoutAmount), t = Now() }
	bids[auctionID] = b
	return b
end

--- A commodity bought (COMMODITY_PURCHASED: no auction id): news that it's on its way, its item known by id. The game's
--- own "won" notification, if it tells it too, is the same news (MA.OnAuction folds them).
function MA.OnCommodity(itemID, quantity)
	itemID = Num(itemID)
	if not itemID then return nil end
	local CI = C_Item
	local name = CI and CI.GetItemNameByID and Str(Safe(CI.GetItemNameByID, itemID))
	if not name then return nil end
	return MA.OnAuction("won", name, nil, nil, { id = itemID, count = Num(quantity) })
end

--- The auction house's news: an entry on your character's list (one told twice within MA.SAME is one), its item's
--- icon and quality learned (your bid, a commodity bought, your post, else its name: MA.ItemFacts). `extra`: what a
--- commodity purchase says ({ id, count }).
function MA.OnAuction(kind, item, auctionID, now, extra)
	item = Str(item)
	if not (kind and item) then return nil end
	now = now or Now()
	MA.Prune(now)
	auctionID = Num(auctionID)
	local list, key = Mine("mailAuctions")
	if not list then return nil end
	for _, a in ipairs(list) do
		if a.kind == kind and a.item == item and math.abs(now - (a.at or 0)) < MA.SAME
			and (not auctionID or not a.auctionID or a.auctionID == auctionID) then
			a.auctionID = a.auctionID or auctionID
			-- (told first by a chat line, which has no id: its price from the post, read before MA.Over lets go of it)
			local kept = auctionID and Store("auctionsPosted")[key]
			kept = kept and kept[auctionID]
			if kept and a.price == nil and a.each == nil then
				a.link, a.price, a.each, a.count, a.seen = a.link or kept.link, kept.price, kept.each, a.count or kept.count, a.seen or kept.seen
			end
			if extra then a.id, a.count = a.id or extra.id, a.count or extra.count end
			if not a.icon then Learn(a) end
			if auctionID and (kind == "sold" or kind == "expired") then MA.Over(auctionID, kind, now, item) end
			return a
		end
	end
	local posted = auctionID and Store("auctionsPosted")[key]
	posted = posted and posted[auctionID]
	local bid = auctionID and Store("auctionBids")[key]
	bid = bid and bid[auctionID]
	local a = { kind = kind, item = item, at = now, auctionID = auctionID }
	if posted then a.link, a.price, a.each, a.count, a.seen = posted.link, posted.price, posted.each, posted.count, posted.seen end
	if bid and kind == "won" then a.id, a.link, a.price, a.seen = bid.id, a.link or bid.link, bid.price, "bid" end
	if extra then a.id, a.count = a.id or extra.id, a.count or extra.count end
	Learn(a)
	table.insert(list, 1, a)
	while #list > MA.MAX_MAILS do table.remove(list) end
	-- (yours sold or expired: off the auction house; a sale kept too, with no id by its name)
	if auctionID and (kind == "sold" or kind == "expired") then MA.Over(auctionID, kind, now, item)
	elseif kind == "sold" then MA.KeepSale(nil, nil, now, item) end
	Dirty()
	ns:Trace(("mail: auction %s: %s%s"):format(kind, item, posted and (" (its price kept: " .. Money(posted.price or posted.each or 0, true) .. ")")
		or (auctionID and " (not seen posted)" or "")))
	return a
end

-- the classic chat lines ("A buyer has been found for your auction of %s."), as the game's own strings say them
local CHAT_NEWS = { sold = "ERR_AUCTION_SOLD_S", won = "ERR_AUCTION_WON_S", outbid = "ERR_AUCTION_OUTBID_S",
	expired = "ERR_AUCTION_EXPIRED_S" }
local chatPatterns
function MA.ChatNews(text)
	if type(text) ~= "string" or ns.Secret(text) then return nil end
	if not chatPatterns then
		chatPatterns = {}
		for kind, global in pairs(CHAT_NEWS) do
			local g = Str(_G[global])
			if g and g:find("%%%d*%$?s") then chatPatterns[kind] = Pattern(g) end
		end
	end
	for kind, p in pairs(chatPatterns) do
		local item = text:match(p)
		if item then return kind, item end
	end
	return nil
end
MA.ResetChatForTests = function() chatPatterns = nil end

-- posts waiting for the game's word that each was made, in order
local pendingPosts = {}

-- the auction house's durations as its post window names them (AUCTION_DURATION_ONE..THREE: "12 Hours"...): the
-- client's own strings, read for their hours (this client's may not be retail's)
local DURATIONS = { "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }
--- How long an auction posted with that duration runs (s), or nil when the game's string doesn't say.
function MA.DurationSeconds(i)
	local s = Str(_G[DURATIONS[Num(i) or 0] or ""])
	local h = s and tonumber(s:match("(%d+)"))
	return h and h * 3600 or nil
end

--- An auction being posted (C_AuctionHouse.PostItem / PostCommodity, hooked after they run): its price and how long it
--- runs kept until the game says it was made (AUCTION_HOUSE_AUCTION_CREATED with its id).
function MA.OnPost(location, quantity, bid, buyout, unitPrice, duration)
	local link = C_Item and C_Item.GetItemLink and Str(Safe(C_Item.GetItemLink, location)) or nil
	local name = (C_Item and C_Item.GetItemName and Str(Safe(C_Item.GetItemName, location))) or NameOfLink(link)
	quantity, bid, buyout, unitPrice = Num(quantity) or 1, Num(bid), Num(buyout), Num(unitPrice)
	local p = { link = link, name = name, count = quantity, price = buyout or bid, each = unitPrice, at = Now(), seen = "posted",
		runs = MA.DurationSeconds(duration) }
	pendingPosts[#pendingPosts + 1] = p
	while #pendingPosts > 50 do table.remove(pendingPosts, 1) end
	return p
end

--- A post the game refused (AUCTION_HOUSE_POST_ERROR, AUCTION_HOUSE_SHOW_ERROR): the last one waiting is no auction, and
--- the next one made isn't given its price (release review: a refused post stayed in line for 30 s).
function MA.PostFailed()
	local p = pendingPosts[#pendingPosts]
	if p and Now() - p.at <= MA.POST_WAIT then table.remove(pendingPosts) end
end
function MA.PendingPosts() return #pendingPosts end -- (tests)

function MA.AuctionCreated(auctionID)
	local now = Now()
	while pendingPosts[1] and now - pendingPosts[1].at > MA.POST_WAIT do table.remove(pendingPosts, 1) end
	local p = table.remove(pendingPosts, 1)
	auctionID = Num(auctionID)
	if not (p and auctionID) then return nil end
	MA.Prune()
	local posted = Mine("auctionsPosted")
	if not posted then return nil end
	p.t, p.at = p.at, nil
	p.ends, p.runs = p.runs and (p.t + p.runs) or nil, nil -- (when it runs out: the Auctions tab's list says it exactly)
	posted[auctionID] = p
	ns:Changed("auctions")
	return p
end

--- The Auctions tab's list (OWNED_AUCTIONS_UPDATED): every auction of yours on the auction house. Each one's price kept
--- (one posted before Terminal watched too; one kept without a price, or with another item's, put right from the list:
--- 0.56.12, a player's auction up with no price) and when it runs out; one sold is over (and kept as a sale), and one
--- kept as posted that the list doesn't have is over (paid out, expired, cancelled), unless the list couldn't be read
--- whole. How many were new.
function MA.ReadOwned()
	local AH = C_AuctionHouse
	if not (AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return 0 end
	MA.Prune()
	local posted, ended = Mine("auctionsPosted"), Mine("auctionsEnded")
	if not (posted and ended) then return 0 end
	local n = Num(Safe(AH.GetNumOwnedAuctions))
	if not n then return 0 end
	local SOLD = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold
	local now, kept, listed, whole = Now(), 0, {}, true
	for i = 1, n do
		local info = Safe(AH.GetOwnedAuctionInfo, i)
		local id = type(info) == "table" and Num(info.auctionID)
		if not id then
			whole = false
		else
			listed[id] = true
			local sold = SOLD ~= nil and info.status == SOLD
			local link = Str(info.itemLink)
			-- (the list's price is for one: x16 at 19c each says 19c, a player saw in game. What the auction brings is
			-- that times how many)
			local each = Num(info.buyoutAmount) or Num(info.bidAmount)
			local count = Num(info.quantity) or 1
			local price = each and each * count
			-- (a commodity's entry may have no link: its name by its item id; release review)
			local key = type(info.itemKey) == "table" and Num(info.itemKey.itemID) or nil
			local function Listed()
				local name = NameOfLink(link) or (key and C_Item and C_Item.GetItemNameByID and Str(Safe(C_Item.GetItemNameByID, key)))
				return { link = link, name = name, id = key, count = count, price = price, each = each, t = now, seen = "listed" }
			end
			-- the list's price is the game's own: it puts right one kept from the post (or kept for the whole, before 0.63.1)
			local function Priced(a)
				local was, is = a and (ItemIDOf(a.link) or a.id), ItemIDOf(link) or key
				if a and each and (not was or not is or was == is) then a.each, a.price, a.count = each, price, count end
			end
			if sold then
				if not posted[id] and not ended[id] then posted[id] = Listed() else Priced(posted[id]) end -- (for the sale)
				MA.Over(id, "sold", now)
			else
				if not posted[id] and ended[id] then ended[id] = nil end -- (listed as up after all: up)
				local a = posted[id]
				if not a then
					a = Listed()
					posted[id] = a
					kept = kept + 1
				else
					-- another item's facts (a post matched to the wrong auction): the list's own; no price: the list's
					local was, is = ItemIDOf(a.link), ItemIDOf(link)
					if was and is and was ~= is then
						local t = a.t
						a = Listed()
						a.t = t
						posted[id] = a
					else
						if not (a.price or a.each) and price then a.seen = "listed" end
						Priced(a)
					end
				end
				local left = Num(info.timeLeftSeconds)
				if left then a.ends = now + left end
			end
		end
	end
	if whole then
		for id in pairs(posted) do
			if not listed[id] then MA.Over(id, "not on the Auctions tab any more", now) end
		end
	end
	ns:Changed("auctions")
	return kept
end

--- Hooks the auction house's posting (after it runs; the post itself stays the game's). True once hooked.
function MA.HookPost()
	if MA.postHooked then return true end
	local AH = C_AuctionHouse
	if type(_G.hooksecurefunc) ~= "function" or type(AH) ~= "table" then return false end
	if type(AH.PostItem) == "function" then
		_G.hooksecurefunc(AH, "PostItem", function(loc, duration, quantity, bid, buyout) pcall(MA.OnPost, loc, quantity, bid, buyout, nil, duration) end)
	end
	if type(AH.PostCommodity) == "function" then
		_G.hooksecurefunc(AH, "PostCommodity", function(loc, duration, quantity, unitPrice) pcall(MA.OnPost, loc, quantity, nil, nil, unitPrice, duration) end)
	end
	-- (and buying: a bid or buyout's auction, for the news that you won it)
	if type(AH.PlaceBid) == "function" then
		_G.hooksecurefunc(AH, "PlaceBid", function(auctionID, amount) pcall(MA.OnBid, auctionID, amount) end)
	end
	MA.postHooked = true
	return true
end

--- A mailbox read on your character: news the inbox now holds is dropped (won, outbid and expired mail come at once;
--- a sale once the inbox has its auction mail), and auctions the inbox shows came back are noted as over
--- (MA.EndedFromMail).
function MA.SettleAuctions(box, now)
	MA.EndedFromMail(box, now)
	MA.SalesFromMail(box, now)
	local list = Mine("mailAuctions")
	if not (list and box) then return end
	-- each sold item's newest sale mail, by when the inbox first had it
	local soldItems = {}
	for _, m in ipairs(box.mails or {}) do
		if m.auction == "sold" or m.auction == "pending" then
			local item = (m.invoice and m.invoice.item) or (m.subject and m.subject:match(":%s*(.+)$"))
			local first = m.first or now
			if item and first > (soldItems[item] or -1) then soldItems[item] = first end
		end
	end
	for i = #list, 1, -1 do
		local a = list[i]
		local mailed = a.kind == "sold" and soldItems[a.item]
		if (a.kind ~= "sold" and (a.at or 0) <= now) or (mailed and mailed >= (a.at or 0)) then table.remove(list, i) end
	end
end

-- 0.48.9 (the player: 200 arrows from an auction that failed, mailed back and taken, still showed in @stored as on the
-- auction house): the game told addons the auction was made (AUCTION_HOUSE_AUCTION_CREATED) and nothing when it came
-- back, so Syndicator's record (what @stored reads) kept it until the next visit to the auction house. Terminal sees the
-- mail that brought it back: the game's own mail (no one to reply to, or an expired or cancelled auction's subject)
-- carrying an auction's item, as many as it held, and not in the inbox before the auction was made. That auction is
-- noted as over (db.auctionsEnded, kept MA.POSTED_KEEP), and @stored leaves it out (Stored.lua's EndedAuctions).
local RETURNED = { expired = true, cancelled = true }

--- Auctions of yours the inbox shows came back: noted as over, no longer kept as posted. How many.
function MA.EndedFromMail(box, now)
	local posted = Mine("auctionsPosted")
	if not (posted and box and next(posted)) then return 0 end
	local used, n = {}, 0
	-- (the ones whose time ran out first, then the oldest: of two alike, the one that came back is the one that ended)
	now = now or Now()
	local order = {}
	for id, a in pairs(posted) do order[#order + 1] = id end
	local function Ended(a) return type(a.ends) == "number" and a.ends <= now end
	table.sort(order, function(x, y)
		local a, b = posted[x], posted[y]
		local ea, eb = Ended(a), Ended(b)
		if ea ~= eb then return ea end
		local ta, tb = tonumber(a.t) or 0, tonumber(b.t) or 0
		if ta ~= tb then return ta < tb end
		return tostring(x) < tostring(y)
	end)
	for _, id in ipairs(order) do
		local a = posted[id]
		local want, wantID = Num(a.count) or 1, ItemIDOf(a.link)
		for i, m in ipairs(box.mails or {}) do
			if not used[i] and m.items and (RETURNED[m.auction] or (m.game and not m.auction))
				and not (m.first and m.first < (a.t or 0)) then -- (mail there before the auction was made isn't its return)
				local got = 0
				for _, it in ipairs(m.items) do
					if (wantID and it.id == wantID) or (not wantID and a.name and it.name == a.name) then got = got + (it.count or 1) end
				end
				if got >= want then
					used[i] = true
					if MA.Over(id, "it came back by mail", now) then n = n + 1 end
					break
				end
			end
		end
	end
	return n
end

--- Every auction of your characters' that Terminal saw come back: { [auctionID] = true }.
function MA.EndedAuctions()
	MA.Prune()
	local out = {}
	for _, kept in pairs(Store("auctionsEnded")) do
		for id in pairs(kept) do out[id] = true end
	end
	return out
end

-- (MailRows.lua's: the rows, the question, the login warning and the events are made from these)
MA._ = { Boxes = Boxes, Dirty = Dirty, Store = Store, NotificationKind = NotificationKind }

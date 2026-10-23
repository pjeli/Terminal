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
-- Mail on its way (0.47.2, the player's ask): mail you send to anyone who isn't one of your characters is kept for an
-- hour (MA.SENT_KEEP: what mail with items or gold takes between accounts), and the auction house's news as the game
-- tells it (AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION: sold, won, outbid, expired; the classic chat lines too): a sold
-- auction's gold due about an hour later, with its price when Terminal saw the auction posted (C_AuctionHouse.PostItem
-- / PostCommodity hooked, then AUCTION_HOUSE_AUCTION_CREATED; or the Auctions tab's list, OWNED_AUCTIONS_UPDATED).

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

local function Boxes()
	if not ns.db then return nil end
	if type(ns.db.mailboxes) ~= "table" then ns.db.mailboxes = {} end
	return ns.db.mailboxes
end

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
	-- after it was made (MA.EndedFromMail)
	-- (the same mail: alike and running out when this one does, each read mail matched once. 0.63.7, review: a new mail
	-- alike an older one, an auction's arrows back a second time, took the older one's time, and the auction it ended
	-- was never seen as over)
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

--- MAIL_FAILED: the send didn't go, unless a confirmation comes or came (0.47.5, the player: mail to "Cai Te" not
--- kept, no trace at all: dropping the send at MAIL_FAILED lost one the game then sent once you'd confirmed it).
function MA.SendFailed()
	if not pendingSend then return end
	pendingSend.failed = true
	ns:Trace("mail: the game said the send failed" .. (pendingSend.confirm and " (a confirmation is open: kept)" or ""))
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

--- An auction of yours sold (0.56.12, a player: "auctions" listed what's up and what failed, never what sold): kept
--- MA.SOLD_KEEP on your character's list of sales (db.auctionsSold), newest first, each auction once. `a`: what was kept
--- of it posted (its price, its count); `item`: its name when nothing was (the news names it). The sale's mail tells the
--- buyer and what you got (MA.SalesFromMail).
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
			-- (and what was kept of it posted, which the chat line didn't have; review, 0.57.7)
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
	-- second whatever is read when): not by its buyer (the game can give it a moment after the mail) nor by where
	-- alike mails sit in the inbox (one taken moves the others). 0.63.7, review: alike sales lost, doubled, or one
	-- not kept
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
	ns:Trace(("mail: auction %d%s is over (%s)"):format(id, a and (" (" .. tostring(a.name) .. " x" .. tostring(a.count or 1) .. ")") or "",
		tostring(why)))
	ns:Changed("stored")
	Dirty()
	return true
end

--- Mail sent to someone not one of your characters: kept an hour on your character's list.
function MA.KeepSent(s)
	MA.Prune() -- (on every write: what's past its time goes even when @mail is never looked at; review, 0.48.6)
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

--- What an auction's item is (0.48.4, the player: what you bought should show its own icon and quality): its id, link,
--- quality and icon, from an id or link known, else from its name (the client knows an item by name once the auction
--- house has shown it). Each nil when not known.
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
			-- (told first by a chat line, which has no id: its price from the post, read before MA.Over lets go of it;
			-- review, 0.57.7)
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

-- posts waiting for the game's word that each was made, in order (0.56.12: one slot, two posted at once gave the first
-- the second's price, and the second none)
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
			-- (the list's price is for one: x16 at 19c each says 19c, a player saw in game; 0.63.1. What the auction
			-- brings is that times how many)
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
	-- each sold item's newest sale mail, by when the inbox first had it (0.49.2, review: an older sale's mail still in
	-- the inbox dropped the news of a new sale whose gold hadn't come yet)
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
	-- (the ones whose time ran out first, then the oldest: of two alike, the one that came back is the one that ended;
	-- 0.50.7, review: pairs' order could mark the one still up as over)
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

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local ICON_BOX, ICON_MAIL = "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Letter_01"
local ICON_MONEY, ICON_COD = "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Letter_03"
local ICON_AUCTION = "Interface\\Icons\\INV_Hammer_15"
local RED, ORANGE, GREY = "|cffff4040", "|cffff9933", "|cff9d9d9d"
local AUCTION_LABEL = { sold = L["Sold"], won = L["Won"], outbid = L["Outbid"], expired = L["Expired"] } -- (the auction house's news)

local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

--- The name a mail goes by: its subject, else its first item's, else "(no subject)".
local function Title(m)
	if m.subject then return m.subject end
	local first = m.items and m.items[1]
	return (first and (first.name or NameOfLink(first.link))) or L["(no subject)"]
end

local function ItemName(it) return it.name or NameOfLink(it.link) or L["item %s"]:format(tostring(it.id)) end

--- A mail's first item's icon and quality colour (0.48.4: a mail is drawn as what it carries, as every item row is; the
--- inbox may have given neither, the client not having the item yet: asked by its id).
local function FirstItemLook(m)
	local first = m.items and m.items[1]
	if not first then return nil, nil end
	local icon, q = first.icon, first.q
	if first.id and not (icon and q) then
		local _, _, q2, icon2 = MA.ItemFacts(first.id, first.link)
		icon, q = icon or icon2, q or q2
	end
	return icon, ns.QualityHex(q)
end
--- What running out does: "deleted", or "back to Bob".
local function Fate(m) return m.deletes and L["deleted"] or L["back to %s"]:format(m.from or L["its sender"]) end

--- A mail's time left, coloured as the inbox does it (red under a day; orange under MA.SOON).
local function LeftText(left)
	local s = L["%s left"]:format(MA.Left(left))
	if left < 86400 then return RED .. s .. "|r" end
	if left < MA.SOON then return ORANGE .. s .. "|r" end
	return s
end

--- "Sold Copper Bar x20 to Bob: 45g (deposit back, cut taken)" and the like, from the auction house's invoice.
local function InvoiceText(v)
	if not v then return nil end
	local item = (v.item or "?") .. (((v.count or 1) > 1) and (" x" .. v.count) or "")
	local net = (v.bid or 0) + (v.deposit or 0) - (v.cut or 0)
	if v.kind == "buyer" then
		if v.player then return L["Bought %s from %s for %s"]:format(item, v.player, Money(v.bid or 0, true)) end
		return L["Bought %s for %s"]:format(item, Money(v.bid or 0, true))
	elseif v.kind == "seller" then
		if v.player then
			return L["Sold %s to %s: %s (%s, deposit %s back, cut %s)"]:format(item, v.player,
				Money(net, true), Money(v.bid or 0, true), Money(v.deposit or 0, true), Money(v.cut or 0, true))
		end
		return L["Sold %s: %s (%s, deposit %s back, cut %s)"]:format(item,
			Money(net, true), Money(v.bid or 0, true), Money(v.deposit or 0, true), Money(v.cut or 0, true))
	elseif v.kind == "seller_temp_invoice" then
		local eta = (v.etaH and v.etaM) and (" " .. L["(the gold comes about %02d:%02d, server time)"]:format(v.etaH, v.etaM)) or ""
		if v.player then return L["Sold %s to %s: %s on its way%s"]:format(item, v.player, Money(net, true), eta) end
		return L["Sold %s: %s on its way%s"]:format(item, Money(net, true), eta)
	end
	return nil
end

local list, boxRows -- (the last collect's rows; box rows by box key)

local function Who(box, myRealm)
	local who = box.name or "?"
	if box.realm and myRealm and box.realm ~= myRealm then who = who .. "-" .. box.realm end
	return who
end

--- A mail's lines for chat: "  From Bob: Auction successful: Copper Bar  ·  45g  ·  2 days left (deleted)".
local function MailLine(e)
	local m = e.mail
	local parts = { m.from and L["From %s: %s"]:format(m.from, Title(m)) or Title(m) }
	if m.money then parts[#parts + 1] = Money(m.money) end
	if m.cod then parts[#parts + 1] = L["COD %s"]:format(Money(m.cod)) end
	if m.items then
		local names = {}
		for _, it in ipairs(m.items) do names[#names + 1] = (it.link or ItemName(it)) .. ((it.count or 1) > 1 and (" x" .. it.count) or "") end
		parts[#parts + 1] = table.concat(names, ", ")
	end
	parts[#parts + 1] = L["%s left (%s)"]:format(MA.Left(e.left), Fate(m))
	return "  " .. table.concat(parts, ns.DETAIL_SEP)
end

local function BoxLines(key)
	local box = boxRows and boxRows[key]
	if not box then return { L["No mail kept for that character."] } end
	local out = { (box.color or "") .. box.who .. (box.color and "|r" or "") .. ": " .. box.detail }
	for _, e in ipairs(list or {}) do
		if e.mailKind == "mail" and e.boxKey == key then out[#out + 1] = MailLine(e) end
	end
	return out
end

--- Where a mail sits in the open inbox: its index, or nil (another character's, the mailbox closed, taken already).
function MA.InboxIndex(e)
	if not (MA.open and e.mail and e.boxKey == MyKey()) then return nil end
	local n = Num(Safe(GetInboxNumItems)) or 0
	local want, now = e.sig, Now()
	for i = 1, n do
		local m = MA.ReadMail(i, now)
		if m and MA.Sig(m) == want then return i end
	end
	return nil
end

--- Enter at an open mailbox: points at the mail in the inbox (Terminal only reads the inbox and highlights: turning its
--- pages would be Terminal's code writing into the window). True when it said something.
function MA.PointAt(e)
	local i = MA.InboxIndex(e)
	if not i then return false end
	local page = math.floor((i - 1) / MA.PER_PAGE) + 1
	local inbox = _G.InboxFrame
	local shown = inbox and Num(rawget(inbox, "pageNum")) or 1
	if shown == page then
		local button = _G["MailItem" .. ((i - 1) % MA.PER_PAGE + 1) .. "Button"]
		if button and ns.Highlight then ns.Highlight:Show(button) end
		ns:Trace(("mail: %s is mail %d, on the page shown: pointed at"):format(Title(e.mail), i))
	else
		ns:Print(L["%s: on page %d of your inbox (page %d shows)."]:format(Title(e.mail), page, shown))
	end
	return true
end

-- a sent mail's or an auction's line: "  To Bob: Linen Cloth (20)  ·  1g  ·  sent 12 min ago"
local function WayLine(e) return "  " .. e.name .. ns.DETAIL_SEP .. (e.plain or "") .. (e.mine and "" or ("  " .. GREY .. "(" .. e.who .. ")|r")) end
MA.WayLine = WayLine

local function Show(e)
	if e.mailKind == "box" then ns:Output(BoxLines(e.boxKey)) return end
	if e.mailKind == "sent" or e.mailKind == "auction" then ns:Output({ WayLine(e) }) return end
	if MA.PointAt(e) then return end
	ns:Output({ MailLine(e) .. (e.mine and "" or ("  " .. GREY .. "(" .. e.who .. ")|r")) })
end

--- Shift+Enter: the nearest mailbox QuestieDB knows, pinned.
local function NearestMailbox()
	local I = ns.Integrations
	local here = I and I.Here and I.Here()
	local rows = here and I.NearestObjectRows and I.NearestObjectRows("mailbox", here)
	local top = rows and rows[1]
	if top and I.PinObject then
		I.PinObject(top)
	elseif not here then
		ns:Print(L["Your position isn't known here, so there's no nearest mailbox."])
	else
		ns:Print(L["No mailbox known near you."])
	end
end
MA.NearestMailbox = NearestMailbox

--- What's sent: "Mail from Bob: Auction successful: Copper Bar (45g, 2 days left)".
local function ShareText(e)
	if e.mailKind == "box" then return L["%s's mail: %s"]:format(e.who, e.plain or "") end
	if e.mailKind == "auction" and e.link then return (AUCTION_LABEL[e.news] or L["Auction"]) .. ": " .. e.link .. " (" .. (e.plain or "") .. ")" end
	if e.mailKind == "sent" or e.mailKind == "auction" then return e.name .. " (" .. (e.plain or "") .. ")" end
	local m = e.mail
	local bits = {}
	if m.money then bits[#bits + 1] = Money(m.money, true) end
	if m.cod then bits[#bits + 1] = L["COD %s"]:format(Money(m.cod, true)) end
	bits[#bits + 1] = L["%s left"]:format(MA.Left(e.left))
	if m.from then return L["Mail from %s: %s (%s)"]:format(m.from, Title(m), table.concat(bits, ", ")) end
	return L["Mail: %s (%s)"]:format(Title(m), table.concat(bits, ", "))
end

local AUCTION_SAID = {
	sold = L["The gold comes by mail about an hour after the sale, less the auction house's cut (and with your deposit back)."],
	won = L["The item comes by mail."], outbid = L["Your bid comes back by mail."], expired = L["The item comes back by mail."],
}

-- the tooltip's Shift+Enter, only where there is one: the nearest mailbox is Questie's (@mailbox), so without it Shift+Enter
-- does what Enter does (0.49.2, review: the tooltip promised a waypoint the footer, rightly, didn't)
local function ShiftHint()
	return ns.providers.mailbox and ("    " .. L["Shift+Enter: set a waypoint to the nearest mailbox"]) or ""
end

local function WayTooltip(e, t)
	if e.mailKind == "sent" then
		local m = e.mail
		t:SetText(e.title, 1, 0.82, 0)
		t:AddLine(e.mine and L["To %s, sent %s"]:format(e.to, ns.Ago(Now() - e.at)) or L["To %s, sent %s by %s"]:format(e.to, ns.Ago(Now() - e.at), e.who), 1, 1, 1)
		if m.money then t:AddDoubleLine(L["Gold"], Money(m.money), 1, 1, 1, 1, 1, 1) end
		if m.cod then t:AddDoubleLine(L["COD (they pay it when they take it)"], Money(m.cod), 1, 0.5, 0.5, 1, 1, 1) end
		for _, it in ipairs(m.items or {}) do
			local hex = ns.QualityHex(it.q)
			t:AddDoubleLine((hex or "") .. ItemName(it) .. (hex and "|r" or ""), (it.count or 1) > 1 and ("x" .. it.count) or "", 1, 1, 1, 1, 1, 1)
		end
		t:AddLine(L["Mail with items or gold to another account can take up to an hour to arrive: Terminal keeps it here for that hour."], 0.6, 0.8, 1, true)
	else
		t:SetText(e.name, 1, 0.82, 0)
		t:AddLine(("%s %s"):format(AUCTION_LABEL[e.news] or L["Auction"], ns.Ago(Now() - e.at)) .. (e.mine and "" or (" " .. L["on %s"]:format(e.who))), 1, 1, 1)
		if e.price then
			t:AddDoubleLine(e.each and L["Price each"] or L["Price"], Money(e.each or e.price), 1, 1, 1, 1, 1, 1)
			t:AddLine((e.seen == "listed" and L["(as the auction house listed it)"]) or (e.seen == "bid" and L["(what you bid or paid)"])
				or L["(as you posted it)"], 0.6, 0.6, 0.6)
		elseif e.news == "sold" then
			t:AddLine(L["Its price isn't known: Terminal didn't see it posted"], 0.6, 0.6, 0.6, true)
		end
		t:AddLine(AUCTION_SAID[e.news] or "", 0.6, 0.8, 1, true)
	end
	ns.KeyHints(t, L["Enter: show in chat"] .. ShiftHint(), 0.6, 0.6, 0.6)
end

local function Tooltip(e, t)
	if e.mailKind == "sent" or e.mailKind == "auction" then return WayTooltip(e, t) end
	if e.mailKind == "box" then
		t:SetText(L["%s's mail"]:format(e.who), 1, 0.82, 0)
		local n = 0
		for _, r in ipairs(list or {}) do
			if r.mailKind == "mail" and r.boxKey == e.boxKey then
				n = n + 1
				if n <= 12 then
					t:AddDoubleLine(Title(r.mail), (r.mail.money and (Money(r.mail.money) .. "  ") or "") .. LeftText(r.left), 1, 1, 1, 1, 1, 1)
				end
			end
		end
		if n > 12 then t:AddLine(L["+%d more"]:format(n - 12), 0.6, 0.6, 0.6) end
		if e.gone and e.gone > 0 then
			t:AddLine(L["%s ran out since (taken, deleted or sent back)"]:format(Plural(e.gone, L["mail"], L["mails"])), 0.6, 0.6, 0.6, true)
		end
		if e.more then t:AddLine(L["%d more waiting on the server (the inbox shows 50 at a time)"]:format(e.more), 0.6, 0.6, 0.6, true) end
		if e.newFrom then t:AddLine(L["New mail from %s"]:format(e.newFrom), 0.4, 1, 0.4, true) end
		if e.seen then t:AddLine(L["Mailbox last opened %s"]:format(ns.Ago(Now() - e.seen)), 0.6, 0.6, 0.6) end
		ns.KeyHints(t, L["Enter: show in chat"] .. ShiftHint(), 0.6, 0.6, 0.6)
		return
	end
	local m = e.mail
	t:SetText(Title(m), 1, 0.82, 0)
	t:AddLine(L["From %s"]:format(m.from or L["someone unknown"]) .. (m.returned and (" " .. L["(sent back to you)"]) or ""), 1, 1, 1)
	if not e.mine then t:AddLine(L["In %s's mailbox"]:format(e.who), 0.6, 0.8, 1) end
	if m.money then t:AddDoubleLine(L["Gold"], Money(m.money), 1, 1, 1, 1, 1, 1) end
	if m.cod then t:AddDoubleLine(L["COD (paid when you take it)"], Money(m.cod), 1, 0.5, 0.5, 1, 1, 1) end
	for _, it in ipairs(m.items or {}) do
		local hex = ns.QualityHex(it.q)
		t:AddDoubleLine((hex or "") .. ItemName(it) .. (hex and "|r" or ""),
			(it.count or 1) > 1 and ("x" .. it.count) or "", 1, 1, 1, 1, 1, 1)
	end
	local inv = InvoiceText(m.invoice)
	if inv then t:AddLine(inv, 0.8, 0.8, 0.8, true) end
	local after = m.deletes and ((m.money or m.items) and L["it's deleted with what's in it"] or L["it's deleted"])
		or L["it goes back to %s"]:format(m.from or L["its sender"])
	t:AddLine(L["%s, then %s"]:format(LeftText(e.left), after), 1, 1, 1, true)
	if m.sent then
		t:AddLine(L["You sent it %s; it shows here until %s opens a mailbox"]:format(ns.Ago(Now() - m.sent), e.who), 0.6, 0.8, 1, true)
	elseif not m.read then
		t:AddLine(L["Unread"], 0.4, 1, 0.4)
	end
	ns.KeyHints(t, ((MA.open and e.mine) and L["Enter: show it in the inbox"] or L["Enter: show in chat"])
		.. ShiftHint(), 0.6, 0.6, 0.6)
end

-- (every row's: shared, not a closure per row)
local function Secondary() return ns.providers.mailbox and NearestMailbox or nil end

local function MailRow(key, m, i, mine, who, now)
	local left = m.expires - now
	local soon = left < MA.SOON
	local d = {}
	if m.from then d[#d + 1] = L["from %s"]:format(m.from) end
	if m.sent then d[#d + 1] = L["you sent it %s"]:format(ns.Ago(now - m.sent)) end
	if m.money then d[#d + 1] = Money(m.money) end
	if m.cod then d[#d + 1] = RED .. L["COD"] .. "|r " .. Money(m.cod) end
	if m.items then
		local first = m.items[1]
		d[#d + 1] = #m.items == 1 and (ItemName(first) .. ((first.count or 1) > 1 and (" x" .. first.count) or ""))
			or Plural(#m.items, L["item"], L["items"])
	end
	d[#d + 1] = LeftText(left)
	if not mine then d[#d + 1] = GREY .. who .. "|r" end
	local words = { "mail inbox", m.from or "", m.subject or "" }
	for _, it in ipairs(m.items or {}) do words[#words + 1] = ItemName(it) end
	if m.money then words[#words + 1] = "gold money" end
	if m.cod then words[#words + 1] = "cod" end
	if m.returned then words[#words + 1] = "returned" end
	if not m.read then words[#words + 1] = "unread new" end
	if soon then words[#words + 1] = "expiring running out" end
	if m.auction then words[#words + 1] = "auction ah " .. m.auction end
	if m.sent then words[#words + 1] = "sent" end
	words[#words + 1] = who
	local e = {
		key = key .. ":" .. i .. ":" .. MA.Sig(m), name = Title(m), mail = m, mailKind = "mail", boxKey = key, who = who,
		mine = mine or nil, left = left, soon = soon or nil, sig = MA.Sig(m),
		icon = (m.items and m.items[1] and m.items[1].icon) or (m.cod and ICON_COD) or (m.money and ICON_MONEY) or ICON_MAIL,
		color = (left < 86400 and RED) or nil,
		detail = table.concat(d, ns.DETAIL_SEP), text = table.concat(words, " "),
		holders = { { who = who, mine = mine or nil, where = "mail", count = 1 } },
		tooltip = Tooltip, activate = Show, secondary = Secondary(), shareLink = ShareText,
	}
	-- (carrying an item: its icon and quality, as your bags show it; running out stays red in the time left)
	local icon, hex = FirstItemLook(m)
	if icon then e.icon = icon end
	if hex then e.color = hex end
	return e
end

local function BoxRow(key, box, mine, who, now, mails, gone, newFrom)
	local money, cods, soon, next = 0, 0, 0, nil
	for _, e in ipairs(mails) do
		money = money + (e.mail.money or 0)
		if e.mail.cod then cods = cods + 1 end
		if e.soon then soon = soon + 1 end
		if not next or e.left < next then next = e.left end
	end
	local d, plain = { Plural(#mails, L["mail"], L["mails"]) }, { Plural(#mails, L["mail"], L["mails"]) }
	if money > 0 then d[#d + 1] = Money(money); plain[#plain + 1] = Money(money, true) end
	if cods > 0 then d[#d + 1] = L["%d COD"]:format(cods); plain[#plain + 1] = L["%d COD"]:format(cods) end
	if soon > 0 then d[#d + 1] = ORANGE .. L["%d running out"]:format(soon) .. "|r" ; plain[#plain + 1] = L["%d running out soon"]:format(soon) end
	if next then d[#d + 1] = L["the next in %s"]:format(MA.Left(next)) end
	if box and box.more then d[#d + 1] = L["+%d on the server"]:format(box.more) end
	if newFrom then d[#d + 1] = "|cff40ff40" .. L["new mail"] .. "|r" end
	if box and box.t then d[#d + 1] = GREY .. L["opened %s"]:format(ns.Ago(now - box.t)) .. "|r"
	elseif box then d[#d + 1] = GREY .. L["no mailbox opened with Terminal yet"] .. "|r" end
	if not box then d = { "|cff40ff40" .. L["new mail"] .. "|r", GREY .. L["not opened with Terminal yet"] .. "|r" } end
	return {
		key = "box:" .. key, name = who, who = who, mailKind = "box", boxKey = key, mine = mine or nil,
		color = ns.ClassHex(box and box.class or (mine and select(2, Safe(UnitClass, "player")))),
		icon = ICON_BOX, detail = table.concat(d, ns.DETAIL_SEP), plain = table.concat(plain, ", "),
		text = "mail inbox mailbox " .. (mine and "you me mine" or "alt alts character") .. (money > 0 and " gold money" or "")
			.. (soon > 0 and " expiring running out" or ""),
		holders = { { who = who, mine = mine or nil, where = "mail", count = 1 } },
		gone = gone, more = box and box.more, newFrom = newFrom, seen = box and box.t,
		tooltip = Tooltip, activate = Show, secondary = Secondary(), shareLink = ShareText,
	}
end

--- Mail sent to someone not one of your characters, kept its hour: "To Bob: Linen Cloth (20)".
local function SentRow(key, s, i, mine, who, now)
	local m = s.mail or {}
	local title = Title(m)
	local d = {}
	if m.money then d[#d + 1] = Money(m.money, true) end
	if m.cod then d[#d + 1] = L["COD %s"]:format(Money(m.cod, true)) end
	if m.items then
		local first = m.items[1]
		d[#d + 1] = #m.items == 1 and (ItemName(first) .. ((first.count or 1) > 1 and (" x" .. first.count) or ""))
			or Plural(#m.items, L["item"], L["items"])
	end
	d[#d + 1] = L["sent %s"]:format(ns.Ago(now - s.at))
	local plain = table.concat(d, ", ")
	if not mine then d[#d + 1] = GREY .. who .. "|r" end
	local words = { "mail sent outgoing to", s.to, m.subject or "", who }
	for _, it in ipairs(m.items or {}) do words[#words + 1] = ItemName(it) end
	if m.money then words[#words + 1] = "gold money" end
	local icon, hex = FirstItemLook(m)
	return {
		key = "sent:" .. key .. ":" .. s.at .. ":" .. i, name = L["To %s: %s"]:format(s.to, title), title = title, to = s.to, at = s.at,
		mail = m, mailKind = "sent", boxKey = key, who = who, mine = mine or nil, color = hex,
		icon = icon or (m.money and ICON_MONEY) or ICON_MAIL,
		detail = table.concat(d, ns.DETAIL_SEP), plain = plain, text = table.concat(words, " "),
		tooltip = Tooltip, activate = Show, secondary = Secondary(), shareLink = ShareText,
	}
end

--- The auction house's news, kept its hour: "Sold: Linen Cloth", its gold due in about 40 min.
local function AuctionRow(key, a, i, mine, who, now)
	local d = {}
	if a.price then d[#d + 1] = a.each and L["%s each"]:format(Money(a.each, true)) or Money(a.price, true) end
	if a.kind == "sold" then
		local left = MA.AUCTION_KEEP - (now - a.at)
		d[#d + 1] = L["gold due in about %s"]:format(MA.Left(left))
	elseif a.kind == "won" then d[#d + 1] = L["on its way to your mailbox"]
	elseif a.kind == "outbid" then d[#d + 1] = L["your bid comes back by mail"]
	else d[#d + 1] = L["coming back by mail"] end
	d[#d + 1] = ns.Ago(now - a.at)
	local plain = table.concat(d, ", ")
	if not mine then d[#d + 1] = GREY .. who .. "|r" end
	-- (its item's own icon and quality: learned when the news came; news kept before that, or an item the client didn't
	-- have then, asked again here)
	local link, q, icon = a.link, a.q, a.icon
	if not (icon and q) then
		local _, l2, q2, icon2 = MA.ItemFacts(a.id, a.link, a.item)
		link, q, icon = link or l2, q or q2, icon or icon2
	end
	return {
		key = "ah:" .. key .. ":" .. a.at .. ":" .. i, name = (AUCTION_LABEL[a.kind] or L["Auction"]) .. ": " .. a.item
			.. (((a.count or 1) > 1) and (" x" .. a.count) or ""),
		news = a.kind, at = a.at, price = a.price, each = a.each, seen = a.seen, link = link,
		money = (a.kind == "sold" and a.price) or nil, auction = a,
		mailKind = "auction", boxKey = key, who = who, mine = mine or nil, color = ns.QualityHex(q),
		icon = icon or (a.kind == "sold" and ICON_MONEY) or ICON_AUCTION,
		detail = table.concat(d, ns.DETAIL_SEP), plain = plain,
		text = "mail auction auctions ah incoming pending expected " .. a.kind .. " " .. a.item .. (a.kind == "sold" and " gold money" or "") .. " " .. who,
		holders = { { who = who, mine = mine or nil, where = "auctions", count = a.count or 1 } }, -- (on:)
		tooltip = Tooltip, activate = Show, secondary = Secondary(), shareLink = ShareText,
	}
end

--- Unread mail the game says is waiting for you (anywhere: the minimap's letter), and from whom.
local function NewMail()
	if Safe(_G.HasNewMail) ~= true then return nil end
	local names = {}
	for _, n in ipairs({ Safe(_G.GetLatestThreeSenders) }) do
		if Str(n) then names[#names + 1] = n end
	end
	return #names > 0 and table.concat(names, ", ") or L["someone"]
end

--- Who a character is, by its GUID: its mailbox's name, yours, an alt's name Terminal noted, else "an alt".
function MA.WhoOf(key)
	local boxes, myRealm = Boxes() or {}, Str(Safe(GetRealmName))
	local box = boxes[key]
	if type(box) == "table" then return Who(box, myRealm) end
	if key == MyKey() then return ns.CharacterName() or Str(Safe(UnitName, "player")) or L["You"] end
	local xp = ns.db and type(ns.db.xpChars) == "table" and ns.db.xpChars[key]
	return (type(xp) == "table" and Str(xp.name)) or L["an alt"]
end

-- newest first; one character's told in order (the newer first)
local function NewerFirst(a, b)
	if a.at ~= b.at then return a.at > b.at end
	if a.boxKey == b.boxKey and a._order ~= b._order then return a._order < b._order end
	return a.name < b.name
end

--- The auction house's news kept on your characters (sold, won, outbid, expired: each kept its hour), newest first, as
--- rows: @auction lists them (Auctions.lua), and "incoming mail" and .mail read them too.
function MA.NewsRows(now)
	now = now or Now()
	MA.Prune(now)
	local myKey, rows = MyKey(), {}
	for key, list in pairs(Store("mailAuctions")) do
		for i, a in ipairs(list) do
			local e = AuctionRow(key, a, i, key == myKey, MA.WhoOf(key), now)
			e._order = i
			rows[#rows + 1] = e
		end
	end
	table.sort(rows, NewerFirst)
	return rows
end

function MA.Collect()
	local boxes = Boxes() or {}
	local myKey, now = MyKey(), Now()
	local myRealm = Str(Safe(GetRealmName))
	local rows, mailRows, byKey = {}, {}, {}
	local keys = {}
	for key, box in pairs(boxes) do
		if type(box) == "table" and type(box.mails) == "table" then keys[#keys + 1] = key end
	end
	local newFrom = NewMail()
	if myKey and newFrom and not boxes[myKey] then keys[#keys + 1] = myKey end -- (new mail, no note yet)
	local function Order(a, b)
		if (a == myKey) ~= (b == myKey) then return a == myKey end
		return tostring(boxes[a] and boxes[a].name) < tostring(boxes[b] and boxes[b].name)
	end
	table.sort(keys, Order)
	for _, key in ipairs(keys) do
		local box, mine = boxes[key], key == myKey
		local who = box and Who(box, myRealm) or (ns.CharacterName() or Str(Safe(UnitName, "player")) or L["You"])
		local mails, gone = {}, 0
		for i, m in ipairs(box and box.mails or {}) do
			if type(m) == "table" and type(m.expires) == "number" then
				if m.expires > now then mails[#mails + 1] = MailRow(key, m, i, mine, who, now) else gone = gone + 1 end
			end
		end
		local b = BoxRow(key, box, mine, who, now, mails, gone, mine and newFrom or nil)
		rows[#rows + 1] = b
		byKey[key] = b
		for _, e in ipairs(mails) do mailRows[#mailRows + 1] = e end
	end
	-- mail: what runs out first, first
	table.sort(mailRows, function(a, b)
		if a.left ~= b.left then return a.left < b.left end
		return a.name < b.name
	end)
	for _, e in ipairs(mailRows) do rows[#rows + 1] = e end
	-- then mail you sent to others (newest first); the auction house's news is @auction's (0.48.10, the player's call:
	-- MA.NewsRows, Auctions.lua)
	MA.Prune(now)
	local way = {}
	for key, list in pairs(Store("mailSent")) do
		for i, sm in ipairs(list) do
			local e = SentRow(key, sm, i, key == myKey, MA.WhoOf(key), now)
			e._order = i -- (never _pos: that's the letters a search marked, drawn by the list)
			way[#way + 1] = e
		end
	end
	table.sort(way, NewerFirst)
	for _, e in ipairs(way) do rows[#rows + 1] = e end
	ns.RankInOrder(rows) -- (this order among equal matches)
	list, boxRows = rows, byKey
	return rows
end

ns:RegisterProvider("mail", {
	label = L["Mail"],
	color = "ffffe0c0", -- (an envelope's paper)
	aliases = { "mail", "mails", "inbox", "letters" },
	explicit = true, -- (every mail of every character: only with @mail, Simple mode's category, or asked in words)
	refreshOnOpen = 60, -- (the time left moves on)
	events = { "UPDATE_PENDING_MAIL", "PLAYER_ENTERING_WORLD" },
	guard = 1,
	-- nothing kept anywhere: a line saying how to fill it (0.49.2, review: @mail said nothing, as @lockout does)
	leadRow = ns.EmptyLead(function() return MA.NONE end, function() return not (list and #list > 0) end),
	collect = function() return MA.Collect() end,
})

----------------------------------------------------------------------
-- The question: "my mail", "mail running out", "cod mail", "gold in my mail", "mail from bob"
----------------------------------------------------------------------

local ASK = {}
for w in ([[my me i the in a an of is are do does did have has got any whats what which how much many show list check see
	all for on theres there will about it its that this still to waiting there was were been come came get]]):gmatch("%a+") do ASK[w] = true end
-- "mail" (also the armour) and "mailbox" (also the places) count only with a cue; "inbox" alone is enough
local SUBJECT = { mail = true, mails = true, mailbox = true, inbox = true, letters = true, letter = true }
local CUE = { expiring = "soon", expire = "soon", expires = "soon", expiry = "soon", expired = "soon", running = "soon",
	run = "soon", runs = "soon", out = "soon", soon = "soon", cod = "cod", gold = "money",
	money = "money", coins = "money", unread = "unread", new = "unread", returned = "returned", bounced = "returned",
	auction = "auction", auctions = "auction", ah = "auction", sold = "auction", from = "from", waiting = "all",
	sent = "sent", outgoing = "sent", outbox = "sent", incoming = "incoming", pending = "incoming", expected = "incoming",
	coming = "incoming" }
-- what only mail is: these make even "mail" (the armour too) a question; the other cues (from, sold, new, gold, out...)
-- count with "mail" only when nothing else is searched ("new mail", "my mail from bob"), else "new mail gloves", "mail
-- boots from wailing caverns" and "mail armor sold by vendors" were taken for mail questions (0.47.0 review)
local STRONG_CUE = { expiring = true, expire = true, expires = true, expiry = true, expired = true, cod = true,
	unread = true, returned = true, bounced = true, waiting = true, sent = true, outgoing = true, outbox = true,
	incoming = true, pending = true, expected = true }
local STRONG_SUBJECT = { mailbox = true, inbox = true, letters = true, letter = true }

--- The question: { words = what narrows it (a sender, an item...), soon, cod, money, unread, returned, auction }, or nil
--- when the line isn't asking about mail.
function MA.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("running out", "expiring")
	local subject, strong, inbox, asked, cues, rest, strongCue, fromFirst = false, false, false, false, {}, {}, false, false
	for w in t:gmatch("%S+") do
		if SUBJECT[w] then subject = true; strong = strong or STRONG_SUBJECT[w] == true; inbox = inbox or w == "inbox"
		elseif CUE[w] then
			cues[CUE[w]] = true
			if STRONG_CUE[w] then strongCue = true end
			if w == "from" and #rest == 0 then fromFirst = true end -- ("mail from bob": the words after it are the sender)
		elseif ASK[w] then asked = true
		else rest[#rest + 1] = w end
	end
	if not subject then return nil end
	-- "mail gloves", "nearest mailbox": searches; "my mail" or "check mailbox": the mail; words besides need a cue
	if not next(cues) and not (inbox and #rest == 0) and not (asked and #rest == 0) then return nil end
	-- "mail" alone (the armour too): a cue only mail has, or nothing else searched, or "from" before the other words
	if not strong and not strongCue and #rest > 0 and not (cues.from and fromFirst) then return nil end
	return { words = rest, soon = cues.soon, cod = cues.cod, money = cues.money, unread = cues.unread,
		returned = cues.returned, auction = cues.auction, sent = cues.sent, incoming = cues.incoming }
end

local function Filtered(q)
	return q.soon or q.cod or q.money or q.unread or q.returned or q.auction or q.sent or q.incoming
end

--- Whether a mail row (or a sent mail's, an auction's) is one the question asks for.
local function Wanted(e, q)
	local kind, m = e.mailKind, e.mail
	if q.sent and not (kind == "sent" or (kind == "mail" and m.sent)) then return false end -- (sent: to others, and to your alts)
	if q.incoming and kind ~= "auction" then return false end
	if kind == "auction" then
		if q.soon or q.cod or q.unread or q.returned then return false end
		if q.money and not e.money then return false end
	elseif kind == "sent" then
		if q.soon or q.cod or q.unread or q.returned or q.auction then return false end
		if q.money and not m.money then return false end
	else
		if q.soon and not e.soon then return false end
		if q.cod and not m.cod then return false end
		if q.money and not m.money then return false end
		if q.unread and m.read then return false end
		if q.returned and not m.returned then return false end
		if q.auction and not m.auction then return false end
	end
	local hay = Lower(e.name) .. " " .. (e._ltext or Lower(e.text or "")) -- (Core keeps only the lowercase copy of the text)
	for _, w in ipairs(q.words or {}) do if not hay:find(w, 1, true) then return false end end
	return true
end

MA.NOTE = L["Your mail"]
MA.NOTE_SOON = L["Mail running out within 3 days"]
MA.NONE = L["No mail kept yet: open a mailbox and Terminal keeps what's in it (on each character)"]
MA.NOTE_SENT, MA.NOTE_INCOMING = L["Mail you sent"], L["The auction house's news, on its way by mail"]

--- The rows a mail question looks at: the mail's (boxes, mail, sent: as @mail lists them) with the auction house's news
--- (@auction's, Auctions.lua) before the mail you sent, as before the news moved there.
local function MailAndNews()
	local p, a = ns.providers.mail, ns.providers.auctions
	local news = {}
	for _, e in ipairs(a and ns:GetEntries(a) or MA.NewsRows()) do
		if e.mailKind == "auction" then news[#news + 1] = e end
	end
	local all, sent = {}, {}
	for _, e in ipairs(p and ns:GetEntries(p) or {}) do
		if e.mailKind == "sent" then sent[#sent + 1] = e else all[#all + 1] = e end
	end
	for _, e in ipairs(news) do all[#all + 1] = e end
	for _, e in ipairs(sent) do all[#all + 1] = e end
	return all
end

function MA.Answer(q)
	q = q or {}
	local all = MailAndNews()
	local rows, money, boxes = {}, 0, 0
	local plain = not Filtered(q) and #(q.words or {}) == 0
	for _, e in ipairs(all) do
		if e.mailKind == "box" then
			boxes = boxes + 1
			if plain then rows[#rows + 1] = e end
		elseif Wanted(e, q) then
			rows[#rows + 1] = e
			money = money + ((e.mail and e.mail.money) or e.money or 0)
		end
	end
	ns.ScoreInOrder(rows)
	local mails, way = 0, 0
	for _, e in ipairs(rows) do
		if e.mailKind == "mail" then mails = mails + 1 elseif e.mailKind ~= "box" then way = way + 1 end
	end
	for _, e in ipairs(all) do if e.mailKind == "sent" or e.mailKind == "auction" then boxes = boxes + 1 break end end
	mails = mails + way
	local note
	if boxes == 0 then
		note = MA.NONE
	elseif mails == 0 then
		note = (q.sent and L["Nothing sent in the last hour"]) or (q.incoming and L["No auction house news in the last hour"])
			or (q.soon and L["Nothing in your mail runs out within 3 days"]) or (q.cod and L["No COD mail"])
			or (q.money and L["No gold in your mail"]) or (q.unread and L["No unread mail"]) or (q.returned and L["No mail sent back to you"])
			or (q.auction and L["No auction house mail"]) or ((q.words and #q.words > 0) and L["No mail has that"]) or L["No mail"]
	else
		note = (q.sent and MA.NOTE_SENT) or (q.incoming and MA.NOTE_INCOMING) or (q.soon and MA.NOTE_SOON) or MA.NOTE
		note = note .. ("  ·  %s"):format(Plural(mails, L["mail"], L["mails"])) .. (money > 0 and (", " .. Money(money, true)) or "")
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@mail is:expiring bob".
function MA.ToAdvanced(q)
	-- (as said, 0.55.7: "my mail" lists the auction house's news and every mailbox too, and gold or auction mail the
	-- news's sales: no one list has them. Search.lua's ns.QuestionToAdvanced)
	if not Filtered(q) or q.money or q.auction then return nil end
	local parts = { q.incoming and "@auction" or "@mail" } -- (the auction house's news is @auction's)
	if q.soon then parts[#parts + 1] = "is:expiring" end
	if q.cod then parts[#parts + 1] = "is:cod" end
	if q.money then parts[#parts + 1] = "is:money" end
	if q.unread then parts[#parts + 1] = "is:unread" end
	if q.returned then parts[#parts + 1] = "is:returned" end
	if q.auction then parts[#parts + 1] = "is:auction" end
	if q.sent then parts[#parts + 1] = "is:sent" end
	if q.incoming then parts[#parts + 1] = "is:incoming" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

----------------------------------------------------------------------
-- The login warning: mail with something in it that runs out soon
----------------------------------------------------------------------

--- The warning's lines (nil when nothing runs out soon): per character, the gold and items in mail running out within
--- MA.SOON, the soonest and what happens to it.
function MA.Warnings(now)
	now = now or Now()
	local boxes, myKey, myRealm = Boxes() or {}, MyKey(), Str(Safe(GetRealmName))
	local found = {}
	for key, box in pairs(boxes) do
		if type(box) == "table" and type(box.mails) == "table" then
			local w = { key = key, who = Who(box, myRealm), money = 0, items = 0, mails = 0 }
			for _, m in ipairs(box.mails) do
				local left = type(m) == "table" and type(m.expires) == "number" and (m.expires - now) or 0
				if left > 0 and left < MA.SOON and (m.money or m.items) then
					w.mails = w.mails + 1
					w.money = w.money + (m.money or 0)
					w.items = w.items + (m.items and #m.items or 0)
					if not w.first or left < w.first then w.first, w.fate = left, Fate(m) end
				end
			end
			if w.mails > 0 then found[#found + 1] = w end
		end
	end
	if #found == 0 then return nil end
	table.sort(found, function(a, b)
		if (a.key == myKey) ~= (b.key == myKey) then return a.key == myKey end
		return a.first < b.first
	end)
	local out = { L["Mail running out (%s lists it):"]:format(ns.Said('"mail running out"', "@mail is:expiring")) }
	for i, w in ipairs(found) do
		if i > MA.WARN_MAX then
			out[#out + 1] = "  " .. L["+%s more"]:format(Plural(#found - MA.WARN_MAX, L["character"], L["characters"]))
			break
		end
		local what = {}
		if w.money > 0 then what[#what + 1] = Money(w.money) end
		if w.items > 0 then what[#what + 1] = Plural(w.items, L["item"], L["items"]) end
		out[#out + 1] = "  " .. L["%s%s: %s in %s, the first in %s (%s)"]:format(w.who, w.key == myKey and (" " .. L["(you)"]) or "",
			#what == 2 and L["%s and %s"]:format(what[1], what[2]) or table.concat(what, " and "), Plural(w.mails, L["mail"], L["mails"]),
			MA.Left(w.first), w.fate)
	end
	return out
end

function MA.Warn()
	-- (the setting, .set mailWarn; 0.65.12: it was .mail warn off, moved to the setting once)
	if ns.db and ns.db.mailWarn == false and ns.Theme and ns.Theme.Set then
		ns.db.mailWarn = nil
		pcall(ns.Theme.Set, "mailWarn", "off")
	end
	local Th = ns.Theme and ns.Theme.Get and ns.Theme.Get()
	if Th and Th.mailWarn == false then return false end
	local lines = MA.Warnings()
	if not lines then return false end
	ns:Output(lines)
	return true
end

--- Forget an alt's mailboxes (and what it sent, its auction news and the prices kept for them: review, 0.48.6): `.forget
--- <name>` (0.65.12: .mail is gone, @mail lists them). How many were dropped.
function MA.ForgetAlt(who)
	local lw, n = Lower(who), 0
	local boxes = Boxes() or {}
	for key, box in pairs(boxes) do
		if type(box) == "table" and box.name and (Lower(box.name) == lw or Lower(box.name .. "-" .. tostring(box.realm)) == lw) then
			boxes[key] = nil
			for _, store in ipairs({ "mailSent", "mailAuctions", "auctionsPosted", "auctionBids", "auctionsEnded", "auctionsSold" }) do Store(store)[key] = nil end
			n = n + 1
		end
	end
	if n > 0 then Dirty() end
	return n
end
--- The names of the characters whose mail is kept (.forget's choices).
function MA.AltNames()
	local out = {}
	for _, box in pairs(Boxes() or {}) do if type(box) == "table" and box.name then out[#out + 1] = box.name end end
	return out
end

----------------------------------------------------------------------
-- Events: the inbox read while a mailbox shows; the warning once a login
----------------------------------------------------------------------

local readGen = 0

local function ReadSoon()
	readGen = readGen + 1
	local gen = readGen
	C_Timer.After(MA.READ_DELAY, function()
		if gen == readGen and MA.open then pcall(MA.ReadInbox) end
	end)
end

local MAIL_TYPE = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo

function MA.OnEvent(event, ...)
	if event == "MAIL_SHOW" then
		MA.open = true
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		if MAIL_TYPE and ... == MAIL_TYPE then MA.open = true end
	elseif event == "MAIL_CLOSED" then
		MA.open = false
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		if MAIL_TYPE and ... == MAIL_TYPE then MA.open = false end
	elseif event == "MAIL_INBOX_UPDATE" then
		ReadSoon() -- (read only if the mailbox still shows then)
	elseif event == "MAIL_SEND_SUCCESS" then
		pcall(MA.SendDone)
	elseif event == "MAIL_FAILED" then
		MA.SendFailed()
	elseif event == "SECURE_TRANSFER_CONFIRM_SEND_MAIL" then
		MA.SendConfirming()
	elseif event == "SECURE_TRANSFER_CANCEL" then
		if pendingSend and pendingSend.confirm then
			ns:Trace("mail: the send to " .. pendingSend.to .. " was cancelled")
			pendingSend = nil
		end
	elseif event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
		local n, text, auctionID = ...
		local kind = NotificationKind(n)
		if kind then pcall(MA.OnAuction, kind, text, auctionID) end
	elseif event == "CHAT_MSG_SYSTEM" then -- (the classic clients' way of telling it)
		local text = ...
		if type(text) == "string" and not ns.Secret(text) then
			local kind, item = MA.ChatNews(text)
			if kind then pcall(MA.OnAuction, kind, item) end
		end
	elseif event == "COMMODITY_PURCHASED" then
		pcall(MA.OnCommodity, ...)
	elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
		pcall(MA.AuctionCreated, ...)
	elseif event == "AUCTION_HOUSE_POST_ERROR" or event == "AUCTION_HOUSE_SHOW_ERROR" then
		MA.PostFailed()
	elseif event == "OWNED_AUCTIONS_UPDATED" then
		pcall(MA.ReadOwned)
	elseif event == "AUCTION_CANCELED" then
		pcall(MA.Over, ..., "cancelled")
	elseif event == "PLAYER_ENTERING_WORLD" then
		MA.HookSend() -- (once; at load too)
		MA.HookPost()
		local login = ...
		if login and not MA.warned then
			MA.warned = true
			C_Timer.After(MA.WARN_DELAY, function() pcall(MA.Warn) end)
		end
	end
end

local ev = CreateFrame("Frame")
MA.frame = ev
-- (not UPDATE_PENDING_MAIL: the list's own event already; review, 0.53.6: handled twice, @auction marked changed for it too)
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "PLAYER_ENTERING_WORLD",
	"MAIL_SEND_SUCCESS", "MAIL_FAILED", "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "SECURE_TRANSFER_CANCEL",
	"AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "CHAT_MSG_SYSTEM",
	"AUCTION_HOUSE_AUCTION_CREATED", "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "COMMODITY_PURCHASED",
	"AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_SHOW_ERROR",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...) MA.OnEvent(event, ...) end)
MA.HookSend()
MA.HookPost()

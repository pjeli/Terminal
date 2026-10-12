local ns = select(2, ...)

-- Your mail (@mail, @inbox; Simple mode: "my mail", "mail running out", "cod mail", under Alts, bank & mail): what's in
-- each of your characters' mailboxes, kept by Terminal itself every time a mailbox shows (no bag addon needed): who
-- sent each mail, its gold, its COD, what's attached, and when it runs out. Running out means deleted (with what's in
-- it: the auction house's gold, the game's own mail) or sent back to whoever sent it (a player's mail); the inbox says
-- which, and so does Terminal. A note of each mailbox, per character (db.mailboxes, by GUID): an alt's mail shows up once
-- you've opened a mailbox on it with Terminal, as it was then (mail that ran out since is left out).
--
-- At login (not a /reload) a chat line names the gold and items in mail that runs out within MA.SOON, per character
-- (".mail warn off" stops it).
--
--   Enter        at an open mailbox, on your own mail: points at it in the inbox (or says the page); else the mail
--                (or a whole mailbox) in chat, only you see it
--   Shift+Enter  a waypoint to the nearest mailbox (QuestieDB's mailboxes)
--
-- Read with the inbox's own calls only (GetInboxHeaderInfo, GetInboxItem, GetInboxInvoiceInfo, InboxItemCanDelete:
-- what Forever's MailFrame.lua reads); never GetInboxText, which marks a mail read.

local MA = {}
ns.Mail = MA

local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower

MA.SOON = 3 * 86400 -- (s: "running out soon", and the login warning's reach)
MA.MAX_MAILS = 100 -- (kept per character; the inbox shows 50 at most)
MA.WARN_DELAY = 10 -- (s after login before the warning, once the chat is up)
MA.WARN_MAX = 4 -- (characters named; the rest counted)
MA.PER_PAGE = 7 -- (INBOXITEMS_TO_DISPLAY in Forever's MailFrame.lua)
MA.READ_DELAY = 0.3 -- (s: an inbox update burst read once)

local function Now() return (_G.time and _G.time()) or 0 end
local function MyKey() return Str(Safe(UnitGUID, "player")) end

local function Boxes()
	if not ns.db then return nil end
	if type(ns.db.mailboxes) ~= "table" then ns.db.mailboxes = {} end
	return ns.db.mailboxes
end

local function Dirty()
	local p = ns.providers.mail
	if p then p._dirty = true end
end

local function Money(c, plain) return ns.Gold and ns.Gold.Text(c, plain) or (tostring(c) .. "c") end

--- Seconds left as the inbox says it: "3 days", "1 day", "5 h", "20 min".
function MA.Left(s)
	s = math.max(0, tonumber(s) or 0)
	if s >= 2 * 86400 then return math.floor(s / 86400) .. " days" end
	if s >= 86400 then return "1 day" end
	if s >= 3600 then return math.floor(s / 3600) .. " h" end
	return math.max(1, math.floor(s / 60)) .. " min"
end

----------------------------------------------------------------------
-- Reading the inbox (only while a mailbox shows)
----------------------------------------------------------------------

-- the auction house's subjects ("Auction successful: %s"...), as the game's own strings say them: what each mail is
local AUCTION_SUBJECTS = { sold = "AUCTION_SOLD_MAIL_SUBJECT", won = "AUCTION_WON_MAIL_SUBJECT",
	expired = "AUCTION_EXPIRED_MAIL_SUBJECT", outbid = "AUCTION_OUTBID_MAIL_SUBJECT", cancelled = "AUCTION_REMOVED_MAIL_SUBJECT" }
local subjectPatterns

local function Pattern(s)
	local p = s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
	return "^" .. p .. "$"
end

--- What an auction house mail is ("sold", "won", "expired", "outbid", "cancelled"), from its subject; nil for others.
function MA.AuctionSubject(subject)
	if type(subject) ~= "string" then return nil end
	if not subjectPatterns then
		subjectPatterns = {}
		for kind, global in pairs(AUCTION_SUBJECTS) do
			local s = Str(_G[global])
			if s and s:find("%s", 1, true) then subjectPatterns[kind] = Pattern(s) end
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
	local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, _, _, isGM = Safe(GetInboxHeaderInfo, i)
	daysLeft = Num(daysLeft)
	if not daysLeft then return nil end
	money, cod, itemCount = Num(money) or 0, Num(cod) or 0, Num(itemCount) or 0
	local m = {
		from = Str(sender), subject = Str(subject), money = money > 0 and money or nil, cod = cod > 0 and cod or nil,
		expires = math.floor(now + daysLeft * 86400), read = wasRead == true or nil, returned = wasReturned == true or nil,
		gm = isGM == true or nil,
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
		name = ns.CharacterName() or Str(Safe(UnitName, "player")) or "You", realm = Str(Safe(GetRealmName)),
		class = Str(select(2, Safe(UnitClass, "player"))), t = now, mails = mails,
		more = (total and total > n) and (total - n) or nil,
	}
	boxes[key] = box
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
MA.SEND_WAIT = 60 -- (s a send is waited on for MAIL_SEND_SUCCESS)

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
	return pendingSend
end

--- The game sent it: into the recipient's list when it's one of your characters (a note made for one that has none yet).
function MA.SendDone()
	local s = pendingSend
	pendingSend = nil
	if not s or Now() - s.at > MA.SEND_WAIT then return nil end
	local key, c = MA.OwnKey(s.to)
	if not key then
		ns:Trace("mail: sent to " .. s.to .. ", not one of your characters Terminal knows: not kept")
		return nil
	end
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
	return true
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local ICON_BOX, ICON_MAIL = "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Letter_01"
local ICON_MONEY, ICON_COD = "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Letter_03"
local RED, ORANGE, GREY = "|cffff4040", "|cffff9933", "|cff9d9d9d"

local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

--- The name a mail goes by: its subject, else its first item's, else "(no subject)".
local function Title(m)
	if m.subject then return m.subject end
	local first = m.items and m.items[1]
	return (first and (first.name or (first.link and first.link:match("%[(.-)%]")))) or "(no subject)"
end

local function ItemName(it) return it.name or (it.link and it.link:match("%[(.-)%]")) or ("item " .. tostring(it.id)) end

--- What running out does: "deleted", or "back to Bob".
local function Fate(m) return m.deletes and "deleted" or ("back to " .. (m.from or "its sender")) end

--- A mail's time left, coloured as the inbox does it (red under a day; orange under MA.SOON).
local function LeftText(left)
	local s = MA.Left(left) .. " left"
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
		return ("Bought %s%s for %s"):format(item, v.player and (" from " .. v.player) or "", Money(v.bid or 0, true))
	elseif v.kind == "seller" then
		return ("Sold %s%s: %s (%s, deposit %s back, cut %s)"):format(item, v.player and (" to " .. v.player) or "",
			Money(net, true), Money(v.bid or 0, true), Money(v.deposit or 0, true), Money(v.cut or 0, true))
	elseif v.kind == "seller_temp_invoice" then
		local eta = (v.etaH and v.etaM) and (" (the gold comes about %02d:%02d, server time)"):format(v.etaH, v.etaM) or ""
		return ("Sold %s%s: %s on its way%s"):format(item, v.player and (" to " .. v.player) or "", Money(net, true), eta)
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
	local parts = { (m.from and ("From " .. m.from .. ": ") or "") .. Title(m) }
	if m.money then parts[#parts + 1] = Money(m.money) end
	if m.cod then parts[#parts + 1] = "COD " .. Money(m.cod) end
	if m.items then
		local names = {}
		for _, it in ipairs(m.items) do names[#names + 1] = (it.link or ItemName(it)) .. ((it.count or 1) > 1 and (" x" .. it.count) or "") end
		parts[#parts + 1] = table.concat(names, ", ")
	end
	parts[#parts + 1] = MA.Left(e.left) .. " left (" .. Fate(m) .. ")"
	return "  " .. table.concat(parts, "  ·  ")
end

local function BoxLines(key)
	local box = boxRows and boxRows[key]
	if not box then return { "No mail kept for that character." } end
	local out = { (box.color or "") .. box.who .. (box.color and "|r" or "") .. ": " .. box.detail }
	for _, e in ipairs(list or {}) do
		if e.mailKind == "mail" and e.boxKey == key then out[#out + 1] = MailLine(e) end
	end
	return out
end
MA.BoxLines = BoxLines

--- Every mailbox kept, for .mail: each box's line and its mail.
function MA.AllLines()
	MA.Collect()
	local out = {}
	for _, e in ipairs(list or {}) do
		if e.mailKind == "box" then
			for _, l in ipairs(BoxLines(e.boxKey)) do out[#out + 1] = l end
		end
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
		ns:Print(("%s: on page %d of your inbox (page %d shows)."):format(Title(e.mail), page, shown))
	end
	return true
end

local function Show(e)
	if e.mailKind == "box" then ns:Output(BoxLines(e.boxKey)) return end
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
		ns:Print("Your position isn't known here, so there's no nearest mailbox.")
	else
		ns:Print("No mailbox known near you.")
	end
end
MA.NearestMailbox = NearestMailbox

--- What's sent: "Mail from Bob: Auction successful: Copper Bar (45g, 2 days left)".
local function ShareText(e)
	if e.mailKind == "box" then return e.who .. "'s mail: " .. (e.plain or "") end
	local m = e.mail
	local bits = {}
	if m.money then bits[#bits + 1] = Money(m.money, true) end
	if m.cod then bits[#bits + 1] = "COD " .. Money(m.cod, true) end
	bits[#bits + 1] = MA.Left(e.left) .. " left"
	return "Mail" .. (m.from and (" from " .. m.from) or "") .. ": " .. Title(m) .. " (" .. table.concat(bits, ", ") .. ")"
end

local function Tooltip(e, t)
	if e.mailKind == "box" then
		t:SetText(e.who .. "'s mail", 1, 0.82, 0)
		local n = 0
		for _, r in ipairs(list or {}) do
			if r.mailKind == "mail" and r.boxKey == e.boxKey then
				n = n + 1
				if n <= 12 then
					t:AddDoubleLine(Title(r.mail), (r.mail.money and (Money(r.mail.money) .. "  ") or "") .. LeftText(r.left), 1, 1, 1, 1, 1, 1)
				end
			end
		end
		if n > 12 then t:AddLine(("+%d more"):format(n - 12), 0.6, 0.6, 0.6) end
		if e.gone and e.gone > 0 then
			t:AddLine(("%s ran out since (taken, deleted or sent back)"):format(Plural(e.gone, "mail", "mails")), 0.6, 0.6, 0.6, true)
		end
		if e.more then t:AddLine(("%d more waiting on the server (the inbox shows 50 at a time)"):format(e.more), 0.6, 0.6, 0.6, true) end
		if e.newFrom then t:AddLine("New mail from " .. e.newFrom, 0.4, 1, 0.4, true) end
		if e.seen then t:AddLine("Mailbox last opened " .. ns.Ago(Now() - e.seen), 0.6, 0.6, 0.6) end
		t:AddLine("Enter: in chat    Shift+Enter: waypoint to the nearest mailbox", 0.6, 0.6, 0.6, true)
		return
	end
	local m = e.mail
	t:SetText(Title(m), 1, 0.82, 0)
	t:AddLine("From " .. (m.from or "someone unknown") .. (m.returned and " (sent back to you)" or ""), 1, 1, 1)
	if not e.mine then t:AddLine("In " .. e.who .. "'s mailbox", 0.6, 0.8, 1) end
	if m.money then t:AddDoubleLine("Gold", Money(m.money), 1, 1, 1, 1, 1, 1) end
	if m.cod then t:AddDoubleLine("COD (paid when you take it)", Money(m.cod), 1, 0.5, 0.5, 1, 1, 1) end
	for _, it in ipairs(m.items or {}) do
		local hex = ns.QualityHex(it.q)
		t:AddDoubleLine((hex or "") .. ItemName(it) .. (hex and "|r" or ""),
			(it.count or 1) > 1 and ("x" .. it.count) or "", 1, 1, 1, 1, 1, 1)
	end
	local inv = InvoiceText(m.invoice)
	if inv then t:AddLine(inv, 0.8, 0.8, 0.8, true) end
	t:AddLine(LeftText(e.left) .. ", then " .. (m.deletes and "it's deleted" .. ((m.money or m.items) and " with what's in it" or "")
		or ("it goes back to " .. (m.from or "its sender"))), 1, 1, 1, true)
	if m.sent then
		t:AddLine(("You sent it %s; it shows here until %s opens a mailbox"):format(ns.Ago(Now() - m.sent), e.who), 0.6, 0.8, 1, true)
	elseif not m.read then
		t:AddLine("Unread", 0.4, 1, 0.4)
	end
	t:AddLine(((MA.open and e.mine) and "Enter: point at it in the inbox" or "Enter: in chat")
		.. "    Shift+Enter: waypoint to the nearest mailbox", 0.6, 0.6, 0.6, true)
end

-- (every row's: shared, not a closure per row)
local function Secondary() return ns.providers.mailbox and NearestMailbox or nil end

local function MailRow(key, box, m, i, mine, who, now)
	local left = m.expires - now
	local soon = left < MA.SOON
	local d = {}
	if m.from then d[#d + 1] = "from " .. m.from end
	if m.sent then d[#d + 1] = "you sent it " .. ns.Ago(now - m.sent) end
	if m.money then d[#d + 1] = Money(m.money) end
	if m.cod then d[#d + 1] = RED .. "COD|r " .. Money(m.cod) end
	if m.items then
		local first = m.items[1]
		d[#d + 1] = #m.items == 1 and (ItemName(first) .. ((first.count or 1) > 1 and (" x" .. first.count) or ""))
			or Plural(#m.items, "item", "items")
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
		detail = table.concat(d, "  ·  "), text = table.concat(words, " "),
		holders = { { who = who, mine = mine or nil, where = "mail", count = 1 } },
		tooltip = Tooltip, activate = Show, secondary = Secondary(), shareLink = ShareText,
	}
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
	local d, plain = { Plural(#mails, "mail", "mails") }, { Plural(#mails, "mail", "mails") }
	if money > 0 then d[#d + 1] = Money(money); plain[#plain + 1] = Money(money, true) end
	if cods > 0 then d[#d + 1] = cods .. " COD"; plain[#plain + 1] = cods .. " COD" end
	if soon > 0 then d[#d + 1] = ORANGE .. soon .. " running out|r" ; plain[#plain + 1] = soon .. " running out soon" end
	if next then d[#d + 1] = "the next in " .. MA.Left(next) end
	if box and box.more then d[#d + 1] = "+" .. box.more .. " on the server" end
	if newFrom then d[#d + 1] = "|cff40ff40new mail|r" end
	if box and box.t then d[#d + 1] = GREY .. "opened " .. ns.Ago(now - box.t) .. "|r"
	elseif box then d[#d + 1] = GREY .. "no mailbox opened with Terminal yet|r" end
	if not box then d = { "|cff40ff40new mail|r", GREY .. "not opened with Terminal yet|r" } end
	return {
		key = "box:" .. key, name = who, who = who, mailKind = "box", boxKey = key, mine = mine or nil,
		color = ns.ClassHex(box and box.class or (mine and select(2, Safe(UnitClass, "player")))),
		icon = ICON_BOX, detail = table.concat(d, "  ·  "), plain = table.concat(plain, ", "),
		text = "mail inbox mailbox " .. (mine and "you me mine" or "alt alts character") .. (money > 0 and " gold money" or "")
			.. (soon > 0 and " expiring running out" or ""),
		holders = { { who = who, mine = mine or nil, where = "mail", count = 1 } },
		gone = gone, more = box and box.more, newFrom = newFrom, seen = box and box.t,
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
	return #names > 0 and table.concat(names, ", ") or "someone"
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
		local who = box and Who(box, myRealm) or (ns.CharacterName() or Str(Safe(UnitName, "player")) or "You")
		local mails, gone = {}, 0
		for i, m in ipairs(box and box.mails or {}) do
			if type(m) == "table" and type(m.expires) == "number" then
				if m.expires > now then mails[#mails + 1] = MailRow(key, box, m, i, mine, who, now) else gone = gone + 1 end
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
	local n = #rows
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * 0.5 end -- (this order among equal matches)
	list, boxRows = rows, byKey
	return rows
end

ns:RegisterProvider("mail", {
	label = "Mail",
	color = "ffffe0c0", -- (an envelope's paper)
	aliases = { "mail", "mails", "inbox", "letters" },
	explicit = true, -- (every mail of every character: only with @mail, Simple mode's category, or asked in words)
	refreshOnOpen = 60, -- (the time left moves on)
	events = { "UPDATE_PENDING_MAIL", "PLAYER_ENTERING_WORLD" },
	guard = 1,
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
	auction = "auction", auctions = "auction", ah = "auction", sold = "auction", from = "from", waiting = "all" }

--- The question: { words = what narrows it (a sender, an item...), soon, cod, money, unread, returned, auction }, or nil
--- when the line isn't asking about mail.
function MA.Question(text)
	if type(text) ~= "string" or text:find("[@:>|]") or text:find("^%s*[%./]") then return nil end
	local t = Lower(text):gsub("'", ""):gsub("[%p]", " ")
	local subject, inbox, asked, cues, rest = false, false, false, {}, {}
	for w in t:gmatch("%S+") do
		if SUBJECT[w] then subject = true; inbox = inbox or w == "inbox"
		elseif CUE[w] then cues[CUE[w]] = true
		elseif ASK[w] then asked = true
		else rest[#rest + 1] = w end
	end
	if not subject then return nil end
	-- "mail gloves", "nearest mailbox": searches; "my mail" or "check mailbox": the mail; words besides need a cue
	if not next(cues) and not (inbox and #rest == 0) and not (asked and #rest == 0) then return nil end
	return { words = rest, soon = cues.soon, cod = cues.cod, money = cues.money, unread = cues.unread,
		returned = cues.returned, auction = cues.auction }
end

local function Filtered(q)
	return q.soon or q.cod or q.money or q.unread or q.returned or q.auction
end

--- Whether a mail row is one the question asks for.
local function Wanted(e, q)
	local m = e.mail
	if q.soon and not e.soon then return false end
	if q.cod and not m.cod then return false end
	if q.money and not m.money then return false end
	if q.unread and m.read then return false end
	if q.returned and not m.returned then return false end
	if q.auction and not m.auction then return false end
	local hay = Lower(e.name) .. " " .. (e._ltext or Lower(e.text or "")) -- (Core keeps only the lowercase copy of the text)
	for _, w in ipairs(q.words or {}) do if not hay:find(w, 1, true) then return false end end
	return true
end

MA.NOTE = "Your mail"
MA.NOTE_SOON = "Mail running out within 3 days"
MA.NONE = "No mail kept yet: open a mailbox and Terminal keeps what's in it (on each character)"

function MA.Answer(q)
	q = q or {}
	local p = ns.providers.mail
	local all = p and ns:GetEntries(p) or {}
	local rows, money, boxes = {}, 0, 0
	local plain = not Filtered(q) and #(q.words or {}) == 0
	for _, e in ipairs(all) do
		if e.mailKind == "box" then
			boxes = boxes + 1
			if plain then rows[#rows + 1] = e end
		elseif Wanted(e, q) then
			rows[#rows + 1] = e
			money = money + (e.mail.money or 0)
		end
	end
	for i, e in ipairs(rows) do e._score = 1e6 - i end
	local mails = 0
	for _, e in ipairs(rows) do if e.mailKind == "mail" then mails = mails + 1 end end
	local note
	if boxes == 0 then
		note = MA.NONE
	elseif mails == 0 then
		note = (q.soon and "Nothing in your mail runs out within 3 days") or (q.cod and "No COD mail")
			or (q.money and "No gold in your mail") or (q.unread and "No unread mail") or (q.returned and "No mail sent back to you")
			or (q.auction and "No auction house mail") or ((q.words and #q.words > 0) and "No mail has that") or "No mail"
	else
		note = (q.soon and MA.NOTE_SOON) or MA.NOTE
		note = note .. ("  ·  %s"):format(Plural(mails, "mail", "mails")) .. (money > 0 and (", " .. Money(money, true)) or "")
	end
	return rows, note
end

--- The question as Advanced syntax (Alt+`): "@mail is:expiring bob".
function MA.ToAdvanced(q)
	local parts = { "@mail" }
	if q.soon then parts[#parts + 1] = "is:expiring" end
	if q.cod then parts[#parts + 1] = "is:cod" end
	if q.money then parts[#parts + 1] = "is:money" end
	if q.unread then parts[#parts + 1] = "is:unread" end
	if q.returned then parts[#parts + 1] = "is:returned" end
	if q.auction then parts[#parts + 1] = "is:auction" end
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
	local out = { "Mail running out (" .. ns.Said('"mail running out"', "@mail is:expiring") .. " lists it):" }
	for i, w in ipairs(found) do
		if i > MA.WARN_MAX then
			out[#out + 1] = ("  +%s more"):format(Plural(#found - MA.WARN_MAX, "character", "characters"))
			break
		end
		local what = {}
		if w.money > 0 then what[#what + 1] = Money(w.money) end
		if w.items > 0 then what[#what + 1] = Plural(w.items, "item", "items") end
		out[#out + 1] = ("  %s%s: %s in %s, the first in %s (%s)"):format(w.who, w.key == myKey and " (you)" or "",
			table.concat(what, " and "), Plural(w.mails, "mail", "mails"), MA.Left(w.first), w.fate)
	end
	return out
end

function MA.Warn()
	if ns.db and ns.db.mailWarn == false then return false end
	local lines = MA.Warnings()
	if not lines then return false end
	ns:Output(lines)
	return true
end

ns:RegisterCommand("mail", {
	desc = "Your characters' mail as Terminal last saw it; .mail warn on|off (the login warning), .mail forget <name>",
	aliases = { "inbox" },
	complete = function()
		local out = { { "warn on", "say at login when mail with something in it runs out soon" }, { "warn off", "don't" } }
		for _, box in pairs(Boxes() or {}) do
			if type(box) == "table" and box.name then out[#out + 1] = { "forget " .. box.name, "drop its mailbox" } end
		end
		return out
	end,
	run = function(args)
		local a = strtrim(args or "")
		local la = Lower(a)
		if la == "warn on" or la == "warn off" then
			ns.db.mailWarn = la == "warn on"
			return { la == "warn on" and "Mail: you're told at login when mail with something in it runs out within 3 days."
				or "Mail: no login warning." }
		end
		local who = a:match("^[Ff]orget%s+(.+)$")
		if who then
			local lw, n = Lower(who), 0
			local boxes = Boxes() or {}
			for key, box in pairs(boxes) do
				if type(box) == "table" and box.name and (Lower(box.name) == lw or Lower(box.name .. "-" .. tostring(box.realm)) == lw) then
					boxes[key] = nil
					n = n + 1
				end
			end
			Dirty()
			return { n > 0 and ("Forgot %s's mail."):format(who) or ("No mail kept for %s."):format(who) }
		end
		local lines = MA.AllLines()
		if #lines == 0 then return { MA.NONE .. "." } end
		table.insert(lines, 1, "Mail:")
		return lines
	end,
})

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
		pendingSend = nil
	elseif event == "UPDATE_PENDING_MAIL" then
		Dirty()
	elseif event == "PLAYER_ENTERING_WORLD" then
		MA.HookSend() -- (once; at load too)
		local login = ...
		if login and not MA.warned then
			MA.warned = true
			C_Timer.After(MA.WARN_DELAY, function() pcall(MA.Warn) end)
		end
	end
end

local ev = CreateFrame("Frame")
MA.frame = ev
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "UPDATE_PENDING_MAIL", "PLAYER_ENTERING_WORLD",
	"MAIL_SEND_SUCCESS", "MAIL_FAILED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...) MA.OnEvent(event, ...) end)
MA.HookSend()

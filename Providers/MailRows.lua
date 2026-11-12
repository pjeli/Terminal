local ns = select(2, ...)
local L = ns.L

-- Your mail, shown: @mail's rows and their tooltips, the question ("my mail", "mail running out", "cod mail", "gold in
-- my mail", "mail from bob"), the login warning, and the events that read the inbox. What's read and kept, mail you
-- send and the auction house's news are Mail.lua's, loaded just before this (1.4.2: one file until then).

local MA = ns.Mail
local Safe, Num, Str, Lower = ns.Safe, ns.Num, ns.Str, ns.Lower
local Now, MyKey, Money, NameOfLink = ns.Now, ns.PlayerGUID, ns.Money, ns.LinkName
local Boxes, Dirty, Store, NotificationKind = MA._.Boxes, MA._.Dirty, MA._.Store, MA._.NotificationKind

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

--- A mail's first item's icon and quality colour.
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

-- the tooltip's Shift+Enter, only where there is one: the nearest mailbox is Questie's (@mailbox), so without it
-- Shift+Enter does what Enter does
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
	-- then mail you sent to others (newest first); the auction house's news is @auction's
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
	-- nothing kept anywhere: a line saying how to fill it
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
-- boots from wailing caverns" and "mail armor sold by vendors" were taken for mail questions
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
	return rows, MA.Note(q, boxes, mails, money)
end

--- The footer of a mail question: what it lists, how many, the gold in them; else why there's none (no mailbox known,
--- or none of what was asked).
function MA.Note(q, boxes, mails, money)
	if boxes == 0 then return MA.NONE end
	if mails == 0 then
		return (q.sent and L["Nothing sent in the last hour"]) or (q.incoming and L["No auction house news in the last hour"])
			or (q.soon and L["Nothing in your mail runs out within 3 days"]) or (q.cod and L["No COD mail"])
			or (q.money and L["No gold in your mail"]) or (q.unread and L["No unread mail"]) or (q.returned and L["No mail sent back to you"])
			or (q.auction and L["No auction house mail"]) or ((q.words and #q.words > 0) and L["No mail has that"]) or L["No mail"]
	end
	local note = (q.sent and MA.NOTE_SENT) or (q.incoming and MA.NOTE_INCOMING) or (q.soon and MA.NOTE_SOON) or MA.NOTE
	return note .. ("  ·  %s"):format(Plural(mails, L["mail"], L["mails"])) .. (money > 0 and (", " .. Money(money, true)) or "")
end

--- The question as Advanced syntax, its answer and its Alt+` (docs/QUESTIONS.md 4.1): "@mail is:expiring bob
--- sort:list"; nil, its own answer, for "my mail" (the auction house's news and every mailbox too), gold and auction
--- mail (the news's sales too): no one list has them.
function MA.Line(q)
	if not Filtered(q) or q.money or q.auction then return nil end
	local parts = { q.incoming and "@auction" or "@mail" } -- (the auction house's news is @auction's)
	if q.soon then parts[#parts + 1] = "is:expiring" end
	if q.cod then parts[#parts + 1] = "is:cod" end
	if q.unread then parts[#parts + 1] = "is:unread" end
	if q.returned then parts[#parts + 1] = "is:returned" end
	if q.sent then parts[#parts + 1] = "is:sent" end
	if q.incoming then parts[#parts + 1] = "is:incoming" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	parts[#parts + 1] = "sort:list"
	return table.concat(parts, " ") .. " "
end
--- A filtered question's footer: what it lists, how many, the gold in them; else why there's none.
function MA.Footer(q, rows)
	local money, mails = 0, 0
	for _, e in ipairs(rows) do
		mails = mails + 1
		money = money + ((e.mail and e.mail.money) or e.money or 0)
	end
	-- (no mailbox known at all: said so, as the answer does)
	local boxes = 0
	for _, e in ipairs(MailAndNews()) do
		if e.mailKind == "box" or e.mailKind == "sent" or e.mailKind == "auction" then boxes = 1 break end
	end
	return MA.Note(q, boxes, mails, money)
end
function MA.None() return {} end

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
	-- (the setting, .set mailWarn)
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

--- Forget an alt's mailboxes (and what it sent, its auction news and the prices kept for them: review): `.forget
--- <name>`. How many were dropped.
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
		MA.SendCancelled()
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
-- (not UPDATE_PENDING_MAIL: the list's own event already)
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

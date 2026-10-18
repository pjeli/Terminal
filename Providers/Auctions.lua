local ns = select(2, ...)
local L = ns.L

-- @auction (0.48.10, the player's ask: auctions out of @mail into a list of their own): every character's auctions on
-- the auction house as Terminal saw them, and the auction house's news.
--
--   up now     each auction posted (seen as it was made: Mail.lua's MA.OnPost / MA.AuctionCreated) or listed on your
--              Auctions tab (read whenever you visit the auction house: MA.ReadOwned), with its price and time left
--   ran out    one whose time is up with no other news of it
--   news       sold, won, outbid, expired, each kept its hour (Mail.lua's MA.NewsRows; "incoming mail" reads them too)
--   sold       your sales of the last 30 days (0.56.12, a player: past sales weren't listed), newest first: each kept as
--              the auction house told it (MA.KeepSale), the buyer and what you got from its mail (MA.SalesFromMail)
--
-- Terminal's own records only (the player's call): an auction leaves the list of those up once it sells, expires, is
-- cancelled, comes back by mail or is gone from the Auctions tab's list (MA.Over). Only auctions posted or seen with
-- Terminal running are known (and sales whose mail it read). @stored still counts what's on the auction house from the
-- bag addon's record.

local AU = {}
ns.Auctions = AU

local MA = ns.Mail
local Lower = ns.Lower
local Now = ns.Now
local MyKey = ns.PlayerGUID
local Money = ns.Money

local ICON = "Interface\\Icons\\INV_Hammer_15"
local GREY = "|cff9d9d9d"

AU.NONE = L["No auctions kept yet: Terminal keeps the ones it sees you post, and your Auctions tab's list whenever you visit the auction house"]
AU.NOTE = L["Your auctions"]

local list -- (the last collect's rows)

local function NameOf(a)
	return a.name or ns.LinkName(a.link) or L["item %s"]:format("?")
end

--- What's said of an auction up now (or whose time ran out): its price, its time left, plain (for chat).
local function Said(a, now)
	local bits = {}
	if a.each then bits[#bits + 1] = L["%s each"]:format(Money(a.each, true))
	elseif a.price then bits[#bits + 1] = Money(a.price, true) end
	local left = a.ends and (a.ends - now)
	if left and left > 0 then bits[#bits + 1] = L["%s left"]:format(MA.Left(left))
	elseif left then bits[#bits + 1] = L["time ran out %s"]:format(ns.Ago(-left)) end
	return bits
end

local function Line(e) return "  " .. e.name .. (e.plain ~= "" and (ns.DETAIL_SEP .. e.plain) or "") .. (e.mine and "" or ("  " .. GREY .. "(" .. e.who .. ")|r")) end
local function Show(e) ns:Output({ Line(e) }) end
local function ShareText(e)
	local a = e.auction
	local what = (a and a.link or e.name) .. ((a and (a.count or 1) > 1 and a.link) and (" x" .. a.count) or "")
	return e.plain ~= "" and (what .. " (" .. e.plain .. ")") or what
end
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end
local CHATBOX = ns.ChatBoxSpec(ShareText)

local function Tooltip(e, t)
	local a, now = e.auction, Now()
	t:SetText(e.name, 1, 0.82, 0)
	local when = (a.seen == "listed" and L["On your Auctions tab %s"] or L["Posted %s"]):format(ns.Ago(now - (a.t or now)))
	t:AddLine(when .. (e.mine and "" or (" " .. L["on %s"]:format(e.who))), 1, 1, 1)
	if a.each or a.price then
		t:AddDoubleLine(a.each and L["Price each"] or L["Price"], Money(a.each or a.price), 1, 1, 1, 1, 1, 1)
		t:AddLine(a.seen == "listed" and L["(as the auction house listed it)"] or L["(as you posted it)"], 0.6, 0.6, 0.6)
	end
	local left = a.ends and (a.ends - now)
	if left then
		t:AddLine(left > 0 and L["%s left"]:format(MA.Left(left)) or L["time ran out %s"]:format(ns.Ago(-left)), 1, 1, 1)
	end
	t:AddLine(L["It leaves this list once it sells, expires, is cancelled or comes back by mail; your Auctions tab's list is read whenever you visit the auction house."],
		0.6, 0.8, 1, true)
	ns.KeyHints(t, L["Enter: show in chat    Shift+Enter: put it in the chat box"], 0.6, 0.6, 0.6, true)
end

local function SoldTooltip(e, t)
	local s, now = e.sale, Now()
	t:SetText(e.name, 1, 0.82, 0)
	t:AddLine(L["Sold %s"]:format(ns.Ago(now - (s.at or now))) .. (e.mine and "" or (" " .. L["on %s"]:format(e.who))), 1, 1, 1)
	if s.each or s.price then t:AddDoubleLine(s.each and L["Price each"] or L["Price"], Money(s.each or s.price), 1, 1, 1, 1, 1, 1) end
	if s.buyer then t:AddDoubleLine(L["Bought by"], s.buyer, 1, 1, 1, 1, 1, 1) end
	if s.net then
		t:AddDoubleLine(L["You got"], Money(s.net), 1, 1, 1, 1, 1, 1)
		t:AddLine(L["(the deposit back, the auction house's cut taken)"], 0.6, 0.6, 0.6)
	end
	t:AddLine(L["Your sales are kept 30 days: each as the auction house tells it, or from its mail once a mailbox shows it."], 0.6, 0.8, 1, true)
	ns.KeyHints(t, L["Enter: show in chat    Shift+Enter: put it in the chat box"], 0.6, 0.6, 0.6, true)
end

--- A sale of yours (MA.KeepSale): "Sold: Linen Cloth x20", its price, its buyer, when.
local function SoldRow(key, i, s, mine, who, now)
	local bits = {}
	if s.each then bits[#bits + 1] = L["%s each"]:format(Money(s.each, true))
	elseif s.price then bits[#bits + 1] = Money(s.price, true) end
	if s.buyer then bits[#bits + 1] = L["to %s"]:format(s.buyer) end
	bits[#bits + 1] = ns.Ago(now - (s.at or now))
	local plain = table.concat(bits, ", ")
	local d = {}
	for _, b in ipairs(bits) do d[#d + 1] = b end
	if not mine then d[#d + 1] = GREY .. who .. "|r" end
	local _, link, q, icon = MA.ItemFacts(nil, s.link, s.item)
	local count = s.count or 1
	return {
		key = "sold:" .. key .. ":" .. tostring(s.auctionID or (tostring(s.at) .. ":" .. i)),
		name = L["Sold"] .. ": " .. s.item .. ((count > 1) and (" x" .. count) or ""),
		sale = s, auction = s, ahKind = "sold", at = s.at, boxKey = key, who = who, mine = mine or nil,
		color = ns.QualityHex(q), icon = icon or ICON, link = link or s.link,
		detail = ns.Detail(unpack(d)), plain = plain,
		text = "auction auctions ah sold sale sales " .. s.item .. " " .. (s.buyer or "") .. " " .. who,
		tooltip = SoldTooltip, activate = Show, secondary = ToChatBox,
		secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = ShareText,
	}
end

--- An auction up now, or whose time ran out.
local function UpRow(key, id, a, mine, who, now)
	local bits = Said(a, now)
	local plain = table.concat(bits, ", ")
	local d = {}
	for _, b in ipairs(bits) do d[#d + 1] = b end
	if not mine then d[#d + 1] = GREY .. who .. "|r" end
	local over = a.ends and a.ends <= now or false
	local _, link, q, icon = MA.ItemFacts(nil, a.link, a.name)
	local name = NameOf(a) .. (((a.count or 1) > 1) and (" x" .. a.count) or "")
	return {
		key = "up:" .. key .. ":" .. id, name = name, auction = a, auctionID = id, ahKind = over and "over" or "up",
		boxKey = key, who = who, mine = mine or nil, ends = a.ends,
		color = over and GREY or ns.QualityHex(q), icon = icon or ICON, link = link or a.link,
		detail = ns.Detail(unpack(d)), plain = plain,
		text = "auction auctions ah " .. (over and "ran out expired " or "listed selling up ") .. NameOf(a) .. " " .. who,
		holders = { { who = who, mine = mine or nil, where = "auctions", count = a.count or 1 } },
		tooltip = Tooltip, activate = Show, secondary = ToChatBox,
		secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = ShareText,
	}
end

function AU.Collect()
	local now, myKey = Now(), MyKey()
	MA.Prune(now)
	local up, over = {}, {}
	for key, posted in pairs(MA.Store("auctionsPosted")) do
		if type(posted) == "table" then
			local who = MA.WhoOf(key)
			for id, a in pairs(posted) do
				if type(a) == "table" then
					local e = UpRow(key, id, a, key == myKey, who, now)
					if e.ahKind == "over" then over[#over + 1] = e else up[#up + 1] = e end
				end
			end
		end
	end
	-- up now: what runs out first, first (yours before your alts' when it's the same); then those whose time ran out
	table.sort(up, function(a, b)
		if (a.ends ~= nil) ~= (b.ends ~= nil) then return a.ends ~= nil end
		if a.ends and a.ends ~= b.ends then return a.ends < b.ends end
		if (a.mine == true) ~= (b.mine == true) then return a.mine == true end
		return a.name < b.name
	end)
	table.sort(over, function(a, b) if a.ends ~= b.ends then return a.ends > b.ends end return a.name < b.name end)
	local rows = {}
	for _, e in ipairs(up) do rows[#rows + 1] = e end
	for _, e in ipairs(over) do rows[#rows + 1] = e end
	local news = MA.NewsRows(now)
	for _, e in ipairs(news) do rows[#rows + 1] = e end -- (then the news, newest first)
	-- then your sales, newest first; one the news still tells (its gold due) once, as the news
	local told = {}
	for _, e in ipairs(news) do
		local a = e.auction
		if e.news == "sold" and a then told[a.auctionID or (a.item .. "@" .. tostring(a.at))] = true end
	end
	local sold = {}
	for _, x in ipairs(MA.Sales()) do
		local s = x.sale
		if not told[s.auctionID or (s.item .. "@" .. tostring(s.at))] then
			sold[#sold + 1] = SoldRow(x.key, x.i, s, x.key == myKey, MA.WhoOf(x.key), now)
		end
	end
	table.sort(sold, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.name < b.name end)
	for _, e in ipairs(sold) do rows[#rows + 1] = e end
	ns.RankInOrder(rows) -- (this order among equal matches)
	list = rows
	return rows
end

local NoteRow = ns.NoteRow

ns:RegisterProvider("auctions", {
	label = L["Auction"],
	color = "ffb98cff", -- (a seal's wax)
	aliases = { "auction", "auctions", "ah" },
	explicit = true, -- (every character's: only with @auction, Simple mode's category, or asked in words)
	refreshOnOpen = 60, -- (the time left moves on)
	events = { "PLAYER_ENTERING_WORLD" },
	guard = 1,
	-- nothing kept anywhere: a line saying so
	leadRow = ns.EmptyLead(function() return AU.NONE end, function() return not (list and #list > 0) end),
	collect = function() return AU.Collect() end,
})

----------------------------------------------------------------------
-- The question: "my auctions", "what am i selling", "auctions sold"
----------------------------------------------------------------------

local ASK = {}
for w in ([[my me i im am the a an of is are do does did have has got any whats what which how much many show list check see all
	for on there theres still currently now any]]):gmatch("%a+") do ASK[w] = true end
local SUBJECT = { auction = true, auctions = true, ah = true, listings = true, listing = true }
-- the auctioneer's words too (Simple mode's role words: "auction", "ah"): about your auctions only when asked
local WEAK = { auction = true, ah = true }
local CUE = { sold = "sold", selling = "up", listed = "up", up = "up", posted = "up", active = "up", sell = "up" }
-- "auction mail" is the mail's question (Mail.lua)
local MAIL = { mail = true, mails = true, mailbox = true, inbox = true, letter = true, letters = true }

--- The question: { words = what narrows it, sold, up }, or nil when the line isn't asking about your auctions. "auctions"
--- alone or asked ("my auctions", "what am i selling"); "auction" and "ah" only asked ("my ah": they're the auctioneer
--- too); other words only asked ("auction house" stays a search).
function AU.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	local subject, weak, asked, cues, rest, selling = false, true, false, {}, {}, false
	for w in t:gmatch("%S+") do
		if MAIL[w] then return nil end
		if SUBJECT[w] then subject = true; weak = weak and WEAK[w] == true
		elseif CUE[w] then cues[CUE[w]] = true; selling = selling or w ~= "up"
		elseif ASK[w] then asked = true
		else rest[#rest + 1] = w end
	end
	-- "what am i selling": selling with asking words is about your auctions too ("what's up" isn't: 0.49.2, review)
	if not subject and not (cues.up and selling and asked and #rest == 0) then return nil end
	if subject and weak and not asked and not next(cues) then return nil end
	-- other words: asked, and with what auctions do (sold, selling, listed) or "auctions" itself, as the mail's question
	-- does ("where is the ah", "show me the auction house" are searches: they said "No auction has that"; 0.49.2, review)
	if #rest > 0 and not (asked and (selling or not weak)) then return nil end
	return { words = rest, sold = cues.sold, up = cues.up and not cues.sold or nil }
end

function AU.Answer(q)
	q = q or {}
	local p = ns.providers.auctions
	local all = p and ns:GetEntries(p) or {}
	local rows = {}
	-- (the filters Alt+` writes, is:sold and is:listed: one test for both ways of asking; Filters/Others.lua)
	local F = ns.Filters
	local sold, listed = F.Parse("is:sold"), F.Parse("is:listed")
	for _, e in ipairs(all) do
		local ok = true
		if q.sold and not sold(e) then ok = false end
		if q.up and not listed(e) then ok = false end
		local hay = ok and (Lower(e.name) .. " " .. (e._ltext or Lower(e.text or ""))) or ""
		for _, w in ipairs(q.words or {}) do if ok and not hay:find(w, 1, true) then ok = false end end
		if ok then rows[#rows + 1] = e end
	end
	ns.ScoreInOrder(rows)
	if #rows == 0 then
		if #all == 0 then return { NoteRow(AU.NONE) }, AU.NOTE end
		return { NoteRow(L["No auction has that"]) }, AU.NOTE
	end
	local up = 0
	for _, e in ipairs(rows) do if e.ahKind == "up" then up = up + 1 end end
	return rows, AU.NOTE .. ns.DETAIL_SEP .. L["%d up now"]:format(up)
end

--- The question as Advanced syntax (Alt+`): "@auction is:sold linen".
function AU.ToAdvanced(q)
	local parts = { "@auction" }
	if q.sold then parts[#parts + 1] = "is:sold" end
	if q.up then parts[#parts + 1] = "is:listed" end
	for _, w in ipairs(q.words or {}) do parts[#parts + 1] = w end
	return table.concat(parts, " ") .. " "
end

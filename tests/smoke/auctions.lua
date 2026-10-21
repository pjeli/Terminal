-- @auction (0.56.12, a player: "auctions" listed what was up and what failed, never what sold; one up had no price):
-- your sales kept 30 days (the news, the Auctions tab's Sold, the sale's mail), posts made together each with its own
-- price, and a price the post left out taken from the Auctions tab's list.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[auctions]\n")
do
	local MA, A = ns.Mail, ns.providers.auctions
	local save = { guid = _G.UnitGUID, time = _G.time, AH = _G.C_AuctionHouse, Item = _G.C_Item, hook = _G.hooksecurefunc,
		hooked = MA.postHooked, Enum = _G.Enum, cname = ns.CharacterName,
		dbs = { posted = ns.db.auctionsPosted, ended = ns.db.auctionsEnded, sold = ns.db.auctionsSold, news = ns.db.mailAuctions,
			bids = ns.db.auctionBids, boxes = ns.db.mailboxes } }
	local ok, err = pcall(function()
		local now, ME, DAY = 7000000, "Player-1-AUC", 86400
		_G.time = function() return now end
		_G.UnitGUID = function() return ME end
		ns.CharacterName = function() return "Seller" end
		ns.db.auctionsPosted, ns.db.auctionsEnded, ns.db.auctionsSold, ns.db.mailAuctions, ns.db.auctionBids = {}, {}, {}, {}, {}
		local function L(id, name) return "|cffffffff|Hitem:" .. id .. "|h[" .. name .. "]|h|r" end
		_G.C_Item = setmetatable({ GetItemLink = function(loc) return loc.link end, GetItemName = function(loc) return loc.name end },
			{ __index = save.Item })
		local owned = {}
		_G.C_AuctionHouse = { PostItem = function() end, PostCommodity = function() end,
			GetNumOwnedAuctions = function() return #owned end, GetOwnedAuctionInfo = function(i) return owned[i] end }
		_G.hooksecurefunc = function(t, name, fn)
			local orig = t[name]
			t[name] = function(...) orig(...); fn(...) end
		end
		_G.Enum = setmetatable({ AuctionStatus = { Active = 0, Sold = 1 } }, { __index = save.Enum })
		MA.postHooked = nil
		check(MA.HookPost(), "(posting hooked)")
		local AH = _G.C_AuctionHouse

		-- two posted before the game says either was made: each its own price (one slot gave the first the second's)
		AH.PostItem({ link = L(2589, "Linen Cloth"), name = "Linen Cloth" }, 1, 20, nil, 4500)
		AH.PostItem({ link = L(2592, "Wool Cloth"), name = "Wool Cloth" }, 1, 5, nil, 12000)
		MA.OnEvent("AUCTION_HOUSE_AUCTION_CREATED", 101)
		MA.OnEvent("AUCTION_HOUSE_AUCTION_CREATED", 102)
		local posted = ns.db.auctionsPosted[ME]
		check(posted[101] and posted[101].name == "Linen Cloth" and posted[101].price == 4500
			and posted[102] and posted[102].name == "Wool Cloth" and posted[102].price == 12000,
			"two posts at once: each auction its own item and price: " .. tostring(posted[101] and posted[101].price) .. ", "
			.. tostring(posted[102] and posted[102].price))

		-- kept with no price (or another item's facts): the Auctions tab's list puts it right
		posted[103] = { name = "Silk Cloth", link = L(4306, "Silk Cloth"), count = 2, t = now, seen = "posted" }
		posted[104] = { name = "Linen Cloth", link = L(2589, "Linen Cloth"), count = 20, price = 4500, t = now - 5, seen = "posted" }
		-- (kept before 0.63.1: the list's price for one taken for the whole x16)
		posted[105] = { name = "Linen Cloth", link = L(2589, "Linen Cloth"), count = 16, price = 19, t = now, seen = "listed" }
		owned = {
			{ auctionID = 101, itemLink = L(2589, "Linen Cloth"), quantity = 20, buyoutAmount = 225, timeLeftSeconds = 3600, status = 0 },
			{ auctionID = 102, itemLink = L(2592, "Wool Cloth"), quantity = 5, buyoutAmount = 2400, timeLeftSeconds = 3600, status = 0 },
			{ auctionID = 103, itemLink = L(4306, "Silk Cloth"), quantity = 2, buyoutAmount = 900, timeLeftSeconds = 7200, status = 0 },
			{ auctionID = 104, itemLink = L(4338, "Mageweave Cloth"), quantity = 10, buyoutAmount = 300, timeLeftSeconds = 7200, status = 0 },
			{ auctionID = 105, itemLink = L(2589, "Linen Cloth"), quantity = 16, buyoutAmount = 19, timeLeftSeconds = 7200, status = 0 },
		}
		MA.OnEvent("OWNED_AUCTIONS_UPDATED")
		-- (0.63.1, a player in game: the list's price is for one; the auction brings that times how many)
		check(posted[103] and posted[103].each == 900 and posted[103].price == 1800, "no price kept: the Auctions tab's, for one: " .. tostring(posted[103] and posted[103].price))
		check(posted[104] and posted[104].name == "Mageweave Cloth" and posted[104].price == 3000 and posted[104].count == 10
			and posted[104].t == now - 5, "another item's facts: the list's own (when it was posted kept)")
		check(posted[105].each == 19 and posted[105].price == 304, "kept with the price for one as the whole: put right: "
			.. tostring(posted[105].each) .. ", " .. tostring(posted[105].price))
		A._dirty = true
		local priced = 0
		for _, e in ipairs(UI:Search("@auction")) do
			if e.ahKind == "up" and e.detail:find("[0-9]+[gsc]") then priced = priced + 1 end
		end
		check(priced == 5, "every auction up now shows a price: " .. priced)

		-- sold, the auction house says: the news for its hour, then kept as a sale
		now = now + 60
		MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Linen Cloth", 101)
		local sales = ns.db.auctionsSold[ME]
		check(sales and #sales == 1 and sales[1].auctionID == 101 and sales[1].price == 4500 and sales[1].count == 20,
			"a sale kept, its price and count from the post")
		A._dirty = true
		local res = UI:Search("@auction linen")
		local n, soldNews = 0, nil
		for _, e in ipairs(res) do
			if e.name == "Sold: Linen Cloth x20" then n = n + 1; soldNews = e end
		end
		check(n == 1 and soldNews.mailKind == "auction", "while the news tells it (its gold due): once, as the news")
		-- sold on the Auctions tab's list (seen before the news came): kept too
		owned[1].status, owned[2].status = 1, 1
		MA.OnEvent("OWNED_AUCTIONS_UPDATED")
		check(#sales == 2 and sales[1].auctionID == 102 and sales[1].price == 12000 and posted[102] == nil, "the Auctions tab's Sold: a sale")
		MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Wool Cloth", 102)
		check(#sales == 2, "the news of it after: still one sale")
		-- news with no id (a chat line), told twice: one sale
		MA.OnAuction("sold", "Copper Bar")
		MA.OnAuction("sold", "Copper Bar")
		check(#sales == 3 and sales[1].item == "Copper Bar" and sales[1].auctionID == nil, "a sale told by name, twice: once")

		-- the sale's mail: the buyer and what you got written on it; a sale Terminal didn't see, kept from its mail
		now = now + 2 * 3600
		local box = { mails = {
			{ first = now - 600, expires = now - 600 + 30 * DAY, auction = "sold", money = 4400,
				invoice = { kind = "seller", item = "Linen Cloth", player = "Zed", bid = 4500, deposit = 100, cut = 200, count = 20 } },
			{ first = now - 300, expires = now - 3 * DAY + 30 * DAY, auction = "sold", money = 800,
				invoice = { kind = "seller", item = "Thorium Bar", player = "Ann", bid = 1000, deposit = 0, cut = 50, count = 4 } },
		} }
		check(MA.SalesFromMail(box, now) == 1, "one sale only its mail tells")
		local linen, thorium
		for _, s in ipairs(sales) do
			if s.item == "Linen Cloth" then linen = s elseif s.item == "Thorium Bar" then thorium = s end
		end
		check(linen and linen.buyer == "Zed" and linen.net == 4400, "the mail's buyer and what you got, on the sale kept")
		check(thorium and thorium.buyer == "Ann" and thorium.seen == "mail" and math.abs(thorium.at - (now - 3 * DAY - 3600)) < 2,
			"sold while Terminal wasn't watching: kept from its mail, when it sold (its mail's 30 days): " .. tostring(thorium and (now - thorium.at)))
		check(MA.SalesFromMail(box, now) == 0 and #sales == 4, "the inbox read again: nothing doubled")
		-- (0.63.2, a player: the sale's mail read first before the game had the buyer's name, then with it: one sale)
		local nameless = { mails = { { first = now - 200, expires = now - 200 + 30 * DAY, auction = "sold", money = 491,
			invoice = { kind = "seller", item = "Chunk of Boar Meat", bid = 411, deposit = 100, cut = 20, count = 1 } } } }
		check(MA.SalesFromMail(nameless, now) == 1, "a sale's mail read before its buyer is known: kept")
		nameless.mails[1].invoice.player = "Yur"
		check(MA.SalesFromMail(nameless, now) == 0, "read again with its buyer: not a new sale")
		local boar = {}
		for _, s in ipairs(sales) do if s.item == "Chunk of Boar Meat" then boar[#boar + 1] = s end end
		check(#boar == 1 and boar[1].buyer == "Yur", "one sale, with its buyer: " .. #boar)
		-- (kept twice before 0.63.2: the one without its buyer goes when the mail is read again)
		table.insert(sales, 1, { item = "Chunk of Boar Meat", at = now - 199, seen = "mail", count = 1, price = 411,
			inv = "Chunk of Boar Meat|1|411|#1" })
		MA.SalesFromMail(nameless, now)
		boar = {}
		for _, s in ipairs(sales) do if s.item == "Chunk of Boar Meat" then boar[#boar + 1] = s end end
		check(#boar == 1 and boar[1].buyer == "Yur", "kept twice before: one again: " .. #boar)
		for i = #sales, 1, -1 do if sales[i].item == "Chunk of Boar Meat" then table.remove(sales, i) end end
		local order = {}
		for _, s in ipairs(sales) do order[#order + 1] = s.item end
		check(order[4] == "Thorium Bar", "kept newest first: " .. table.concat(order, ", "))

		-- @auction: the news's hour over, the sales still listed, after what's up, newest first
		A._dirty = true
		res = UI:Search("@auction")
		local sold, upAt, firstSold = {}, nil, nil
		for i, e in ipairs(res) do
			if e.ahKind == "up" or e.ahKind == "over" then upAt = i end
			if e.ahKind == "sold" then sold[#sold + 1] = e; firstSold = firstSold or i end
		end
		check(#sold == 4 and upAt and firstSold > upAt, "four sales, after the auctions up (or run out): " .. #sold)
		local zed
		for _, e in ipairs(sold) do if e.name == "Sold: Linen Cloth x20" then zed = e end end
		check(zed and zed.detail:find("45s", 1, true) and zed.detail:find("to Zed", 1, true) and zed.detail:find("ago", 1, true),
			"a sale: its price, its buyer, when: " .. tostring(zed and zed.detail))
		local tip = T.TooltipText and T.TooltipText(zed) or nil
		check(tip == nil or tip:find("Zed", 1, true), "(its tooltip names the buyer)")
		-- "auctions sold", @auction is:sold: the sales
		local F = ns.Filters
		check(F.Parse("is:sold")(zed), "is:sold: a sale kept")
		local ans = ns.Auctions.Answer(ns.Auctions.Question("auctions sold"))
		local nSold = 0
		for _, e in ipairs(ans) do if e.ahKind == "sold" then nSold = nSold + 1 end end
		check(nSold == 4, "\"auctions sold\": the sales: " .. nSold)

		-- (release review) the chat line first, the notification with its id after: one sale, given the id
		ns.db.auctionsSold[ME] = {}
		sales = ns.db.auctionsSold[ME]
		posted[301] = { name = "Iron Bar", link = L(3575, "Iron Bar"), count = 5, price = 700, t = now, seen = "posted" }
		MA.OnAuction("sold", "Iron Bar")
		MA.OnEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Iron Bar", 301)
		check(#sales == 1 and sales[1].auctionID == 301, "the chat line, then the notification: one sale, with its id: " .. #sales)
		-- (review, 0.57.7) and with its posted price, on the sale and on the news
		check(sales[1].price == 700 and sales[1].count == 5, "...and its posted price and count: " .. tostring(sales[1].price))
		local news
		for _, n in ipairs(ns.db.mailAuctions[ME] or {}) do if n.item == "Iron Bar" and n.kind == "sold" then news = n end end
		check(news and news.price == 700 and news.auctionID == 301, "the news too: " .. tostring(news and news.price))
		-- alike sale mails, the same item, price and buyer: a sale each
		local alike = { mails = {} }
		for k = 1, 3 do
			alike.mails[k] = { first = now - 100, expires = now - 2 * DAY + 30 * DAY, auction = "sold",
				invoice = { kind = "seller", item = "Gold Bar", player = "Kim", bid = 5000, deposit = 0, cut = 250, count = 1 } }
		end
		check(MA.SalesFromMail(alike, now) == 3 and MA.SalesFromMail(alike, now) == 0, "three alike sale mails: three sales, once")
		-- a commodity sold whose entry has no link: named by its item id
		local wasName = _G.C_Item.GetItemNameByID
		rawset(_G.C_Item, "GetItemNameByID", function(id) return id == 2589 and "Linen Cloth" or nil end)
		owned = { { auctionID = 401, itemKey = { itemID = 2589 }, quantity = 40, buyoutAmount = 30, status = 1 } }
		MA.OnEvent("OWNED_AUCTIONS_UPDATED")
		local linenSale
		for _, s2 in ipairs(sales) do if s2.auctionID == 401 then linenSale = s2 end end
		check(linenSale and linenSale.item == "Linen Cloth" and linenSale.price == 1200, "a commodity with no link: its sale named by its id")
		rawset(_G.C_Item, "GetItemNameByID", wasName)
		-- a post the game refuses leaves the line: the next one made gets its own price
		AH.PostItem({ link = L(2770, "Copper Ore"), name = "Copper Ore" }, 1, 20, nil, 111)
		MA.OnEvent("AUCTION_HOUSE_POST_ERROR")
		AH.PostItem({ link = L(2771, "Tin Ore"), name = "Tin Ore" }, 1, 20, nil, 222)
		MA.OnEvent("AUCTION_HOUSE_AUCTION_CREATED", 501)
		check(posted[501] and posted[501].name == "Tin Ore" and posted[501].price == 222 and MA.PendingPosts() == 0,
			"a refused post: the next one keeps its own price: " .. tostring(posted[501] and posted[501].name))

		-- kept 30 days
		now = now + 30 * DAY
		MA.Prune(now)
		check(#ns.db.auctionsSold[ME] == 0, "past 30 days: gone")
	end)
	_G.UnitGUID, _G.time, _G.C_AuctionHouse, _G.C_Item, _G.hooksecurefunc = save.guid, save.time, save.AH, save.Item, save.hook
	MA.postHooked, _G.Enum, ns.CharacterName = save.hooked, save.Enum, save.cname
	ns.db.auctionsPosted, ns.db.auctionsEnded, ns.db.auctionsSold, ns.db.mailAuctions = save.dbs.posted, save.dbs.ended, save.dbs.sold, save.dbs.news
	ns.db.auctionBids, ns.db.mailboxes = save.dbs.bids, save.dbs.boxes
	ns.providers.auctions._dirty = true
	UI:Hide(); FlushAll()
	if not ok then check(false, "auctions: " .. tostring(err)) end
end

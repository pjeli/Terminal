-- (0.62.0, the player's ask) Auctionator: its public API (Auctionator.API.v1) gives items their auction house price
-- (ahprice, ahvalue: "| sum ahvalue", sort:ahvalue), your bag items worth posting (is:auctionable, "what should i
-- auction", "what should i do"'s "Post on the auction house"), @auction's price now and is:undercut, "ah value of my
-- mats", and an empty prompt example. Without it: none of that, and nothing breaks.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L = ns.L
local AN, A, F = ns.Auctionator, ns.Aggregate, ns.Filters
io.write("[auctionator: auction house prices from its public API]\n")
check(AN and not AN.On(), "Auctionator.lua loaded; without Auctionator: off")
check(AN.Price(2589) == nil and AN.ValueOf({ kind = "items", itemID = 2589, count = 5 }) == nil, "without it: no price")
check(not ns.AuctionatorQ.Question("what should i auction"), "without it: \"what should i auction\" isn't asked")
check(AN.ValueQuestion("ah value of my mats") == nil and ns.PerField.Line("ah value of my mats") == nil, "without it: \"ah value of my mats\" isn't rewritten")
check(ns.Integrations.AddonMissing("Auctionator"), "the hint system knows it's missing")
-- (review) without it, "undercut" is a word of the search: not your auctions' question saying none is
check(ns.Auctions.Question("am i undercut") == nil and ns.Auctions.Question("undercut") == nil and ns.Auctions.Question("beaten") == nil,
	"without it: \"am i undercut\" isn't asked")

local save = { ac = rawget(_G, "Auctionator"), addons = _G.C_AddOns, item = C_Item.GetItemInfo, providers = ns.providers,
	order = ns.providerOrder, easy = ns.db.easyMode }
-- Auctionator's API for other addons, as its documentation gives it: a caller's name first; prices in copper; nil
-- for an item it hasn't seen
local PRICES = { [2589] = 50, [2592] = 120, [4306] = 300, [2772] = 900, [6948] = nil, [1] = 5, [99] = 2000 }
local AGES = { [2589] = 0, [2592] = 3 }
local asked, dbUpdate = 0, nil
local api = {
	GetAuctionPriceByItemID = function(caller, id)
		assert(type(caller) == "string" and caller ~= "", "callerID")
		asked = asked + 1
		return PRICES[id]
	end,
	GetAuctionPriceByItemLink = function(caller, link)
		assert(type(caller) == "string", "callerID")
		local id = tonumber(link:match("|Hitem:(%d+)"))
		asked = asked + 1
		if link:find(":1234:", 1, true) then return nil end -- (a copy it hasn't seen)
		return PRICES[id]
	end,
	GetAuctionAgeByItemID = function(caller, id) return AGES[id] end,
	GetAuctionAgeByItemLink = function(caller, link) return AGES[tonumber(link:match("|Hitem:(%d+)"))] end,
	RegisterForDBUpdate = function(caller, cb) dbUpdate = cb end,
}
_G.Auctionator = { API = { v1 = api } }
_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) return n == "Auctionator" or save.addons.IsAddOnLoaded(n) end },
	{ __index = save.addons })
-- what a vendor pays (GetItemInfo's 11th)
local VENDOR = { [2589] = 13, [2592] = 25, [4306] = 150, [2772] = 1000, [6948] = 0, [1] = 1, [99] = 500 }
C_Item.GetItemInfo = function(id)
	if not VENDOR[id] then return save.item(id) end
	return "Item " .. id, "|cffffffff|Hitem:" .. id .. "::::::::|h[Item " .. id .. "]|h|r", 1, 10, 1, "Trade Goods", "Cloth", 20, "", 0, VENDOR[id], 7, 5, 0
end
F.ClearCache()
AN.Forget()
AN.Setup()
check(AN.On() and dbUpdate ~= nil, "with it: on, and told when its prices change (RegisterForDBUpdate)")
check(not ns.Integrations.AddonMissing("Auctionator"), "not missing")
check(AN.Status():find("found", 1, true), ".integrations: " .. AN.Status())

-- prices: asked once an item till its data changes
asked = 0
check(AN.Price(2589) == 50 and AN.Price(2589) == 50 and asked == 1, "asked once: " .. asked)
check(AN.Price(6948) == nil and AN.Price(6948) == nil and asked == 2, "not seen: nil, asked once too: " .. asked)
PRICES[2589] = 60
dbUpdate()
check(AN.Price(2589) == 60, "its data changed: asked again")
PRICES[2589] = 50
-- (no word from Auctionator: kept AN.KEEP seconds, then asked again)
do
	local realTime, now = _G.GetTime, 1000
	_G.GetTime = function() return now end
	AN.Forget()
	asked = 0
	AN.Price(2589); AN.Price(2589)
	now = now + AN.KEEP - 1
	AN.Price(2589)
	check(asked == 1, "kept a while: " .. asked)
	now = now + 2
	AN.Price(2589)
	check(asked == 2, "then asked again: " .. asked)
	_G.GetTime = realTime
end
AN.Forget()

-- your bags: what's worth posting
local function Link(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[Item " .. id .. "]|h|r" end
local ROWS = {
	{ name = "Linen Cloth", itemID = 2589, count = 20, unbound = true },        -- 50 each on the AH, 13 at a vendor
	{ name = "Wool Cloth", itemID = 2592, count = 10, unbound = true },         -- 120 vs 25
	{ name = "Iron Bar", itemID = 2772, count = 3, unbound = true },            -- 900 vs 1000: a vendor pays more
	{ name = "Hearthstone", itemID = 6948, count = 1, bound = true },           -- bound, never seen
	{ name = "Soulbound Ring", itemID = 99, count = 1, bound = true },          -- bound (a price for another copy)
	{ name = "Quest Thing", itemID = 4306, count = 2, unbound = true, questItem = true },
	{ name = "Worn Sword", itemID = 1, count = 1, slotId = 16, unbound = true }, -- worn: not for sale
}
ns.providers, ns.providerOrder = {}, {}
local function Reg(id, aliases, want)
	ns:RegisterProvider(id, { label = id, aliases = aliases, collect = function()
		local out = {}
		for i, r in ipairs(ROWS) do
			if not want or want(r) then
				local e = {}
				for k, v in pairs(r) do e[k] = v end
				e.key, e.link = i, Link(r.itemID)
				if not r.slotId then e.locs = { { 0, i } } end
				out[#out + 1] = e
			end
		end
		return out
	end })
end
Reg("items", { "item", "items", "bag", "bags" })
Reg("mats", { "mats", "mat" }, function(r) return r.itemID == 2589 or r.itemID == 2592 or r.itemID == 2772 end)
ns:AliasesChanged()
local items = ns:GetEntries(ns.providers.items)
local by = {}
for _, e in ipairs(items) do by[e.name] = e end
-- (review) a row with some stacks bound: not for sale (its count would take them in); worn and bound: no AH value
local mixed = { kind = "items", itemID = 2592, count = 4, bound = true, unbound = true, locs = { { 0, 1 } }, link = Link(2592) }
check(not AN.Auctionable(mixed) and AN.ValueOf(mixed) == nil, "some stacks bound: not auctionable, no value")
check(AN.ValueOf(by["Worn Sword"]) == nil and AN.ValueOf(by["Soulbound Ring"]) == nil and AN.PriceOf(by["Soulbound Ring"]) == 2000,
	"worn, bound: no value (the price is still said)")
-- (review) a copy with a random suffix Auctionator hasn't seen: not the plain item's price
check(AN.Price(2592, "|cffffffff|Hitem:2592::::::1234:::|h[x]|h|r") == nil, "a suffixed copy unseen: no price (not the plain item's)")
check(AN.PriceOf(by["Linen Cloth"]) == 50 and AN.ValueOf(by["Linen Cloth"]) == 1000, "Linen Cloth: 50 each, 1000 for 20")
check(AN.Auctionable(by["Linen Cloth"]) and AN.Auctionable(by["Wool Cloth"]), "cloth: worth posting")
check(not AN.Auctionable(by["Iron Bar"]), "a vendor pays more: not")
check(not AN.Auctionable(by["Hearthstone"]) and not AN.Auctionable(by["Soulbound Ring"]), "bound: not")
check(not AN.Auctionable(by["Quest Thing"]) and not AN.Auctionable(by["Worn Sword"]), "a quest's, a worn one: not")
local rows, total = AN.ToPost(true)
check(#rows == 2 and total == 1000 + 1200, "two to post, 22s in all: " .. #rows .. ", " .. total)

local function Names(res)
	local t = {}
	for _, e in ipairs(res or {}) do if ns.Bar.Real(e) then t[#t + 1] = tostring(e.name) end end
	return table.concat(t, " | ")
end
ns.db.easyMode = false; UI:EasyChanged()
UI.lastScan, UI.lastExtra = nil, nil
-- the filter, the sort, the sums
check(Names(UI:Search("@item is:auctionable sort:ahvalue")) == "Wool Cloth | Linen Cloth", "is:auctionable sort:ahvalue: "
	.. Names(UI:Search("@item is:auctionable sort:ahvalue")))
UI:Open("@mats | sum ahvalue"); FlushAll()
local sum = UI.Results()
UI:Hide(); FlushAll()
check(sum[1] and ns.Plain(sum[1].name):find(ns.Plain(ns.Money(1000 + 1200 + 2700)), 1, true),
	"@mats | sum ahvalue: Linen, Wool and Iron (49s): " .. tostring(sum[1] and ns.Plain(sum[1].name)))
check(Names(UI:Search("@item sort:ahprice")):find("^Soulbound Ring | Iron Bar") ~= nil, "sort:ahprice: the dearest each first: " .. Names(UI:Search("@item sort:ahprice")))
-- (0.62.2, the player: the value went from the details once the line was a search, "@item @mybank is:auctionable
-- sort:ahvalue") sorted by AH value, or is:auctionable: each row's detail says what it brings, then where it is
for _, line in ipairs({ "@item is:auctionable sort:ahvalue ", "@item sort:ahvalue ", "@item is:auctionable " }) do
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open(""); UI:SetQuery(line, #line); FlushAll()
	local shown
	for i = 1, 10 do
		local row = UI.rows[i]
		if row and row.label:GetText() and row.label:GetText():find("Wool Cloth", 1, true) then shown = row.detail:GetText() end
	end
	check(shown and shown:find(L["AH %s each"]:format(ns.Money(120)), 1, true) and shown:find(L["x%d: %s"]:format(10, ns.Money(1200)), 1, true),
		line .. ": the detail says what it brings: " .. tostring(shown))
	UI:Hide(); FlushAll()
end
UI.lastScan, UI.lastExtra = nil, nil
UI:Open(""); UI:SetQuery("@item wool ", 11); FlushAll()
check(UI.rows[1].detail:GetText() == (by["Wool Cloth"].detail or ""), "not sorted by it: the row's own detail")
UI:Hide(); FlushAll()
check(F.SortOf("sort:ahvalue") == "ahvalue" and F.Parse("is:auctionable") ~= nil and F.Parse("is:undercut") ~= nil, "sort:ahvalue, is:auctionable, is:undercut")
local offered = false
for _, o in ipairs(ns.Bar.SORTS) do if o.id == "ahvalue" then offered = true end end
check(offered, "the bar's Sort: AH value")

-- the questions, and their Advanced syntax
local Q = ns.AuctionatorQ
for _, s in ipairs({ "what should i auction", "What can I sell on the AH?", "what to post", "auctionable items", "what should i sell on the auction house" }) do
	check(Q.Question(s) ~= nil, "asked: " .. s)
end
check(not Q.Question("auction") and not Q.Question("what should i auction linen"), "not every line with auction")
check(ns.QuestionToAdvanced("what should i auction") == "@item is:auctionable sort:ahvalue ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("what should i auction")))
for line, want in pairs({ ["ah value of my mats"] = "@mats | sum ahvalue ", ["what are my mats worth"] = "@mats | sum ahvalue ",
	["mats ah value"] = "@mats | sum ahvalue ", ["ah value of my bags"] = "@item in:bags | sum ahvalue ",
	["how much are my consumables worth on the ah"] = "@consumables | sum ahvalue " }) do
	local q = AN.ValueQuestion(line)
	check(q and q.line == want, ("%q: %s"):format(line, tostring(q and q.line)))
	check(ns.QuestionToAdvanced(line) == want, "Alt+`: " .. tostring(ns.QuestionToAdvanced(line)))
end
check(AN.ValueQuestion("mats") == nil and AN.ValueQuestion("ah value of hogger") == nil, "not every line")
for _, simple in ipairs({ true, false }) do
	ns.db.easyMode = simple; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open("what should i auction"); FlushAll()
	local res = UI.Results()
	check(Names(res) == "Wool Cloth | Linen Cloth", (simple and "Simple" or "Advanced") .. ": what should i auction: " .. Names(res))
	check(res[1] and res[1].detail:find(ns.Money(120), 1, true) and res[1].detail:find(ns.Money(1200), 1, true),
		"each says what it would bring: " .. tostring(res[1] and res[1].detail))
	check(res[2] and res[2].detail:find(L["vendor %s"]:format(ns.Money(260)), 1, true), "and what a vendor pays: " .. tostring(res[2] and res[2].detail))
	check(UI.answerNote and UI.answerNote:find(AN.About(2200), 1, true), "the note: about what they come to: " .. tostring(UI.answerNote))
	check(by["Linen Cloth"].detail == nil, "(the item's own row keeps its detail)")
	UI:Hide(); FlushAll()
	UI:Open("ah value of my mats"); FlushAll()
	res = UI.Results()
	check(res[1] and ns.Plain(res[1].name):find(ns.Plain(ns.Money(4900)), 1, true), "ah value of my mats: " .. tostring(res[1] and ns.Plain(res[1].name)))
	UI:Hide(); FlushAll()
end

-- (0.62.1, the player: "by default we can assume bags / @items but it is worth it to allow inclusion of bank or alts")
do
	local function H(who, where, n, mine) return { key = who .. "|" .. where, who = who, where = where, count = n, mine = mine } end
	local STORED = {
		{ name = "Linen Cloth", id = 2589, holders = { H("Me", "bags", 20, true), H("Me", "bank", 30, true), H("Alt", "bank", 100) } },
		{ name = "Wool Cloth", id = 2592, holders = { H("Alt", "bags", 5), H("Alt", "equipped", 1), H("Guild", "guild", 50) } },
		{ name = "Iron Bar", id = 2772, holders = { H("Me", "bank", 9, true) } }, -- (a vendor pays more)
	}
	ns:RegisterProvider("stored", { label = "Alts & bank", aliases = { "stored", "alts" }, explicit = true, collect = function()
		local out = {}
		for i, r in ipairs(STORED) do
			local hs, total = {}, 0
			for _, h in ipairs(r.holders) do hs[h.key] = h; total = total + h.count end
			out[i] = { name = r.name, key = r.id, itemID = r.id, holders = hs, total = total, link = Link(r.id) }
		end
		return out
	end })
	ns:AliasesChanged()
	local st = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.stored)) do st[e.name] = e end
	check(AN.ValueOf(st["Wool Cloth"]) == 5 * 120, "@stored's AH value: what could be posted (not worn, not the guild's): " .. tostring(AN.ValueOf(st["Wool Cloth"])))
	check(AN.Auctionable(st["Linen Cloth"]) and not AN.Auctionable(st["Iron Bar"]), "@stored is:auctionable")
	local Q = ns.AuctionatorQ
	local function Places(line) local q = Q.Question(line) return q and q.places end
	local pl = Places("what should i auction in my bank")
	check(pl and pl.bank and not pl.bags and not pl.alts, "\"... in my bank\": the bank")
	pl = Places("what can i sell on the ah on my alts")
	check(pl and pl.alts and not pl.bank, "\"... on my alts\": the alts")
	pl = Places("what should i auction everywhere")
	check(pl and pl.bags and pl.bank and pl.alts, "\"... everywhere\": all of them")
	pl = Places("what to post from my bags and bank")
	check(pl and pl.bags and pl.bank and not pl.alts, "\"... bags and bank\"")
	check(Q.Question("what should i auction in hogger") == nil, "another word: not it")
	check(ns.QuestionToAdvanced("what should i auction in my bank") == "@bank is:auctionable sort:ahvalue "
		and ns.QuestionToAdvanced("what should i auction on my alts") == "@stored is:auctionable sort:ahvalue ", "as Advanced: @bank, @stored")
	local function Answer(line)
		local rows = Q.Answer(Q.Question(line))
		local t = {}
		for _, e in ipairs(rows) do t[#t + 1] = e.name .. "=" .. tostring(e._ahvalue) end
		return table.concat(t, " | "), rows
	end
	check(Answer("what should i auction in my bank") == "Linen Cloth=1500", "your bank: 30 linen: " .. Answer("what should i auction in my bank"))
	check(Answer("what should i auction on my alts") == "Linen Cloth=5000 | Wool Cloth=600", "your alts: their linen, wool (not worn, not the guild's): "
		.. Answer("what should i auction on my alts"))
	local all, rows = Answer("what should i auction everywhere")
	check(all == "Linen Cloth=7500 | Wool Cloth=1800", "everywhere: bags 20 + bank 30 + alt 100 linen; bags 10 + alt 5 wool: " .. all)
	check(rows[1].detail:find(L["bank"], 1, true), "each says where: " .. rows[1].detail)
	ns.providers.stored = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "stored" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
end

-- (release review, 0.63.0)
do
	local function H(who, where, n, mine) return { key = who .. "|" .. where, who = who, where = where, count = n, mine = mine } end
	local STORED = {
		{ name = "Linen Cloth", id = 2589, holders = { H("Me", "bank", 12, true), H("Me", "mail", 3, true), H("Warband", "warband", 4), H("Alt", "bags", 5) } },
		{ name = "Hearthstone", id = 6948, holders = { H("Me", "bank", 1, true) } },
	}
	ns:RegisterProvider("stored", { label = "Alts & bank", aliases = { "stored", "alts" }, explicit = true, collect = function()
		local out = {}
		for i, r in ipairs(STORED) do
			local hs, total = {}, 0
			for _, h in ipairs(r.holders) do hs[h.key] = h; total = total + h.count end
			out[i] = { name = r.name, key = r.id, itemID = r.id, holders = hs, total = total, link = Link(r.id), detail = "x" .. total .. ns.DETAIL_SEP .. "4 places" }
		end
		return out
	end })
	ns:AliasesChanged()
	local st = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.stored)) do st[e.name] = e end
	-- the detail of a search sorted by AH value: no separator left over from the count taken off
	local d = AN.DetailFor(st["Linen Cloth"], "ahvalue")
	check(d and not d:find(ns.DETAIL_SEP .. ns.DETAIL_SEP, 1, true) and not d:find("·%s*·") and d:find("4 places", 1, true), "one separator each: " .. tostring(d))
	-- a held item bound on pickup: not worth posting, whatever the price
	PRICES[6948], VENDOR[6948] = 5000, 0
	local saveInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(id)
		if id == 6948 then return "Hearthstone", Link(6948), 1, 1, 1, "Misc", "Junk", 1, "", 0, 0, 15, 0, 1 end
		return saveInfo(id)
	end
	F.ClearCache(); AN.Forget()
	check(not AN.Auctionable(st["Hearthstone"]), "@stored's Hearthstone (bound on pickup): not auctionable")
	C_Item.GetItemInfo = saveInfo
	PRICES[6948], VENDOR[6948] = nil, 0
	F.ClearCache(); AN.Forget()
	-- everywhere: your mail and the warband bank too; the warband's said without a name
	local rows = ns.AuctionatorQ.Answer(ns.AuctionatorQ.Question("what should i auction everywhere"))
	local linen
	for _, e in ipairs(rows) do if e.name == "Linen Cloth" then linen = e end end
	-- (bags 20 from @item, bank 12, mail 3, warband 4, alt 5)
	check(linen and linen._ahvalue == 50 * (20 + 12 + 3 + 4 + 5), "everywhere: bags, bank, mail, warband, alts: " .. tostring(linen and linen._ahvalue))
	rows = ns.AuctionatorQ.Answer(ns.AuctionatorQ.Question("what should i auction in my bank"))
	linen = nil
	for _, e in ipairs(rows) do if e.name == "Linen Cloth" then linen = e end end
	check(linen and linen.detail:find(L["warband bank"] .. " 4", 1, true) and not linen.detail:find("Warband " .. L["warband bank"], 1, true),
		"your bank and the warband's (said once): " .. tostring(linen and linen.detail))
	for line, want in pairs({ ["what should i auction"] = "@item is:auctionable sort:ahvalue ", ["what should i auction in my bank"] = "@bank is:auctionable sort:ahvalue ",
		["what should i auction from my bags and bank"] = "@item @bank is:auctionable sort:ahvalue ",
		["what should i auction everywhere"] = "@item @stored is:auctionable sort:ahvalue " }) do
		check(ns.QuestionToAdvanced(line) == want, ("%q as Advanced: %s"):format(line, tostring(ns.QuestionToAdvanced(line))))
	end
	ns.providers.stored = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "stored" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	-- an answer after a search sorted by AH value: its rows keep their own detail; -is:auctionable shows none
	ns.db.easyMode = false; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open(""); UI:SetQuery("@item sort:ahvalue ", 19); FlushAll()
	check(UI.showField == "ahvalue", "(sorted by AH value)")
	UI:SetQuery("what should i auction", 21); FlushAll()
	check(UI.showField == nil, "then a question: its own details")
	UI:SetQuery("@item -is:auctionable ", 22); FlushAll()
	check(UI.showField == nil, "-is:auctionable: no AH details")
	UI:Hide(); FlushAll()
end

-- "what should i do": worth posting, once it comes to a gold
local SG = ns.Suggest
local function Has(id)
	for _, r in ipairs(SG.Rows(true, 20)) do if r.suggestId == id then return r end end
end
SG.Forget()
check(not Has("auction"), "22s to post: not worth saying")
PRICES[2589], PRICES[2592] = 900, 1200
AN.Forget(); SG.Forget()
local r = Has("auction")
check(r and r.searchText == "what should i auction" and r.detail:find(AN.About(900 * 20 + 1200 * 10), 1, true), "30g to post: said, with about how much: " .. tostring(r and r.detail))
-- and the empty prompt's example (the bags as last read: no list made)
ns.db.easyMode = true; UI:EasyChanged()
local found
for _, x in ipairs(ns.Easy.PersonalTagged(false)) do if x[1]:find("^what should i auction") then found = x[1] end end
check(found and found:find(AN.About(30000), 1, true), "try: what should i auction (about 30g): " .. tostring(found))
local mats
for _, x in ipairs(ns.Easy.PersonalTagged(false)) do if x[1]:find("^ah value of my mats") then mats = x[1] end end
check(mats ~= nil, "try: ah value of my mats (about ...): " .. tostring(mats))
PRICES[2589], PRICES[2592] = 50, 120
AN.Forget(); SG.Forget()

-- @auction: the auction house's price now, and undercut
do
	local MA = ns.Mail
	local saveStore, saveMine = MA.Store, ns.PlayerGUID
	local posted = { ["Player-1"] = {
		[1] = { name = "Wool Cloth", link = Link(2592), count = 10, price = 2000, each = 200, ends = ns.Now() + 3600, t = ns.Now() },
		[2] = { name = "Linen Cloth", link = Link(2589), count = 20, price = 800, each = 40, ends = ns.Now() + 3600, t = ns.Now() },
		-- (review) a commodity read off your Auctions tab: its item id, no link
		[3] = { name = "Silk Cloth", id = 4306, count = 10, price = 5000, ends = ns.Now() + 3600, t = ns.Now(), seen = "listed" },
	} }
	MA.Store = function(k) if k == "auctionsPosted" then return posted end return saveStore(k) end
	ns.PlayerGUID = function() return "Player-1" end
	ns.providers.auctions = save.providers.auctions
	ns.providerOrder[#ns.providerOrder + 1] = "auctions"
	ns:AliasesChanged()
	ns.providers.auctions._dirty = true
	local all = ns:GetEntries(ns.providers.auctions)
	local wool, linen
	for _, e in ipairs(all) do if e.name:find("Wool") then wool = e elseif e.name:find("Linen") then linen = e end end
	check(wool and wool.undercut and wool.market == 120 and wool.detail:find(L["undercut: AH %s"]:format(ns.Money(120, true)), 1, true),
		"200 each, the AH at 120: undercut: " .. tostring(wool and wool.detail))
	check(linen and not linen.undercut and linen.market == 50, "40 each, the AH at 50: not undercut")
	local silk
	for _, e in ipairs(all) do if e.name:find("Silk") then silk = e end end
	check(silk and silk.market == 300 and silk.undercut, "a commodity with no link: its id's price (500 each, the AH at 300: undercut)")
	ns.db.easyMode = false; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	check(Names(UI:Search("@auction is:undercut")) == "Silk Cloth x10 | Wool Cloth x10" or Names(UI:Search("@auction is:undercut")) == "Wool Cloth x10 | Silk Cloth x10",
		"@auction is:undercut: " .. Names(UI:Search("@auction is:undercut")))
	local AU = ns.Auctions
	check(AU.Question("am i undercut") and AU.Question("undercut auctions") and AU.Question("my undercut auctions"), "\"am i undercut\"")
	check(ns.QuestionToAdvanced("am i undercut") == "@auction is:undercut ", "as Advanced: " .. tostring(ns.QuestionToAdvanced("am i undercut")))
	local rows = AU.Answer(AU.Question("am i undercut"))
	check(#rows == 2, "its answer: the two undercut")
	-- (review) your own cheaper auction is the AH's price: the dearer one isn't undercut by you
	posted["Player-1"][4] = { name = "Wool Cloth", link = Link(2592), count = 5, price = 600, each = 120, ends = ns.Now() + 3600, t = ns.Now() }
	ns.providers.auctions._dirty = true
	all = ns:GetEntries(ns.providers.auctions)
	local dear
	for _, e in ipairs(all) do if e.name == "Wool Cloth x10" then dear = e end end
	check(dear and not dear.undercut, "the AH's 120 is your own other auction: not undercut")
	posted["Player-1"][4] = nil
	ns.providers.auctions._dirty = true
	all = ns:GetEntries(ns.providers.auctions)
	-- its data changed: @auction worked out again
	ns.providers.auctions._dirty = nil
	PRICES[2592] = 250
	dbUpdate()
	check(ns.providers.auctions._dirty == true, "Auctionator's data changed: @auction made again")
	all = ns:GetEntries(ns.providers.auctions)
	for _, e in ipairs(all) do if e.name:find("Wool") then wool = e end end
	check(not wool.undercut, "the AH up to 250: not undercut any more")
	PRICES[2592] = 120
	MA.Store, ns.PlayerGUID = saveStore, saveMine
	ns.providers.auctions._dirty = true
end

ns.providers, ns.providerOrder = save.providers, save.order
ns:AliasesChanged()
_G.Auctionator, _G.C_AddOns, C_Item.GetItemInfo = save.ac, save.addons, save.item
AN.Forget(); F.ClearCache(); SG.Forget()
ns.db.easyMode = save.easy; UI:EasyChanged()
UI.lastScan, UI.lastExtra = nil, nil
check(not AN.On(), "(gone again)")

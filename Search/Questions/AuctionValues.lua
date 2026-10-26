local ns = select(2, ...)
local L = ns.L

-- Auctionator (0.62.0, the player's ask: "support for Auctionator if detected ... into the existing @auction kinds, as
-- well as taking auction house values into items ... a suggestion to go place items on the AH and expected values").
--
-- Read through its public API only (Auctionator.API.v1, for other addons), at run time, while it's installed: the
-- price its last scan of the auction house saw, and when it changes. Nothing of Auctionator's is copied into Terminal
-- (its licence: all rights reserved), and its files aren't read.
--
--   AH price, AH value   an item's auction house price each (ahprice), and times how many you have (ahvalue): Pipes'
--                        fields ("| sum ahvalue", "| avg ahprice"), sort:ahvalue (the bar's Sort: AH value)
--   is:auctionable       your bag items worth posting: not bound, not a quest's, the auction house paying more than a
--                        vendor would
--   @auction             each auction up now says the auction house's price now, and is:undercut when it's below yours
--   questions            "what should i auction" (is:auctionable sort:ahvalue, with what each would bring), "ah value
--                        of my mats" (@mats | sum ahvalue); "what should i do" says when your bags are worth posting

local AN = {}
ns.Auctionator = AN
AN.ADDON, AN.CALLER = "Auctionator", "Terminal"
AN.WORTH_POSTING = 10000 -- (copper: what your auctionable items must come to for "what should i do" to say so: 1g)

local Num = ns.Num
local SEP = ns.DETAIL_SEP
local Money = ns.Money

--- Is Auctionator loaded?
function AN.Loaded()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not isLoaded then return false end
	local ok, yes = pcall(isLoaded, AN.ADDON)
	return ok and yes == true
end

--- Its API for other addons (Auctionator.API.v1), or nil (not loaded, or not the API expected).
function AN.Api()
	local a = rawget(_G, "Auctionator")
	local api = type(a) == "table" and type(a.API) == "table" and a.API.v1
	if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
	return api
end

function AN.On() return AN.Api() ~= nil end

----------------------------------------------------------------------
-- Prices: asked once per item until Auctionator's data changes (RegisterForDBUpdate)
----------------------------------------------------------------------

local prices, ages, askedAt = {}, {}, nil
AN.KEEP = 300 -- (seconds a price is kept without word from Auctionator: a build without RegisterForDBUpdate still catches up)
function AN.Forget() prices, ages, askedAt = {}, {}, nil end
local function Fresh()
	local now = (type(GetTime) == "function" and GetTime()) or 0
	if askedAt and now - askedAt > AN.KEEP then prices, ages = {}, {} ; askedAt = nil end
	askedAt = askedAt or now
end

local function ItemLink(link) return type(link) == "string" and link:find("|Hitem:", 1, true) and link or nil end

local function Ask(fnLink, fnID, id, link)
	local api = AN.Api()
	if not api then return nil end
	local got
	link = ItemLink(link)
	if link and type(api[fnLink]) == "function" then
		local ok, v = pcall(api[fnLink], AN.CALLER, link)
		if ok then got = Num(v) end
	end
	-- (a copy with a random suffix, "of the Bear", Auctionator hasn't seen: not the plain item's price, another copy's)
	local suffixed = link and link:match("|Hitem:%-?%d+:[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*:(%-?%d+)")
	if suffixed == "0" or suffixed == "" then suffixed = nil end
	if got == nil and not suffixed and type(id) == "number" and type(api[fnID]) == "function" then
		local ok, v = pcall(api[fnID], AN.CALLER, id)
		if ok then got = Num(v) end
	end
	return got
end

--- The auction house's price for one (copper), as Auctionator last saw it, or nil (never seen, or no Auctionator).
function AN.Price(id, link)
	local key = ItemLink(link) or id
	if key == nil then return nil end
	Fresh()
	local got = prices[key]
	if got == nil then
		got = Ask("GetAuctionPriceByItemLink", "GetAuctionPriceByItemID", id, link)
		if got and got <= 0 then got = nil end
		prices[key] = got or false
	end
	return got or nil
end

--- How many days ago Auctionator saw it on the auction house (0: today), or nil.
function AN.Age(id, link)
	local key = ItemLink(link) or id
	if key == nil then return nil end
	local got = ages[key]
	if got == nil then
		got = Ask("GetAuctionAgeByItemLink", "GetAuctionAgeByItemID", id, link)
		ages[key] = got or false
	end
	return got or nil
end

local function ItemID(e)
	local F = ns.Filters
	local id = F and F.ItemOf and F.ItemOf(e)
	return type(id) == "number" and id or nil
end
local function RowLink(e) return ItemLink(rawget(e, "link")) end

--- A row's AH price each, and its AH value (times how many), or nil.
function AN.PriceOf(e)
	if type(e) ~= "table" or not AN.On() then return nil end
	local id = ItemID(e)
	if not id then return nil end
	return AN.Price(id, RowLink(e))
end
local OWN_KINDS = { items = true, gear = true, consumables = true, mats = true }
local function CountOf(e)
	local A = ns.Aggregate
	local f = A and A.FIELDS and A.FIELDS.count
	return f and f.num(e) or Num(e.count) or 1
end
-- (@stored's and @bank's places whose items you could post: not worn, not up already, not the guild's)
AN.SELLABLE = { bags = true, bank = true, mail = true, void = true, warband = true }
local HELD = { stored = true, bank = true }

--- How many of a row you could post: your bag stacks (none bound); @stored's and @bank's in places you could sell from
--- (`want`: which holders count, else every one of those places).
function AN.SellableCount(e, want)
	if HELD[e.kind] and type(e.holders) == "table" then
		local n = 0
		for _, h in pairs(e.holders) do
			if AN.SELLABLE[h.where] and (not want or want(h)) then n = n + (h.count or 0) end
		end
		return n
	end
	if OWN_KINDS[e.kind] and (rawget(e, "slotId") or e.bound) then return 0 end
	return CountOf(e)
end

function AN.ValueOf(e)
	-- (yours: only what could be sold, in your bags and not bound, or held where it could be; worn or bound gear, what's
	-- up already, a guild's bank bring nothing)
	local p = AN.PriceOf(e)
	if not p then return nil end
	local n = AN.SellableCount(e)
	return n > 0 and p * n or nil
end
--- What a vendor pays for one (copper), or nil.
function AN.VendorOf(e)
	local A = ns.Aggregate
	local f = A and A.FIELDS and A.FIELDS.price
	return f and f.num(e) or nil
end


--- Bound however it's held (picked up, a quest's, the account's): never posted. A row of @stored or @bank says nothing
--- of its stacks' binding, the item's own type does (one equipped and banked, bound since, isn't known).
local BOUND = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }
function AN.BindsOnPickup(e)
	local F = ns.Filters
	local info = F and F._ and F._.ItemInfo and F._.ItemInfo(ItemID(e))
	return info ~= nil and BOUND[info.bindType] == true
end

--- Worth posting: in your bags (not bound, not a quest's) or held in your bank, on your alts (@bank, @stored), the
--- auction house paying more than a vendor.
function AN.Auctionable(e)
	if type(e) ~= "table" then return false end
	if HELD[e.kind] then
		if AN.SellableCount(e) <= 0 or AN.BindsOnPickup(e) then return false end
	elseif not OWN_KINDS[e.kind] or not rawget(e, "locs") or rawget(e, "slotId") or e.questItem or e.bound then
		return false -- (any stack bound: its count would take them in)
	end
	local p = AN.PriceOf(e)
	if not p then return false end
	return p > (AN.VendorOf(e) or 0)
end

--- A row's detail when the search is sorted by its AH value (or price), or is:auctionable: "AH 3s 77c each · x185:
--- 6g 97s · Bag 4" (what it brings, then where it is, from its own detail); nil without a price.
function AN.DetailFor(e, field)
	if type(e) ~= "table" or not AN.On() then return nil end
	local each = AN.PriceOf(e)
	if not each then return nil end
	local n = AN.SellableCount(e)
	local parts = { L["AH %s each"]:format(Money(each)) }
	if n > 1 then parts[#parts + 1] = L["x%d: %s"]:format(n, Money(each * n)) end
	local d = type(e.detail) == "string" and e.detail or ""
	-- (its own detail without the count it starts with: "x185  Bag 4" -> "Bag 4", "x112  ·  bank" -> "bank"; none to
	-- post, bound: its count kept)
	if n > 0 then d = d:gsub("^x%d+", ""):gsub("^%s*·%s*", ""):gsub("^%s+", "") end
	if d ~= "" then parts[#parts + 1] = d end
	return table.concat(parts, SEP)
end

-- (the rows' detail when sorted by AH value or price: List.lua's FillRow)
ns.FIELD_DETAIL = ns.FIELD_DETAIL or {}
ns.FIELD_DETAIL.ahvalue = function(e, field) return AN.DetailFor(e, field) end
ns.FIELD_DETAIL.ahprice = ns.FIELD_DETAIL.ahvalue

--- About how much, plain: to the gold above a gold, to the silver above a silver ("about 45g").
function AN.About(copper)
	copper = Num(copper) or 0
	if copper >= 10000 then copper = math.floor(copper / 10000 + 0.5) * 10000
	elseif copper >= 100 then copper = math.floor(copper / 100 + 0.5) * 100 end
	return Money(copper, true)
end

--- Your auctionable bag items: the rows, and what they'd bring together. `build`: read the bags (asked); else only the
--- list as last read (the empty prompt's example, "what should i do"'s check: no list is made for them).
function AN.ToPost(build)
	local p = ns.providers.items
	if not (p and AN.On()) then return {}, 0, false end
	local list
	if build then list = ns:GetEntries(p) or {}
	else
		list = rawget(p, "_entries")
		if type(list) ~= "table" or rawget(p, "_dirty") then return {}, 0, false end
	end
	local rows, total, priced = {}, 0, false
	for _, e in ipairs(list) do
		if not priced and AN.PriceOf(e) then priced = true end
		if AN.Auctionable(e) then
			rows[#rows + 1] = e
			total = total + (AN.ValueOf(e) or 0)
		end
	end
	return rows, total, priced
end

----------------------------------------------------------------------
-- Fields, sorts and filters: "| sum ahvalue", sort:ahvalue, is:auctionable, is:undercut
----------------------------------------------------------------------

do
	local A = ns.Aggregate
	if A and A.FIELDS then
		A.FIELDS.ahprice = { label = L["AH price"], money = true, num = function(e) return AN.PriceOf(e) end }
		A.FIELDS.ahvalue = { label = L["AH value"], money = true, num = function(e) return AN.ValueOf(e) end }
		A.ALIASES.ah, A.ALIASES.auction, A.ALIASES.market = "ahvalue", "ahvalue", "ahprice"
		table.insert(A.ORDER, 3, "ahvalue")
		table.insert(A.ORDER, 4, "ahprice")
	end
	local F = ns.Filters
	if F then
		F.SORTS.ahvalue, F.SORTS.ah, F.SORTS.ahprice, F.SORTS.market = "ahvalue", "ahvalue", "ahprice", "ahprice"
		local V = F.VALUES
		V.sort[#V.sort + 1] = "ahvalue"
		V.sort[#V.sort + 1] = "ahprice"
		V.is[#V.is + 1] = "auctionable"
		V.is[#V.is + 1] = "undercut"
		local IS = F._ and F._.IS
		if IS then
			IS.auctionable = AN.Auctionable
			IS.undercut = function(e) return e.kind == "auctions" and rawget(e, "undercut") == true end
		end
		local AP = F.APPLIES and F.APPLIES.is
		if AP then
			AP.auctionable = { "items", "gear", "consumables", "mats", "bank", "stored" }
			AP.undercut = { "auctions" }
		end
		local AS = F.APPLIES and F.APPLIES.sort
		if AS then AS.ahvalue, AS.ahprice = AS.value, AS.value end -- (what has an item: yours, loot, recipes' crafts)
		for i, h in ipairs(F.HELP or {}) do
			if h[1] == "sort:name" then
				table.insert(F.HELP, i + 1, { "is:auctionable", L["Auctionator: bag items worth more on the auction house than at a vendor; sort:ahvalue, | sum ahvalue; @auction is:undercut"] })
				break
			end
		end
	end
	local B = ns.Bar
	if B and B.SORTS then
		-- (after Value: the bar offers it only when the rows have a price)
		local at = #B.SORTS + 1
		for i, o in ipairs(B.SORTS) do if o.id == "value" then at = i + 1 end end
		table.insert(B.SORTS, at, { id = "ahvalue", label = L["AH value"], field = "ahvalue" })
		table.insert(B.SORTS, at + 1, { id = "ahprice", label = L["AH price"], field = "ahprice" })
	end
end

----------------------------------------------------------------------
-- The questions: "what should i auction" (your auctionable items, what each would bring); "ah value of my mats"
-- (summed up: Suggest.lua's ns.PerField runs it as "@mats | sum ahvalue")
----------------------------------------------------------------------

local Q = {}
AN.Q = Q
ns.AuctionatorQ = Q -- (Search.lua's Scan.ANSWERS: Asks("AuctionatorQ"))
local POST = {}
for _, s in ipairs({ "what should i auction", "what should i sell on the ah", "what should i sell on the auction house",
	"what can i auction", "what can i sell on the ah", "what can i sell on the auction house", "what to auction",
	"what to sell on the ah", "what to sell on the auction house", "what should i post", "what can i post", "what to post",
	"items to auction", "things to auction", "stuff to auction", "auctionable items", "auctionable", "items worth auctioning",
	"what should i put on the ah", "what can i put on the ah", "what is worth auctioning", "whats worth auctioning",
	"what sells on the ah", "sell on the ah", "post on the ah" }) do POST[s] = true end

-- (0.62.1, the player: "by default we can assume bags / @items but it is worth it to allow inclusion of bank or alts")
-- where to look, said after the question: "... in my bank", "... on my alts", "... everywhere", "... bags and bank"
local SCOPE_FILL = { ["in"] = true, on = true, from = true, my = true, the = true, ["and"] = true, plus = true, with = true,
	including = true, include = true, also = true, too = true, all = true, characters = true, character = true, of = true }
local SCOPE_PLACE = { bags = "bags", bag = "bags", bank = "bank", banks = "bank", alts = "alts", alt = "alts",
	everywhere = "all", anywhere = "all", everything = "all" }

--- The places said after it ({ bags, bank, alts }), or nil when those words aren't only places.
local function Scope(words, from)
	local set, any = {}, false
	for k = from, #words do
		local w = words[k]
		local place = SCOPE_PLACE[w]
		if place == "all" then set.bags, set.bank, set.alts, set.all, any = true, true, true, true, true
		elseif place then set[place], any = true, true
		elseif not SCOPE_FILL[w] then return nil end
	end
	-- ("all my characters": everywhere)
	if not any and #words >= from then
		for k = from, #words do if words[k] == "characters" then set.bags, set.bank, set.alts, set.all = true, true, true, true return set end end
		return nil
	end
	return any and set or nil
end

function Q.Question(text)
	if not AN.On() then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(" please$", "")
	if POST[t] then return { places = { bags = true } } end
	-- the question, then where: "what should i auction in my bank"
	local words = {}
	for w in t:gmatch("%S+") do words[#words + 1] = w end
	for k = #words - 1, 1, -1 do
		local head = table.concat(words, " ", 1, k)
		if POST[head] then
			local places = Scope(words, k + 1)
			if places then return { places = places } end
			return nil
		end
	end
	return nil
end

local WHERE = { bags = L["bags"], bank = L["bank"], mail = L["mail"], void = L["void storage"], warband = L["warband bank"] }

--- Where a row's items to post are ("bank 5", "Alt 10, bank 2"): @stored's and @bank's holders that count.
local function Where(e, want)
	if type(e.holders) ~= "table" then return nil end
	local parts = {}
	for _, h in pairs(e.holders) do
		if AN.SELLABLE[h.where] and (h.count or 0) > 0 and (not want or want(h)) then
			local place = WHERE[h.where] or h.where
			parts[#parts + 1] = ((h.mine or h.where == "warband") and place or (tostring(h.who) .. " " .. place)) .. " " .. h.count
		end
	end
	table.sort(parts)
	if #parts > 3 then return L["%d places"]:format(#parts) end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

--- What to post from these places: { row, count, where } each (bags: your items; bank: @bank's; alts: your other
--- characters' bags, banks and mail from @stored), one per item.
function AN.ToPostIn(places)
	local out, byID = {}, {}
	local function Add(e, n, where)
		local id = ItemID(e)
		if not id or n <= 0 then return end
		local got = byID[id]
		if got then
			got.n = got.n + n
			got.where = got.where and where and (got.where .. ", " .. where) or got.where or where
		else
			got = { e = e, n = n, where = where }
			byID[id] = got
			out[#out + 1] = got
		end
	end
	if places.bags then
		for _, e in ipairs(AN.ToPost(true)) do Add(e, CountOf(e), (places.bank or places.alts) and L["bags"] or nil) end
	end
	local function want(h)
		-- (yours: your bank; everywhere, your mail and void storage too, the warband bank; your bags are the items')
		if h.mine then return (places.bank and h.where == "bank") or (places.all and h.where ~= "bags") or false end
		if h.where == "warband" then return places.all == true end -- (the account's: everywhere, not your bank, as @bank)
		return places.alts == true
	end
	if places.bank or places.alts then
		local p = ns.providers.stored
		for _, e in ipairs(p and ns:GetEntries(p) or {}) do
			local n = AN.SellableCount(e, want)
			if n > 0 and AN.Auctionable(e) then Add(e, n, Where(e, want)) end
		end
	end
	return out
end

function Q.Answer(q)
	local places = (q and q.places) or { bags = true }
	local found = AN.ToPostIn(places)
	local note = L["Worth posting"]
	if #found == 0 then
		local _, _, priced = AN.ToPost(true)
		return { ns.NoteRow(priced and L["Nothing there sells for more on the auction house than at a vendor"]
			or L["Auctionator has no prices for your items yet: scan the auction house with it"]) }, note
	end
	local out, total = {}, 0
	for _, x in ipairs(found) do
		local e, n = x.e, x.n
		-- (a copy: the item's own row keeps its detail)
		local c = {}
		for k, v in pairs(e) do c[k] = v end
		local each, vendor = AN.PriceOf(e), AN.VendorOf(e)
		local parts = { L["AH %s each"]:format(Money(each)) }
		if n > 1 then parts[#parts + 1] = L["x%d: %s"]:format(n, Money(each * n)) end
		if vendor and vendor > 0 then parts[#parts + 1] = L["vendor %s"]:format(Money(vendor * n)) end
		if x.where then parts[#parts + 1] = x.where end
		local age = AN.Age(ItemID(e), RowLink(e))
		if age and age > 1 then parts[#parts + 1] = L["seen %d days ago"]:format(age) end
		c.detail = table.concat(parts, SEP)
		c._ahvalue = each * n
		total = total + each * n
		out[#out + 1] = c
	end
	table.sort(out, function(a, b)
		if a._ahvalue ~= b._ahvalue then return a._ahvalue > b._ahvalue end
		return tostring(a.name) < tostring(b.name)
	end)
	ns.ScoreInOrder(out)
	return out, note .. SEP .. L["about %s on the auction house"]:format(AN.About(total)) .. SEP .. L["before its cut"]
end

--- As Advanced syntax: your bags' @item, your bank's @bank, else @stored (your alts and banks).
function Q.ToAdvanced(q)
	local pl = (q and q.places) or { bags = true }
	-- (your alts', everywhere: the answer counts only those holders, @stored every one of each item, yours too; no Advanced
	-- line finds the same: kept as said. 0.63.7, review)
	if pl.alts or pl.all then return nil end
	-- (your bags are @item, your bank @bank, your alts' @stored; together, each list named)
	local kinds = {}
	if pl.bags then kinds[#kinds + 1] = "@item" end
	if pl.alts then kinds[#kinds + 1] = "@stored"
	elseif pl.bank then kinds[#kinds + 1] = "@bank" end
	if #kinds == 0 then kinds[1] = "@item" end
	return table.concat(kinds, " ") .. " is:auctionable sort:ahvalue "
end

-- "ah value of my mats", "what are my mats worth", "my bags ah value": a list summed up by its AH value
local LISTS = { mats = "@mats", materials = "@mats", mat = "@mats", reagents = "@mats", bags = "@item in:bags",
	bag = "@item in:bags", items = "@item in:bags", inventory = "@item in:bags", consumables = "@consumables",
	potions = "@consumables", food = "@consumables", gear = "@gear", bank = "@bank", alts = "@stored", alt = "@stored",
	stored = "@stored" }
local VALUE_FILL = { the = true, my = true, of = true, what = true, whats = true, are = true, is = true, how = true, much = true,
	["in"] = true, on = true, at = true, total = true, all = true, worth = true, value = true, ah = true, auction = true,
	house = true, price = true, prices = true, sum = true, me = true, i = true, ["do"] = true, have = true }

-- (Search.lua's Scan.ANSWERS: Asks("AhValueQ"), for Alt+`; the search runs its line, UI/Results.lua's TakeAggregate)
ns.AhValueQ = { Question = function(text) return AN.ValueQuestion(text) end, Answer = function() return nil end,
	ToAdvanced = function(q) return q.line end }

--- { line = "@mats | sum ahvalue " } or nil: a list (mats, bags, consumables, gear) and the auction house's worth of it.
function AN.ValueQuestion(text)
	if not AN.On() then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local list, ah, worth
	for w in t:gmatch("%S+") do
		if LISTS[w] then
			if list and list ~= LISTS[w] then return nil end
			list = LISTS[w]
		elseif w == "ah" or w == "auction" then ah = true
		elseif w == "worth" or w == "value" then worth = true
		elseif not VALUE_FILL[w] then return nil end
	end
	-- ("ah value of my mats", "mats ah value", "what are my mats worth on the ah"; "what are my mats worth" too: the
	-- auction house's, with Auctionator)
	if not (list and worth) then return nil end
	if not ah and not t:find("worth", 1, true) then return nil end
	return { line = list .. " | sum ahvalue " }
end

----------------------------------------------------------------------
-- The cheapest upgrades on the auction house (0.66.13, the player): "ah upgrades", "cheapest upgrades on the ah",
-- "upgrades on the auction house": bind-on-equip items from AtlasLoot that are clear upgrades for you, at Auctionator's
-- last-scanned price, the most gain per gold first ("+12 for 3g 40s"). Only what showed in its last scan; each row says
-- when it was seen when that's days ago.
----------------------------------------------------------------------
local AHU = {}
AN.Upgrades = AHU
ns.AhUpgradesQ = AHU -- (Search.lua's Scan.ANSWERS: Asks("AhUpgradesQ"))
local AH_WORDS = { ah = true, auction = true, auctions = true, house = true, auctionhouse = true }
local UPG_WORDS = { upgrade = true, upgrades = true }
local AHU_FILL = { cheapest = true, cheap = true, best = true, value = true, gold = true, per = true, ["for"] = true, on = true,
	the = true, at = true, ["in"] = true, i = true, can = true, buy = true, my = true, me = true, what = true, whats = true,
	are = true, show = true, list = true, find = true, any = true, some = true, from = true, to = true, of = true, a = true,
	affordable = true, good = true }
AHU.ASK = 40 -- (items asked of the server per answer)
AHU.MAX = 50 -- (rows listed at most)
AHU.SELLABLE_BIND = { [0] = true, [2] = true, [3] = true } -- (none, on equip, on use)

--- "ah upgrades", "cheapest upgrades on the ah": true (with Auctionator).
function AHU.Question(text)
	if not AN.On() then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	local ah, upg = false, false
	for w in t:gmatch("%S+") do
		if AH_WORDS[w] then ah = true
		elseif UPG_WORDS[w] then upg = true
		elseif not AHU_FILL[w] then return nil end
	end
	return (ah and upg) or nil
end

local equipKept -- { rows = AtlasLoot's rows, list = their equipment, one row per item }
--- The upgrades the auction house has (AtlasLoot's bind-on-equip items Auctionator saw), the most gain per gold first.
function AHU.Answer()
	local note = L["Upgrades on the auction house, the most gain per gold first"]
	local F = ns.Filters
	local loot = ns.providers.loot
	if not (F and F.GearFit) then return { ns.NoteRow(L["No upgrades to judge"]) }, note end
	if not loot then return { ns.NoteRow(L["Needs AtlasLoot: it knows which items there are"]) }, note end
	local fit = F.GearFit()
	local info = F._ and F._.ItemInfo
	local cached = C_Item and C_Item.IsItemDataCachedByID
	local seen, found, asked, priced = {}, {}, 0, false
	local inst = C_Item and C_Item.GetItemInfoInstant
	local SLOTS = F.SLOTS or {}
	-- (run in the search's own coroutine: tens of thousands of AtlasLoot rows go over several frames; review)
	local UI, n = ns.UI, 0
	local slicing = UI and UI.sliceUntil and coroutine.running() and debugprofilestop
	-- (AtlasLoot's equipment, one row per item: worked out once for its rows, not again on each of the searches made
	-- again as items arrive from the server; review)
	local rows = ns:GetEntries(loot) or {}
	local equip = equipKept and equipKept.rows == rows and equipKept.list
	local list = equip or {}
	for _, e in ipairs(equip and {} or rows) do
		n = n + 1
		if slicing and n % 256 == 0 and UI.sliceUntil and debugprofilestop() > UI.sliceUntil then coroutine.yield(UI.Results()) end
		local id = ItemID(e)
		-- (equipment only, by the client's own data: no price asked for the rest)
		local okI, _, _, _, loc = false, nil, nil, nil, nil
		if id and inst then okI, _, _, _, loc = pcall(inst, id) end
		if id and inst and not (okI and type(loc) == "string" and SLOTS[loc]) then id = nil end
		if id and not seen[id] then seen[id] = true; list[#list + 1] = e end
	end
	if not equip then equipKept = { rows = rows, list = list } end
	for _, e in ipairs(list) do
		n = n + 1
		if slicing and n % 256 == 0 and UI.sliceUntil and debugprofilestop() > UI.sliceUntil then coroutine.yield(UI.Results()) end
		local id = ItemID(e)
		if id then
			local price = AN.Price(id)
			if price then
				priced = true
				if cached and ns.Safe(cached, id) == false and not (F.Known and F.Known(id)) then
					if asked < AHU.ASK then
						asked = asked + 1
						if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
					end
				else
					local it = info and info(id)
					-- (one bound when picked up never reaches the auction house: unbound, on equip or on use do)
					if it and AHU.SELLABLE_BIND[it.bindType or 0] then
						local probe = { kind = "ahitem", itemID = id, key = id, name = e.name, link = rawget(e, "link") }
						if fit(probe) then
							local g = F.GainOf(probe)
							if g and not g.byLevel then
								found[#found + 1] = { e = e, g = g, price = price, per = g.gain / math.max(price / 10000, 0.01) }
							end
						end
					end
				end
			end
		end
	end
	if asked > 0 then F.loading = true end
	table.sort(found, function(a, b)
		if a.per ~= b.per then return a.per > b.per end
		return tostring(a.e.name) < tostring(b.e.name)
	end)
	local out = {}
	for i, x in ipairs(found) do
		if i > AHU.MAX then break end
		-- (a view of the loot row: its Enter, link, icon and colour are its metatable's on AtlasLoot's compact rows; review)
		local c = setmetatable({}, { __index = x.e })
		local gain = math.floor(x.g.gain * 10 + 0.5) / 10
		local parts = { L["+%s for %s"]:format(gain, Money(x.price)) }
		local age = AN.Age(x.e.itemID or ItemID(x.e))
		if age and age > 1 then parts[#parts + 1] = L["seen %d days ago"]:format(age) end
		c.detail = table.concat(parts, SEP)
		F.SetGain(c, x.g)
		out[#out + 1] = c
	end
	ns.ScoreInOrder(out)
	if #out == 0 then
		local say = (asked > 0 and L["None yet: the items' details are still coming in"])
			or (not priced and L["Auctionator has no prices yet: scan the auction house with it"])
			or L["Nothing on the auction house is an upgrade for you"]
		return { ns.NoteRow(say) }, note
	end
	return out, note .. SEP .. L["at Auctionator's last-scanned prices"]
end
function AHU.ToAdvanced() return nil end -- (as said: gain per gold has no Advanced form)

----------------------------------------------------------------------
-- Starting: Auctionator's data changing forgets the prices asked (and @auction's undercuts are worked out again)
----------------------------------------------------------------------

function AN.Setup()
	local api = AN.Api()
	if not (api and type(api.RegisterForDBUpdate) == "function") then return end
	local ok, err = pcall(api.RegisterForDBUpdate, AN.CALLER, function()
		AN.Forget()
		ns:Changed("auctions") -- (its undercuts are worked out as it's made)
	end)
	if not ok then ns:Trace("auctionator: RegisterForDBUpdate: " .. tostring(err)) end
end

--- .integrations' line.
function AN.Status()
	if not AN.Loaded() then return L["not found"] end
	local ver = ns.Integrations and ns.Integrations._ and ns.Integrations._.AddOnVersion and ns.Integrations._.AddOnVersion(AN.ADDON)
	if not AN.On() then return L["found (%s), but not its API for other addons: update Auctionator"]:format(tostring(ver or "?")) end
	return L["found (%s). Auction house prices on items (sort:ahvalue, | sum ahvalue, is:auctionable) and @auction (is:undercut)"]:format(tostring(ver or "?"))
end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	-- (leaving the auction house: Auctionator may have scanned it; its prices asked again)
	f:RegisterEvent("AUCTION_HOUSE_CLOSED")
	f:SetScript("OnEvent", function(_, event)
		if event == "AUCTION_HOUSE_CLOSED" then
			if AN.On() then AN.Forget(); ns:Changed("auctions") end
			return
		end
		local ok, err = pcall(AN.Setup)
		if not ok then ns:Trace("auctionator: " .. tostring(err)) end
	end)
end

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

local Safe, Str, Num, Lower = ns.Safe, ns.Str, ns.Num, ns.Lower
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
	if got == nil and type(id) == "number" and type(api[fnID]) == "function" then
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
local function CountOf(e)
	local A = ns.Aggregate
	local f = A and A.FIELDS and A.FIELDS.count
	return f and f.num(e) or Num(e.count) or 1
end
function AN.ValueOf(e)
	local p = AN.PriceOf(e)
	return p and p * CountOf(e) or nil
end
--- What a vendor pays for one (copper), or nil.
function AN.VendorOf(e)
	local A = ns.Aggregate
	local f = A and A.FIELDS and A.FIELDS.price
	return f and f.num(e) or nil
end

-- your own stacks in your bags (not worn: equipped gear isn't for sale)
local OWN = { items = true, gear = true, consumables = true, mats = true }

--- Worth posting: in your bags, not bound, not a quest's, the auction house paying more than a vendor.
function AN.Auctionable(e)
	if type(e) ~= "table" or not OWN[e.kind] or not rawget(e, "locs") or rawget(e, "slotId") then return false end
	if e.questItem or (e.bound and not e.unbound) then return false end
	local p = AN.PriceOf(e)
	if not p then return false end
	return p > (AN.VendorOf(e) or 0)
end

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
		V.is[#V.is + 1] = "auctionable"
		V.is[#V.is + 1] = "undercut"
		local IS = F._ and F._.IS
		if IS then
			IS.auctionable = AN.Auctionable
			IS.undercut = function(e) return e.kind == "auctions" and rawget(e, "undercut") == true end
		end
		local AP = F.APPLIES and F.APPLIES.is
		if AP then
			AP.auctionable = { "items", "gear", "consumables", "mats" }
			AP.undercut = { "auctions" }
		end
		local AS = F.APPLIES and F.APPLIES.sort
		if AS then AS.ahvalue = AS.value end -- (what has an item: yours, loot, recipes' crafts)
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

function Q.Question(text)
	if not AN.On() then return nil end
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(" please$", "")
	if POST[t] then return {} end
	return nil
end

function Q.Answer()
	local rows, total, priced = AN.ToPost(true)
	local note = L["Worth posting"]
	if #rows == 0 then
		return { ns.NoteRow(priced and L["Nothing in your bags sells for more on the auction house than at a vendor"]
			or L["Auctionator has no prices for your items yet: scan the auction house with it"]) }, note
	end
	local out = {}
	for _, e in ipairs(rows) do
		-- (a copy: the item's own row keeps its detail)
		local c = {}
		for k, v in pairs(e) do c[k] = v end
		local each, n, vendor = AN.PriceOf(e), CountOf(e), AN.VendorOf(e)
		local parts = { L["AH %s each"]:format(Money(each)) }
		if n > 1 then parts[#parts + 1] = L["x%d: %s"]:format(n, Money(each * n)) end
		if vendor and vendor > 0 then parts[#parts + 1] = L["vendor %s"]:format(Money(vendor * n)) end
		local age = AN.Age(ItemID(e), RowLink(e))
		if age and age > 1 then parts[#parts + 1] = L["seen %d days ago"]:format(age) end
		c.detail = table.concat(parts, SEP)
		c._ahvalue = each * n
		out[#out + 1] = c
	end
	table.sort(out, function(a, b)
		if a._ahvalue ~= b._ahvalue then return a._ahvalue > b._ahvalue end
		return tostring(a.name) < tostring(b.name)
	end)
	ns.ScoreInOrder(out)
	return out, note .. SEP .. L["about %s on the auction house"]:format(AN.About(total)) .. SEP .. L["before its cut"]
end

function Q.ToAdvanced() return "@item is:auctionable sort:ahvalue " end

-- "ah value of my mats", "what are my mats worth", "my bags ah value": a list summed up by its AH value
local LISTS = { mats = "@mats", materials = "@mats", mat = "@mats", reagents = "@mats", bags = "@item in:bags",
	bag = "@item in:bags", items = "@item in:bags", inventory = "@item in:bags", consumables = "@consumables",
	potions = "@consumables", food = "@consumables", gear = "@gear" }
local VALUE_FILL = { the = true, my = true, of = true, what = true, whats = true, are = true, is = true, how = true, much = true,
	["in"] = true, on = true, at = true, total = true, all = true, worth = true, value = true, ah = true, auction = true,
	house = true, price = true, prices = true, sum = true, me = true, i = true, ["do"] = true, have = true }

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

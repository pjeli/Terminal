-- (1.5.1, the player's ask) TradeSkillMaster's prices first, Auctionator's where it has none: TSM_API's
-- GetCustomPriceValue (AuctionDB's minimum buyout, else its market value) for each item, Auctionator.API.v1 for the rest.
-- Either one alone gives every auction house price feature; the texts name whose prices are shown.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L = ns.L
local AN, I = ns.Auctionator, ns.Integrations
local TSM = AN.TSM
io.write("[tsm: TradeSkillMaster's prices first, Auctionator's after]\n")
check(TSM and not TSM.On() and not AN.On(), "without either: off")
check(I.AddonMissing("TradeSkillMaster"), "the hint system knows prices are missing")
I.ForgetHint()
local hint = tostring(I.MissingHint("@item is:auctionable")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
check(hint:find("TradeSkillMaster or Auctionator", 1, true), "the hint names both, TSM first: " .. hint)

local save = { tsm = rawget(_G, "TSM_API"), ac = rawget(_G, "Auctionator"), addons = _G.C_AddOns, item = C_Item.GetItemInfo,
	store = ns.Mail.Store, mine = ns.PlayerGUID }
local function Link(id, suffix)
	return "|cffffffff|Hitem:" .. id .. "::::::" .. (suffix or "") .. "::|h[Item " .. id .. "]|h|r"
end

-- TSM_API as its file gives it: plain functions (a colon call is an error), a TSM item string ("i:2589") or an error
local MIN = { ["i:2589"] = 40, ["i:2592"] = 150 }
local MARKET = { ["i:2589"] = 55, ["i:4306"] = 310, ["i:2592"] = 160 }
local tsmAsked, tsmBroken = 0, false
local tsm = {
	ToItemString = function(item)
		assert(type(item) == "string", "item")
		local id, suffix = item:match("|Hitem:(%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*:(%-?%d*)")
		if not id then return nil end
		return (suffix and suffix ~= "" and suffix ~= "0") and ("i:" .. id .. "::" .. suffix) or ("i:" .. id)
	end,
	GetCustomPriceValue = function(source, item)
		if tsmBroken then error("TSM isn't ready") end
		assert(type(source) == "string", "customPriceStr")
		if type(item) ~= "string" or not item:match("^[ip]:%d+") then error("Invalid 'itemString' argument") end
		tsmAsked = tsmAsked + 1
		-- (as its AuctionDB does: a copy with a suffix it has nothing of its own for answers the plain item's)
		local base = item:match("^(i:%d+)")
		if source == "DBMinBuyout" then return MIN[item] or MIN[base] end
		if source == "DBMarket" then return MARKET[item] or MARKET[base] end
		return nil, "Invalid price source"
	end,
}
local loaded = { Auctionator = false }
_G.C_AddOns = setmetatable({ IsAddOnLoaded = function(n) if loaded[n] ~= nil then return loaded[n] end return save.addons.IsAddOnLoaded(n) end },
	{ __index = save.addons })

-- TSM alone
_G.TSM_API, loaded.TradeSkillMaster = tsm, true
AN.Forget(); I.ForgetHint()
check(TSM.On() and AN.On() and not AN.AtrOn(), "TSM alone: prices on")
check(not I.AddonMissing("TradeSkillMaster"), "not missing with TSM alone")
check(AN.Price(2589) == 40 and AN.SourceOf(2589) == "TSM", "its minimum buyout first")
check(AN.Price(4306) == 310, "no minimum buyout: its market value")
check(AN.Price(6948) == nil and AN.SourceOf(6948) == nil, "neither: no price")
tsmAsked = 0
AN.Price(2589); AN.Price(6948)
check(tsmAsked == 0, "asked once an item: " .. tsmAsked)
check(AN.Age(2589) == nil, "TSM says no age")
check(AN.Said() == "TSM", "whose prices: " .. AN.Said())
check(AN.NoPrices(true) == L["TSM has no prices for your items yet: they come from the TSM desktop app"], "no prices: where TSM's come from")
check(TSM.Status() == L["found (%s). Auction house prices on items (sort:ahvalue, | sum ahvalue, is:auctionable) and @auction (is:undercut), from its AuctionDB (the TSM desktop app's prices)"]
	:format(I._.AddOnVersion("TradeSkillMaster")), ".integrations: one text: " .. TSM.Status())
check(AN.Status() == L["not found"], "Auctionator's line: not found (hidden)")
-- a copy with a random suffix: its own item string, never the plain item's price
AN.Forget()
check(AN.Price(2589, Link(2589, "-55")) == nil, "a suffixed copy TSM hasn't seen: no price (not the plain item's, which TSM answers)")
MIN["i:2589::-56"] = 95
check(AN.Price(2589, Link(2589, "-56")) == 95 and AN.SourceOf(2589, Link(2589, "-56")) == "TSM", "one it has a price of its own for: that")
MIN["i:2589::-56"] = nil
-- (1.5.6, review) what's up now (@auction's undercut): its minimum buyout only, not its 14-day market value
check(AN.Price(4306, nil, true) == nil and AN.Price(4306) == 310 and AN.Price(2589, nil, true) == 40,
	"now: the minimum buyout only (4306 has a market value alone)")
-- (1.5.6, review) TSM reads its data in its own login, after Terminal's: the prices are asked again a little later
AN.Forget()
AN.frame:GetScript("OnEvent")(AN.frame, "PLAYER_LOGIN")
check(AN.Price(5000) == nil, "asked before TSM had it: no price")
MIN["i:5000"] = 70
check(AN.Price(5000) == nil, "(kept a while)")
FlushAll()
check(AN.Price(5000) == 70, "asked again once TSM is settled: " .. tostring(AN.Price(5000)))
MIN["i:5000"] = nil
-- (TSM erroring: not ready yet) no error out of Terminal, no price
AN.Forget(); tsmBroken = true
check(AN.Price(2589) == nil, "TSM erroring: no price, no error")
tsmBroken = false
-- an API missing its functions (an old or a different TSM_API): off, said so
_G.TSM_API = { GetCustomPriceValue = tsm.GetCustomPriceValue }
check(not TSM.On() and TSM.Status() == L["found (%s), but not its API for other addons: update %s"]:format(
	tostring(I._.AddOnVersion("TradeSkillMaster") or "?"), "TradeSkillMaster"), "no ToItemString: off, said so: " .. TSM.Status())
_G.TSM_API = tsm

-- both: TSM first, Auctionator for the rest
local APRICES = { [2589] = 50, [2592] = 120, [6948] = 75 }
local AGES = { [6948] = 3, [2589] = 1 }
_G.Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(_, id) return APRICES[id] end,
	GetAuctionPriceByItemLink = function(_, link) return APRICES[tonumber(link:match("|Hitem:(%d+)"))] end,
	GetAuctionAgeByItemID = function(_, id) return AGES[id] end,
	GetAuctionAgeByItemLink = function(_, link) return AGES[tonumber(link:match("|Hitem:(%d+)"))] end,
} } }
loaded.Auctionator = true
AN.Forget()
check(AN.Price(2589) == 40 and AN.SourceOf(2589) == "TSM", "both: TSM's price wins (40, not Auctionator's 50)")
check(AN.Age(2589) == nil, "TSM's price: no age said (Auctionator's age is of its own price)")
check(AN.Said() == "TSM", "only TSM's shown so far")
check(AN.Price(6948) == 75 and AN.SourceOf(6948) == "Auctionator", "one TSM has no price for: Auctionator's")
check(AN.Age(6948) == 3, "and its age, Auctionator's")
check(AN.Said() == L["%s and %s"]:format("TSM", "Auctionator"), "both shown: both named: " .. AN.Said())
check(AN.Said({ { 2589 } }) == "TSM" and AN.Said({ { 6948 } }) == "Auctionator", "(review) the rows shown: only their addons named")
check(AN.NoPrices(false) == L["TSM and Auctionator have no prices yet: scan the auction house with Auctionator"], "no prices: both named")
check(AN.Status() == L["found (%s). Auction house prices for the items TSM has none for"]:format(tostring(I._.AddOnVersion("Auctionator") or "?")),
	"Auctionator's line says it's the fallback: " .. AN.Status())
local lines = table.concat(ns:FindCommand("integrations").run("") or {}, " / ")
check(lines:find("TradeSkillMaster:", 1, true) and lines:find("Auctionator:", 1, true)
	and lines:find("TradeSkillMaster:", 1, true) < lines:find("Auctionator:", 1, true), ".integrations: TSM's line first: " .. lines)

-- @auction: the price now says whose it is
do
	local now = ns.Now()
	local posted = { ["Player-1"] = {
		[1] = { name = "Wool Cloth", link = Link(2592), count = 10, price = 2000, each = 200, ends = now + 3600, t = now },
		[2] = { name = "Rune Thread", link = Link(6948), count = 1, price = 50, each = 50, ends = now + 3600, t = now },
		[3] = { name = "Market Thing", link = Link(4306), count = 1, price = 400, each = 400, ends = now + 3600, t = now },
	} }
	ns.Mail.Store = function(k) if k == "auctionsPosted" then return posted end return save.store(k) end
	ns.PlayerGUID = function() return "Player-1" end
	ns.providers.auctions._dirty = true
	local wool, thread, thing
	for _, e in ipairs(ns:GetEntries(ns.providers.auctions)) do
		if e.name:find("Wool") then wool = e elseif e.name:find("Rune Thread") then thread = e elseif e.name:find("Market Thing") then thing = e end
	end
	check(thing and not thing.undercut and thing.market == nil, "(1.5.6, review) TSM's market value alone (310 under your 400): not an undercut")
	check(wool and wool.market == 150 and wool.undercut and wool.marketBy == "TSM", "TSM's 150 under your 200: undercut, by TSM's price")
	check(thread and thread.market == 75 and thread.marketBy == "Auctionator" and not thread.undercut,
		"one TSM hasn't priced: Auctionator's (75, not under your 50)")
	local said = {}
	local function Put(_, a, b) said[#said + 1] = tostring(a) .. (type(b) == "string" and (" " .. b) or "") end
	local tip = setmetatable({ SetText = Put, AddLine = Put, AddDoubleLine = Put }, { __index = function() return function() end end })
	if wool then wool.tooltip(wool, tip) end
	local text = table.concat(said, " / ")
	check(text:find(L["(each, from %s)"]:format("TSM"), 1, true), "the tooltip says whose: " .. text)
	ns.Mail.Store, ns.PlayerGUID = save.store, save.mine
	ns.providers.auctions._dirty = true
end

-- TSM gone: Auctionator's alone, as before
_G.TSM_API, loaded.TradeSkillMaster = nil, nil
AN.Forget()
check(AN.On() and AN.Price(2589) == 50 and AN.SourceOf(2589) == "Auctionator", "Auctionator alone: its price")
check(AN.Age(2589) == 1 and AN.Said() == "Auctionator", "its age, its name")

_G.TSM_API, _G.Auctionator, _G.C_AddOns, C_Item.GetItemInfo = save.tsm, save.ac, save.addons, save.item
AN.Forget(); I.ForgetHint()
check(not AN.On(), "(gone again)")

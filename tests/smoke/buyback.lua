-- Buyback (0.64.2, the player's ask: "keep a record of what you sold, so buyback can be searched anywhere without
-- opening a vendor"; the game's list is lost on logout, checked)
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local BB = ns.Buyback

io.write("[buyback: what you sold, anywhere]\n")
do
	local save = { n = _G.GetNumBuybackItems, info = _G.GetBuybackItemInfo, link = _G.GetBuybackItemLink, buy = _G.BuybackItem,
		money = _G.GetMoney, time = _G.time, print = ns.Print, easy = ns.db.easyMode, kept = ns.db.buyback }
	local clock = 1000000
	_G.time = function() return clock end
	local game = {} -- (the game's buyback list: oldest first)
	local function Sell(id, name, count, price)
		game[#game + 1] = { name = name, link = ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, name), count = count, price = price }
		if #game > 12 then table.remove(game, 1) end
	end
	_G.GetNumBuybackItems = function() return #game end
	_G.GetBuybackItemInfo = function(i) local g = game[i]; if g then return g.name, 133, g.price, g.count, 1, true end end
	_G.GetBuybackItemLink = function(i) return game[i] and game[i].link end
	local bought
	_G.BuybackItem = function(i) bought = game[i] and game[i].name; table.remove(game, i) end
	_G.GetMoney = function() return 10000 end
	local said = {}
	ns.Print = function(_, m) said[#said + 1] = m end
	ns.db.buyback = {}
	local function Names(rows) local t = {} for _, e in ipairs(rows) do t[#t + 1] = tostring(e.name) end return table.concat(t, " | ") end

	-- at a vendor: what you sell is kept, newest first, each with when it was sold and its price
	BB.OnEvent("MERCHANT_SHOW")
	Sell(2589, "Linen Cloth", 20, 200)
	BB.OnEvent("MERCHANT_UPDATE")
	clock = clock + 300
	Sell(4865, "Ruined Pelt", 1, 5)
	BB.OnEvent("MERCHANT_UPDATE")
	BB.OnEvent("MERCHANT_CLOSED")
	local rows = BB.Rows()
	check(Names(rows) == "Ruined Pelt | Linen Cloth", "kept, newest first: " .. Names(rows))
	check(rows[2].detail:find("x20", 1, true) and rows[2].detail:find(ns.L["%d min ago"]:format(5), 1, true), "how many, when sold: " .. rows[2].detail)

	-- away from the vendor: searchable, in plain words and @buyback; Enter says where to buy it back
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("what did i sell"); FlushAll()
	check(Names(UI.Results()) == "Ruined Pelt | Linen Cloth", "\"what did i sell\": " .. Names(UI.Results()))
	UI.sel = 2
	UI:Activate(); FlushAll()
	check(bought == nil and said[#said] and said[#said]:find("Open any vendor", 1, true), "away from a vendor: Enter says where: " .. tostring(said[#said]))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()
	UI.lastScan = nil
	check(Names(UI:Search("@buyback linen")) == "Linen Cloth", "@buyback linen")
	check(ns.QuestionToAdvanced("buyback") == "@buyback ", "Alt+`: @buyback")

	-- at a vendor again: Enter buys it back, and the list follows the game's
	BB.OnEvent("MERCHANT_SHOW")
	local linen
	for _, e in ipairs(BB.Rows()) do if e.name == "Linen Cloth" then linen = e end end
	linen.activate(linen)
	BB.OnEvent("MERCHANT_UPDATE")
	check(bought == "Linen Cloth" and Names(BB.Rows()) == "Ruined Pelt", "at a vendor: bought back, gone from the list: " .. Names(BB.Rows()))
	-- not enough money: said, nothing bought
	Sell(1, "Pricey Thing", 1, 99999)
	BB.OnEvent("MERCHANT_UPDATE")
	bought = nil
	local pricey = BB.Rows()[1]
	pricey.activate(pricey)
	check(bought == nil and said[#said]:find("Not enough money", 1, true), "too dear: said")
	BB.OnEvent("MERCHANT_CLOSED")

	-- a /reload keeps it; a fresh login drops it (the game's list is gone too)
	BB.OnEvent("PLAYER_ENTERING_WORLD", false)
	check(#BB.Rows() == 2, "a /reload: kept")
	BB.OnEvent("PLAYER_ENTERING_WORLD", true)
	check(#BB.Rows() == 0, "a fresh login: gone")
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("buyback"); FlushAll()
	check(UI.Results()[1] and UI.Results()[1].name == ns.L["Nothing sold since you logged in"], "nothing sold: said")
	UI:Hide(); FlushAll()

	_G.GetNumBuybackItems, _G.GetBuybackItemInfo, _G.GetBuybackItemLink, _G.BuybackItem = save.n, save.info, save.link, save.buy
	_G.GetMoney, _G.time, ns.Print = save.money, save.time, save.print
	ns.db.easyMode, ns.db.buyback = save.easy, save.kept
	UI:EasyChanged()
	ns.providers.buyback._dirty = true
	UI.lastScan = nil
end

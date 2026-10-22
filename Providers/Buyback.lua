local ns = select(2, ...)
local L = ns.L
local Safe, Num, Str = ns.Safe, ns.Num, ns.Str

-- What you sold to vendors, searchable anywhere (0.64.2, the player's ask, tabled since 0.52: "buyback ... without
-- opening a vendor"). The game's buyback list holds the last 12 items sold, and only until you log out; it can be read
-- only while a vendor's window is open. Terminal keeps a copy each time it's open (MERCHANT_SHOW, MERCHANT_UPDATE), so
-- @buyback, "buyback" and "what did i sell" list it anywhere; at a vendor Enter buys one back. The copy is saved, so a
-- /reload keeps it, and dropped on a fresh login, when the game's list is gone too.

local BB = {}
ns.Buyback = BB
BB.ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local atVendor = false
function BB.AtVendor() return atVendor end

--- The kept copy: { { link, name, icon, count, price, t } }, newest first ({} with no saved variables yet).
function BB.List()
	local db = ns.db
	if not db then return {} end
	if type(db.buyback) ~= "table" then db.buyback = {} end
	return db.buyback
end

--- The game's buyback list now (a vendor's window open): { { link, name, icon, count, price, index } }, in its order.
function BB.ReadGame()
	local out = {}
	local n = Num(_G.GetNumBuybackItems and Safe(_G.GetNumBuybackItems)) or 0
	for i = 1, n do
		local name, icon, price, count = Safe(_G.GetBuybackItemInfo, i)
		local link = _G.GetBuybackItemLink and Str(Safe(_G.GetBuybackItemLink, i))
		name = Str(name) or (link and ns.LinkName(link))
		if name then
			out[#out + 1] = { link = link, name = name, icon = icon, count = Num(count) or 1, price = Num(price) or 0, index = i }
		end
	end
	return out
end

local function Same(a, b) return (a.link or a.name) == (b.link or b.name) and a.count == b.count end

--- The game's list read into the kept copy: what was there keeps when it was sold; what's new was sold now. Newest
--- first (the game's list is oldest first).
function BB.Read()
	local game = BB.ReadGame()
	local old = BB.List()
	local used, out = {}, {}
	local now = time()
	for i = #game, 1, -1 do
		local g = game[i]
		local t
		for k, o in ipairs(old) do
			if not used[k] and Same(o, g) then used[k], t = true, o.t break end
		end
		out[#out + 1] = { link = g.link, name = g.name, icon = g.icon, count = g.count, price = g.price, t = t or now }
	end
	local changed = #out ~= #old
	for i = 1, #out do if not changed and not Same(out[i], old[i]) then changed = true end end
	if ns.db then ns.db.buyback = out end
	if changed then ns:Changed("buyback") end
end

--- Where a kept row is in the game's list now (a vendor's window open), or nil.
function BB.IndexOf(e)
	local game = BB.ReadGame()
	for i = #game, 1, -1 do
		if Same(game[i], e) then return game[i].index end
	end
	return nil
end

--- Enter: at a vendor, bought back (for what it sold for); anywhere else, where to.
local function BuyBack(e)
	if not atVendor then
		ns:Print(L["Open any vendor to buy %s back (until you log out)."]:format(tostring(e.name)))
		return
	end
	local i = BB.IndexOf(e)
	if not i then
		ns:Print(L["%s isn't on this vendor's buyback list any more."]:format(tostring(e.name)))
		return
	end
	local money = Num(_G.GetMoney and Safe(_G.GetMoney))
	if money and e.price and money < e.price then
		ns:Print(L["Not enough money to buy %s back (%s)."]:format(tostring(e.name), ns.Money(e.price, true)))
		return
	end
	if not ns.Guarded("BuybackItem", _G.BuybackItem, i) then
		ns:Print(L["Couldn't buy %s back from here: use the vendor's Buyback tab."]:format(tostring(e.name)))
	end
end

local function LinkOf(e) return e.link end
local CHATBOX = ns.ChatBoxSpec(LinkOf)
local function ToChat(e) ns.LinkInChat(e.link) end

local function Detail(x)
	local parts = {}
	if x.count and x.count > 1 then parts[#parts + 1] = "x" .. x.count end
	parts[#parts + 1] = L["sold %s"]:format(ns.Ago(time() - (x.t or time())))
	if x.price and x.price > 0 then parts[#parts + 1] = L["buy back: %s"]:format(ns.Money(x.price)) end
	return ns.Detail(unpack(parts))
end

--- The kept copy as rows, newest first.
function BB.Rows()
	local out = {}
	local list = BB.List()
	for i, x in ipairs(list) do
		local id = x.link and tonumber(x.link:match("item:(%d+)"))
		out[#out + 1] = {
			key = (x.link or x.name) .. "#" .. i, name = x.name, icon = x.icon or BB.ICON, link = x.link, itemID = id,
			count = x.count, price = x.price, t = x.t,
			color = id and ns.QualityHex(ns.ItemQuality(id)) or nil,
			detail = Detail(x), text = "buyback sold vendor",
			activate = BuyBack, staysOpen = true,
			secondary = ToChat, secondarySecure = CHATBOX, secondaryIsOpen = ns.Never,
			_rank = (#list - i + 1) / (#list + 1) * 0.99, -- (newest first among equal matches)
		}
	end
	return out
end

ns:RegisterProvider("buyback", {
	label = L["Sold"],
	color = "ffd9b44a",
	aliases = { "buyback", "sold", "buybacks" },
	explicit = true, -- (only asked for: @buyback, "buyback", "what did i sell")
	refreshOnOpen = 60, -- ("sold 5 min ago" moves on; a sale marks it changed)
	leadRow = ns.EmptyLead(L["Nothing sold since you logged in"], function() return #BB.List() == 0 end),
	collect = function() return BB.Rows() end,
})

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
function BB.OnEvent(event, isLogin)
	if event == "PLAYER_ENTERING_WORLD" then
		-- (a fresh login: the game's buyback list is empty; a /reload or a loading screen: it still holds what you sold)
		if isLogin == true and ns.db then ns.db.buyback = {}; ns:Changed("buyback") end
		return
	end
	if event == "MERCHANT_SHOW" then atVendor = true end
	if atVendor then BB.Read() end
	if event == "MERCHANT_CLOSED" then atVendor = false end
end
-- (a sale's update comes a moment after the item leaves your bags: read when the game has it)
ev:SetScript("OnEvent", function(_, event, a)
	if event == "MERCHANT_UPDATE" and C_Timer then
		C_Timer.After(0, function() BB.OnEvent(event) end)
	else
		BB.OnEvent(event, a)
	end
end)

----------------------------------------------------------------------
-- "buyback", "what did i sell" in plain words
----------------------------------------------------------------------

local BQ = {}
ns.BuybackQ = BQ
local ASKS = {}
for _, s in ipairs({ "buyback", "buy back", "my buyback", "buyback list", "what did i sell", "what have i sold", "what i sold",
	"sold items", "items i sold", "things i sold", "what did i vendor", "undo sell", "undo sale", "buy back what i sold",
	"what did i just sell", "recently sold", "my sold items" }) do
	ASKS[s] = true
end

function BQ.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(" please$", "")
	if ASKS[t] then return {} end
	return nil
end

function BQ.Answer()
	local rows = BB.Rows()
	local note = L["Sold since you logged in"]
	if #rows == 0 then return { ns.NoteRow(L["Nothing sold since you logged in"]) }, note end
	ns.ScoreInOrder(rows)
	return rows, note .. ns.DETAIL_SEP .. (atVendor and L["Enter buys one back"] or L["at any vendor, Enter buys one back"])
end

function BQ.ToAdvanced() return "@buyback " end

local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight
local TOKEN_SECURE, TokenOpen = ns.TOKEN_SECURE, ns.TokenOpen -- (Panels.lua)

-- shared by every currency entry (not one copy per entry)
local function PointAtCurrency(e)
	H:Find(function()
		local root = _G.TokenFrame or CharacterFrame
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end)
end
-- without the game's route (combat): the client's own opener (a C call) if it has one, else said (never ToggleCharacter
-- from here: the character window would hold what Terminal's code wrote)
local function OpenCurrency(e)
	if C_CurrencyInfo.OpenCurrencyPanel then
		C_CurrencyInfo.OpenCurrencyPanel()
		PointAtCurrency(e)
	else
		ns:Print(L["Open the Currency tab from your character window (opening it from Terminal's own code would taint it)."])
	end
end

-- Currencies
----------------------------------------------------------------------

--- A currency's id: in its list info on newer clients, else read from its link (both C calls).
local function CurrencyID(info, index)
	local id = ns.Num(info.currencyID)
	if id then return id end
	local C = C_CurrencyInfo
	local link = C.GetCurrencyListLink and ns.Safe(C.GetCurrencyListLink, index)
	return link and C.GetCurrencyIDFromLink and ns.Num(ns.Safe(C.GetCurrencyIDFromLink, link)) or nil
end

-- The currency list as the Currency tab reads it: a folded header's currencies aren't in it, so folded ones are opened
-- for the read and folded back (ns.ReadExpanded; the tab itself folds them with C_CurrencyInfo.ExpandCurrencyList:
-- Forever's Camelot/Blizzard_TokenUI.lua; review, 0.48.6: "Miscellaneous" folded left its currencies out)
local function CurrencyRow(i)
	local info = ns.Safe(C_CurrencyInfo.GetCurrencyListInfo, i)
	if type(info) ~= "table" then return nil end
	local name = ns.Str(info.name)
	if not name then return nil end
	local r = { name = name, header = info.isHeader and true or false, info = info }
	if r.header then r.collapsed = info.isHeaderExpanded == false else r.id = CurrencyID(info, i) end
	return r
end
local CURRENCY_LIST = {
	count = function() return ns.Num(ns.Safe(C_CurrencyInfo.GetCurrencyListSize)) or 0 end,
	row = CurrencyRow,
	collapsed = function(r) return r.collapsed end,
	expand = function(i) if C_CurrencyInfo.ExpandCurrencyList then ns.Safe(C_CurrencyInfo.ExpandCurrencyList, i, true) end end,
	collapse = function(i) if C_CurrencyInfo.ExpandCurrencyList then ns.Safe(C_CurrencyInfo.ExpandCurrencyList, i, false) end end,
}

ns:RegisterProvider("currency", {
	label = L["Currency"],
	color = "ffffe066",
	aliases = { "currency", "currencies", "token", "tokens" },
	events = { "CURRENCY_DISPLAY_UPDATE" },
	guard = 2,
	selfEvents = true, -- (opening folded headers for the read fires CURRENCY_DISPLAY_UPDATE)
	collect = function()
		local out = {}
		for _, r in ipairs(ns.ReadExpanded(CURRENCY_LIST, 200)) do
			local info = r.info
			if not r.header and (ns.Num(info.quantity) or 0) > 0 then -- only currencies you hold
				out[#out + 1] = {
					key = r.name,
					name = r.name,
					icon = info.iconFileID,
					-- the numbers too, for filters (count:, the weekly cap); maxQuantity 0 = uncapped
					currencyID = r.id,
					quantity = ns.Num(info.quantity) or 0,
					maxQuantity = ns.Num(info.maxQuantity) or 0,
					maxWeeklyQuantity = ns.Num(info.maxWeeklyQuantity),
					quantityEarnedThisWeek = ns.Num(info.quantityEarnedThisWeek),
					detail = tostring(ns.Num(info.quantity) or 0) .. (((ns.Num(info.maxQuantity) or 0) > 0) and ("/" .. ns.Num(info.maxQuantity)) or ""),
					secure = TOKEN_SECURE, isOpen = TokenOpen, after = PointAtCurrency, -- (the game opens the tab)
					activate = OpenCurrency,
				}
			end
		end
		return out
	end,
})

local ns = select(2, ...)
local H = ns.Highlight
local TOKEN_SECURE, TokenOpen = ns.TOKEN_SECURE, ns.TokenOpen -- (Panels.lua)

-- shared by every currency entry (not one copy per entry)
local function PointAtCurrency(e)
	H:Find(function()
		local root = _G.TokenFrame or CharacterFrame
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end)
end
-- without the tab's /click route: the client's own opener (a C call), else the character window from here
local function OpenCurrency(e)
	if C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel() else ToggleCharacter("TokenFrame") end
	PointAtCurrency(e)
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

ns:RegisterProvider("currency", {
	label = "Currency",
	color = "ffffe066",
	aliases = { "currencies", "token", "tokens" },
	events = { "CURRENCY_DISPLAY_UPDATE" },
	guard = 2,
	collect = function()
		local out = {}
		for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
			local info = C_CurrencyInfo.GetCurrencyListInfo(i)
			if info and not info.isHeader and info.name and (info.quantity or 0) > 0 then -- only currencies you hold
				out[#out + 1] = {
					key = info.name,
					name = info.name,
					icon = info.iconFileID,
					-- the numbers too, for filters (count:, the weekly cap); maxQuantity 0 = uncapped
					currencyID = CurrencyID(info, i),
					quantity = ns.Num(info.quantity) or 0,
					maxQuantity = ns.Num(info.maxQuantity) or 0,
					maxWeeklyQuantity = ns.Num(info.maxWeeklyQuantity),
					quantityEarnedThisWeek = ns.Num(info.quantityEarnedThisWeek),
					detail = tostring(info.quantity or 0) .. ((info.maxQuantity and info.maxQuantity > 0) and (" / " .. info.maxQuantity) or ""),
					secure = TOKEN_SECURE, isOpen = TokenOpen, after = PointAtCurrency, -- (the game opens the tab)
					activate = OpenCurrency,
				}
			end
		end
		return out
	end,
})

-- Your other characters' currencies on @currency's tooltip (Providers/Currency.lua, Stored.lua's S.CurrencyLines): from
-- Syndicator's GetCurrencyInfo, asked with the settings @stored honours (connected realms only, one faction only), the
-- character you're on left out (its amount is the game's), the most first, and the total; without Syndicator only yours.
local T = ...
local ns, check = T.ns, T.check
local S, L = ns.Stored, ns.L

io.write("[currency: your alts' amounts on its tooltip]\n")
do
	local was = { syn = rawget(_G, "Syndicator"), cfg = rawget(_G, "SYNDICATOR_CONFIG"), mine = S.mineName }
	local ok, err = pcall(function()
		local asked
		_G.SYNDICATOR_CONFIG = { tooltips_connected_realms_only_2 = false, tooltips_faction_only = true }
		_G.Syndicator = { API = {
			GetAllCharacters = function() return {} end, GetByCharacterFullName = function() return nil end, IsReady = function() return true end,
			GetCurrentCharacter = function() return "Plamen Warr-Forever" end,
			GetCurrencyInfo = function(id, connected, faction)
				asked = { id = id, connected = connected, faction = faction }
				return { { character = "Plamen Warr", realmNormalized = "Forever", className = "WARRIOR", quantity = 40 },
					{ character = "Plamen Pally", realmNormalized = "Forever", className = "PALADIN", quantity = 3 },
					{ character = "Plamen Mage", realmNormalized = "Other", className = "MAGE", quantity = 12 },
					{ character = "Plamen Zero", realmNormalized = "Forever", quantity = 0 } }
			end } }
		S.mineName = "Plamen Warr"
		local alts = S.CurrencyHolders(1901)
		check(asked and asked.id == 1901 and asked.connected == false and asked.faction == true,
			"asked with Syndicator's own tooltip settings")
		check(alts and #alts == 2 and alts[1].who == "Plamen Mage-Other" and alts[1].count == 12 and alts[2].who == "Plamen Pally",
			"your alts, the most first, another realm's named with it; you and those with none left out")
		-- the row's tooltip: the game's own, then the characters and the total
		local p = ns.providers.currency
		local lines = {}
		local tip = { SetCurrencyByID = function(_, id) lines[#lines + 1] = "game:" .. id end,
			SetText = function(_, s) lines[#lines + 1] = "text:" .. s end,
			AddLine = function(_, s) lines[#lines + 1] = "line:" .. tostring(s) end,
			AddDoubleLine = function(_, a, b) lines[#lines + 1] = ns.Plain(a) .. "=" .. ns.Plain(b) end }
		local e = { name = "Honor Points", currencyID = 1901, quantity = 40, detail = "40" }
		-- (the tooltip function the rows carry: a row of the list made with a mocked currency list)
		local C = _G.C_CurrencyInfo
		local saveC = { size = C.GetCurrencyListSize, info = C.GetCurrencyListInfo }
		C.GetCurrencyListSize = function() return 1 end
		C.GetCurrencyListInfo = function() return { name = "Honor Points", currencyID = 1901, quantity = 40, maxQuantity = 0, iconFileID = 1 } end
		p._dirty = true
		local rows = ns:GetEntries(p)
		C.GetCurrencyListSize, C.GetCurrencyListInfo = saveC.size, saveC.info
		p._dirty = true
		local fn = rows[1] and rows[1].tooltip
		check(type(fn) == "function", "currency rows draw their own tooltip")
		fn(e, tip)
		local all = table.concat(lines, " | ")
		check(lines[1] == "game:1901" and all:find("Plamen Warr " .. L["(you)"] .. "=40", 1, true) and all:find("Plamen Mage-Other=12", 1, true)
			and all:find("Plamen Pally=3", 1, true) and all:find(L["Total"] .. "=55", 1, true), "the game's tooltip, yours, your alts', the total: " .. all)
		-- no game tooltip for it: its name and amount; without Syndicator: only that
		_G.Syndicator = nil
		lines = {}
		tip.SetCurrencyByID = nil
		fn(e, tip)
		check(table.concat(lines, " | ") == "text:Honor Points | line:40" and S.CurrencyHolders(1901) == nil, "without Syndicator: yours only: " .. table.concat(lines, " | "))
	end)
	_G.Syndicator, _G.SYNDICATOR_CONFIG, S.mineName = was.syn, was.cfg, was.mine
	check(ok, "currency alts: " .. tostring(err))
end

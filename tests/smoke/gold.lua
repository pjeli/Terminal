-- Gold (Gold.lua): @gold lists your own gold (live), and with Syndicator or BagBrother every alt's, guild banks and the
-- warband bank, with a total on top, counted the way the bag addon's own gold summary counts it.
local T = ...
local ns, UI, check, key, FlushAll = T.ns, T.UI, T.check, T.key, T.FlushAll

local function list(res) local t = {} for _, e in ipairs(res) do t[#t + 1] = tostring(e.name) .. "=" .. tostring(e.money) end return table.concat(t, ",") end

io.write("[gold]\n")
do
	local G = ns.Gold
	local save = { money = _G.GetMoney, syn = _G.Syndicator, bag = _G.Baganator, bb = _G.BrotherBags, bn = _G.Bagnon,
		bank = _G.C_Bank, out = ns.Output, link = ns.LinkInChat, ac = _G.GetAutoCompleteRealms, easy = ns.db.easyMode }
	local P = ns.providers.gold
	check(P and ns:ResolveProvider("gold") == P and ns:ResolveProvider("money") == P, "@gold and @money")
	check(G.Text(12345678, true) == "1,234g 56s 78c" and G.Text(50000, true) == "5g" and G.Text(30, true) == "30c"
		and G.Text(10030, true) == "1g 0s 30c" and G.Text(0, true) == "0c", "money text: " .. G.Text(10030, true))
	check(G.Text(3e13, true):find("^3,000,000,000g"), "big sums don't overflow: " .. G.Text(3e13, true))
	check(G.Text(50000):find("UI%-GoldIcon"), "shown with coin icons")

	-- no bag addon: just you
	_G.Syndicator, _G.Baganator, _G.BrotherBags, _G.Bagnon, _G.C_Bank = nil, nil, nil, nil, nil
	local mine = 1234500
	_G.GetMoney = function() return mine end
	P._dirty = true
	local res = UI:Search("@gold")
	check(#res == 1 and res[1].money == 1234500 and res[1].goldKind == "me", "no bag addon: only you, live: " .. list(res))
	mine = 2000000
	local ev = {}
	for _, e in ipairs(P.events) do ev[e] = true end
	check(ev.PLAYER_MONEY and ev.ACCOUNT_MONEY, "rebuilt when your money changes")
	P._dirty = true
	res = UI:Search("@gold")
	check(res[1].money == 2000000, "read again: " .. list(res))

	-- Baganator + Syndicator: alts, guilds and the warband as its gold summary shows them
	local SD = {
		Characters = {
			["Me-Forever"] = { money = 1, details = { character = "Me", realmNormalized = "Forever", className = "WARRIOR", show = { gold = true } } },
			["Rich-Forever"] = { money = 50000000, details = { character = "Rich", realmNormalized = "Forever", className = "MAGE", show = { gold = true } } },
			["Poor-Forever"] = { money = 500, details = { character = "Poor", realmNormalized = "Forever", show = { gold = true } } },
			["Hidden-Forever"] = { money = 99999999, details = { character = "Hidden", realmNormalized = "Forever", show = { gold = false } } },
			["Old-Forever"] = { money = 7, details = { character = "Old", realmNormalized = "Forever", hidden = true } },
			["Far-Elsewhere"] = { money = 99999999, details = { character = "Far", realmNormalized = "Elsewhere", show = { gold = true } } },
			["Near-Linked"] = { money = 300000, details = { character = "Near", realmNormalized = "Linked", show = { gold = true } } },
		},
		Guilds = {
			["Guildy-Forever"] = { money = 1000000, details = { guild = "Guildy", realmNormalized = "Forever", show = { gold = true } } },
			["Quiet-Forever"] = { money = 1000000, details = { guild = "Quiet", realmNormalized = "Forever", show = { gold = false } } },
		},
		Warband = { { money = 4000000 } },
	}
	local callbacks = {}
	_G.Syndicator = {
		Utilities = { GetConnectedRealms = function() return { "Forever", "Linked" } end },
		Constants = { IsClassic = false },
		API = {
			IsReady = function() return true end,
			GetCurrentCharacter = function() return "Me-Forever" end,
			GetAllCharacters = function() local o = {} for k in pairs(SD.Characters) do o[#o + 1] = k end return o end,
			GetByCharacterFullName = function(n) return SD.Characters[n] end,
			GetAllGuilds = function() local o = {} for k in pairs(SD.Guilds) do o[#o + 1] = k end return o end,
			GetByGuildFullName = function(n) return SD.Guilds[n], n end,
			GetWarband = function(i) return SD.Warband[i or 1] end,
		},
		CallbackRegistry = { RegisterCallback = function(_, ev, fn) callbacks[ev] = fn end },
	}
	_G.Baganator = { CallbackRegistry = {} }
	ns.Stored.hooked = nil
	ns.Stored.HookSyndicator()
	P._dirty = true
	res = UI:Search("@gold")
	local by = {}
	for _, e in ipairs(res) do by[e.name] = e end
	local total = 2000000 + 50000000 + 500 + 300000 + 1000000 + 4000000
	check(res[1].name == "All gold" and res[1].money == total, "the total on top, everything counted: " .. list(res))
	check(res[2].goldKind == "me" and res[2].money == 2000000, "you next, live (not Syndicator's stale record): " .. list(res))
	check(res[3].name == "Rich" and by["Near-Linked"] and by.Poor, "then the richest first; a connected realm named Name-Realm: " .. list(res))
	check(not by.Hidden and not by.Old and not by["Far-Elsewhere"] and not by.Far, "characters hidden from its gold summary, or on other realms, left out")
	check(by.Guildy and not by.Quiet and by["Warband bank"] and by["Warband bank"].money == 4000000, "guild banks shown for gold, and the warband bank")
	check(res[1].detail:find("4 characters", 1, true), "the total says how many characters: " .. res[1].detail)
	P._dirty = false
	check(type(callbacks.CurrencyCacheUpdate) == "function", "listens to Syndicator's money updates")
	callbacks.CurrencyCacheUpdate("Rich-Forever")
	check(P._dirty == true, "and rebuilds after them")
	-- searching by name, and "alts"
	res = UI:Search("@gold rich")
	check(res[1] and res[1].name == "Rich", "@gold rich: " .. list(res))
	-- the tooltip of the total lists everyone
	local lines = {}
	local tip = { SetText = function(_, s) lines[#lines + 1] = s end, AddLine = function(_, s) lines[#lines + 1] = s end,
		AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. "=" .. b end }
	res = UI:Search("@gold")
	res[1].tooltip(res[1], tip)
	local joined = table.concat(lines, "\n")
	check(joined:find("Rich", 1, true) and joined:find("Guildy", 1, true) and joined:find("Warband bank", 1, true), "the total's tooltip lists everyone")
	-- Enter lists it in chat; Shift+Enter puts the row in the chat box as plain text
	local said
	ns.Output = function(_, l) said = l end
	res[1].activate(res[1])
	check(said and #said == #res and said[1]:find("All gold", 1, true), "Enter: every row in chat")
	local box
	ns.LinkInChat = function(s) box = s end
	res[1].secondary(res[1])
	check(box == "All gold: " .. G.Text(total, true), "Shift+Enter: the total in the chat box: " .. tostring(box))
	check(ns.Share.Text(res[3]) == "Rich: 5,000g", ">> sends plain text: " .. tostring(ns.Share.Text(res[3])))
	-- Syndicator still loading: you only, and busy
	_G.Syndicator.API.IsReady = function() return false end
	P._dirty = true
	res = UI:Search("@gold")
	check(#res == 1 and P.busy() and P.busy():find("Syndicator", 1, true), "while Syndicator loads: you only, and busy")
	_G.Syndicator.API.IsReady = function() return true end
	-- classic clients: your faction only, as Baganator does there
	_G.Syndicator.Constants.IsClassic = true
	SD.Characters["Me-Forever"].details.faction = "Horde"
	SD.Characters["Rich-Forever"].details.faction = "Alliance"
	SD.Characters["Poor-Forever"].details.faction = "Horde"
	P._dirty = true
	by = {}
	for _, e in ipairs(UI:Search("@gold")) do by[e.name] = e end
	check(by.Poor and not by.Rich, "classic: the other faction's characters left out")
	_G.Syndicator.Constants.IsClassic = false

	-- Bagnon + BagBrother: its characters on your realm and the connected ones
	_G.Syndicator, _G.Baganator = nil, nil
	_G.Bagnon = { Frames = { IsEnabled = function() return true end }, Owners = {}, player = { id = "Me", realm = "Forever" } }
	_G.BrotherBags = {
		Forever = { Me = { money = 1 }, Alt = { money = 70000, class = "PRIEST" }, ["Guildy*"] = { money = 5 } },
		Linked = { Twin = { money = 20000 } },
		Elsewhere = { Far = { money = 99999999 } },
		account = {},
	}
	_G.GetAutoCompleteRealms = function() return { "Forever", "Linked" } end
	_G.C_Bank = { FetchDepositedMoney = function() return 10000 end }
	local saveBT = Enum.BankType
	Enum.BankType = Enum.BankType or { Account = 2 }
	P._dirty = true
	res = UI:Search("@gold")
	by = {}
	for _, e in ipairs(res) do by[e.name] = e end
	check(by.Alt and by["Twin-Linked"] and not by["Far-Elsewhere"] and not by.Guildy and not by["Guildy*"] and by["Warband bank"],
		"BagBrother: your realm and connected ones, no guilds, the warband bank live: " .. list(res))
	check(res[1].name == "All gold" and res[1].money == 2000000 + 70000 + 20000 + 10000, "BagBrother total: " .. list(res))

	-- Simple mode: "gold" under Character
	ns.db.easyMode = nil
	res = UI:Search("gold")
	local found = false
	for _, e in ipairs(res) do if e.goldKind == "total" or (e.catId == "character") then found = true end end
	check(found, "Simple: gold is found (Character): " .. list(res))
	ns.db.easyMode = save.easy

	_G.GetMoney, _G.Syndicator, _G.Baganator, _G.BrotherBags, _G.Bagnon = save.money, save.syn, save.bag, save.bb, save.bn
	_G.C_Bank, ns.Output, ns.LinkInChat, _G.GetAutoCompleteRealms = save.bank, save.out, save.link, save.ac
	Enum.BankType = saveBT
	ns.Stored.hooked = nil
	P._dirty = true
	UI:Hide()
end

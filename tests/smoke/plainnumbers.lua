-- Numbers in plain words (0.66.5, the player): "swords between level 20 and 30" is lvl:20-30, "quests under level 25"
-- lvl:<25, "items worth more than 1g" value:>1g, "bags with at least 10 slots" slots:>=10. Search/Easy.lua (PlainNumbers),
-- Filters (value:, slots:, F.Copper, F.MoneyRange).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local E, F, B = ns.Easy, ns.Filters, ns.Bar

io.write("[plainnumbers: ranges and comparisons in words]\n")
do
	local function Read(text)
		local words = {}
		for w in text:gmatch("%S+") do words[#words + 1] = w end
		local out, said = E.PlainNumbers(words)
		return table.concat(out, " "), said
	end
	local CASES = {
		{ "swords between level 20 and 30", "swords lvl:20-30" },
		{ "quests under level 25", "quests lvl:<25" },
		{ "quests level under 25", "quests lvl:<25" },
		{ "items worth more than 1g", "items value:>1g" },
		{ "bags with at least 10 slots", "bags with slots:>=10" },
		{ "bags with 10 slots or more", "bags with slots:>=10" },
		{ "level 20 swords", "lvl:20 swords" },
		{ "levels 20 to 30 quests", "lvl:20-30 quests" },
		{ "level 20-30 quests", "lvl:20-30 quests" },
		{ "quests level 25 or higher", "quests lvl:>=25" },
		{ "quests at most level 10", "quests lvl:<=10" },
		{ "from level 10 to 20", "lvl:10-20" },
		{ "gear with durability below 50%", "gear with dura:<50" },
		{ "linen under 1 gold 50 silver", "linen value:<1g50s" },
		{ "cloth worth between 10s and 1g", "cloth value:10s-1g" },
		{ "item level over 30", "ilvl:>30" },
		{ "ilvl 40+", "ilvl:40+" },
		{ "10 slot bag", "slots:10 bag" }, -- (a bag's tooltip says "10 Slot Bag")
		-- left as words: no number, a number with nothing to say what it is, a name's words
		{ "under the sea", "under the sea" },
		{ "more than 5 linen", "more than 5 linen" },
		{ "worth 1g", "worth 1g" },
		{ "level", "level" },
	}
	for _, c in ipairs(CASES) do
		local got = Read(c[1])
		check(got == c[2], ("%q -> %q: %s"):format(c[1], c[2], got))
	end
	local _, said = Read("swords between level 20 and 30")
	check(said["lvl:20-30"] == "between level 20 and 30", "the words it came from, for the bar: " .. tostring(said["lvl:20-30"]))

	-- money
	check(F.Copper("1g") == 10000 and F.Copper("1g50s") == 15000 and F.Copper("50s") == 5000 and F.Copper("30c") == 30
		and F.Copper("2.5g") == 25000 and F.Copper("123") == 123 and F.Copper("1x") == nil and F.Copper("") == nil, "amounts of money")
	local r = F.MoneyRange(">1g")
	check(r and r(10001) and not r(10000) and F.MoneyRange("10s-1g")(5000) and not F.MoneyRange("10s-1g")(500), "money ranges")

	-- searched: Simple mode reads them, the bar shows them, Alt+` writes them
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, info = C_Item.GetItemInfo }
	ns.providers, ns.providerOrder = {}, {}
	local ITEMS = { [501] = { "Short Sword", 10, 500 }, [502] = { "Long Sword", 22, 15000 }, [503] = { "Great Sword", 28, 9000 },
		[504] = { "Broad Sword", 35, 30000 } }
	local realInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(id)
		local t = ITEMS[tonumber(tostring(id):match("(%d+)")) or 0]
		if t then return t[1], "|Hitem:" .. id .. "|h", 2, t[2] + 2, t[2], "Weapon", "One-Handed Swords", 1, "INVTYPE_WEAPON", 1, t[3] end
		return realInfo(id)
	end
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for id, t in pairs(ITEMS) do out[#out + 1] = { name = t[1], itemID = id, key = id } end
		return out
	end })
	ns:AliasesChanged()
	F.ClearCache()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = true; UI:EasyChanged()
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name):match("^(%S+)") end end
		table.sort(t)
		return table.concat(t, " ")
	end
	UI:Open(""); FlushAll()
	UI:SetQuery("sword between level 20 and 30"); FlushAll()
	check(Names() == "Great Long", "swords between level 20 and 30: " .. Names())
	check(ns.QueryToAdvanced(UI.edit:GetText()):find("lvl:20-30", 1, true), "Alt+` writes lvl:20-30: " .. ns.QueryToAdvanced(UI.edit:GetText()))
	local typed = B.Typed()
	check(#typed.filters == 1 and typed.filters[1].spec == "lvl:20-30" and B.SpecLabel(typed.filters[1].spec) == ns.L["Level %s"]:format("20-30"),
		"the bar shows it: " .. tostring(typed.filters[1] and typed.filters[1].spec))
	-- the bar unticks it: its words go from the line
	B.Pick("filter", "lvl:20-30"); FlushAll()
	check(UI.edit:GetText() == "sword", "unticked: its words taken out: " .. UI.edit:GetText())
	UI:SetQuery("sword worth more than 1g"); FlushAll()
	check(Names() == "Broad Long", "worth more than 1g: " .. Names())
	UI:SetQuery("sword under level 20"); FlushAll()
	check(Names() == "Short", "under level 20: " .. Names())
	local same, why = T.SameAsAdvanced("sword under level 20")
	check(same, "as Advanced's: " .. tostring(why))
	UI:Hide(); FlushAll()
	C_Item.GetItemInfo = realInfo
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	F.ClearCache()
	UI.lastScan, UI.lastExtra = nil, nil
end

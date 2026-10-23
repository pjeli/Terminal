-- 0.66.x review (0.66.14): what a review of 0.66.4-0.66.10 found, each failing before its fix.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local A, E, B, F = ns.Aggregate, ns.Easy, ns.Bar, ns.Filters

io.write("[review: sort with | except; | also's stale scores]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local BAGS = { { "Iron Sword", 2, 11 }, { "Arcanite Sword", 4, 12 }, { "Bronze Sword", 3, 13 }, { "Copper Sword", 1, 14 } }
	local BANK = { { "Copper Sword", 1, 14 }, { "Zinc Sword", 2, 16 } }
	local function Rows(list, where)
		return function()
			local out = {}
			for i, r in ipairs(list) do out[i] = { name = r[1], quality = r[2], itemID = r[3], key = where .. i } end
			return out
		end
	end
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Rows(BAGS, "bags") })
	ns:RegisterProvider("bank", { label = "Bank", aliases = { "bank" }, collect = Rows(BANK, "bank") })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name):match("^(%S+)") end end
		return table.concat(t, " ")
	end
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("@item sword sort:name | except @bank "); FlushAll()
	check(Names() == "Arcanite Bronze Iron", "sort:name kept with | except @bank: " .. Names())
	-- a search that scores the bank's rows, then another that adds them
	UI:SetQuery("@bank sword "); FlushAll()
	UI:SetQuery("@item iron | also @bank "); FlushAll()
	check(Names():match("^Iron"), "| also: the search's own row first, the added after: " .. Names())
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

io.write("[review: top N over Simple mode's categories]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function() return {
		{ name = "Iron Sword", itemID = 11, key = "i1" }, { name = "Bronze Sword", itemID = 13, key = "i2" } } end })
	ns:RegisterProvider("stored", { label = "Stored", aliases = { "stored" }, collect = function() return {
		{ name = "Zinc Sword", itemID = 16, key = "s1" } } end })
	ns:RegisterProvider("spells", { label = "Spell", aliases = { "spell" }, collect = function() return {
		{ name = "Sword Dance", spellID = 5, key = "p1" } } end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("sword"); FlushAll()
	local cats = #UI.Results()
	UI:SetQuery("2 sword"); FlushAll()
	local cat = 0
	for _, e in ipairs(UI.Results()) do if e.catId then cat = cat + 1 end end
	check(cat == 0 or cat == cats, "\"2 sword\": not the first 2 of " .. cats .. " categories: " .. cat .. " category rows")
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

io.write("[review: dates on loot questions]\n")
do
	local save = { time = _G.time, date = _G.date, log = ns.db.lootLog, easy = ns.db.easyMode, now = ns.Now }
	local now = os.time({ year = 2026, month = 10, day = 22, hour = 15, min = 0, sec = 0 })
	_G.time = function(t) if t then return os.time(t) end return now end
	_G.date = function(f, t) return os.date(f, t or now) end
	ns.Now = function() return now end
	local me = ns.CharacterName and ns.CharacterName() or "Me"
	ns.db.lootLog = { { t = now - 60, id = 2589, link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r", who = me },
		{ t = now - 86400, id = 2592, link = "|cff1eff00|Hitem:2592::::::::|h[Wool Cloth]|h|r", who = me },
		{ t = now - 5 * 86400, id = 4306, link = "|cff1eff00|Hitem:4306::::::::|h[Silk Cloth]|h|r", who = me } }
	ns.providers.lootlog._dirty = true
	ns.db.easyMode = true; UI:EasyChanged()
	local function Got(q)
		local t = {}
		for _, e in ipairs(UI:SearchText(q)) do if B.Real(e) then t[#t + 1] = tostring(e.name):match("^%[?(%a+)") or tostring(e.name) end end
		return table.concat(t, " ")
	end
	check(Got("what dropped today") == "Linen", "what dropped today: today's only: " .. Got("what dropped today"))
	check(Got("loot today") == "Linen", "loot today: " .. Got("loot today"))
	check(Got("loot from yesterday") == "Wool", "loot from yesterday: " .. Got("loot from yesterday"))
	_G.time, _G.date, ns.db.lootLog, ns.db.easyMode, ns.Now = save.time, save.date, save.log, save.easy, save.now
	ns.providers.lootlog._dirty = true
	UI:EasyChanged()
end

io.write("[review: mail older than 20 days is no mail question]\n")
do
	local easy = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	-- ("mail" alone is the armour's type: "my mail" is yours, as the changelog says it)
	local adv = E.ToAdvanced("my mail older than 20 days")
	check(adv:find("older:20d", 1, true) and not adv:find("type:mail", 1, true), "my mail older than 20 days: your mail, older:20d: " .. adv)
	ns.db.easyMode = easy; UI:EasyChanged()
end

io.write("[review: Alt+` keeps the bar's Group with top N / except]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function() return {
		{ name = "Iron Sword", quality = 2, key = 1 }, { name = "Arcanite Sword", quality = 4, key = 2 }, { name = "Bronze Sword", quality = 3, key = 3 } } end })
	ns:AliasesChanged()
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("sword"); FlushAll()
	B.Pick("group", "quality"); FlushAll()
	UI:SetQuery("2 sword"); FlushAll()
	local grouped = UI.Results()[1] and not B.Real(UI.Results()[1]) or (UI.Results()[1] and UI.Results()[1].drill ~= nil)
	local adv = E.ToAdvanced("2 sword")
	check(adv:find("group by quality", 1, true), "Alt+` of \"2 sword\" with the bar's Group: " .. adv)
	B.Reset()
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

io.write("[review: .explain of <=, >= with me]\n")
do
	local s1, s2 = E.Explain("@quest lvl:<=me"), E.Explain("@quest lvl:>=me+1")
	check(not s1:find("below your level", 1, true), "lvl:<=me includes yours: " .. s1)
	check(not s2:find("above a level above yours", 1, true), "lvl:>=me+1: " .. s2)
end

io.write("[review: plain words taken from a name]\n")
do
	local function Read(text)
		local words = {}
		for w in text:gmatch("%S+") do words[#words + 1] = w end
		return table.concat((E.PlainNumbers(words)), " ")
	end
	check(Read("tome of the last day") == "tome of the last day", "a name's words: " .. Read("tome of the last day"))
	local rest, n = E.TopN("the five sorrows")
	check(n == nil, "\"the five sorrows\" isn't top 5 of \"the sorrows\": " .. tostring(rest) .. " " .. tostring(n))
	check(Read("cloth worth between 10 and 50 silver") == "cloth value:10s-50s", "" .. Read("cloth worth between 10 and 50 silver"))
end

io.write("[review: the bar's words for dates and levels; Alt+` keeps top N before >>]\n")
do
	local L = ns.L
	check(B.SpecLabel("since:yesterday") == L["Since %s"]:format(L["yesterday"]) and B.SpecLabel("older:today") == L["Before %s"]:format(L["today"])
		and B.SpecLabel("older:20d") == L["Older than %s"]:format(L["%s %s"]:format("20", L["days"])),
		"date chips: " .. B.SpecLabel("since:yesterday") .. " / " .. B.SpecLabel("older:today") .. " / " .. B.SpecLabel("older:20d"))
	check(B.SpecLabel("lvl:me+3") == ns.UpperFirst(L["%s above yours"]:format(L["%s levels"]:format("3"))), "lvl:me+3 chip: " .. B.SpecLabel("lvl:me+3"))
	local easy = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	local adv = E.ToAdvanced("5 sword >> party")
	check(adv:find("| first 5", 1, true) and adv:find(">> party", 1, true), "5 sword >> party: " .. adv)
	ns.db.easyMode = easy; UI:EasyChanged()
	check(E.Explain("@drop since:3days") == "Loot you saw drop, since 3 days", "explain says what since: reads: " .. tostring(E.Explain("@drop since:3days")))
end

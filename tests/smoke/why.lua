-- "Why is this here?" (0.66.11, the player): a row's menu says why the last search listed it. Search/Search.lua
-- (UI:WhyLines), UI/RowMenu.lua.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local L = ns.L

io.write("[why: what a row matched]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local ROWS = { { "Arcanite Sword", 4, 3, "a blade" }, { "Iron Sword", 2, 9, "a sword" }, { "Bronze Mace", 3, 1, "sword-like" } }
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for i, r in ipairs(ROWS) do out[i] = { name = r[1], quality = r[2], count = r[3], text = r[4], key = i } end
		return out
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open(""); FlushAll()
	UI:SetQuery("@item sword count:2+ sort:count "); FlushAll()
	local row
	for _, e in ipairs(UI.Results()) do if e.name == "Arcanite Sword" then row = e end end
	check(row ~= nil, "the row is listed")
	local lines = table.concat(UI:WhyLines(row), "\n")
	check(lines:find(L["Why %s is here:"]:format("Arcanite Sword"), 1, true), "which row: " .. lines)
	check(lines:find(L["it's one of %s"]:format(L["items"]), 1, true), "its list")
	check(lines:find(L["\"%s\": %s"]:format("sword", L["in its name"]), 1, true), "the word, in its name")
	check(lines:find("passed count:2+ (" .. L["%s of them"]:format(L["%s or more"]:format("2")) .. ")", 1, true), "the filter it passed, said: " .. lines)
	check(lines:find(L["sorted by %s: %s"]:format(L["count"], "3"), 1, true), "the sort's value for it")
	-- (review) sort:name says its name; a quality its word, not its number
	UI:SetQuery("@item sword sort:name "); FlushAll()
	lines = table.concat(UI:WhyLines(UI.Results()[1]), "\n")
	check(lines:find(L["sorted by %s: %s"]:format(L["name"], "Arcanite Sword"), 1, true), "sorted by name: its name: " .. lines)
	-- (review) "| also": said only of the rows it added
	ns:RegisterProvider("bank", { label = "Bank", aliases = { "bank" }, collect = function()
		return { { name = "Thorium Sword", key = "b1", text = "in the bank" } }
	end })
	ns:AliasesChanged()
	UI:SetQuery("@item sword | also @bank "); FlushAll()
	local own, added
	for _, e in ipairs(UI.Results()) do
		if e.name == "Iron Sword" then own = e elseif e.name == "Thorium Sword" then added = e end
	end
	local ownLines = own and table.concat(UI:WhyLines(own), "\n") or ""
	local addedLines = added and table.concat(UI:WhyLines(added), "\n") or ""
	check(own and not ownLines:find(L["added by | also %s"]:format("@bank"), 1, true), "a row the search found: not added by | also: " .. ownLines)
	check(added and addedLines:find(L["added by | also %s"]:format("@bank"), 1, true)
		and not addedLines:find(L["a close spelling of a word in it"], 1, true), "the row | also added: said so, no words claimed: " .. addedLines)
	ns.providers.bank = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "bank" then table.remove(ns.providerOrder, i) end end
	ns:AliasesChanged()
	-- a word found elsewhere than its name
	UI:SetQuery("@item blade"); FlushAll()
	lines = table.concat(UI:WhyLines(UI.Results()[1]), "\n")
	check(lines:find(L["\"%s\": %s"]:format("blade", L["in what it's about (its other words)"]), 1, true), "in its other words: " .. lines)
	-- an upgrade: what it gains, by which tree's weights
	local F = ns.Filters
	F.fitMade = true
	F.SetGain(row, { gain = 9.46, kinds = { str = 7, sta = 4 }, worn = { str = 0, agi = 2 }, role = "arms", name = "Old Helm" })
	lines = table.concat(UI:WhyLines(row), "\n")
	check(lines:find(L["an upgrade: %s over %s, worth %s by %s weights"]:format("+7 str, +4 sta, -2 agi", "Old Helm", "9.5", F.ROLE_SAY.arms), 1, true),
		"an upgrade: its stats over what you wear, its gain: " .. lines)
	F.SetGain(row, nil)
	F.fitMade = nil
	-- a question's row
	UI.whyQ = { answer = "what killed me" }
	lines = table.concat(UI:WhyLines(row), "\n")
	check(lines:find(L["your question \"%s\" lists it"]:format("what killed me"), 1, true), "a question's answer")
	-- the menu offers it; it's said in chat
	UI:SetQuery("@item sword"); FlushAll()
	UI:ShowRowMenu(1)
	local found
	for i = 1, 20 do
		local b = _G["TerminalRowMenuLine" .. i]
		if b and b.item and b.item.label == L["Why is this here?"] then found = b.item end
	end
	check(found and found.run, "the row's menu: Why is this here?")
	local said = {}
	local realPrint = ns.Print
	ns.Print = function(_, m) said[#said + 1] = m end
	if found then found.run() end
	ns.Print = realPrint
	check(#said >= 3 and said[1]:find("is here", 1, true), "said in chat: " .. tostring(said[1]))
	UI:HideRowMenu()
	UI:Hide(); FlushAll()
	ns.providers, ns.providerOrder, ns.db.easyMode = saved.providers, saved.order, saved.easy
	ns:AliasesChanged(); UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
end

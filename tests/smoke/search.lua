-- Search: the "Search Questie's NPCs" row beside your own quest of that name (Steelsnap), initials
-- ("scb"), place shorthand ("brd", "sw") and close spellings ("hearhtstone").
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local Fuzzy = ns.Fuzzy

-- every list swapped for these test ones while a block runs (nothing else in the results), put
-- back after: the other test files see the lists as they were
local saved = { providers = ns.providers, order = ns.providerOrder }
local function Use(defs)
	ns.providers, ns.providerOrder = {}, {}
	for _, d in ipairs(defs) do ns:RegisterProvider(d[1], d[2]) end
	UI.lastScan = nil
end
local function Restore()
	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	UI.lastScan = nil
end
local function Rows(list)
	return function()
		local out = {}
		for i, r in ipairs(list) do
			local e = {}
			for k, v in pairs(r) do e[k] = v end
			e.key = e.key or i
			out[i] = e
		end
		return out
	end
end
-- a big @kind list with only a name index (as Questie's: hintFind); withRows: it also hands back
-- the first ids and makes a row for one (hintRow), as Questie's lists do
local function HintList(label, alias, names, withRows)
	return { label = label, hintLabel = label, aliases = { alias }, explicit = true, collect = function() return {} end,
		hintFind = function(_, tokens)
			local first, count, ids = nil, 0, {}
			for i, n in ipairs(names) do
				local ln, all = n:lower(), true
				for _, tk in ipairs(tokens) do if not ln:find(tk, 1, true) then all = false end end
				if all then
					count = count + 1; first = first or n
					if #ids < 2 then ids[#ids + 1] = i end
				end
			end
			if withRows then return first, count, ids end
			return first, count
		end,
		hintRow = withRows and function(_, id) return names[id] and { name = names[id], key = id, kind = alias } or nil end or nil }
end
local function Index(res, pred)
	for i, e in ipairs(res) do if pred(e) then return i end end
end
local function Named(n) return function(e) return e.name == n end end
local function Offers(c) return function(e) return e.completion == c end end
-- each block: an error is a failure, and the lists are put back whatever happens
local function Run(title, fn)
	io.write("[search: " .. title .. "]\n")
	local ok, err = pcall(fn)
	Restore()
	UI:Hide(); FlushAll()
	if not ok then check(false, title .. ": " .. tostring(err)) end
end
local function Show(res)
	local t = {}
	for i = 1, math.min(#res, 6) do t[i] = tostring(res[i].completion or res[i].name) end
	return table.concat(t, " | ")
end

Run("Questie rows beside your own results", function()
	local quests, items, questie, npcs = {}, {}, {}, {}
	local function Lists()
		Use({
			{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows(quests) } },
			{ "items", { label = "Item", aliases = { "item" }, collect = Rows(items) } },
			{ "stored", HintList("alts and banks", "stored", {}) },
			{ "questie", HintList("Questie's quests", "questie", questie) },
			{ "npc", HintList("Questie's NPCs", "npc", npcs) },
		})
	end
	-- Steelsnap: a quest in your log named after the NPC; Questie has the NPC (and the quest)
	quests[1] = { name = "Steelsnap", questID = 1 }
	questie[1], npcs[1] = "Steelsnap", "Steelsnap"
	Lists()
	local r = UI:Search("steelsnap")
	check(r[1] and r[1].name == "Steelsnap" and r[1].kind == "quests", "Steelsnap: your quest first: " .. Show(r))
	check(r[2] and r[2].completion == "@npc steelsnap", "and the row for Questie's NPC of that name second: " .. Show(r))
	check(not Index(r, Offers("@questie steelsnap")), "no Questie quests row: the quest is in your log: " .. Show(r))
	-- nothing of yours: both rows, on top (quests, then NPCs)
	quests[1] = nil
	Lists()
	r = UI:Search("steelsnap")
	check(r[1] and r[1].completion == "@questie steelsnap" and r[2] and r[2].completion == "@npc steelsnap",
		"only Questie has it: a row for its quests and one for its NPCs, on top: " .. Show(r))
	-- an item named after the NPC: your item first, then both rows (neither is the same sort of thing)
	items[1] = { name = "Steelsnap's Claw", itemID = 5 }
	Lists()
	r = UI:Search("steelsnap")
	check(r[1] and r[1].name == "Steelsnap's Claw" and r[2] and r[2].completion == "@questie steelsnap"
		and r[3] and r[3].completion == "@npc steelsnap", "an item of that name: the item, then Questie's quests and NPCs: " .. Show(r))
	-- unchanged: the quest in your log and in Questie, no NPC of that name: nothing offered
	items[1] = nil
	quests[1], questie[1], npcs[1] = { name = "Wolves Across the Border", questID = 33 }, "Wolves Across the Border", "Edwin VanCleef"
	Lists()
	r = UI:Search("wolves across")
	check(r[1] and r[1].kind == "quests" and #r == 1, "your quest has it and no NPC does: nothing offered: " .. Show(r))
	-- an own result matching only in its text (not every word in the name): the rows stay on top
	quests[1] = { name = "A Lost Claw", questID = 34, text = "bring steelsnap's claw" }
	npcs[1] = "Steelsnap"
	Lists()
	r = UI:Search("steelsnap")
	check(r[1] and r[1].completion == "@npc steelsnap" and r[2] and r[2].name == "A Lost Claw", "a quest with it only in its text: the NPC row stays on top: " .. Show(r))
	check(UI.HINT_SAME and UI.HINT_SAME.questie.quests, "which list a kind of yours covers is declared (HINT_SAME)")
end)

Run("one or two matches in a big list: the rows themselves", function()
	local quests, questie, npcs = {}, {}, {}
	local function Lists()
		Use({
			{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows(quests) } },
			{ "questie", HintList("Questie's quests", "questie", questie, true) },
			{ "npc", HintList("Questie's NPCs", "npc", npcs, true) },
		})
	end
	npcs[1], npcs[2], npcs[3] = "Steelsnap", "Defias Pillager", "Defias Thug"
	Lists()
	local r = UI:Search("steelsnap")
	check(r[1] and r[1].kind == "npc" and r[1].name == "Steelsnap" and not Index(r, Offers("@npc steelsnap")),
		"one NPC has it: the NPC itself, no row to step through: " .. Show(r))
	r = UI:Search("defias")
	check(#r == 2 and r[1].kind == "npc" and r[2].kind == "npc" and not Index(r, Offers("@npc defias")),
		"two NPCs: both themselves: " .. Show(r))
	npcs[4] = "Defias Looter"
	Lists()
	r = UI:Search("defias")
	check(r[1] and r[1].completion == "@npc defias" and #r == 1, "three: the row offering @npc again: " .. Show(r))
	-- your quest of that name stays first; the NPC comes second, as its row did
	quests[1] = { name = "Steelsnap", questID = 1 }
	Lists()
	r = UI:Search("steelsnap")
	check(r[1] and r[1].kind == "quests" and r[2] and r[2].kind == "npc" and r[2].name == "Steelsnap",
		"Steelsnap: your quest first, the NPC itself second: " .. Show(r))
	-- a list that can't make the row (no hintRow): the hint row as before
	Use({ { "npc", HintList("Questie's NPCs", "npc", { "Steelsnap" }) } })
	r = UI:Search("steelsnap")
	check(r[1] and r[1].completion == "@npc steelsnap", "no hintRow: the hint row: " .. Show(r))
end)

Run("initials", function()
	local I = Fuzzy.initials
	check(I("scb", "Shadow Council Bracers") and I("zg", "Zul'Gurub") and I("kt", "Kel'Thuzad"), "initials: words and an apostrophe before a capital")
	check(I("hb", "Hero's Brand") and not I("hsb", "Hero's Brand"), "an apostrophe before a small letter stays in the word")
	check(I("be", "Bracers of the Eagle") and I("bote", "Bracers of the Eagle") and I("db", "The Defias Brotherhood"), "with and without of/the/a/an/and")
	check(I("th", "Tier 2 Helm") and I("sp", "Super-Potion") and not I("ab", "Abc"), "words starting with a digit skipped; hyphens split; one word has no initials")
	check(I("sco", "Shadow Council Orb Bracers") and not I("sc", "Shadow Council Orb Bracers"), "the start of the initials: 3+ letters only")
	check(I("sco", "Shadow Council Orb Bracers") < I("sco", "Shadow Council Orb"), "the start scores under the whole")
	local pos = {}
	I("zg", "Zul'Gurub", pos)
	check(pos[1] == 1 and pos[2] == 5, "positions of the initials: " .. tostring(pos[1]) .. "," .. tostring(pos[2]))
	check(I("be", "Bracers of the Eagle") < Fuzzy.score("be", "Bear Meat") and I("be", "Bracers of the Eagle") > Fuzzy.score("be", "Bright Cloak of Fire"),
		"initials rank under the letters as they are at a word's start, over scattered letters")

	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Scabbard of Bronze" }, { name = "Shadow Council Bracers" }, { name = "Zigzag Gloves" }, { name = "Zul'Gurub" },
		{ name = "Bear Meat" }, { name = "Bracers of the Eagle" }, { name = "Bright Cloak of Fire" }, { name = "Kel'Thuzad" },
	}) } } })
	local r = UI:Search("@srch scb")
	check(r[1] and r[1].name == "Shadow Council Bracers", "scb: Shadow Council Bracers first (over a scattered Scabbard of Bronze): " .. Show(r))
	r = UI:Search("@srch zg")
	check(r[1] and r[1].name == "Zul'Gurub", "zg: Zul'Gurub first: " .. Show(r))
	r = UI:Search("@srch kt")
	check(r[1] and r[1].name == "Kel'Thuzad", "kt: Kel'Thuzad: " .. Show(r))
	r = UI:Search("@srch be")
	local bear, eagle, bright = Index(r, Named("Bear Meat")), Index(r, Named("Bracers of the Eagle")), Index(r, Named("Bright Cloak of Fire"))
	check(bear and eagle and bright and bear < eagle and eagle < bright,
		"be: a name with the letters as they are first, then the initials, then scattered letters: " .. Show(r))
	r = UI:Search("@srch bote")
	check(r[1] and r[1].name == "Bracers of the Eagle", "bote: every word's initial: " .. Show(r))
	-- the highlight lights the initials
	UI:Open("@srch scb")
	local e = UI.Results()[1]
	local p = e and e._pos or {}
	check(p[1] and p[8] and p[16] and not p[2], "scb lights S, C and B")
	UI:Hide(); FlushAll()
end)

Run("place shorthand", function()
	check(ns.Shorthand and ns.Shorthand.brd and ns.Shorthand.dm[1] == "dire maul" and ns.Shorthand.vc[1] == "deadmines", "the shorthand table (DM is Dire Maul, VC the Deadmines)")
	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Ironfoe", text = "Emperor Dagran Thaurissan  Blackrock Depths" },
		{ name = "Swamp of Sorrows" }, { name = "Stormwind City" },
		{ name = "Tooth of Gnarr", text = "Overlord Wyrmthalak  Lower Blackrock Spire" },
		{ name = "Dal'Rend's Sacred Charge", text = "Warchief Rend Blackhand  Upper Blackrock Spire" },
		{ name = "Steel Bar" },
	}) } } })
	local r = UI:Search("@srch brd")
	check(r[1] and r[1].name == "Ironfoe" and #r == 1, "brd: loot from Blackrock Depths (by its text): " .. Show(r))
	r = UI:Search("@srch ubrs")
	check(r[1] and r[1].name == "Dal'Rend's Sacred Charge" and #r == 1, "ubrs: Upper Blackrock Spire: " .. Show(r))
	r = UI:Search("@srch lbrs")
	check(r[1] and r[1].name == "Tooth of Gnarr" and #r == 1, "lbrs: Lower Blackrock Spire: " .. Show(r))
	r = UI:Search("@srch sw")
	check(r[1] and r[1].name == "Stormwind City" and Index(r, Named("Swamp of Sorrows")), "sw: Stormwind City first, Swamp of Sorrows still there: " .. Show(r))
	-- an instance's shorthand beats its letters: rfk = Razorfen Kraul's loot before names whose initials are r f k
	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Rough Flask of Kings", text = "Rare drop  Wailing Caverns" }, { name = "Robe of the Faithful Knight" },
		{ name = "Corpsemaker", text = "Overlord Ramtusk  Razorfen Kraul" }, { name = "Sword of Fang Keeper" },
		{ name = "Shadowfang", text = "Rare drop  Shadowfang Keep" }, { name = "Rockfang Kilt" },
	}) } } })
	r = UI:Search("@srch rfk")
	check(r[1] and r[1].name == "Corpsemaker", "rfk: Razorfen Kraul's loot first: " .. Show(r))
	r = UI:Search("@srch sfk")
	check(r[1] and r[1].name == "Shadowfang", "sfk: Shadowfang Keep's loot first: " .. Show(r))
	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Ironfoe", text = "Emperor Dagran Thaurissan  Blackrock Depths" },
		{ name = "Swamp of Sorrows" }, { name = "Stormwind City" },
		{ name = "Tooth of Gnarr", text = "Overlord Wyrmthalak  Lower Blackrock Spire" },
		{ name = "Dal'Rend's Sacred Charge", text = "Warchief Rend Blackhand  Upper Blackrock Spire" },
		{ name = "Steel Bar" },
	}) } } })
	-- one letter more turns a word into a shorthand: the rows it matches aren't in the last scan's
	UI.lastScan = nil
	UI:SearchText("@srch br")
	r = UI:SearchText("@srch brd")
	check(r[1] and r[1].name == "Ironfoe", "br -> brd: the shorthand's rows are found (not narrowed from br's): " .. Show(r))
	-- and back: "st" (shorthand: the Sunken Temple, or "st" itself) -> "ste" finds rows st's matches didn't hold
	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Shattered Edge" }, { name = "Steel Bar" } }) } } })
	UI.lastScan = nil
	r = UI:SearchText("@srch st")
	check(not Index(r, Named("Shattered Edge")), "(st: not by scattered letters)")
	r = UI:SearchText("@srch ste")
	check(Index(r, Named("Shattered Edge")), "st -> ste: a row st's shorthand left out comes back: " .. Show(r))
	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Ironfoe", text = "Emperor Dagran Thaurissan  Blackrock Depths" },
		{ name = "Swamp of Sorrows" }, { name = "Stormwind City" },
		{ name = "Tooth of Gnarr", text = "Overlord Wyrmthalak  Lower Blackrock Spire" },
		{ name = "Dal'Rend's Sacred Charge", text = "Warchief Rend Blackhand  Upper Blackrock Spire" },
		{ name = "Steel Bar" },
	}) } } })
	-- the highlight lights the full name in the row's name
	UI:Open("@srch sw")
	local e = UI.Results()[1]
	local p = e and e._pos or {}
	check(e and e.name == "Stormwind City" and p[1] and p[9] and not p[10], "sw lights Stormwind")
	UI:Hide(); FlushAll()
end)

Run("close spellings", function()
	local D = Fuzzy.distance
	check(D("abcd", "abdc", 1, 4, 1) == 1 and D("abcd", "abce", 1, 4, 1) == 1 and D("abcd", "abd", 1, 3, 1) == 1 and D("abc", "abcd", 1, 4, 1) == 1,
		"one swap, change, drop or extra letter is one edit")
	check(D("abcd", "badc", 1, 4, 1) == nil and D("abcd", "badc", 1, 4, 2) == 2, "two edits: only within a limit of two")
	check(D("fire", "xx fire yy", 4, 7, 1) == 0, "measured on a word inside a text")

	Use({ { "srch", { label = "Test", aliases = { "srch" }, explicit = true, collect = Rows({
		{ name = "Hearthstone" }, { name = "Fireball" }, { name = "Fireblast" }, { name = "Steelsnap" }, { name = "Torch" },
		{ name = "Linen Cloth" },
	}) } } })
	local function top(q) local r = UI:Search("@srch " .. q) return r[1] and r[1].name, r end
	check(top("hearhtstone") == "Hearthstone", "hearhtstone: Hearthstone")
	check(UI.closeSpellings == true, "marked as close spellings")
	check(top("hearthstome") == "Hearthstone" and top("fireblal") == "Fireball" and top("steelsanp") == "Steelsnap", "hearthstome, fireblal, steelsanp")
	check(top("firebxyl") == "Fireball", "8+ letters: two edits")
	check(top("tprch") == "Torch" and top("tprxh") == nil, "4-7 letters: one edit, not two")
	check(top("trc") == "Torch" and top("tcx") == nil, "under 4 letters: no tolerance (trc is still a scattered match)")
	local n, r = top("fireblsat")
	check(n == "Fireblast", "the closest spelling first: " .. Show(r))
	check(top("linen clotj") == "Linen Cloth", "one word right, one close")
	check(top("fireball") == "Fireball" and not UI.closeSpellings, "an exact match isn't marked")
	-- the footer says so
	UI:Open("@srch fireblal")
	FlushAll()
	local s = UI.status and UI.status.text or ""
	check(s:find("close spellings", 1, true), "the footer says they're close spellings: " .. s)
	UI:SetQuery("@srch fireball"); FlushAll()
	s = UI.status and UI.status.text or ""
	check(not s:find("close spellings", 1, true), "and not for an exact match: " .. s)
	-- (0.50.7, review) a pick list after it ("q:"): not the search's footer
	UI:SetQuery("@srch fireblal"); FlushAll()
	UI:SetQuery("@srch fireblal @s", 17); FlushAll()
	s = UI.status and UI.status.text or ""
	check(UI.Results()[1] and UI.Results()[1].syntaxRow and not s:find("close spellings", 1, true), "@s picked after it: not said: " .. s)
	-- the close word is lit
	UI:SetQuery("@srch fireblal"); FlushAll()
	local e = UI.Results()[1]
	check(e and e._pos and e._pos[1] and e._pos[8], "the word it's close to is lit")
	UI:Hide(); FlushAll()
	-- spread over frames: it pauses with the search (always over budget here) and finishes
	local realClock = _G.debugprofilestop
	_G.debugprofilestop = function() return 0 end
	local co = coroutine.create(function() return UI:SearchText("@srch fireblal") end)
	local yields, ok, res = 0, nil, nil
	repeat
		UI.sliceUntil = -math.huge
		ok, res = coroutine.resume(co)
		UI.sliceUntil = nil
		if coroutine.status(co) ~= "dead" then yields = yields + 1 end
	until coroutine.status(co) == "dead" or yields > 50
	_G.debugprofilestop = realClock
	check(ok and yields > 1 and res and res[1] and res[1].name == "Fireball", "spread over frames, it pauses and finishes (" .. yields .. " pauses)")
end)

io.write("[advanced: typing @ or key: lists what fits; Shift+Tab cycles it]\n")
do
	local typeText, key = T.typeText, T.key
	ns.db.easyMode = false
	local function withShift(fn) local s = _G.IsShiftKeyDown; _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = s end
	UI:Open("")
	typeText("@")
	local r = UI.Results()
	-- (each kind by its name, its first alias, as .kinds writes it)
	local kinds, first = 0, nil
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		if not p.noKind then kinds = kinds + 1; first = first or ("@" .. (p.aliases[1] or id)) end -- (no @ names a noKind list)
	end
	check(#r == kinds and r[1].syntaxRow and r[1].name == first, "@: every kind to pick from: " .. #r .. "/" .. kinds .. " " .. tostring(r[1] and r[1].name))
	typeText("ite")
	r = UI.Results()
	check(r[1] and r[1].name == "@item" and r[1].syntaxRow, "@ite: narrowed to @item: " .. tostring(r[1] and r[1].name))
	key("ENTER")
	check(UI:IsShown() and UI.edit:GetText() == "@item ", "Enter: @item written with a space for the next word: '" .. UI.edit:GetText() .. "'")
	-- a filter's values
	UI:SetQuery("")
	typeText("rare q:")
	r = UI.Results()
	check(#r == #ns.Filters.QUALITIES and r[1].name == "q:poor", "q: every quality to pick from: " .. tostring(r[1] and r[1].name))
	-- Tab / Shift+Tab move through the list (the prompt stays as typed); Enter writes the one picked
	key("TAB"); key("TAB")
	check(UI.Results()[UI.Selected()].name == "q:uncommon" and UI.edit:GetText() == "rare q:", "Tab twice: the third picked, nothing written yet: " .. tostring(UI.Results()[UI.Selected()].name))
	withShift(function() key("TAB") end)
	check(UI.Results()[UI.Selected()].name == "q:common", "Shift+Tab: back up one")
	withShift(function() key("TAB") end); withShift(function() key("TAB") end)
	check(UI.Results()[UI.Selected()].name == "q:legendary", "Shift+Tab past the top: round to the bottom")
	check(UI:Suggestion() and UI:Completion() == "rare q:legendary ", "the faint completion is the one picked")
	key("TAB")
	check(UI.Results()[UI.Selected()].name == "q:poor", "Tab past the bottom: round to the top")
	key("TAB"); key("ENTER")
	check(UI.edit:GetText() == "rare q:common ", "Enter writes the one picked: '" .. UI.edit:GetText() .. "'")
	-- once picked, it stays: Tab doesn't change it
	key("TAB")
	check(UI.edit:GetText() == "rare q:common ", "picked: Tab leaves it: '" .. UI.edit:GetText() .. "'")
	-- a text set by code (Open) searches as before
	UI:Hide(); FlushAll()
	UI:Open("@items")
	check(not (UI.Results()[1] and UI.Results()[1].syntaxRow), "Open(\"@items\"): not the pick list")
	UI:Hide(); FlushAll()
	-- 0.47.7 (the player: "@questlog is:" offered online, ready, equippable...): only the values that judge a list typed
	UI:Open("")
	local function Picks(text)
		UI:SetQuery("")
		typeText(text)
		local t = {}
		for _, e in ipairs(UI.Results()) do if e.syntaxRow then t[#t + 1] = e.name:gsub("^%a+:", "") end end
		return table.concat(t, " ")
	end
	local quest = Picks("@questlog is:")
	-- (is:upgrade: a quest whose reward is an upgrade, 0.51.15)
	check(quest == "complete upgrade grey leftbehind drop", "@questlog is: only the quest log's: " .. quest)
	check(Picks("@achievement is:") == "done todo", "@achievement is: done todo: " .. Picks("@achievement is:"))
	local item = Picks("@item is:")
	check(item:find("usable", 1, true) and item:find("equippable", 1, true) and item:find("boe", 1, true)
		and not item:find("online", 1, true) and not item:find("leftbehind", 1, true), "@item is: the items': " .. item)
	check(Picks("@group quests is:") == "shareable together", "@group quests is: the party quests': " .. Picks("@group quests is:"))
	check(Picks("@group is:"):find("^online offline dead tank healer dps far inrange unbuffed$"), "@group is: " .. Picks("@group is:"))
	check(Picks("@spell @currency is:") == "ready passive unplaced known capped", "two lists: both lists' values: " .. Picks("@spell @currency is:"))
	check(#Picks("is:"):gsub("%S+", "x"):gsub(" ", "") == #ns.Filters.VALUES.is, "no list typed: every value")
	check(Picks("@questlog stat:") == "" and Picks("@npc trainer:"):find("^class classes"), "a key that judges no list typed: none")
	check(Picks("@questlog is:co") == "complete", "narrowed by what's typed: " .. Picks("@questlog is:co"))
	-- Tab completes from them too ("co": complete for the quest log; cod or complete with no list typed)
	UI:SetQuery("")
	typeText("@questlog is:co")
	local qc = ns.Filters.ValuesFor("is", "@questlog ")
	local fromAll = 0
	for _, v in ipairs(ns.Filters.VALUES.is) do if v:sub(1, 2) == "co" then fromAll = fromAll + 1 end end
	check(#qc == 5 and fromAll > 1, "the quest log's values, several from all of them")
	-- every value is said to judge some list, and every list named is one (a typo would hide a value everywhere)
	local known = { loot = true, questie = true, npc = true, attune = true, training = true } -- (AtlasLoot's, Questie's, Attune's and What's Training's lists: not loaded in every run)
	for _, id in ipairs(ns.providerOrder) do known[id] = true end
	local undeclared, strange = {}, {}
	for key, values in pairs(ns.Filters.VALUES) do
		local applies = ns.Filters.APPLIES[key]
		if applies then
			for _, v in ipairs(values) do
				local where = applies[v] or applies["*"]
				if not where then undeclared[#undeclared + 1] = key .. ":" .. v end
				for _, k in ipairs(where or {}) do if not known[k] then strange[#strange + 1] = key .. ":" .. v .. " -> " .. k end end
			end
		end
	end
	check(#undeclared == 0 and #strange == 0, "every value judges a list that exists: " .. table.concat(undeclared, ", ") .. " " .. table.concat(strange, ", "))
	-- (0.50.5, the player: WoW Forever has no warband bank) in: doesn't offer it
	local inValues = table.concat(ns.Filters.ValuesFor("in", "") or {}, ",")
	check(not inValues:find("warband", 1, true) and inValues:find("bank", 1, true), "in: offers no warband: " .. inValues)
	UI:Hide(); FlushAll()
	-- Simple mode: an @ typed runs in Advanced mode this once (0.54.1): its kinds list
	ns.db.easyMode = true
	UI:Open("")
	typeText("@")
	check(UI.Results()[1] and UI.Results()[1].syntaxRow and not ns.Easy.On(), "Simple mode: @ typed: the kinds list (Advanced this once)")
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
end


io.write("[review 0.48.6: the search engine]\n")
do
	local E, F, Scan, P = ns.Easy, ns.Filters, UI._Scan, ns.Pipes
	local IS = F._.IS
	IS.zzs = function(e) return e.zz == true end
	IS.zzr = function(e) return e.zzr == true end
	E.WORDS.zzstrict, E.HARD_WORDS.zzstrict = "is:zzs", true
	E.WORDS.zzrole, E.HARD_WORDS.zzrole, E.ROLE_WORDS.zzrole = "is:zzr", true, true
	-- a strict everyday word is an everyday word: "my zzstrict" drops its "my" as the soft ones do
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Alpha Stone", itemID = 1, zz = true },
			{ name = "Beta Stone", itemID = 2 }, { name = "Hearthstone", itemID = 6948 } }) } },
		{ "spells", { label = "Spell", aliases = { "spell" }, collect = Rows({ { name = "Stone Skin", zz = true }, { name = "World Map Spell" } }) } },
		{ "panels", { label = "Panel", aliases = { "panel" }, collect = Rows({ { name = "World Map" } }) } },
		{ "npc", HintList("Questie's NPCs", "npc", { "Ann Zzrole", "Bob Smith" }, true) } })
	ns.db.easyMode = true
	UI.category, UI.categoryAuto = nil, nil
	local a, b = UI:Search("zzstrict"), UI:Search("my zzstrict")
	check(#a > 0 and a[1].catId and #b == #a and b[1].catId, "\"my zzstrict\" as \"zzstrict\": " .. #a .. " / " .. #b .. " " .. tostring(b[1] and b[1].name))
	-- a strict role word: Questie's NPCs looked up by it in the overview; "nearest" with it keeps to friendly NPCs
	local r = UI:Search("zzrole")
	local npcs = false
	for _, e in ipairs(r) do if e.catId == "npcs" then npcs = true end end
	check(npcs or UI.category == "npcs", "a strict role word: the NPCs it names found: " .. tostring(r[1] and r[1].name))
	check(Scan.RoleFriendly(nil, { "zzrole" }) ~= nil and Scan.RoleFriendly({ "zzrole" }) ~= nil and Scan.RoleFriendly({ "stone" }) == nil,
		"a role word, soft or strict, keeps to friendly NPCs")
	local I = ns.Integrations
	local hereWas = I.Here
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	local early, here, friendly = Scan.NearestStart({ "ann" }, nil, nil, { "zzrole" })
	I.Here = hereWas
	check(not early and here and friendly ~= nil, "\"nearest zzrole\": faction:friendly as for \"nearest innkeeper\"")
	local nearWas, strictGot = Scan.NearestStart, nil
	Scan.NearestStart = function(...) strictGot = select(4, ...) return nearWas(...) end
	UI.category, UI.categoryAuto = nil, nil
	UI:Search("nearest zzrole")
	Scan.NearestStart = nearWas
	check(strictGot and strictGot[1] == "zzrole", "the search hands \"nearest\" its strict words: " .. tostring(strictGot and strictGot[1]))
	-- close spellings with no category picked
	UI.category, UI.categoryAuto = nil, nil
	r = UI:Search("hearhtstone")
	local found = false
	for _, e in ipairs(r) do if e.name == "Hearthstone" or (e.catId and (e.detail or ""):find("Hearthstone", 1, true)) then found = true end end
	check(found and UI.closeSpellings, "Simple mode, no category: close spellings too: " .. tostring(r[1] and r[1].name))
	-- the category picked has nothing: the categories that do, with the clear winner on top as with none picked
	UI.category, UI.categoryAuto = "items", nil
	r = UI:Search("world map")
	check(r[1] and r[1].name == "World Map" and UI.overviewWinner == r[1], "nothing in Items: the categories, World Map on top: " .. tostring(r[1] and r[1].name))
	UI.category, UI.categoryAuto = nil, nil
	ns.db.easyMode = false
	-- a list made from another (@gear from @item) is stale while that one is: narrowing doesn't keep what's gone
	local items = { { name = "Sword of A", itemID = 1 }, { name = "Swordbreaker", itemID = 2 } }
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = function()
			local out = {}
			for i, x in ipairs(items) do out[i] = { name = x.name, itemID = x.itemID, key = x.itemID } end
			return out
		end } },
		{ "gear", { label = "Gear", aliases = { "gear" }, explicit = true, follows = "items", collect = function()
			local out = {}
			for _, e in ipairs(ns:GetEntries(ns.providers.items)) do out[#out + 1] = { name = e.name, key = e.key, itemID = e.itemID } end
			return out
		end } } })
	UI:Search("@gear swo")
	items = { { name = "Swordbreaker", itemID = 2 } }
	ns.providers.items._dirty = true
	r = UI:Search("@gear swor")
	local names = {}
	for _, e in ipairs(r) do names[#names + 1] = e.name end
	check(#r == 1 and r[1].name == "Swordbreaker", "the sword sold: gone from @gear's narrowed search: " .. table.concat(names, ", "))
	-- items the client hasn't loaded: at most F.ITEM_ASK asked per search, and the search runs again (F.loading)
	local gii, cached = C_Item.GetItemInfo, C_Item.IsItemDataCachedByID
	local asked = 0
	C_Item.GetItemInfo = function() asked = asked + 1 return nil end
	C_Item.IsItemDataCachedByID = function() return false end
	local loot = {}
	for i = 1, 300 do loot[i] = { name = "Blade " .. i, itemID = 50000 + i } end
	Use({ { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows(loot) } } })
	UI:Search("@loot blade q:epic")
	local first = asked
	UI:Search("@loot blade 1 q:epic") -- (a letter more: a narrowing of the last search, which judged only some)
	C_Item.GetItemInfo, C_Item.IsItemDataCachedByID = gii, cached
	check(first <= F.ITEM_ASK and asked - first > 0 and asked - first <= F.ITEM_ASK and F.loading, "uncached items: a few asked per search, not 300: " .. first .. ", " .. (asked - first))
	-- a chain's views of one row, found the same way: one
	local npc = { kind = "npc", key = 5, name = "Trader" }
	local v1 = setmetatable({ pipeHow = "sold by", detail = "a" }, { __index = npc })
	local v2 = setmetatable({ pipeHow = "sold by", detail = "b" }, { __index = npc })
	local v3 = setmetatable({ pipeHow = "dropped by" }, { __index = npc })
	check(P.Id(v1) == P.Id(v2) and P.Id(v1) ~= P.Id(v3), "a chain: the same NPC found the same way is one row")
	Restore()
	-- the plan question reads your professions only when a plan word is typed (it's asked every keystroke)
	local pp, calls = ns.Professions.PlayerProfessions, 0
	ns.Professions.PlayerProfessions = function(...) calls = calls + 1 return pp(...) end
	ns.Plan.Question("hearth"); ns.Plan.Question("hearthstone")
	local noCue = calls
	ns.Plan.Question("blacksmithing plan")
	ns.Professions.PlayerProfessions = pp
	check(noCue == 0 and calls == 1, "the plan question: professions read only with a plan word: " .. noCue .. " / " .. calls)
	-- the prompt's colours: a word's parse remembered (not every keystroke)
	local parse, parses = F.Parse, 0
	F.Parse = function(...) parses = parses + 1 return parse(...) end
	UI:SyntaxSegments("q:rare lvl:20 stone")
	local once = parses
	UI:SyntaxSegments("q:rare lvl:20 stone")
	F.Parse = parse
	check(parses == once, "the prompt's colours: the same words not parsed again: " .. once .. " then " .. (parses - once))
	-- what was picked of a list is looked up once for the list, not per row
	local many = {}
	ns:RegisterProvider("zzfreq", { label = "Zz", aliases = { "zzfreq" }, explicit = true, collect = function() return many end })
	local meta = ns:CompactMeta(ns.providers.zzfreq, {})
	for i = 1, 300 do many[i] = setmetatable({ _compact = true, key = i, name = "Stone " .. i }, meta) end
	local fw = { recent = ns.db.recent, freq = ns.db.freq }
	ns.db.recent, ns.db.freq = {}, {}
	ns.freqKinds = nil
	ns:Bump("zzfreq:7")
	local fk, asks = ns.FreqKind, 0
	ns.FreqKind = function(...) asks = asks + 1 return fk(...) end
	UI.lastScan, UI.lastOverview = nil, nil
	r = UI:Search("@zzfreq stone")
	ns.FreqKind = fk
	ns.db.recent, ns.db.freq = fw.recent, fw.freq
	ns.freqKinds = nil
	check(asks <= 3 and r[1] and r[1].key == 7, "a list's recent picks looked up once, the pick still first: " .. asks .. " asks")
	ns.providers.zzfreq = nil
	for i, x in ipairs(ns.providerOrder) do if x == "zzfreq" then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()
	IS.zzs, IS.zzr = nil, nil
	E.WORDS.zzstrict, E.HARD_WORDS.zzstrict = nil, nil
	E.WORDS.zzrole, E.HARD_WORDS.zzrole, E.ROLE_WORDS.zzrole = nil, nil, nil
	UI.lastScan, UI.lastOverview = nil, nil
end

-- (0.49.2, review C3) "reset" with other words is the lockouts' question only when they name a lockout or an instance
-- ("reset my keybinds" listed the lockouts); time words are question words ("what resets this week" said "No lockout
-- has that", and Alt+` wrote "@lockout week")
do
	io.write("[search: reset questions]\n")
	local LK, p = ns.Lockouts, ns.providers.lockouts
	local save = { entries = p._entries, dirty = p._dirty }
	local ok, err = pcall(function()
		p._entries, p._dirty = {}, false
		check(LK.Question("reset my keybinds") == nil and LK.Question("how do i reset my talents") == nil and LK.Question("reset my ui") == nil
			and LK.Question("when does my hearthstone reset") == nil and LK.Question("reset all my settings") == nil,
			"reset with words that name no lockout nor instance: a search")
		check(LK.Question("when does mc reset") and LK.Question("when does molten core reset") and LK.Question("when does strat reset"),
			"nothing saved: an instance's name or shorthand still asks")
		p._entries = { { name = "Molten Core", kind = "lockouts", isRaid = true, mine = true, _lname = "molten core",
			_ltext = "molten core 40 player resets in 3 d" }, { name = "Wailing Caverns", kind = "lockouts", mine = true,
			_lname = "wailing caverns", _ltext = "wailing caverns" } }
		local function Words(text) local q = LK.Question(text) return q and table.concat(q.words, ",") end
		check(Words("what resets this week") == "" and Words("raid lockouts this week") == "" and Words("when does mc reset tomorrow") == "mc"
			and Words("am i saved this week") == "", "time words are question words: " .. tostring(Words("what resets this week"))
			.. " / " .. tostring(Words("raid lockouts this week")) .. " / " .. tostring(Words("when does mc reset tomorrow")))
		local rows = LK.Answer(LK.Question("when does mc reset tomorrow"))
		check(#rows == 1 and rows[1].name == "Molten Core", "when does mc reset tomorrow: Molten Core")
		check(ns.Easy.QuestionToAdvanced("what resets this week") == "@lockout ", "Alt+`: @lockout: "
			.. tostring(ns.Easy.QuestionToAdvanced("what resets this week")))
	end)
	p._entries, p._dirty = save.entries, save.dirty
	check(ok, "the reset questions block ran: " .. tostring(err))
end

-- (0.49.2, review C6) words besides the auctions' own need what auctions do (sold, selling, listed) or "auctions" itself:
-- "where is the ah", "show me the auction house" said "No auction has that"; "what's up" listed your auctions
do
	io.write("[search: auction questions]\n")
	local Q = ns.Auctions.Question
	check(Q("where is the ah") == nil and Q("where is the auction house") == nil and Q("show me the auction house") == nil
		and Q("the auction house") == nil and Q("what's up") == nil, "where is the ah / the auction house / what's up: searches")
	check(Q("my auctions") and Q("what am i selling") and Q("my auctions sold linen") and Q("my auctions on bob") and Q("auction sold")
		and Q("my ah") and Q("what am i selling") and Q("is my ah selling linen"), "your auctions still asked")
	local was = ns.db.easyMode
	ns.db.easyMode = true
	UI.category, UI.categoryAuto = nil, nil
	UI:Search("where is the ah")
	local note = UI.answerNote
	ns.db.easyMode = was
	UI.category, UI.categoryAuto = nil, nil
	check(note == nil, "Simple: where is the ah isn't your auctions: " .. tostring(note))
end

-- (0.49.2, review C13) the calculator's functions answer on their own ("sqrt(2)", "max(3, 5)": the header lists them, they
-- gave nothing); a plain number still doesn't (a search word: "20")
do
	io.write("[search: calculator functions]\n")
	local C = ns.Calc
	check(C.Evaluate("sqrt(2)") == "1.414214" and C.Evaluate("floor(3.7)") == "3" and C.Evaluate("max(3, 5)") == "5"
		and C.Evaluate("abs(-3)") == "3", "sqrt(2), floor(3.7), max(3, 5), abs(-3): " .. tostring(C.Evaluate("sqrt(2)")))
	check(C.Evaluate("20") == nil and C.Evaluate("-5") == nil and C.Evaluate("=20") == "20", "a plain number: no answer (=20 is one)")
	-- (review, 0.53.6) a number with a trailing point is a number; money rounded to nothing has no sign
	check(C.Evaluate("3.*2") == "6" and C.Evaluate("10. + 5") == "15" and C.Evaluate(".5*2") == "1",
		"3.*2, 10. + 5, .5*2: " .. tostring(C.Evaluate("3.*2")) .. ", " .. tostring(C.Evaluate("10. + 5")))
	check(C.Evaluate("=-0.3c") == "0c", "=-0.3c: 0c, not -0c: " .. tostring(C.Evaluate("=-0.3c")))
	check(C.Evaluate("3 . 4") == nil, "a point alone is no number")
	local res = UI:Search("sqrt(2)")
	check(res[1] and res[1].kind == "calc" and res[1].name == "= 1.414214", "sqrt(2) in the prompt: the answer on top")
end

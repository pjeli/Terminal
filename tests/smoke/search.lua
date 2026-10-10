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
	-- Simple mode: none of it
	ns.db.easyMode = true
	UI:Open("")
	typeText("@")
	check(not (UI.Results()[1] and UI.Results()[1].syntaxRow), "Simple mode: no kinds list")
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
end

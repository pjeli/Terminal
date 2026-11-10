-- Easy mode: categories picked from the results, everyday words, Questie's rows among the results, the footer's verbs,
-- Tab through categories. ("easy" in the code is Simple mode; "hard" is Advanced.) Part 2, easy_2.lua: action words,
-- nearest, the examples, the row menu, Advanced syntax refused, .advanced and .simple.
local T = ...
local ns, UI, check, key, FlushAll, log, logHas, S = T.ns, T.UI, T.check, T.key, T.FlushAll, T.log, T.logHas, T.S
local E = ns.Easy

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
local function BigList(label, alias, names)
	return { label = label, hintLabel = label, aliases = { alias }, explicit = true, collect = Rows((function()
			local t = {}
			for i, n in ipairs(names) do t[i] = { name = n } end
			return t
		end)()),
		hintFind = function(_, tokens)
			local first, count, ids = nil, 0, {}
			for i, n in ipairs(names) do
				local ln, all = n:lower(), true
				for _, tk in ipairs(tokens) do if not ln:find(tk, 1, true) then all = false end end
				if all then
					count = count + 1; first = first or n
					if #ids < 3 then ids[#ids + 1] = i end
				end
			end
			return first, count, ids
		end,
		hintRow = function(_, id) return { name = names[id], key = id, kind = alias } end }
end
local function Has(res, name)
	for i, e in ipairs(res) do if e.name == name then return i end end
end
local function Kinds(res)
	local t = {}
	for _, e in ipairs(res) do t[e.kind or "?"] = true end
	return t
end
local function Show(res)
	local t = {}
	for i = 1, math.min(#res, 8) do t[i] = tostring(res[i].completion or res[i].name) end
	return table.concat(t, " | ")
end
local function Run(title, fn)
	io.write("[easy: " .. title .. "]\n")
	local ok, err = pcall(fn)
	Restore()
	UI.category = nil
	ns.db.easyMode = false
	UI:EasyChanged()
	UI:Hide(); FlushAll()
	if not ok then check(false, title .. ": " .. tostring(err)) end
end

local function Lists()
	Use({
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({
			{ name = "Rare Sword", quality = 1, itemID = 1 },
			{ name = "Blade of Ages", quality = 3, itemID = 2 },
			{ name = "Shiny Sword", quality = 3, itemID = 3 },
			{ name = "Rusty Sword", quality = 0, itemID = 4 },
		}) } },
		{ "spells", { label = "Spell", aliases = { "spell" }, collect = Rows({ { name = "Sword Specialization" }, { name = "Fireball" } }) } },
		{ "quests", { label = "Quest", aliases = { "questlog" }, collect = Rows({ { name = "The Sword of Kings", questID = 9 } }) } },
		{ "keybinds", { label = "Keybinding", aliases = { "keybind" }, collect = Rows({ { name = "Sheathe Sword" } }) } },
		{ "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({ { name = "Sword of Omen", itemID = 50 }, { name = "Thunderfury" } }) } },
		{ "npc", BigList("Questie's NPCs", "npc", { "Sword Master Thorn", "Swordsmith Ivan", "Old Sword Guy", "Sword Dummy" }) },
		{ "questie", BigList("Questie's quests", "questie", { "The Sword of Kings", "Sword Practice" }) },
		{ "slash", { label = "Slash", aliases = { "slash" }, explicit = true, collect = Rows({
			{ name = "/dance", emote = "DANCE", text = "emote dance" }, { name = "/swordplay", text = "swordplay" },
			{ name = "/reload", text = "reload" } }) } },
		{ "cvars", { label = "CVar", aliases = { "cvar" }, explicit = true, collect = Rows({ { name = "cameraDistanceMaxZoomFactor" } }) } },
	})
end
-- typed, then the category picked from the rows (as a player does it)
local function In(cat, query)
	UI:Open(query)
	UI:SetCategory(cat)
	return UI.Results()
end

Run("on by default: nothing listed until something is typed", function()
	ns.db.easyMode = nil
	check(E.On(), "no choice saved: easy mode")
	E.Set(true)
	Lists()
	local hardY
	ns.db.easyMode = false; UI:Open(""); hardY = UI.rows[1].baseY; UI:Hide(); FlushAll()
	E.Set(true)
	UI:Open("")
	check(UI.rows[1].baseY == hardY, "no chips: the rows sit where they do in hard mode")
	check(UI.category == nil, "opens with no category picked")
	local res = UI.Results()
	check(#res == 0 and UI.bare, "nothing typed: nothing listed, just the prompt: " .. Show(res))
	check(not UI.status:IsShown() and not UI.hints:IsShown(), "no footer")
	-- the prompt's background stops 4 px above the header's end; the bare frame keeps its bottom border clear of it
	local hh = -UI.rows[1].baseY
	local inset = ns.Theme.Get().frame == "classic" and 4 or 1
	check(_G.TerminalFrame.h == hh - 4 + inset, "bare: the bottom border shows under the prompt: " .. tostring(_G.TerminalFrame.h) .. " (header " .. hh .. ")")
	check(UI:Suggestion() == nil, "(no completion)")
	UI:SetQuery("sword")
	check(not UI.bare and UI.status:IsShown(), "typed: the rows and the footer come")
	UI:SetQuery("")
	check(UI.bare, "cleared: just the prompt again")
	UI:SetQuery("zzqqxx")
	check(not UI.bare and not UI.noFoot and UI.status:IsShown() and UI.status:GetText():find("keep typing", 1, true), "nothing found: the line, and the footer stays (0.43.4)")
	check(_G.TerminalFrame.h < 100, "(as tall as the prompt and the line): " .. tostring(_G.TerminalFrame.h))
	UI:SetQuery("")
	ns.db.easyMode = false; UI:EasyChanged()
	check(UI.bare and not UI.status:IsShown(), "Advanced mode too: just the prompt")
	UI:SetQuery("zzzqqq")
	check(not UI.bare and UI.status:IsShown(), "Advanced, typed and nothing found: the footer says so")
	E.Set(true)
end)

Run("typing lists the categories that have it", function()
	E.Set(true)
	Lists()
	-- (the mock measures colour codes as letters: a wide terminal so the footer's hints all fit)
	local t = ns.Theme.Get()
	local saveW = t.width
	t.width = 1100
	UI:Open("sword")
	local res = UI.Results()
	local cats = {}
	for _, e in ipairs(res) do cats[#cats + 1] = tostring(e.catId) end
	local joined = table.concat(cats, ",")
	check(res[1] and res[1].catId, "one row per category: " .. Show(res))
	check(joined:find("items", 1, true) and joined:find("quests", 1, true) and joined:find("npcs", 1, true) and joined:find("loot", 1, true)
		and joined:find("settings", 1, true) and joined:find("commands", 1, true), "every category with a sword: " .. joined)
	check(not joined:find("emotes", 1, true), "no emote has sword: no Emotes row")
	local npcs
	for _, e in ipairs(res) do if e.catId == "npcs" then npcs = e end end
	check(npcs and npcs.detail:find("+3 more", 1, true), "NPCs counted by Questie's name index: " .. tostring(npcs and npcs.detail))
	check((UI.status:GetText() or ""):find("pick one", 1, true), "the footer: pick one: " .. tostring(UI.status:GetText()))
	local h = UI.hints:GetText() or ""
	check(h:find("look in", 1, true) and h:find("pick", 1, true), "Enter: look in it; Tab picks: " .. h)
	-- Enter on a category row picks it, keeps the words, the terminal stays open
	local at
	for i, e in ipairs(res) do if e.catId == "items" then at = i end end
	UI:Activate(at)
	check(UI:IsShown() and UI.category == "items" and UI.edit:GetText() == "sword", "Enter picks Items, the words stay")
	res = UI.Results()
	check(res[1] and Kinds(res).items and not Kinds(res).loot and not Kinds(res).category, "Items: only your own, no AtlasLoot: " .. Show(res))
	check((UI.status:GetText() or ""):find("Items", 1, true), "the footer names the category: " .. tostring(UI.status:GetText()))
	check((UI.hints:GetText() or ""):find("Shift+Left|r all categories", 1, true), "Shift+Left (or Tab): back to all categories: " .. tostring(UI.hints:GetText()))
	-- (0.45.17) Shift+Left, the back key: back to all categories, as Tab
	local s4 = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	key("LEFT")
	_G.IsShiftKeyDown = s4
	UI.frame.scripts.OnKeyUp(UI.frame, "LEFT")
	check(UI.category == nil and UI.Results()[1] and UI.Results()[1].catId and UI.edit:GetText() == "sword", "Shift+Left in a category: back to all of them")
	UI:Activate(at)
	check(UI.category == "items", "(picked again)")
	-- (0.45.20) Tab, one rule in every mode: in a category it goes down the list (back is Shift+Left's), Shift+Tab up;
	-- Tab on a category row picks it
	local nIn = #UI.Results()
	key("TAB")
	check(UI.category == "items" and nIn >= 2 and UI.Selected() == 2, "Tab in a category: the next result, the category kept: " .. tostring(UI.category) .. " " .. UI.Selected())
	_G.IsShiftKeyDown = function() return true end
	key("TAB")
	_G.IsShiftKeyDown = s4
	check(UI.category == "items" and UI.Selected() == 1, "Shift+Tab: the previous one")
	UI:SetCategory(nil)
	check(UI.category == nil and UI.Results()[1].catId, "(the categories again)")
	key("TAB")
	check(UI.category ~= nil, "Tab on a category row: picks it: " .. tostring(UI.category))
	-- typing on in a category keeps it; words that aren't in it: the categories again
	UI:SetCategory("loot")
	UI:SetQuery("sword of omen")
	check(UI.category == "loot" and UI.Results()[1].name == "Sword of Omen", "typing on keeps the category")
	UI:SetQuery("sword practice")
	-- (Loot let go: the categories that have them, or the one that does, opened by itself)
	check(UI.category ~= "loot" and (UI.Results()[1].catId == "quests" or (UI.category == "quests" and UI.categoryAuto)),
		"words not in it: the categories that have them: " .. Show(UI.Results()) .. " cat=" .. tostring(UI.category))
	-- clearing the prompt lets the category go
	UI:SetCategory("quests")
	UI:SetQuery("")
	check(UI.category == nil and #UI.Results() == 0, "prompt cleared: no category, nothing listed")
	-- nothing anywhere
	UI:SetQuery("zzzzqqq")
	res = UI.Results()
	check(#res == 1 and res[1].noActivate, "nothing has it: says so: " .. Show(res))
	-- a new open starts with none picked
	UI:SetQuery("sword"); UI:SetCategory("spells")
	UI:Hide(); FlushAll()
	UI:Open("sword")
	check(UI.category == nil, "opened again: none picked")
	t.width = saveW
end)

Run("every list is in a category: emotes, commands, settings", function()
	E.Set(true)
	Lists()
	UI:Open("dance")
	local res = UI.Results()
	-- (0.48.4: named exactly what was typed, it's the clear winner, above the categories)
	check(res[1] and res[1].name == "/dance" and UI.overviewWinner == res[1] and res[2] and res[2].catId == "emotes"
		and res[2].detail:find("/dance", 1, true), "dance: /dance itself on top, then Emotes: " .. Show(res))
	res = In("emotes", "dance")
	check(#res == 1 and res[1].name == "/dance" and res[1].emote, "in Emotes: /dance: " .. Show(res))
	local h = UI.hints:GetText() or ""
	check(h:find("do it", 1, true), "Enter: do it: " .. h)
	res = In("commands", "reload")
	check(#res == 1 and res[1].name == "/reload", "Commands: /reload, no emotes: " .. Show(res))
	UI:Open("camera zoom")
	res = UI.Results()
	check(res[1] and res[1].name == "cameraDistanceMaxZoomFactor" and UI.category == "settings" and UI.categoryAuto,
		"camera zoom: only Settings has it: straight to the setting: " .. Show(res))
	res = In("npcs", "sword")
	check(#res == 4 and Kinds(res).npc and not Kinds(res).items, "NPCs: every matching NPC, nothing else: " .. Show(res))
	res = In("settings", "sword")
	check(Has(res, "Sheathe Sword"), "Settings: the keybinding: " .. Show(res))
	-- (a category's old id picks the one that took it over: a pick kept from before, another addon's simpleCategory)
	for old, now in pairs({ game = "settings", console = "settings", bags = "items", alts = "stored", slash = "commands",
		lootlog = "recent", combat = "recent" }) do
		check(E.BY_ID[old] and E.BY_ID[old].id == now, old .. " is " .. now .. " now")
	end
	UI:SetCategory(nil); UI:SetCategory("game")
	check(UI.category == "settings" and Has(UI.Results(), "Sheathe Sword"), "picking an old id picks its new category: " .. tostring(UI.category))
	res = In("quests", "sword")
	check(Has(res, "The Sword of Kings") and Has(res, "Sword Practice") and not Kinds(res).items, "Quests: yours and Questie's: " .. Show(res))
end)

Run("category rows say what they hold; a clear winner goes on top (0.48.4)", function()
	E.Set(true)
	Lists()
	ns:RegisterProvider("toys", { label = "Toy", aliases = { "toy" }, collect = Rows({ { name = "Sword Dummy Toy" },
		{ name = "Shiny Sword" }, { name = "Old Map" }, { name = "Old Map" }, { name = "Old Map" }, { name = "Gold Map" },
		{ name = "Gold Map" }, { name = "The Old Lantern" } }) })
	ns:RegisterProvider("gameoptions", { label = "Game option", aliases = { "option" }, collect = Rows({ { name = "Old Map Fading" },
		{ name = "Gold Map Shade" }, { name = "Old Lantern Glow" } }) })
	local t = ns.Theme.Get()
	local saveW = t.width
	t.width = 1100
	UI:Open("sword")
	local res = UI.Results()
	local function Row(id) for _, e in ipairs(res) do if e.catId == id then return e end end end
	local set, q, npcs = Row("settings"), Row("quests"), Row("npcs")
	check(set and set.labelNote and set.labelNote:find("Keybinding", 1, true) and not set.labelNote:find("Game option", 1, true),
		"Settings: which of its lists had the words (the keybinding, not the game options): " .. tostring(set and set.labelNote))
	check(q and q.labelNote and q.labelNote:find("Quest", 1, true) and q.labelNote:find("Questie", 1, true),
		"Quests: both lists had them: " .. tostring(q and q.labelNote))
	check(npcs and npcs.labelNote == nil, "a category of one list: nothing to say")
	local drawn
	for i = 1, #UI.rows do
		local r = UI.rows[i]
		local txt = r:IsShown() and r.label:GetText() or ""
		if txt:find("Keybinding", 1, true) then drawn = txt end
	end
	check(drawn and drawn:find("Settings", 1, true), "drawn after the category's name: " .. tostring(drawn))
	check(UI.overviewWinner == nil and res[1].catId, "nothing is named \"sword\": no winner")
	-- the only NPC named that (Questie's name index), another category having the words too
	UI:SetQuery("sword dummy")
	res = UI.Results()
	check(res[1] and res[1].name == "Sword Dummy" and res[1].kind == "npc" and res[2] and res[2].catId and UI.overviewWinner == res[1],
		"the NPC named exactly that, on top of the categories: " .. Show(res))
	check((UI.status:GetText() or ""):find("best match first", 1, true), "the footer says so: " .. tostring(UI.status:GetText()))
	-- named that in two categories: the categories tell them apart
	UI:SetQuery("shiny sword")
	res = UI.Results()
	check(res[1] and res[1].catId and UI.overviewWinner == nil, "Shiny Sword in Items and in Collections: no winner: " .. Show(res))
	-- two named that in one category: one thing (the first); three: no clear winner
	UI:SetQuery("gold map")
	res = UI.Results()
	check(res[1] and res[1].name == "Gold Map" and res[2] and res[2].catId, "two Gold Maps, one category: the winner: " .. Show(res))
	UI:SetQuery("old map")
	res = UI.Results()
	check(res[1] and res[1].catId and UI.overviewWinner == nil, "three Old Maps: the category to pick: " .. Show(res))
	-- a leading "the" isn't needed (nor a command's "/": /dance above)
	UI:SetQuery("old lantern")
	res = UI.Results()
	check(res[1] and res[1].name == "The Old Lantern" and UI.overviewWinner == res[1], "\"old lantern\": The Old Lantern: " .. Show(res))
	UI:SetQuery("lantern")
	check(UI.overviewWinner == nil, "only part of its name: no winner")
	-- one category only: opened for you, as before (no winner row then)
	UI:SetQuery("sheathe sword")
	check(UI.category == "settings" and UI.categoryAuto and UI.overviewWinner == nil, "one category: straight to it")
	t.width = saveW
end)

Run("the categories' order: a job's title, more matches, the player's picks (0.56.11)", function()
	E.Set(true)
	ns.db.catPicks = nil
	-- Questie's NPCs with their titles in the index line ("kyra boucher <reagent vendor>"), as Questie's hintFind hands back
	local npcs = { { "Kyra Boucher", "reagent vendor" }, { "Hal McAllister", "reagent vendor" }, { "Tamar", "reagent vendor" },
		{ "Ormak Grimshot", "hunter trainer" } }
	local titled = { label = "Questie's NPCs", hintLabel = "Questie's NPCs", aliases = { "npc" }, explicit = true,
		collect = function() return {} end,
		hintFind = function(_, tokens)
			local first, count, ids, line = nil, 0, {}, nil
			for i, n in ipairs(npcs) do
				local ln = n[1]:lower() .. (n[2] and (" <" .. n[2] .. ">") or "")
				local all = true
				for _, tk in ipairs(tokens) do if not ln:find(tk, 1, true) then all = false end end
				if all then
					count = count + 1; first = first or n[1]; line = line or ln
					if #ids < 2 then ids[#ids + 1] = i end
				end
			end
			return first, count, ids, line
		end }
	Use({
		{ "keybinds", { label = "Keybinding", aliases = { "keybind" }, collect = Rows({ { name = "Toggle Reagent Bag" } }) } },
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Linen Cloth", itemID = 2589 } }) } },
		{ "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({ { name = "Reagent Satchel", itemID = 77 } }) } },
		{ "toys", { label = "Toy", aliases = { "toy" }, collect = Rows({ { name = "Linen Cloth" }, { name = "Linen Cloth" },
			{ name = "Linen Cloth" } }) } },
		{ "npc", titled },
	})
	local function Order(text)
		UI:Open(text)
		local t = {}
		for _, e in ipairs(UI.Results()) do t[#t + 1] = tostring(e.catId) end
		return t, table.concat(t, ",")
	end
	-- a word that is several NPCs' title names their job: those NPCs first (they were last, scored as text)
	local o, joined = Order("reagent")
	check(o[1] == "npcs" and #o == 3, "reagent: the reagent vendors first: " .. joined)
	local npcRow = UI.Results()[1]
	check(npcRow.detail:find("Kyra Boucher", 1, true), "(their row names the first of them): " .. tostring(npcRow.detail))
	local sc, inTitle = UI._HintScore({ "reagent" }, "Kyra Boucher", "kyra boucher <reagent vendor>")
	check(inTitle and sc > ns.Score.TEXT_SCORE + 1, "a match in the title scores as a word in a name would: " .. tostring(sc))
	sc, inTitle = UI._HintScore({ "reagent" }, "Reagent Rick", "reagent rick")
	check(not inTitle and sc > ns.Score.TEXT_SCORE + 1, "in the name: the name's score, not the title's")
	sc = UI._HintScore({ "kyra" }, "Kyra Boucher")
	check(sc > ns.Score.TEXT_SCORE + 1, "no index line (another list's hintFind): the name it gave is scored")
	-- the same best match: more of them, higher
	o, joined = Order("linen")
	check(o[1] == "collections" and o[2] == "items", "Linen Cloth thrice in Collections, once in Items: Collections first: " .. joined)
	-- the category picked for these words before goes higher each time (up to three)
	for _ = 1, 3 do
		Order("reagent")
		local at
		for i, e in ipairs(UI.Results()) do if e.catId == "settings" then at = i end end
		UI:Activate(at)
		check(UI.category == "settings", "(Settings picked)")
		UI:Hide(); FlushAll()
	end
	check(type(ns.db.catPicks) == "table" and ns.db.catPicks.reagent and ns.db.catPicks.reagent.settings == 3,
		"the picks are kept by the words: " .. tostring(ns.db.catPicks and ns.db.catPicks.reagent and ns.db.catPicks.reagent.settings))
	o, joined = Order("reagent")
	check(o[1] == "settings", "picked three times for reagent: Settings first now: " .. joined)
	local full = UI.Results()[1]._score
	Order("reag")
	local part
	for _, e in ipairs(UI.Results()) do if e.catId == "settings" then part = e end end
	local pBonus = UI.CategoryPicks("reag").settings
	check(pBonus and pBonus > 0 and pBonus < UI.CategoryPicks("reagent").settings, "still typing it (reag): half the lift: " .. tostring(pBonus))
	check(part and part._score < full, "(lower than for the whole word)")
	-- (release review) longer words' picks together: half of three at most
	local was = ns.db.catPicks
	ns.db.catPicks = { reagent = { npcs = 3 }, reagents = { npcs = 3 }, ["reagent vendor"] = { npcs = 3 } }
	check(UI.CategoryPicks("rea").npcs == 1.5, "longer words' picks together: half of three at most: " .. tostring(UI.CategoryPicks("rea").npcs))
	ns.db.catPicks = was
	-- Tab on a category row counts as a pick too
	Order("linen")
	key("TAB")
	check(UI.category == "collections" and ns.db.catPicks.linen and ns.db.catPicks.linen.collections == 1, "Tab's pick is kept too")
	UI:Hide(); FlushAll()
	-- .forget clears them with the rest of the learned ranking
	ns.commands.forget.run("")
	check(ns.db.catPicks == nil, ".forget clears the category picks")
	o, joined = Order("reagent")
	check(o[1] == "npcs", "and the vendors are first again: " .. joined)
	ns.db.catPicks = nil
end)

Run("each list's category, by what you'd do with it (0.48.4)", function()
	-- (the addon's own lists, as loaded: Run gives them back after each block)
	-- (0.55.16, the player: your bags and your bank & alts apart again)
	local WANT = { items = "items", stored = "stored", mail = "character", gold = "character", panels = "windows",
		gameoptions = "settings", keybinds = "settings", cvars = "settings", addons = "settings", terminal = "settings",
		macros = "commands", lootlog = "recent", combatlog = "recent", loot = "loot" }
	local checked = 0
	for kind, cat in pairs(WANT) do
		if ns.providers[kind] then
			checked = checked + 1
			check(E.CategoryOf({ kind = kind }) == cat, kind .. " is in " .. cat .. ": " .. tostring((E.CategoryOf({ kind = kind }))))
		end
	end
	check(checked >= 10, "(most of them loaded here: " .. checked .. ")")
	check(E.CategoryOf({ kind = "slash", emote = "DANCE" }) == "emotes" and E.CategoryOf({ kind = "slash" }) == "commands",
		"slash rows: an emote in Emotes, the rest in Commands")
end)

Run("everyday words", function()
	E.Set(true)
	Lists()
	local res = In("bags", "rare sword")
	check(Has(res, "Shiny Sword") and Has(res, "Blade of Ages") == nil, "rare sword: the rare swords: " .. Show(res))
	check(Has(res, "Rare Sword"), "...and one named Rare (a soft filter: the word in the name counts)")
	check(Has(res, "Rusty Sword") == nil, "not the grey one")
	UI:SetQuery("junk")
	res = UI.Results()
	check(Has(res, "Rusty Sword") and #res == 1, "junk alone lists: the grey item: " .. Show(res))
	check(UI:SyntaxSegments("rare sword")[1][3] == ns.Theme.SYNTAX.filter, "rare is coloured as a filter")
	-- hard mode: just a word
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("rare sword")
	check(#res == 1 and res[1].name == "Rare Sword", "hard mode: rare is only a word: " .. Show(res))
	-- every everyday word stands for a real filter
	ns.db.easyMode = true
	local bad = {}
	for w, spec in pairs(E.WORDS) do if not ns.Filters.Parse(spec) then bad[#bad + 1] = w .. "=" .. spec end end
	check(#bad == 0, "every everyday word is a filter: " .. table.concat(bad, ", "))
end)

Run("weapon damage: sharpening stones and weightstones", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, spell = C_Item.GetItemSpell,
		desc = C_Spell.GetSpellDescription, stats = C_Item.GetItemStats }
	local ITEMS = {
		[211] = { "Coarse Sharpening Stone", "|Hitem:211|h", 1, 15, 5, "Trade Goods", "Trade Goods" },
		[212] = { "Heavy Weightstone", "|Hitem:212|h", 1, 25, 15, "Trade Goods", "Trade Goods" },
		[213] = { "Copper Bar", "|Hitem:213|h", 1, 10, 0, "Trade Goods", "Metal & Stone" },
		[214] = { "Elixir of Giants", "|Hitem:214|h", 1, 40, 30, "Consumable", "Elixir" },
		[215] = { "Gnarled Axe", "|Hitem:215|h", 2, 20, 15, "Weapon", "Two-Handed Axes" },
	}
	local CLASS = { [211] = 7, [212] = 7, [213] = 7, [214] = 0, [215] = 2 }
	local DESC = { [6211] = "Increase sharp weapon damage by 3 for 30 minutes.",
		[6212] = "Increase the damage of a blunt weapon by 6 for 30 minutes.",
		[6214] = "Increases your Strength by 25 for 1 hour." }
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemInfoInstant = function(id) return id, "x", "x", "", 1, CLASS[id] or 0, 0 end
	C_Item.GetItemSpell = function(id) if DESC[6000 + id] then return "spell", 6000 + id end end
	C_Spell.GetSpellDescription = function(id) return DESC[id] end
	C_Item.GetItemStats = function(link) if tostring(link):find("215") then return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 } end return {} end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({
		{ name = "Coarse Sharpening Stone", itemID = 211 }, { name = "Heavy Weightstone", itemID = 212 },
		{ name = "Copper Bar", itemID = 213 }, { name = "Elixir of Giants", itemID = 214 }, { name = "Gnarled Axe", itemID = 215 },
	}) } } })
	local res = In("bags", "weapon damage")
	check(#res == 2 and Has(res, "Coarse Sharpening Stone") and Has(res, "Heavy Weightstone"), "weapon damage: the stones (Trade Goods here), not bars, elixirs or the axe: " .. Show(res))
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("stat:weapondamage>=5")
	check(#res == 1 and res[1].name == "Heavy Weightstone", "Advanced stat:weapondamage>=5: the weightstone (+6): " .. Show(res))
	check(F.Parse("stat:wdmg") ~= nil, "stat:wdmg parses")
	E.Set(true)
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemSpell = save.info, save.inst, save.spell
	C_Spell.GetSpellDescription, C_Item.GetItemStats = save.desc, save.stats
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
end)

Run("stamina food: consumables in your bags", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, spell = C_Item.GetItemSpell,
		desc = C_Spell.GetSpellDescription, stats = C_Item.GetItemStats }
	local ITEMS = {
		[201] = { "Spiced Wolf Ribs", "|Hitem:201|h", 1, 15, 10, "Consumable", "Food & Drink" },
		[202] = { "Tough Jerky", "|Hitem:202|h", 1, 5, 1, "Consumable", "Food & Drink" },
		[203] = { "Elixir of Fortitude", "|Hitem:203|h", 1, 25, 15, "Consumable", "Elixir" },
		[204] = { "Grilled Squid", "|Hitem:204|h", 1, 45, 35, "Consumable", "Food & Drink" },
	}
	local DESC = { [6201] = "Restores 552 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 6 Stamina and Spirit for 15 min.",
		[6202] = "Restores 61 health over 18 sec.", [6203] = "Increases the player's maximum health by 120 and Stamina by 10 for 1 hour.",
		[6204] = "Restores 874 health over 27 sec. If you spend at least 10 seconds eating you will become well fed and gain 40 Attack Power for 10 min." }
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemInfoInstant = function(id) return id, "Consumable", "Food & Drink", "", 1, 0, 0 end
	C_Item.GetItemSpell = function(id) return "spell", 6000 + id end
	C_Spell.GetSpellDescription = function(id) return DESC[id] end
	C_Item.GetItemStats = function() return {} end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({
		{ name = "Spiced Wolf Ribs", itemID = 201 }, { name = "Tough Jerky", itemID = 202 }, { name = "Elixir of Fortitude", itemID = 203 },
		{ name = "Grilled Squid", itemID = 204 },
	}) } }, { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({ { name = "Gauntlets of Power", itemID = 99, _ltext = "attack power" } }) } } })
	local res = In("bags", "stamina food")
	check(#res == 1 and res[1].name == "Spiced Wolf Ribs", "stamina food: the food that gives stamina: " .. Show(res))
	-- two words that are one stat: the food that gives attack power, in your bags (not loot with "power" in it)
	UI:Hide(); FlushAll()
	UI:Open("attack power food")
	local ap = UI.Results()
	check(ap[1] and ap[1].name == "Grilled Squid" and not ap[2], "attack power food: Grilled Squid from your bags: " .. Show(ap) .. " cat=" .. tostring(UI.category))
	UI:Hide(); FlushAll()
	In("bags", "stamina food")
	UI:SetQuery("food")
	check(#UI.Results() == 3, "food: every food: " .. Show(UI.Results()))
	UI:SetQuery("food that gives stamina")
	check(#UI.Results() == 1 and UI.Results()[1].name == "Spiced Wolf Ribs", "food that gives stamina: " .. Show(UI.Results()))
	UI:SetQuery("stamina elixir")
	check(UI.Results()[1] and UI.Results()[1].name == "Elixir of Fortitude", "stamina elixir: " .. Show(UI.Results()))
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemSpell = save.info, save.inst, save.spell
	C_Spell.GetSpellDescription, C_Item.GetItemStats = save.desc, save.stats
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
end)

-- (0.69.4) the same on a German client: the game's own stat names ("Ausdauer", "Angriffskraft") are Simple mode's words
-- and what the effect text is read for; food in the language's words ("Essen", translated); Russian effect texts bend
-- the stat's name ("выносливости")
Run("stats in the client's language: Ausdauer Essen, and Russian word endings", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	local G = { "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_SPIRIT_SHORT", "SPELL_STAT3_NAME" }
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, spell = C_Item.GetItemSpell,
		desc = C_Spell.GetSpellDescription, stats = C_Item.GetItemStats, locale = ns.LOCALE, food = rawget(ns.L, "words: food"), g = {} }
	for _, k in ipairs(G) do save.g[k] = rawget(_G, k) end
	_G.ITEM_MOD_STAMINA_SHORT, _G.SPELL_STAT3_NAME = "Ausdauer", "Ausdauer"
	_G.ITEM_MOD_ATTACK_POWER_SHORT, _G.ITEM_MOD_SPIRIT_SHORT = "Angriffskraft", "Willenskraft"
	rawset(ns.L, "words: food", "Essen | Nahrung")
	ns.LOCALE = "deDE"; E.ForgetGameWords()
	local ITEMS = { -- (the class and subclass numbers last: what the game gives on every client, 0 and 5 for food)
		[301] = { "Gewürzte Wolfsrippchen", "|Hitem:301|h", 1, 15, 10, "Verbrauchbar", "Speis & Trank", 20, "", 0, 0, 0, 5 },
		[302] = { "Zähes Dörrfleisch", "|Hitem:302|h", 1, 5, 1, "Verbrauchbar", "Speis & Trank", 20, "", 0, 0, 0, 5 },
		[303] = { "Gegrillter Tintenfisch", "|Hitem:303|h", 1, 45, 35, "Verbrauchbar", "Speis & Trank", 20, "", 0, 0, 0, 5 },
	}
	local DESC = { [6301] = "Stellt im Verlauf von 21 Sek. insgesamt 552 Gesundheit wieder her. Wenn Ihr mindestens 10 Sek. lang esst, werdet Ihr satt und erhaltet 15 Min. lang 6 Ausdauer und Willenskraft.",
		[6302] = "Stellt im Verlauf von 18 Sek. insgesamt 61 Gesundheit wieder her.",
		[6303] = "Stellt im Verlauf von 27 Sek. insgesamt 874 Gesundheit wieder her. Wenn Ihr mindestens 10 Sek. lang esst, werdet Ihr satt und erhaltet 10 Min. lang 40 Angriffskraft." }
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemInfoInstant = function(id) return id, "Verbrauchbar", "Speis & Trank", "", 1, 0, 5 end -- (class 0, subclass 5: food)
	C_Item.GetItemSpell = function(id) return "spell", 6000 + id end
	C_Spell.GetSpellDescription = function(id) return DESC[id] end
	C_Item.GetItemStats = function() return {} end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({
		{ name = "Gewürzte Wolfsrippchen", itemID = 301 }, { name = "Zähes Dörrfleisch", itemID = 302 }, { name = "Gegrillter Tintenfisch", itemID = 303 },
	}) } } })
	check(E.WORDS["ausdauer"] == "stat:stamina" and E.WORDS["angriffskraft"] == "stat:ap" and E.WORDS["essen"] == "type:food",
		"the game's stat names and the language's food words are Simple mode's words: " .. tostring(E.WORDS["ausdauer"]) .. " "
		.. tostring(E.WORDS["angriffskraft"]) .. " " .. tostring(E.WORDS["essen"]))
	local res = In("bags", "Ausdauer Essen")
	check(#res == 1 and res[1].name == "Gewürzte Wolfsrippchen", "Ausdauer Essen: the food that gives Ausdauer: " .. Show(res))
	UI:Hide(); FlushAll()
	res = In("bags", "Angriffskraft Essen")
	check(#res == 1 and res[1].name == "Gegrillter Tintenfisch", "Angriffskraft Essen: " .. Show(res))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("stat:stamina>=6")
	check(#res == 1 and res[1].name == "Gewürzte Wolfsrippchen", "Advanced stat:stamina>=6 reads the German effect text: " .. Show(res))
	E.Set(true)
	-- Russian: "выносливость" (the game's name) found as "выносливости" in an effect text, "сила атаки" as "силу атаки"
	local function Has(text, word)
		local pat = F.Stemmed(word)
		if type(pat) == "table" then return text:find(pat.pat) ~= nil end
		return text:find(pat, 1, true) ~= nil
	end
	check(Has("и повышает показатель выносливости и духа на 6 ед.", "выносливость") and Has("увеличивает силу атаки на 40", "сила атаки")
		and not Has("увеличивает ловкость на 25", "выносливость") and Has("erhöht ausdauer um 6", "ausdauer"),
		"Russian: a stat's name found in its bent forms; another stat not; other languages as they are")
	ns.LOCALE = save.locale; E.ForgetGameWords()
	for _, k in ipairs(G) do _G[k] = save.g[k] end
	rawset(ns.L, "words: food", save.food)
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemSpell = save.info, save.inst, save.spell
	C_Spell.GetSpellDescription, C_Item.GetItemStats = save.desc, save.stats
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
end)

-- (0.69.6) the rest of the gap: weapon damage by the game's words for weapon and damage (a wizard oil's spell damage
-- left out), the language's sentence words left out, a stat named in three words joined, shorthand by the place's own
-- name there, Chinese written without spaces
Run("other clients: weapon damage, sentence words, three-word stats, shorthand, Chinese without spaces", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	local G = { "WEAPON", "DAMAGE", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_SPELL_POWER_SHORT", "GetRealZoneText" }
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, spell = C_Item.GetItemSpell,
		desc = C_Spell.GetSpellDescription, stats = C_Item.GetItemStats, locale = ns.LOCALE, g = {}, L = {} }
	for _, k in ipairs(G) do save.g[k] = rawget(_G, k) end
	local LK = { "words: weapon damage", "words: sentence words", "words: food" }
	for _, k in ipairs(LK) do save.L[k] = rawget(ns.L, k) end
	_G.WEAPON, _G.DAMAGE, _G.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Waffe", "Schaden", "Zauberschaden"
	_G.ITEM_MOD_STAMINA_SHORT, _G.ITEM_MOD_SPELL_POWER_SHORT = "Ausdauer", "Macht der Zauber"
	rawset(ns.L, "words: weapon damage", "Waffenschaden"); rawset(ns.L, "words: food", "Essen")
	rawset(ns.L, "words: sentence words", "das | gibt | mit")
	ns.LOCALE = "deDE"; E.ForgetGameWords(); E.AddSentenceWords()
	local ITEMS = { -- (class and subclass numbers last)
		[401] = { "Grober Wetzstein", "|Hitem:401|h", 1, 15, 5, "Handwerkswaren", "Handwerkswaren", 20, "", 0, 0, 7, 0 },
		[402] = { "Schwerer Gewichtsstein", "|Hitem:402|h", 1, 25, 15, "Handwerkswaren", "Handwerkswaren", 20, "", 0, 0, 7, 0 },
		[403] = { "Hervorragendes Zauberöl", "|Hitem:403|h", 1, 45, 40, "Verbrauchbar", "Gegenstandsverbesserung", 20, "", 0, 0, 0, 8 },
		[404] = { "Grobe Dynamitstange", "|Hitem:404|h", 1, 10, 5, "Handwerkswaren", "Sprengstoff", 20, "", 0, 0, 7, 2 },
		[405] = { "Gewürzte Wolfsrippchen", "|Hitem:405|h", 1, 15, 10, "Verbrauchbar", "Speis & Trank", 20, "", 0, 0, 0, 5 },
	}
	local CLASS = { [401] = 7, [402] = 7, [403] = 0, [404] = 7, [405] = 0 }
	local SUB = { [403] = 8, [404] = 2, [405] = 5 }
	local DESC = { [6401] = "Erhöht 30 Min. lang den Schaden einer Waffe mit Klinge um 3.",
		[6402] = "Erhöht 30 Min. lang den Schaden einer stumpfen Waffe um 6.",
		[6403] = "Solange auf eine Waffe aufgetragen, erhöht sich der Zauberschaden um bis zu 36. Hält 30 Min.",
		[6404] = "Fügt Feinden in einem Umkreis von 5 Metern 26 bis 34 Feuerschaden zu.",
		[6405] = "Wenn Ihr mindestens 10 Sek. lang esst, werdet Ihr satt und erhaltet 15 Min. lang 6 Ausdauer." }
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetItemInfoInstant = function(id) return id, "x", "x", "", 1, CLASS[id] or 0, SUB[id] or 0 end
	C_Item.GetItemSpell = function(id) if DESC[6000 + id] then return "spell", 6000 + id end end
	C_Spell.GetSpellDescription = function(id) return DESC[id] end
	C_Item.GetItemStats = function() return {} end
	local rows = {}
	for id, t in pairs(ITEMS) do rows[#rows + 1] = { name = t[1], itemID = id } end
	rows[#rows + 1] = { name = "Schwarzfelstiefen-Schlüssel", itemID = 499 }
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows(rows) } } })
	-- weapon damage: the stones, not the oil (spell damage) or the dynamite (fire damage, no weapon)
	local res = In("bags", "Waffenschaden")
	check(#res == 2 and Has(res, "Grober Wetzstein") and Has(res, "Schwerer Gewichtsstein"),
		"Waffenschaden: the stones, by the game's words for weapon and damage; not the wizard oil or dynamite: " .. Show(res))
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("stat:weapondamage>=5")
	check(#res == 1 and res[1].name == "Schwerer Gewichtsstein", "Advanced stat:weapondamage>=5 on German text: the weightstone (+6): " .. Show(res))
	E.Set(true)
	-- sentence words: "Essen, das Ausdauer gibt"
	res = In("bags", "Essen das Ausdauer gibt")
	check(#res == 1 and res[1].name == "Gewürzte Wolfsrippchen", "Essen das Ausdauer gibt: the language's sentence words left out: " .. Show(res))
	UI:Hide(); FlushAll()
	-- a stat named in three words, "Macht der Zauber" (spell power): read as one
	local adv = E.ToAdvanced("Macht der Zauber Essen")
	check(adv:find("stat:sp", 1, true) and adv:find("type:food", 1, true), "a stat in three words joined as one: " .. adv)
	-- shorthand: "brd" also Blackrock Depths as the client names it (GetRealZoneText of its instance)
	_G.GetRealZoneText = function(id) return id == 230 and "Schwarzfelstiefen" or nil end
	ns.ShorthandLocalize()
	local brd = ns.Shorthand.brd
	check(brd[#brd] == "schwarzfelstiefen", "brd: Schwarzfelstiefen on a German client: " .. table.concat(brd, ", "))
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("brd")
	check(Has(res, "Schwarzfelstiefen-Schlüssel"), "brd finds Schwarzfelstiefen's key: " .. Show(res))
	E.Set(true)
	for k, list in pairs(ns.Shorthand) do
		for i = #list, 1, -1 do if list[i] == "schwarzfelstiefen" then table.remove(list, i) end end
	end
	-- Chinese without spaces: "耐力食物" is stamina and food; a name made of other characters as typed
	_G.ITEM_MOD_STAMINA_SHORT = "耐力"; rawset(ns.L, "words: food", "食物")
	ns.LOCALE = "zhCN"; E.ForgetGameWords()
	check(E.English("耐力食物") == "耐力 食物" and E.English("耐力之戒") == "耐力之戒" and E.English("治疗药水") == "治疗药水"
		and E.English("食物") == "食物", "Chinese: a run made of known words spaced into them, anything else as typed: "
		.. E.English("耐力食物") .. " / " .. E.English("耐力之戒"))
	-- put back
	ns.LOCALE = save.locale
	for _, k in ipairs(G) do _G[k] = save.g[k] end
	for _, k in ipairs(LK) do rawset(ns.L, k, save.L[k]) end
	E.STOP.das, E.STOP.gibt, E.STOP.mit = nil, nil, nil
	E.ForgetGameWords()
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemSpell = save.info, save.inst, save.spell
	C_Spell.GetSpellDescription, C_Item.GetItemStats = save.desc, save.stats
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
end)

Run("rare shield wailing caverns: the loot, even when not every word fits", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache()
	local saveInfo = C_Item.GetItemInfo
	local ITEMS = {
		[13245] = { "Kresh's Back", "|Hitem:13245|h", 2, 20, 15, "Armor", "Shields", 1, "INVTYPE_SHIELD" },
		[6473] = { "Armor of the Fang", "|Hitem:6473|h", 3, 23, 18, "Armor", "Leather", 1, "INVTYPE_CHEST" },
		[10413] = { "Gloves of the Fang", "|Hitem:10413|h", 3, 24, 19, "Armor", "Leather", 1, "INVTYPE_HAND" },
		[1979] = { "Wall of the Dead", "|Hitem:1979|h", 3, 40, 35, "Armor", "Shields", 1, "INVTYPE_SHIELD" },
	}
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	local function L(name, id, boss, inst) return { name = name, itemID = id, detail = boss .. "  " .. inst,
		_ltext = (inst .. " " .. boss .. " loot drop atlasloot"):lower() } end
	Use({ { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
		L("Kresh's Back", 13245, "Kresh", "Wailing Caverns"), L("Armor of the Fang", 6473, "Lord Cobrahn", "Wailing Caverns"),
		L("Gloves of the Fang", 10413, "Lady Anacondra", "Wailing Caverns"), L("Wall of the Dead", 1979, "Ras Frostwhisper", "Scholomance"),
	}) } } })
	local res = In("loot", "shield wailing caverns")
	check(#res == 1 and res[1].name == "Kresh's Back", "shield: the item's type counts (\"shield\" isn't in its name): " .. Show(res))
	-- Kresh's Back is green, not rare: nothing passes every word, so the closest come, the shield first
	UI:SetQuery("rare shield wailing caverns")
	res = UI.Results()
	check(res[1] and res[1].name == "Kresh's Back" and not Has(res, "Wall of the Dead"),
		"rare shield wailing caverns: Kresh's shield first, nothing outside Wailing Caverns: " .. Show(res))
	check((UI.status:GetText() or ""):find("closest", 1, true), "the footer says these are the closest: " .. tostring(UI.status:GetText()))
	-- typed like a sentence: the little words aren't asked for
	UI:SetQuery("shield that drops from kresh")
	res = UI.Results()
	check(res[1] and res[1].name == "Kresh's Back", "shield that drops from kresh: " .. Show(res))
	UI:SetQuery("rare shield wailing caverns")
	-- typed before picking a category: Loot is offered, its best match the shield
	UI:SetCategory(nil) -- (back to all of them)
	res = UI.Results()
	check(res[1] and res[1].name == "Kresh's Back" and UI.categoryAuto, "no category picked: only Loot has it, so its results straight away: " .. Show(res))
	C_Item.GetItemInfo = saveInfo
	F.ClearCache()
end)

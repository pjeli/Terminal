-- Easy mode: categories picked from the results, everyday words, Questie's rows among the results, the footer's verbs,
-- Tab through categories, action words, nearest, the row menu, Advanced syntax refused, .advanced (with a confirmation)
-- and .simple. ("easy" in the code is Simple mode; "hard" is Advanced.)
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

local function Fire(e) return function() log[#log + 1] = "RAN " .. e end end
local function ActionLists()
	Use({
		{ "items", { label = "Item", aliases = { "item" }, collect = Rows({
			{ name = "Hearthstone", itemID = 6948, secure = { binding = "OPENALLBAGS" }, activate = Fire("bags"),
				secondary = Fire("use"), secondarySecure = { macro = "/use item:6948" }, link = "|cffffffff|Hitem:6948|h[Hearthstone]|h|r" },
			{ name = "Shiny Sword", quality = 3, itemID = 3 } }) } },
		{ "spells", { label = "Spell", aliases = { "spell" }, collect = Rows({
			{ name = "Frost Nova", activate = Fire("book"), secondary = Fire("cast"), secondarySecure = { macro = "/cast Frost Nova" } },
			{ name = "Summon Voidwalker", activate = Fire("book"), secondary = Fire("cast"),
				secondarySecure = { macro = "/cast Summon Voidwalker" } } }) } },
		{ "mounts", { label = "Mount", aliases = { "mount" }, collect = Rows({ { name = "Swift Raptor", activate = Fire("summon") } }) } },
		{ "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = Rows({
			{ name = "Innkeeper Farley", key = 295, npcID = 295, activate = Fire("map"), secondary = Fire("target"), secondarySecure = { macro = "/targetexact Innkeeper Farley" } },
			{ name = "Innkeeper Allison", key = 6740, npcID = 6740, activate = Fire("map") },
			{ name = "Innkeeper Far Away", key = 9999, npcID = 9999, activate = Fire("map") },
			{ name = "Hogger", key = 448, npcID = 448, activate = Fire("map") },
			{ name = "Bernie Heisten", key = 3546, npcID = 3546, activate = Fire("map") },
			{ name = "Grimtak", key = 3881, npcID = 3881, activate = Fire("map") } }) } },
	})
end

Run("action words", function()
	E.Set(true)
	ActionLists()
	UI:Open("use hearthstone")
	local res = UI.Results()
	check(res[1] and res[1].name == "Hearthstone" and res[1].actionVerb == "use" and res[1].secure.macro == "/use item:6948",
		"use hearthstone: the Hearthstone, Enter uses it: " .. Show(res))
	check((UI.status:GetText() or ""):find("Use", 1, true), "the footer says Use: " .. tostring(UI.status:GetText()))
	check((UI.hints:GetText() or ""):find("use", 1, true), "Enter: use: " .. tostring(UI.hints:GetText()))
	key("ENTER")
	local mp = _G.TerminalMacroProxy
	check(S.armed == "MACRO" and mp.attrs.macrotext == "/use item:6948", "Enter: the game presses /use: " .. tostring(mp.attrs.macrotext))
	mp.scripts.PostClick(mp, "LeftButton", true); FlushAll()
	UI:Disarm(); UI:Hide(); FlushAll()
	UI:Open("cast frost nova")
	key("ENTER")
	check(mp.attrs.macrotext == "/cast Frost Nova", "cast frost nova: /cast: " .. tostring(mp.attrs.macrotext))
	UI:Disarm(); UI:Hide(); FlushAll()
	UI:Open("summon raptor")
	res = UI.Results()
	check(res[1] and res[1].name == "Swift Raptor" and #res == 1, "summon raptor: the mount only: " .. Show(res))
	-- (0.50.7, review) a warlock's "summon voidwalker": the spell, cast on Enter
	UI:Hide(); FlushAll()
	UI:Open("summon voidwalker")
	res = UI.Results()
	check(res[1] and res[1].name == "Summon Voidwalker", "summon voidwalker: the spell: " .. Show(res))
	key("ENTER")
	check(mp.attrs.macrotext == "/cast Summon Voidwalker", "...Enter casts it: " .. tostring(mp.attrs.macrotext))
	UI:Disarm(); UI:Hide(); FlushAll()
	UI:Open("summon raptor")
	local mark = #log
	UI:Activate(1)
	check(logHas("RAN summon", mark + 1), "...Enter summons it")
	UI:Open("target farley")
	key("ENTER")
	check(mp.attrs.macrotext == "/targetexact Innkeeper Farley", "target farley: /targetexact: " .. tostring(mp.attrs.macrotext))
	UI:Disarm(); UI:Hide(); FlushAll()
	-- the word alone is just a word; Advanced mode: just a word
	UI:Open("use")
	check(not UI.action, "\"use\" alone: no action")
	ns.db.easyMode = false; UI:EasyChanged()
	UI:SetQuery("use hearthstone")
	check(not UI.action, "Advanced mode: no action words")
end)

Run("nearest", function()
	E.Set(true)
	ActionLists()
	local I = ns.Integrations
	local saveHere, saveDist = I.Here, I.NpcDistance
	local DIST = { [295] = 120, [6740] = 40 }
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	local saveField, saveDefs, saveGroup = I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup
	local FIELDS = { [295] = { npcFlags = 128, friendlyToFaction = "A" }, [6740] = { npcFlags = 128, friendlyToFaction = "AH" },
		[9999] = { npcFlags = 128, friendlyToFaction = "A" },
		[3546] = { npcFlags = 4096 + 4, friendlyToFaction = "A" }, [3881] = { npcFlags = 4096 + 4, friendlyToFaction = "H" },
		[448] = { npcFlags = 0 } }
	I.NpcField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
	I.NpcFlagDefs = function() return { VENDOR = 4, REPAIR = 4096, INNKEEPER = 128 } end
	_G.UnitFactionGroup = function() return "Alliance" end
	ns.Filters.ClearCache()
	UI:Open("nearest innkeeper")
	local res = UI.Results()
	check(res[1] and res[1].name == "Innkeeper Allison" and res[1].detail == "40 yd" and res[2] and res[2].name == "Innkeeper Farley",
		"nearest innkeeper: closest first, how far: " .. Show(res) .. " / " .. tostring(res[1] and res[1].detail))
	check(not Has(res, "Innkeeper Far Away") and not Has(res, "Hogger"), "unknown places and other NPCs left out")
	-- "nearby" means nearest too, first or last: "nearby innkeeper", "innkeeper nearby"
	for _, q in ipairs({ "nearby innkeeper", "innkeeper nearby", "innkeeper closest" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		local r2 = UI.Results()
		check(r2[1] and r2[1].name == "Innkeeper Allison" and r2[1].detail == "40 yd", q .. ": as nearest innkeeper: " .. Show(r2))
	end
	check(E.ToAdvanced("innkeeper nearby") == "@npc is:innkeeper faction:friendly sort:distance ", "Alt+` writes innkeeper nearby as sort:distance: " .. E.ToAdvanced("innkeeper nearby"))
	-- (0.65.7, the player: "allow for searching for nearest vs farthest, with unknown distances treated as infinitely far
	-- away"; "sort:distance should be nearest and sort:-distance furthest") the farthest first; one whose place isn't
	-- known before them all
	for _, q in ipairs({ "farthest innkeeper", "furthest innkeeper", "innkeeper farthest" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		local r2 = UI.Results()
		check(Show(r2) == "Innkeeper Far Away | Innkeeper Farley | Innkeeper Allison" and r2[2].detail == "120 yd",
			q .. ": the farthest first, the unknown one as infinitely far: " .. Show(r2))
	end
	check(E.ToAdvanced("farthest innkeeper") == "@npc is:innkeeper faction:friendly sort:-distance ",
		"Alt+` writes farthest innkeeper as sort:-distance: " .. E.ToAdvanced("farthest innkeeper"))
	local dist
	for _, o in ipairs(ns.Bar.Options("sort")) do if o.id == "distance" then dist = o end end
	check(dist and dist.on and dist.asc == false, "the bar: Sort: Distance, its arrow down (the farthest first)")
	-- the bar: Distance picked, the nearest first (its arrow up); picked again, the farthest
	UI:Hide(); FlushAll()
	ns.Bar.Reset()
	UI:Open("innkeeper"); FlushAll()
	ns.Bar.Pick("sort", "distance"); FlushAll()
	check(ns.Bar.state.sort == "distance" and Show(UI.Results()) == "Innkeeper Allison | Innkeeper Farley | Innkeeper Far Away",
		"the bar's Distance: the nearest first (the unknown kept, last): " .. Show(UI.Results()))
	ns.Bar.Pick("sort", "distance"); FlushAll()
	check(ns.Bar.state.sort == "-distance" and Show(UI.Results()) == "Innkeeper Far Away | Innkeeper Farley | Innkeeper Allison",
		"picked again: the farthest first: " .. Show(UI.Results()))
	check(E.ToAdvanced("innkeeper") == "@npc is:innkeeper faction:friendly sort:-distance ", "Alt+` writes the bar's farthest: " .. E.ToAdvanced("innkeeper"))
	ns.Bar.Reset()
	-- Advanced: sort:distance, sort:-distance; the words sort:nearest and sort:farthest (and sort:-farthest) still read
	E.Set(false)
	local function Adv(line) local t = {} for _, e in ipairs(UI:Search(line)) do t[#t + 1] = e.name end return table.concat(t, ", ") end
	local near, far = Adv("@npc innkeeper sort:distance"), Adv("@npc innkeeper sort:-distance")
	check(near == "Innkeeper Allison, Innkeeper Farley, Innkeeper Far Away", "sort:distance: the nearest first, the unknown last: " .. near)
	check(far == "Innkeeper Far Away, Innkeeper Farley, Innkeeper Allison", "sort:-distance: the unknown first, then the farthest: " .. far)
	check(Adv("@npc innkeeper sort:nearest") == near and Adv("@npc innkeeper sort:farthest") == far and Adv("@npc innkeeper sort:-farthest") == near,
		"sort:nearest, sort:farthest and sort:-farthest read as before")
	E.Set(true)
	-- (0.56.8, a player's comment) "nearest" mistyped ("nearset", "neareset", "nearbby"), and an NPC's role said alone
	-- ("inn", "innkeeper"): the nearest, as "nearest innkeeper" lists them
	for _, q in ipairs({ "nearset innkeeper", "neareset innkeeper", "innkeeper nearbby", "innkeeper", "inn" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		local r2 = UI.Results()
		check(r2[1] and r2[1].name == "Innkeeper Allison" and r2[1].detail == "40 yd" and not Has(r2, "Innkeeper Far Away"),
			q .. ": the nearest innkeeper: " .. Show(r2))
	end
	check(E.NearTypo("nearer") and not E.NearTypo("dearest") and not E.NearTypo("near") and not E.NearTypo("neutral"),
		"nearest's typos: n..., two letters off at most")
	check(not E.NearTypo("newest") and not E.NearTypo("nearly") and E.NearTypo("nearset") and E.NearTypo("nearbby"),
		"(release review) newest and nearly are words of their own")
	-- "skinner", "weapon master": a profession's trainers, the weapon masters; the nearest (Questie's titles)
	check(E.ToAdvanced("skinner"):find("trainer:skinning", 1, true) and E.ToAdvanced("skinner"):find("sort:distance", 1, true),
		"skinner: the nearest skinning trainer: " .. E.ToAdvanced("skinner"))
	check(E.ToAdvanced("weapon master"):find("is:weaponmaster", 1, true) and E.ToAdvanced("weapon master"):find("sort:distance", 1, true),
		"weapon master: the nearest of them: " .. E.ToAdvanced("weapon master"))
	local wm = ns.Filters.Parse("is:weaponmaster")
	check(wm and ns.Filters.Pass({ npcID = 1, kind = "npc", sub = "Weapon Master", name = "Woo Ping" }, { wm })
		and not ns.Filters.Pass({ npcID = 2, kind = "npc", sub = "Mage Trainer", name = "Maginor" }, { wm }), "is:weaponmaster: by the title")
	-- (0.56.10, the player: "all NPC lists should be sorted by nearest by default") a list of NPCs alone: the nearest
	-- first, those with no place known kept after; a sort picked: that one
	local npcs = UI:Search("@npc is:innkeeper")
	check(Show(npcs) == "Innkeeper Allison | Innkeeper Farley | Innkeeper Far Away" and npcs[1].detail == "40 yd",
		"@npc: the nearest first, the unknown ones after: " .. Show(npcs))
	local byName = UI:Search("@npc is:innkeeper sort:name")
	check(Show(byName) == "Innkeeper Allison | Innkeeper Far Away | Innkeeper Farley", "a sort asked for: that one: " .. Show(byName))
	check(E.WORDS.merchant == "is:vendor" and E.ROLE_WORDS.merchant, "merchant: a vendor, an NPC's role")
	-- nowhere known (a dungeon): "innkeeper" listed as before, not "can't tell where you are"
	local hereWas = I.Here
	I.Here = function() return nil end
	UI:Hide(); FlushAll()
	UI:Open("innkeeper"); FlushAll()
	check(not (UI.action and UI.action.nearest), "innkeeper, nowhere known: a list as before")
	I.Here = hereWas
	-- not with other words, a place or Advanced syntax: "innkeeper hogger" is a search
	UI:Hide(); FlushAll()
	UI:Open("innkeeper allison"); FlushAll()
	check(not (UI.action and UI.action.nearest), "a role with a name: not made nearest")
	-- (0.50.7, review) "the nearest innkeeper": as the search reads it
	-- (0.66.7, top N: "the nearest innkeeper" is the one, | first 1; "nearest innkeeper" all of them, nearest first)
	check(E.ToAdvanced("the nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:distance | first 1",
		"Alt+`, the nearest innkeeper: " .. E.ToAdvanced("the nearest innkeeper"))
	check(E.ToAdvanced("nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:distance ",
		"Alt+`, nearest innkeeper: " .. E.ToAdvanced("nearest innkeeper"))
	UI:Hide(); FlushAll()
	UI:Open("nearest innkeeper")
	local mark = #log
	UI:Activate(1)
	check(logHas("RAN map", mark + 1), "Enter: on the map (and pinned)")
	I.Here = function() return nil end
	UI:Open("nearest innkeeper")
	res = UI.Results()
	check(res[1] and res[1].noActivate and res[1].name:find("where you are", 1, true), "nowhere known (a dungeon): says so: " .. Show(res))
	-- "nearest repair": NPCs that repair (Questie's flags), only those friendly to you (an Alliance player here)
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	DIST[3546], DIST[3881], DIST[448] = 300, 50, 10
	ns.Filters.ClearCache()
	UI:Open("nearest repair")
	res = UI.Results()
	check(#res == 1 and res[1].name == "Bernie Heisten", "nearest repair: the Alliance repairer, not the closer Horde one: " .. Show(res))
	UI:SetQuery("nearest hogger")
	check(UI.Results()[1] and UI.Results()[1].name == "Hogger", "nearest hogger: a name, anyone (no faction kept to)")
	-- (0.55.10, the player's screenshot: "nearest unlearned flight master" grouped by zone from the bar, Enter on the
	-- zone kept grouping, in:"Winterspring" written again on each) a group's Enter lists the NPCs
	FIELDS[295].zoneID, FIELDS[6740].zoneID = 12, 12
	local saveMap = _G.C_Map
	_G.C_Map = setmetatable({ GetAreaInfo = function(id) return id == 12 and "Elwynn Forest" or nil end }, { __index = saveMap })
	ns.Filters.ClearCache()
	UI:Open("nearest innkeeper"); FlushAll()
	ns.Bar.Pick("group", "zone"); FlushAll()
	local r3 = UI.Results()
	check(r3[1] and r3[1].kind == "aggregate" and r3[1].drillTo, "(grouped by zone: " .. Show(r3) .. ")")
	UI.sel = 1
	T.key("ENTER"); FlushAll()
	r3 = UI.Results()
	check(not ns.Bar.state.group and r3[1] and r3[1].kind ~= "aggregate" and Has(r3, "Innkeeper Allison"),
		"Enter on the zone: its NPCs, nearest first: " .. Show(r3) .. " [" .. T.query() .. "]")
	-- (0.55.16, the player's screenshot: Alt+` then wrote in:Elwynn Forest, unquoted: nothing found) quoted again
	local adv = E.ToAdvanced(T.query())
	check(adv:find('in:"Elwynn Forest"', 1, true), "Alt+` keeps a place of several words quoted: " .. adv)
	ns.db.easyMode = false
	local r4 = UI:Search(adv)
	ns.db.easyMode = true
	check(Has(r4, "Innkeeper Allison"), "and finds the same: " .. Show(r4))
	UI:Hide(); FlushAll()
	_G.C_Map = saveMap
	ns.Bar.Reset()
	I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup = saveField, saveDefs, saveGroup
	I.Here, I.NpcDistance = saveHere, saveDist
end)

-- (0.54.1, a player's ask: "if I type a query that's clearly for advanced mode (like starting with @), it should just work")
-- (0.55.9, the player: "if things are written in simple mode let's try to keep them in simple mode as much as we can")
-- Advanced syntax typed in Simple mode is searched as typed, in Simple mode: no switch, nothing rewritten
Run("Advanced syntax in Simple mode: searched as typed, Simple kept", function()
	E.Set(true)
	ActionLists()
	UI:Open("@npc hogger")
	local res = UI.Results()
	check(res[1] and res[1].name == "Hogger" and E.On() and not E.temp and T.query() == "@npc hogger",
		"@npc hogger: Hogger, Simple mode kept, the line as typed: " .. Show(res))
	check(UI:SyntaxSegments("@npc hogger")[1][3] ~= ns.Theme.SYNTAX.bad, "@npc in the taken colour")
	UI:SetQuery("hogger")
	check(E.On() and not E.temp, "the line without it: Simple")
	UI:SetQuery("hearthstone >> party")
	check(UI.sendTo and UI.sendTo.cmd and E.On(), ">> party: the send armed, Simple kept")
	UI:SetQuery("q:rare sword")
	check(not Has(UI.Results(), "Shiny Sword") or UI.Results()[1].kind ~= "advanced", "q:rare: a filter, no row refusing it: " .. Show(UI.Results()))
	UI:SetQuery("/who")
	check(E.On(), "a /slash line leaves the mode as it is")
	UI:Hide(); FlushAll()
	check(E.On() and ns.db.easyMode ~= false and not E.temp, "closed: Simple again")
	-- Advanced mode takes them
	ns.db.easyMode = false; UI:EasyChanged()
	res = UI:Search("@npc hogger")
	check(res[1] and res[1].name == "Hogger", "Advanced: @npc works: " .. Show(res))
end)

Run("rotating examples in the empty prompt", function()
	E.Set(true)
	UI:Open("")
	local a = E.Example()
	UI:Hide(); FlushAll()
	UI:Open("")
	local b = E.Example()
	-- (the pool has tips too: "tip: F1 shows every key")
	local function Ex(x) return type(x) == "string" and (x:find("^try:") or x:find("^tip:")) end
	check(a ~= b and Ex(a) and Ex(b), "a different example each open: " .. tostring(a) .. " / " .. tostring(b))
	-- Advanced: its own examples (@kinds, filters, >> chat), shown faintly in the empty prompt
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Hide(); FlushAll()
	local seen = {}
	for _ = 1, #E.ADV_EXAMPLES do
		UI:Open("")
		seen[E.Example()] = true
		check(UI:Suggestion() == nil and UI.ghost:IsShown() and UI.ghost:GetText() == E.Example():gsub("|", "||"), "Advanced: the example is in the empty prompt: " .. tostring(UI.ghost:GetText()))
		UI:Hide(); FlushAll()
	end
	local any = { at = false, filter = false, chat = false }
	for ex in pairs(seen) do
		if ex:find("@", 1, true) then any.at = true end
		if ex:find("%a:%S") then any.filter = true end
		if ex:find(">>", 1, true) then any.chat = true end
	end
	check(any.at and any.filter and any.chat, "Advanced examples show @kinds, key:value filters and >> chat")
	-- Shift+Right on the empty prompt takes the suggestion
	UI:Open("")
	while not E.Example():find("^try:") or E.Example():find("%(") do UI:Hide(); FlushAll(); UI:Open("") end
	local want = E.Example():gsub("^try: ", "")
	T.withShift = T.withShift or function(fn) local s = _G.IsShiftKeyDown; _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = s end
	T.withShift(function() key("RIGHT") end)
	check(UI.edit:GetText() == want .. " ", "Shift+Right takes the suggestion: '" .. UI.edit:GetText() .. "' (" .. want .. ")")
	UI:Hide(); FlushAll()
	-- a note in brackets isn't typed; a tip isn't taken
	UI:Open("")
	while E.Example() ~= "try: .filters (every key:value)" do UI:Hide(); FlushAll(); UI:Open("") end
	T.withShift(function() key("RIGHT") end)
	check(UI.edit:GetText() == ".filters ", "the bracketed note isn't typed: '" .. UI.edit:GetText() .. "'")
	UI:Hide(); FlushAll()
	UI:Open("")
	while not E.Example():find("^tip:") do UI:Hide(); FlushAll(); UI:Open("") end
	T.withShift(function() key("RIGHT") end)
	check(UI.edit:GetText() == "", "a tip isn't taken")
	UI:Hide(); FlushAll()
	-- the option off: no suggestion in either mode, just the empty prompt
	ns.Theme.Set("suggest", "off")
	UI:Open("")
	check(not UI.ghost:IsShown(), "suggestions off (Advanced): the prompt stays empty")
	UI:Hide(); FlushAll()
	E.Set(true)
	UI:Open("")
	check(not UI.ghost:IsShown(), "suggestions off (Simple): the prompt stays empty")
	UI:Hide(); FlushAll()
	ns.Theme.Set("suggest", "on")
	UI:Open("")
	check(UI.ghost:IsShown() and UI.ghost:GetText():find("try:", 1, true), "on again: the suggestion is back")
	check(ns.Options == nil or ns.Options.widgets == nil or ns.Options.widgets.suggest, "(the options panel has its checkbox)")
	UI:Hide(); FlushAll()
	ns.db.easyMode = false; UI:EasyChanged()
	-- every one is real syntax: its @kinds and filter keys exist
	for _, ex in ipairs(E.ADV_EXAMPLES) do
		for w in ex:gsub("^%a+: ", ""):gmatch("%S+") do
			if w:sub(1, 1) == "@" then check(ns:ResolveProvider(w:sub(2)) ~= nil or w == "@questie" or w == "@npc" or w == "@stored" or w == "@training", "known kind in an example: " .. w) end
			if w:find("^%a+:%S") and not w:find("[()]") then check(ns.Filters.Parse(w) ~= nil, "a working filter in an example: " .. w) end
		end
	end
end)

Run("examples made for the character", function()
	local save = { lvl = _G.UnitLevel, cls = _G.UnitClass, zone = _G.GetRealZoneText, guild = _G.IsInGuild, rand = E.rand,
		missing = ns.Integrations.AddonMissing, rand01 = E.rand01, place = E.Place, group = _G.IsInGroup }
	ns.Integrations.AddonMissing = function() return false end -- (Questie, AtlasLoot, Attune all there)
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.GetRealZoneText = function() return "Westfall" end
	_G.IsInGuild = function() return true end
	E.rand = function(a) return a end -- (the first of each list)
	local mine = table.concat(E.PersonalExamples(false), " | ")
	check(mine:find("try: nearest warrior trainer", 1, true), "your class's trainer: " .. mine)
	check(mine:find("skillup", 1, true) and mine:find("trainer", 1, true), "one of your professions: " .. mine)
	check(mine:find("try: shadowfang keep", 1, true) and mine:find("try: shadowfang keep upgrades", 1, true), "a dungeon for your level (20: Shadowfang Keep, 22-30, close enough): " .. mine)
	check(mine:find("try: vendor westfall", 1, true) and mine:find("try: online", 1, true), "where you are, and your guild: " .. mine)
	local adv = E.PersonalExamples(true)
	local advText = table.concat(adv, " | ")
	check(advText:find("@gear stat:str is:upgrade", 1, true) and advText:find("@guild is:online", 1, true)
		and advText:find("@recipe is:skillup", 1, true), "Advanced: for you too: " .. advText)
	check(not advText:find("@questie", 1, true) and not advText:find("@npc", 1, true), "lists this setup doesn't have (no Questie here) aren't suggested: " .. advText)
	for _, ex in ipairs(adv) do
		for w in ex:gsub("^try: ", ""):gmatch("%S+") do
			if w:sub(1, 1) == "@" then check(ns:ResolveProvider(w:sub(2)) ~= nil, "a known kind: " .. w) end
			if w:find("^%a+:%S") then check(ns.Filters.Parse(w) ~= nil, "a working filter: " .. w) end
		end
	end
	-- in the rotation: yours and the fixed ones, every one of them
	E.Set(true)
	ns.db.easyMode = nil
	local list = E.ExamplePool()
	local yours, inPool = {}, {}
	for _, x in ipairs(list) do inPool[x] = true end
	for _, x in ipairs(E.PersonalExamples(false)) do yours[x] = true end
	local all, want = true, #E.PersonalExamples(false)
	for x in pairs(yours) do if not inPool[x] then all = false end end
	for _, x in ipairs(E.SIMPLE) do
		local shown = x.tip and x[1] or ("try: " .. x[1])
		if E.HasForExample(x[2]) then want = want + 1; if not inPool[shown] then all = false end
		elseif inPool[shown] then all = false end -- (in no group: "who needs fortitude" isn't offered)
	end
	check(all and #list == want, "yours and the fixed ones this setup has, each once: " .. #list .. " of " .. want)

	-- (0.52.1, the player's ask) where you are: the examples for it first (a city: trainers, the mailbox; outside:
	-- quests, dungeons, upgrades; in a dungeon: your group, the loot), the others still offered
	E.rand01 = function() return 0.5 end -- (each one's draw the same: its weight alone orders them)
	local TAG = {}
	for _, x in ipairs(E.SIMPLE) do TAG["try: " .. x[1]] = x[3] end
	for _, x in ipairs(E.PersonalTagged(false)) do TAG["try: " .. x[1]] = x[3] end
	_G.IsInGroup = function() return true end
	for _, where in ipairs({ "city", "field", "instance" }) do
		E.Place = function() return where end
		list = E.ExamplePool()
		local firstOther
		for i, x in ipairs(list) do if TAG[x] ~= where then firstOther = i break end end
		local fits = 0
		for _, x in ipairs(list) do if TAG[x] == where then fits = fits + 1 end end
		check(fits > 0 and firstOther == fits + 1 and #list >= #E.EXAMPLES - 1, where .. ": its " .. fits .. " first, then the others ("
			.. tostring(list[1]) .. ", " .. tostring(list[firstOther]) .. "; " .. #list .. ")")
	end
	-- the place itself: a capital (or a part of one), a dungeon, an inn elsewhere, out in the world
	E.Place = save.place
	local wasMap, wasInst, wasRest = _G.C_Map, _G.IsInInstance, _G.IsResting
	local map, inst, rest = 1454, false, false
	_G.C_Map = { GetBestMapForUnit = function() return map end,
		GetMapInfo = function(m) return m == 1469 and { parentMapID = 1454 } or { parentMapID = 1411 } end }
	_G.IsInInstance = function() return inst, inst and "party" or "none" end
	_G.IsResting = function() return rest end
	check(E.Place() == "city", "Orgrimmar: a city")
	map = 1469
	check(E.Place() == "city", "a part of Orgrimmar (its parent): a city")
	map, rest = 1411, true
	check(E.Place() == "town", "Durotar, resting at an inn: a town")
	rest = false
	check(E.Place() == "field", "Durotar: out in the world")
	inst = true
	check(E.Place() == "instance", "in a dungeon")
	_G.C_Map, _G.IsInInstance, _G.IsResting = wasMap, wasInst, wasRest

	-- (0.52.1, the player's ask) what isn't installed isn't suggested: no Questie, no NPCs; no AtlasLoot, no loot
	E.Place = function() return "city" end
	ns.Integrations.AddonMissing = function(n) return n == "Questie" or n == "AtlasLoot" end
	list = E.ExamplePool()
	local text = table.concat(list, " | ")
	check(not text:find("nearest mailbox", 1, true) and not text:find("nearest warrior trainer", 1, true)
		and not text:find("where is hogger", 1, true) and not text:find("drops from kresh", 1, true)
		and not text:find("shadowfang keep upgrades", 1, true) and text:find("try: my mail", 1, true),
		"no Questie, no AtlasLoot: none of their suggestions: " .. text)
	ns.db.easyMode = false
	E.Set(false)
	local advList = table.concat(E.ExamplePool(), " | ")
	check(not advList:find("@npc", 1, true) and not advList:find("@questie", 1, true) and advList:find("@gold", 1, true),
		"Advanced: no @npc, no @questie without Questie: " .. advList)
	E.Set(true)
	ns.db.easyMode = nil
	ns.Integrations.AddonMissing = function() return false end
	_G.IsInGroup = save.group
	-- every Simple one finds something or at least searches without an error (the fixed ones too)
	for _, x in ipairs(E.SIMPLE) do if not x.tip then yours["try: " .. x[1]] = true end end
	for x in pairs(yours) do
		local ok, err = pcall(UI.Search, UI, x:gsub("^try: ", ""))
		check(ok, "searchable: " .. x .. " " .. tostring(err))
	end
	ns.db.easyMode = false
	_G.UnitLevel, _G.UnitClass, _G.GetRealZoneText, _G.IsInGuild, E.rand = save.lvl, save.cls, save.zone, save.guild, save.rand
	ns.Integrations.AddonMissing, E.rand01, E.Place, _G.IsInGroup = save.missing, save.rand01, save.place, save.group
end)

Run("a pinned row (no score) sorts without an error, first", function()
	local note = ns.NoteRow("a line saying something")
	local rows = { { name = "Console settings", _score = 1, key = 1 }, note, { name = "B", _score = 3, key = 2 } }
	local ok, err = pcall(table.sort, rows, UI._Better)
	check(ok and rows[1] == note, "a note row sorts first: " .. tostring(err))
end)

Run("right-click menu", function()
	E.Set(true)
	ActionLists()
	UI:Open("hearthstone")
	check(UI.Results()[1] and UI.Results()[1].name == "Hearthstone", "(found)")
	UI.rows[1].scripts.OnClick(UI.rows[1], "RightButton")
	local m = _G.TerminalRowMenu
	check(m and m:IsShown() and UI:IsShown(), "right-click: the menu, the terminal stays")
	local labels = {}
	for _, b in ipairs(m.lines) do if b:IsShown() then labels[#labels + 1] = b.fs:GetText() end end
	local all = table.concat(labels, ",")
	check(all == "Show in bags,Use,Link in chat,Say in chat,Copy as text,Why is this here?,Report a problem with this result,Cancel", "its actions in words (0.55.12: copied as text here, not from the send button): " .. all)
	local use = m.lines[2]
	check(use.attrs.type1 == "macro" and use.attrs.macrotext1 == "/use item:6948", "Use: the game runs /use on the click: " .. tostring(use.attrs.macrotext1))
	use.scripts.PostClick(use, "LeftButton"); FlushAll()
	check(not m:IsShown() and not UI:IsShown(), "after it: menu and terminal gone")
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	m.lines[6].scripts.PostClick(m.lines[6], "LeftButton")
	check(not m:IsShown() and UI:IsShown(), "Cancel: only the menu goes")
	-- (review, 0.53.6) a chat line with nothing to send: said so, the terminal stays (nothing was pressed)
	do
		local lineWas, printWas, said = ns.Share.ChatLine, ns.Print, nil
		ns.Share.ChatLine = function() return nil end
		ns.Print = function(_, msg) said = msg end
		UI:ShowRowMenu(1)
		local sayLine = m.lines[4]
		sayLine.scripts.PreClick(sayLine, "LeftButton")
		sayLine.scripts.PostClick(sayLine, "LeftButton")
		check(UI:IsShown() and said and said:find("Hearthstone", 1, true), "nothing to send: said, the terminal stays: " .. tostring(said))
		ns.Share.ChatLine, ns.Print = lineWas, printWas
	end
	UI:ShowRowMenu(1)
	key("DOWN")
	check(not m:IsShown(), "a key closes it")
	-- Shift+Right in Simple mode: the menu, by the row, driven by the keyboard (never Advanced syntax in the prompt)
	local F = _G.TerminalFrame
	local function shiftRight()
		_G.IsShiftKeyDown = function() return true end
		F.scripts.OnKeyDown(F, "RIGHT")
		_G.IsShiftKeyDown = function() return false end
	end
	UI:UpdateTooltip()
	local tipWas = _G.TerminalTooltip and _G.TerminalTooltip:IsShown()
	shiftRight()
	check(m:IsShown() and UI.edit:GetText() == "hearthstone", "Simple: Shift+Right opens the menu, the prompt untouched: " .. UI.edit:GetText())
	check(m.lastPoint and (m.lastPoint[2] == UIParent or m.lastPoint[2] == nil),
		"the menu is placed against UIParent, never anchored to Terminal's row (a secure frame anchored to it made it protected: Enter stopped reaching the game)")
	check(tipWas and not _G.TerminalTooltip:IsShown(), "the row's tooltip goes while the menu is up (both sit beside the terminal)")
	UI:UpdateTooltip()
	check(not _G.TerminalTooltip:IsShown(), "and stays away (hovering a row asks for it again)")
	check(m.lines[1].hl:IsShown() and not m.lines[2].hl:IsShown(), "its first line picked")
	key("DOWN")
	check(m:IsShown() and m.lines[2].hl:IsShown() and not m.lines[1].hl:IsShown(), "Down: the next line, the menu stays")
	key("UP"); key("UP")
	check(m.lines[8].hl:IsShown(), "Up from the first: round to the last (Cancel)")
	key("ESCAPE")
	check(not m:IsShown() and UI:IsShown(), "Esc: only the menu goes")
	check(_G.TerminalTooltip:IsShown(), "and the tooltip comes back")
	-- Enter: armed for this very press, as Terminal's own Enter is, with the press let through ONCE (in the game,
	-- binding ahead of the press never fired, and a false-then-true propagate seemed to lose it)
	local function enter()
		local calls = {}
		local was = F.SetPropagateKeyboardInput
		F.SetPropagateKeyboardInput = function(_, v) calls[#calls + 1] = v end
		ns.Secure.Disarm()
		key("ENTER")
		F.SetPropagateKeyboardInput = was
		local px = ns.Secure.armed == "MACROUP" and _G.TerminalMacroProxyUp or _G.TerminalMacroProxy
		ns.ranMacro = (ns.Secure.armed == "MACRO" or ns.Secure.armed == "MACROUP") and px and px.attrs.macrotext or nil
		ns.ranOn = ns.Secure.armed
		return calls
	end
	shiftRight(); key("DOWN")
	local calls = enter()
	check(#calls == 1 and calls[1] == true and ns.ranMacro == "/use item:6948" and not m:IsShown(),
		"Enter on Use: armed for the press, let through once, menu gone: " .. tostring(ns.ranMacro) .. " " .. #calls)
	UI:Hide(); FlushAll()
	-- the list rebuilt while the menu is open (friends' Battle.net updates come every few seconds): still runs
	UI:Open("hearthstone")
	shiftRight(); key("DOWN")
	local before = UI.Results()[1]
	ns.providers.items._dirty = true
	UI.searchedText = nil
	UI:Refresh(); FlushAll()
	check(UI.Results()[1] ~= before and UI.Results()[1].name == "Hearthstone" and m:IsShown(), "(the row is a new table now, the menu still up)")
	enter()
	check(ns.ranMacro == "/use item:6948", "Enter still runs the line on the rebuilt list")
	UI:Hide(); FlushAll()
	UI:Open("hearthstone")
	shiftRight(); key("DOWN"); key("DOWN"); key("DOWN")
	calls = enter()
	check(m.lines[4].fs:GetText() == "Say in chat" and tostring(ns.ranMacro):match("^/s ") and tostring(ns.ranMacro):find("|Hitem:6948", 1, true)
		and #calls == 1 and calls[1] == true and ns.ranOn == "MACRO", "Enter on Say in chat: the game sends it on this press, as the click does: " .. tostring(ns.ranMacro))
	UI:Hide(); FlushAll()
	-- "Link in chat": the game opens the chat box with it a moment later (Terminal's own call tainted the chat box,
	-- and macros the game ran afterwards stopped working), from the keyboard and from a click
	UI:Open("hearthstone")
	shiftRight(); key("DOWN"); key("DOWN")
	calls = enter()
	check(m.lines[3].fs:GetText() == "Link in chat" and tostring(ns.ranMacro):find("ChatFrame_OpenChat", 1, true)
		and tostring(ns.ranMacro):find("\\124Hitem:6948", 1, true) and #calls == 1, "Link in chat from the keyboard: a line the game runs: " .. tostring(ns.ranMacro))
	UI:Hide(); FlushAll()
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	local link = m.lines[3]
	link.scripts.PreClick(link, "LeftButton")
	check(link.attrs.type1 == "macro" and tostring(link.attrs.macrotext1):find("ChatFrame_OpenChat", 1, true), "Link in chat by click: the game runs it too: " .. tostring(link.attrs.macrotext1))
	local lic, used = ns.LinkInChat, false
	ns.LinkInChat = function() used = true end
	link.scripts.PostClick(link, "LeftButton"); FlushAll()
	ns.LinkInChat = lic
	check(not used and not UI:IsShown(), "and Terminal's code never opens the chat box itself")
	UI:Open("hearthstone")
	shiftRight(); key("UP"); calls = enter()
	check(not m:IsShown() and UI:IsShown() and #calls == 1 and calls[1] == false, "Enter on Cancel: only the menu goes")
	shiftRight(); key("a")
	check(not m:IsShown() and UI:IsShown(), "any other key closes it")
	UI:Hide()
	-- Advanced mode: write into the prompt too
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	labels = {}
	for _, b in ipairs(m.lines) do if b:IsShown() then labels[#labels + 1] = b.fs:GetText() end end
	check(table.concat(labels, ","):find("Write into the prompt", 1, true), "Advanced: Write into the prompt: " .. table.concat(labels, ","))
	UI:HideRowMenu()
end)

Run("right-click: send to chat (Simple mode too)", function()
	E.Set(true)
	ActionLists()
	local saved = { _G.IsInGroup, _G.IsInRaid, _G.IsInGuild, _G.UnitIsPlayer, _G.UnitIsUnit, _G.UnitName, _G.LE_PARTY_CATEGORY_INSTANCE, _G.LE_PARTY_CATEGORY_HOME }
	_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
	_G.IsInGroup = function(c) return c ~= 2 end
	_G.IsInRaid = function() return false end
	_G.IsInGuild = function() return true end
	_G.UnitIsPlayer = function(u) return u == "target" end
	_G.UnitIsUnit = function() return false end
	-- (0.56.3, the player: "/w %t" whispered no one on WoW Forever, and "Whisper Fatherless" read as a friend's name)
	-- by name, the surname joined the game's way
	local rune, constsWas = _G.RegionalUniqueNamesEnabled, _G.Constants
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.Constants = setmetatable({ CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }, { __index = constsWas })
	_G.UnitName = function(u) if u == "target" then return "Fatherless", "Behavior" end return "Me" end
	UI:Open("hearthstone")
	local textWas, baseWas, texts = ns.Share.Text, ns.Share.BaseText, 0
	ns.Share.Text = function(...) texts = texts + 1 return textWas(...) end
	ns.Share.BaseText = function(...) texts = texts + 1 return baseWas(...) end
	UI:ShowRowMenu(1)
	ns.Share.Text, ns.Share.BaseText = textWas, baseWas
	check(texts == 0, "opening the menu works out no chat text (an NPC's would move your map pin): " .. texts)
	local m = _G.TerminalRowMenu
	local byLabel, labels = {}, {}
	for _, b in ipairs(m.lines) do if b:IsShown() then byLabel[b.fs:GetText()] = b; labels[#labels + 1] = b.fs:GetText() end end
	local all = table.concat(labels, ",")
	local wl = ns.L["Whisper to target (%s)"]:format("Fatherless Behavior")
	check(all == "Show in bags,Use,Link in chat,Say in chat,Send to party,Send to guild," .. wl .. ",Copy as text,Why is this here?,Report a problem with this result,Cancel", "the channels you're in: " .. all)
	local g, w = byLabel["Send to guild"], byLabel[wl]
	check(g and (g.attrs.macrotext1 or "") == "", "nothing worked out (no waypoint moved) until a line is clicked")
	if g then g.scripts.PreClick(g, "LeftButton") end
	if w then w.scripts.PreClick(w, "LeftButton") end
	check(g and g.attrs.type1 == "macro" and g.attrs.macrotext1:match("^/g ") and g.attrs.macrotext1:find("|Hitem:6948", 1, true), "guild: the game presses /g with the link: " .. tostring(g and g.attrs.macrotext1))
	check(w and w.attrs.macrotext1:match("^/w Fatherless Behavior |"), "whisper: to the target by name and surname: " .. tostring(w and w.attrs.macrotext1))
	_G.RegionalUniqueNamesEnabled, _G.Constants = rune, constsWas
	local mark = #log
	g.scripts.PostClick(g, "LeftButton"); FlushAll()
	check(not m:IsShown() and not UI:IsShown(), "sent: menu and terminal gone")
	check(not logHas("CHAT", mark + 1), "Terminal's code sent nothing itself")
	-- solo, no guild, no target: say only
	_G.IsInGroup = function() return false end
	_G.IsInGuild = function() return false end
	_G.UnitIsPlayer = function() return false end
	check(#ns.Share.MenuChannels() == 1 and ns.Share.MenuChannels()[1].cmd == "/s", "solo: say only")
	_G.IsInRaid = function() return true end
	_G.IsInGroup = function() return true end
	local chs = ns.Share.MenuChannels()
	check(chs[2] and chs[2].cmd == "/raid" and chs[3] and chs[3].cmd == "/i", "raid replaces party; instance group too: " .. tostring(chs[2] and chs[2].cmd))
	-- context from a Simple search: "nearest innkeeper" reads as the Advanced line would
	local line = ns.Share.Line({ npcID = 1, name = "Innkeeper Allison" }, E.ToAdvanced("nearest innkeeper"))
	check(line and line:match("^Nearby innkeeper: Innkeeper Allison"), "Simple context: " .. tostring(line))
	_G.IsInGroup, _G.IsInRaid, _G.IsInGuild, _G.UnitIsPlayer, _G.UnitIsUnit, _G.UnitName, _G.LE_PARTY_CATEGORY_INSTANCE, _G.LE_PARTY_CATEGORY_HOME = unpack(saved, 1, 8)
	UI:Hide(); FlushAll()
end)

-- (0.54.1, the player's call: "we don't need .simple and .advanced anymore; we just start simple and have it switch to
-- advanced when syntax used") one mode: no .advanced, .simple or their other names; Advanced for good, saved from
-- before, dropped at load; .help in plain sentences, .help advanced the commands and the syntax
Run("one mode: no .advanced or .simple", function()
	E.Set(true)
	for _, name in ipairs({ "advanced", "hardmode", "hard", "simple", "easymode", "easy" }) do
		check(ns:FindCommand(name) == nil, "no ." .. name)
	end
	-- a saved Advanced-for-good from before: dropped as the addon loads
	local db = ns.db
	TerminalDB = { easyMode = false, advancedAsked = true }
	local ef = T.ef
	ef:GetScript("OnEvent")(ef, "ADDON_LOADED", "Terminal")
	check(TerminalDB.easyMode == nil and TerminalDB.advancedAsked == nil and E.On(), "Advanced for good, from before: Simple now")
	TerminalDB = db
	ns.db = db
	-- .help: plain sentences (no ">"), .help advanced the commands and the syntax
	local help = ns.commands.help.run("", ns)
	check(help[1]:find("type the name of anything", 1, true) and not table.concat(help, " "):find("lvl:", 1, true)
		and not table.concat(help, " "):find(">", 1, true), ".help: plain sentences")
	help = ns.commands.help.run("advanced", ns)
	check(help[1] == "Terminal commands:" and table.concat(help, " "):find("lvl:", 1, true), ".help advanced: the commands and the syntax")
end)

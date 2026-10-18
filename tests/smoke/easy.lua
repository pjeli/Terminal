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
	check(E.ToAdvanced("innkeeper nearby") == "@npc is:innkeeper faction:friendly sort:nearest ", "Alt+` writes innkeeper nearby as sort:nearest: " .. E.ToAdvanced("innkeeper nearby"))
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
	-- "skinner", "weapon master": a profession's trainers, the weapon masters; the nearest (Questie's titles)
	check(E.ToAdvanced("skinner"):find("trainer:skinning", 1, true) and E.ToAdvanced("skinner"):find("sort:nearest", 1, true),
		"skinner: the nearest skinning trainer: " .. E.ToAdvanced("skinner"))
	check(E.ToAdvanced("weapon master"):find("is:weaponmaster", 1, true) and E.ToAdvanced("weapon master"):find("sort:nearest", 1, true),
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
	check(E.ToAdvanced("the nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:nearest ",
		"Alt+`, the nearest innkeeper: " .. E.ToAdvanced("the nearest innkeeper"))
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
	check(all == "Show in bags,Use,Link in chat,Say in chat,Copy as text,Cancel", "its actions in words (0.55.12: copied as text here, not from the send button): " .. all)
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
	check(m.lines[6].hl:IsShown(), "Up from the first: round to the last (Cancel)")
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
	check(all == "Show in bags,Use,Link in chat,Say in chat,Send to party,Send to guild," .. wl .. ",Copy as text,Cancel", "the channels you're in: " .. all)
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

Run("reopening: no flash of the last results; Down brings them back", function()
	for _, mode in ipairs({ true, false }) do
		local name = mode and "Simple" or "Advanced"
		E.Set(mode); ns.db.easyMode = mode
		Lists()
		UI:Open("sword")
		local fr = _G.TerminalFrame
		local tall = fr.h
		check(#UI.Results() > 0 and not UI.bare, name .. ": a search lists rows")
		UI:Hide(); FlushAll()
		-- the game may report SetText's change a frame later: Open must not wait for it
		local edit = UI.edit
		local realSet = edit.SetText
		edit.SetText = function(self, s) self.text = s or ""; C_Timer.After(0, function() local f = self.scripts.OnTextChanged; if f then f(self) end end) end
		local realShow = fr.Show
		local atShow
		fr.Show = function(self, ...) atShow = self.h; return realShow(self, ...) end
		UI:Open()
		fr.Show = nil
		check(atShow and atShow < tall, name .. ": the frame is already the bare prompt when it shows: " .. tostring(atShow) .. " (was " .. tostring(tall) .. ")")
		check(#UI.Results() == 0 and UI.bare, name .. ": nothing listed at once, not a frame later")
		FlushAll()
		edit.SetText = nil
		check(rawget(edit, "SetText") == nil and edit.SetText ~= nil, "(mock restored)")
		check(UI.edit:GetText() == "" and UI.bare, name .. ": reopened as just the prompt")
		if mode then
			key("DOWN")
			check(UI.edit:GetText() == "sword" and #UI.Results() > 0, name .. ": Down brings the last search back: " .. UI.edit:GetText())
		end
		UI:Hide(); FlushAll()
	end
	-- a category picked in Simple mode comes back with it
	E.Set(true); ns.db.easyMode = true
	Lists()
	In("spells", "sword")
	UI:Hide(); FlushAll()
	UI:Open()
	key("DOWN")
	check(UI.edit:GetText() == "sword" and UI.category == "spells", "Simple: the category comes back too: " .. tostring(UI.category))
	key("UP")
	check(UI.edit:GetText() == "" and UI.bare, "Up on its first row: put away, just the prompt")
	UI:Hide(); FlushAll()
	-- a .command isn't a search to bring back
	UI.lastQuery = nil
	UI:Open(".help"); UI:Hide(); FlushAll()
	check(UI.lastQuery == nil, "a .command isn't kept as the last search")
	-- (0.50.7, review) closed by the game (a window a press opened), not by Terminal: the search is kept all the same
	UI:Open("frostbolt"); FlushAll()
	UI.frame:Hide(); UI.frame.scripts.OnHide(UI.frame); FlushAll()
	UI:Hide(); FlushAll()
	check(UI.lastQuery == "frostbolt", "closed by the game: kept for Down: " .. tostring(UI.lastQuery))

	-- Advanced: Down shows your recent picks (even with a last search), Up the last line run
	ns.db.easyMode = false; UI:EasyChanged()
	ns:Bump("items:1")
	UI:Open("sword"); UI:Hide(); FlushAll()
	UI:Open()
	check(UI:Suggestion() == nil and UI.bare, "Advanced: the bare prompt")
	key("DOWN")
	check(UI.edit:GetText() == "" and #UI.Results() > 0 and UI.Results()[1].name == "Rare Sword", "Advanced: Down shows your recent picks: " .. Show(UI.Results()))
	key("UP")
	check(UI.edit:GetText() == "" and #UI.Results() == 0 and UI.bare, "Up on the first of them: back to just the prompt")
	UI:Hide(); FlushAll()
	local saveH = ns.db.history
	ns.db.history = { ".about" }
	UI:Open(); key("UP")
	check(UI.edit:GetText() == ".about", "Advanced: Up brings the last line run: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	ns.db.history = {}
	UI:Open(); key("UP")
	check(UI.edit:GetText() == "", "no lines run: Up does nothing")
	ns.db.history = saveH
	ns.db.recent = {}
end)

Run("release review fixes", function()
	E.Set(true)
	ActionLists()
	-- everyday words match a name's word start, not inside a word: "ah" isn't Sarah, "inn" isn't Finn
	local function NameRow(n) return { name = n, _lname = n:lower(), kind = "x" } end
	check(not E.Word("ah")(NameRow("Sarah Shahram")) and not E.Word("inn")(NameRow("Finn")), "ah / inn don't match inside names")
	check(not E.Word("ring")(NameRow("Red Herring")) and E.Word("ring")(NameRow("Ring of Valor")), "ring: a word start (not Herring)")
	check(E.Word("sword")(NameRow("Swordsmith Ivan")), "sword still finds Swordsmith (a word start)")
	-- an action word with nothing to do it to says so (it collapsed to the bare prompt)
	UI:Open("use xyzzyq")
	local r = UI.Results()
	check(r[1] and r[1].noActivate and not UI.bare, "use xyzzy: a line says nothing has that: " .. Show(r))
	UI:Hide(); FlushAll()
	-- an action view never falls back to the row's own Enter (no secondary function: false, not nil)
	local view = E.ActionView({ kind = "items", name = "X", activate = function() return "primary" end, secondarySecure = { macro = "/use x" } },
		{ map = { items = "s" }, label = "use" })
	check(view.activate == false, "action view: activate false when the row has only a secure secondary")
	-- the right-click menu goes when combat starts (its secure lines can't be hidden once it's on)
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	local m = _G.TerminalRowMenu
	check(m:IsShown(), "(menu shown)")
	m.scripts.OnEvent(m, "PLAYER_REGEN_DISABLED")
	check(not m:IsShown(), "combat starts: the menu goes")
	UI:Hide(); FlushAll()
	-- the sort:nearest note doesn't outlive its search
	UI.noPosition = true
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Search("hearthstone")
	check(not UI.noPosition, "the no-position note is reset by the next search")
end)

Run("Alt+`: Advanced mode for this run only", function()
	E.Set(true)
	ActionLists()
	local F = T.F
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	-- what a Simple search says, in Advanced syntax
	-- (0.55.18: a kind of item said as a word is that kind or the word in a name, sword|type:sword, as searched)
	check(E.ToAdvanced("rare sword") == "q:rare sword|type:sword ",
		"rare sword -> filters: " .. E.ToAdvanced("rare sword"))
	check(E.ToAdvanced("attack power food") == "stat:ap food|type:food ", "attack power food -> stat:ap type:food: " .. E.ToAdvanced("attack power food"))
	check(E.ToAdvanced("cast frost nova") == "@spell do:cast frost nova ", "cast frost nova -> @spell do:cast (0.44.11: the action stays): " .. E.ToAdvanced("cast frost nova"))
	check(E.ToAdvanced("nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:nearest ",
		"nearest innkeeper -> @npc ... sort:nearest: " .. E.ToAdvanced("nearest innkeeper"))
	check(E.ToAdvanced("hearthstone", "bags") == "@item hearthstone ", "a picked category -> its @kind: " .. E.ToAdvanced("hearthstone", "bags"))
	check(E.ToAdvanced("shield that drops from kresh") == "kresh shield|type:shield ", "sentence words dropped: " .. E.ToAdvanced("shield that drops from kresh"))
	check(E.ToAdvanced("") == "", "nothing typed: nothing")
	-- Alt+` in an open Simple prompt: written in Advanced syntax, searched as Advanced
	UI:Open("cast frost nova")
	alt(function() key("`", "`") end) -- (the key's character comes after it, as in the game)
	check(UI:IsShown() and T.query() == "@spell do:cast frost nova " and not E.On() and E.temp, "Alt+`: the prompt is Advanced now: " .. T.query())
	check(UI.ONCE_LABEL == ns.L["Advanced"], "the footer says Advanced (0.55.17: not \"Advanced, this time\"): " .. tostring(UI.ONCE_LABEL))
	local r = UI.Results()
	check(r[1] and r[1].name == "Frost Nova" and r[1].actionVerb == "cast", "searched as Advanced: the spell, Enter still casts it: " .. Show(r))
	key("A", "a")
	check(T.query() == "@spell do:cast frost nova a", "typing goes on after it (only the switch's ` was dropped): " .. T.query())
	key("BACKSPACE")
	check(ns.db.easyMode == true, "the saved mode stays Simple")
	-- closing gives Simple back, and Down brings back what the Simple prompt said
	UI:Hide(); FlushAll()
	check(E.On() and not E.temp, "closed: Simple again")
	UI:Open(""); key("DOWN")
	check(T.query() == "cast frost nova", "Down: the Simple search, not the Advanced one: " .. T.query())
	UI:Hide(); FlushAll()
	-- closed: the binding opens it as ` does (0.54.3, the player: one mode, nothing to open "in Advanced")
	UI:AdvancedOnce()
	check(UI:IsShown() and E.On() and not E.temp, "the binding (closed): opens as ` does, in Simple")
	UI:SetQuery("@spell nova")
	check(UI.Results()[1] and UI.Results()[1].name == "Frost Nova" and E.On(), "Advanced syntax typed: found, Simple kept (0.55.9)")
	UI:Hide(); FlushAll()
	-- (0.55.9, the player: "we lose the ability to go back") Alt+` again: back to the Simple words, the bar's picks too
	UI:Open("cast frost nova")
	ns.Bar.Pick("sort", "name")
	alt(function() key("`", "`") end)
	check(not E.On() and T.query():find("^@spell do:cast frost nova") and not ns.Bar.Active(), "(Alt+`: Advanced)")
	alt(function() key("`", "`") end)
	check(UI:IsShown() and E.On() and not E.temp and T.query() == "cast frost nova" and ns.Bar.state.sort == "name",
		"Alt+` again: the Simple words back, and the bar's sort: " .. T.query())
	-- Shift+Left does it too (the footer says so)
	alt(function() key("`", "`") end)
	check(not E.On() and UI:CanGoBack(), "(Advanced again; Shift+Left can go back)")
	check(UI:GoBack() and E.On() and T.query() == "cast frost nova", "Shift+Left: the Simple words back: " .. T.query())
	-- edited since: the line as it is now, in Simple mode
	alt(function() key("`", "`") end)
	key("SPACE", " "); key("X", "x")
	check(not UI:CanUndoAdvanced(), "edited: Shift+Left doesn't undo Alt+` any more")
	local edited = T.query()
	alt(function() key("`", "`") end)
	check(E.On() and T.query() == edited, "edited, then Alt+`: Simple, the line kept: " .. T.query())
	ns.Bar.Reset()
	-- plain words with nothing Advanced to write: Alt+` leaves the line and the mode as they are
	UI:SetQuery("", 0)
	alt(function() key("`", "`") end)
	check(E.On() and not E.temp and T.query() == "", "an empty line: Alt+` changes nothing: " .. T.query())
	UI:Hide(); FlushAll()
	-- in Advanced for good, Alt+` is just the toggle
	ns.db.easyMode = false
	UI:AdvancedOnce()
	check(UI:IsShown() and not E.temp, "Advanced for good: Alt+` only opens")
	UI:Hide(); FlushAll()
end)

Run("Advanced syntax typed after Simple words: kept as typed, in Simple mode (0.55.9; 0.54.3-0.55.8 rewrote the line)", function()
	E.Set(true)
	ActionLists()
	local function Names() local t = {} for _, e in ipairs(UI.Results()) do if ns.Bar.Real(e) then t[#t + 1] = tostring(e.name) end end return table.concat(t, " | ") end
	UI:Open("")
	UI:SetQuery("cast frost nova", 15); FlushAll()
	local plain = Names()
	UI:SetQuery("cast frost nova >> party", 24); FlushAll()
	check(T.query() == "cast frost nova >> party" and E.On() and UI.sendTo and UI.sendTo.cmd, "cast frost nova >> party: as typed, Simple: " .. T.query())
	check(Names() == plain and UI.Results()[1].actionVerb == "cast", "the same results, Enter still casts: " .. Names())
	UI:Hide(); FlushAll()
	check(E.On() and UI.lastQuery == "cast frost nova >> party", "closed: Down brings the line back as it was: " .. tostring(UI.lastQuery))
	-- a filter typed after the words
	UI:Open("")
	UI:SetQuery("cast frost nova q:rare"); FlushAll()
	check(T.query() == "cast frost nova q:rare" and E.On(), "a key:value after them: as typed: " .. T.query())
	UI:Hide(); FlushAll()
	-- the line starting with it: as it is
	UI:Open("")
	UI:SetQuery("@spell nova"); FlushAll()
	check(T.query() == "@spell nova" and E.On() and UI.Results()[1] and UI.Results()[1].name == "Frost Nova", "@spell nova: as typed")
	UI:Hide(); FlushAll()
	-- a .command, and Simple's own a|b: left alone
	UI:Open("")
	UI:SetQuery("sword|axe"); FlushAll()
	check(T.query() == "sword|axe" and E.On(), "sword|axe: Simple's own")
	UI:Hide(); FlushAll()
end)

Run("Alt+` names the lists the results come from (use hearthstone: @item, not @camp @item @toy)", function()
	E.Set(true)
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	local function Lists(items)
		Use({
			{ "camp", { label = "Camp", aliases = { "camp" }, collect = Rows({ { name = "Campfire", secondary = Fire("craft") } }) } },
			{ "items", { label = "Item", aliases = { "item" }, collect = Rows(items or {
				{ name = "Hearthstone", itemID = 6948, secondary = Fire("use"), secondarySecure = { macro = "/use item:6948" } },
				{ name = "Train Ticket", itemID = 7, secondary = Fire("use") } }) } },
			{ "toys", { label = "Toy", aliases = { "toy" }, explicit = true, collect = Rows({ { name = "Toy Train Set", activate = Fire("toy") } }) } },
			{ "mounts", { label = "Mount", aliases = { "mount" }, collect = Rows({ { name = "Swift Raptor", activate = Fire("summon") } }) } },
			{ "pets", { label = "Pet", aliases = { "pet" }, collect = Rows({ { name = "Mechanical Squirrel", activate = Fire("pet") } }) } },
		})
	end
	Lists()
	local function Converted(text)
		UI:Open(text)
		alt(function() key("`", "`") end)
		local q = T.query()
		UI:Hide(); FlushAll()
		return q
	end
	-- not told what shows: every list the action looks in (as before)
	check(E.ToAdvanced("use hearthstone") == "@camp @item @toy do:use hearthstone ", "(not told what shows: every list) " .. E.ToAdvanced("use hearthstone"))
	check(E.ToAdvanced("use hearthstone", nil, { items = true }) == "@item do:use hearthstone ", "told: only the list the result is in")
	check(E.ToAdvanced("use zzz", nil, {}) == "do:use zzz ", "nothing shows: no @kind, do:use stands for the action's lists")
	-- in the terminal: what the Simple search shows
	local q = Converted("use hearthstone")
	check(q == "@item do:use hearthstone ", "use hearthstone -> only @item (not a camp object, nor a toy): " .. q)
	q = Converted("use train")
	check(q == "@item @toy do:use train ", "two lists show something: both named: " .. q)
	q = Converted("use zzzz")
	check(q == "do:use zzzz ", "nothing found: do:use alone: " .. q)
	q = Converted("summon raptor")
	check(q == "@mount do:summon raptor ", "summon raptor -> @mount (no pet called that): " .. q)
	-- a category opened for you: its lists that show something (Collections has mounts, pets, toys...)
	q = Converted("swift")
	check(q == "@mount swift ", "swift in Collections -> @mount only: " .. q)
	check(E.ToAdvanced("swift", "collections", {}) == "@mount @pet @toy swift ", "a category with nothing showing: all its lists (no one word for them)")
	-- the Advanced search finds what the Simple one did, Enter still uses it
	UI:Open("use hearthstone")
	alt(function() key("`", "`") end)
	local r = UI.Results()
	check(r[1] and r[1].name == "Hearthstone" and r[1].actionVerb == "use", "searched as Advanced: the Hearthstone, Enter uses it: " .. Show(r))
	UI:Hide(); FlushAll()
	-- a search still going over frames when Alt+` comes: finished first, so the lists named are what it found (its
	-- first frame had seen only part of the bags, nothing that matched, and no toys yet)
	local big = {}
	for i = 1, 3000 do big[i] = { name = ("Pebble %04d"):format(i), itemID = 10000 + i } end
	big[#big + 1] = { name = "Train Ticket", itemID = 7, secondary = Fire("use") }
	Lists(big)
	local realClock = _G.debugprofilestop
	local ms = 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end -- every look at the clock: 1 ms
	local budget = UI.FINISH_MS
	UI.FINISH_MS = 1e9 -- (quick enough to finish)
	UI:Open("use train")
	local going = UI.searchJob ~= nil
	alt(function() key("`", "`") end)
	q = T.query()
	FlushAll()
	check(going and q == "@item @toy do:use train ", "a search still going: finished first, then named (" .. tostring(going) .. "): " .. q)
	UI:Hide(); FlushAll()
	-- the same with a category Simple mode opens for you: it's set only once the overview is done (read after it)
	UI:Open("swift")
	going = UI.searchJob ~= nil
	alt(function() key("`", "`") end)
	q = T.query()
	FlushAll()
	check(going and q == "@mount swift ", "a category opened for you while the search still went on: named: " .. q)
	UI:Hide(); FlushAll()
	-- too long to finish at once (the budget spent): not a frame-long hitch, every list the action looks in instead
	UI.FINISH_MS = 0
	UI:Open("use train")
	alt(function() key("`", "`") end)
	q = T.query()
	FlushAll()
	_G.debugprofilestop = realClock
	UI.FINISH_MS = budget
	check(q == "@camp @item @toy do:use train ", "a search too long to finish now: every list the action looks in: " .. q)
end)

Run("pure fuzzy finding (Tab+`): every list, names only, no syntax; Enter to Simple, Shift+Enter with its @kind", function()
	E.Set(true)
	ActionLists()
	local function win(fn) local was = _G.IsKeyDown; _G.IsKeyDown = function(k) return k == "TAB" end; fn(); _G.IsKeyDown = was end
	local function shifted(fn) local was = _G.IsShiftKeyDown; _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = was end
	-- one more list: a row whose words are only in its text, and a copy list (@gear-like) that must not double rows
	ns:RegisterProvider("quests", { label = "Quest", aliases = { "quest" }, collect = Rows({
		{ name = "The Lost Ring", text = "Bring Hogger's claw to the marshal" } }) })
	ns:RegisterProvider("gearcopy", { label = "Gear", aliases = { "gearcopy" }, follows = "items", explicit = true,
		collect = Rows({ { name = "Shiny Sword", quality = 3, itemID = 3 } }) })
	-- Tab+` in an open Simple prompt
	UI:Open("cast frost nova")
	local traceWas, traced = ns.Trace, false
	ns.Trace = function(self, m) if tostring(m):find("key `: alt=false tab=true", 1, true) then traced = true end return traceWas(self, m) end
	win(function() key("`", "`") end)
	ns.Trace = traceWas
	check(UI.fzf and T.query() == "cast frost nova ", "Tab+`: fuzzy finding, the prompt keeps its words: " .. T.query())
	check(UI.glow and UI.glow:IsShown(), "a glow round the prompt bar")
	check((UI.status:GetText() or ""):find("Fuzzy find", 1, true), "the footer says so: " .. tostring(UI.status:GetText()))
	check((UI.hints:GetText() or ""):find("Enter", 1, true), "its own key hints: " .. tostring(UI.hints:GetText()))
	check(traced, "the ` press is traced with its modifiers")
	UI:SetQuery("frost nova", 10)
	local r = UI.Results()
	check(r[1] and r[1].name == "Frost Nova" and not r[1].actionVerb, "Frost Nova found: " .. Show(r))
	-- explicit lists too (NPCs need no @npc), letters in order
	UI:SetQuery("hggr", 4)
	r = UI.Results()
	check(r[1] and r[1].name == "Hogger" and #r == 1, "hggr: Hogger, from a list only searched with @kind elsewhere: " .. Show(r))
	-- names only: a quest's text doesn't match
	UI:SetQuery("marshal", 7)
	check(#UI.Results() == 0, "words in a row's text don't count: " .. Show(UI.Results()))
	-- nothing is syntax: @kinds, filters and sums are plain letters
	UI:SetQuery("@npc hogger", 11)
	check(#UI.Results() == 0, "@npc is just letters: " .. Show(UI.Results()))
	UI:SetQuery("q:rare", 6)
	check(#UI.Results() == 0, "q:rare is just letters (nothing has them): " .. Show(UI.Results()))
	UI:SetQuery("2+2", 3)
	check(#UI.Results() == 0, "no calculator: " .. Show(UI.Results()))
	check(#UI:SyntaxSegments("@npc q:rare >> party") == 1, "the prompt isn't coloured as syntax")
	UI:SetQuery("froost", 6)
	check(#UI.Results() == 0, "no close spellings: " .. Show(UI.Results()))
	-- a row once, even from a copy list
	UI:SetQuery("shiny", 5)
	r = UI.Results()
	check(#r == 1 and r[1].kind == "items", "a copy list (follows another) isn't listed twice: " .. Show(r))
	-- the arrows go through the list, never the history
	ns.db.history = { "@spell frost nova" }
	UI:SetQuery("", 0)
	check(UI.ghost:IsShown() and UI.ghost:GetText() == "fzf", "the empty prompt says fzf: " .. tostring(UI.ghost:GetText()))
	key("UP")
	check(T.query() == "", "Up on the empty prompt: no history line: " .. T.query())
	key("DOWN")
	check(#UI.Results() == 0, "Down on the empty prompt: no recent picks")
	UI:SetQuery("innkeeper", 9)
	check(UI.Selected() == 1 and #UI.Results() == 3, "three innkeepers: " .. Show(UI.Results()))
	key("DOWN"); key("DOWN")
	check(UI.Selected() == 3, "Down moves through them: " .. tostring(UI.Selected()))
	key("UP")
	check(UI.Selected() == 2, "Up moves back: " .. tostring(UI.Selected()))
	key("TAB")
	check(UI.Selected() == 3, "Tab moves too (no categories here): " .. tostring(UI.Selected()))
	-- narrowing letter by letter gives what a fresh search does
	for _, word in ipairs({ "i", "in", "inn", "innk", "innk f", "innk fa" }) do
		UI:SetQuery(word, #word)
		local got = Show(UI.Results())
		local was = UI.lastFzf
		UI.lastFzf = nil
		local fresh = Show(UI:Search(word))
		check(got == fresh, ("'%s': narrowed = fresh (%s / %s)"):format(word, got, fresh))
		UI.lastFzf = was
	end
	ns.db.history = {}
	-- Shift+Right writes the plain name (no @kind)
	UI:SetQuery("hggr", 4)
	shifted(function() key("RIGHT") end)
	check(T.query() == "Hogger ", "Shift+Right: the name only: " .. T.query())
	-- no click catcher over the rows (a click hands over, it never opens)
	UI:PlaceCatcher(1)
	check(not (_G.TerminalClickCatcher and _G.TerminalClickCatcher:IsShown()), "no click catcher in fuzzy finding")
	-- Enter: to Simple mode, in its category, selected; nothing is run or armed
	UI:SetQuery("innkeeper farley", 16)
	key("ENTER")
	check(not UI.fzf and E.On() and T.query() == "Innkeeper Farley " and UI.category == "npcs" and not UI.armedEntry,
		"Enter: to Simple mode, in NPCs: " .. T.query() .. " [" .. tostring(UI.category) .. "]")
	r = UI.Results()
	check(r[UI.Selected()] and r[UI.Selected()].name == "Innkeeper Farley", "the result is selected there: " .. Show(r))
	check(not UI.glow:IsShown(), "the glow goes")
	UI:Hide(); FlushAll()
	-- Shift+Enter: to Advanced mode, "@kind name", for this run only
	UI:Open("")
	win(function() key("`", "`") end)
	check(UI.fzf and T.query() == "", "Tab+` on the empty prompt: fuzzy finding")
	UI:SetQuery("frost", 5)
	shifted(function() key("ENTER") end)
	check(not UI.fzf and E.On() and not E.temp and T.query() == "@spell Frost Nova ", "Shift+Enter: \"@kind name\", Simple kept (0.55.9): " .. T.query())
	r = UI.Results()
	check(r[UI.Selected()] and r[UI.Selected()].name == "Frost Nova", "selected: " .. Show(r))
	check(ns.db.easyMode == true, "the saved mode stays Simple")
	UI:Hide(); FlushAll()
	check(E.On() and not E.temp, "closed: Simple again")
	-- a click is Enter (Shift+click Shift+Enter)
	UI:Open(""); UI:FuzzyOnce()
	UI:SetQuery("raptor", 6)
	UI:Activate(1, {})
	check(not UI.fzf and E.On() and T.query() == "Swift Raptor ", "a click: to Simple: " .. T.query())
	UI:Hide(); FlushAll()
	-- Tab+` in it: the terminal closes (as Alt+` again does), and the next open is the usual mode
	UI:Open("hogger")
	win(function() key("`", "`") end)
	check(UI.fzf, "(fuzzy finding)")
	win(function() key("`", "`") end)
	check(not UI:IsShown() and not UI.fzf and E.On(), "Tab+` again: closes")
	FlushAll()
	UI:FuzzyOnce()
	-- Alt+` in it: out of it; nothing typed, nothing to write in Advanced syntax: Simple (0.54.3: the line picks the mode)
	_G.IsAltKeyDown = function() return true end; key("`", "`"); _G.IsAltKeyDown = function() return false end
	check(not UI.fzf and E.On() and not E.temp, "Alt+` in it: out of it, Simple for an empty line")
	UI:Hide(); FlushAll()
	-- Tab seen by its own key-down (a client where IsKeyDown doesn't answer)
	local was = _G.IsKeyDown
	_G.IsKeyDown = nil
	UI:Open("")
	key("TAB"); key("`", "`")
	check(UI.fzf, "Tab's own key-down counts")
	T.F.scripts.OnKeyUp(T.F, "TAB")
	key("`")
	check(not UI:IsShown(), "let go: ` closes as ever")
	FlushAll()
	-- closed: the toggle key with Tab held opens in fuzzy finding
	win(function() UI:Toggle() end)
	check(UI:IsShown() and UI.fzf, "the toggle binding with Tab held: fuzzy finding")
	UI:Hide(); FlushAll()
	-- IsKeyDown not answering (or secret): ` opens the terminal, then Tab's repeats and its release come
	_G.IsKeyDown = function() return false end
	UI:Toggle()
	check(UI:IsShown() and not UI.fzf and E.On(), "(the toggle key opened it in Simple mode)")
	key("TAB")
	check(not UI.fzf and UI.openedByToggle, "Tab still held right after opening: swallowed (no Tab of its own)")
	T.F.scripts.OnKeyUp(T.F, "TAB")
	check(UI.fzf, "Tab let go right after: it was Tab+`, fuzzy finding now")
	UI:Hide(); FlushAll()
	UI:Toggle()
	key("A", "a")
	T.F.scripts.OnKeyUp(T.F, "TAB")
	check(not UI.fzf, "something typed first: Tab let go later is just that")
	UI:Hide(); FlushAll()
	_G.IsKeyDown = was
	check(not UI.fzf and not UI.glow:IsShown() and E.On() and not E.temp, "closed: over, Simple again")
	-- the frame hidden by something else ends it too
	UI:Open(""); UI:FuzzyOnce()
	local tf = _G.TerminalFrame
	tf:Hide(); tf.scripts.OnHide(tf)
	check(not UI.fzf, "the frame hidden directly: over")
	FlushAll()
	-- .fuzzy [words]: once, from a command
	UI:Open(".fuzzy hggr"); key("ENTER"); FlushAll()
	check(UI:IsShown() and UI.fzf and T.query() == "hggr" and UI.Results()[1] and UI.Results()[1].name == "Hogger",
		".fuzzy hggr: opens fuzzy finding with the words: " .. T.query())
	UI:Hide(); FlushAll()
	-- Advanced for good: Enter takes it to Simple for this run only
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("@npc hogger is:elite >> party")
	UI:FuzzyOnce()
	check(UI.fzf and T.query() == "hogger ", "syntax dropped going in: " .. T.query())
	key("ENTER")
	check(E.On() and E.tempSimple and T.query() == "Hogger ", "Advanced player, Enter: Simple this run: " .. T.query())
	-- Alt+` then (0.44.16): Advanced for this run (it stayed Simple, refusing what it had just written)
	_G.IsAltKeyDown = function() return true end; key("`", "`"); _G.IsAltKeyDown = function() return false end
	local top = UI.Results()[1]
	check(not E.On() and not E.tempSimple and T.query():lower():find("hogger", 1, true) and top ~= E.ADVANCED_ROW,
		"handed over to Simple, then Alt+`: Advanced this run: " .. T.query() .. " / " .. tostring(top and top.name))
	UI:Hide(); FlushAll()
	check(not E.On() and not E.tempSimple and not E.temp, "closed: Advanced again")
	check(UI.FuzzyPlain(".help") == "" and UI.FuzzyPlain("sword|axe -boe rare sort:nearest") == "rare ", "plain words kept: " .. UI.FuzzyPlain("sword|axe -boe rare sort:nearest"))
end)

Run("Up walks every line run, whatever mode ran it (0.54.3: one mode)", function()
	E.Set(true)
	ActionLists()
	ns.db.history = {}
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	UI:Open("shiny sword"); key("ENTER"); UI:Hide(); FlushAll()
	-- an Alt+` run
	UI:Open("cast frost nova"); alt(function() key("`", "`") end)
	check(T.query() == "@spell do:cast frost nova ", "(Advanced this run)")
	UI:Activate(1); UI:Hide(); FlushAll()
	check(ns.db.history[1] == "@spell do:cast frost nova", "the Advanced line is in the history: " .. tostring(ns.db.history[1]))
	-- Up: it, then the Simple one; brought back, it runs in Advanced again by itself
	UI:Open(""); key("UP")
	check(T.query() == "@spell do:cast frost nova" and E.On(), "Up: the Advanced line, searched as it is (Simple kept): " .. T.query())
	key("UP")
	check(T.query() == "shiny sword", "Up again: the Simple one: " .. T.query())
	UI:Hide(); FlushAll()
	-- closed Alt+`: the same prompt and the same Up as `
	local function Seen(open)
		open(); local first = T.query(); key("UP"); local up = T.query()
		UI:Hide(); FlushAll()
		return first .. " / " .. up
	end
	local tick = Seen(function() UI:Toggle() end)
	local altTick = Seen(function() UI:AdvancedOnce() end)
	check(altTick == tick and tick:find("shiny sword", 1, true), "opened with Alt+`: as with `: " .. altTick .. " = " .. tick)
	ns.db.history = {}
end)

Run("typing on narrows from the last keystroke's matches, with the same results", function()
	E.Set(true)
	Lists()
	local function Sig(res)
		local t = {}
		for i, e in ipairs(res) do t[i] = tostring(e.name) .. "|" .. tostring(e.detail) .. "|" .. tostring(e.catId) end
		return table.concat(t, " ; ")
	end
	local reused = 0
	for _, phrase in ipairs({ "sword", "sword sp", "rare sword", "thunder", "s" }) do
		UI:Open("")
		for k = 1, #phrase do
			local part = phrase:sub(1, k)
			UI:SetQuery(part, #part)
			local got = Sig(UI.Results())
			if UI.lastSearchNarrowed then reused = reused + 1 end
			-- the same search from scratch (then the narrowing state put back for the next letter)
			local scanWas, ovWas, catWas, autoWas = UI.lastScan, UI.lastExtra, UI.category, UI.categoryAuto
			UI.lastScan, UI.lastExtra = nil, nil
			if autoWas then UI.category, UI.categoryAuto = nil, nil end
			local fresh = Sig(UI:Search(part))
			check(got == fresh, ("'%s': narrowed = fresh (%s / %s)"):format(part, got, fresh))
			UI.lastScan, UI.lastExtra, UI.category, UI.categoryAuto = scanWas, ovWas, catWas, autoWas
		end
		UI:Hide(); FlushAll()
	end
	check(reused > 0, "the overview did reuse the last keystroke's matches: " .. reused)
	-- a list rebuilt between keystrokes: its new rows are found (not the old matches)
	UI:Open(""); UI:SetQuery("sw", 2)
	local p = ns.providers.keybinds
	p.collect = Rows({ { name = "Sheathe Sword" }, { name = "Swap Weapons" } })
	p._dirty = true
	UI:SetQuery("swa", 3)
	check(Sig(UI.Results()):find("Swap Weapons", 1, true) or Sig(UI.Results()):find("Keybind", 1, true), "a list rebuilt meanwhile is scanned in full: " .. Sig(UI.Results()))
	UI:Hide(); FlushAll()
end)

Run("Alt+` ends with the terminal however it closes; Up's history line runs as it is", function()
	E.Set(true)
	ActionLists()
	-- the frame hidden by something else (a window the press opened closes it): Simple again all the same
	UI:Open("cast frost nova")
	UI:AdvancedOnce()
	check(E.temp and not E.On(), "(Advanced this run)")
	local tf = _G.TerminalFrame
	tf:Hide(); tf.scripts.OnHide(tf) -- (as UISpecialFrames / a window opening does, not through UI:Hide)
	check(E.temp == nil and E.On(), "the frame hidden directly: Simple again")
	check(UI.lastQuery == "cast frost nova", "and Down brings back the Simple search: " .. tostring(UI.lastQuery))
	FlushAll()
	-- Advanced syntax typed: a Simple search like any (0.55.9): Down brings it back
	UI.lastQuery = "old simple search"
	UI:Open("")
	UI:SetQuery("@spell nova", 11)
	UI:Hide(); FlushAll()
	check(UI.lastQuery == "@spell nova", "Advanced syntax typed: Down brings it back: " .. tostring(UI.lastQuery))
	-- Advanced: a history line ending in a filter runs, it isn't a pick list
	ns.db.easyMode = false; UI:EasyChanged()
	ns.db.history = { "@spell is:passive" }
	UI:Open(""); T.key("UP")
	check(T.query() == "@spell is:passive" and not (UI.Results()[1] and UI.Results()[1].syntaxRow), "Up's line is searched, not a pick list")
	UI:Hide(); FlushAll()
	ns.db.history = {}
end)

Run("stamina food right after login: found once the game has loaded the food's text", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	local save = { info = C_Item.GetItemInfo, inst = C_Item.GetItemInfoInstant, spell = C_Item.GetItemSpell,
		desc = C_Spell.GetSpellDescription, stats = C_Item.GetItemStats, cached = C_Spell.IsSpellDataCached, now = _G.GetTime }
	local loaded = false
	local clock = 1000
	_G.GetTime = function() return clock end
	C_Item.GetItemInfo = function(id) if id == 201 then return "Spiced Wolf Ribs", "|Hitem:201|h", 1, 15, 10, "Consumable", "Food & Drink" end end
	C_Item.GetItemInfoInstant = function(id) return id, "Consumable", "Food & Drink", "", 1, 0, 0 end
	C_Item.GetItemSpell = function(id) return "spell", 6201 end
	-- the spell's text isn't in yet at first (the game is still loading it)
	C_Spell.GetSpellDescription = function() return loaded and "Restores 552 health. Well fed: gain 6 Stamina and Spirit for 15 min." or "" end
	C_Spell.IsSpellDataCached = function() return loaded end
	C_Item.GetItemStats = function() return {} end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Spiced Wolf Ribs", itemID = 201 } }) } } })
	-- the prewarm asks for your bags' consumables' text ahead of any search
	local asked, reqWas = 0, C_Spell.RequestLoadSpellData
	C_Spell.RequestLoadSpellData = function() asked = asked + 1 end
	check(F.WarmEffects(ns:GetEntries(ns.providers.items)) == 1 and asked == 1 and not F.loading, "the bags' food has its text asked for ahead of the search")
	C_Spell.RequestLoadSpellData = reqWas
	clock = clock + 2 -- (past the wait the warm-up set)
	UI:Open("stamina food")
	local first = UI.Results()
	check(not Has(first, "Spiced Wolf Ribs"), "(the food's text still loading: not yet)")
	-- the text comes in: the same search runs again by itself, from scratch
	loaded = true
	clock = clock + 2
	FlushAll()
	local res = UI.Results()
	check(Has(res, "Spiced Wolf Ribs") or (res[1] and res[1].catId == "bags"), "once loaded, the food shows without typing again: " .. Show(res))
	UI:Hide(); FlushAll()
	-- Advanced, with a ">> party" after the search: the retry still fires (the prompt isn't the searched text)
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
	loaded = false
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("stat:stamina type:food >> party")
	clock = clock + 0.01; T.Flush() -- (the refresh the opening queued for the next frame runs now, while still loading)
	check(not Has(UI.Results(), "Spiced Wolf Ribs"), "(Advanced: still loading)")
	loaded = true
	clock = clock + 2
	FlushAll()
	check(Has(UI.Results(), "Spiced Wolf Ribs"), "Advanced with >>: found once loaded: " .. Show(UI.Results()))
	UI:Hide(); FlushAll()
	E.Set(true)
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemSpell = save.info, save.inst, save.spell
	C_Spell.GetSpellDescription, C_Item.GetItemStats, C_Spell.IsSpellDataCached, _G.GetTime = save.desc, save.stats, save.cached, save.now
	F.ClearCache(); if F.ClearEffects then F.ClearEffects() end
end)

Run("helmet among the loot: every helmet; helm upgrades: the ones that suit you (level, class, item level)", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache()
	local save = { info = C_Item.GetItemInfo, level = _G.UnitLevel, inv = _G.GetInventoryItemLink, can = C_PlayerInfo.CanUseItem,
		det = C_Item.GetDetailedItemLevelInfo }
	local ITEMS = {
		[1] = { "Good Helm", "|Hitem:1|h", 2, 24, 18, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[2] = { "Future Helm", "|Hitem:2|h", 3, 40, 35, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[3] = { "Old Cap", "|Hitem:3|h", 1, 8, 3, "Armor", "Cloth", 1, "INVTYPE_HEAD" },
		[4] = { "Plate Helm", "|Hitem:4|h", 2, 25, 20, "Armor", "Plate", 1, "INVTYPE_HEAD" },
		[5] = { "Great Helm", "|Hitem:5|h", 4, 30, 22, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[9] = { "Worn Hood", "|Hitem:9|h", 2, 20, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
	}
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetDetailedItemLevelInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)")); return ITEMS[id] and ITEMS[id][4] end
	_G.UnitLevel = function() return 21 end
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9|h[Worn Hood]|h" end end
	C_PlayerInfo.CanUseItem = function(id) return id ~= 4 end -- (plate: not for you)
	local function L(name, id) return { name = name, itemID = id, detail = "Boss  Dungeon", _ltext = "dungeon boss loot drop atlasloot" } end
	Use({ { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
		L("Good Helm", 1), L("Future Helm", 2), L("Old Cap", 3), L("Plate Helm", 4), L("Great Helm", 5) }) } } })
	ITEMS[6] = { "Kraul Helm", "|Hitem:6|h", 2, 26, 20, "Armor", "Leather", 1, "INVTYPE_HEAD" }
	ITEMS[7] = { "Rough Flask of Kings", "|Hitem:7|h", 2, 26, 20, "Armor", "Leather", 1, "INVTYPE_HEAD" }
	Use({ { "loot", { label = "Loot", aliases = { "loot" }, collect = Rows({
		L("Good Helm", 1), L("Future Helm", 2), L("Old Cap", 3), L("Plate Helm", 4), L("Great Helm", 5),
		{ name = "Kraul Helm", itemID = 6, detail = "Agathelos  Razorfen Kraul", _ltext = "agathelos razorfen kraul" },
		{ name = "Rough Flask of Kings", itemID = 7, detail = "Boss  Dungeon", _ltext = "dungeon boss loot" } }) } } })
	-- a plain slot word: every helmet
	local res = In("loot", "helmet")
	check(#res == 7, "helmet: every helmet: " .. Show(res))
	-- "upgrades": only what you can equip now, near what you wear or better
	UI:Hide(); FlushAll()
	res = In("loot", "helm upgrades")
	check(Has(res, "Good Helm") and Has(res, "Kraul Helm"), "helm upgrades: near what you wear and better: " .. Show(res))
	check(not Has(res, "Future Helm") and not Has(res, "Great Helm"), "never one above your level (Great Helm needs 22, you're 21)")
	check(not Has(res, "Old Cap"), "not ones well below what you wear")
	check(not Has(res, "Plate Helm"), "not a kind you can't wear")
	-- a level 3 with nothing worn: only what a level 3 can wear
	_G.UnitLevel = function() return 3 end
	_G.GetInventoryItemLink = function() return nil end
	UI:Hide(); FlushAll()
	res = In("loot", "helm upgrades")
	check(#res == 1 and res[1].name == "Old Cap", "a level 3: the cap only: " .. Show(res))
	-- nothing suits (a level 60 in far better gear): no helmet you'd never want
	_G.UnitLevel = function() return 60 end
	ITEMS[9][4] = 100
	_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:9|h[Worn Hood]|h" end end
	UI:Hide(); FlushAll()
	UI:Open("helm upgrades")
	res = UI.Results()
	check(not Has(res, "Good Helm") and not Has(res, "Great Helm") and not Has(res, "Future Helm"), "none suits: none listed: " .. Show(res))
	UI:Hide(); FlushAll()
	-- an instance's shorthand: its helmets only (no name whose letters fit r f k)
	_G.UnitLevel = function() return 21 end
	res = In("loot", "rfk helm")
	check(#res == 1 and res[1].name == "Kraul Helm", "rfk helm: Razorfen Kraul's helmet only: " .. Show(res))
	check(ns.Easy.ToAdvanced("helm upgrades"):find("is:upgrade", 1, true), "Alt+`: upgrades -> is:upgrade: " .. ns.Easy.ToAdvanced("helm upgrades"))
	-- the filter never asks the server for AtlasLoot's items, and others only a few per search
	local savedCached, savedReq, savedInst = C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemInfoInstant
	local asks = 0
	C_Item.IsItemDataCachedByID = function() return false end
	C_Item.RequestLoadItemDataByID = function() asks = asks + 1 end
	local fit = F.GearFit()
	for i = 1, 100 do fit({ kind = "loot", itemID = 1000 + i }) end
	check(asks == 0, "loot rows the client hasn't got: never asked from the filter: " .. asks)
	for i = 1, 100 do fit({ kind = "items", itemID = 2000 + i }) end
	check(asks == F.GEAR_ASK, "other rows: at most F.GEAR_ASK asks per search: " .. asks)
	-- not equipment by the client's own data: turned away before anything is asked
	C_Item.IsItemDataCachedByID = savedCached
	C_Item.GetItemInfoInstant = function() return 1, "Consumable", "Food", "" end
	local infoWas, infos = C_Item.GetItemInfo, 0
	C_Item.GetItemInfo = function(...) infos = infos + 1 return infoWas(...) end
	check(F.GearFit()({ kind = "loot", itemID = 3001 }) == false and infos == 0, "non-equipment: no item info read")
	C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.RequestLoadItemDataByID = infoWas, savedInst, savedReq
	-- a two-hander worn: one-handers and shields are weighed against it (the off hand isn't empty)
	F.ClearCache()
	ITEMS[20] = { "Big Sword", "|Hitem:20|h", 2, 40, 20, "Weapon", "Two-Handed Swords", 1, "INVTYPE_2HWEAPON" }
	ITEMS[21] = { "Small Shield", "|Hitem:21|h", 2, 22, 20, "Armor", "Shields", 1, "INVTYPE_SHIELD" }
	local savedId = _G.GetInventoryItemID
	_G.GetInventoryItemID = function(_, slot) if slot == 16 then return 20 end end
	C_Item.GetItemInfoInstant = function(id) local t = ITEMS[id] return id, t and t[6], t and t[7], t and t[9] end
	_G.GetInventoryItemLink = function(_, slot) if slot == 16 then return "|Hitem:20|h[Big Sword]|h" end end
	check(F.GearFit()({ kind = "loot", itemID = 21 }) == false, "a shield 18 item levels below your two-hander isn't an upgrade")
	_G.GetInventoryItemID, C_Item.GetItemInfoInstant = savedId, savedInst
	-- outside the loot (your bags), a slot word is only the slot
	C_Item.GetItemInfo, _G.UnitLevel, _G.GetInventoryItemLink, C_PlayerInfo.CanUseItem = save.info, save.level, save.inv, save.can
	C_Item.GetDetailedItemLevelInfo = save.det
	F.ClearCache()
end)

Run("upgrades inside an or (helm upgrades or boots upgrades): made new each search, never kept from an earlier one", function()
	E.Set(true)
	local F = ns.Filters
	F.ClearCache()
	local save = { info = C_Item.GetItemInfo, level = _G.UnitLevel, inv = _G.GetInventoryItemLink, can = C_PlayerInfo.CanUseItem,
		det = C_Item.GetDetailedItemLevelInfo }
	local ITEMS = {
		[1] = { "Good Helm", "|Hitem:1|h", 2, 24, 18, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[2] = { "Good Boots", "|Hitem:2|h", 2, 24, 18, "Armor", "Leather", 1, "INVTYPE_FEET" },
		[9] = { "Worn Hood", "|Hitem:9|h", 2, 100, 15, "Armor", "Leather", 1, "INVTYPE_HEAD" },
		[10] = { "Worn Shoes", "|Hitem:10|h", 2, 100, 15, "Armor", "Leather", 1, "INVTYPE_FEET" },
	}
	C_Item.GetItemInfo = function(id) local t = ITEMS[tonumber(id) or 0] if t then return unpack(t) end end
	C_Item.GetDetailedItemLevelInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)")); return ITEMS[id] and ITEMS[id][4] end
	C_PlayerInfo.CanUseItem = function() return true end
	-- a level 60 in far better gear: nothing is an upgrade
	_G.UnitLevel = function() return 60 end
	_G.GetInventoryItemLink = function(_, slot)
		if slot == 1 then return "|Hitem:9|h[Worn Hood]|h" elseif slot == 8 then return "|Hitem:10|h[Worn Shoes]|h" end
	end
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({
		{ name = "Good Helm", itemID = 1 }, { name = "Good Boots", itemID = 2 } }) } } })
	local res = In("items", "helm upgrades or boots upgrades")
	check(not Has(res, "Good Helm") and not Has(res, "Good Boots"), "level 60 in better gear: no upgrades: " .. Show(res))
	UI:Hide(); FlushAll()
	-- the same search after the character changed (level 21, nothing worn): the new level and gear count
	_G.UnitLevel = function() return 21 end
	_G.GetInventoryItemLink = function() return nil end
	UI.lastScan, UI.lastExtra = nil, nil
	res = In("items", "helm upgrades or boots upgrades")
	check(Has(res, "Good Helm") and Has(res, "Good Boots"), "level 21, nothing worn: both are upgrades now: " .. Show(res))
	-- a hard word reached as a plain piece is the strict filter itself (no name fallback)
	check(E.Word("upgrades") ~= E.Word("upgrades"), "upgrades: a new filter each time it's asked for")
	check(E.Word("upgrades")({ name = "Upgrades Manual", itemID = 999 }) == false, "upgrades: a name with the word isn't an upgrade")
	C_Item.GetItemInfo, _G.UnitLevel, _G.GetInventoryItemLink, C_PlayerInfo.CanUseItem = save.info, save.level, save.inv, save.can
	C_Item.GetDetailedItemLevelInfo = save.det
	F.ClearCache()
end)

Run("E.JoinPairs: two everyday words that mean one thing become one word", function()
	local w = { "Attack", "Power", "food", "spell", "power", "x" }
	E.JoinPairs(w)
	check(table.concat(w, ",") == "attack power,food,spell power,x", "pairs joined, the rest kept: " .. table.concat(w, ","))
	w = { "rare", "sword" }
	E.JoinPairs(w)
	check(table.concat(w, ",") == "rare,sword", "no pair: unchanged")
	check(E.ToAdvanced("attack power food"):find("stat:ap", 1, true), "ToAdvanced: attack power -> stat:ap: " .. E.ToAdvanced("attack power food"))
	check(E.ToAdvanced("mining trainer nearby"):find("sort:nearest", 1, true), "ToAdvanced: nearest said last: " .. E.ToAdvanced("mining trainer nearby"))
	check(E.ToAdvanced("sword or axe not boe"):find("type:sword|type:axe", 1, true) and E.ToAdvanced("sword or axe not boe"):find("-is:boe", 1, true),
		"ToAdvanced: or/not pieces as filters: " .. E.ToAdvanced("sword or axe not boe"))
end)

-- (0.49.2, review C2) "X without Y" is Simple mode's "not", never the group's question: "cloak without stamina" said
-- "Needs Fortitude, cloak"; a missing word with no group word nor "who" asks only when every other word names a buff
Run("\"X without Y\" stays a search, not the group's question", function()
	local Q = ns.Group.Question
	check(Q("cloak without stamina") == nil and Q("food without spirit") == nil and Q("shield without stamina") == nil
		and Q("elixir without intellect") == nil and Q("cloak needs stamina") == nil and Q("boots missing spirit") == nil,
		"an item word with without/needs/missing: a search")
	check(Q("missing stamina") and Q("needs int") and Q("who is without fortitude") and Q("party without food")
		and Q("needs blessing of kings") and Q("missing shadow protection") and Q("need flask") and Q("missing buffs"),
		"still the group's: missing stamina, needs int, who is without fortitude, party without food, a buff by its name")
	Use({ { "items", { label = "Item", aliases = { "item" }, collect = Rows({ { name = "Wolf Cloak" }, { name = "Linen Shirt" } }) } } })
	ns.db.easyMode = true
	UI:EasyChanged()
	UI.category, UI.lastExtra = nil, nil
	local res = UI:Search("cloak without stamina")
	check(UI.answerNote == nil and res[1] and res[1].name == "Wolf Cloak", "Simple: cloak without stamina lists the cloak: "
		.. tostring(UI.answerNote) .. " / " .. tostring(res[1] and res[1].name))
end)

-- (0.49.2, review G14) the examples made for you name your professions, not their trade spells (Smelting: "nearest
-- smelting trainer", "smelting skillup", "@npc trainer:smelting" found nothing)
Run("examples name your professions, not their trade spells", function()
	local rand, missing = E.rand, ns.Integrations.AddonMissing
	E.rand = function(a) return a end -- (the first of each list)
	ns.Integrations.AddonMissing = function() return false end
	Use({ { "professions", { label = "Profession", aliases = { "profession" }, collect = Rows({
		{ name = "Smelting", spellID = 2656, parentName = "Mining" }, { name = "Mining", skillLine = 186 } }) } } })
	ns:GetEntries(ns.providers.professions) -- (built, as the lists are after login: suggestions never build them, 0.53.1)
	local ok, err = pcall(function()
		local mine = table.concat(E.PersonalExamples(false), " | ") .. " | " .. table.concat(E.PersonalExamples(true), " | ")
		check(not mine:find("smelting", 1, true) and mine:find("try: mining skillup", 1, true) and mine:find("try: nearest mining trainer", 1, true),
			"Mining, not Smelting: " .. mine)
	end)
	E.rand, ns.Integrations.AddonMissing = rand, missing
	if not ok then error(err, 0) end
end)

-- (0.49.8, the player's ask) "nearest enchanting trainer" found nothing ("nearest enchant trainer" did): a profession
-- said with trainer is what they teach (trainer:enchanting finds the Journeyman Enchanter), not a word in the title
Run("a profession's trainer by what they teach", function()
	for q, want in pairs({ ["nearest enchanting trainer"] = "trainer:enchanting", ["nearest enchant trainer"] = "trainer:enchanting",
		["blacksmithing trainer"] = "trainer:blacksmithing", ["herbalism trainers"] = "trainer:herbalism",
		["nearest first aid trainer"] = "trainer:firstaid", ["mining trainer in org"] = "trainer:mining" }) do
		local a = E.ToAdvanced(q)
		check(a:find(want, 1, true) and not a:find(" enchanting ", 1, true) and not a:find(" enchant ", 1, true)
			and not a:find(" aid ", 1, true) and not a:find(" blacksmithing ", 1, true), "Alt+`: " .. q .. " -> " .. a)
	end
	local a = E.ToAdvanced("nearest enchanting supplies")
	check(not a:find("trainer:", 1, true) and a:find("enchanting", 1, true), "no trainer said: the word stays a word: " .. a)
	a = E.ToAdvanced("nearest first trainer")
	check(not a:find("trainer:first", 1, true), "\"first\" alone isn't first aid: " .. a)
	-- the search itself: the Journeyman Enchanter, nearest first; not the blacksmith
	E.Set(true)
	Use({ { "npc", { label = "NPC", aliases = { "npc" }, explicit = true, collect = Rows({
		{ name = "Elra Spellweave", key = 7001, npcID = 7001, activate = Fire("map") },
		{ name = "Tovan Brightquill", key = 7003, npcID = 7003, activate = Fire("map") },
		{ name = "Gorm Anvilhand", key = 7002, npcID = 7002, activate = Fire("map") },
		{ name = "Ardan Vey", key = 7004, npcID = 7004, activate = Fire("map") },
		{ name = "Lysa Fernwhistle", key = 7005, npcID = 7005, activate = Fire("map") },
		{ name = "Bram Huntsworth", key = 7006, npcID = 7006, activate = Fire("map") },
		{ name = "Morvek Ashgrin", key = 7007, npcID = 7007, activate = Fire("map") },
		{ name = "Selis Darrow", key = 7008, npcID = 7008, activate = Fire("map") } }) } } })
	local I = ns.Integrations
	local was = { field = I.NpcField, defs = I.NpcFlagDefs, here = I.Here, dist = I.NpcDistance, group = _G.UnitFactionGroup }
	local FIELDS = { [7001] = { subName = "Journeyman Enchanter", npcFlags = 16, friendlyToFaction = "A" },
		[7003] = { subName = "Enchanting Trainer", npcFlags = 16, friendlyToFaction = "A" },
		[7002] = { subName = "Journeyman Blacksmith", npcFlags = 16, friendlyToFaction = "A" },
		[7004] = { subName = "Master Mage", npcFlags = 16, friendlyToFaction = "A" }, -- (no "trainer" in the title)
		[7005] = { subName = "Pet Trainer", npcFlags = 16, friendlyToFaction = "A" },
		[7006] = { subName = "Hunter Trainer", npcFlags = 16, friendlyToFaction = "A" },
		[7007] = { subName = "Demon Trainer", npcFlags = 4, friendlyToFaction = "A" }, -- (sells grimoires: a vendor's flag, not a trainer's)
		[7008] = { subName = "Warlock Trainer", npcFlags = 16, friendlyToFaction = "A" } }
	local DIST = { [7001] = 30, [7003] = 90, [7002] = 10, [7004] = 55, [7005] = 70, [7006] = 5, [7007] = 80, [7008] = 3 }
	I.NpcField = function(id, f) return FIELDS[id] and FIELDS[id][f] end
	I.NpcFlagDefs = function() return { TRAINER = 16 } end
	I.Here = function() return { cont = 1, x = 0, y = 0 } end
	I.NpcDistance = function(id) return DIST[id] end
	_G.UnitFactionGroup = function() return "Alliance" end
	ns.Filters.ClearCache()
	for _, q in ipairs({ "nearest enchanting trainer", "nearest enchant trainer", "enchanting trainer nearby" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		local res = UI.Results()
		check(res[1] and res[1].name == "Elra Spellweave" and res[2] and res[2].name == "Tovan Brightquill" and not Has(res, "Gorm Anvilhand"),
			q .. ": the enchanting trainers, nearest first: " .. Show(res))
	end
	UI:Hide(); FlushAll()
	UI:Open("nearest blacksmithing trainer")
	local res = UI.Results()
	check(res[1] and res[1].name == "Gorm Anvilhand" and #res == 1, "nearest blacksmithing trainer: the Journeyman Blacksmith: " .. Show(res))
	-- (0.49.9, the player's ask) said alone, without nearest: the nearest all the same (it listed nothing)
	for q, want in pairs({ ["blacksmithing trainer"] = "Gorm Anvilhand", ["enchanting trainer"] = "Elra Spellweave",
		["enchant trainers"] = "Elra Spellweave", ["mage trainer"] = "Ardan Vey", ["hunter pet trainer"] = "Lysa Fernwhistle",
		["pet trainer"] = "Lysa Fernwhistle", ["demon trainer"] = "Morvek Ashgrin", ["warlock pet trainer"] = "Morvek Ashgrin",
		["warlock trainer"] = "Selis Darrow" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		res = UI.Results()
		check(res[1] and res[1].name == want and res[1].detail == DIST[res[1].key] .. " yd" and UI.action == E.ACTIONS.nearest,
			q .. " alone: the nearest, how far: " .. Show(res))
	end
	check(E.ToAdvanced("blacksmithing trainer") == "@npc trainer:blacksmithing faction:friendly sort:nearest ",
		"Alt+` writes it as the nearest: " .. E.ToAdvanced("blacksmithing trainer"))
	check(E.ToAdvanced("hunter pet trainer") == "@npc trainer:pet faction:friendly sort:nearest ",
		"hunter pet trainer: the pet trainers, nearest: " .. E.ToAdvanced("hunter pet trainer"))
	check(E.ToAdvanced("warlock pet trainer") == "@npc trainer:demon faction:friendly sort:nearest ",
		"warlock pet trainer: the Demon Trainers, nearest: " .. E.ToAdvanced("warlock pet trainer"))
	-- "pet trainer" alone follows your class: a warlock's are the Demon Trainers ("hunter pet trainer" stays the hunters')
	local classWas = _G.UnitClass
	_G.UnitClass = function() return "Warlock", "WARLOCK" end
	UI:Hide(); FlushAll()
	UI:Open("pet trainer")
	res = UI.Results()
	check(res[1] and res[1].name == "Morvek Ashgrin" and not Has(res, "Lysa Fernwhistle"), "a warlock's pet trainer: the Demon Trainer: " .. Show(res))
	check(E.ToAdvanced("hunter pet trainer"):find("trainer:pet", 1, true), "a warlock's hunter pet trainer: still the hunters'")
	_G.UnitClass = function() return "Hunter", "HUNTER" end
	check(E.ToAdvanced("pet trainer"):find("trainer:pet", 1, true), "a hunter's pet trainer: the pet trainers")
	_G.UnitClass = classWas
	-- (review, 0.49.17) a sentence's little words go as for any everyday word; several professions: any of them; a
	-- two-word class isn't its first word's; first aid only by name; Alt+` names the NPCs a place or not
	UI:Hide(); FlushAll()
	UI:Open("the enchanting trainer")
	res = UI.Results()
	check(res[1] and res[1].name == "Elra Spellweave", "the enchanting trainer: the little word isn't searched: " .. Show(res))
	UI:Hide(); FlushAll()
	UI:Open("enchanting blacksmithing trainer")
	res = UI.Results()
	check(res[1] and res[1].name == "Gorm Anvilhand" and Has(res, "Elra Spellweave"), "two professions: either's trainers: " .. Show(res))
	check(E.ToAdvanced("mining herbalism trainer"):find("trainer:mining|trainer:herbalism", 1, true), "Alt+`: one filter, either: "
		.. E.ToAdvanced("mining herbalism trainer"))
	check(not E.ToAdvanced("demon hunter trainer"):find("trainer:", 1, true), "demon hunter trainer: words: " .. E.ToAdvanced("demon hunter trainer"))
	check(not E.ToAdvanced("firs trainer"):find("firstaid", 1, true), "firs trainer isn't first aid: " .. E.ToAdvanced("firs trainer"))
	-- "trainer" alone, or a name with it, isn't a nearest search
	UI:Hide(); FlushAll()
	UI:Open("trainer")
	check(UI.action == nil, "\"trainer\" alone: no nearest search")
	I.NpcField, I.NpcFlagDefs, I.Here, I.NpcDistance, _G.UnitFactionGroup = was.field, was.defs, was.here, was.dist, was.group
	ns.Filters.ClearCache()
end)

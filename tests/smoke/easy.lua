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
	check(not UI.bare and UI.noFoot and not UI.status:IsShown() and not UI.hints:IsShown(), "nothing found: the line, no empty footer under it")
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
	check(joined:find("bags", 1, true) and joined:find("quests", 1, true) and joined:find("npcs", 1, true) and joined:find("loot", 1, true)
		and joined:find("game", 1, true) and joined:find("slash", 1, true), "every category with a sword: " .. joined)
	check(not joined:find("emotes", 1, true), "no emote has sword: no Emotes row")
	local npcs
	for _, e in ipairs(res) do if e.catId == "npcs" then npcs = e end end
	check(npcs and npcs.detail:find("+3 more", 1, true), "NPCs counted by Questie's name index: " .. tostring(npcs and npcs.detail))
	check((UI.status:GetText() or ""):find("pick one", 1, true), "the footer: pick one: " .. tostring(UI.status:GetText()))
	local h = UI.hints:GetText() or ""
	check(h:find("look in", 1, true) and h:find("pick", 1, true), "Enter: look in it; Tab picks: " .. h)
	-- Enter on a category row picks it, keeps the words, the terminal stays open
	local at
	for i, e in ipairs(res) do if e.catId == "bags" then at = i end end
	UI:Activate(at)
	check(UI:IsShown() and UI.category == "bags" and UI.edit:GetText() == "sword", "Enter picks Bags, the words stay")
	res = UI.Results()
	check(res[1] and Kinds(res).items and not Kinds(res).loot and not Kinds(res).category, "Bags: only what's in your bags, no AtlasLoot: " .. Show(res))
	check((UI.status:GetText() or ""):find("Bags", 1, true), "the footer names the category: " .. tostring(UI.status:GetText()))
	check((UI.hints:GetText() or ""):find("all categories", 1, true), "Tab: back to all categories: " .. tostring(UI.hints:GetText()))
	-- Tab: back to the categories; Tab on a category row picks it
	key("TAB")
	check(UI.category == nil and UI.Results()[1].catId, "Tab in a category: back to all of them")
	key("TAB")
	check(UI.category ~= nil, "Tab on a category row: picks it: " .. tostring(UI.category))
	-- typing on in a category keeps it; words that aren't in it: the categories again
	UI:SetCategory("loot")
	UI:SetQuery("sword of omen")
	check(UI.category == "loot" and UI.Results()[1].name == "Sword of Omen", "typing on keeps the category")
	UI:SetQuery("sword practice")
	check(UI.category == nil and UI.Results()[1].catId == "quests", "words not in it: the categories that have them: " .. Show(UI.Results()))
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

Run("every list is in a category: emotes, slash commands, console settings", function()
	E.Set(true)
	Lists()
	UI:Open("dance")
	local res = UI.Results()
	check(res[1] and res[1].catId == "emotes" and res[1].detail:find("/dance", 1, true), "dance: Emotes, /dance: " .. Show(res))
	res = In("emotes", "dance")
	check(#res == 1 and res[1].name == "/dance" and res[1].emote, "in Emotes: /dance: " .. Show(res))
	local h = UI.hints:GetText() or ""
	check(h:find("do it", 1, true), "Enter: do it: " .. h)
	res = In("slash", "reload")
	check(#res == 1 and res[1].name == "/reload", "Slash commands: /reload, no emotes: " .. Show(res))
	UI:Open("camera zoom")
	res = UI.Results()
	check(res[1] and res[1].name == "cameraDistanceMaxZoomFactor" and UI.category == "console" and UI.categoryAuto,
		"camera zoom: only Console settings has it: straight to the setting: " .. Show(res))
	res = In("npcs", "sword")
	check(#res == 4 and Kinds(res).npc and not Kinds(res).items, "NPCs: every matching NPC, nothing else: " .. Show(res))
	res = In("game", "sword")
	check(Has(res, "Sheathe Sword"), "Game: the keybinding: " .. Show(res))
	res = In("quests", "sword")
	check(Has(res, "The Sword of Kings") and Has(res, "Sword Practice") and not Kinds(res).items, "Quests: yours and Questie's: " .. Show(res))
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
			{ name = "Frost Nova", activate = Fire("book"), secondary = Fire("cast"), secondarySecure = { macro = "/cast Frost Nova" } } }) } },
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
	check(res[1] and res[1].name == "Hearthstone" and res[1].actionVerb == "Use" and res[1].secure.macro == "/use item:6948",
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
	I.NpcField, I.NpcFlagDefs, _G.UnitFactionGroup = saveField, saveDefs, saveGroup
	I.Here, I.NpcDistance = saveHere, saveDist
end)

Run("Advanced syntax is refused in Simple mode", function()
	E.Set(true)
	ActionLists()
	UI:Open("@npc hogger")
	local res = UI.Results()
	check(res[1] and res[1].kind == "advanced", "@npc: a row says it's Advanced mode's: " .. Show(res))
	check(UI:SyntaxSegments("@npc hogger")[1][3] == ns.Theme.SYNTAX.bad, "@npc in the 'not taken' colour")
	UI:SetQuery("hearthstone >> party")
	res = UI.Results()
	check(res[1] and res[1].kind == "advanced" and Has(res, "Hearthstone") and not UI.sendTo, ">> party: not sent, the row, the item still found: " .. Show(res))
	UI:SetQuery("q:rare sword")
	check(UI.Results()[1].kind == "advanced" and Has(UI.Results(), "Shiny Sword"), "q:rare: the row; sword still searched: " .. Show(UI.Results()))
	UI:SetQuery("@npc")
	check(#UI.Results() == 1 and UI.Results()[1].kind == "advanced" and not UI.bare, "only syntax: the row alone")
	check((UI.hints:GetText() or ""):find("Advanced", 1, true), "Enter: switch to Advanced mode: " .. tostring(UI.hints:GetText()))
	UI:Activate(1); FlushAll()
	check(_G.TerminalHardMode and _G.TerminalHardMode:IsShown(), "Enter: the switch's confirmation")
	_G.TerminalHardMode:Hide()
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
	check(a ~= b and a:find("try:", 1, true) and b:find("try:", 1, true), "a different example each open: " .. tostring(a) .. " / " .. tostring(b))
	-- Advanced: its own examples (@kinds, filters, >> chat), shown faintly in the empty prompt
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Hide(); FlushAll()
	local seen = {}
	for _ = 1, #E.ADV_EXAMPLES do
		UI:Open("")
		seen[E.Example()] = true
		check(UI:Suggestion() == nil and UI.ghost:IsShown() and UI.ghost:GetText() == E.Example(), "Advanced: the example is in the empty prompt: " .. tostring(UI.ghost:GetText()))
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
			if w:sub(1, 1) == "@" then check(ns:ResolveProvider(w:sub(2)) ~= nil or w == "@questie" or w == "@npc" or w == "@stored", "known kind in an example: " .. w) end
			if w:find("^%a+:%S") and not w:find("[()]") then check(ns.Filters.Parse(w) ~= nil, "a working filter in an example: " .. w) end
		end
	end
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
	check(all == "Show in bags,Use,Link in chat,Cancel", "its actions in words: " .. all)
	local use = m.lines[2]
	check(use.attrs.type1 == "macro" and use.attrs.macrotext1 == "/use item:6948", "Use: the game runs /use on the click: " .. tostring(use.attrs.macrotext1))
	use.scripts.PostClick(use, "LeftButton"); FlushAll()
	check(not m:IsShown() and not UI:IsShown(), "after it: menu and terminal gone")
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	m.lines[4].scripts.PostClick(m.lines[4], "LeftButton")
	check(not m:IsShown() and UI:IsShown(), "Cancel: only the menu goes")
	UI:ShowRowMenu(1)
	key("DOWN")
	check(not m:IsShown(), "a key closes it")
	-- Advanced mode: write into the prompt too
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	labels = {}
	for _, b in ipairs(m.lines) do if b:IsShown() then labels[#labels + 1] = b.fs:GetText() end end
	check(table.concat(labels, ","):find("Write into the prompt", 1, true), "Advanced: Write into the prompt: " .. table.concat(labels, ","))
	UI:HideRowMenu()
end)

Run(".advanced and .simple", function()
	E.Set(true)
	local r = ns:FindCommand("advanced").run("", ns)
	FlushAll()
	local d = _G.TerminalHardMode
	check(d and d:IsShown() and E.On(), ".advanced asks first (still Simple): " .. tostring(d and d:IsShown()))
	d.scripts.OnKeyDown(d, "ESCAPE")
	check(not d:IsShown() and E.On(), "Esc: stays in Simple mode")
	-- as tall as its text (it had a lot of empty space): title, text, buttons
	d.body.GetStringHeight = function() return 36 end
	E.ShowConfirm()
	check(d.h == E.CONFIRM_BODY_Y + 36 + E.CONFIRM_PAD * 2 + 24 + 4 and d.h < 150, "the dialog fits its text: " .. tostring(d.h))
	d.body.GetStringHeight = nil
	d.scripts.OnKeyDown(d, "ESCAPE")
	ns:FindCommand("hardmode").run("", ns); FlushAll()
	check(d:IsShown(), "(.hardmode still works as another name)")
	d.yes.scripts.OnClick(d.yes)
	check(not d:IsShown() and not E.On() and ns.db.easyMode == false, "the button: Advanced mode, saved")
	r = ns:FindCommand("advanced").run("", ns)
	check(r[1] and r[1]:find("Already", 1, true), "again: already in Advanced mode")
	r = ns:FindCommand("simple").run("", ns)
	check(E.On() and r[1]:find("Simple mode", 1, true), ".simple: straight back, no question")
	-- .help in plain sentences in Simple mode, the full list in Advanced mode
	local help = ns.commands.help.run("", ns)
	check(help[1]:find("type the name of anything", 1, true) and not table.concat(help, " "):find("lvl:", 1, true), ".help in Simple mode: plain sentences")
	ns.db.easyMode = false
	help = ns.commands.help.run("", ns)
	check(help[1] == "Terminal commands:", ".help in Advanced mode: the commands")
	-- in combat the dialog doesn't open (it takes the keyboard)
	ns.db.easyMode = true
	local ic = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	d:Hide()
	E.ShowConfirm()
	_G.InCombatLockdown = ic
	check(not d:IsShown(), "not in combat")
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
	check(E.ToAdvanced("rare sword") == "sword q:rare " or E.ToAdvanced("rare sword") == "q:rare type:sword ",
		"rare sword -> filters: " .. E.ToAdvanced("rare sword"))
	check(E.ToAdvanced("attack power food") == "stat:ap type:food ", "attack power food -> stat:ap type:food: " .. E.ToAdvanced("attack power food"))
	check(E.ToAdvanced("cast frost nova") == "@spell frost nova ", "cast frost nova -> @spell: " .. E.ToAdvanced("cast frost nova"))
	check(E.ToAdvanced("nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:nearest ",
		"nearest innkeeper -> @npc ... sort:nearest: " .. E.ToAdvanced("nearest innkeeper"))
	check(E.ToAdvanced("hearthstone", "bags") == "@item hearthstone ", "a picked category -> its @kind: " .. E.ToAdvanced("hearthstone", "bags"))
	check(E.ToAdvanced("shield that drops from kresh") == "kresh type:shield ", "sentence words dropped: " .. E.ToAdvanced("shield that drops from kresh"))
	check(E.ToAdvanced("") == "", "nothing typed: nothing")
	-- Alt+` in an open Simple prompt: written in Advanced syntax, searched as Advanced
	UI:Open("cast frost nova")
	alt(function() key("`", "`") end) -- (the key's character comes after it, as in the game)
	check(UI:IsShown() and T.query() == "@spell frost nova " and not E.On() and E.temp, "Alt+`: the prompt is Advanced now: " .. T.query())
	local r = UI.Results()
	check(r[1] and r[1].name == "Frost Nova" and not r[1].actionVerb, "searched as Advanced: the spell row itself: " .. Show(r))
	key("A", "a")
	check(T.query() == "@spell frost nova a", "typing goes on after it (only the switch's ` was dropped): " .. T.query())
	key("BACKSPACE")
	check(ns.db.easyMode == true, "the saved mode stays Simple")
	-- closing gives Simple back, and Down brings back what the Simple prompt said
	UI:Hide(); FlushAll()
	check(E.On() and not E.temp, "closed: Simple again")
	UI:Open(""); key("DOWN")
	check(T.query() == "cast frost nova", "Down: the Simple search, not the Advanced one: " .. T.query())
	UI:Hide(); FlushAll()
	-- closed: the binding opens straight in Advanced
	UI:AdvancedOnce()
	check(UI:IsShown() and not E.On() and T.query() == "", "the binding (closed): opens in Advanced, empty")
	UI:SetQuery("@spell nova")
	check(UI.Results()[1] and UI.Results()[1].name == "Frost Nova", "Advanced syntax taken this run")
	-- Alt+` again (already Advanced this run): closes, like `
	alt(function() key("`") end)
	check(not UI:IsShown() and E.On(), "Alt+` again: closes, Simple again")
	FlushAll()
	-- in Advanced for good, Alt+` is just the toggle
	ns.db.easyMode = false
	UI:AdvancedOnce()
	check(UI:IsShown() and not E.temp, "Advanced for good: Alt+` only opens")
	UI:Hide(); FlushAll()
end)

Run("Alt+`: what it runs stays out of Simple mode's history", function()
	E.Set(true)
	ActionLists()
	ns.db.history, ns.db.historyAdv = {}, {}
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	-- a Simple search run: in the history
	UI:Open("shiny sword"); key("ENTER"); UI:Hide(); FlushAll()
	-- an Alt+` run
	UI:Open("cast frost nova"); alt(function() key("`", "`") end)
	check(T.query() == "@spell frost nova ", "(Advanced this run)")
	UI:Activate(1); UI:Hide(); FlushAll()
	check(ns.db.history[1] == "@spell frost nova", "the Advanced line is in the history: " .. tostring(ns.db.history[1]))
	-- Simple: Up skips it
	UI:Open(""); key("UP")
	check(T.query() == "shiny sword", "Simple mode's Up: its own lines only, not what Alt+` ran: " .. T.query())
	UI:Hide(); FlushAll()
	-- Advanced (Alt+` again, or for good): Up has it
	UI:AdvancedOnce(); key("UP")
	check(T.query() == "@spell frost nova", "Advanced mode's Up: the Advanced line: " .. T.query())
	UI:Hide(); FlushAll()
	-- the same line run in Simple mode later is Simple's again
	ns:RecordHistory("@spell frost nova")
	check(not ns.db.historyAdv["@spell frost nova"], "run again in Simple: no longer Advanced-only")
	ns.db.history, ns.db.historyAdv = {}, {}
end)

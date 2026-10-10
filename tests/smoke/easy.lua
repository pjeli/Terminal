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
	check((UI.hints:GetText() or ""):find("Shift+Left|r all categories", 1, true), "Shift+Left (or Tab): back to all categories: " .. tostring(UI.hints:GetText()))
	-- (0.45.17) Shift+Left, the back key: back to all categories, as Tab
	local s4 = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	key("LEFT")
	_G.IsShiftKeyDown = s4
	UI.frame.scripts.OnKeyUp(UI.frame, "LEFT")
	check(UI.category == nil and UI.Results()[1] and UI.Results()[1].catId and UI.edit:GetText() == "sword", "Shift+Left in a category: back to all of them")
	UI:Activate(at)
	check(UI.category == "bags", "(picked again)")
	-- (0.45.20) Tab, one rule in every mode: in a category it goes down the list (back is Shift+Left's), Shift+Tab up;
	-- Tab on a category row picks it
	local nIn = #UI.Results()
	key("TAB")
	check(UI.category == "bags" and nIn >= 2 and UI.Selected() == 2, "Tab in a category: the next result, the category kept: " .. tostring(UI.category) .. " " .. UI.Selected())
	_G.IsShiftKeyDown = function() return true end
	key("TAB")
	_G.IsShiftKeyDown = s4
	check(UI.category == "bags" and UI.Selected() == 1, "Shift+Tab: the previous one")
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
	-- "nearby" means nearest too, first or last: "nearby innkeeper", "innkeeper nearby"
	for _, q in ipairs({ "nearby innkeeper", "innkeeper nearby", "innkeeper closest" }) do
		UI:Hide(); FlushAll()
		UI:Open(q)
		local r2 = UI.Results()
		check(r2[1] and r2[1].name == "Innkeeper Allison" and r2[1].detail == "40 yd", q .. ": as nearest innkeeper: " .. Show(r2))
	end
	check(E.ToAdvanced("innkeeper nearby") == "@npc is:innkeeper faction:friendly sort:nearest ", "Alt+` writes innkeeper nearby as sort:nearest: " .. E.ToAdvanced("innkeeper nearby"))
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
	check(res[1] == E.SEND_ROW and Has(res, "Hearthstone") and not UI.sendTo, ">> party: not sent, a row says to right-click, the item still found: " .. Show(res))
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
			if w:sub(1, 1) == "@" then check(ns:ResolveProvider(w:sub(2)) ~= nil or w == "@questie" or w == "@npc" or w == "@stored", "known kind in an example: " .. w) end
			if w:find("^%a+:%S") and not w:find("[()]") then check(ns.Filters.Parse(w) ~= nil, "a working filter in an example: " .. w) end
		end
	end
end)

Run("examples made for the character", function()
	local save = { lvl = _G.UnitLevel, cls = _G.UnitClass, zone = _G.GetRealZoneText, guild = _G.IsInGuild, rand = E.rand }
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
	-- in the rotation: one of yours, then a fixed one, in turn
	E.Set(true)
	ns.db.easyMode = nil
	local list = E.ExamplePool()
	local yours = {}
	for _, x in ipairs(E.PersonalExamples(false)) do yours[x] = true end
	check(yours[list[1]] and not yours[list[2]] and list[2] == E.EXAMPLES[1], "yours and the fixed ones take turns: " .. tostring(list[1]) .. " / " .. tostring(list[2]))
	-- every Simple one finds something or at least searches without an error
	for x in pairs(yours) do
		local ok, err = pcall(UI.Search, UI, x:gsub("^try: ", ""))
		check(ok, "searchable: " .. x .. " " .. tostring(err))
	end
	ns.db.easyMode = false
	_G.UnitLevel, _G.UnitClass, _G.GetRealZoneText, _G.IsInGuild, E.rand = save.lvl, save.cls, save.zone, save.guild, save.rand
end)

Run("a pinned row (no score) sorts without an error, first", function()
	local rows = { { name = "Console settings", _score = 1, key = 1 }, ns.Easy.ADVANCED_ROW, { name = "B", _score = 3, key = 2 } }
	local ok, err = pcall(table.sort, rows, UI._Better)
	check(ok and rows[1] == ns.Easy.ADVANCED_ROW, "the Advanced syntax row sorts first: " .. tostring(err))
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
	check(all == "Show in bags,Use,Link in chat,Say in chat,Cancel", "its actions in words: " .. all)
	local use = m.lines[2]
	check(use.attrs.type1 == "macro" and use.attrs.macrotext1 == "/use item:6948", "Use: the game runs /use on the click: " .. tostring(use.attrs.macrotext1))
	use.scripts.PostClick(use, "LeftButton"); FlushAll()
	check(not m:IsShown() and not UI:IsShown(), "after it: menu and terminal gone")
	UI:Open("hearthstone")
	UI:ShowRowMenu(1)
	m.lines[5].scripts.PostClick(m.lines[5], "LeftButton")
	check(not m:IsShown() and UI:IsShown(), "Cancel: only the menu goes")
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
	check(m.lines[5].hl:IsShown(), "Up from the first: round to the last (Cancel)")
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
	_G.UnitName = function(u) return u == "target" and "Thrall" or "Me" end
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
	check(all == "Show in bags,Use,Link in chat,Say in chat,Send to party,Send to guild,Whisper Thrall,Cancel", "the channels you're in: " .. all)
	local g, w = byLabel["Send to guild"], byLabel["Whisper Thrall"]
	check(g and (g.attrs.macrotext1 or "") == "", "nothing worked out (no waypoint moved) until a line is clicked")
	if g then g.scripts.PreClick(g, "LeftButton") end
	if w then w.scripts.PreClick(w, "LeftButton") end
	check(g and g.attrs.type1 == "macro" and g.attrs.macrotext1:match("^/g ") and g.attrs.macrotext1:find("|Hitem:6948", 1, true), "guild: the game presses /g with the link: " .. tostring(g and g.attrs.macrotext1))
	check(w and w.attrs.macrotext1:match("^/w %%t "), "whisper: /w %t, the game fills the target's name: " .. tostring(w and w.attrs.macrotext1))
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
	check(E.ToAdvanced("cast frost nova") == "@spell do:cast frost nova ", "cast frost nova -> @spell do:cast (0.44.11: the action stays): " .. E.ToAdvanced("cast frost nova"))
	check(E.ToAdvanced("nearest innkeeper") == "@npc is:innkeeper faction:friendly sort:nearest ",
		"nearest innkeeper -> @npc ... sort:nearest: " .. E.ToAdvanced("nearest innkeeper"))
	check(E.ToAdvanced("hearthstone", "bags") == "@item hearthstone ", "a picked category -> its @kind: " .. E.ToAdvanced("hearthstone", "bags"))
	check(E.ToAdvanced("shield that drops from kresh") == "kresh type:shield ", "sentence words dropped: " .. E.ToAdvanced("shield that drops from kresh"))
	check(E.ToAdvanced("") == "", "nothing typed: nothing")
	-- Alt+` in an open Simple prompt: written in Advanced syntax, searched as Advanced
	UI:Open("cast frost nova")
	alt(function() key("`", "`") end) -- (the key's character comes after it, as in the game)
	check(UI:IsShown() and T.query() == "@spell do:cast frost nova " and not E.On() and E.temp, "Alt+`: the prompt is Advanced now: " .. T.query())
	local r = UI.Results()
	check(r[1] and r[1].name == "Frost Nova" and r[1].actionVerb == "Cast", "searched as Advanced: the spell, Enter still casts it: " .. Show(r))
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
	check(r[1] and r[1].name == "Hearthstone" and r[1].actionVerb == "Use", "searched as Advanced: the Hearthstone, Enter uses it: " .. Show(r))
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

Run("pure fuzzy finding (Tab+`): every list, names only, no syntax; Enter to Simple, Shift+Enter to Advanced", function()
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
	check(not UI.fzf and not E.On() and E.temp and T.query() == "@spell Frost Nova ", "Shift+Enter: to Advanced: " .. T.query())
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
	-- Alt+` in it: out of it, and Advanced this run
	_G.IsAltKeyDown = function() return true end; key("`", "`"); _G.IsAltKeyDown = function() return false end
	check(not UI.fzf and not E.On() and E.temp, "Alt+` in it: Advanced this run")
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

Run("Alt+`: what it runs stays out of Simple mode's history", function()
	E.Set(true)
	ActionLists()
	ns.db.history, ns.db.historyAdv = {}, {}
	local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
	-- a Simple search run: in the history
	UI:Open("shiny sword"); key("ENTER"); UI:Hide(); FlushAll()
	-- an Alt+` run
	UI:Open("cast frost nova"); alt(function() key("`", "`") end)
	check(T.query() == "@spell do:cast frost nova ", "(Advanced this run)")
	UI:Activate(1); UI:Hide(); FlushAll()
	check(ns.db.history[1] == "@spell do:cast frost nova", "the Advanced line is in the history: " .. tostring(ns.db.history[1]))
	-- Simple: Up skips it
	UI:Open(""); key("UP")
	check(T.query() == "shiny sword", "Simple mode's Up: its own lines only, not what Alt+` ran: " .. T.query())
	UI:Hide(); FlushAll()
	-- Advanced (Alt+` again, or for good): Up has it
	UI:AdvancedOnce(); key("UP")
	check(T.query() == "@spell do:cast frost nova", "Advanced mode's Up: the Advanced line: " .. T.query())
	UI:Hide(); FlushAll()
	-- the same line run in Simple mode later is Simple's again
	check(ns.db.historyAdv["@spell do:cast frost nova"], "(marked Advanced-only)")
	ns:RecordHistory("@spell do:cast frost nova")
	check(not ns.db.historyAdv["@spell do:cast frost nova"], "run again in Simple: no longer Advanced-only")
	ns.db.history, ns.db.historyAdv = {}, {}
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
			if UI.lastOverviewReused then reused = reused + 1 end
			-- the same search from scratch (then the narrowing state put back for the next letter)
			local scanWas, ovWas, catWas, autoWas = UI.lastScan, UI.lastOverview, UI.category, UI.categoryAuto
			UI.lastScan, UI.lastOverview = nil, nil
			if autoWas then UI.category, UI.categoryAuto = nil, nil end
			local fresh = Sig(UI:Search(part))
			check(got == fresh, ("'%s': narrowed = fresh (%s / %s)"):format(part, got, fresh))
			UI.lastScan, UI.lastOverview, UI.category, UI.categoryAuto = scanWas, ovWas, catWas, autoWas
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
	-- opened closed with Alt+`: what was typed then isn't a Simple search to bring back
	UI.lastQuery = "old simple search"
	UI:AdvancedOnce()
	UI:SetQuery("@spell nova", 11)
	UI:Hide(); FlushAll()
	check(UI.lastQuery == nil, "Alt+` from closed: Down doesn't bring Advanced text into Simple mode: " .. tostring(UI.lastQuery))
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
	UI.lastScan, UI.lastOverview = nil, nil
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

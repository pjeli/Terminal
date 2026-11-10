-- Easy mode, part 2 (split from easy.lua in 1.3.0: the file had reached its 20M-instruction test budget): action
-- words, nearest, Advanced syntax in Simple mode, the rotating examples, the row menu, sending to chat, one mode.
-- ("easy" in the code is Simple mode; "hard" is Advanced.) The helpers are easy.lua's, copied.
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
	-- (an example or a tip: which comes next is math.random's, another on GitHub's Linux than here: 1.1.8's Ctrl+T tip
	-- made a tip likelier there, and the check expected "try:")
	local said = UI.ghost:IsShown() and UI.ghost:GetText() or ""
	check(said:find("try:", 1, true) or said:find("^tip:"), "on again: the suggestion is back: " .. said)
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

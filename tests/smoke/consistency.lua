-- The consistency pass (0.44.11): what the footer and the row menu say a row does is what it does, Simple and Advanced
-- alike; similar rows behave alike; one wording for one thing.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local E = ns.Easy

io.write("[consistency]\n")

-- every list says what Enter (and Shift+Enter) does on its rows: no generic "open"/"more" left
do
	local generic, seen = {}, 0
	for _, id in ipairs(ns.providerOrder) do
		local p = ns.providers[id]
		local src = p.collect and debug.getinfo(p.collect, "S").source or ""
		-- (only the addon's own lists: the tests make others)
		local own = src:find("^@Terminal/") and not src:find("tests", 1, true)
		if own then seen = seen + 1 end
		if own and not E.VERBS[id] then generic[#generic + 1] = id end
	end
	check(seen >= 25 and #generic == 0, "every kind has its verbs (" .. seen .. " lists): missing " .. table.concat(generic, ", "))
	local function V(e) local a, b = E.Verbs(e) return tostring(a) .. "/" .. tostring(b) end
	local use = function() end
	-- a copy of the items list (@consumable, @mats) says what the items list says
	check(V({ kind = "consumables", secondary = use }) == "show in bags/use", "@consumable rows: " .. V({ kind = "consumables", secondary = use }))
	-- rows of one kind that differ
	check(V({ kind = "items", slotId = 13, secondary = use }) == "show on character/use", "an equipped item: shown on the character")
	check(V({ kind = "gear", slotId = 5, secondary = use }) == "show on character/nil" and V({ kind = "gear", secondary = use }) == "show in bags/equip",
		"worn gear: nothing to equip; gear in your bags: equip")
	check(V({ kind = "spells", passive = true, secondary = use }) == "show in spellbook/nil" and V({ kind = "spells", secondary = use }) == "show in spellbook/cast",
		"a passive spell: nothing to cast")
	check(V({ kind = "talents", other = true, secondary = use }) == "Wowhead link/link in chat", "another class's talent: Enter is Wowhead")
	check(V({ kind = "equipmentset", secondary = use }) == "equip/show in manager" and V({ kind = "macros", secondarySecure = {} }) == "run/show in Macros"
		and V({ kind = "mounts", secondary = use }) == "summon/show in journal" and V({ kind = "cvars", secondary = use }) == "edit/reset to default"
		and V({ kind = "quests", secondary = use }) == "show in quest log/track" and V({ kind = "maps", secondary = use }) == "show on map/set waypoint",
		"sets equip, macros run, mounts summon, CVars edit, quests track, maps set a waypoint")
	check(V({ kind = "terminal", presetId = "x" }) == "apply/nil" and V({ kind = "calc", secondary = use }) == "show in chat/put in the chat box",
		"themes apply; the calculator shows in chat")
	-- no Shift+Enter: none said (the @who ask row, an addon's options row)
	local ask = ns.Social.WhoAskRow("@who orc")
	check(V(ask) == "ask the server/nil", "@who's ask row: asks the server, no Shift+Enter: " .. V(ask))
	check(V({ kind = "addons", opt = {} }) == "options/nil", "an addon's options row: no Shift+Enter")
	check(V({ kind = "addons", launch = {}, secondary = use }) == "open/turn on/off", "an addon with a minimap button")
	-- printing in your own chat window is "show in chat" everywhere
	check(V({ kind = "combatlog", secondary = use }) == "show in chat/put in the chat box" and V({ kind = "gold", secondary = use }) == "show in chat/put in the chat box"
		and V({ kind = "stored", secondary = use }) == "show in bags/show in chat", "one name for printing in your chat window")
	-- a chain's row: Enter walks on, Shift+Enter is the row's own Enter
	local bar = { kind = "reagent", name = "Thorium Bar", itemID = 12359, activate = use }
	local walk = ns.Pipes.WalkView(bar, "thorium belt > mats", "mats")
	check(V(walk) == "where to get it/show in bags", "a chain's reagent: where to get it, Shift+Enter shows it: " .. V(walk))
end

-- the row menu lists each action once
do
	local function Labels(e)
		UI.results, UI.sel = { e }, 1
		UI:ShowRowMenu(1)
		local m, seen, dup = _G.TerminalRowMenu, {}, nil
		local labels = {}
		for _, b in ipairs(m.lines) do
			if b:IsShown() then
				local l = b.fs:GetText()
				labels[#labels + 1] = l
				if seen[l] then dup = l end
				seen[l] = true
			end
		end
		UI:HideRowMenu()
		return labels, dup
	end
	UI:Open(""); FlushAll()
	local chatbox = { macro = function() return "/run x" end }
	local ach = { kind = "achievementlist", name = "Level 10", link = "|Hachievement:6|h[Level 10]|h", secondary = function() end,
		secondarySecure = chatbox }
	local labels, dup = Labels(ach)
	check(not dup and labels[2] == "Link in chat", "achievements: Link in chat once: " .. table.concat(labels, ", "))
	local gold = { kind = "gold", name = "You", shareLink = function() return "12g" end, secondary = function() end, secondarySecure = chatbox }
	labels, dup = Labels(gold)
	local both = false
	for _, l in ipairs(labels) do if l == "Link in chat" then both = true end end
	check(not dup and not both and labels[2] == "Put in the chat box", "gold: the chat box once: " .. table.concat(labels, ", "))
	labels = Labels(ns.Social.WhoAskRow("@who orc"))
	check(#labels == 2 and labels[1] == "Ask the server", "@who's ask row: no chat lines (it isn't a result): " .. table.concat(labels, ", "))
	UI:Hide(); FlushAll()
end

-- Advanced's footer says what the selected row does too; the armed line says the press's verb
do
	local was = ns.db.easyMode
	ns.db.easyMode = false
	UI:Open("hearthstone"); FlushAll()
	local h = UI.hints:GetText() or ""
	check(h:find("show in bags", 1, true) and h:find("use", 1, true) and not h:find("Enter|r open", 1, true),
		"Advanced footer: the row's verbs: " .. h)
	UI:SetQuery("zzqqxxww", 8); FlushAll()
	h = UI.hints:GetText() or ""
	check(h:find("kind", 1, true), "nothing to run: the command line's own keys: " .. h)
	UI:SetQuery("hearthstone", 11); FlushAll()
	local row = UI.Results()[1]
	local se = row and UI.SecureView(row, true)
	if se then
		UI:TryArmSecure(se)
		local st = UI.status:GetText() or ""
		check(st:find("Press Enter to use", 1, true), "armed: the press's own verb: " .. st)
		UI:Disarm()
	end
	UI:Hide(); FlushAll()
	ns.db.easyMode = was
end

-- the combat log's Enter shows its line like the other lists (no "Terminal:" prefix)
do
	local out, printed = {}, {}
	local o, p = ns.Output, _G.print
	ns.Output = function(_, lines) for _, l in ipairs(lines) do out[#out + 1] = l end end
	_G.print = function(m) printed[#printed + 1] = m end
	local keep = ns.db.combatLog
	ns.db.combatLog = {}
	ns.CombatLog.Add({ what = "killed", who = "Hogger", spell = "Mortal Strike", amount = 300 })
	local CL = ns.providers.combatlog
	CL._dirty = true
	local rows = ns:GetEntries(CL)
	if rows[1] and rows[1].activate then rows[1].activate(rows[1]) end
	ns.Output, _G.print = o, p
	check(rows[1] and #out == 1 and #printed == 0, "combat log: shown like other lists: " .. #out .. " " .. #printed)
	ns.db.combatLog = keep
	CL._dirty = true
end

-- Simple mode doesn't teach Advanced syntax: Down's help rows, the commands' descriptions and what they print
do
	local was = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	local lines = {}
	local saved = { recent = ns.db.recent, freq = ns.db.freq }
	ns.db.recent, ns.db.freq = {}, {}
	UI:Open(""); FlushAll()
	UI.showRecent = true
	for _, e in ipairs(UI:SearchText("")) do lines[#lines + 1] = e.name end
	local all = table.concat(lines, " | ")
	check(#lines > 0 and not all:find("@", 1, true) and not all:find(">>", 1, true), "Simple: Down's help rows have no @ or >>: " .. all)
	UI.showRecent = nil
	UI:Hide(); FlushAll()
	ns.db.recent, ns.db.freq = saved.recent, saved.freq
	for _, name in ipairs({ "lootlog", "combatlog", "xp" }) do
		local c = ns.commands[name]
		check(c and not c.desc:find("@", 1, true), "." .. name .. "'s description has no @kind: " .. tostring(c and c.desc))
	end
	local out = table.concat(ns:FindCommand("lootlog").run("") or {}, " ")
	check(not out:find("@", 1, true), "Simple: .lootlog says how to search it in words: " .. out)
	ns.db.easyMode = false; UI:EasyChanged()
	out = table.concat(ns:FindCommand("lootlog").run("") or {}, " ")
	check(out:find("@drop", 1, true), "Advanced: .lootlog says @drop: " .. out)
	ns.db.easyMode = was; UI:EasyChanged()
end

-- action words reach every kind they make sense for; Alt+` keeps the action (do:use)
do
	local A = E.ACTIONS
	check(A.equip.map.equipmentset and A.wear.map.equipmentset, "equip / wear: equipment sets too")
	check(A.link.map.recipes and A.link.map.talents and A.link.map.lootlog and A.link.map.items, "link: recipes, talents, drops, items too")
	check(A.where.map.dungeon and A.where.map.raid and A.where.map.mailbox, "where: entrances and mailboxes too")
	-- "link" on a row whose Shift+Enter is something else: a link in the chat box (the game opens it)
	local item = { kind = "items", name = "Hearthstone", itemID = 6948, link = "item:6948", secondary = function() end }
	local v = E.ActionView(item, A.link)
	check(v ~= item and v.secure and v.secure.macro and E.Verbs(v) == "link in chat", "link hearthstone: Enter links it: " .. tostring(E.Verbs(v)))
	-- Alt+` writes the action as do:<word>, which Advanced understands
	local adv = E.ToAdvanced("use hearthstone")
	check(adv:find("do:use", 1, true) and adv:find("hearthstone", 1, true), "Alt+`: use hearthstone -> " .. adv)
	check(not E.ToAdvanced("nearest innkeeper"):find("do:", 1, true), "nearest stays sort:nearest")
	check(ns.Filters.Parse("do:use") and ns.Filters.ActionOf("do:use") == A.use and not ns.Filters.ActionOf("do:zzz"), "do: is a known key")
	check(E.IsAdvancedWord("do:use"), "Simple mode refuses do: (it's Advanced syntax)")
	local was = ns.db.easyMode
	ns.db.easyMode = false
	local res = UI:SearchText("@items do:use hearthstone")
	local r = res[1]
	check(r and r.actionVerb == "Use" and E.Verbs(r) == "use" and UI.action == A.use, "Advanced do:use: Enter uses it: " .. tostring(r and r.name) .. " " .. tostring(r and E.Verbs(r)))
	res = UI:SearchText("do:use hearthstone")
	check(res[1] and res[1].actionVerb == "Use", "do:use with no @kind: the action's own lists")
	UI:SearchText("hearthstone")
	ns.db.easyMode = was
end

-- the two .help texts cover the same things, each in its own words
do
	local was = ns.db.easyMode
	ns.db.easyMode = false
	local adv = table.concat(ns:FindCommand("help").run("") or {}, " ")
	ns.db.easyMode = true
	local simple = table.concat(ns:FindCommand("help").run("") or {}, " ")
	ns.db.easyMode = was
	for _, w in ipairs({ "mats for thorium belt", "where should i level", "what killed me", "Tab+`", "right-click", "Ctrl+click", "Ctrl+Enter" }) do
		local lw = w:lower()
		check(adv:lower():find(lw, 1, true) and simple:lower():find(lw, 1, true), "both helps say \"" .. w .. "\"")
	end
	check(adv:find("> mats", 1, true) and not simple:find(">", 1, true), "chains: Advanced shows >, Simple doesn't")
end

-- Tab in the game's own text box (combat, after Ctrl+C) does what it does in the drawn prompt
do
	local was = ns.db.easyMode
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); FlushAll()
	local cats = 0
	local real = UI.EasyTab
	UI.EasyTab = function(self) cats = cats + 1 end
	local moved = 0
	local realMove = UI.Move
	UI.Move = function(self, d) moved = moved + 1 end
	UI.edit.scripts.OnTabPressed(UI.edit)
	UI.EasyTab, UI.Move = real, realMove
	check(cats == 1 and moved == 0, "Simple: Tab in the real box goes to the categories, not down the list (" .. cats .. ", " .. moved .. ")")
	UI:Hide(); FlushAll()
	ns.db.easyMode = was; UI:EasyChanged()
end

local function Upvalue(fn, name)
	for i = 1, 200 do
		local n, v = debug.getupvalue(fn, i)
		if not n then return nil end
		if n == name then return v end
	end
end

-- similar rows behave alike: a mailbox opens the map on it as an entrance does; a quest from your log isn't listed
-- again as its Questie copy; a nearest list keeps what each NPC is
do
	local I, M = ns.Integrations, ns.Maps
	local box = I.SpotRow({ name = "Mailbox", key = "1-1", kind = "mailbox", ui = 1453, px = 50, py = 60, zone = "Stormwind City" })
	check(box.secure == M.SECURE and box.mapID == 1453 and box.after == I.SpotAfter and box.secondary == I.PinObject,
		"a mailbox: Enter opens the map on it (as an entrance), Shift+Enter pins it")
	check(table.concat({ E.Verbs(box) }, "/") == "show on map/set waypoint", "and says so")
	check(M.PinLine("set", "Mailbox", "Stormwind City") == "Waypoint set on Mailbox (Stormwind City)" and M.PinLine("moved", "Hogger") == "Waypoint moved to Hogger",
		"one wording for where the map pin went")
	local Scan = Upvalue(UI.SearchText, "Scan")
	local res = Scan.OneQuest({ { kind = "quests", questID = 5, name = "Wolves" }, { kind = "questie", key = 5, name = "Wolves" },
		{ kind = "questie", key = 6, name = "Wolves Too" } })
	check(#res == 2 and res[1].kind == "quests" and res[2].key == 6, "a quest in your log: its Questie copy isn't listed too")
	local npc = { _compact = true, key = 7, name = "Brom", sub = "Mining Trainer" }
	local v = Scan.NearView(npc, 120)
	check(v.detail == "120 yd  Mining Trainer" and v.nearRest == "Mining Trainer", "nearest: the distance and what it is: " .. tostring(v.detail))
end

-- Ctrl+Enter keeps the terminal open for a press that opens no window (using an item); a window's press still closes it
do
	local was = ns.db.easyMode
	ns.db.easyMode = false
	UI:Open("hearthstone"); FlushAll()
	local row = UI.Results()[1]
	local se = row and UI.SecureView(row, true)
	check(se and UI.HoldFor(se, true) and not UI.HoldFor(se, false), "using an item with Ctrl: held open")
	if se then
		UI:Activate(nil, { keepOpen = true, secondary = true })
		UI:FinishSecure()
		check(UI:IsShown(), "Ctrl+Enter on a use press: the terminal stays")
	end
	UI:Hide(); FlushAll()
	check(not UI.HoldFor({ isOpen = function() return false end }, true), "a window's press (it has its own isOpen): closes as before")
	ns.db.easyMode = was
end

-- the mount journal, the chat box, the achievement window and Terminal's options are opened by the game
do
	local mrows = ns.providers.mounts and ns:GetEntries(ns.providers.mounts) or {}
	local m = mrows[1]
	local mac = m and m.secondarySecure and m.secondarySecure.macro(m)
	check(m and mac and mac:find("MountJournal", 1, true) and mac:find(m.name, 1, true), "mounts: the journal opened by the game, the name searched: " .. tostring(mac))
	local srows = ns:GetEntries(ns.providers.slash)
	local sl
	for _, e in ipairs(srows) do if e.name == "/reload" or e.name == "/rl" then sl = e break end end
	sl = sl or srows[1]
	local smac = sl and sl.secondarySecure and sl.secondarySecure.macro(sl)
	check(smac and smac:find("C_Timer.After", 1, true) and smac:find(sl.name, 1, true), "slash Shift+Enter: the chat box opened by the game: " .. tostring(smac))
	local calc = ns.Calc.Entry("2*3")
	check(calc and calc.shareLink and calc.shareLink(calc) == calc.sum .. " = " .. calc.answer and calc.secondarySecure,
		"the calculator: one text everywhere, the chat box opened by the game")
	local arows = ns:GetEntries(ns.providers.achievementlist)
	local a = arows[1]
	local amac = a and a.secure and a.secure.macro(a)
	check(amac and amac:find("OpenAchievementFrameToAchievement(" .. a.key .. ")", 1, true), "achievements: the window opened by the game: " .. tostring(amac))
	local trows = ns:GetEntries(ns.providers.terminal)
	check(trows[1] and trows[1].secure and trows[1].secure.macro, "Terminal Options: opened by the game")
end

-- loot rows in their quality's colour; AtlasLoot rows link on Shift+Enter
do
	local LL = ns.LootLog
	local iqc = _G.ITEM_QUALITY_COLORS
	_G.ITEM_QUALITY_COLORS = { [3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" } }
	local keep = ns.db.lootLog
	ns.db.lootLog = {}
	LL.Add("|cff0070dd|Hitem:4444::::::::20:::::|h[Blue Thing]|h|r", "Bob", 1, nil, "loot")
	local p = ns.providers.lootlog
	p._dirty = true
	local r = ns:GetEntries(p)[1]
	check(r and r.color == "|cff0070dd", "a drop in its quality's colour: " .. tostring(r and r.color))
	ns.db.lootLog = keep
	p._dirty = true
	local meta = ns.Integrations.loot and ns.Integrations.loot.meta
	if meta then
		local q = C_Item.GetItemQualityByID
		C_Item.GetItemQualityByID = function() return 4 end
		local row = setmetatable({ _compact = true, key = 1, itemID = 2589, name = "Linen Cloth" }, meta)
		check(row.color == "|cffa335ee" and row.secondarySecure and table.concat({ E.Verbs(row) }, "/") == "show in AtlasLoot/link in chat",
			"AtlasLoot rows: coloured, Shift+Enter links them")
		C_Item.GetItemQualityByID = q
	end
	_G.ITEM_QUALITY_COLORS = iqc
end

-- a chain's "gathered from" row is a real row: shown on the map at its spot, sent with the rest
do
	local P, I = ns.Pipes, ns.Integrations
	local save = { field = I.ItemField, name = I.ObjectName, spawn = I.NearestSpawn, here = I.Here }
	I.ItemField = function(id, f) if f == "objectDrops" then return { 1731, 1732 } end end
	I.ObjectName = function(id) return "Copper Vein" end
	I.NearestSpawn = function(oids) return #oids == 2 and { ui = 1429, px = 40, py = 50, zone = "Elwynn Forest", d = 80 } or nil end
	I.Here = function() return { cont = 0, x = 0, y = 0 } end
	local rows = P.Run("sources", { { kind = "items", key = 2770, itemID = 2770, name = "Copper Ore" } })
	local vein
	for _, e in ipairs(rows) do if e.name == "Copper Vein" then vein = e end end
	check(vein and not vein.noActivate and vein.secure == ns.Maps.SECURE and vein.px == 40 and vein.detail:find("80 yd", 1, true),
		"gathered from: at the spot nearest you, Enter shows it on the map: " .. tostring(vein and vein.detail))
	check(vein and #ns.Share.GroupRows({ vein }) == 1, "and it's sent with the others (>>>, All N)")
	I.ItemField, I.ObjectName, I.NearestSpawn, I.Here = save.field, save.name, save.spawn, save.here
end

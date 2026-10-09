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

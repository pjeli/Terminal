-- Simple mode's bar (0.55.1, experimental; the player: "tabs for filtering, sorting, grouping, and a little
-- announcement horn"): UI/Bar.lua. Shown in Simple mode with words typed, gone in Advanced; its filters, sort and group
-- run in the search; Alt+` (or Advanced syntax typed) writes them into the line.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local B, E = ns.Bar, ns.Easy
local L = ns.L

io.write("[bar: Simple mode's filter, sort, group and horn]\n")
do
	local saved = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	local ROWS = {
		{ name = "Iron Sword", quality = 2 }, { name = "Arcanite Sword", quality = 4 }, { name = "Bronze Sword", quality = 3 },
		{ name = "Copper Sword", quality = 1 }, { name = "Mithril Sword", quality = 3 },
	}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		local out = {}
		for i, r in ipairs(ROWS) do out[i] = { name = r.name, quality = r.quality, key = i } end
		return out
	end })
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = true; UI:EasyChanged()
	local function Names()
		local t = {}
		for _, e in ipairs(UI.Results()) do if B.Real(e) then t[#t + 1] = tostring(e.name) end end
		return table.concat(t, " | ")
	end

	UI:Open(""); FlushAll()
	check((UI.barH or 0) == 0, "nothing typed: no bar")
	UI:SetQuery("sword"); FlushAll()
	check(UI.barH == B.H and B.strip and B.strip:IsShown(), "words typed in Simple mode: the bar shows")
	-- (0.55.1, the player: "mousing over and clicking do nothing") the buttons aren't placed again on every footer
	-- update, a hover or a selection: a frame moved under the pointer loses its hover and its click
	local moved = 0
	for _, b in ipairs(B.strip.buttons) do
		local was = b.ClearAllPoints
		b.ClearAllPoints = function(self, ...) moved = moved + 1; return was(self, ...) end
	end
	UI:SetStatus(); B.Update(); B.Update()
	B.strip.buttons[1]:GetScript("OnEnter")(B.strip.buttons[1])
	B.strip.buttons[1]:GetScript("OnLeave")(B.strip.buttons[1])
	UI:SetStatus()
	check(moved == 0, "the bar's buttons stay put through updates and hovers: moved " .. moved .. " times")
	for _, b in ipairs(B.strip.buttons) do b.ClearAllPoints = nil end
	local ids = {}
	for _, o in ipairs(B.Options("filter")) do ids[#ids + 1] = o.id end
	ids = table.concat(ids, " ")
	check(ids:find("q:rare+", 1, true) and not ids:find("is:online", 1, true), "Filter offers what fits the items shown, not what doesn't: " .. ids)

	-- Filter: rare or better
	B.Pick("filter", "q:rare+"); FlushAll()
	check(Names() == "Arcanite Sword | Bronze Sword | Mithril Sword" or Names():find("Arcanite") and not Names():find("Iron") and not Names():find("Copper"),
		"Rare or better: only those: " .. Names())
	-- Sort: by name, then by quality (the best first)
	B.Pick("sort", "name"); FlushAll()
	check(Names() == "Arcanite Sword | Bronze Sword | Mithril Sword", "sorted by name: " .. Names())
	B.Pick("sort", "quality"); FlushAll()
	check(Names():find("^Arcanite Sword"), "sorted by quality, the best first: " .. Names())
	-- (0.65.5, the player: "ascending and descending; an up arrow for ascending, a down arrow for descending instead of
	-- the check mark"; "assume descending at first") a number's sort picked: the highest first, its arrow down; picked
	-- again: the lowest first, its arrow up; a name's: A-Z first (up)
	local function Line(id)
		B.ShowMenu("sort", B.strip.buttons[2])
		for _, b in ipairs(B.menu.lines) do if b.id == id and b:IsShown() then return b end end
	end
	local q = Line("quality")
	check(q and q.arrow:IsShown() and not q.check:IsShown() and q.arrow.coord and q.arrow.coord[3] == 0 and q.arrow.coord[4] == 1,
		"quality picked: a down arrow, not the check: " .. tostring(q and q.arrow.coord and table.concat(q.arrow.coord, ",")))
	-- (Advanced's sort:x is each sort's own way, as before: sort:quality the best first, sort:level the lowest; sort:-x
	-- the other way round)
	check(B.state.sort == "quality" and ns.QueryToAdvanced("sword"):find("sort:quality ", 1, true),
		"descending first; Alt+` writes sort:quality: " .. tostring(B.state.sort) .. " / " .. ns.QueryToAdvanced("sword"))
	B.Pick("sort", "quality"); FlushAll()
	check(Names():find("^Bronze Sword") or Names():find("^Mithril Sword"), "picked again: the lowest first: " .. Names())
	q = Line("quality")
	check(q and q.arrow:IsShown() and q.arrow.coord[3] == 1 and q.arrow.coord[4] == 0, "and its arrow up")
	check(B.state.sort == "-quality" and ns.QueryToAdvanced("sword"):find("sort:-quality ", 1, true), "Alt+` writes sort:-quality")
	local same, why = T.SameAsAdvanced("sword")
	check(same, "the bar's ascending sort as Advanced's: " .. tostring(why))
	local n = Line("name")
	check(n and not n.arrow:IsShown() and not n.check:IsShown(), "the others: no arrow, no check")
	B.Pick("sort", "name"); FlushAll()
	n = Line("name")
	check(Names() == "Arcanite Sword | Bronze Sword | Mithril Sword" and n.arrow:IsShown() and n.arrow.coord[3] == 1,
		"a name: A-Z first, its arrow up: " .. Names())
	B.Pick("sort", "name"); FlushAll()
	check(Names() == "Mithril Sword | Bronze Sword | Arcanite Sword" and B.state.sort == "-name", "picked again: Z-A: " .. Names())
	same, why = T.SameAsAdvanced("sword")
	check(same, "Z-A on the bar as sort:-name in Advanced: " .. tostring(why))
	B.HideMenu()
	B.Pick("sort", "quality"); FlushAll()
	-- Advanced's word for it: sort:-x the other way round; nearest, plan and best have no other way
	local F = ns.Filters
	check(F.SortOf("sort:-level") == "-level" and F.SortOf("sort:level") == "level" and F.SortOf("sort:-plan") == nil
		and F.SortOf("sort:-bogus") == nil, "sort:-level parsed; sort:-plan isn't a sort")
	B.Clear("filter"); B.Clear("sort"); FlushAll()
	check(Names():find("Copper Sword", 1, true), "cleared: every sword again: " .. Names())
	-- Group: a row per quality
	B.Pick("group", "quality"); FlushAll()
	local groups = 0
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" then groups = groups + 1 end end
	check(groups >= 3, "grouped by quality: a row per quality: " .. groups)
	-- (0.56.2, the player's screenshot: "14 results" for 14 dungeons holding 34 swords) the footer counts the groups and
	-- what they hold
	local inside = 0
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" then inside = inside + (tonumber(tostring(e.detail):match("^(%d+)")) or 0) end end
	UI:SetStatus()
	local foot = tostring(UI.status:GetText())
	check(foot:find(L["%d groups"]:format(groups) .. "  ·  " .. L["%s results"]:format(inside), 1, true) and inside > groups,
		"the footer: groups and the results in them: " .. foot)
	local gopts = {}
	for _, o in ipairs(B.Options("group")) do gopts[#gopts + 1] = o.id end
	local sopts = {}
	for _, o in ipairs(B.Options("sort")) do sopts[#sopts + 1] = o.id end
	check(table.concat(sopts, " "):find("quality", 1, true), "grouped: the menus read the rows the groups are made of: " .. table.concat(sopts, " "))
	local one
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" and tostring(e.detail):find("^1 result") then one = e.detail end end
	check(one == "1 result", "a group of one says 1 result (not 1 results): " .. tostring(one))
	-- (0.55.10) a group's Enter: its rows, the bar's Group let go (else they'd be grouped again, one row); Shift+Left back
	-- to the groups, the bar's Group with them
	local gi
	for i, e in ipairs(UI.Results()) do if e.kind == "aggregate" and e.drillTo then gi = gi or i end end
	UI:Activate(gi, {}); FlushAll()
	local drilled = UI.edit:GetText()
	check(drilled:find("^sword q:") and not B.state.group and Names() ~= "" and E.On(),
		"a group's Enter: its rows, Simple mode, the Group let go: '" .. drilled .. "' " .. Names())
	-- (0.55.14, the player: "I am already in a chosen group and it is letting me group again") in a group: the bar's
	-- Filter says which, and Group doesn't offer what the rows all share
	local offered = {}
	for _, o in ipairs(B.Options("group")) do offered[#offered + 1] = o.id end
	check(not table.concat(offered, " "):find("quality", 1, true), "in a quality's group: no Group by quality offered: " .. table.concat(offered, " "))
	check(B.strip.buttons[1].label:find("Filter: ", 1, true) and B.strip.buttons[1].active, "Filter says the group's filter: " .. B.strip.buttons[1].label)
	check(UI:GoBack() and UI.edit:GetText() == "sword" and B.state.group == "quality", "Shift+Left: the groups again: " .. UI.edit:GetText())
	FlushAll()
	B.Clear("group"); FlushAll()

	-- (0.55.9) Advanced syntax typed: Simple mode stays, the line as typed, the bar and its picks with it
	B.Pick("filter", "q:rare+"); B.Pick("sort", "name"); FlushAll()
	UI:SetQuery("sword >>", 8); FlushAll()
	check(UI.edit:GetText() == "sword >>" and E.On() and UI.barH == B.H and B.Active() and Names() == "Arcanite Sword | Bronze Sword | Mithril Sword",
		"Advanced syntax typed: the line, the bar and its picks kept: " .. UI.edit:GetText() .. " / " .. Names())
	B.Reset()
	-- what's typed in Advanced syntax shows on the bar as picked: a filter, a sort, a group; taken back out from there
	UI:SetQuery("sword q:rare+ sort:name "); FlushAll() -- (a space after: a key:value at the caret is its pick list)
	check(B.strip.buttons[1].label == L["Filter: %s"]:format(L["Rare or better"]) and B.strip.buttons[2].label == L["Sort: %s"]:format(L["Name"]),
		"typed q:rare+ and sort:name show: " .. B.strip.buttons[1].label .. " / " .. B.strip.buttons[2].label)
	B.Pick("sort", "quality"); FlushAll()
	check(UI.edit:GetText() == "sword q:rare+ " and B.state.sort == "quality" and Names():find("^Arcanite Sword"),
		"another sort picked: the typed sort: goes from the line: '" .. UI.edit:GetText() .. "' " .. Names())
	B.Reset()
	UI:SetQuery("sword | group by quality"); FlushAll()
	local groups2 = 0
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" then groups2 = groups2 + 1 end end
	check(E.On() and groups2 >= 3 and B.strip.buttons[3].label:find(ns.UpperFirst(ns.Aggregate.FIELDS.quality.label), 1, true),
		"a | group typed in Simple mode: grouped, and the bar says so: " .. groups2 .. " " .. B.strip.buttons[3].label)
	B.Pick("group", "quality"); FlushAll()
	check(UI.edit:GetText() == "sword" and not B.state.group, "unticked: the step goes from the line: '" .. UI.edit:GetText() .. "'")
	UI:Hide(); FlushAll()

	-- Alt+`: written in too, the group step last
	UI:Open(""); UI:SetQuery("sword"); FlushAll()
	B.Pick("group", "quality"); FlushAll()
	UI:AdvancedOnce(); FlushAll()
	check(UI.edit:GetText():find("| group by quality%s*$"), "Alt+`: the group step written last: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	check(not B.Active() and #B.state.filters == 0, "closed: nothing picked any more")

	-- (0.55.3, the player: under .zen the bar did nothing) its menu is made kept up while the interface is faded, and
	-- .zen keeps it by name on later opens
	local Z = ns.Zen
	local wasActive = Z.active
	Z.active = true
	B.menu = nil
	B.ShowMenu("filter", B.strip.buttons[1])
	check(B.menu and Z.Kept(B.menu), "the menu made under .zen keeps its own alpha (not faded with the interface)")
	local own = table.concat(Z.OWN, " ")
	check(own:find("TerminalBarMenu", 1, true) and own:find("TerminalBarTip", 1, true), ".zen keeps the bar's menu and tooltip by name")
	B.HideMenu()
	Z.active = wasActive

	-- the prompt cleared: what was picked goes
	UI:Open(""); UI:SetQuery("sword"); FlushAll()
	B.Pick("filter", "q:epic+"); FlushAll()
	UI:SetQuery(""); FlushAll()
	check(#B.state.filters == 0, "the prompt cleared: the filter goes")

	-- (0.55.10, the player's screenshot) the send button's tooltip doesn't sit over the selected row's: that one goes while
	-- the pointer is on the button, and comes back after
	UI:SetQuery("sword"); FlushAll()
	UI.results[UI.sel].tip = "a sword"; UI:ForgetTooltip(); UI:UpdateTooltip()
	local rowTip = _G.TerminalTooltip
	check(rowTip and rowTip:IsShown(), "(the selected row's tooltip is up)")
	local horn = B.strip.horn
	horn:GetScript("OnEnter")(horn)
	check(not rowTip:IsShown() and B.tip and B.tip:IsShown(), "on the send button: its own tooltip, not the row's")
	UI:UpdateTooltip()
	check(not rowTip:IsShown(), "and the row's stays away meanwhile")
	horn:GetScript("OnLeave")(horn)
	check(rowTip:IsShown() and not B.tip:IsShown(), "off it: the row's back")
	-- the horn: the selected result's sending and copying lines only
	UI:SetQuery("sword"); FlushAll()
	local shown, share
	local was = UI.ShowRowMenu
	UI.ShowRowMenu = function(_, idx, keys, s) shown, share = idx, s end
	B.Horn()
	UI.ShowRowMenu = was
	check(shown == UI.sel and share == true, "the horn: the row menu's sending lines for the selected result")
	UI:Hide(); FlushAll()

	-- (0.55.15, the player: "missing the is:unplaced / missing from my action bars filter") every list's own filters,
	-- each where its list is shown
	do
		local function Ids(kinds)
			local t = {}
			for _, o in ipairs(B.FILTERS) do if B.Fits(o.id, kinds) then t[#t + 1] = o.id end end
			return " " .. table.concat(t, " ") .. " "
		end
		local sp = Ids({ spells = true })
		check(sp:find(" is:unplaced ", 1, true) and sp:find(" is:passive ", 1, true) and sp:find(" is:ready ", 1, true) and not sp:find(" q:rare+ ", 1, true),
			"spells: not on your bars, passive, ready: " .. sp)
		check(Ids({ group = true }):find(" is:dead ", 1, true) and Ids({ mail = true }):find(" is:expiring ", 1, true)
			and Ids({ quests = true }):find(" is:drop ", 1, true) and Ids({ auctions = true }):find(" is:sold ", 1, true), "and the others' own")
		for _, o in ipairs(B.FILTERS) do check(ns.Filters.Parse(o.id) ~= nil, "a filter the search knows: " .. o.id) end
	end

	-- (0.55.14) a filter typed as key:value shows too, named in words; unticked, its words go, quotes and all
	UI:Open(""); UI:SetQuery('sword in:"Scarlet Monastery" '); FlushAll()
	check(B.strip.buttons[1].label == L["Filter: %s"]:format("In Scarlet Monastery"), "in: typed: " .. B.strip.buttons[1].label)
	B.Pick("filter", "in:Scarlet Monastery"); FlushAll()
	check(UI.edit:GetText() == "sword ", "unticked: in:\"...\" taken out: '" .. UI.edit:GetText() .. "'")
	UI:Hide(); FlushAll()

	-- (0.55.13, the player) Alt+F, Alt+S, Alt+G: the bar's menus from the keys
	do
		local key = T.key
		local function alt(fn) _G.IsAltKeyDown = function() return true end; fn(); _G.IsAltKeyDown = function() return false end end
		UI:Open(""); UI:SetQuery("sword", 5); FlushAll()
		alt(function() key("F", "f") end)
		local m = B.menu
		check(m and m:IsShown() and m.which == "filter" and m.keys and m.keySel == 1 and UI.edit:GetText() == "sword",
			"Alt+F: Filter's menu, its first line picked, nothing typed: '" .. UI.edit:GetText() .. "'")
		local rareAt
		for i = 1, m.n do if m.lines[i].id == "q:rare+" then rareAt = i end end
		while m.keySel ~= rareAt do key("DOWN") end
		key("ENTER"); FlushAll()
		check(B.state.filters[1] == "q:rare+" and m:IsShown() and m.keySel == rareAt and not Names():find("Iron", 1, true),
			"Enter: picked, the menu stays (filters add up), the line where it was: " .. Names())
		key("SPACE", " "); FlushAll()
		check(#B.state.filters == 0 and UI.edit:GetText() == "sword", "Space picks too (unticked), and types nothing: '" .. UI.edit:GetText() .. "'")
		key("RIGHT")
		check(m:IsShown() and m.which == "sort", "Right: the next menu, Sort")
		local nameAt
		for i = 1, m.n do if m.lines[i].id == "name" then nameAt = i end end
		while m.keySel ~= nameAt do key("DOWN") end
		key("ENTER"); FlushAll()
		check(B.state.sort == "name" and not m:IsShown() and Names() == "Arcanite Sword | Bronze Sword | Copper Sword | Iron Sword | Mithril Sword",
			"Sort by name from the keys, the menu gone: " .. Names())
		alt(function() key("G", "g") end)
		check(m:IsShown() and m.which == "group" and UI.edit:GetText() == "sword", "Alt+G: Group's menu")
		key("ESCAPE")
		check(not m:IsShown() and UI:IsShown(), "Esc: only the menu goes")
		alt(function() key("S", "s") end)
		check(m.lines[m.keySel].id == "name", "opened again: the line ticked is the one picked")
		while m.keySel ~= 1 do key("UP") end
		key("UP")
		-- (the last line that picks something: the hint under a sort, "Shift: then by another", says something only; 0.66.4)
		local lastPick = m.n
		while m.lines[lastPick].id == nil do lastPick = lastPick - 1 end
		check(m.keySel == lastPick and lastPick >= m.n - 1, "Up from the first line: round to the last")
		key("DOWN"); key("ENTER"); FlushAll()
		check(B.state.sort == nil, "Best match from the keys: no sort: " .. tostring(B.state.sort))
		alt(function() key("F", "f") end)
		key("A", "a"); FlushAll()
		check(not m:IsShown() and UI.edit:GetText() == "sworda", "another key: the menu goes, the key types: '" .. UI.edit:GetText() .. "'")
		UI:Hide(); FlushAll()
		UI:Open("", nil); FlushAll()
		alt(function() key("F", "f") end)
		check(not (B.menu and B.menu:IsShown()), "no bar (nothing typed): Alt+F opens nothing")
		UI:Hide(); FlushAll()
		B.Reset()
		-- (0.55.19, the player: "pressing Alt+G is both typing g and opening the menu") the character the client types for
		-- the key (Windows: g; a Mac's Option: ©) isn't typed; when none comes, the next letter isn't eaten
		UI:Open(""); UI:SetQuery("sword", 5); FlushAll()
		alt(function() key("G", "g") end)
		check(B.menu:IsShown() and B.menu.which == "group" and UI.edit:GetText() == "sword", "Windows: Alt+G's g not typed: '" .. UI.edit:GetText() .. "'")
		key("ESCAPE")
		alt(function() key("F", "ƒ") end)
		key("ESCAPE")
		check(UI.edit:GetText() == "sword", "Mac: Option+F's ƒ not typed: '" .. UI.edit:GetText() .. "'")
		alt(function() key("S") end)
		key("ESCAPE")
		key("S", "s"); FlushAll()
		check(UI.edit:GetText() == "swords", "nothing came for Alt+S: the s typed next is typed: '" .. UI.edit:GetText() .. "'")
		-- the categories showing: Sort and Group can't be used, so their keys open nothing (as a click)
		UI:Hide(); FlushAll()
		B.Reset()
	end

	-- (0.55.18, review) the bar's picks belong to the search they were picked for
	do
		local function Picked() return #B.state.filters end
		UI:Open(""); UI:SetQuery("sword", 5); FlushAll()
		B.Pick("filter", "q:epic+"); FlushAll()
		UI:SetQuery(".help", 5); FlushAll()
		check(Picked() == 0, "a .command line: the picks go (they came back on the next search)")
		UI:SetQuery("sword", 5); B.Pick("filter", "q:epic+"); FlushAll()
		UI:StartFuzzy()
		check(Picked() == 0, "fuzzy finding: the picks go")
		UI:EndFuzzy(true)
		UI:SetQuery("sword", 5); B.Pick("filter", "q:epic+"); FlushAll()
		ns.db.history = { "iron" }
		UI:SetQuery("", 0); FlushAll(); B.Pick("filter", "q:epic+")
		UI:History(-1); FlushAll()
		check(Picked() == 0 and UI.edit:GetText() == "iron", "a history line: the picks go: " .. UI.edit:GetText())
		-- closed by the game (Esc's menu, a window): the picks and an open menu go, as with UI:Hide
		UI:SetQuery("sword", 5); B.Pick("filter", "q:epic+"); FlushAll()
		_G.IsAltKeyDown = function() return true end; T.key("F"); _G.IsAltKeyDown = function() return false end
		local tf = _G.TerminalFrame
		tf:Hide(); tf.scripts.OnHide(tf)
		check(Picked() == 0 and not (B.menu and B.menu:IsShown()), "hidden by the game: no picks, no menu left up")
		FlushAll()
		-- F1 (and combat) come back as they were, picks and all
		UI:Open(""); UI:SetQuery("sword", 5); B.Pick("filter", "q:epic+"); FlushAll()
		local st = UI:SaveState()
		UI:Hide(); FlushAll()
		UI:RestoreState(st); FlushAll()
		check(B.state.filters[1] == "q:epic+" and Names() == "Arcanite Sword", "back as it was, the filter too: " .. Names())
		UI:Hide(); FlushAll()
	end

	-- (0.55.18, review) the line's "| group by" is the line's: a search made once it's closed isn't summed up
	UI:Open(""); UI:SetQuery("sword | count", 13); FlushAll()
	UI:Hide(); FlushAll()
	local after = UI:Search("sword")
	check(after[1] and after[1].kind ~= "aggregate", "closed: UI:Search isn't summed up as the last line was: " .. tostring(after[1] and after[1].kind))
	-- (0.55.18, review) a category opened for you goes with an @kind typed (the footer named it)
	UI:Open(""); UI:SetQuery("arcanite", 8); FlushAll()
	UI:SetQuery("@item iron", 10); FlushAll()
	check(UI.category == nil, "@kind typed: no category left over: " .. tostring(UI.category))
	UI:Hide(); FlushAll()

	-- (0.55.18, review) taking words back out of the line
	do
		UI:Open(""); UI:SetQuery("sword not boe", 13); FlushAll()
		check(B.Typed().filters[1] and B.Typed().filters[1].spec == "-is:boe", "(not boe: a filter typed)")
		B.Pick("filter", "-is:boe"); FlushAll()
		check(UI.edit:GetText() == "sword", "\"not boe\" unticked: its two words go: '" .. UI.edit:GetText() .. "'")
		UI:SetQuery('"big rare sword" rare', 21); FlushAll()
		B.Pick("filter", "q:rare"); FlushAll()
		check(UI.edit:GetText() == '"big rare sword"', "a quoted phrase is left alone: '" .. UI.edit:GetText() .. "'")
		UI:SetQuery("rare sword rare", 15); FlushAll()
		B.Pick("filter", "q:rare"); FlushAll()
		check(UI.edit:GetText() == "sword" and not B.Typed().filters[1], "said twice: both go: '" .. UI.edit:GetText() .. "'")
		-- (FRONT_END.md Phase 4: taken out where each was typed, not by its word: the "boe" of "not boe" stays)
		UI:SetQuery("boe linen not boe", 17); FlushAll()
		B.Pick("filter", "is:boe"); FlushAll()
		check(UI.edit:GetText() == "linen not boe", "a word another filter has too: only the unticked one goes: '" .. UI.edit:GetText() .. "'")
		-- (a line read a keystroke ago that the prompt only goes on from: not cut by its spans; review)
		local stale = { s = 1, e = 13, line = "under level 2" }
		check(B.CutSpans("under level 25", { stale }) == nil and B.CutSpans("under level 2 swords", { stale }) == " swords",
			"spans only of the line as it stands: " .. tostring(B.CutSpans("under level 25", { stale })))
		-- (a "quoted phrase" between a join's words stays: only "not" and "boe" go; invariant 7, review)
		UI:SetQuery('linen not "big boe" boe', 23); FlushAll()
		B.Pick("filter", "-is:boe"); FlushAll()
		check(UI.edit:GetText() == 'linen "big boe"', "a quoted phrase inside a join is left alone: '" .. UI.edit:GetText() .. "'")
		-- (a typed group: taken out from its "|" to its end, where it is in the line)
		UI:SetQuery("linen  |  group by quality", 26); FlushAll()
		local g = B.Typed().group
		check(g and g.src and g.src.said == "|  group by quality", "a typed group's place in the line: " .. tostring(g and g.src and g.src.said))
		B.Clear("group"); FlushAll()
		check(UI.edit:GetText() == "linen", "Group cleared: the typed step goes: '" .. UI.edit:GetText() .. "'")
		UI:SetQuery("rare linen", 10); FlushAll()
		B.Clear("filter"); FlushAll()
		check(UI.edit:GetText() == "linen", "Filter cleared: the typed word goes: '" .. UI.edit:GetText() .. "'")
		UI:Hide(); FlushAll()
	end

	-- (0.55.18, review) steps typed sum up their own way: the bar's Group isn't shown as on
	do
		UI:Open(""); UI:SetQuery("sword", 5); FlushAll()
		B.Pick("group", "quality"); FlushAll()
		UI:SetQuery("sword | count", 13); FlushAll()
		check(B.strip.buttons[3].label == B.GroupWord() and not B.strip.buttons[3].active, "| count typed: Group not shown as on: " .. B.strip.buttons[3].label)
		-- (0.56.1, the player) the button says "Group"; a language with its own word for grouping says that one
		check(B.strip.buttons[3].label == "Group", "its word: Group: " .. B.strip.buttons[3].label)
		-- (0.56.7, the player) each button's key letter underlined: F, S, G; none in a language whose word hasn't it
		local f, so, g = B.strip.buttons[1], B.strip.buttons[2], B.strip.buttons[3]
		check(f.under:IsShown() and so.under:IsShown() and g.under:IsShown() and f.underAt == 0 and g.underAt == 0
			and f.underWide == 7, "Filter's F, Sort's S, Group's G underlined: " .. tostring(f.underAt) .. " " .. tostring(f.underWide))
		local sortWas = rawget(L, "Sort")
		rawset(L, "Sort", "Порядок"); so.label = nil
		B.Update()
		check(not so.under:IsShown(), "a word without the letter: no line under it")
		rawset(L, "Sort", sortWas); so.label = nil
		B.Update()
		check(so.under:IsShown(), "back: underlined again")
		-- (release review) only in the button's word, never in what's picked after its ":"
		local labelWas = so.label
		so.label = "Ordenado: Más cercano primero"
		B.Underline(so)
		check(not so.under:IsShown(), "\"Ordenado: Más...\": no s of its own, none underlined in what's picked")
		so.label = "Sort: Name"
		B.Underline(so)
		check(so.under:IsShown() and so.underAt == 0, "\"Sort: Name\": its own S")
		so.label = labelWas
		B.Underline(so)
		local was = rawget(L, "Group by")
		rawset(L, "Group by", "分组")
		check(B.GroupWord() == "分组", "translated: grouping's word, not the party's: " .. B.GroupWord())
		rawset(L, "Group by", was)
		B.Reset()
		-- grouped: the send button copies them out
		UI:SetQuery("sword", 5); B.Pick("group", "quality"); FlushAll()
		local shown, share
		local was = UI.ShowRowMenu
		UI.ShowRowMenu = function(_, idx, keys, sh) shown, share = idx, sh end
		B.Horn()
		UI.ShowRowMenu = was
		check(shown and share, "grouped: the send button still works (copy them all)")
		UI:Hide(); FlushAll()
		B.Reset()
	end

	-- (0.55.18) nothing passed an everyday word, the closest shown: Alt+` writes the word as a word, not a filter that
	-- finds nothing
	UI:Open(""); UI:SetQuery("legendary arcanite", 18); FlushAll()
	check(UI.softRelaxed and Names() == "Arcanite Sword", "(legendary arcanite: it isn't, the closest shown: " .. Names() .. ")")
	local advL = E.ToAdvanced("legendary arcanite")
	check(not advL:find("q:legendary", 1, true) and advL:find("legendary", 1, true), "Alt+` writes it as a word: " .. advL)
	UI:SetQuery("epic arcanite", 13); FlushAll()
	check(E.ToAdvanced("legendary arcanite"):find("q:legendary", 1, true), "(another line, not the one shown: the filter)")
	UI:Hide(); FlushAll()

	-- (0.55.12, the player's screenshot: "Filter: Q:rare") a filter typed in Advanced syntax is named in words
	check(B.SpecLabel("q:rare", "q:rare") == "Rare" and B.SpecLabel("q:epic+", "q:epic+") == "Epic or better"
		and B.SpecLabel("-is:boe", "-is:boe") == "Not boe" and B.SpecLabel("is:unlearned", "is:unlearned") == "Unlearned"
		and B.SpecLabel("q:rare+", "x") == L["Rare or better"],
		"typed filters in words: " .. B.SpecLabel("q:rare", "q:rare") .. " / " .. B.SpecLabel("-is:boe", "-is:boe"))
	-- (0.55.12, the player's screenshot: "q:rare type:sword | group by dungeon", 0 results) a sum over the categories:
	-- every category's rows summed up, not the categories
	ns:RegisterProvider("spells", { label = "Spell", aliases = { "spell" }, collect = function()
		return { { name = "Sword Dance", key = 1 }, { name = "Mithril Ward", key = 2 } }
	end })
	ns:AliasesChanged()
	UI:Open(""); UI:SetQuery("sword | group by quality"); FlushAll()
	local gq = 0
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" and e.drillTo then gq = gq + 1 end end
	check(gq >= 3 and not B.Overview(UI.Results()), "grouped over every category's rows, not over the categories: " .. gq)
	-- (0.55.18, review) and typing on narrows from the last keystroke's matches (every list was read twice a keystroke)
	UI:SetQuery("", 0); FlushAll()
	UI:SetQuery("mithr", 5); FlushAll()
	B.Pick("group", "quality"); FlushAll()
	local Scan, calls = UI._Scan, 0
	local collectWas = Scan.Collect
	Scan.Collect = function(...) calls = calls + 1 return collectWas(...) end
	UI:SetQuery("mithri", 6); FlushAll()
	Scan.Collect = collectWas
	check(calls == 1 and UI.lastSearchNarrowed and B.Overview(UI.Results()) == false, "grouped over the categories: one pass, narrowed as typed: " .. calls)
	B.Reset()
	UI:Hide(); FlushAll()
	ns.providers.spells = nil
	for i, id in ipairs(ns.providerOrder) do if id == "spells" then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()

	-- (0.55.7, the search's rewrite, phase 4) the bar edits the query: a filter typed as a word shows as picked, and is
	-- taken back out of the line from the bar
	UI:Open(""); UI:SetQuery("rare sword"); FlushAll()
	local b1 = B.strip.buttons[1]
	check(b1.label == L["Filter: %s"]:format("Rare") and b1.active, "a filter typed as a word shows picked: " .. tostring(b1.label))
	local typedOpt
	for _, o in ipairs(B.Options("filter")) do if o.typed then typedOpt = o end end
	check(typedOpt and typedOpt.id == "q:rare" and typedOpt.on, "its menu line: ticked, typed: " .. tostring(typedOpt and typedOpt.id))
	B.Pick("filter", "q:rare"); FlushAll()
	check(UI.edit:GetText() == "sword", "unticked: its word taken out of the line: '" .. UI.edit:GetText() .. "'")
	check(#B.state.filters == 0 and not B.Typed().filters[1], "and nothing picked: " .. #B.state.filters)
	UI:SetQuery("sword rare usable"); FlushAll()
	B.Clear("filter"); FlushAll()
	check(UI.edit:GetText() == "sword", "Filter cleared: every filter word typed goes too: '" .. UI.edit:GetText() .. "'")
	B.DropWords({ "bind on equip" })
	UI:SetQuery("Bind  on Equip sword"); FlushAll()
	B.DropWords({ "bind on equip" }); FlushAll()
	check(UI.edit:GetText() == "sword", "a phrase taken out whatever its case and spaces: '" .. UI.edit:GetText() .. "'")
	UI:Hide(); FlushAll()

	-- questions are filtered and sorted as searches are: the bar's, and Advanced words after the question
	local Scan = UI._Scan
	local NOTE = { name = "Your swords", noActivate = true, raw = true }
	table.insert(Scan.ANSWERS, 1, {
		ask = function(text) return text == "my swords" or nil end,
		answer = function()
			local out = { NOTE }
			for i, r in ipairs(ROWS) do out[#out + 1] = { name = r.name, quality = r.quality, key = i, kind = "items" } end
			return out
		end,
		toAdvanced = function() return "@item sword " end })
	local ok, err = pcall(function()
		UI:Open(""); UI:SetQuery("my swords"); FlushAll()
		check(Names():find("Iron Sword", 1, true), "the question answered: " .. Names())
		B.Pick("filter", "q:rare+"); FlushAll()
		check(not Names():find("Iron", 1, true) and Names():find("Arcanite", 1, true), "the bar's filter on a question's rows: " .. Names())
		check(UI.Results()[1] == NOTE, "its own lines kept")
		B.Pick("sort", "name"); FlushAll()
		check(Names() == "Arcanite Sword | Bronze Sword | Mithril Sword", "the bar's sort on a question's rows: " .. Names())
		check(ns.QueryToAdvanced("my swords"):find("q:rare+ sort:name", 1, true), "Alt+` writes them after the question: " .. ns.QueryToAdvanced("my swords"))
		B.Pick("filter", "q:epic+"); B.Pick("filter", "q:rare+"); B.Pick("filter", "is:online"); FlushAll()
		check(UI.Results()[1] == NOTE and UI.Results()[2] and UI.Results()[2].noActivate and #UI.Results() == 2,
			"nothing passes: the answer's line, and one saying so: " .. #UI.Results())
		UI:Hide(); FlushAll()
		ns.db.easyMode = false; UI:EasyChanged()
		local r = UI:Search("my swords q:rare+ sort:name")
		local t = {}
		for _, e in ipairs(r) do if B.Real(e) then t[#t + 1] = e.name end end
		check(table.concat(t, " | ") == "Arcanite Sword | Bronze Sword | Mithril Sword", "Advanced words after a question: " .. table.concat(t, " | "))
		ns.db.easyMode = true; UI:EasyChanged()
	end)
	table.remove(Scan.ANSWERS, 1)
	B.Reset()
	if not ok then error(err, 0) end

	-- Advanced mode's own sort:name (the bar's sorts in Advanced syntax)
	ns.db.easyMode = false; UI:EasyChanged()
	local res = UI:Search("@item sword sort:name")
	check(res[1] and res[1].name == "Arcanite Sword" and res[#res].name == "Mithril Sword", "sort:name in Advanced mode: "
		.. tostring(res[1] and res[1].name) .. " .. " .. tostring(res[#res] and res[#res].name))
	res = UI:Search("@item sword sort:-name")
	check(res[1] and res[1].name == "Mithril Sword" and res[#res].name == "Arcanite Sword", "sort:-name in Advanced mode: Z-A: "
		.. tostring(res[1] and res[1].name) .. " .. " .. tostring(res[#res] and res[#res].name))

	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	ns.db.easyMode = saved.easy; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	B.Reset()
end

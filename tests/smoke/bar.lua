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
	B.Clear("filter"); B.Clear("sort"); FlushAll()
	check(Names():find("Copper Sword", 1, true), "cleared: every sword again: " .. Names())
	-- Group: a row per quality
	B.Pick("group", "quality"); FlushAll()
	local groups = 0
	for _, e in ipairs(UI.Results()) do if e.kind == "aggregate" then groups = groups + 1 end end
	check(groups >= 3, "grouped by quality: a row per quality: " .. groups)
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

	ns.providers, ns.providerOrder = saved.providers, saved.order
	ns:AliasesChanged()
	ns.db.easyMode = saved.easy; UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	B.Reset()
end

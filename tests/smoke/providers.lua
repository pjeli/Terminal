-- Providers review fixes: secret text, game-pressed panels and slash lines, no clicks inside Blizzard's
-- windows, reagent-name events, aliases, the shared helpers (Util.lua).
local T = ...
local ns, UI, F, S, check, log, logHas, key, names, Obj, FlushAll = T.ns, T.UI, T.F, T.S, T.check, T.log, T.logHas, T.key, T.names, T.Obj, T.FlushAll
local P = ns.Professions

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

io.write("[util helpers]\n")
do
	local a, b, c, d, e, f, g, h, i, j, k = ns.Safe(function() return 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 end)
	check(a == 1 and h == 8 and k == 11, "ns.Safe hands back every result (a mount's info has eleven)")
	check(ns.Safe(nil) == nil and ns.Safe(function() error("x") end) == nil and select("#", ns.Safe(error, "x")) == 0, "ns.Safe: nothing from a missing or failing function")
	check(ns.Str("") == nil and ns.Str(3) == nil and ns.Str("a") == "a" and ns.Num("3") == nil and ns.Num(3) == 3, "ns.Str / ns.Num")
	check(ns.QualityHex(4) == "|cffa335ee" and ns.QualityHex(nil) == nil, "ns.QualityHex")
	check(ns.Never() == false, "ns.Never")
	local named, unnamed = Obj("Frame"), Obj("Frame")
	named.GetName = function() return "NamedFrame" end
	unnamed.GetName = function() return nil end
	check(ns.FrameName(named) == "NamedFrame" and ns.FrameName(unnamed) == nil and ns.FrameName(nil) == nil and ns.FrameName({}) == nil,
		"ns.FrameName: a string name, else nil, never an error")
	local fs = function(t) return { GetObjectType = function() return "FontString" end, GetText = function() return t end } end
	local tex = { GetObjectType = function() return "Texture" end, GetText = function() return "no" end }
	local row = { GetText = function() return "Own" end, GetRegions = function() return fs("A"), tex, fs(nil), fs("B") end }
	check(table.concat(ns.FrameTexts(row), ",") == "Own,A,B", "ns.FrameTexts: own text, then the FontStrings' (" .. table.concat(ns.FrameTexts(row), ",") .. ")")
	check(table.concat(ns.FrameTexts({ GetText = function() error("x") end, GetRegions = function() return fs("C") end }), ",") == "C",
		"ns.FrameTexts: a failing GetText is skipped")
	-- a list with collapsed headers: expanded for the read, collapsed again last first
	local rows = { { name = "A", header = true, collapsed = true }, { name = "a1" }, { name = "B", header = true, collapsed = false }, { name = "b1" } }
	local ops = {}
	local api = {
		count = function() return #rows end,
		row = function(i) return rows[i] end,
		collapsed = function(r) return r.collapsed end,
		expand = function(i) ops[#ops + 1] = "expand " .. rows[i].name; rows[i].collapsed = false end,
		collapse = function(i) ops[#ops + 1] = "collapse " .. rows[i].name; rows[i].collapsed = true end,
	}
	local got = ns.ReadExpanded(api, 100)
	check(#got == 4 and got[2].name == "a1" and table.concat(ops, ", ") == "expand A, collapse A" and rows[1].collapsed == true,
		"ns.ReadExpanded: every row read, the headers it opened closed again: " .. table.concat(ops, ", "))
	-- a row not scrolled into view: scrolled once, found on the second look
	local frame, scrolls, found, shown = Obj("Frame"), 0, false, nil
	frame.shown = true
	local box = { ScrollToElementDataByPredicate = function(_, pred)
		scrolls = scrolls + 1
		if pred({ GetData = function() return { setID = 7 } end }) then found = true end
	end }
	ns.PointAtRow({
		frame = function() return frame end,
		find = function() return found and frame or nil end,
		scroll = function() return ns.ScrollBoxTo(box, function(d) return d.setID == 7 end) end,
		show = function(row) shown = row end,
	})
	FlushAll()
	check(scrolls == 1 and shown == frame, "ns.PointAtRow: scrolls once to the row, then points at it")
	check(ns.ScrollBoxTo(nil, function() return true end) == false, "no box: nothing to scroll")
end

io.write("[secret text]\n")
do
	local SECRET = {}
	_G.issecretvalue = function(v) return v == SECRET end
	local saveNum, saveInfo, saveText = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo, _G.GetQuestLogQuestText
	local quests = {
		{ title = "Elwynn Forest", isHeader = true },
		{ title = "Wolves Across the Border", questID = 33, level = 5 },
		{ title = SECRET, questID = 34, level = 5 },
		{ title = "Hidden Words", questID = 35, level = 5 },
	}
	C_QuestLog.GetNumQuestLogEntries = function() return #quests end
	C_QuestLog.GetInfo = function(i) return quests[i] end
	_G.GetQuestLogQuestText = function(i) if i == 4 then return SECRET, "Slay." end return "The wolves have been threatening the farmers.", "Slay the wolves." end
	ns.providers.quests._dirty = true
	local q = names(ns:GetEntries(ns.providers.quests))
	check(q["Wolves Across the Border"] and q["Hidden Words"] and count(q) == 2, "a quest whose title is a secret value is left out; the others stay")
	check(q["Hidden Words"] and not q["Hidden Words"]._ltext:find("secret", 1, true) and q["Hidden Words"].desc == nil, "a secret description isn't read")
	C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo, _G.GetQuestLogQuestText = saveNum, saveInfo, saveText
	ns.providers.quests._dirty = true
	-- a bag item whose name is secret (and no link to read it from) is skipped, not an error
	local saveSlots, saveItem = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
	C_Container.GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end
	C_Container.GetContainerItemInfo = function(b, s)
		if b ~= 0 then return nil end
		if s == 1 then return { itemID = 6948, itemName = "Hearthstone", stackCount = 1, quality = 1 } end
		return { itemID = 4242, itemName = SECRET, stackCount = 1, quality = 1 }
	end
	ns.providers.items._dirty = true
	local it = names(ns:GetEntries(ns.providers.items))
	check(it["Hearthstone"] and not ns.providers.items._warned, "the items still index with a secret name among them")
	local secretRow = false
	for _, e in ipairs(ns:GetEntries(ns.providers.items)) do if e.itemID == 4242 then secretRow = true end end
	check(not secretRow, "the item with the secret name is left out")
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = saveSlots, saveItem
	_G.issecretvalue = nil
	ns.providers.items._dirty = true
end

io.write("[quest index from the quest rows]\n")
do
	-- the quest items index reads the Quest Log rows, not the log again on every bag event
	local saveInfo = C_QuestLog.GetInfo
	local reads = 0
	C_QuestLog.GetInfo = function(i) reads = reads + 1; return saveInfo(i) end
	ns.providers.quests._dirty = true
	ns:GetEntries(ns.providers.quests) -- (the rows are up to date)
	reads = 0
	ns.providers.items._dirty = true
	ns:GetEntries(ns.providers.items)
	check(reads == 0, "indexing your bags doesn't read the quest log again (" .. reads .. " reads)")
	check(names(ns:GetEntries(ns.providers.quests))["Wolves Across the Border"].objectives[1][1] == "Kill 10 Timber Wolves", "quest rows keep their objectives for it")
	C_QuestLog.GetInfo = saveInfo
end

io.write("[panels pressed by the game]\n")
do
	_G.BINDING_NAME_TOGGLEWORLDMAP = "Toggle World Map"
	_G.BINDING_NAME_OPENALLBAGS = "Open All Bags"
	ns.providers.panels._dirty = true
	local pn = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.panels)) do pn[e.key] = e end
	local function route(k) local r = S.Resolve(pn[k].secure, pn[k]); return r and (r.binding or r.macro or r.button) end
	check(route("World Map") == "TOGGLEWORLDMAP", "World Map: the map key: " .. tostring(route("World Map")))
	check(route("Quest Log") == "TOGGLEQUESTLOG", "Quest Log: the quest log key: " .. tostring(route("Quest Log")))
	check(route("Backpack & Bags") == "OPENALLBAGS", "Bags: the bags key: " .. tostring(route("Backpack & Bags")))
	check(route("Edit Mode") == "/editmode", "Edit Mode: a macro line the game runs: " .. tostring(route("Edit Mode")))
	check(tostring(route("Options")):find("^/run ") and tostring(route("Options")):find("SettingsPanel", 1, true), "Options: a /run line the game runs: " .. tostring(route("Options")))
	check(tostring(route("AddOn List")):find("ShowUIPanel(AddonList)", 1, true), "AddOn List: a /run line the game runs")
	check(pn["Achievements"].secure.binding == "TOGGLEACHIEVEMENT" and pn["Collections"].secure.binding == "TOGGLECOLLECTIONS"
		and pn["Professions"].secure.binding == "TOGGLEPROFESSIONBOOK" and pn["Adventure Guide"].secure.binding == "TOGGLEENCOUNTERJOURNAL"
		and pn["Guild & Communities"].secure.binding == "TOGGLEGUILDTAB" and pn["Social / Friends"].secure.binding == "TOGGLESOCIAL"
		and pn["Calendar"].secure.binding == "TOGGLECALENDAR" and pn["Game Menu"].secure.binding == "TOGGLEGAMEMENU"
		and pn["Spellbook"].secure.binding == "TOGGLESPELLBOOK", "every window panel names the game's key for it")
	check(pn["Talents"].secure == ns.Talents.SECURE, "the Talents panel still rides the Talents key")
	-- Enter on the World Map panel: the game's key, nothing opened from Terminal's code
	WorldMapFrame.shown = false
	UI:Open("@panel world map")
	local mark = #log
	key("ENTER")
	check(S.armed == "TOGGLEWORLDMAP" and F.propagate == true and not logHas("ToggleWorldMap", mark + 1), "Enter: the map key is pressed, ToggleWorldMap never called from here")
	FlushAll()
	-- the map already showing: only pointed at, never toggled closed
	WorldMapFrame.shown = true
	UI:Open("@panel world map"); mark = #log; key("ENTER")
	check(S.armed == nil and not UI:IsShown() and not logHas("ToggleWorldMap", mark + 1), "the map open: Enter doesn't toggle it closed")
	WorldMapFrame.shown = false
	UI:Hide(); FlushAll()
	_G.BINDING_NAME_TOGGLEWORLDMAP, _G.BINDING_NAME_OPENALLBAGS = nil, nil
	ns.providers.panels._dirty = true
end

io.write("[Legacy panel]\n")
do
	-- WoW Forever's Legacy window: listed only where the client has its micro button
	_G.LegacyMicroButton = nil
	ns.providers.panels._dirty = true
	local function legacy()
		for _, e in ipairs(ns:GetEntries(ns.providers.panels)) do if e.key == "Legacy" then return e end end
	end
	check(legacy() == nil, "no Legacy panel on a client without it")
	local b = Obj("Button"); b.tooltipText = "Legacy |cffffd200(L)|r"
	_G.LegacyMicroButton = b
	ns.providers.panels._dirty = true
	local e = legacy()
	check(e and e.name == "Legacy", "the Legacy panel, named from its micro button's tooltip (key dropped): " .. tostring(e and e.name))
	local r = e and S.Resolve(e.secure, e)
	check(r and r.button == "LegacyMicroButton", "opened by the game clicking its micro button: " .. tostring(r and (r.binding or r.macro or tostring(r.button))))
	_G.LegacySystemFrame = Obj("Frame"); LegacySystemFrame.shown = false
	check(e.isOpen(e) == false, "not open while its window is hidden")
	LegacySystemFrame.shown = true
	check(e.isOpen(e) == true, "open (only pointed at) while LegacySystemFrame shows")
	check(UI:Search("@panel legacy")[1].key == "Legacy", "found by its name")
	-- without the game's route, Terminal's own code never clicks it (that would taint the window)
	local clicked = false
	b.Click = function() clicked = true end
	local printWas = ns.Print; ns.Print = function() end
	e.open()
	ns.Print = printWas
	check(not clicked, "the fallback never clicks the micro button from Terminal's code")
	-- its tabs: the game opens the window when it's closed, then clicks the tab
	local function row(k)
		for _, x in ipairs(ns:GetEntries(ns.providers.panels)) do if x.key == k then return x end end
	end
	local ch, tr = row("Legacy Challenges"), row("Legacy Tree")
	check(ch and tr and ch.tab == "LegacyChallengeTab" and tr.tab == "LegacyTreeTab", "Legacy Challenges and Legacy Tree rows")
	check(UI:Search("@panel legacy tree")[1].key == "Legacy Tree" and UI:Search("@panel challenges")[1].key == "Legacy Challenges", "found by their names")
	LegacySystemFrame.shown = false
	-- worked out for a resting pointer (every redraw): no trace lines
	local traceWas, traced = ns.Trace, 0
	ns.Trace = function() traced = traced + 1 end
	S.ClickMacro(ch.secure, ch, true)
	ns.Trace = traceWas
	check(traced == 0, "a hover's quiet macro traces nothing: " .. traced)
	local m = ch and S.Resolve(ch.secure, ch)
	local text = m and m.macro or ""
	check(text:match("^/click LegacyMicroButton\n/run local t=LegacyChallengeTab "), "window closed: the micro button, then the tab: " .. text)
	check(#text <= S.MACRO_MAX, "within a macro's length: " .. #text)
	local body = text:match("\n/run (.*)$")
	check(body and loadstring(body), "the /run line is valid Lua")
	-- run what the game would: a button tab is clicked, a plain frame's mouse scripts run
	local tabClicked, downs = false, 0
	_G.LegacyChallengeTab = { Click = function() tabClicked = true end }
	if body then loadstring(body)() end
	check(tabClicked, "a button tab is clicked")
	_G.LegacyChallengeTab = { GetScript = function(_, s) return function() downs = downs + 1 end end }
	if body then loadstring(body)() end
	check(downs == 2, "a plain-frame tab gets its mouse down and up scripts: " .. downs)
	_G.LegacyChallengeTab = nil
	if body then loadstring(body)() end -- not loaded: nothing errors
	LegacySystemFrame.shown = true
	m = tr and S.Resolve(tr.secure, tr)
	text = m and m.macro or ""
	check(text:match("^/run local t=LegacyTreeTab "), "window open: only the tab: " .. text)
	check(tr.isOpen(tr) == false, "a tab row always presses (clicking the shown tab is harmless)")
	b.Click = function() clicked = true end
	printWas = ns.Print; ns.Print = function() end
	tr.open()
	ns.Print = printWas
	check(not clicked, "a tab row's fallback never clicks from Terminal's code")
	_G.LegacyMicroButton, _G.LegacySystemFrame = nil, nil
	ns.providers.panels._dirty = true
	check(row("Legacy Tree") == nil, "no tab rows without the Legacy window")
	ns.providers.panels._dirty = true
end

io.write("[panel tabs: group finder's browser and who listing]\n")
do
	local function row(k)
		for _, x in ipairs(ns:GetEntries(ns.providers.panels)) do if x.key == k then return x end end
	end
	local S = ns.Secure
	local hadLFD = _G.LFDMicroButton
	_G.LFDMicroButton = _G.LFDMicroButton or Obj("Button")
	ns.providers.panels._dirty = true
	local gb, wl = row("Group Browser"), row("Who Listing")
	check(gb and wl and gb.tab == "BrowsingTab" and wl.tab == "WhoListingTab", "Group Browser and Who Listing rows")
	check(UI:Search("@panel group browser")[1].key == "Group Browser" and UI:Search("@panel who listing")[1].key == "Who Listing", "found by their names")
	-- window closed (the tab not even loaded): the micro button, then the tab
	_G.BrowsingTab, _G.WhoListingTab, _G.PVEFrame = nil, nil, nil
	local m = S.Resolve(gb.secure, gb)
	local text = m and m.macro or ""
	check(text:match("^/click LFDMicroButton\n/run local t=BrowsingTab "), "window closed: the micro button, then the tab: " .. text)
	check(#text <= S.MACRO_MAX and loadstring(text:match("\n/run (.*)$")), "within a macro, valid Lua")
	-- the window open on another page: never clicked shut, only the tab
	local win = Obj("Frame"); win.shown = true
	local tab = Obj("Button"); tab.shown = false
	tab.GetParent = function() return win end
	win.GetParent = function() return UIParent end
	_G.WhoListingTab = tab
	m = S.Resolve(wl.secure, wl)
	text = m and m.macro or ""
	check(text:match("^/run local t=WhoListingTab "), "the window open: only the tab: " .. text)
	check(wl.isOpen(wl) == false, "a tab row always presses")
	_G.WhoListingTab, _G.LFDMicroButton = nil, hadLFD
	ns.providers.panels._dirty = true
end

io.write("[panel tabs: guild roster/info, character side tabs]\n")
do
	local function row(k)
		for _, x in ipairs(ns:GetEntries(ns.providers.panels)) do if x.key == k then return x end end
	end
	ns.providers.panels._dirty = true
	-- guild & communities: tabs are keys under CommunitiesFrame, clicked from a game-run /run line
	local savedCF, savedGM, savedModes = _G.CommunitiesFrame, _G.GuildMicroButton, _G.COMMUNITIES_FRAME_DISPLAY_MODES
	_G.GuildMicroButton = Obj("Button")
	local roster, info = row("Guild Roster"), row("Guild Info")
	check(roster and info, "Guild Roster and Guild Info rows")
	check(UI:Search("@panel guild roster")[1].key == "Guild Roster" and UI:Search("@panel guild info")[1].key == "Guild Info", "found by name")
	_G.CommunitiesFrame = nil
	local m = roster and S.Resolve(roster.secure, roster)
	local text = m and m.macro or ""
	check(text == "/click GuildMicroButton\n/run local t=CommunitiesFrame and CommunitiesFrame.RosterTab if t then t:Click() end",
		"window closed: the guild button, then the roster tab: " .. text)
	local body = text:match("\n/run (.*)$")
	check(body and loadstring(body), "valid Lua")
	if body then loadstring(body)() end -- no window: nothing errors
	local clickedTab = false
	_G.CommunitiesFrame = Obj("Frame"); CommunitiesFrame.shown = true
	CommunitiesFrame.RosterTab = { Click = function() clickedTab = true end }
	if body then loadstring(body)() end
	check(clickedTab, "the game clicks CommunitiesFrame.RosterTab")
	m = info and S.Resolve(info.secure, info)
	text = m and m.macro or ""
	check(text == "/run local t=CommunitiesFrame and CommunitiesFrame.GuildInfoTab if t then t:Click() end", "window open: only the tab: " .. text)
	_G.COMMUNITIES_FRAME_DISPLAY_MODES = { ROSTER = 2, GUILD_INFO = 5 }
	local mode = 2
	CommunitiesFrame.GetDisplayMode = function() return mode end
	check(roster.isOpen(roster) == true and info.isOpen(info) == false, "open only on its own page (roster)")
	mode = 5
	check(roster.isOpen(roster) == false and info.isOpen(info) == true, "open only on its own page (guild info)")
	CommunitiesFrame.shown = false
	check(info.isOpen(info) == false, "closed window: not open")
	_G.CommunitiesFrame, _G.GuildMicroButton, _G.COMMUNITIES_FRAME_DISPLAY_MODES = savedCF, savedGM, savedModes

	-- character side tabs: the same route as the equipment sets page
	local cf, micro, pd = _G.CharacterFrame, _G.CharacterMicroButton, _G.PaperDollFrame
	local savedCollapsed, savedPdShown, savedGet = cf.rightPaneCollapsed, pd.shown, _G.GetPaperDollSideBarFrame
	_G.CharacterMicroButton = micro or Obj("Button")
	local panes = {}
	for i = 1, 3 do
		local t = Obj("Button"); t.__name = "PaperDollSideBarTab" .. i; t.shown = true
		_G["PaperDollSideBarTab" .. i] = t
		panes[i] = Obj("Frame"); panes[i].shown = false
	end
	_G.GetPaperDollSideBarFrame = function(i) return panes[i] end
	local stats, sets, titles = row("Character Stats"), row("Equipment Manager"), row("Titles")
	check(stats and sets and titles and titles.side == 3, "Character Stats, Equipment Manager and Titles rows")
	check(UI:Search("@panel titles")[1].key == "Titles", "Titles found by name")
	pd.shown = false; cf.rightPaneCollapsed = true
	m = titles and S.Resolve(titles.secure, titles)
	text = m and m.macro or ""
	check(text:match("^/click CharacterMicroButton\n") and text:match("/click PaperDollSideBarTab3$"), "closed: the character button, then the third tab: " .. text)
	pd.shown = true; cf.rightPaneCollapsed = false
	m = stats and S.Resolve(stats.secure, stats)
	text = m and m.macro or ""
	check(text == "/click PaperDollSideBarTab1", "open with the pane out: only the tab: " .. text)
	panes[2].shown = true
	check(sets.isOpen(sets) == true and stats.isOpen(stats) == false and titles.isOpen(titles) == false, "open only while its own pane shows")
	pd.shown = false
	check(sets.isOpen(sets) == false, "not open while the paper doll is hidden")
	local printWas = ns.Print; ns.Print = function() end
	titles.open(titles)
	ns.Print = printWas
	for i = 1, 3 do _G["PaperDollSideBarTab" .. i] = nil end
	cf.rightPaneCollapsed, pd.shown, _G.GetPaperDollSideBarFrame, _G.CharacterMicroButton = savedCollapsed, savedPdShown, savedGet, micro
	ns.providers.panels._dirty = true
end

io.write("[slash lines pressed by the game]\n")
do
	UI:Open("/foo bar baz")
	local mark = #log
	key("ENTER")
	local mp = _G.TerminalMacroProxy
	check(S.armed == "MACRO" and mp and mp.attrs.macrotext == "/foo bar baz" and F.propagate == true, "Enter on a slash command: the game runs the line: " .. tostring(mp and mp.attrs.macrotext))
	check(not logHas("CHAT /foo bar baz", mark + 1), "...not Terminal's chat box")
	mp.scripts.PostClick(mp, "LeftButton", true); FlushAll()
	check(not UI:IsShown() and S.armed == nil, "done: the terminal closes")
	UI:Open("/reload")
	key("ENTER")
	check(mp.attrs.macrotext == "/reload", "no arguments: the command alone: " .. tostring(mp.attrs.macrotext))
	UI:Disarm(); UI:Hide(); FlushAll()
	-- the fallback (no secure button) still types into the chat box
	local r = UI:WordSearch(ns:GetEntries(ns.providers.slash), "/foo")
	mark = #log
	r[1].activate(r[1], "x")
	check(logHas("CHAT /foo x", mark + 1), "without the secure route the chat box runs it")
	-- /console alone: nothing to set
	local con
	for _, e in ipairs(ns:GetEntries(ns.providers.slash)) do if e.name == "/console" then con = e end end
	check(con and con.secure and con.needsArgs and S.Resolve(con.secure, con) == nil, "/console with nothing after it is never pressed")
end

io.write("[no clicks inside Blizzard's windows]\n")
do
	local shown
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t, d) shown = t; return origShow(self, t, d) end
	-- the profession window: the recipe is scrolled to and pointed at, its row never clicked
	local savePF = _G.ProfessionsFrame
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = true
	local row = Obj("Button"); row.shown = true; row.text = "Mana Well"
	row.Click = function() log[#log + 1] = "ROWCLICK Mana Well (review)" end
	ProfessionsFrame.GetChildren = function() return row end
	local mark = #log
	P.SelectRecipe(12, "Mana Well"); FlushAll()
	check(shown == row and not logHas("ROWCLICK Mana Well (review)", mark + 1), "a recipe is pointed at in the window, never clicked (taint)")
	_G.ProfessionsFrame = savePF
	-- Blizzard's talent window: its tree tabs aren't clicked; ClassicUIForever's still are
	local TL = ns.Talents
	local W = Obj("Frame"); W.shown = true; W.__name = "PlayerSpellsFrame"; _G.PlayerSpellsFrame = W
	local tab = Obj("Button"); tab.shown = true; tab.text = "Fury"
	local node = Obj("Button"); node.shown = true; node.GetNodeID = function() return 1002 end
	tab.Click = function() log[#log + 1] = "TABCLICK Fury (review)"; W.GetChildren = function() return tab, node end end
	W.GetChildren = function() return tab end
	local saveCUF = _G.ClassicUIForeverTalents
	_G.ClassicUIForeverTalents = nil
	shown = nil; mark = #log
	TL.Highlight(1002, "Fury", 2); FlushAll()
	check(not logHas("TABCLICK Fury (review)", mark + 1) and shown == nil, "PlayerSpellsFrame on another tree: its tab isn't clicked from here")
	_G.PlayerSpellsFrame = nil
	local C = Obj("Frame"); C.shown = true; C.__name = "ClassicUIForeverTalents"; _G.ClassicUIForeverTalents = C
	tab.Click = function() log[#log + 1] = "TABCLICK Fury (review)"; C.GetChildren = function() return tab, node end end
	C.GetChildren = function() return tab end
	shown = nil; mark = #log
	TL.Highlight(1002, "Fury", 2); FlushAll()
	check(logHas("TABCLICK Fury (review)", mark + 1) and shown == node, "ClassicUIForever's window: its tab is clicked, then the node pointed at")
	_G.ClassicUIForeverTalents = saveCUF
	ns.Highlight.Show = origShow
	-- the game's options and addons' pages: opened by a /run line the game presses
	local saveSettings, saveSP = _G.Settings, _G.SettingsPanel
	_G.Settings = { OpenToCategory = function() return true end }
	_G.SettingsPanel = Obj("Frame"); SettingsPanel.shown = false
	local function Cat(name, id, inits) return { GetName = function() return name end, GetID = function() return id end, GetSubcategories = function() return {} end, inits = inits } end
	local gfx = Cat("Graphics", 7, { { GetName = function() return "Display Mode" end, data = { name = "Display Mode" } } })
	SettingsPanel.GetAllCategories = function() return { gfx } end
	SettingsPanel.GetLayout = function(_, cat) return { GetInitializers = function() return cat.inits end } end
	ns.providers.gameoptions._dirty = true
	local go = names(ns:GetEntries(ns.providers.gameoptions))
	check(go["Display Mode"] and S.Resolve(go["Display Mode"].secure, go["Display Mode"]).macro == '/run Settings.OpenToCategory(7,"Display Mode")',
		"a setting: the game opens its page scrolled to it: " .. tostring(go["Display Mode"] and S.Resolve(go["Display Mode"].secure, go["Display Mode"]).macro))
	check(go["Graphics"] and S.Resolve(go["Graphics"].secure, go["Graphics"]).macro == "/run Settings.OpenToCategory(7)", "a page: the game opens it")
	ns.providers.gameoptions._dirty = true
	-- addons: options page by the game, a minimap button still clicked by Terminal, the AddOn list otherwise
	local cat = { GetName = function() return "Cool Addon 1" end, GetID = function() return 42 end }
	SettingsPanel.GetAllCategories = function() return { cat } end
	ns.providers.addons._dirty = true
	local a = names(ns:GetEntries(ns.providers.addons))
	check(a["Cool Addon 1"] and S.Resolve(a["Cool Addon 1"].secure, a["Cool Addon 1"]).macro == "/run Settings.OpenToCategory(42)", "an addon's options page: the game opens it")
	check(a["Cool Addon 2"] and S.Resolve(a["Cool Addon 2"].secure, a["Cool Addon 2"]).macro == "/run if AddonList then ShowUIPanel(AddonList) end", "no page or button: the AddOn list, by the game")
	a["Cool Addon 2"].launch = { button = Obj("Button") }
	check(S.Resolve(a["Cool Addon 2"].secure, a["Cool Addon 2"]) == nil, "a minimap button: no macro, Terminal clicks it itself")
	_G.Settings, _G.SettingsPanel = saveSettings, saveSP
	ns.providers.addons._dirty = true
end

io.write("[reagent names arriving]\n")
do
	-- (an indexed profession of our own: the tests before emptied the store)
	local store = P.Store()
	store[171] = { name = "Alchemy", skillLine = 171, fromList = true, updated = 1, list = {
		{ id = 11, name = "Elixir of Strength", learned = true, categoryID = 1, reagents = { { 100, 2 } } } } }
	local list = store[171].list
	local asked = 0
	local saveReq, saveGII = C_Item.RequestLoadItemDataByID, C_Item.GetItemInfo
	C_Item.RequestLoadItemDataByID = function() asked = asked + 1 end
	C_Item.GetItemInfo = function(id, ...) if id == 5555 then return nil end return saveGII(id, ...) end
	list[#list + 1] = { id = 19, name = "Nameless Brew", learned = true, categoryID = 1, reagents = { { 5555, 1 } } }
	ns.providers.recipes._dirty = true
	ns:GetEntries(ns.providers.recipes)
	check((P.waitingNames or {})[5555] == true and P.watchingNames == true and asked == 1, "an unnamed reagent: its name is asked for and the event listened for")
	ns.providers.recipes._dirty = true; ns:GetEntries(ns.providers.recipes)
	ns.providers.recipes._dirty = true; ns:GetEntries(ns.providers.recipes)
	check(asked == 2 and P.watchingNames == false, "asked twice at most; nothing pending: the event is let go (" .. asked .. " asks)")
	list[#list] = nil
	C_Item.RequestLoadItemDataByID, C_Item.GetItemInfo = saveReq, saveGII
	ns.providers.recipes._dirty = true
	ns:GetEntries(ns.providers.recipes)
end

io.write("[reagent names: failing or empty answers]\n")
do
	local store = P.Store()
	store[171] = store[171] or { name = "Alchemy", skillLine = 171, fromList = true, updated = 1, list = {} }
	local list = store[171].list
	local saveReq, saveGII, saveBy = C_Item.RequestLoadItemDataByID, C_Item.GetItemInfo, C_Item.GetItemNameByID
	local round = 1
	C_Item.RequestLoadItemDataByID = function() error("request failed") end
	C_Item.GetItemNameByID = function(id, ...) if id == 5556 then return nil end return saveBy and saveBy(id, ...) end
	C_Item.GetItemInfo = function(id, ...)
		if id == 5556 then if round == 1 then return "" end return "Late Herb" end
		if id == 5557 then error("no info") end
		return saveGII(id, ...)
	end
	list[#list + 1] = { id = 20, name = "Herbal Brew", learned = true, categoryID = 1, reagents = { { 5556, 1 } } }
	list[#list + 1] = { id = 21, name = "Odd Brew", learned = true, categoryID = 1, reagents = { { 5557, 1 } } }
	ns.providers.recipes._dirty = true
	local got = names(ns:GetEntries(ns.providers.recipes))
	check(got["Herbal Brew"] and got["Odd Brew"], "recipes listed though the name lookups fail or say nothing")
	round = 2
	ns.providers.recipes._dirty = true
	local e = names(ns:GetEntries(ns.providers.recipes))["Herbal Brew"]
	check(e and (rawget(e, "_ltext") or ""):find("late herb", 1, true), "an empty name isn't kept: the real one is used once it comes")
	list[#list] = nil; list[#list] = nil
	C_Item.RequestLoadItemDataByID, C_Item.GetItemInfo, C_Item.GetItemNameByID = saveReq, saveGII, saveBy
	ns.providers.recipes._dirty = true
	ns:GetEntries(ns.providers.recipes)
end

io.write("[names in every language]\n")
do
	local store = P.Store()
	local list = store[171].list
	list[#list + 1] = { id = 18, name = "Élixir Étrange", learned = true, categoryID = 1 }
	check(P.NameIndex()["élixir étrange"] ~= nil, "the recipe index is keyed by ns.Lower (accented names fold)")
	list[#list] = nil
	store[171] = nil
	P.MarkDirty()
	check(ns.Camp.IsCampName(ns.Lower("Mana Well")) and ns.Camp.IsCampName("mana well"), "camp names are looked up the same way")
end

io.write("[aliases]\n")
do
	check(ns:ResolveProvider("equipment") == ns.providers.equipmentset, "@equipment: the equipment sets")
	check(ns:ResolveProvider("gear") == ns.providers.gear and ns:ResolveProvider("equip") == ns.providers.gear, "@gear / @equip: the pieces")
	check(ns:ResolveProvider("settings") == ns.providers.gameoptions and ns:ResolveProvider("setting") == ns.providers.gameoptions, "@settings: the game's options")
	check(ns:ResolveProvider("cvar") == ns.providers.cvars and ns:ResolveProvider("console") == ns.providers.cvars, "@cvar / @console: the console settings")
	check(ns:ResolveProvider("skill") == ns.providers.skills and ns:ResolveProvider("skills") == ns.providers.skills, "@skill: the Skills tab")
	check(ns:ResolveProvider("prof") == ns.providers.professions, "@prof: professions")
end

io.write("[lazy links, guards, keys]\n")
do
	local m = names(ns:GetEntries(ns.providers.mounts))["Mount1"]
	check(m and rawget(m, "link") == nil and m.getLink(m) == "|Hspell:901|h[x]|h", "a mount's link is made when wanted, not per row")
	local ach = names(UI:Search("level 10"))["Level 10"]
	check(ach and rawget(ach, "link") == nil and ach.getLink(ach) == "|Hachievement:7|h[Level 10]|h", "an achievement's link is made when wanted")
	local sp = names(ns:GetEntries(ns.providers.spells))["Fireball"]
	check(sp and rawget(sp, "link") == nil and sp.getLink(sp) == "|Hspell:101|h[x]|h", "a spell's link is made when wanted")
	local tal = names(ns:GetEntries(ns.providers.talents))["Deflection"]
	check(tal and rawget(tal, "link") == nil and tal.getLink(tal) == "|Hspell:1111|h[x]|h", "a talent's link is made when wanted")
	local mac = names(ns:GetEntries(ns.providers.macros))["Heal Macro"]
	check(mac and mac.key == "Heal Macro" and mac.index == 1, "macros are known by name, not by slot")
	-- a client without the mount journal or achievements: empty lists, no error
	local saveMJ, saveCL = _G.C_MountJournal, _G.GetCategoryList
	_G.C_MountJournal = nil
	ns.providers.mounts._dirty = true
	check(#ns:GetEntries(ns.providers.mounts) == 0 and not ns.providers.mounts._warned, "no mount journal: no mounts, no error")
	_G.GetCategoryList = nil
	ns.providers.achievements._dirty = true
	check(#ns:GetEntries(ns.providers.achievements) == 0 and not ns.providers.achievements._warned, "no achievements API: none listed, no error")
	_G.C_MountJournal, _G.GetCategoryList = saveMJ, saveCL
	ns.providers.mounts._dirty = true; ns.providers.achievements._dirty = true
	-- the map list doesn't follow you around; the options list doesn't rebuild as addons load
	local mapEvents = table.concat(ns.providers.maps.events or {}, ",")
	check(not mapEvents:find("ZONE_CHANGED_NEW_AREA", 1, true), "maps: no rebuild on changing zone")
	check(table.concat(ns.providers.gameoptions.events, ",") == "PLAYER_ENTERING_WORLD", "options: one event, not every addon load")
	-- equipment sets share one secure spec
	local saveES = _G.C_EquipmentSet
	_G.C_EquipmentSet = {
		GetEquipmentSetIDs = function() return { 1, 2 } end,
		GetEquipmentSetInfo = function(id) return "Set " .. id, 1, id, false, 3, 3, 0, 0 end,
	}
	ns.providers.equipmentset._dirty = true
	local sets = ns:GetEntries(ns.providers.equipmentset)
	check(#sets == 2 and sets[1].secondarySecure == sets[2].secondarySecure and type(sets[1].secondarySecure.macro) == "function", "every set shares the one manager spec")
	_G.C_EquipmentSet = saveES
	ns.providers.equipmentset._dirty = true
end

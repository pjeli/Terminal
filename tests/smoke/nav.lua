local T = ...
-- Turning a window to the right page by the game's own clicks (0.46.16, the player's ask; Secure.lua "Turning a
-- window"): the press's macro opens the window, then "/click TerminalNavN" lines, each a step whose PreClick picks the
-- Blizzard button to click (read only) for the secure button to click for the game. Afterwards the window fields the
-- clicks write are read (issecurevariable): one left written by anyone else turns the route off (.nav, .nav reset).
local ns, UI, check, Obj = T.ns, T.UI, T.check, T.Obj
local S = ns.Secure

-- what the game does with a macro: "/click X" clicks X; a turning step's secure button runs its PreClick, then clicks
-- the button it was given (SECURE_ACTIONS.click), if any
local function RunMacro(text)
	local clicked = {}
	for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
		local name = line:match("^/click (%S+)")
		local b = name and _G[name]
		if b then
			local isStep = b.attrs and b.attrs.type == "click"
			if isStep then
				if b.scripts.PreClick then b.scripts.PreClick(b, "LeftButton", false) end
				local t = b.attrs.clickbutton
				if t then clicked[#clicked + 1] = t; t:Click("LeftButton") end
			else
				clicked[#clicked + 1] = b; b:Click("LeftButton")
			end
		end
	end
	return clicked
end

local function Button(name, onClick)
	local b = Obj("Button"); b.shown = true; b.__name = name
	b.Click = function(self) if onClick then onClick(self) end end
	b.HasAccessConstraints = function() return false end
	return b
end

-- who wrote a field (issecurevariable): "Terminal" for the ones a test marks, else the game
local tainted = {}
local secWas = _G.issecurevariable
_G.issecurevariable = function(t, k)
	local by = tainted[t] and tainted[t][k]
	if by then return false, by end
	return true
end
local said = {}
local printWas = ns.Print
ns.Print = function(_, m) said[#said + 1] = m end
ns.db.navTainted = nil

io.write("[nav: turning windows by the game's own clicks]\n")
do -- the macro: the opening line, then step lines that fit in 255 characters; none when the route is off
	local def = { route = "spellbook", step = function() return nil end }
	local text = S.NavMacro(def, {}, "/click SpellbookMicroButton")
	local steps = select(2, text:gsub("\n/click TerminalNav%d", ""))
	check(text:find("^/click SpellbookMicroButton\n/click TerminalNav%d") and steps >= 8 and #text <= S.MACRO_MAX,
		"an opening line and step lines, within 255 characters: " .. steps .. " steps, " .. #text .. " characters")
	local long = S.NavMacro(def, {}, ("x"):rep(250))
	check(long == nil, "no room for a step after the opening line: nothing (the window's own route instead)")
	ns.db.navTainted = { spellbook = { what = "test" } }
	check(S.NavMacro(def, {}, nil) == nil and not S.NavOn("spellbook") and S.NavOn("questlog"), "a route turned off: nothing")
	ns.db.navTainted = nil
	-- a step's PreClick hands its button over only when it can be clicked; a hidden or disabled one isn't
	local target = Button("SomeButton")
	local n = 0
	local plan = { route = "spellbook", step = function() n = n + 1; return target, "test" end }
	text = S.NavMacro(plan, {}, nil)
	local nav = _G[text:match("/click (TerminalNav%d)")]
	nav.scripts.PreClick(nav, "LeftButton", false)
	check(nav.attrs.clickbutton == target and nav.attrs.type == "click" and nav.attrs.useOnKeyDown == false, "a step: its button set for the secure click")
	target.shown = false
	nav.scripts.PreClick(nav, "LeftButton", false)
	check(nav.attrs.clickbutton == nil, "a hidden button: nothing clicked")
	target.shown = true
	target.IsEnabled = function() return false end
	nav.scripts.PreClick(nav, "LeftButton", false)
	check(nav.attrs.clickbutton == nil, "a disabled button: nothing clicked")
	target.IsEnabled = nil
	for _ = 1, S.NAV_STEPS + 2 do nav.scripts.PreClick(nav, "LeftButton", false) end
	check(n == S.NAV_STEPS and nav.attrs.clickbutton == nil, "at most NAV_STEPS steps in one press: " .. n)
	T.FlushAll()
end

do -- the spellbook (the game's own): its micro button when closed, then the search cleared, the tab, the page arrows
	local SP = ns.Spells
	local savedPSF, savedFind, savedCUF = _G.PlayerSpellsFrame, C_SpellBook.FindSpellBookSlotForSpell, _G.ClassicUIForeverAPI
	_G.ClassicUIForeverAPI = nil
	local book = Obj("Frame"); book.shown = false
	_G.PlayerSpellsFrame = Obj("Frame"); PlayerSpellsFrame.shown = true; PlayerSpellsFrame.SpellBookFrame = book
	_G.SpellbookMicroButton = Button("SpellbookMicroButton", function() book.shown = true end)
	local curTab = 1
	local pc = { currentPage = 1 }
	pc.NextPageButton = Button(nil, function() pc.currentPage = pc.currentPage + 1 end)
	pc.PrevPageButton = Button(nil, function() pc.currentPage = pc.currentPage - 1 end)
	local tabButtons = {}
	for i = 1, 2 do tabButtons[i] = Button(nil, function() curTab = i; pc.currentPage = 1 end) end
	book.CategoryTabSystem = { GetTabButton = function(_, id) return tabButtons[id] end }
	book.GetTab = function() return curTab end
	local function Cat(id, lo, hi)
		return { GetTabID = function() return id end, ContainsSlot = function(_, s) return s >= lo and s <= hi end }
	end
	book.categoryMixins = { Cat(1, 1, 10), Cat(2, 11, 20) }
	local function El(slot) return { slotIndex = slot, spellBank = 0 } end
	book.PagedSpellsFrame = { viewsPerPage = 2, PagingControls = pc,
		viewDataList = { { El(11), El(12) }, { El(13) }, { El(14), { isSpacer = true } }, { El(15) } } }
	book.SearchBox = Obj("EditBox"); book.SearchBox.text = "fire"
	book.SearchBox.clearButton = Button(nil, function() book.SearchBox.text = "" end)
	C_SpellBook.FindSpellBookSlotForSpell = function(id) if id == 202 then return 15, 0 end end
	local e = { name = "Fireball", spellID = 202 }
	-- the press: opens the book, then turns it (the steps chosen as it goes)
	local text = S.Resolve(SP.SECURE, e)
	check(text and text.macro and text.macro:find("^/click SpellbookMicroButton\n/click TerminalNav%d"), "closed: its micro button, then the steps: " .. tostring(text and (text.macro or text.binding)))
	local clicked = RunMacro(text.macro)
	check(book.SearchBox.text == "" and curTab == 2 and pc.currentPage == 2, "the search cleared, the spell's tab, its page (4th view, 2 a page): tab "
		.. curTab .. ", page " .. pc.currentPage)
	check(clicked[1] == SpellbookMicroButton and clicked[2] == book.SearchBox.clearButton and clicked[3] == tabButtons[2]
		and clicked[4] == pc.NextPageButton and #clicked == 4, "click by click: micro button, clear, tab, next page (" .. #clicked .. " clicks)")
	-- open already: no opening line (the micro button would close it), steps only; turned back from a later page
	pc.currentPage = 3
	text = S.Resolve(SP.SECURE, e)
	check(text.macro and text.macro:find("^/click TerminalNav%d") and not text.macro:find("MicroButton"), "open: steps only")
	RunMacro(text.macro)
	check(pc.currentPage == 2, "from a later page: back to its page: " .. pc.currentPage)
	check(SP.NavStep(e) == nil and select(2, SP.NavStep(e)) == "on its page", "on its page: nothing more to click")
	-- the entry's open check: the book showing doesn't stop the press while it turns
	check(SP.IsOpen(e) == false, "the book showing: still pressed (it's turned)")
	ns.db.navTainted = { spellbook = { what = "test" } }
	check(SP.IsOpen(e) == true, "turning it off: the book showing presses nothing (pointed at only)")
	ns.db.navTainted = nil
	-- taint check: the page written by anyone else after the press turns the route off, once, said in chat
	tainted[pc] = nil
	T.FlushAll()
	said = {}
	text = S.Resolve(SP.SECURE, e)
	pc.currentPage = 1
	RunMacro(text.macro)
	tainted[pc] = { currentPage = "Terminal" }
	T.FlushAll()
	check(ns.db.navTainted and ns.db.navTainted.spellbook and #said == 1 and said[1]:find("only opens it and points", 1, true),
		"the page left written by Terminal: turning the book is off, said once: " .. tostring(said[1]))
	text = S.Resolve(SP.SECURE, e)
	check(text and text.binding == "TOGGLESPELLBOOK" and not text.macro, "off: the spellbook key, and pointing")
	local out = ns:FindCommand("nav").run("")
	check(table.concat(out, "\n"):find("your spellbook: off", 1, true), ".nav lists it: " .. table.concat(out, " | "))
	ns:FindCommand("navigate").run("reset")
	check(ns.db.navTainted == nil and S.NavOn("spellbook"), ".nav reset: on again")
	-- already tainted before the press (someone else's): not blamed on the turning
	tainted[pc] = { currentPage = "SomeAddon" }
	said = {}
	text = S.Resolve(SP.SECURE, e)
	RunMacro(text.macro)
	T.FlushAll()
	check(S.NavOn("spellbook") and #said == 0, "tainted before the press already: not the turning's doing")
	tainted[pc] = nil
	-- a blocked action blamed on Terminal right after a turning press: off too
	text = S.Resolve(SP.SECURE, e)
	RunMacro(text.macro)
	S.OnBlocked("SomeProtectedCall()", GetTime())
	check(not S.NavOn("spellbook"), "a blocked action right after the press: off")
	ns.db.navTainted = nil
	T.FlushAll()
	-- ClassicUIForever's book: its own route (its key, turned by its own buttons), never these clicks
	_G.ClassicUIForeverAPI = { GetFrame = function() return book end, IsOn = function() return true end }
	text = S.Resolve(SP.SECURE, e)
	check(text and not text.macro, "ClassicUIForever's book: not turned by these clicks")
	_G.ClassicUIForeverAPI = nil
	-- no micro button to open it: the spellbook key (pointing), as before
	book.shown = false
	local mb = _G.SpellbookMicroButton
	_G.SpellbookMicroButton = nil
	text = S.Resolve(SP.SECURE, e)
	check(text and text.binding == "TOGGLESPELLBOOK", "closed, no micro button: the spellbook key")
	_G.SpellbookMicroButton = mb
	_G.PlayerSpellsFrame, C_SpellBook.FindSpellBookSlotForSpell, _G.ClassicUIForeverAPI = savedPSF, savedFind, savedCUF
	_G.SpellbookMicroButton = nil
	T.FlushAll()
end

do -- the quest log (the map's quest panel): its micro button when closed, then back from another quest's details,
	-- the quest's folded header, the quest's row (the log shows its details)
	local Q = ns.Quests
	local savedQMF, savedQSF, savedQLMB = _G.QuestMapFrame, _G.QuestScrollFrame, _G.QuestLogMicroButton
	local savedCUIF = _G.ForeverClassicUIQuestLog
	_G.ForeverClassicUIQuestLog = nil
	local qm = Obj("Frame"); qm.shown = false
	_G.QuestMapFrame = qm
	_G.QuestLogMicroButton = Button("QuestLogMicroButton", function() qm.shown = true end)
	local det = Obj("Frame"); det.shown = false
	qm.DetailsFrame = det
	det.BackFrame = { BackButton = Button(nil, function() det.shown = false end) }
	local folded = false
	local row = Button(nil, function() det.shown = true; det.questID = 33 end); row.questID = 33
	local hdr = Button(nil, function() folded = false end); hdr.questLogIndex = 1
	local function Pool(...) local a = {} for _, f in ipairs({ ... }) do a[f] = true end return { EnumerateActive = function(self) return pairs(a) end } end
	_G.QuestScrollFrame = { titleFramePool = Pool(row), headerFramePool = Pool(hdr) }
	local giWas, liWas = C_QuestLog.GetInfo, C_QuestLog.GetLogIndexForQuestID
	C_QuestLog.GetLogIndexForQuestID = function(id) return id == 33 and 2 or nil end
	C_QuestLog.GetInfo = function(i) if i == 1 then return { isHeader = true, isCollapsed = folded } end return { questID = 33 } end
	local e = { name = "Wolves Across the Border", questID = 33 }
	local text = S.Resolve(Q.NAV_SECURE, e)
	check(text and text.macro and text.macro:find("^/click QuestLogMicroButton\n/click TerminalNav%d"), "closed: its micro button, then the steps: "
		.. tostring(text and (text.macro or text.binding)))
	local clicked = RunMacro(text.macro)
	check(det.shown and det.questID == 33 and clicked[2] == row and #clicked == 2, "the log opened, the quest's row clicked: its details show")
	-- another quest's details showing: back to the list, then the row
	det.questID = 34
	text = S.Resolve(Q.NAV_SECURE, e)
	check(not text.macro:find("QuestLogMicroButton"), "open: steps only")
	clicked = RunMacro(text.macro)
	check(clicked[1] == det.BackFrame.BackButton and clicked[2] == row and det.shown and det.questID == 33, "another quest's details: back, then its row")
	-- its header folded (no row for it): the header is unfolded (its row comes with the log's next update)
	det.shown, folded = false, true
	row.shown = false
	local step, why = Q.NavStep(e)
	check(step == hdr and why:find("unfold", 1, true), "a folded header: unfolded: " .. tostring(why))
	row.shown = true
	-- Shift held: no click (the log would track the quest instead)
	local shiftWas = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	check(Q.NavStep(e) == nil, "Shift held: nothing clicked")
	_G.IsShiftKeyDown = shiftWas
	-- a classic-style log (ClassicUIForever's): its own route
	_G.ForeverClassicUIQuestLog = Obj("Frame"); ForeverClassicUIQuestLog.shown = true
	text = S.Resolve(Q.NAV_SECURE, e)
	check(text and not text.macro, "a classic-style log showing: not turned by these clicks")
	_G.ForeverClassicUIQuestLog = nil
	-- the panel row "Quest Log" (no quest): the quest key, as before
	text = S.Resolve(Q.NAV_SECURE, { name = "Quest Log" })
	check(text and not text.macro, "no quest: the quest key")
	C_QuestLog.GetInfo, C_QuestLog.GetLogIndexForQuestID = giWas, liWas
	_G.QuestMapFrame, _G.QuestScrollFrame, _G.QuestLogMicroButton = savedQMF, savedQSF, savedQLMB
	_G.ForeverClassicUIQuestLog = savedCUIF
	T.FlushAll()
end

do -- Options > Keybindings: the page scrolled to the action's section (the game's own call), the section unfolded by a click
	local K = ns.Keybinds
	local savedSP, savedSettings, savedU = _G.SettingsPanel, _G.Settings, _G.C_SettingsUtil
	_G.Settings = { KEYBINDINGS_CATEGORY_ID = 42 }
	_G.C_SettingsUtil = { OpenSettingsPanel = function() end }
	local data = { name = "Movement Keys", expanded = false }
	local section = Obj("Frame"); section.shown = true
	section.GetElementData = function() return { data = data } end
	section.Button = Button(nil, function() data.expanded = not data.expanded end)
	local box = Obj("Frame"); box.shown = true; box.frames = { section }
	local sp = Obj("Frame"); sp.shown = true
	sp.GetSettingsList = function() return { ScrollBox = box } end
	sp.GetCurrentCategory = function() return { GetID = function() return 42 end } end
	_G.SettingsPanel = sp
	local e = { name = "Move Forward", rowText = "Move Forward", category = "Movement Keys" }
	local text = K.NavMacro(e)
	check(text:find('^/run C_SettingsUtil.OpenSettingsPanel%(42,"Movement Keys"%)\n/click TerminalNav%d'), "the page at the section by name, then the steps: " .. text)
	RunMacro(text)
	check(data.expanded == true, "the folded section unfolded by its header's click")
	check(K.NavStep(e) == nil, "unfolded: nothing more to click")
	-- the row in view or not (laid out further down the section than the list shows)
	local G = ns.GameOptions
	box.GetTop, box.GetBottom = function() return 500 end, function() return 100 end
	local r = Obj("Frame"); r.shown = true
	r.GetParent = function() return section end
	section.GetParent = function() return box end
	r.GetTop, r.GetBottom = function() return 300 end, function() return 275 end
	check(G.InView(r, sp) == true, "a row inside the list: in view")
	r.GetTop, r.GetBottom = function() return 60 end, function() return 35 end
	check(G.InView(r, sp) == false, "a row below the list's bottom edge: not in view (pointed at once scrolled to)")
	-- the Quick Keybind row (no section): only the page
	check(K.NavMacro({ name = "Quick Keybind Mode" }) == "/run C_SettingsUtil.OpenSettingsPanel(42)", "no section: only the page")
	-- turned off: only the page, and the page showing presses nothing (pointing only)
	ns.db.navTainted = { keybinds = { what = "test" } }
	check(K.NavMacro(e) == "/run C_SettingsUtil.OpenSettingsPanel(42)", "off: only the page")
	ns.db.navTainted = nil
	_G.SettingsPanel, _G.Settings, _G.C_SettingsUtil = savedSP, savedSettings, savedU
	T.FlushAll()
end

ns.Print = printWas
_G.issecurevariable = secWas
ns.db.navTainted = nil

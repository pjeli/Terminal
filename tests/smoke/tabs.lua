-- (0.53.5, the player's ask) several lists open at once: Ctrl+T opens a tab, Ctrl+1-4 switch, Ctrl+Tab goes
-- round, Ctrl+Shift+W closes one; each tab keeps its search (and mode) and keeps itself up to date.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local key, typeText, withCtrl, query = T.key, T.typeText, T.withCtrl, T.query
local Tabs = ns.Tabs
local function withShift(fn) local s = _G.IsShiftKeyDown; _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = s end

io.write("[tabs: Ctrl+T, Ctrl+1-4, Ctrl+Tab, Ctrl+Shift+W]\n")
local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, time = _G.GetTime, tabs = ns.db.tabs }
local rows = {}
for i = 1, 5 do rows[i] = { name = ("Linen Cloth %d"):format(i), itemID = 60000 + i, key = i } end
rows[6] = { name = "Wool Cloth", itemID = 60010, key = 10 }
local function Collect() local out = {} for i, r in ipairs(rows) do out[i] = r end return out end
ns.providers, ns.providerOrder = {}, {}
ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = Collect })
ns:RegisterProvider("spells", { label = "Spell", aliases = { "spell" }, collect = function() return { { name = "Frost Nova", key = "nova" } } end })
ns.db.easyMode = false
UI:EasyChanged()
_G.GetTime = function() return T.clock() end
ns.db.tabs = nil
UI.lastScan, UI.lastExtra = nil, nil

UI:Open("")
typeText("linen")
FlushAll()
check(not Tabs.On() and (UI.tabsH or 0) == 0, "no tabs to begin with: the plain prompt")
local midBefore = UI.editMid
withCtrl(function() key("T") end)
FlushAll()
check(Tabs.On() and #Tabs.List() == 2 and Tabs.Cur() == 2 and query() == "", "Ctrl+T: a second tab, empty: " .. query())
check((UI.tabsH or 0) > 0 and Tabs.strip:IsShown() and UI.editMid < midBefore, "the strip shows over the prompt, the prompt moved under it")
typeText("wool")
FlushAll()
withCtrl(function() key("1") end)
FlushAll()
check(Tabs.Cur() == 1 and query() == "linen" and UI.results[1] and UI.results[1].name:find("Linen"), "Ctrl+1: the first tab's search, searched again: " .. query())
withCtrl(function() key("2") end)
FlushAll()
check(Tabs.Cur() == 2 and query() == "wool" and UI.results[1] and UI.results[1].name == "Wool Cloth", "Ctrl+2: the second's: " .. query())
withCtrl(function() key("TAB") end)
check(Tabs.Cur() == 1 and query() == "linen", "Ctrl+Tab: the next, round: " .. query())
withCtrl(function() withShift(function() key("TAB") end) end)
check(Tabs.Cur() == 2 and query() == "wool", "Ctrl+Shift+Tab: the previous, round: " .. query())
withCtrl(function() key("4") end)
check(Tabs.Cur() == 2, "Ctrl+4 with two tabs: nothing")
local stripText = Tabs.strip.buttons[1].text:GetText() or ""
check(stripText:find("linen", 1, true) and (Tabs.strip.buttons[2].text:GetText() or ""):find("wool", 1, true),
	"each tab's label says its search: " .. stripText)

-- closed and opened again, however long after, even with Esc: the tab you were on, as it was
UI:Dismiss(); FlushAll()
UI:Toggle(); FlushAll()
check(UI:IsShown() and query() == "wool" and Tabs.Cur() == 2 and (UI.tabsH or 0) > 0, "reopened after Esc: the tab you were on: " .. query())
check(type(ns.db.tabs) == "table" and ns.db.tabs.list[1].text == "linen" and ns.db.tabs.list[2].text == "wool",
	"the tabs are saved (there after a /reload)")

-- each tab its own mode for the run: Alt+`'s Advanced in one, Simple in the other
ns.db.easyMode = true
UI:EasyChanged()
withCtrl(function() key("1") end); FlushAll()
ns.Easy.temp = { from = "linen" } -- (Alt+`: this one Advanced)
withCtrl(function() key("2") end); FlushAll()
check(ns.Easy.On() and not ns.Easy.temp, "the second tab: Simple, the mode you're in")
withCtrl(function() key("1") end); FlushAll()
check(not ns.Easy.On() and ns.Easy.temp ~= nil, "the first again: Advanced, as it was")
ns.Easy.temp = nil
ns.db.easyMode = false
UI:EasyChanged()
withCtrl(function() key("2") end); FlushAll()

-- the tab shown keeps itself up to date: a change goes up on its own once sure (no F5)
withCtrl(function() key("1") end); FlushAll()
table.insert(rows, 1, { name = "Linen Cloth New", itemID = 61000, key = 99 })
ns:Changed("items")
FlushAll()
local up = false
for _, e in ipairs(UI.Results()) do if e.name == "Linen Cloth New" then up = true end end
check(up and UI.held == nil, "a list the tab shows changed: the new rows up by themselves, nothing waiting for F5")
-- a tab not shown: a dot once a list it showed changed; looked at, gone
withCtrl(function() key("2") end); FlushAll()
check(not Tabs.Changed(Tabs.List()[1]), "nothing changed since: no dot")
table.insert(rows, 1, { name = "Linen Cloth Newer", itemID = 61001, key = 98 })
ns:Changed("items"); FlushAll()
check(Tabs.Changed(Tabs.List()[1]) and (Tabs.strip.buttons[1].text:GetText() or ""):find("•", 1, true) ~= nil,
	"the first tab's items changed while the second was shown: a dot on its label")
withCtrl(function() key("1") end); FlushAll()
withCtrl(function() key("2") end); FlushAll()
check(not Tabs.Changed(Tabs.List()[1]), "looked at: the dot gone")

-- four at most; Ctrl+W still deletes a word; Ctrl+Shift+W closes the tab shown
withCtrl(function() key("T") end); withCtrl(function() key("T") end); FlushAll()
local printed
local realPrint = ns.Print
ns.Print = function(_, msg) printed = msg end
withCtrl(function() key("T") end)
ns.Print = realPrint
check(#Tabs.List() == 4 and printed and printed:find("4", 1, true), "four tabs at most, and it says so: " .. tostring(printed))
typeText("frost nova")
withCtrl(function() key("W") end)
check(query() == "frost " and #Tabs.List() == 4, "Ctrl+W: still the word before the cursor: " .. query())
withCtrl(function() withShift(function() key("W") end) end); FlushAll()
check(#Tabs.List() == 3 and Tabs.Cur() == 3, "Ctrl+Shift+W: the tab shown closed, the one before it shown")
withCtrl(function() withShift(function() key("W") end) end); FlushAll()
withCtrl(function() key("2") end); FlushAll()
check(query() == "wool", "(the second: wool)")
withCtrl(function() withShift(function() key("W") end) end); FlushAll()
check(not Tabs.On() and (UI.tabsH or 0) == 0 and not Tabs.strip:IsShown() and query() == "linen",
	"down to one: no tabs, the strip gone, the plain prompt with what's left: " .. query())
check(UI.editMid == midBefore, "the prompt back up where it was")
UI:Dismiss(); FlushAll()
UI:Toggle(); FlushAll()
check(query() == "", "no tabs: Esc lets go of the text again, as before: " .. query())
UI:Hide(); FlushAll()

-- (review, 0.53.6) the ways in that ask for an empty prompt, or bring a text of their own, leave the tabs alone
io.write("[tabs: Alt+`, Tab+`, the tour, links, Ctrl+Tab, the caret]\n")
UI:Open(""); typeText("linen"); FlushAll()
withCtrl(function() key("T") end); typeText("wool"); FlushAll()
UI:Hide(); FlushAll()
ns.db.easyMode = true
UI:EasyChanged()
UI:AdvancedOnce(); FlushAll()
check(not UI:IsShown() and ns.Easy.On(), "Alt+` closed, with tabs: nothing (0.57.0: it never opens Terminal)")
UI:Hide(); FlushAll()
check(Tabs.List()[2].text == "wool", "and the tab as it was: " .. tostring(Tabs.List()[2].text))
UI:FuzzyOnce(); FlushAll()
check(UI.fzf and query() == "", "Tab+` closed, with tabs: fuzzy finding from an empty prompt: " .. query())
typeText("zz"); FlushAll()
withCtrl(function() key("1") end); FlushAll()
check(Tabs.List()[2].text == "wool" and query() == "linen", "switched from fuzzy finding: its words aren't kept as the tab: "
	.. tostring(Tabs.List()[2].text))
UI:Hide(); FlushAll()
UI:Open("hogger"); FlushAll() -- (a chat link, /term hogger: a text of its own)
check(query() == "hogger", "opened with a text of its own: that text")
UI:Hide(); FlushAll()
UI:Toggle(); FlushAll()
check(query() == "linen" and Tabs.List()[1].text == "linen", "the tab you were on wasn't written over by it: " .. query())
ns.Tour.Start(); FlushAll()
withCtrl(function() key("2") end); FlushAll()
check(not ns.Tour.Active() and query() == "wool" and Tabs.List()[1].text == "linen", "a switch ends the tour; its step isn't kept as a tab")
UI:Hide(); FlushAll()
ns.db.easyMode = false
UI:EasyChanged()
-- Ctrl+Tab right after ` opened it: the next tab, never Tab+`'s Tab
UI:Toggle(); FlushAll()
UI.openedByToggle = GetTime()
withCtrl(function() key("TAB") end); FlushAll()
check(Tabs.Cur() == 1 and not UI.fzf, "Ctrl+Tab just after opening: the next tab: " .. Tabs.Cur())
-- a tab of no list's rows (a sum): any change; a calculation's: none
typeText(" | count"); FlushAll()
withCtrl(function() key("2") end); FlushAll()
ns:Changed("spells"); FlushAll()
check(Tabs.Changed(Tabs.List()[1]), "a summing tab: any list's change gives it the dot")
withCtrl(function() key("1") end); FlushAll()
withCtrl(function() key("U") end); typeText("=2+2"); FlushAll()
withCtrl(function() key("2") end); FlushAll()
ns:Changed("items"); FlushAll()
check(not Tabs.Changed(Tabs.List()[1]), "a calculation's tab: no dot for a list it doesn't show")
-- the caret in the game's own text box (combat, the clipboard): where it is now
withCtrl(function() key("1") end); FlushAll()
UI:EnterEdit()
UI.edit.GetCursorPosition = function() return 1 end -- (the caret moved with the arrows: no text change)
withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "2") end); FlushAll()
UI.edit.GetCursorPosition = nil
check(Tabs.List()[1].cursor == 1, "switched from the text box: its caret kept, not a stale one: " .. tostring(Tabs.List()[1].cursor))
UI:EnterKeys()
UI:Hide(); FlushAll()

-- (0.64.5, the player: "a visual way to close a tab ... a small x on mouseover") each tab's x: shown while the pointer is
-- on the tab or the x, a click closes that tab
io.write("[tabs: the x on mouseover]\n")
UI:Toggle(); FlushAll()
withCtrl(function() key("T") end); typeText("frost"); FlushAll()
withCtrl(function() key("1") end); FlushAll()
check(#Tabs.List() == 3 and Tabs.Cur() == 1, "(three tabs, the first shown)")
local first, second = query(), Tabs.List()[2].text
local b2 = Tabs.strip.buttons[2]
local x2 = b2.close
local over = {}
b2.IsMouseOver = function() return over.tab == true end
x2.IsMouseOver = function() return over.x == true end
check(x2 and not x2:IsShown(), "no x until the pointer is on a tab")
over.tab = true; b2.scripts.OnEnter(b2)
check(x2:IsShown(), "the pointer on the second tab: its x")
check(not Tabs.strip.buttons[1].close:IsShown() and not Tabs.strip.buttons[3].close:IsShown(), "the other tabs: none")
over.tab, over.x = false, true; b2.scripts.OnLeave(b2); x2.scripts.OnEnter(x2)
check(x2:IsShown(), "onto the x itself: still there")
over.x = false; x2.scripts.OnLeave(x2)
check(not x2:IsShown(), "the pointer gone: the x gone")
over.tab = true; b2.scripts.OnEnter(b2); over.tab, over.x = false, true; x2.scripts.OnEnter(x2)
x2.scripts.OnClick(x2, "LeftButton"); FlushAll()
check(#Tabs.List() == 2 and Tabs.Cur() == 1 and query() == first and Tabs.List()[2].text == "frost" and second ~= "frost",
	"its x clicked: that tab closed (" .. tostring(second) .. "), the one shown stays: " .. query())
-- the x of the tab shown: closed, the one before it shown; down to one: the plain prompt
local b1, x1 = Tabs.strip.buttons[1], Tabs.strip.buttons[1].close
over = {}
b1.IsMouseOver = function() return over.tab == true end
x1.IsMouseOver = function() return over.x == true end
withCtrl(function() key("2") end); FlushAll()
local x2b = Tabs.strip.buttons[2].close
Tabs.strip.buttons[2].IsMouseOver = function() return false end
x2b.IsMouseOver = function() return true end
x2b.scripts.OnEnter(x2b); x2b.scripts.OnClick(x2b, "LeftButton"); FlushAll()
check(not Tabs.On() and query() == first, "the shown tab's x: closed, down to one, the plain prompt: " .. query())
UI:Hide(); FlushAll()

ns.providers, ns.providerOrder = save.providers, save.order
ns:AliasesChanged()
UI.lastScan, UI.lastExtra = nil, nil
ns.db.easyMode = save.easy
ns.db.tabs = save.tabs
UI:EasyChanged()
_G.GetTime = save.time

io.write("[tabs: Keep your session, on by default: tabs, and the one prompt's search with its results]\n")
do -- (1.1.8, the player: "make session-preservation a Terminal option and have it on by default"; 1.1.9: "tabs and
	-- search text with results list; even if only on 1 tab / base terminal")
	local Th = ns.Theme
	local wasKeep, wasTabs, wasTime = Th.Get().keepSession, ns.db.tabs, _G.GetTime
	check(_G.SMOKE_KEEP_SESSION_DEFAULT == true, "Keep your session is on by default")
	Th.Get().keepSession = true
	check(Tabs.KeepOn() and type(Tabs.loginFrame) == "table" and Tabs.loginFrame.scripts.OnEvent ~= nil, "(on; looked at as the game logs in)")
	-- tabs: kept at login
	local two = { list = { { text = "linen" }, { text = "hogger" } }, cur = 2 }
	ns.db.tabs = two
	Tabs.loginFrame.scripts.OnEvent(Tabs.loginFrame, "PLAYER_LOGIN")
	check(ns.db.tabs == two and #Tabs.List() == 2 and Tabs.On(), "on: a /reload brings the tabs back")
	-- one prompt, no other tab: the search you left comes back, its results with it
	ns.db.tabs = nil
	ns.db.easyMode = false; UI:EasyChanged()
	local now = 1000
	_G.GetTime = function() return now end
	UI:Toggle(); FlushAll()
	check(UI:IsShown() and query() == "", "(opened on an empty prompt: nothing kept yet)")
	typeText("linen"); FlushAll()
	local listed = #UI.Results()
	check(listed > 0, "(linen lists something: " .. listed .. ")")
	UI:Hide(); FlushAll()
	check(#Tabs.List() == 1 and Tabs.List()[1].text == "linen" and not Tabs.On(), "closed: the one prompt kept as the only tab, no strip")
	now = now + 600 -- (long after: not the quick reopen's 5 s)
	UI:Toggle(); FlushAll()
	check(UI:IsShown() and query() == "linen" and #UI.Results() == listed, "reopened ten minutes later: the search and its results: " .. query())
	-- a run opened with a text of its own (a chat link, /term words): shown, the session left as it was
	UI:Hide(); FlushAll()
	UI:Open("hogger"); FlushAll()
	UI:Hide(); FlushAll()
	check(Tabs.List()[1].text == "linen", "a run with its own text: the session stays: " .. tostring(Tabs.List()[1].text))
	-- after a /reload: still there
	Tabs.loginFrame.scripts.OnEvent(Tabs.loginFrame, "PLAYER_LOGIN")
	now = now + 600
	UI:Toggle(); FlushAll()
	check(query() == "linen" and #UI.Results() == listed, "after a /reload: the search and its results again")
	-- Ctrl+T from it: the search becomes tab 1, a new empty tab 2
	withCtrl(function() key("T") end); FlushAll()
	check(#Tabs.List() == 2 and Tabs.List()[1].text == "linen" and query() == "", "Ctrl+T: the search is tab 1, an empty tab 2")
	withShift(function() withCtrl(function() key("W") end) end); FlushAll()
	check(#Tabs.List() == 0 and query() == "linen", "tab 2 closed: back to the one prompt and its search")
	UI:Hide(); FlushAll()
	check(#Tabs.List() == 1 and Tabs.List()[1].text == "linen", "closed again: kept")
	-- off: the one prompt isn't kept, a login starts empty
	Th.Set("keepSession", "off", true)
	check(not Tabs.KeepOn(), ".set keepSession off")
	Tabs.loginFrame.scripts.OnEvent(Tabs.loginFrame, "PLAYER_LOGIN")
	check(#Tabs.List() == 0 and not Tabs.On(), "off: the login starts on one empty prompt")
	now = now + 600
	UI:Toggle(); FlushAll()
	typeText("hogger"); FlushAll()
	UI:Hide(); FlushAll()
	now = now + 600
	UI:Toggle(); FlushAll()
	check(query() == "" and #Tabs.List() == 0, "off: reopened later on an empty prompt, as before: " .. query())
	UI:Hide(); FlushAll()
	Th.Set("keepSession", "on", true)
	-- found among Terminal's settings by its words
	ns.providers.terminal._dirty = true
	for _, q in ipairs({ "@terminal session", "@terminal restore tabs" }) do
		UI:Open(q); FlushAll()
		local r = UI.Results()[1]
		check(r and r.setKey == "keepSession", q .. ": Keep your session: " .. tostring(r and r.name))
	end
	UI:Hide(); FlushAll()
	ns.db.easyMode = save.easy; UI:EasyChanged()
	_G.GetTime = wasTime
	Th.Get().keepSession = wasKeep
	ns.db.tabs = wasTabs
end

io.write("[tabs: review 1.1.19: Ctrl+T in a run with its own text, your session kept: what's on screen is tab 1]\n")
do
	local Th = ns.Theme
	local wasKeep, wasTabs = Th.Get().keepSession, ns.db.tabs
	Th.Get().keepSession = true
	ns.db.tabs = { list = { { text = "linen" } }, cur = 1 }
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("hogger"); FlushAll() -- (a text of its own: a chat link, /term words)
	withCtrl(function() key("T") end); FlushAll()
	check(#Tabs.List() == 2 and Tabs.List()[1].text == "hogger" and query() == "", "Ctrl+T: hogger, on screen, is tab 1: " .. tostring(Tabs.List()[1].text))
	UI:Hide(); FlushAll()
	ns.db.easyMode = save.easy; UI:EasyChanged()
	Th.Get().keepSession = wasKeep
	ns.db.tabs = wasTabs
end

io.write("[tabs: the empty prompt's tips say tabs open with Ctrl+T]\n")
do
	local E = ns.Easy
	local tip = ns.L["tip: Ctrl+T opens another tab, Ctrl+Tab switches"]
	local function Has(list) for _, s in ipairs(list) do if s == tip then return true end end return false end
	check(Has(E.EXAMPLES) and Has(E.ADV_EXAMPLES), "both modes' tips name Ctrl+T and Ctrl+Tab")
end

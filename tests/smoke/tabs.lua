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
UI.lastScan, UI.lastOverview = nil, nil

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

ns.providers, ns.providerOrder = save.providers, save.order
ns:AliasesChanged()
UI.lastScan, UI.lastOverview = nil, nil
ns.db.easyMode = save.easy
ns.db.tabs = save.tabs
UI:EasyChanged()
_G.GetTime = save.time

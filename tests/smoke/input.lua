local T = ...
-- (0.49.2, review) the keyboard, Enter armed, the click catcher, sending to chat, the apps and the spinner's tooltip:
-- each a regression test of a reviewer's finding (A1-A11, B2, B9, G15)
local ns, UI, check, key, query = T.ns, T.UI, T.check, T.key, T.query
local L = ns.L
local S = ns.Secure
local F = UI.frame

local function Drop(id)
	ns.providers[id] = nil
	for i, x in ipairs(ns.providerOrder) do if x == id then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()
end
local function Advanced(fn)
	local was = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	fn()
	ns.db.easyMode = was; UI:EasyChanged()
end
local function Shifted(fn)
	local was = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	fn()
	_G.IsShiftKeyDown = was
end
local function AltGr(fn) -- (AltGr reaches the game as Ctrl+Alt)
	local c, a = _G.IsControlKeyDown, _G.IsAltKeyDown
	_G.IsControlKeyDown, _G.IsAltKeyDown = function() return true end, function() return true end
	fn()
	_G.IsControlKeyDown, _G.IsAltKeyDown = c, a
end
local function Placed(on) -- (the mock's rows have no position: the catcher lies over a row only where it can say where)
	for _, r in ipairs(UI.rows) do
		if on then
			r.GetLeft, r.GetBottom, r.GetEffectiveScale = function() return 100 end, function() return 300 end, function() return 1 end
		else
			r.GetLeft, r.GetBottom, r.GetEffectiveScale = nil, nil, nil
		end
	end
end
local function Printed(fn)
	local out, pr = {}, ns.Print
	ns.Print = function(_, m) out[#out + 1] = m end
	fn()
	ns.Print = pr
	return out
end

io.write("[review 0.49.2: Enter presses what was armed]\n")
Advanced(function()
	-- A1: Shift+Enter in the game's text box (after Ctrl+C) arms "link in chat"; the next Enter, in the drawn prompt, presses
	-- that (it ran the achievement window's macro), and counts the pick once
	UI:Open("level 10"); T.FlushAll()
	local ach = UI.Results()[1]
	check(ach and ach.kind == "achievements", "(the achievement is found)")
	local bumps, bumpWas = 0, ns.Bump
	ns.Bump = function(self, k) bumps = bumps + 1 return bumpWas(self, k) end
	UI:EnterEdit()
	Shifted(function() UI.edit.scripts.OnEnterPressed(UI.edit) end)
	local px = _G.TerminalMacroProxy
	local armedLine = px and px.attrs and px.attrs.macrotext
	check(UI.keys and S.armed == "MACRO" and tostring(armedLine):find("ChatFrame_OpenChat", 1, true)
		and (UI.status:GetText() or ""):find(L["Press Enter: %s"]:format(L["link in chat"]), 1, true),
		"(Shift+Enter in the text box armed the link, back in the drawn prompt: " .. tostring(armedLine) .. ")")
	key("ENTER")
	check(S.armed == "MACRO" and px.attrs.macrotext == armedLine and F.propagate == true,
		"Enter presses what was armed (the link), not the plain open: " .. tostring(px.attrs.macrotext))
	check(bumps == 1, "the pick counted once: " .. bumps)
	ns.Bump = bumpWas
	UI:Disarm(); UI:Hide(); T.FlushAll()
	-- armed for another row than the one selected now: stale, Enter works the selected row's press out afresh
	UI:Open("@ach level"); T.FlushAll()
	check(#UI.Results() >= 2, "(two achievements)")
	UI:EnterEdit()
	Shifted(function() UI.edit.scripts.OnEnterPressed(UI.edit) end)
	UI.sel = 2 -- (moved without disarming)
	key("ENTER")
	check(UI.armedEntry and UI.armedEntry.name == UI.Results()[2].name and not rawget(UI.armedEntry, "isShift"),
		"armed for another row: the selected row's own press: " .. tostring(UI.armedEntry and UI.armedEntry.name))
	UI:Disarm(); UI:Hide(); T.FlushAll()
end)

io.write("[review 0.49.2: a press finishing isn't dropped]\n")
Advanced(function()
	-- A3: the binding's press is made on Enter; a same-text search (the data retry, the spinner's refresh) or a Down arrow
	-- in FinishSoon's moment left the terminal over the window it opened, Enter still bound
	UI:Open("character info"); T.FlushAll()
	key("ENTER")
	check(S.armed == "TOGGLECHARACTER0" and S.mode == "binding" and UI.pendingAfter, "(Enter armed the character key's binding)")
	UI.refreshedAt, UI.searchedText = nil, nil
	UI:Refresh() -- (the same text, searched again)
	T.FlushAll()
	check(not UI:IsShown() and S.armed == nil, "a same-text search meanwhile: the press still finishes (closed, disarmed)")
	T.FlushAll()
	UI:Open("character info"); T.FlushAll()
	key("ENTER")
	check(S.armed == "TOGGLECHARACTER0", "(armed again)")
	key("DOWN") -- (the selection moved: disarmed)
	T.FlushAll()
	check(not UI:IsShown(), "a Down arrow meanwhile: the press made still finishes")
	T.FlushAll()
end)

io.write("[review 0.49.2: AltGr types]\n")
do
	-- A4: AltGr (Ctrl+Alt) characters are typed, never taken for Ctrl's keys
	UI:Open(""); T.FlushAll()
	AltGr(function() key("V", "@") end) -- (Hungarian, Czech: AltGr+V)
	check(query() == "@" and UI.keys and not UI.clipHint, "AltGr+V types @ (not the clipboard box): " .. query())
	UI:SetQuery("hogger", 6)
	AltGr(function() key("A", "\196\133") end) -- (Polish: AltGr+A)
	check(query() == "hogger\196\133", "AltGr+A types ą (not select all): " .. query())
	UI:SetQuery("q:rare epic", 6)
	AltGr(function() key("W", "|") end) -- (Hungarian: AltGr+W)
	check(query() == "q:rare| epic", "AltGr+W types | (no word deleted): " .. query())
	AltGr(function() key("N", "\197\132") end) -- (Polish: AltGr+N)
	check(query() == "q:rare|\197\132 epic", "AltGr+N types ń (no next row): " .. query())
	-- the game's own text box: Ctrl+W there still deletes, AltGr+W doesn't
	UI:SetQuery("hearth stone")
	UI:EnterEdit()
	AltGr(function() UI.edit.scripts.OnKeyDown(UI.edit, "W") end)
	check(query() == "hearth stone", "the text box: AltGr+W deletes nothing: " .. query())
	T.withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "W") end)
	check(query() == "hearth ", "the text box: Ctrl+W still does: " .. query())
	UI:Hide(); T.FlushAll()
end

io.write("[review 0.49.2: Terminal's own keys while it reads the keyboard]\n")
do
	-- A5: ".bind CTRL-SPACE": Ctrl+Space closes it again; the fuzzy-finding key bound elsewhere works in it too
	_G.SetBinding("CTRL-SPACE", "TERMINAL_TOGGLE")
	_G.SetBinding("F12", "TERMINAL_FUZZY")
	_G.SetBinding("T", "TERMINAL_TOGGLE")
	UI:Open(""); T.FlushAll()
	T.withCtrl(function() key("SPACE") end)
	check(not UI:IsShown() and F.propagate == false, "Ctrl+Space bound to the toggle: closes it (not passed on to open it again)")
	T.FlushAll()
	UI:Open(""); T.FlushAll()
	key("F12")
	check(UI:IsShown() and UI.fzf, "F12 bound to fuzzy finding: on")
	key("F12")
	check(not UI:IsShown(), "F12 again: closed")
	T.FlushAll()
	UI:Open(""); T.FlushAll()
	key("T", "t")
	check(UI:IsShown() and query() == "t", "a plain letter bound to the toggle types: " .. query())
	UI:Hide(); T.FlushAll()
	_G.SetBinding("CTRL-SPACE", nil); _G.SetBinding("F12", nil); _G.SetBinding("T", nil)
end

io.write("[review 0.49.2: the click catcher]\n")
Advanced(function()
	Placed(true)
	-- A2: " >> party" typed under a resting pointer keeps the same rows: the catcher's macros follow it (the click opened
	-- the quest log instead of sending)
	-- (the quest log closed, whichever window it is: a click opens it)
	local logs = {}
	for _, n in ipairs({ "WorldMapFrame", "ForeverClassicUIQuestLog", "QuestLogFrame", "QuestLogDetailFrame", "QuestLogExFrame", "ClassicQuestLog" }) do
		local f = _G[n]
		if type(f) == "table" then logs[f] = f.shown; f.shown = false end
	end
	UI:Open("wolves across"); T.FlushAll()
	UI:PlaceCatcher(1)
	local c = UI.catcher
	local e1 = UI.Results()[1]
	check(c and c:IsShown() and c.entry == e1 and e1 and e1.name == "Wolves Across the Border" and (c.attrs.macrotext1 or "") ~= "",
		"(the catcher over the quest, its window's macro: " .. tostring(c and c.attrs.macrotext1) .. ")")
	UI:SetQuery("wolves across >> party"); T.FlushAll()
	UI:Render()
	check(UI.Results()[1] == e1 and UI.sendTo and UI.sendTo.cmd == "/p", "(the same row, now sent to the party)")
	check(c.plain == UI.SEND_LATER and c.attrs.macrotext1 == "", "the catcher's click sends it now, its line worked out on the click: " .. tostring(c.attrs.macrotext1))
	c.scripts.PreClick(c, "LeftButton")
	check((c.attrs.macrotext1 or ""):find("^/p "), "the click: /p: " .. tostring(c.attrs.macrotext1))
	UI:Hide(); T.FlushAll()
	for f, was in pairs(logs) do f.shown = was end
	-- A6: Ctrl+click on a press that opens no window keeps the terminal open, and the catcher with it
	local never = ns.Never
	local toys = { { key = "b", name = "Toy zz", secure = { macro = "/use item:1" }, isOpen = never } }
	ns:RegisterProvider("zzin2", { label = "In2", aliases = { "zzin2" }, explicit = true, collect = function() return toys end })
	UI:Open("@zzin2 zz"); T.FlushAll()
	UI.rows[1].scripts.OnEnter(UI.rows[1])
	c = UI.catcher
	T.withCtrl(function() c.scripts.PostClick(c, "LeftButton") end)
	check(UI:IsShown() and c:IsShown() and c.entry == UI.Results()[1] and c.attrs["ctrl-macrotext1"] == "/use item:1",
		"after a Ctrl+click that keeps it open: the catcher back over the row, the next click the game's too")
	UI:Hide(); T.FlushAll()
	Drop("zzin2")
	-- A7: a right-click (the row's menu) works no chat line out: an NPC's would move your waypoint
	local npcs = { { key = 1, npcID = 1, name = "Orc Innkeeper One", secure = { macro = "/targetexact Orc Innkeeper" }, isOpen = never } }
	ns:RegisterProvider("zzin3", { label = "In3", aliases = { "zzin3" }, explicit = true, collect = function() return npcs end })
	local I = ns.Integrations
	local basePin, pins = I.NpcPinLink, 0
	I.NpcPinLink = function() pins = pins + 1; return "[pin]" end
	UI:Open("@zzin3 orc >> party"); T.FlushAll()
	UI.rows[1].scripts.OnEnter(UI.rows[1])
	c = UI.catcher
	c.scripts.PreClick(c, "RightButton", false)
	check(pins == 0 and (c.attrs.macrotext1 or "") == "", "a right-click: nothing worked out, no pin set: " .. pins)
	c.scripts.PostClick(c, "RightButton", false)
	check(_G.TerminalRowMenu and _G.TerminalRowMenu:IsShown(), "(its menu opens)")
	UI:HideRowMenu()
	c.scripts.PreClick(c, "LeftButton", false)
	check(pins == 1 and (c.attrs.macrotext1 or ""):find("^/p "), "a left click still works its line out: " .. tostring(c.attrs.macrotext1))
	I.NpcPinLink = basePin
	UI:Hide(); T.FlushAll()
	Drop("zzin3")
	Placed(false)
end)

io.write("[review 0.49.2: raid and party in an instance's group]\n")
do
	-- A8: your only group is one an instance made (a battleground, the raid finder): instance chat, never /raid or party
	local SH = ns.Share
	local saved = { _G.IsInGroup, _G.IsInRaid, _G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE, _G.C_ChatInfo }
	_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
	_G.IsInGroup = function(c) return c ~= 1 end
	_G.IsInRaid = function(c) return c ~= 1 end
	local cmds = {}
	for _, ch in ipairs(SH.MenuChannels()) do cmds[#cmds + 1] = ch.cmd end
	local list = table.concat(cmds, " ")
	check(not list:find("/raid", 1, true) and not list:find("/p", 1, true) and list:find("/i", 1, true),
		"an instance's raid: no raid or party line, instance chat: " .. list)
	check(SH.ChatType("RAID") == "INSTANCE_CHAT" and SH.ChatType("PARTY") == "INSTANCE_CHAT" and SH.ChatType("GUILD") == "GUILD",
		"raid and party go to instance chat there")
	local sent = {}
	_G.C_ChatInfo = { SendChatMessage = function(m, chat) sent[#sent + 1] = chat end, InChatMessagingLockdown = function() return false end }
	local rows = { { kind = "zz", key = 1, name = "Pebble One" }, { kind = "zz", key = 2, name = "Pebble Two" } }
	local n = SH.SendAll(rows, { chat = "RAID", label = "raid" }, "pebble")
	check(n and sent[1] == "INSTANCE_CHAT", ">>> raid there: sent as instance chat: " .. tostring(sent[1]))
	-- your own raid: as before
	_G.IsInRaid = function() return true end
	_G.IsInGroup = function() return true end
	sent = {}
	SH.SendAll(rows, { chat = "RAID", label = "raid" }, "pebble")
	check(sent[1] == "RAID" and SH.MenuChannels()[2].cmd == "/raid", "your own raid: raid: " .. tostring(sent[1]))
	_G.IsInGroup, _G.IsInRaid, _G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE, _G.C_ChatInfo = unpack(saved, 1, 5)
end

io.write("[review 0.49.2: the first key typed]\n")
do
	-- A9: a dead key first in a session (´ then e: é) types nothing until the next key: not taken for a client that
	-- can't pass typed text (the plain text box for the whole session)
	local cc, nc = UI.charChecked, UI.noChar
	UI.charChecked, UI.noChar = nil, nil
	UI:Open(""); T.FlushAll()
	key("\194\180"); T.FlushAll() -- (´)
	key("^"); T.FlushAll()
	check(not UI.noChar and UI.keys, "dead keys first: the drawn prompt stays")
	key("E", "\195\169")
	check(query() == "\195\169" and UI.charChecked, "the next key's é typed: " .. query())
	UI.charChecked, UI.noChar = cc, nc
	UI:Hide(); T.FlushAll()
end

io.write("[review 0.49.2: Tab just after the toggle key]\n")
do
	-- A10: the client says Tab isn't held as ` opens the terminal, then Tab within a second: a Tab of its own (it was
	-- swallowed, and its key-up turned to fuzzy finding)
	local was, tabDown = _G.IsKeyDown, false
	_G.IsKeyDown = function(k) return k == "TAB" and tabDown end
	UI:Hide(); T.FlushAll()
	UI:Toggle()
	check(UI:IsShown() and not UI.fzf, "(` opened it, Tab not held)")
	tabDown = true
	key("TAB")
	check(UI.openedByToggle == nil and F.propagate == false, "Tab pressed now: its own (not swallowed)")
	tabDown = false
	F.scripts.OnKeyUp(F, "TAB")
	check(UI:IsShown() and not UI.fzf, "its key-up: no fuzzy finding")
	UI:Hide(); T.FlushAll()
	_G.IsKeyDown = was
end

io.write("[review 0.49.2: sends in combat, history]\n")
Advanced(function()
	-- A11: in combat, ">> party" on a row that opens a window says it can't send (as any row does), not "can't open"
	local icl = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	UI:Open("character info >> party"); T.FlushAll()
	local e = UI.Results()[1]
	check(e and e.name == "Character Info" and e.secure and UI.sendTo, "(a window's row, sent to the party, in combat)")
	local said = Printed(function() UI:Activate(1, {}) end)
	check(said[1] == L["In combat: can't send it now."], "in combat: it can't send it now: " .. tostring(said[1]))
	_G.InCombatLockdown = icl
	UI:Hide(); T.FlushAll()
	-- Enter on a press that asks for more (@who's "Ask the server") isn't kept in the history, as a click's isn't
	local rows = { { key = "a", name = "Ask zz", secure = { macro = "/who zz" }, isOpen = ns.Never, staysOpen = true } }
	ns:RegisterProvider("zzin4", { label = "In4", aliases = { "zzin4" }, explicit = true, collect = function() return rows end })
	local recWas, recorded = ns.RecordHistory, {}
	ns.RecordHistory = function(_, l) recorded[#recorded + 1] = l end
	UI:Open("@zzin4 zz"); T.FlushAll()
	key("ENTER")
	check(S.armed == "MACRO" and #recorded == 0, "Enter on it: pressed, not in the history: " .. #recorded)
	-- (0.49.2, review) the same through the keyboard's row menu (its first line: the row's own press)
	UI:Disarm(); T.FlushAll()
	UI:ShowRowMenu(1, true); UI:MenuSelect(1)
	key("ENTER")
	check(S.armed == "MACRO" and #recorded == 0, "the menu's line: pressed, not in the history: " .. #recorded)
	ns.RecordHistory = recWas
	UI:Disarm(); UI:Hide(); T.FlushAll()
	Drop("zzin4")
end)

io.write("[review 0.49.2: the terminal opened over an app]\n")
do
	-- B2: opening the terminal closes an app up (as an app opening closes the terminal): both took the keyboard
	ns.Changelog.Open()
	check(ns.Changelog.IsShown() and not UI:IsShown(), "(the changelog up)")
	UI:Toggle(); T.FlushAll() -- (its key bound elsewhere, /term)
	check(UI:IsShown() and not ns.Changelog.IsShown(), "the terminal opened: the changelog closed")
	UI:Hide(); T.FlushAll()
	ns.Atop.Open()
	check(ns.Atop.IsShown(), "(.atop up)")
	local altWas = _G.IsAltKeyDown
	_G.IsAltKeyDown = function() return true end
	ns.ChatLinks.OnRef("item:2589", "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", "LeftButton")
	_G.IsAltKeyDown = altWas
	T.FlushAll()
	check(UI:IsShown() and not ns.Atop.IsShown() and query() == "Linen Cloth", "Alt+click on a chat link over .atop: atop closed: " .. query())
	UI:Hide(); T.FlushAll()
	if ns.Atop.IsShown() then ns.Atop.Close() end
end

io.write("[review 0.49.2: the spinner's tooltip under .zen]\n")
do
	-- B9: while .zen fades the interface (GameTooltip with it), the spinner's lines show in a tooltip .zen keeps up
	local Zen = ns.Zen
	UI:Open(""); T.FlushAll()
	local activeWas = Zen.active
	Zen.active = true -- (.zen fading the interface, as Zen.Opened leaves it; support.lua opens it for real)
	local B = UI.busy
	local linesWas = B.lines
	B.lines = { "Zz still reading" }
	B:Show()
	local gt = _G.GameTooltip
	local gtShown = gt.shown
	gt.shown = false
	B.scripts.OnEnter(B)
	local tip = _G.TerminalBusyTip
	check(tip and tip:IsShown() and Zen.Kept(tip) and gt.shown == false, "the spinner's tooltip: Terminal's own, kept up by .zen")
	B.scripts.OnLeave(B)
	check(not (tip and tip:IsShown()), "the pointer gone: it hides")
	-- without .zen: the game's own, as ever
	Zen.active = false
	B.scripts.OnEnter(B)
	check(gt.shown == true and not (tip and tip:IsShown()), "without .zen: the game's tooltip")
	B.scripts.OnLeave(B)
	check(gt.shown == false, "(and it hides)")
	Zen.active = activeWas
	B.lines = linesWas
	B:Hide()
	gt.shown = gtShown
	UI:Hide(); T.FlushAll()
end

io.write("[review 0.49.2: the keyboard menu's too-long line]\n")
Advanced(function()
	-- G15: says only that it's too long (it told you to right-click and pick the line: Terminal's own code then opens the
	-- chat box, which taints it)
	UI:Open("hearthstone"); T.FlushAll()
	local SH = ns.Share
	local lineWas = SH.Line
	SH.Line = function() return ("x"):rep(300) end
	UI:ShowRowMenu(UI.Selected(), true)
	local at
	for i, b in ipairs(_G.TerminalRowMenu.lines) do if b:IsShown() and b.item and b.item.boxLine then at = i end end
	check(at ~= nil, "(the menu has a chat-box line)")
	local said = {}
	if at then
		UI:MenuSelect(at)
		said = Printed(function() key("ENTER") end)
	end
	SH.Line = lineWas
	check(said[1] == L["Too long to put in the chat box."], "too long: says so, nothing more: " .. tostring(said[1]))
	UI:HideRowMenu(); UI:Hide(); T.FlushAll()
end)

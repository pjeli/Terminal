-- (0.52.10, the player's asks) ">> text" and ">> csv" (">>>": every result) open the results in a box to copy, plain or
-- as CSV; and the terminal closed and opened again within a few seconds has what was typed back.
local T = ...
local ns, UI, check, FlushAll, key = T.ns, T.UI, T.check, T.FlushAll, T.key
local L = ns.L

io.write("[copyout: >> text, >> csv, and the text kept for a quick reopen]\n")
do
	local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode, show = ns.ShowText }
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		return {
			{ name = "Linen Cloth", key = 2589, itemID = 2589, detail = "|cff9d9d9dx20|r  ·  Bags" },
			{ name = "|cff1eff00Linen Belt|r", key = 7026, itemID = 7026, detail = 'Waist, "light"' },
			{ name = "Linen Bag", key = 4238, itemID = 4238, detail = "" },
		}
	end })
	ns:AliasesChanged()
	local shown = {}
	ns.ShowText = function(_, title, text, opts)
		shown = { title = title, text = text, compact = opts and opts.compact, close = opts and opts.closeOnCopy }
	end
	ns.db.easyMode = false
	UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil

	-- ">> text": the selected one, as a line to copy (the slim bar)
	UI:Open("linen cloth >> text")
	FlushAll()
	check(UI.sendTo and UI.sendTo.copy == "text", ">> text: a place to copy to, not chat")
	check(tostring(UI.status:GetText()):find(L["Enter copies it as %s"]:format(L["text"]), 1, true), "the footer says Enter copies it")
	UI:Activate()
	FlushAll()
	check(shown.text == "Linen Cloth - x20 · Bags" and shown.compact and not UI:IsShown(),
		"Enter: the row as plain text (no colour codes), in the slim bar; the terminal closed: " .. tostring(shown.text))

	-- ">>> csv": every result, a header and a line each, fields with a comma or quote quoted
	shown = {}
	UI:Open("linen >>> csv")
	FlushAll()
	check(#UI.Results() == 1 and UI.Results()[1].name == L["Copy all %d as %s"]:format(3, "CSV"), ">>> csv: one row says how many: "
		.. tostring(UI.Results()[1] and UI.Results()[1].name))
	UI:Activate()
	FlushAll()
	local lines = {}
	for l in (shown.text or ""):gmatch("[^\n]+") do lines[#lines + 1] = l end
	local belt
	for _, l in ipairs(lines) do if l:find("Linen Belt", 1, true) then belt = l end end
	check(lines[1] == ns.Share.CSV_HEAD and #lines == 4 and not shown.compact and shown.close,
		">>> csv: a header and a line for each, in the window that closes once copied: " .. #lines)
	check(belt == 'Linen Belt,"Waist, ""light""",Item,7026', "a field with a comma or quote quoted, no colour codes: " .. tostring(belt))

	-- ">>> text": a line each
	shown = {}
	UI:Open("linen >>> text")
	FlushAll()
	UI:Activate()
	FlushAll()
	local n = 0
	for _ in (shown.text or ""):gmatch("[^\n]+") do n = n + 1 end
	check(n == 3 and (shown.text or ""):find("Linen Bag", 1, true), ">>> text: a plain line for each result: " .. n)
	check(shown.close, ">>> text: the window closes once copied")

	-- (0.52.12, the player's ask) the window closes on Ctrl+C for these, as the slim bar does; other text keeps it
	do
		local CB = ns.CopyBox
		local realCtrl = _G.IsControlKeyDown
		save.show(ns, "linen as CSV", "name\nLinen Cloth", { closeOnCopy = true })
		_G.IsControlKeyDown = function() return true end
		CB.edit.scripts.OnKeyDown(CB.edit, "C")
		_G.IsControlKeyDown = realCtrl
		FlushAll()
		check(CB.copied and not CB.frame.shown, "the copy window: Ctrl+C copies it and it closes")
		save.show(ns, "debug", { "a", "b" })
		_G.IsControlKeyDown = function() return true end
		CB.edit.scripts.OnKeyDown(CB.edit, "C")
		_G.IsControlKeyDown = realCtrl
		FlushAll()
		check(CB.frame.shown and not CB.copied, "other text (the debug log) stays open after Ctrl+C")
		CB.Hide()
	end
	UI:Hide(); FlushAll()

	-- Simple mode (0.52.12, the player's call): no ">>", ">> csv" neither; plain words at the end copy every result
	ns.db.easyMode = true
	UI:EasyChanged()
	-- (0.54.1) ">>> csv", ">> party" typed in Simple mode: run in Advanced mode this once
	UI:Open("linen >>> csv")
	FlushAll()
	check(UI.sendTo and UI.sendTo.copy == "csv" and UI.sendTo.all and not ns.Easy.On(),
		"Simple mode: >>> csv runs in Advanced this once: " .. tostring(UI.sendTo and UI.sendTo.copy))
	UI:Hide(); FlushAll()
	UI:Open("linen >> party")
	FlushAll()
	check(UI.sendTo and UI.sendTo.cmd and not ns.Easy.On(), "Simple mode: >> party too")
	UI:Hide(); FlushAll()
	shown = {}
	UI:Open("linen to csv")
	FlushAll()
	check(UI.sendTo and UI.sendTo.copy == "csv" and UI.sendTo.all and UI.blockedSyntax == nil
		and UI.Results()[1] and UI.Results()[1].name == L["Copy all %d as %s"]:format(3, "CSV"),
		"Simple mode: \"linen to csv\" copies every result: " .. tostring(UI.Results()[1] and UI.Results()[1].name))
	UI:Activate()
	FlushAll()
	local nl = 0
	for _ in (shown.text or ""):gmatch("[^\n]+") do nl = nl + 1 end
	check(nl == 4 and shown.close and (shown.title or ""):find("linen", 1, true), "\"to csv\": the header and 3 lines, titled with the search: " .. nl)
	UI:Open("Linen As Text")
	FlushAll()
	check(UI.sendTo and UI.sendTo.copy == "text" and UI.sendTo.all, "Simple mode: \"as text\" too, in any case")
	UI:Open("linen to party")
	FlushAll()
	check(UI.sendTo == nil, "Simple mode: \"to party\" is a search, not a copy")
	check(ns.Share.PlainCopy("to csv") == nil and ns.Share.PlainCopy("cloth to csv") == "cloth",
		"\"to csv\" on its own isn't a copy (nothing searched)")
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
	UI:EasyChanged()

	-- (release review) Simple mode, the words in two categories: "linen to csv" copies the rows of both, not a line per
	-- category; coins keep their units when copied
	ns:RegisterProvider("quests", { label = "Quest", aliases = { "quest" }, collect = function()
		return { { name = "Linen Delivery", key = 9, questID = 9, detail = "Elwynn" } }
	end })
	ns:AliasesChanged()
	ns.db.easyMode = true
	UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	shown = {}
	UI:Open("linen to csv")
	FlushAll()
	UI:Activate()
	FlushAll()
	local copied = shown.text or ""
	check(copied:find("Linen Delivery,Elwynn,Quest,9", 1, true) and copied:find("Linen Bag", 1, true)
		and not copied:find("+1 more", 1, true), "Simple mode, two categories: every row copied, not the categories: " .. copied)
	ns.db.easyMode = false
	UI:EasyChanged()
	check(ns.Share.Clean("1,234" .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 5|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t")
		== "1,234g 5s", "copied coins keep their units: " .. ns.Share.Clean("1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"))
	check(ns.Share.Clean("|cnIQ4:[Linen Cloth]|r") == "[Linen Cloth]", "the game's named colours go")

	-- the terminal closed (the key, a click elsewhere) and opened again within UI.REOPEN_KEEP s: what was typed is back;
	-- after Esc, later, or after running something: empty
	local realTime = _G.GetTime
	local now = 1000
	_G.GetTime = function() return now end
	UI:Open("")
	UI:SetQuery("hearth")
	FlushAll()
	UI:Hide(); FlushAll()
	now = now + 3
	UI:Toggle()
	FlushAll()
	check(UI.edit:GetText() == "hearth", "reopened 3 s later: the text is back: " .. tostring(UI.edit:GetText()))
	-- Esc (0.52.11, the player's ask): closed and the text let go, in the drawn prompt and the game's text box alike
	UI:SetQuery("hearth")
	FlushAll()
	key("ESCAPE"); FlushAll()
	check(not UI:IsShown(), "Esc closes it")
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(UI.edit:GetText() == "", "Esc, reopened a second later: empty: " .. tostring(UI.edit:GetText()))
	UI:SetQuery("hearth")
	FlushAll()
	UI.edit:GetScript("OnEscapePressed")(UI.edit); FlushAll()
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(UI.edit:GetText() == "", "Esc in the game's text box: empty too: " .. tostring(UI.edit:GetText()))
	UI:Hide(); FlushAll()
	now = now + UI.REOPEN_KEEP + 1
	UI:Toggle()
	FlushAll()
	check(UI.edit:GetText() == "", "reopened later: empty")
	UI:SetQuery("linen bag")
	FlushAll()
	UI:Activate() -- (something run; the terminal closes)
	FlushAll()
	UI:Hide(); FlushAll()
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(UI.edit:GetText() == "", "after running something: not kept: " .. tostring(UI.edit:GetText()))
	UI:Hide(); FlushAll()

	-- (0.52.14, the player) reopened: the toggle key's ` that opened it isn't typed after the text; the caret where it
	-- was; Advanced for that run comes back as Advanced, the text as it was ("|" and all)
	now = now + UI.REOPEN_KEEP + 1
	UI:Open("")
	UI:SetQuery("@item | sum value by quality", 5)
	FlushAll()
	UI:Hide(); FlushAll()
	now = now + 1
	UI:Toggle()
	FlushAll()
	if UI.keys then UI:OnChar("`") else UI.edit:SetText(UI.edit:GetText() .. "`") end
	FlushAll()
	check(UI.edit:GetText() == "@item | sum value by quality" and UI.cursor == 5,
		"reopened: no ` from the key that opened it, the caret where it was: " .. UI.edit:GetText() .. " @" .. tostring(UI.cursor))
	UI:Hide(); FlushAll()
	ns.db.easyMode = true
	UI:EasyChanged()
	now = now + UI.REOPEN_KEEP + 1
	UI:Open("")
	UI:AdvancedOnce()
	FlushAll()
	UI:SetQuery("@item | count")
	FlushAll()
	check(not ns.Easy.On(), "Alt+`: Advanced for this run")
	UI:Hide(); FlushAll()
	check(ns.Easy.On(), "closed: Simple again")
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(not ns.Easy.On() and UI.edit:GetText() == "@item | count" and UI.aggregate ~= nil,
		"reopened a moment later: Advanced again, its text searched as Advanced: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	check(ns.Easy.On(), "and closed: Simple again")
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(not ns.Easy.On() and UI.edit:GetText() == "@item | count", "reopened again: Advanced still")
	UI:Hide(); FlushAll()
	ns.db.easyMode = false -- (switched to Advanced for good meanwhile: nothing "for this run" to bring back)
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(ns.Easy.temp == nil and UI.edit:GetText() == "@item | count", "Advanced for good since: no run's mode brought back")
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
	UI:EasyChanged()

	-- (release review) only a run that closes the terminal lets go of the text: a row that keeps it open doesn't
	now = now + UI.REOPEN_KEEP + 1
	ns:RegisterProvider("stays", { label = "Stay", aliases = { "stay" }, collect = function()
		return { { name = "Linen Stay", key = "s", staysOpen = true, activate = function() end } }
	end })
	ns:AliasesChanged()
	UI:Open("")
	UI:SetQuery("linen stay")
	FlushAll()
	UI:Activate()
	FlushAll()
	check(UI:IsShown(), "a row that keeps the terminal open")
	UI:Hide(); FlushAll()
	now = now + 1
	UI:Toggle()
	FlushAll()
	check(UI.edit:GetText() == "linen stay", "closed by hand right after: the text kept: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	-- opened another way meanwhile (/term, a chat link): what was kept is over
	UI:Open("")
	check(UI.closedText == nil, "opened another way: nothing kept from before")
	UI:Hide(); FlushAll()
	-- the tour: Esc ends it with nothing kept, nor its Simple mode
	now = now + UI.REOPEN_KEEP + 1
	if ns.Tour and ns.Tour.Start then
		ns.Tour.Start()
		FlushAll()
		ns.Tour.Next() -- (a step with something typed)
		FlushAll()
		check(ns.Tour.Active() and UI:IsShown() and UI.edit:GetText() ~= "", "the tour on, a step's search typed: "
			.. UI.edit:GetText())
		ns.Tour.Key("ESCAPE")
		FlushAll()
		now = now + 1
		UI:Toggle()
		FlushAll()
		check(UI.edit:GetText() == "" and ns.Easy.tempSimple == nil, "the tour ended with Esc: reopened empty, not in its mode: "
			.. UI.edit:GetText())
		UI:Hide(); FlushAll()
	end
	_G.GetTime = realTime

	ns.ShowText = save.show
	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end

-- Quests to drop (Quests.lua's marks, QuestDrop.lua): grey quests and quests in zones left behind, Shift+Enter has the
-- game ask, ">> drop" / ">>> drop", "Drop all N", Terminal's confirmation, the filters and Alt+`.
local T = ...
local ns, UI, S, check, log, logHas, key, FlushAll = T.ns, T.UI, T.S, T.check, T.log, T.logHas, T.key, T.FlushAll
local QD = ns.QuestDrop

io.write("[quests to drop]\n")
do
	local Q = C_QuestLog
	local save = {
		num = Q.GetNumQuestLogEntries, info = Q.GetInfo, obj = Q.GetQuestObjectives, ready = Q.ReadyForTurnIn,
		isComplete = Q.IsComplete, trivial = Q.IsQuestTrivial, sel = Q.SetSelectedQuest, getSel = Q.GetSelectedQuest,
		setAb = Q.SetAbandonQuest, ab = Q.AbandonQuest, idx = Q.GetLogIndexForQuestID, title = Q.GetTitleForQuestID,
		pi = _G.C_PlayerInfo, map = _G.C_Map, uiMap = _G.GetQuestUiMapID, ul = _G.UnitLevel, gt = _G.GetTime,
		qmq = _G.QuestMapQuestOptions_AbandonQuest, easy = ns.db.easyMode, print = ns.Print, out = ns.Output,
	}
	-- a level 24's log: Elwynn (1-10), Westfall (10-20), Stranglethorn (30-45), and a city with no levels
	local quests = {
		{ title = "Westfall", isHeader = true },
		{ title = "The Defias Brotherhood", questID = 102, level = 18 },
		{ title = "Westfall Stew", questID = 103, level = 12 },
		{ title = "Elwynn Forest", isHeader = true },
		{ title = "Kobold Camp Cleanup", questID = 101, level = 4 },
		{ title = "Duskwood", isHeader = true },
		{ title = "Supplies for Darkshire", questID = 105, level = 22 },
		{ title = "Stranglethorn Vale", isHeader = true },
		{ title = "Raptor Mastery", questID = 104, level = 33 },
		{ title = "Stormwind", isHeader = true },
		{ title = "Messenger", questID = 106, level = 20 },
	}
	local DIFF = { [101] = 0, [102] = 1, [103] = 0, [104] = 3, [105] = 2, [106] = 2 } -- (0 = Trivial: the log shows it grey)
	local MAP = { [101] = 1429, [102] = 1436, [103] = 1436, [104] = 1434, [105] = 1431 } -- (106: no zone)
	local LEVELS = { [1429] = { 1, 10, "Elwynn Forest" }, [1436] = { 10, 20, "Westfall" }, [1434] = { 30, 45, "Stranglethorn Vale" },
		[1431] = { 15, 24, "Duskwood" } } -- (Duskwood tops out at your level: not behind you yet)
	local inLog = { [101] = true, [102] = true, [103] = true, [104] = true, [105] = true, [106] = true }
	local abandoned, selected, setAbandon = {}, 104, nil
	Q.GetNumQuestLogEntries = function() return #quests end
	Q.GetInfo = function(i) return quests[i] end
	Q.GetQuestObjectives = function() return {} end
	Q.ReadyForTurnIn = function(id) return id == 103 end
	Q.IsQuestTrivial = function() return false end -- (not asked: the difficulty answers first)
	Q.GetSelectedQuest = function() return selected end
	Q.SetSelectedQuest = function(id) selected = id end
	Q.SetAbandonQuest = function() setAbandon = selected end
	Q.AbandonQuest = function() if setAbandon then abandoned[#abandoned + 1] = setAbandon; inLog[setAbandon] = nil end end
	Q.GetLogIndexForQuestID = function(id) return inLog[id] and 1 or nil end
	Q.GetTitleForQuestID = function(id) return "Quest " .. id end
	_G.C_PlayerInfo = setmetatable({ GetContentDifficultyQuestForPlayer = function(id) return DIFF[id] end }, { __index = save.pi })
	_G.C_Map = setmetatable({
		GetMapLevels = function(ui) local l = LEVELS[ui] if l then return l[1], l[2], 0, 0 end end,
		GetMapInfo = function(ui) local l = LEVELS[ui] return l and { name = l[3] } or nil end,
	}, { __index = save.map })
	_G.GetQuestUiMapID = function(id) return MAP[id] or 0 end
	_G.UnitLevel = function() return 24 end
	_G.QuestMapQuestOptions_AbandonQuest = function(id) log[#log + 1] = "AbandonDialog " .. id end
	local clock = 9000
	_G.GetTime = function() return clock end
	local printed = {}
	ns.Print = function(_, m) printed[#printed + 1] = m end
	local said = {}
	ns.Output = function(_, lines) for _, l in ipairs(lines or {}) do said[#said + 1] = l end end
	ns.db.easyMode = false; UI:EasyChanged()
	ns.providers.quests._dirty = true
	local function row(id)
		for _, e in ipairs(ns:GetEntries(ns.providers.quests)) do if e.questID == id then return e end end
	end
	local function ids(rows)
		local t = {}
		for _, e in ipairs(rows) do t[#t + 1] = e.lead and "all" or tostring(e.questID or e.name) end
		return table.concat(t, ",")
	end

	-- the marks: the game's grey, the world map's zone levels; a complete one is never one to drop
	local kobold, defias, stew, raptor, msg = row(101), row(102), row(103), row(104), row(106)
	check(kobold.grey and kobold.behind and kobold.drop and kobold.detail:find("grey", 1, true),
		"grey for your level (the log's own colour): one to drop: " .. tostring(kobold.detail))
	check(not defias.grey and defias.behind and defias.drop and defias.detail:find("zone left behind (Lv 10-20)", 1, true),
		"green, but its zone tops out at 20: left behind: " .. tostring(defias.detail))
	check(stew.grey and stew.complete and not stew.drop, "grey but complete: turn it in, not one to drop")
	check(not raptor.grey and not raptor.behind and not raptor.drop and not msg.behind and not msg.drop,
		"a quest at your level, and one in a city with no levels: not to drop")
	check(not row(105).behind and not row(105).drop, "a zone that tops out at your own level isn't left behind yet")
	-- Shift+Enter: one to drop has the game ask (its own Abandon); the others still track
	check(kobold.secondarySecure and kobold.secondarySecure.macro(kobold) == "/run QuestMapQuestOptions_AbandonQuest(101)"
		and kobold.secondaryIsOpen == ns.Never, "Shift+Enter on one to drop: the game's own Abandon, which asks")
	check(raptor.secondarySecure == nil and raptor.secondary ~= nil, "Shift+Enter on any other quest: tracks it, as before")
	local saveCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	local mark = #log
	kobold.secondary(kobold)
	_G.InCombatLockdown = saveCombat
	check(printed[#printed] and printed[#printed]:find("In combat: drop Kobold Camp Cleanup", 1, true) and not logHas("SuperTrack", mark + 1),
		"in combat (no press): it says so, and doesn't track it instead: " .. tostring(printed[#printed]))
	local enter, shift = ns.Easy.Verbs(kobold)
	local _, rshift = ns.Easy.Verbs(raptor)
	check(enter == "show in quest log" and shift == "drop" and rshift == "track", "the footer's verbs: drop / track")
	_G.QuestMapQuestOptions_AbandonQuest = nil
	local fallback = kobold.secondarySecure.macro(kobold)
	check(fallback:find("local q=101", 1, true) and fallback:find('StaticPopup_Show("ABANDON_QUEST"', 1, true) and #fallback <= 255,
		"no Abandon function: the press shows the game's own dialog itself: " .. fallback)
	_G.QuestMapQuestOptions_AbandonQuest = function(id) log[#log + 1] = "AbandonDialog " .. id end

	-- the question
	local q = QD.Question("quests to drop")
	check(q and #q.words == 0 and not q.grey and not q.behind, "quests to drop: the question")
	check(QD.Question("Which quests should I abandon?") and QD.Question("old quests") and QD.Question("drop my quests"),
		"and the like")
	q = QD.Question("grey quests")
	check(q and q.grey and not q.behind, "grey quests: only grey ones")
	q = QD.Question("quests in zones I've left behind")
	check(q and q.behind and not q.grey, "zones left behind: only those")
	q = QD.Question("westfall quests to drop")
	check(q and #q.words == 1 and q.words[1] == "westfall", "other words narrow it")
	check(QD.Question("quest") == nil and QD.Question("drop") == nil and QD.Question("quest drops") == nil
		and QD.Question("@quest is:drop") == nil and QD.Question("kobold camp cleanup") == nil and QD.Question(".drop") == nil,
		"other lines aren't")

	-- the answer: grey first, then by level; "Drop all N" on top; complete ones left out, said
	local res = UI:SearchText("quests to drop")
	check(ids(res) == "all,101,102" and res[1].lead and res[1].name == "Drop all 2", "the answer: " .. ids(res))
	check(UI.answerNote and UI.answerNote:find("grey, or in a zone", 1, true) and UI.answerNote:find("1 complete left out", 1, true),
		"its note: " .. tostring(UI.answerNote))
	check(ids(UI:SearchText("grey quests")) == "101", "grey quests (the complete one left out): " .. ids(UI:SearchText("grey quests")))
	check(ids(UI:SearchText("outleveled quests")) == "all,101,102", "quests in zones left behind")
	check(ids(UI:SearchText("westfall quests to drop")) == "102", "narrowed by a zone's name")
	check(ids(UI:SearchText("raptor quests to drop")) == "" and UI.answerNote == "None of those quests is one to drop", "nothing there: said")
	-- the filters, and Alt+`
	local function names(text)
		local t = {}
		for _, e in ipairs(UI:Search(text)) do if e.questID then t[#t + 1] = e.questID end end
		table.sort(t)
		return table.concat(t, ",")
	end
	check(names("@quest is:grey") == "101,103" and names("@quest is:leftbehind") == "101,102,103" and names("@quest is:drop") == "101,102",
		"@quest is:grey / is:leftbehind / is:drop: " .. names("@quest is:grey") .. " / " .. names("@quest is:leftbehind") .. " / " .. names("@quest is:drop"))
	check(ns.Easy.ToAdvanced("quests to drop") == "@quest is:drop " and ns.Easy.ToAdvanced("grey quests") == "@quest is:grey -is:complete "
		and ns.Easy.ToAdvanced("westfall quests to drop") == "@quest is:drop westfall ",
		"Alt+` writes it: " .. tostring(ns.Easy.ToAdvanced("quests to drop")))
	check(names("@quest is:grey -is:complete") == "101", "and that finds the same")
	-- (the recipes' is:grey still answers for recipes only)
	check(ns.Filters.Parse("is:grey")({ recipeID = 5, difficulty = ns.Filters.DIFF.grey }) and not ns.Filters.Parse("is:grey")(raptor),
		"is:grey: a grey recipe still, and a quest only when it's grey")

	-- Shift+Enter in the answer: the same press has the game ask
	UI:Open("quests to drop"); FlushAll()
	key("DOWN")
	local sel = UI.Results()[UI.sel]
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	local proxy = _G.TerminalMacroProxy
	check(sel and sel.questID == 101 and S.armed == "MACRO" and proxy.attrs.macrotext == "/run QuestMapQuestOptions_AbandonQuest(101)",
		"Shift+Enter: the game asks to drop it: " .. tostring(proxy.attrs.macrotext))
	proxy.scripts.PostClick(proxy, "LeftButton", true); FlushAll()
	UI:Disarm(); UI:Hide(); FlushAll()

	-- ">> drop": the selected quest (the game asks); not a quest: nothing pressed
	UI:Open("@quest is:drop >> drop"); FlushAll()
	check(UI.sendTo and UI.sendTo.drop and #UI.Results() == 2 and _G.TerminalFrame and true, ">> drop keeps the list")
	local first = UI.Results()[1]
	key("ENTER")
	check(S.armed == "MACRO" and proxy.attrs.macrotext == ("/run QuestMapQuestOptions_AbandonQuest(%d)"):format(first.questID),
		">> drop: Enter has the game ask to drop the selected one: " .. tostring(proxy.attrs.macrotext))
	proxy.scripts.PostClick(proxy, "LeftButton", true); FlushAll()
	UI:Disarm(); UI:Hide(); FlushAll()
	UI:Open("hearthstone >> drop"); FlushAll()
	S.armed = nil
	printed = {}
	key("ENTER")
	check(S.armed == nil and printed[1] and printed[1]:find("Only quests in your log", 1, true), ">> drop on an item: nothing pressed, said")
	UI:Disarm(); UI:Hide(); FlushAll()

	-- ">>> drop": one row; Enter shows Terminal's confirmation naming them (the complete one kept)
	UI:Open("@quest is:leftbehind >>> drop"); FlushAll()
	local top = UI.Results()[1]
	check(#UI.Results() == 1 and top.name == "Drop all 2 quests" and top.detail:find("1 complete kept", 1, true),
		">>> drop collapses into one row: " .. tostring(top.name) .. " / " .. tostring(top.detail))
	local status = UI.status and UI.status:GetText() or ""
	check(status:find("Enter drops all 2: Terminal asks first", 1, true), "the footer says so: " .. status)
	key("ENTER")
	local pend = QD.Pending()
	check(pend and #pend == 2 and pend[1].questID == 101 and pend[2].questID == 102 and QD.app.IsShown() and not UI:IsShown(),
		"Enter: Terminal's confirmation, the terminal gone")
	check(#abandoned == 0, "nothing dropped before the answer")
	local dlg = _G.TerminalDropQuests
	check(dlg.title:GetText():find("Drop 2 quests?", 1, true) and dlg.body:GetText():find("Kobold Camp Cleanup, The Defias Brotherhood", 1, true),
		"it names them: " .. tostring(dlg.body:GetText()))
	dlg.scripts.OnKeyDown(dlg, "ENTER") -- (at once: a held Enter's repeat)
	check(QD.Pending() and #abandoned == 0, "an Enter the moment it shows doesn't answer it")
	clock = clock + 1
	dlg.scripts.OnKeyDown(dlg, "ENTER")
	FlushAll()
	check(table.concat(abandoned, ",") == "101,102" and not QD.app.IsShown() and selected == 104,
		"Enter: both dropped, the log's selection put back: " .. table.concat(abandoned, ","))
	check(said[#said] == "Dropped 2 quests: Kobold Camp Cleanup, The Defias Brotherhood", "a line says which: " .. tostring(said[#said]))

	-- ">>> drop" after any quest search: what you listed, even one that isn't grey (not complete ones)
	UI:Open("@quest raptor >>> drop"); FlushAll()
	check(UI.Results()[1].name == "Drop the 1 quest", ">>> drop takes the quests you listed: " .. tostring(UI.Results()[1].name))
	UI:Hide(); FlushAll()

	-- Esc keeps them; a quest gone meanwhile is said
	abandoned, said = {}, {}
	inLog[101], inLog[102] = true, true
	QD.Confirm({ kobold, defias })
	clock = clock + 1
	dlg.scripts.OnKeyDown(dlg, "ESCAPE")
	FlushAll()
	check(#abandoned == 0 and not QD.app.IsShown() and QD.Pending() == nil, "Esc keeps them")
	QD.Confirm({ kobold, defias })
	inLog[101] = nil -- (turned in meanwhile)
	QD.Decide(true); FlushAll()
	check(table.concat(abandoned, ",") == "102" and said[#said]:find("Not dropped", 1, true) and said[#said]:find("Kobold", 1, true),
		"one no longer in the log: said: " .. tostring(said[#said]))
	inLog[101], inLog[102] = true, true
	abandoned, said = {}, {}

	-- the answer's "Drop all 2" and the right-click menu's line open the same confirmation
	UI:Open("quests to drop"); FlushAll()
	UI:Activate(1)
	FlushAll()
	pend = QD.Pending()
	check(pend and #pend == 2 and QD.app.IsShown(), "\"Drop all 2\": the confirmation")
	QD.Decide(false); FlushAll()
	UI:Open("quests to drop"); FlushAll()
	UI:ShowRowMenu(2)
	local m, line = _G.TerminalRowMenu, nil
	for _, b in ipairs(m.lines) do
		if b:IsShown() and b.fs:GetText() == "Drop all 2 quests" then line = b end
	end
	check(line ~= nil, "the right-click menu: Drop all 2 quests")
	if line then line.item.run() end
	FlushAll()
	check(QD.Pending() and #QD.Pending() == 2, "which opens the confirmation")
	QD.Decide(false); FlushAll()
	UI:HideRowMenu(); UI:Hide(); FlushAll()
	check(#abandoned == 0, "(nothing dropped by those)")

	-- a level gained rebuilds the marks
	check(ns.providers.quests.events and table.concat(ns.providers.quests.events, ","):find("PLAYER_LEVEL_UP", 1, true),
		"a level gained rebuilds the log's marks")

	Q.GetNumQuestLogEntries, Q.GetInfo, Q.GetQuestObjectives, Q.ReadyForTurnIn = save.num, save.info, save.obj, save.ready
	Q.IsComplete, Q.IsQuestTrivial, Q.SetSelectedQuest, Q.GetSelectedQuest = save.isComplete, save.trivial, save.sel, save.getSel
	Q.SetAbandonQuest, Q.AbandonQuest, Q.GetLogIndexForQuestID, Q.GetTitleForQuestID = save.setAb, save.ab, save.idx, save.title
	_G.C_PlayerInfo, _G.C_Map, _G.GetQuestUiMapID, _G.UnitLevel, _G.GetTime = save.pi, save.map, save.uiMap, save.ul, save.gt
	_G.QuestMapQuestOptions_AbandonQuest, ns.Print, ns.Output = save.qmq, save.print, save.out
	ns.db.easyMode = save.easy; UI:EasyChanged()
	ns.providers.quests._dirty = true
end

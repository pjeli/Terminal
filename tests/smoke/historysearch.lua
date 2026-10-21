-- The history (0.63.6, the player: "a Ctrl+R history search like a real shell; a search of 'history' should show the
-- commands ran before"): Ctrl+R finds among the lines you ran (again: an older one; Enter puts it in the prompt and
-- searches it; Esc goes back), @history and "history" list them newest first with when each ran.
local T = ...
local ns, UI, check, key, FlushAll = T.ns, T.UI, T.check, T.key, T.FlushAll

io.write("[history: Ctrl+R, @history, \"history\"]\n")
do
	local save = { h = ns.db.history, at = ns.db.historyAt, easy = ns.db.easyMode, ctrl = _G.IsControlKeyDown }
	local now = time()
	ns.db.history = { "@npc is:repair sort:nearest", "thorium belt > mats", "linen cloth", ".mail" }
	ns.db.historyAt = { ["@npc is:repair sort:nearest"] = now - 30, ["thorium belt > mats"] = now - 600, ["linen cloth"] = now - 7200 }
	ns.providers.history._dirty = true
	local function Names(rows)
		local t = {}
		for _, e in ipairs(rows or UI.Results()) do t[#t + 1] = tostring(e.name) end
		return table.concat(t, " | ")
	end
	local function CtrlR()
		_G.IsControlKeyDown = function() return true end
		key("R")
		_G.IsControlKeyDown = save.ctrl
		FlushAll()
	end

	-- a line run: kept on top, with when it ran
	ns:RecordHistory("linen cloth")
	check(ns.db.history[1] == "linen cloth" and #ns.db.history == 4 and math.abs(ns:HistoryAt("linen cloth") - time()) < 2,
		"run again: on top, once, with when it ran")

	-- "history" in plain words: what you ran, newest first, each with when
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open("history"); FlushAll()
	local r = UI.Results()
	check(Names(r) == "linen cloth | @npc is:repair sort:nearest | thorium belt > mats | .mail",
		"\"history\": newest first: " .. Names(r))
	check(r[1].detail == ns.L["just now"] and r[3].detail == ns.L["%d min ago"]:format(10) and r[4].detail == nil,
		"each says when it ran (none kept for an old one): " .. tostring(r[3].detail))
	check(ns.History.Question("my history") and ns.History.Question("recent searches") and not ns.History.Question("history of linen"),
		"\"my history\", \"recent searches\"; not other lines")
	-- Enter on one: searched again, as if typed (Shift+Left back)
	UI.sel = 3
	UI:Activate(); FlushAll()
	check(T.query() == "thorium belt > mats" and UI:IsShown(), "Enter: the line searched again: " .. T.query())
	UI:Hide(); FlushAll()

	-- @history: the same list in Advanced, narrowed by words
	ns.db.easyMode = false; UI:EasyChanged()
	UI:Open("@history thorium"); FlushAll()
	check(Names() == "thorium belt > mats", "@history thorium: " .. Names())
	UI:Hide(); FlushAll()

	-- Ctrl+R: the prompt searches the history, what it said already being the search
	UI:Open("thor"); FlushAll()
	CtrlR()
	check(UI.histSearch and Names() == "thorium belt > mats", "Ctrl+R: what you typed, found in the history: " .. Names())
	local status = UI.status and UI.status:GetText() or ""
	check(status:find("History search (Ctrl+R)", 1, true), "the footer says so: " .. status)
	-- typed on: nothing in it is syntax (".ma" finds ".mail", not the commands)
	UI:SetQuery("", 0); FlushAll()
	check(Names() == "linen cloth | @npc is:repair sort:nearest | thorium belt > mats | .mail", "nothing typed: every line, newest first: " .. Names())
	T.typeText(".ma"); FlushAll()
	check(UI.mode == "search" and UI.Results()[1] and UI.Results()[1].name == ".mail", "\".ma\": a word to find, not a command: " .. Names())
	-- Ctrl+R again: the next (older) match
	UI:SetQuery("n", 1); FlushAll()
	local first = UI.Results()[UI.sel] and UI.Results()[UI.sel].name
	CtrlR()
	local second = UI.Results()[UI.sel] and UI.Results()[UI.sel].name
	check(UI.sel == 2 and first ~= second, "Ctrl+R again: an older match selected: " .. tostring(first) .. " -> " .. tostring(second))
	-- Enter: the line in the prompt, searched (out of the history search)
	key("ENTER"); FlushAll()
	check(not UI.histSearch and T.query() == second and UI:IsShown(), "Enter: the line in the prompt, searched: " .. T.query())

	-- Esc: back to what the prompt said
	UI:SetQuery("lin", 3); FlushAll()
	CtrlR()
	T.typeText("en"); FlushAll()
	key("ESCAPE"); FlushAll()
	check(not UI.histSearch and T.query() == "lin" and UI:IsShown(), "Esc: back to what you had typed, still open: " .. T.query())

	-- closed in it: what was typed before it is what's kept
	CtrlR()
	T.typeText("xyz"); FlushAll()
	UI:Hide(); FlushAll()
	check(not UI.histSearch and UI.closedText and UI.closedText.text == "lin", "closed in it: what you had typed is kept: "
		.. tostring(UI.closedText and UI.closedText.text))
	UI.closedText = nil

	-- a click on a line: as Enter
	UI:Open(""); FlushAll()
	CtrlR()
	UI:Activate(2); FlushAll()
	check(not UI.histSearch and T.query() == "@npc is:repair sort:nearest", "a click: as Enter: " .. T.query())
	UI:Hide(); FlushAll()

	-- .history clear forgets the times too
	ns:FindCommand("history").run("clear")
	check(#ns.db.history == 0 and next(ns.db.historyAt) == nil, ".history clear: the lines and their times")

	ns.db.history, ns.db.historyAt, ns.db.easyMode, _G.IsControlKeyDown = save.h, save.at, save.easy, save.ctrl
	UI:EasyChanged()
	ns.providers.history._dirty = true
end
